#import "TX500TimeSync.h"
#import <errno.h>
#import <fcntl.h>
#import <math.h>
#import <poll.h>
#import <sys/ioctl.h>
#import <termios.h>
#import <time.h>
#import <unistd.h>

// Recovered independently from both supplied TimeSync binaries.
// Set: TMhh:mm:ss;  -> 100 ms -> query: TM; -> reply: TMhh:mm:ss;
// See TIMESYNC-REVIEW.md for addresses, original behavior and deliberate changes.
@implementation TXTimeSyncResult
@end

TXTimeSyncOptions TXDefaultTimeSyncOptions(void) {
    return (TXTimeSyncOptions){ .responseTimeout = 2.0, .writeTimeout = 2.0,
        .settleDelay = 0.1, .commandDelay = 0.1 };
}

NSData *TXTimeSetCommand(NSDate *date, NSTimeZone *zone) {
    if (!date || !zone || !isfinite(date.timeIntervalSince1970)) return nil;
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = zone;
    NSDateComponents *parts = [calendar components:(NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond)
        fromDate:date];
    char command[12];
    int count = snprintf(command, sizeof(command), "TM%02ld:%02ld:%02ld;",
        (long)parts.hour, (long)parts.minute, (long)parts.second);
    return count == 11 ? [NSData dataWithBytes:command length:11] : nil;
}

NSInteger TXParseTimeReply(NSData *frame) {
    if (frame.length != 11) return -1;
    const uint8_t *b = frame.bytes;
    if (b[0] != 'T' || b[1] != 'M' || b[4] != ':' || b[7] != ':' || b[10] != ';') return -1;
    const unsigned positions[] = {2, 3, 5, 6, 8, 9};
    for (unsigned i = 0; i < 6; i++) if (b[positions[i]] < '0' || b[positions[i]] > '9') return -1;
    NSInteger h = (b[2] - '0') * 10 + b[3] - '0';
    NSInteger m = (b[5] - '0') * 10 + b[6] - '0';
    NSInteger s = (b[8] - '0') * 10 + b[9] - '0';
    return h < 24 && m < 60 && s < 60 ? h * 3600 + m * 60 + s : -1;
}

BOOL TXTimeReplyMatches(NSInteger sent, NSInteger received, double elapsed) {
    if (sent < 0 || sent >= 86400 || received < 0 || received >= 86400 ||
        !isfinite(elapsed) || elapsed < 0 || elapsed > 60) return NO;
    NSInteger expected = (sent + (NSInteger)floor(elapsed)) % 86400;
    NSInteger difference = labs(received - expected);
    return MIN(difference, 86400 - difference) <= 2;
}

static double Now(void) {
    struct timespec stamp;
    clock_gettime(CLOCK_MONOTONIC, &stamp);
    return stamp.tv_sec + stamp.tv_nsec / 1e9;
}

static void Pause(double seconds) {
    struct timespec remaining = {(time_t)seconds, (long)((seconds - (time_t)seconds) * 1e9)};
    while (nanosleep(&remaining, &remaining) < 0 && errno == EINTR) {}
}

static BOOL Fail(TXTimeSyncResult *result, NSString *message) {
    result.failure = [NSString stringWithFormat:@"%@: %@%@", result.phase, message,
        result.timeCommandSent ? @" The set-time command was sent, but synchronization is not confirmed." : @""];
    return NO;
}

static BOOL SystemFailure(TXTimeSyncResult *result, NSString *operation) {
    int error = errno;
    return Fail(result, [NSString stringWithFormat:@"%@ failed: %s", operation, strerror(error)]);
}

static BOOL Configure(int fd, TXTimeSyncResult *result) {
    struct termios settings;
    if (tcgetattr(fd, &settings) < 0) return SystemFailure(result, @"Reading serial settings");
    cfmakeraw(&settings);
    settings.c_iflag = 0;
    settings.c_oflag = 0;
    settings.c_lflag = 0;
    settings.c_cflag &= ~(CSIZE | PARENB | PARODD | CSTOPB | HUPCL |
        CRTSCTS | CDTR_IFLOW | CDSR_OFLOW | CCAR_OFLOW);
    settings.c_cflag |= CLOCAL | CREAD | CS8;
    settings.c_cc[VMIN] = 0;
    settings.c_cc[VTIME] = 0;
    if (cfsetispeed(&settings, B9600) < 0 || cfsetospeed(&settings, B9600) < 0 ||
        tcsetattr(fd, TCSANOW, &settings) < 0 || tcflush(fd, TCIOFLUSH) < 0)
        return SystemFailure(result, @"Configuring 9600 baud, 8N1, no flow control");
    if (tcgetattr(fd, &settings) < 0) return SystemFailure(result, @"Verifying serial settings");
    if (cfgetispeed(&settings) != B9600 || cfgetospeed(&settings) != B9600 ||
        (settings.c_cflag & CSIZE) != CS8 ||
        (settings.c_cflag & (PARENB | CSTOPB | CRTSCTS | CDTR_IFLOW | CDSR_OFLOW | CCAR_OFLOW)) ||
        (settings.c_iflag & (IXON | IXOFF | IXANY)))
        return Fail(result, @"The serial driver did not accept 9600 baud, 8N1 with no flow control.");
    return YES;
}

static BOOL Send(int fd, NSData *data, TXTimeSyncOptions options, TXTimeSyncResult *result) {
    const uint8_t *bytes = data.bytes;
    NSUInteger offset = 0;
    double deadline = Now() + options.writeTimeout;
    while (offset < data.length) {
        if (Now() >= deadline) return Fail(result, @"Timed out writing to the serial port.");
        ssize_t count = write(fd, bytes + offset, data.length - offset);
        if (count > 0) {
            offset += (NSUInteger)count;
            result.bytesSubmitted += (NSUInteger)count;
            // The first complete 11-byte command may reach the radio even if
            // the following output-queue check fails.
            if (result.bytesSubmitted >= 11) result.timeCommandSent = YES;
        } else if (count < 0 && errno == EINTR) continue;
        else if (count == 0 || errno == EAGAIN || errno == EWOULDBLOCK) Pause(0.001);
        else return SystemFailure(result, @"Serial write");
    }
    for (;;) {
        int pending = 0;
        if (Now() >= deadline) return Fail(result, @"The serial output queue did not drain.");
        if (ioctl(fd, TIOCOUTQ, &pending) < 0) {
            if (errno == EINTR) continue;
            return SystemFailure(result, @"Reading the serial output queue");
        }
        if (!pending) return YES;
        Pause(0.001);
    }
}

static NSData *ReadTime(int fd, TXTimeSyncOptions options, TXTimeSyncResult *result,
                       void (^log)(NSString *)) {
    NSMutableData *frame = [NSMutableData data];
    double deadline = Now() + options.responseTimeout;
    NSUInteger total = 0;
    while (Now() < deadline) {
        struct pollfd item = {.fd = fd, .events = POLLIN};
        int ready = poll(&item, 1, 10);
        if (ready < 0) {
            if (errno == EINTR) continue;
            SystemFailure(result, @"Waiting for the radio"); return nil;
        }
        if (item.revents & (POLLHUP | POLLERR | POLLNVAL)) {
            Fail(result, @"The serial connection was lost."); return nil;
        }
        if (!(item.revents & POLLIN)) continue;
        uint8_t bytes[64];
        ssize_t count = read(fd, bytes, sizeof(bytes));
        if (count < 0) {
            if (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) continue;
            SystemFailure(result, @"Reading the radio clock"); return nil;
        }
        for (ssize_t i = 0; i < count; i++) {
            if (++total > 1024) { Fail(result, @"Too much unrelated serial data. Close other CAT applications."); return nil; }
            if (!frame.length && (bytes[i] == '\r' || bytes[i] == '\n')) continue;
            [frame appendBytes:bytes + i length:1];
            if (frame.length > 128) { Fail(result, @"The radio response has no valid frame terminator."); return nil; }
            if (bytes[i] != ';') continue;
            NSString *text = [[NSString alloc] initWithData:frame encoding:NSASCIIStringEncoding];
            log([NSString stringWithFormat:@"RX %@", text ?: frame.description]);
            if (frame.length >= 2 && memcmp(frame.bytes, "TM", 2) == 0) {
                if (TXParseTimeReply(frame) >= 0) return frame;
                Fail(result, @"Malformed clock reply; expected TMhh:mm:ss; with a valid 24-hour time."); return nil;
            }
            if ([text isEqualToString:@"?;"]) { Fail(result, @"The radio rejected the clock command. Check firmware support for TimeSync."); return nil; }
            [frame setLength:0];
        }
    }
    Fail(result, @"No complete clock reply. Turn the radio on normally, use CAT at 9600 baud, and close other radio apps.");
    return nil;
}

TXTimeSyncResult *TXSynchronizeTime(NSString *port, NSTimeZone *zone, TXTimeSyncOptions options,
                                    NSDate *(^clock)(void), void (^log)(NSString *)) {
    TXTimeSyncResult *result = [TXTimeSyncResult new];
    result.phase = @"Input validation";
    if (!log) log = ^(NSString *message) {};
    double values[] = {options.responseTimeout, options.writeTimeout, options.settleDelay, options.commandDelay};
    for (unsigned i = 0; i < 4; i++) {
        if (!isfinite(values[i]) || values[i] < 0 || values[i] > 10 || (i < 2 && values[i] == 0)) {
            Fail(result, @"Invalid time synchronization timing options."); return result;
        }
    }
    if (!port.length || !zone) { Fail(result, @"Select a serial port and time zone."); return result; }
    result.phase = @"Opening serial port";
    log([NSString stringWithFormat:@"Opening %@ for time synchronization (%@).", port, zone.name]);
    int fd = open(port.fileSystemRepresentation, O_RDWR | O_NOCTTY | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) { SystemFailure(result, @"Opening the selected port (close other radio apps)"); return result; }
    NSData *command = nil;
    NSData *reply = nil;
    double sentAt = 0;
    if (ioctl(fd, TIOCEXCL) < 0) { SystemFailure(result, @"Obtaining exclusive serial access"); goto finish; }
    result.phase = @"Serial configuration";
    if (!Configure(fd, result)) goto finish;
    log(@"Serial settings verified: 9600 baud, 8N1, no flow control. Radio must be in normal operating mode.");
    Pause(options.settleDelay);
    if (tcflush(fd, TCIFLUSH) < 0) { SystemFailure(result, @"Clearing stale input"); goto finish; }
    result.phase = @"Setting radio clock";
    sentAt = Now();
    command = TXTimeSetCommand(clock ? clock() : NSDate.date, zone);
    if (!command) { Fail(result, @"Could not obtain a valid computer clock value."); goto finish; }
    result.requestedTime = [[[NSString alloc] initWithData:command encoding:NSASCIIStringEncoding] substringWithRange:NSMakeRange(2, 8)];
    if (!Send(fd, command, options, result)) goto finish;
    result.timeCommandSent = YES;
    log([NSString stringWithFormat:@"TX TM%@;", result.requestedTime]);
    Pause(options.commandDelay);
    result.phase = @"Reading radio clock";
    // A set-command echo/unsolicited reply must not count as read-back confirmation.
    if (tcflush(fd, TCIFLUSH) < 0) { SystemFailure(result, @"Clearing input before clock query"); goto finish; }
    if (!Send(fd, [@"TM;" dataUsingEncoding:NSASCIIStringEncoding], options, result)) goto finish;
    log(@"TX TM;");
    reply = ReadTime(fd, options, result, log);
    if (!reply) goto finish;
    result.radioTime = [[[NSString alloc] initWithData:reply encoding:NSASCIIStringEncoding] substringWithRange:NSMakeRange(2, 8)];
    result.phase = @"Verifying radio clock";
    if (!TXTimeReplyMatches(TXParseTimeReply(command), TXParseTimeReply(reply), Now() - sentAt)) {
        Fail(result, [NSString stringWithFormat:@"Radio returned %@ after setting %@; read-back is outside the 2-second tolerance.",
            result.radioTime, result.requestedTime]); goto finish;
    }
    result.success = YES;
    result.phase = @"Complete";
    log([NSString stringWithFormat:@"Radio clock verified: %@ (%@); read-back within 2 seconds of expected time.", result.radioTime, zone.name]);
finish:
    if (!result.success) log(result.failure ?: @"Time synchronization failed.");
    close(fd);
    return result;
}
