#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <util.h>
#import <poll.h>
#import <fcntl.h>
#import <termios.h>
#import <unistd.h>
#import <math.h>
#import "../Headers/TX500TimeSync.h"

static void Check(BOOL passed, NSString *message) {
    if (!passed) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static NSData *ASCII(NSString *text) { return [text dataUsingEncoding:NSASCIIStringEncoding]; }
static NSDate *FixedDate(void) {
    // 2026-09-18 12:34:56 UTC. Independent of the computer's current clock/zone.
    return [[[NSISO8601DateFormatter alloc] init] dateFromString:@"2026-09-18T12:34:56Z"];
}
static NSData *ReadExact(int fd, NSUInteger length, double timeout) {
    NSMutableData *data = [NSMutableData data];
    double deadline = NSProcessInfo.processInfo.systemUptime + timeout;
    while (data.length < length && NSProcessInfo.processInfo.systemUptime < deadline) {
        struct pollfd p = {.fd = fd, .events = POLLIN};
        if (poll(&p, 1, 10) > 0 && (p.revents & POLLIN)) {
            uint8_t bytes[32];
            ssize_t count = read(fd, bytes, MIN(sizeof(bytes), length - data.length));
            if (count > 0) [data appendBytes:bytes length:(NSUInteger)count];
        }
    }
    return data;
}
static void Reply(int fd, NSString *text, BOOL fragmented) {
    NSData *data = ASCII(text);
    for (NSUInteger offset = 0; offset < data.length;) {
        NSUInteger length = fragmented ? 1 : data.length;
        Check(write(fd, (const uint8_t *)data.bytes + offset, length) == (ssize_t)length, @"Emulator writes reply");
        offset += length;
        if (fragmented) usleep(5000);
    }
}
static void Scenario(NSString *name, NSString *reply, BOOL fragmented, BOOL disconnect,
                     BOOL echoOnly, BOOL success, NSString *phase) {
    int master, slave; char path[256];
    Check(openpty(&master, &slave, path, NULL, NULL) == 0, @"Create pseudo-terminal");
    TXTimeSyncOptions options = TXDefaultTimeSyncOptions();
    options.settleDelay = 0.01;
    options.responseTimeout = 0.35;
    options.writeTimeout = 0.3;
    __block BOOL settingsOK = NO, closed = NO, exactCommand = NO, exactQuery = NO, noExtra = NO;
    __block double queryDelay = 0;
    __block NSUInteger clockSamples = 0;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSData *command = ReadExact(master, 11, 1);
            double setAt = NSProcessInfo.processInfo.systemUptime;
            exactCommand = [command isEqual:ASCII(@"TM12:34:56;")];
            struct termios settings;
            settingsOK = tcgetattr(slave, &settings) == 0 &&
                cfgetispeed(&settings) == B9600 && cfgetospeed(&settings) == B9600 &&
                (settings.c_cflag & CSIZE) == CS8 &&
                !(settings.c_cflag & (PARENB | CSTOPB | CRTSCTS | CDTR_IFLOW | CDSR_OFLOW | CCAR_OFLOW)) &&
                !(settings.c_iflag & (IXON | IXOFF | IXANY)) && !(settings.c_lflag & (ICANON | ECHO));
            if (echoOnly) Reply(master, @"TM12:34:56;", NO);
            NSData *query = ReadExact(master, 3, 1);
            queryDelay = NSProcessInfo.processInfo.systemUptime - setAt;
            exactQuery = [query isEqual:ASCII(@"TM;")];
            if (disconnect) { close(master); closed = YES; }
            else {
                if (fragmented) usleep(120000);
                if (!echoOnly) Reply(master, reply, fragmented);
                noExtra = ReadExact(master, 1, 0.45).length == 0;
            }
            dispatch_semaphore_signal(done);
        }
    });
    TXTimeSyncResult *result = TXSynchronizeTime(@(path), [NSTimeZone timeZoneForSecondsFromGMT:0], options,
        ^NSDate * { clockSamples++; return FixedDate(); }, nil);
    Check(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) == 0, @"Emulator terminates");
    if (!closed) close(master);
    close(slave);
    Check(settingsOK, [name stringByAppendingString:@": verified 9600/8N1/no flow"]);
    Check(exactCommand && exactQuery, [name stringByAppendingString:@": exact 11-byte set then 3-byte query"]);
    Check(queryDelay >= 0.08, @"Preserves the official 100 ms inter-command delay");
    Check(clockSamples == 1, @"Samples clock once after opening port");
    Check(disconnect || noExtra, @"No retries, bootloader commands, or extra serial writes");
    Check(result.success == success && [result.phase isEqual:phase],
        [NSString stringWithFormat:@"%@: success=%d phase=%@ failure=%@", name, result.success, result.phase, result.failure]);
    Check(result.timeCommandSent && result.bytesSubmitted == 14, @"Records exact transmission and possible clock change");
    Check(success || result.failure.length > 0, @"Failure explains the result");
    printf("PASS: %s\n", name.UTF8String);
}

int main(void) {
    @autoreleasepool {
        NSDate *date = FixedDate();
        Check([TXTimeSetCommand(date, [NSTimeZone timeZoneForSecondsFromGMT:0]) isEqual:ASCII(@"TM12:34:56;")], @"UTC wire fixture");
        Check([TXTimeSetCommand(date, [NSTimeZone timeZoneForSecondsFromGMT:12600]) isEqual:ASCII(@"TM16:04:56;")], @"Half-hour zone");
        Check([TXTimeSetCommand(date, [NSTimeZone timeZoneForSecondsFromGMT:45900]) isEqual:ASCII(@"TM01:19:56;")], @"Quarter-hour offset and next-day rollover");
        Check([TXTimeSetCommand(date, [NSTimeZone timeZoneForSecondsFromGMT:-18000]) isEqual:ASCII(@"TM07:34:56;")], @"Negative offset");
        Check(TXTimeSetCommand(nil, NSTimeZone.localTimeZone) == nil, @"Missing clock is rejected");
        Check(TXTimeSetCommand(date, nil) == nil, @"Missing time zone is rejected");
        Check(TXParseTimeReply(ASCII(@"TM00:00:00;")) == 0, @"Midnight");
        Check(TXParseTimeReply(ASCII(@"TM23:59:59;")) == 86399, @"Last second of day");
        for (NSString *bad in @[@"", @"TM;", @"TM24:00:00;", @"TM12:60:00;", @"TM12:00:60;", @"TMab:cd:ef;",
            @"TM12-34-56;", @"XX12:34:56;", @"TM12:34:56", @"TM12:34:56;extra", @"TM1:34:56;"])
            Check(TXParseTimeReply(ASCII(bad)) == -1, [@"Reject malformed frame: " stringByAppendingString:bad]);
        Check(TXTimeReplyMatches(86399, 0, 1.1), @"Verification crosses midnight");
        Check(TXTimeReplyMatches(45296, 45298, 0.2), @"Two-second tolerance");
        Check(!TXTimeReplyMatches(45296, 45300, 0.2), @"Unchanged/wrong clock cannot succeed");
        Check(!TXTimeReplyMatches(0, 0, NAN), @"Nonfinite elapsed time rejected");
        printf("PASS: Clock formatting, zones, midnight, strict parsing and verification fixtures\n");

        Scenario(@"Exact clock read-back", @"TM12:34:56;", NO, NO, NO, YES, @"Complete");
        Scenario(@"Fragmented reply beyond original 100 ms window", @"TM12:34:56;", YES, NO, NO, YES, @"Complete");
        Scenario(@"Unrelated CAT frame and line endings", @"IF0000;\r\nTM12:34:56;", NO, NO, NO, YES, @"Complete");
        Scenario(@"Radio retains a wrong time", @"TM09:00:00;", NO, NO, NO, NO, @"Verifying radio clock");
        Scenario(@"Invalid clock fields", @"TM29:99:99;", NO, NO, NO, NO, @"Reading radio clock");
        Scenario(@"Query echo is not clock confirmation", @"TM;", NO, NO, NO, NO, @"Reading radio clock");
        Scenario(@"Radio rejects clock command", @"?;", NO, NO, NO, NO, @"Reading radio clock");
        Scenario(@"No radio response", @"", NO, NO, NO, NO, @"Reading radio clock");
        Scenario(@"Partial response times out", @"TM12:34", NO, NO, NO, NO, @"Reading radio clock");
        Scenario(@"Set echo alone does not confirm query", @"", NO, NO, YES, NO, @"Reading radio clock");
        Scenario(@"Cable disconnect", @"", NO, YES, NO, NO, @"Reading radio clock");
        Scenario(@"Unterminated oversized response", [@"X" stringByPaddingToLength:129 withString:@"X" startingAtIndex:0],
            NO, NO, NO, NO, @"Reading radio clock");
        TXTimeSyncResult *missing = TXSynchronizeTime(@"/does-not-exist", NSTimeZone.localTimeZone,
            TXDefaultTimeSyncOptions(), nil, nil);
        Check(!missing.success && !missing.timeCommandSent && missing.bytesSubmitted == 0, @"Missing port has no writes");
        for (unsigned i = 0; i < 4; i++) {
            TXTimeSyncOptions options = TXDefaultTimeSyncOptions();
            if (i == 0) options.responseTimeout = 0;
            if (i == 1) options.writeTimeout = NAN;
            if (i == 2) options.settleDelay = -1;
            if (i == 3) options.commandDelay = INFINITY;
            TXTimeSyncResult *invalid = TXSynchronizeTime(@"/does-not-exist", NSTimeZone.localTimeZone, options, nil, nil);
            Check([invalid.phase isEqual:@"Input validation"] && invalid.bytesSubmitted == 0, @"Invalid options fail before port access");
        }
        printf("PASS: Missing port and invalid timing options\nAll time synchronization checks passed. No physical radio was accessed.\n");
    }
    return 0;
}
