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

#pragma mark - Radio State & Interactive CAT Support

@implementation TXRadioState
- (instancetype)init {
    if ((self = [super init])) {
        _frequencyHz = 14074000;
        _frequencyDisplay = @"14.074.000 MHz";
        _operatingMode = @"USB";
        _modeCode = 2;
        _rfPowerWatts = 10.0;
        _filterNumber = 1;
        _preampOn = NO;
        _attenuatorOn = NO;
        _voltage = 13.8;
        _sMeterDots = 12;
        _modelID = @"Lab599 TX-500 (ID019)";
        _isTransmitting = NO;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    TXRadioState *c = [[[self class] allocWithZone:zone] init];
    c.frequencyHz = self.frequencyHz;
    c.frequencyDisplay = [self.frequencyDisplay copy];
    c.operatingMode = [self.operatingMode copy];
    c.modeCode = self.modeCode;
    c.rfPowerWatts = self.rfPowerWatts;
    c.filterNumber = self.filterNumber;
    c.preampOn = self.preampOn;
    c.attenuatorOn = self.attenuatorOn;
    c.voltage = self.voltage;
    c.sMeterDots = self.sMeterDots;
    c.modelID = [self.modelID copy];
    c.isTransmitting = self.isTransmitting;
    c.rawIFReply = [self.rawIFReply copy];
    c.rawFAReply = [self.rawFAReply copy];
    c.rawMDReply = [self.rawMDReply copy];
    c.rawPCReply = [self.rawPCReply copy];
    return c;
}
@end

static NSString *FormatFrequency(uint64_t hz) {
    uint64_t m = hz / 1000000;
    uint64_t k = (hz % 1000000) / 1000;
    uint64_t h = hz % 1000;
    return [NSString stringWithFormat:@"%llu.%03llu.%03llu MHz", m, k, h];
}

static NSString *ModeNameFromCode(NSInteger code) {
    switch (code) {
        case 1: return @"LSB";
        case 2: return @"USB";
        case 3: return @"CW";
        case 4: return @"FM";
        case 5: return @"AM";
        case 6: return @"DIG";
        case 7: return @"CWR";
        default: return @"USB";
    }
}

static NSString *SendOverPort(Lab599SerialPort *port, NSString *cmd, NSTimeInterval timeout, double *roundtripMs, NSError **error) {
    if (!port) return nil;
    NSMutableString *s = [cmd mutableCopy];
    if (![s hasSuffix:@";"]) [s appendString:@";"];
    [port discardInput:nil];
    NSData *data = [s dataUsingEncoding:NSASCIIStringEncoding];
    double started = Lab599MonotonicTime();
    Lab599Cancellation *token = [Lab599Cancellation new];
    if (![port writeData:data timeout:timeout cancellation:token error:error]) return nil;

    NSMutableData *resp = [NSMutableData data];
    double deadline = started + timeout;
    double completeAt = 0;
    while (Lab599MonotonicTime() < deadline) {
        NSData *chunk = [port readMaximum:256 timeout:MIN(0.04, deadline - Lab599MonotonicTime()) cancellation:token error:error];
        if (chunk.length > 0) {
            [resp appendData:chunk];
            NSData *semi = [@";" dataUsingEncoding:NSASCIIStringEncoding];
            NSRange r = [resp rangeOfData:semi options:0 range:NSMakeRange(0, resp.length)];
            if (r.location != NSNotFound) {
                completeAt = Lab599MonotonicTime();
                break;
            }
        } else if (error && *error) {
            break;
        }
    }
    if (roundtripMs) {
        *roundtripMs = completeAt > started ? (completeAt - started) * 1000.0 : (Lab599MonotonicTime() - started) * 1000.0;
    }
    if (resp.length > 0) {
        return [[NSString alloc] initWithData:resp encoding:NSASCIIStringEncoding];
    }
    return nil;
}

NSString *TXExecuteCATCommand(NSString *path, NSString *command,
    NSTimeInterval timeout, double *roundtripMs, NSError **error) {
    if (!path.length || !command.length) {
        if (error) *error = [NSError errorWithDomain:@"TXCAT" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid serial port or command."}];
        return nil;
    }
    Lab599SerialPort *port = [Lab599SerialPort openPath:path speed:B9600 error:error];
    if (!port) return nil;

    NSString *resp = SendOverPort(port, command, timeout > 0 ? timeout : 0.5, roundtripMs, error);
    [port close];
    return resp;
}

static double ParseVoltageReply(NSString *reply) {
    if (!reply.length) return 0.0;
    NSString *clean = [[reply componentsSeparatedByCharactersInSet:
                        [NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsJoinedByString:@""];
    NSRange prefix = [clean rangeOfString:@"VL"];
    if (prefix.location == NSNotFound) return 0.0;
    NSUInteger valueStart = NSMaxRange(prefix);
    NSRange suffix = [clean rangeOfString:@";" options:0
                                    range:NSMakeRange(valueStart, clean.length - valueStart)];
    if (suffix.location == NSNotFound || suffix.location == valueStart) return 0.0;
    NSString *field = [clean substringWithRange:NSMakeRange(valueStart, suffix.location - valueStart)];
    if ([field containsString:@"."]) return field.doubleValue;
    NSInteger raw = field.integerValue;
    double candidates[] = { raw / 10.0, raw / 100.0, raw / 1000.0 };
    for (NSUInteger i = 0; i < sizeof(candidates) / sizeof(candidates[0]); i++) {
        if (candidates[i] >= 7.0 && candidates[i] <= 20.0) return candidates[i];
    }
    return 0.0;
}

TXRadioState *TXReadRadioState(NSString *path, NSTimeInterval timeout, NSError **error) {
    if (!path.length) {
        if (error) *error = [NSError errorWithDomain:@"TXCAT" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Missing serial port path."}];
        return nil;
    }
    Lab599SerialPort *port = [Lab599SerialPort openPath:path speed:B9600 error:error];
    if (!port) return nil;

    TXRadioState *state = [TXRadioState new];
    NSTimeInterval cmdTimeout = timeout > 0 ? timeout : 0.25;

    // 1. Model ID (ID;)
    NSString *idReply = SendOverPort(port, @"ID;", cmdTimeout, NULL, nil);
    if (idReply) {
        if ([idReply containsString:@"ID019"]) state.modelID = @"Lab599 TX-500 Discovery (ID019)";
        else if ([idReply containsString:@"ID500"]) state.modelID = @"Lab599 TX-500 Discovery (ID500)";
        else if ([idReply containsString:@"ID501"]) state.modelID = @"Lab599 TX-500MP (ID501)";
        else if ([idReply containsString:@"ID502"]) state.modelID = @"Lab599 TX-500PRO (ID502)";
        else if ([idReply containsString:@"ID505"]) state.modelID = @"Lab599 TX-500PRO ALTAI (ID505)";
        else state.modelID = idReply;
    }

    // 2. Comprehensive Status (IF;)
    NSString *ifReply = SendOverPort(port, @"IF;", cmdTimeout, NULL, nil);
    if (ifReply && [ifReply hasPrefix:@"IF"] && ifReply.length >= 28) {
        state.rawIFReply = ifReply;
        NSString *clean = [ifReply stringByReplacingOccurrencesOfString:@";" withString:@""];
        if (clean.length >= 13) {
            NSString *freqStr = [clean substringWithRange:NSMakeRange(2, 11)];
            uint64_t f = (uint64_t)[freqStr longLongValue];
            if (f > 0) {
                state.frequencyHz = f;
                state.frequencyDisplay = FormatFrequency(f);
            }
        }
        if (clean.length > 28) {
            state.isTransmitting = ([clean characterAtIndex:28] == '1');
        }
        if (clean.length > 29) {
            int m = [clean characterAtIndex:29] - '0';
            state.modeCode = m;
            state.operatingMode = ModeNameFromCode(m);
        }
    }

    // 3. Precise VFO-A Frequency (FA;)
    NSString *faReply = SendOverPort(port, @"FA;", cmdTimeout, NULL, nil);
    if (faReply && [faReply hasPrefix:@"FA"] && faReply.length >= 13) {
        state.rawFAReply = faReply;
        NSString *digits = [faReply substringWithRange:NSMakeRange(2, 11)];
        uint64_t f = (uint64_t)[digits longLongValue];
        if (f > 0) {
            state.frequencyHz = f;
            state.frequencyDisplay = FormatFrequency(f);
        }
    }

    // 4. Operating Mode (MD;)
    NSString *mdReply = SendOverPort(port, @"MD;", cmdTimeout, NULL, nil);
    if (mdReply && [mdReply hasPrefix:@"MD"] && mdReply.length >= 3) {
        state.rawMDReply = mdReply;
        int m = [[mdReply substringWithRange:NSMakeRange(2, 1)] intValue];
        if (m > 0) {
            state.modeCode = m;
            state.operatingMode = ModeNameFromCode(m);
        }
    }

    // 5. RF Output Power (PC;)
    NSString *pcReply = SendOverPort(port, @"PC;", cmdTimeout, NULL, nil);
    if (pcReply && [pcReply hasPrefix:@"PC"] && pcReply.length >= 5) {
        state.rawPCReply = pcReply;
        int p = [[pcReply substringWithRange:NSMakeRange(2, 3)] intValue];
        if (p > 0) state.rfPowerWatts = (double)p;
    }

    // 6. Preamp (PA;)
    NSString *paReply = SendOverPort(port, @"PA;", cmdTimeout, NULL, nil);
    if (paReply && [paReply hasPrefix:@"PA"] && paReply.length >= 3) {
        state.preampOn = ([paReply characterAtIndex:2] == '1');
    }

    // 7. Attenuator (RA;)
    NSString *raReply = SendOverPort(port, @"RA;", cmdTimeout, NULL, nil);
    if (raReply && [raReply hasPrefix:@"RA"] && raReply.length >= 3) {
        int r = [[raReply substringFromIndex:2] intValue];
        state.attenuatorOn = (r > 0);
    }

    // 8. Filter (FL;)
    NSString *flReply = SendOverPort(port, @"FL;", cmdTimeout, NULL, nil);
    if (flReply && [flReply hasPrefix:@"FL"] && flReply.length >= 3) {
        int fl = [[flReply substringFromIndex:2] intValue];
        if (fl > 0) state.filterNumber = fl;
    }

    // 9. Supply Voltage (VL;)
    NSString *vlReply = SendOverPort(port, @"VL;", cmdTimeout, NULL, nil);
    if (vlReply) {
        double v = ParseVoltageReply(vlReply);
        if (v > 0) state.voltage = v;
    }

    // 10. S-Meter (SM0;)
    NSString *smReply = SendOverPort(port, @"SM0;", cmdTimeout, NULL, nil);
    if (smReply && [smReply hasPrefix:@"SM"] && smReply.length >= 4) {
        state.sMeterDots = [[smReply substringFromIndex:2] intValue];
    }

    [port close];
    return state;
}

BOOL TXSetRadioFrequency(NSString *path, uint64_t freqHz, NSError **error) {
    if (freqHz < 100000 || freqHz > 60000000) {
        if (error) *error = [NSError errorWithDomain:@"TXCAT" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Frequency out of range (100 kHz - 60 MHz)."}];
        return NO;
    }
    NSString *cmd = [NSString stringWithFormat:@"FA%011llu;", freqHz];
    double rtt = 0;
    NSString *reply = TXExecuteCATCommand(path, cmd, 0.3, &rtt, error);
    (void)reply;
    return (error && *error) ? NO : YES;
}

BOOL TXSetRadioMode(NSString *path, NSInteger modeCode, NSError **error) {
    if (modeCode < 1 || modeCode > 7) {
        if (error) *error = [NSError errorWithDomain:@"TXCAT" code:3 userInfo:@{NSLocalizedDescriptionKey: @"Invalid mode code (1-7)."}];
        return NO;
    }
    NSString *cmd = [NSString stringWithFormat:@"MD%ld;", (long)modeCode];
    double rtt = 0;
    NSString *reply = TXExecuteCATCommand(path, cmd, 0.3, &rtt, error);
    (void)reply;
    return (error && *error) ? NO : YES;
}

BOOL TXSetRadioPower(NSString *path, double watts, NSError **error) {
    int p = (int)round(watts);
    if (p < 1) p = 1;
    if (p > 10) p = 10;
    NSString *cmd = [NSString stringWithFormat:@"PC%03d;", p];
    double rtt = 0;
    NSString *reply = TXExecuteCATCommand(path, cmd, 0.3, &rtt, error);
    (void)reply;
    return (error && *error) ? NO : YES;
}

BOOL TXSetRadioPreamp(NSString *path, BOOL on, NSError **error) {
    NSString *cmd = [NSString stringWithFormat:@"PA%d;", on ? 1 : 0];
    double rtt = 0;
    NSString *reply = TXExecuteCATCommand(path, cmd, 0.3, &rtt, error);
    (void)reply;
    return (error && *error) ? NO : YES;
}

BOOL TXSetRadioAttenuator(NSString *path, BOOL on, NSError **error) {
    NSString *cmd = [NSString stringWithFormat:@"RA%02d;", on ? 1 : 0];
    double rtt = 0;
    NSString *reply = TXExecuteCATCommand(path, cmd, 0.3, &rtt, error);
    (void)reply;
    return (error && *error) ? NO : YES;
}

BOOL TXSetRadioFilter(NSString *path, NSInteger filterNumber, NSError **error) {
    if (filterNumber < 1 || filterNumber > 3) filterNumber = 1;
    NSString *cmd = [NSString stringWithFormat:@"FL%ld;", (long)filterNumber];
    double rtt = 0;
    NSString *reply = TXExecuteCATCommand(path, cmd, 0.3, &rtt, error);
    (void)reply;
    return (error && *error) ? NO : YES;
}

