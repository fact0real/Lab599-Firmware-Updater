#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <util.h>
#import <poll.h>
#import <fcntl.h>
#import <sys/ioctl.h>
#import <termios.h>
#import <unistd.h>
#import "../TX500Transfer.h"

// A radio-side emulator using a real macOS pseudo-terminal. It implements the
// two-ACK protocol recovered from the official binaries, not per-byte ACKs.
// It never opens a USB serial device and cannot transmit to a real radio.

static void Check(BOOL passed, NSString *message) {
    if (!passed) {
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
        exit(1);
    }
}

static BOOL ReadUntil(int fd, NSMutableData *data, NSUInteger length, double timeout) {
    double deadline = NSProcessInfo.processInfo.systemUptime + timeout;
    while (data.length < length && NSProcessInfo.processInfo.systemUptime < deadline) {
        struct pollfd item = { .fd = fd, .events = POLLIN };
        if (poll(&item, 1, 10) > 0 && (item.revents & POLLIN)) {
            uint8_t buffer[4096];
            ssize_t count = read(fd, buffer, MIN(sizeof(buffer), length - data.length));
            if (count > 0) {
                [data appendBytes:buffer length:(NSUInteger)count];
                // This is an inactivity deadline. A full firmware can take
                // several minutes with byte-wise output-queue pacing.
                deadline = NSProcessInfo.processInfo.systemUptime + timeout;
            }
        }
    }
    return data.length == length;
}

static void Respond(int fd, NSString *text, BOOL fragmented) {
    NSData *bytes = [text dataUsingEncoding:NSASCIIStringEncoding];
    if (fragmented && bytes.length == 2) {
        Check(write(fd, bytes.bytes, 1) == 1, @"Emulator first response byte");
        usleep(20000);
        Check(write(fd, (const uint8_t *)bytes.bytes + 1, 1) == 1, @"Emulator second response byte");
    } else if (bytes.length) {
        Check(write(fd, bytes.bytes, bytes.length) == (ssize_t)bytes.length, @"Emulator response");
    }
}

static void RunScenario(NSString *name, NSData *firmware, NSString *headerReply, NSString *finalReply,
                        BOOL fragmented, BOOL disconnect, BOOL backpressure, BOOL expectedSuccess,
                        NSString *expectedPhase) {
    int master, slave;
    char path[256];
    Check(openpty(&master, &slave, path, NULL, NULL) == 0, @"Create test pseudo-terminal");
    __block NSMutableData *captured = [NSMutableData data];
    __block BOOL prematurePayload = NO;
    __block BOOL correctSettings = NO;
    __block BOOL peerClosed = NO;
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    TXTransferOptions options = TXDefaultTransferOptions();
    options.acknowledgementTimeout = 0.2;
    options.writeTimeout = backpressure ? 0.15 : 1.0;
    options.settleDelay = 0.01;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            if (ReadUntil(master, captured, 16, 3.0)) {
                struct termios settings;
                correctSettings = tcgetattr(slave, &settings) == 0 &&
                    cfgetispeed(&settings) == B57600 && cfgetospeed(&settings) == B57600 &&
                    (settings.c_cflag & CSIZE) == CS8 &&
                    !(settings.c_cflag & (PARENB | CSTOPB | CRTSCTS | CDTR_IFLOW | CDSR_OFLOW | CCAR_OFLOW)) &&
                    !(settings.c_iflag & (IXON | IXOFF | IXANY)) && !(settings.c_lflag & (ICANON | ECHO));
                struct pollfd item = { .fd = master, .events = POLLIN };
                prematurePayload = poll(&item, 1, 25) > 0 && (item.revents & POLLIN);
                if (disconnect) {
                    close(master);
                    peerClosed = YES;
                } else {
                    Respond(master, headerReply, fragmented);
                    if ([headerReply isEqualToString:@"OK"]) {
                        if (backpressure) {
                            usleep(500000);
                        } else if (ReadUntil(master, captured, firmware.length, 15.0)) {
                            // Deliberately no acknowledgements inside ReadUntil.
                            usleep(30000);
                            Respond(master, finalReply, fragmented);
                        }
                    } else {
                        // Observe whether a rejected header incorrectly starts a payload.
                        ReadUntil(master, captured, firmware.length, 0.3);
                    }
                }
            }
            dispatch_semaphore_signal(finished);
        }
    });

    __block NSUInteger lastProgress = 0;
    NSMutableArray *messages = [NSMutableArray array];
    TXTransferResult *result = TXFlashFirmware(firmware, @(path), options,
        ^(NSUInteger sent, NSUInteger total) {
            Check(sent >= lastProgress && sent <= total, @"Progress is monotonic and bounded");
            lastProgress = sent;
        }, ^(NSString *message) { [messages addObject:message]; });
    Check(dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC)) == 0,
        @"Emulator terminates");
    if (!peerClosed) close(master);
    close(slave);

    Check(correctSettings, [name stringByAppendingString:@": 57600/8N1/no flow control"]);
    Check(!prematurePayload, [name stringByAppendingString:@": no payload before header OK"]);
    Check(captured.length >= 16 && memcmp(captured.bytes, firmware.bytes, 16) == 0,
        [name stringByAppendingString:@": exact header"]);
    Check(result.success == expectedSuccess,
        [NSString stringWithFormat:@"%@: success=%d; %@", name, result.success, result.failure]);
    Check([result.phase isEqualToString:expectedPhase],
        [NSString stringWithFormat:@"%@: phase %@, expected %@", name, result.phase, expectedPhase]);
    if (![headerReply isEqualToString:@"OK"] || disconnect) {
        Check(result.bytesSubmitted == 16 && captured.length == 16 && !result.headerAccepted,
            @"No payload after missing/rejected header or header disconnect");
    } else if (!backpressure) {
        Check([captured isEqualToData:firmware], [name stringByAppendingString:@": entire file matches byte-for-byte"]);
        Check(result.bytesSubmitted == firmware.length && result.headerAccepted, @"Exact submitted count");
    }
    Check(result.finalAcknowledged == expectedSuccess, @"Success requires the final acknowledgement");
    if (!expectedSuccess) Check(result.failure.length > 0, @"Failure has an actionable diagnostic");
    printf("PASS: %s (submitted=%lu, captured=%lu, phase=%s)\n", name.UTF8String,
        (unsigned long)result.bytesSubmitted, (unsigned long)captured.length, result.phase.UTF8String);
}

static NSData *Fixture(NSUInteger length) {
    NSMutableData *data = [NSMutableData dataWithLength:length];
    uint8_t *bytes = data.mutableBytes;
    for (NSUInteger index = 0; index < length; index++) bytes[index] = (uint8_t)(index * 79);
    if (length >= 4) memcpy(bytes, "BL20", 4);
    return data;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        Check(argc == 2, @"Supply the local firmware path for a simulated transfer");
        NSData *real = [NSData dataWithContentsOfFile:@(argv[1])];
        Check(real.length == 246384, @"Expected full-sized local firmware");
        Check([TXFirmwareSHA256(real) isEqualToString:@"2162fed7d27987507c8b412f3d38478c0a670a906a0c747578d7c975ad5a04ea"],
            @"Firmware matches the downloaded reference hash");

        RunScenario(@"Complete real firmware with only two OK replies", real, @"OK", @"OK", NO, NO, NO, YES, @"Complete");
        RunScenario(@"Fragmented header and final OK", Fixture(513), @"OK", @"OK", YES, NO, NO, YES, @"Complete");
        RunScenario(@"Smallest non-empty payload", Fixture(17), @"OK", @"OK", NO, NO, NO, YES, @"Complete");
        RunScenario(@"Header timeout", Fixture(64), @"", @"OK", NO, NO, NO, NO, @"Header acknowledgement");
        RunScenario(@"Header rejection", Fixture(64), @"NO", @"OK", NO, NO, NO, NO, @"Header acknowledgement");
        RunScenario(@"Incomplete header reply", Fixture(64), @"O", @"OK", NO, NO, NO, NO, @"Header acknowledgement");
        RunScenario(@"Extra header bytes rejected", Fixture(64), @"OKX", @"OK", NO, NO, NO, NO, @"Header acknowledgement");
        RunScenario(@"Final timeout is not success", Fixture(2048), @"OK", @"", NO, NO, NO, NO, @"Final acknowledgement");
        RunScenario(@"Final rejection is not success", Fixture(2048), @"OK", @"NO", NO, NO, NO, NO, @"Final acknowledgement");
        RunScenario(@"Cable loss during header acknowledgement", Fixture(64), @"OK", @"OK", NO, YES, NO, NO, @"Header acknowledgement");
        RunScenario(@"Output backpressure is bounded", Fixture(1024 * 1024), @"OK", @"OK", NO, NO, YES, NO, @"Payload transmission");

        for (NSData *bad in @[[NSData data], Fixture(16), [@"This is not a firmware container" dataUsingEncoding:NSUTF8StringEncoding]]) {
            TXTransferResult *result = TXFlashFirmware(bad, @"/does-not-exist", TXDefaultTransferOptions(),
                ^(NSUInteger a, NSUInteger b) {}, ^(NSString *message) {});
            Check(!result.success && result.bytesSubmitted == 0 && [result.phase isEqualToString:@"File validation"],
                @"Invalid firmware is rejected before opening any port");
        }
        printf("PASS: Invalid firmware rejected before serial access (three cases)\n");
        TXTransferResult *missing = TXFlashFirmware(Fixture(64), @"/does-not-exist", TXDefaultTransferOptions(),
            ^(NSUInteger a, NSUInteger b) {}, ^(NSString *message) {});
        Check(!missing.success && missing.bytesSubmitted == 0 && [missing.phase isEqualToString:@"Opening serial port"],
            @"Missing port has no write side effects");
        printf("PASS: Missing port fails before transmission\n");
        printf("All 15 transfer checks passed. No physical radio was accessed.\n");
    }
    return 0;
}
