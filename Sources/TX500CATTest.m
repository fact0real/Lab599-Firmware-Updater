#import "TX500CATTest.h"
#import <math.h>

@implementation TXCATSummary
- (id)copyWithZone:(NSZone *)zone {
    TXCATSummary *copy = [TXCATSummary new];
    copy.checks = self.checks; copy.passed = self.passed; copy.failed = self.failed;
    copy.cancelled = self.cancelled; copy.connectionFailed = self.connectionFailed;
    copy.lastCode = self.lastCode; copy.responseMilliseconds = self.responseMilliseconds;
    copy.lastReply = self.lastReply; copy.message = self.message;
    return copy;
}
@end

TXCATOptions TXDefaultCATOptions(void) {
    return (TXCATOptions){.responseTimeout = 1, .cycleInterval = 0.1,
        .settleDelay = 0.1, .maximumChecks = 0};
}

TXCATCode TXClassifyCATReply(NSData *reply) {
    if (reply.length == 0) return TXCATNoReply;
    if (reply.length != 6) return TXCATWrongLength;
    const char *accepted[] = {"ID019;", "ID500;", "ID501;", "ID502;", "ID505;"};
    for (unsigned i = 0; i < 5; i++) if (memcmp(reply.bytes, accepted[i], 6) == 0) return TXCATOK;
    return TXCATUnexpectedID;
}

static NSString *DisplayBytes(NSData *data) {
    if (!data.length) return @"(none)";
    const uint8_t *bytes = data.bytes;
    NSMutableString *display = [NSMutableString string];
    for (NSUInteger i = 0; i < MIN(data.length, (NSUInteger)64); i++) {
        if (bytes[i] >= 32 && bytes[i] <= 126) [display appendFormat:@"%c", bytes[i]];
        else [display appendFormat:@"\\x%02X", bytes[i]];
    }
    if (data.length > 64) [display appendString:@"..."];
    return display;
}

static NSString *Message(TXCATCode code) {
    switch (code) {
        case TXCATOK: return @"CAT OK! Recognized reply received.";
        case TXCATPortError: return @"ERROR 001 — Serial port or connection error.";
        case TXCATNoReply: return @"ERROR 002 — No reply. Check normal radio mode, CAT at 9600 baud and the cable.";
        case TXCATWrongLength: return @"ERROR 003 — Incomplete or extra data; expected exactly 6 response bytes. Close other CAT apps.";
        case TXCATUnexpectedID: return @"ERROR 004 — Transceiver model ID not recognized. Check the returned bytes and radio CAT configuration.";
    }
    return @"Unknown CAT result.";
}

TXCATSummary *TXRunCATTest(NSString *path, TXCATOptions options, Lab599Cancellation *token,
                          void (^update)(TXCATSummary *), void (^log)(NSString *)) {
    TXCATSummary *result = [TXCATSummary new];
    if (!token) token = [Lab599Cancellation new];
    if (!update) update = ^(TXCATSummary *summary) {};
    if (!log) log = ^(NSString *message) {};
    if (!isfinite(options.responseTimeout) || options.responseTimeout <= 0 || options.responseTimeout > 10 ||
        !isfinite(options.cycleInterval) || options.cycleInterval <= 0 || options.cycleInterval > options.responseTimeout ||
        !isfinite(options.settleDelay) || options.settleDelay < 0 || options.settleDelay > 10) {
        result.connectionFailed = YES; result.lastCode = TXCATPortError;
        result.message = @"Invalid CAT test timing options."; update([result copy]); return result;
    }
    if (token.cancelled) { result.cancelled = YES; result.message = @"CAT test stopped."; return result; }
    NSError *error = nil;
    log([NSString stringWithFormat:@"CAT test: opening %@ at 9600 baud, 8N1, no flow control.", path]);
    Lab599SerialPort *port = [Lab599SerialPort openPath:path speed:B9600 error:&error];
    if (!port) {
        result.connectionFailed = YES; result.lastCode = TXCATPortError;
        result.message = [NSString stringWithFormat:@"%@ %@", Message(TXCATPortError), error.localizedDescription];
        log(result.message); update([result copy]); return result;
    }
    Lab599Pause(options.settleDelay, token);
    TXCATCode previousCode = (TXCATCode)-1;
    NSData *query = [@"ID;" dataUsingEncoding:NSASCIIStringEncoding];
    while (!token.cancelled && (!options.maximumChecks || result.checks < options.maximumChecks)) {
        error = nil;
        result.lastReply = @"(none)";
        result.responseMilliseconds = 0;
        double started = Lab599MonotonicTime();
        NSMutableData *received = [NSMutableData data];
        double completeAt = 0;
        if ([port discardInput:&error] && [port writeData:query timeout:1 cancellation:token error:&error]) {
            double deadline = started + options.responseTimeout;
            while (!token.cancelled && Lab599MonotonicTime() < deadline) {
                double now = Lab599MonotonicTime();
                // Keep the original 100 ms observation window but allow slow,
                // fragmented replies up to the longer bounded deadline.
                BOOL terminated = received.length && memchr(received.bytes, ';', received.length) != NULL;
                if (now - started >= options.cycleInterval && (received.length >= 6 || terminated)) break;
                NSData *chunk = [port readMaximum:1024 timeout:MIN(0.02, deadline - now) cancellation:token error:&error];
                if (!chunk) {
                    if (error.code == Lab599SerialTimeout) { error = nil; continue; }
                    break;
                }
                [received appendData:chunk];
                if (!completeAt && received.length >= 6) completeAt = Lab599MonotonicTime();
                if (received.length > 1024) break;
            }
        }
        if (token.cancelled || ([error.domain isEqualToString:Lab599SerialErrorDomain] && error.code == Lab599SerialCancelled)) break;
        result.checks++;
        result.lastReply = DisplayBytes(received);
        result.lastCode = error ? TXCATPortError : TXClassifyCATReply(received);
        result.responseMilliseconds = completeAt ? (completeAt - started) * 1000 : 0;
        result.message = error ? [NSString stringWithFormat:@"%@ %@", Message(TXCATPortError), error.localizedDescription] : Message(result.lastCode);
        if (result.lastCode == TXCATOK) result.passed++; else result.failed++;
        if (result.checks == 1 || result.lastCode != previousCode || result.checks % 50 == 0 || error) {
            log([NSString stringWithFormat:@"CAT check %lu: TX ID; | RX %@ | %@ (passed %lu, failed %lu)",
                (unsigned long)result.checks, result.lastReply, result.message, (unsigned long)result.passed, (unsigned long)result.failed]);
        }
        previousCode = result.lastCode;
        update([result copy]);
        if (error) { result.connectionFailed = YES; break; }
        // Enforces pacing even when malformed/oversized data arrives immediately.
        Lab599Pause(MAX(0, options.cycleInterval - (Lab599MonotonicTime() - started)), token);
    }
    [port close];
    result.cancelled = token.cancelled;
    if (result.cancelled && !result.checks) result.message = @"CAT test stopped before a check completed.";
    log([NSString stringWithFormat:@"CAT test %@; %lu completed, %lu passed, %lu failed. Serial port closed.",
        result.cancelled ? @"stopped" : @"finished", (unsigned long)result.checks,
        (unsigned long)result.passed, (unsigned long)result.failed]);
    return result;
}
