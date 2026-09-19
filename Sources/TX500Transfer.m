#import "TX500Transfer.h"
#import <CommonCrypto/CommonDigest.h>
#import <errno.h>
#import <fcntl.h>
#import <poll.h>
#import <sys/ioctl.h>
#import <termios.h>
#import <time.h>
#import <unistd.h>

// Verified against the supplied Linux 1.0.1 and Windows x64 1.0.2 binaries.
// 57600 baud, 8N1, no flow control:
//   send file[0:16] -> receive "OK" -> send file[16:end] -> receive "OK".
// The Linux payload loop checks TIOCOUTQ (the host output queue), NOT RX.
// No payload byte is individually acknowledged. See PROTOCOL-REVIEW.md.

@implementation TXTransferResult
@end

TXTransferOptions TXDefaultTransferOptions(void) {
    return (TXTransferOptions){ .acknowledgementTimeout = 5.0,
        .writeTimeout = 10.0, .settleDelay = 0.1 };
}

NSString *TXFirmwareValidationError(NSData *firmware) {
    if (firmware.length <= 16) return @"The firmware must contain a 16-byte header and a non-empty payload.";
    // BL20 is the container signature of the supplied Discovery firmware.
    // This is a format check, not an authenticity or radio-model check.
    if (memcmp(firmware.bytes, "BL20", 4) != 0)
        return @"Unsupported firmware header. Select an official BL20-format .fw file for your radio.";
    return nil;
}

NSString *TXFirmwareSHA256(NSData *firmware) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    const uint8_t *bytes = firmware.bytes;
    for (NSUInteger offset = 0; offset < firmware.length;) {
        CC_LONG size = (CC_LONG)MIN(firmware.length - offset, (NSUInteger)UINT32_MAX);
        CC_SHA256_Update(&context, bytes + offset, size);
        offset += size;
    }
    CC_SHA256_Final(digest, &context);
    NSMutableString *hash = [NSMutableString string];
    for (NSUInteger index = 0; index < sizeof(digest); index++) [hash appendFormat:@"%02x", digest[index]];
    return hash;
}

static double MonotonicTime(void) {
    struct timespec stamp;
    clock_gettime(CLOCK_MONOTONIC, &stamp);
    return stamp.tv_sec + stamp.tv_nsec / 1e9;
}

static void PauseFor(double seconds) {
    if (seconds <= 0) return;
    struct timespec remaining = { (time_t)seconds, (long)((seconds - (time_t)seconds) * 1e9) };
    while (nanosleep(&remaining, &remaining) < 0 && errno == EINTR) {}
}

static BOOL Fail(TXTransferResult *result, NSString *message) {
    result.failure = [NSString stringWithFormat:@"%@: %@ (file bytes submitted: %lu)",
        result.phase, message, (unsigned long)result.bytesSubmitted];
    return NO;
}

static BOOL SystemFailure(TXTransferResult *result, NSString *operation) {
    int error = errno;
    return Fail(result, [NSString stringWithFormat:@"%@ failed: %s", operation, strerror(error)]);
}

static BOOL ConfigurePort(int fd, TXTransferResult *result) {
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
    if (cfsetispeed(&settings, B57600) < 0 || cfsetospeed(&settings, B57600) < 0 ||
        tcsetattr(fd, TCSANOW, &settings) < 0 || tcflush(fd, TCIOFLUSH) < 0)
        return SystemFailure(result, @"Configuring 57600 baud, 8N1, no flow control");
    struct termios actual;
    if (tcgetattr(fd, &actual) < 0) return SystemFailure(result, @"Checking serial settings");
    if (cfgetispeed(&actual) != B57600 || cfgetospeed(&actual) != B57600 ||
        (actual.c_cflag & CSIZE) != CS8 ||
        (actual.c_cflag & (PARENB | CSTOPB | CRTSCTS | CDTR_IFLOW | CDSR_OFLOW | CCAR_OFLOW)) ||
        (actual.c_iflag & (IXON | IXOFF | IXANY)) || (actual.c_lflag & (ICANON | ECHO)))
        return Fail(result, @"The driver did not retain the required serial settings.");
    return YES;
}

static BOOL WriteBytes(int fd, const uint8_t *bytes, size_t length,
                       TXTransferOptions options, TXTransferResult *result) {
    size_t offset = 0;
    double deadline = MonotonicTime() + options.writeTimeout;
    while (offset < length) {
        if (MonotonicTime() >= deadline) return Fail(result, @"Timed out writing to the serial port.");
        ssize_t count = write(fd, bytes + offset, length - offset);
        if (count > 0) {
            offset += (size_t)count;
            result.bytesSubmitted += (NSUInteger)count;
        } else if (count < 0 && errno == EINTR) {
            continue;
        } else if (count == 0 || (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))) {
            PauseFor(0.001);
        } else {
            return SystemFailure(result, @"Serial write");
        }
    }
    return YES;
}

static BOOL WaitForOutputQueue(int fd, TXTransferOptions options, TXTransferResult *result) {
    double deadline = MonotonicTime() + options.writeTimeout;
    for (;;) {
        if (MonotonicTime() >= deadline) return Fail(result, @"The serial output queue did not drain.");
        int pending = 0;
        if (ioctl(fd, TIOCOUTQ, &pending) < 0) {
            if (errno == EINTR) continue;
            return SystemFailure(result, @"Reading the serial output queue");
        }
        if (pending == 0) return YES;
        PauseFor(0.001);
    }
}

static NSString *HexBytes(const uint8_t *bytes, size_t count) {
    if (count == 0) return @"none";
    NSMutableArray *parts = [NSMutableArray array];
    for (size_t index = 0; index < count; index++) [parts addObject:[NSString stringWithFormat:@"%02X", bytes[index]]];
    return [parts componentsJoinedByString:@" "];
}

static BOOL WaitForOK(int fd, TXTransferOptions options, TXTransferResult *result,
                      void (^log)(NSString *)) {
    double deadline = MonotonicTime() + options.acknowledgementTimeout;
    uint8_t reply[16];
    size_t received = 0;
    while (MonotonicTime() < deadline) {
        struct pollfd item = { .fd = fd, .events = POLLIN };
        int ready = poll(&item, 1, 10);
        if (ready < 0) {
            if (errno == EINTR) continue;
            return SystemFailure(result, @"Waiting for the radio");
        }
        if (item.revents & (POLLHUP | POLLERR | POLLNVAL))
            return Fail(result, @"The serial connection was lost while waiting for the radio.");
        if (!(item.revents & POLLIN)) continue;
        ssize_t count = read(fd, reply + received, sizeof(reply) - received);
        if (count < 0) {
            if (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) continue;
            return SystemFailure(result, @"Reading the radio response");
        }
        if (count == 0) continue;
        received += (size_t)count;
        if (reply[0] != 'O' || (received >= 2 && reply[1] != 'K') || received > 2) {
            log([NSString stringWithFormat:@"RX unexpected bytes: %@", HexBytes(reply, received)]);
            return Fail(result, @"Unexpected radio response; expected exactly the two bytes 4F 4B (OK).");
        }
        if (received == 2) {
            log(@"RX 4F 4B (OK)");
            return YES;
        }
    }
    return Fail(result, [NSString stringWithFormat:@"No complete OK within %.1f seconds; received: %@.",
        options.acknowledgementTimeout, HexBytes(reply, received)]);
}

TXTransferResult *TXFlashFirmware(NSData *firmware, NSString *port, TXTransferOptions options,
    void (^progress)(NSUInteger, NSUInteger), void (^log)(NSString *)) {
    TXTransferResult *result = [TXTransferResult new];
    result.phase = @"File validation";
    NSString *validation = TXFirmwareValidationError(firmware);
    if (validation) { Fail(result, validation); return result; }
    if (options.acknowledgementTimeout <= 0 || options.writeTimeout <= 0 || options.settleDelay < 0) {
        Fail(result, @"Invalid transfer timing options.");
        return result;
    }
    log([NSString stringWithFormat:@"File size: %lu bytes; SHA-256: %@",
        (unsigned long)firmware.length, TXFirmwareSHA256(firmware)]);
    log([NSString stringWithFormat:@"Opening %@", port]);
    result.phase = @"Opening serial port";
    int fd = open(port.fileSystemRepresentation, O_RDWR | O_NOCTTY | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) { SystemFailure(result, @"Opening the selected port (close other radio apps)"); return result; }

    // TIOCEXCL prevents new competing opens; it cannot evict already-open clients.
    if (ioctl(fd, TIOCEXCL) < 0) { SystemFailure(result, @"Obtaining exclusive serial access"); goto finish; }
    result.phase = @"Serial configuration";
    if (!ConfigurePort(fd, result)) goto finish;
    log(@"Serial settings verified: 57600 baud, 8N1, no hardware/software flow control.");
    PauseFor(options.settleDelay);
    if (tcflush(fd, TCIFLUSH) < 0) { SystemFailure(result, @"Clearing stale input before the header"); goto finish; }

    const uint8_t *bytes = firmware.bytes;
    result.phase = @"Header transmission";
    log(@"Sending the original 16-byte file header.");
    if (!WriteBytes(fd, bytes, 16, options, result) || !WaitForOutputQueue(fd, options, result)) goto finish;
    result.phase = @"Header acknowledgement";
    if (!WaitForOK(fd, options, result, log)) goto finish;
    result.headerAccepted = YES;

    result.phase = @"Payload transmission";
    log(@"Header accepted. Sending the remaining file; no per-byte acknowledgements are expected.");
    double lastProgress = MonotonicTime();
    progress(result.bytesSubmitted, firmware.length);
    // Preserve the Linux updater's byte-write/output-queue pacing. The queue
    // check is local to the host; it does not read or wait for any radio bytes.
    for (NSUInteger offset = 16; offset < firmware.length; offset++) {
        if (!WriteBytes(fd, bytes + offset, 1, options, result) || !WaitForOutputQueue(fd, options, result)) goto finish;
        if (MonotonicTime() - lastProgress >= 0.2 || offset + 1 == firmware.length) {
            progress(result.bytesSubmitted, firmware.length);
            lastProgress = MonotonicTime();
        }
    }
    result.phase = @"Final acknowledgement";
    log(@"All file bytes sent and host output queue drained. Waiting for the radio's final OK.");
    if (!WaitForOK(fd, options, result, log)) goto finish;
    result.finalAcknowledged = YES;
    result.success = YES;
    result.phase = @"Complete";
    log(@"The radio acknowledged the complete firmware. Transfer successful.");

finish:
    if (!result.success) log(result.failure ?: @"Transfer failed.");
    // No automatic re-send, firmware transformation, or boot/reset command.
    close(fd);
    return result;
}
