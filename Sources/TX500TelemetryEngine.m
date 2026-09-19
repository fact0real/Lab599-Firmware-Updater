#import "TX500TelemetryEngine.h"
#import <termios.h>
#import <fcntl.h>
#import <unistd.h>
#import <poll.h>
#import <string.h>

@implementation TXRollingAverages
- (id)copyWithZone:(NSZone *)zone {
    TXRollingAverages *copy = [[[self class] allocWithZone:zone] init];
    copy.avg5m = self.avg5m;
    copy.avg15m = self.avg15m;
    copy.avg30m = self.avg30m;
    copy.avg60m = self.avg60m;
    copy.hasData = self.hasData;
    return copy;
}
@end

@implementation TXTelemetryData

- (instancetype)init {
    if ((self = [super init])) {
        // Unknown until the radio answers the documented LAB599 `VL;` query.
        // A nominal value here used to make a disconnected radio look like a
        // verified 13.8 V external supply.
        _voltage = 0.0;
        _voltageValid = NO;
        _currentAmps = 0.0;
        _currentValid = NO;
        _rfPowerWatts = 0.0;
        _rfPowerValid = NO;
        _swr = 0.0;
        _swrValid = NO;
        _swrMeterDots = 0;
        _swrMeterValid = NO;
        _temperatureCelsius = 0.0;
        _temperatureValid = NO;
        _frequencyHz = 0;
        _frequencyValid = NO;
        _operatingMode = @"";
        _modeValid = NO;
        _isTransmitting = NO;
        _txStateValid = NO;
        _sMeterDots = 0;
        _sMeterValid = NO;
        _batteryPercent = 0;
        _voltageAverages = [TXRollingAverages new];
        _currentAverages = [TXRollingAverages new];
        _rfPowerAverages = [TXRollingAverages new];
        _swrAverages = [TXRollingAverages new];
        _temperatureAverages = [TXRollingAverages new];
        [self evaluateAlarms];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    TXTelemetryData *copy = [[[self class] allocWithZone:zone] init];
    copy.voltage = self.voltage;
    copy.voltageValid = self.voltageValid;
    copy.currentAmps = self.currentAmps;
    copy.currentValid = self.currentValid;
    copy.rfPowerWatts = self.rfPowerWatts;
    copy.rfPowerValid = self.rfPowerValid;
    copy.swr = self.swr;
    copy.swrValid = self.swrValid;
    copy.swrMeterDots = self.swrMeterDots;
    copy.swrMeterValid = self.swrMeterValid;
    copy.temperatureCelsius = self.temperatureCelsius;
    copy.temperatureValid = self.temperatureValid;
    copy.frequencyHz = self.frequencyHz;
    copy.frequencyValid = self.frequencyValid;
    copy.operatingMode = [self.operatingMode copy];
    copy.modeValid = self.modeValid;
    copy.isTransmitting = self.isTransmitting;
    copy.txStateValid = self.txStateValid;
    copy.sMeterDots = self.sMeterDots;
    copy.sMeterValid = self.sMeterValid;
    copy.batteryPercent = self.batteryPercent;
    copy.overvoltageAlert = self.overvoltageAlert;
    copy.lowVoltageAlert = self.lowVoltageAlert;
    copy.highSWRAlert = self.highSWRAlert;
    copy.overtempAlert = self.overtempAlert;
    copy.voltageAverages = [self.voltageAverages copy];
    copy.currentAverages = [self.currentAverages copy];
    copy.rfPowerAverages = [self.rfPowerAverages copy];
    copy.swrAverages = [self.swrAverages copy];
    copy.temperatureAverages = [self.temperatureAverages copy];
    return copy;
}

- (void)evaluateAlarms {
    self.overvoltageAlert = self.voltageValid && (self.voltage > 15.0);
    self.lowVoltageAlert = self.voltageValid && (self.voltage < 9.5);
    self.highSWRAlert = self.swrValid && (self.swr >= 3.0);
    self.overtempAlert = self.temperatureValid && (self.temperatureCelsius > 60.0);

    // Estimate 3S Li-ion battery pack percentage (9.6V empty to 12.6V full)
    if (!self.voltageValid) {
        self.batteryPercent = 0;
    } else if (self.voltage <= 9.6) {
        self.batteryPercent = 0;
    } else if (self.voltage >= 12.6 && self.voltage < 13.5) {
        self.batteryPercent = 100;
    } else if (self.voltage >= 13.5) {
        // External PSU mode (>13.5V)
        self.batteryPercent = 100;
    } else {
        self.batteryPercent = (NSInteger)(((self.voltage - 9.6) / 3.0) * 100.0);
    }
}

- (BOOL)isBatteryPackPowered {
    return self.voltageValid && (self.voltage > 7.0 && self.voltage <= 12.8);
}

- (BOOL)isExternalDCPowered {
    return self.voltageValid && (self.voltage > 13.0);
}

- (NSString *)powerSourceDescription {
    if (!self.voltageValid) {
        return @"Voltage unavailable";
    } else if (self.isExternalDCPowered) {
        return [NSString stringWithFormat:@"External DC Power (%.1f V)", self.voltage];
    } else if (self.isBatteryPackPowered) {
        return [NSString stringWithFormat:@"BP-500/550 Battery Pack (%.1f V • %ld%%)", self.voltage, (long)self.batteryPercent];
    } else if (self.voltage > 0) {
        return [NSString stringWithFormat:@"DC Power (%.1f V)", self.voltage];
    }
    return @"Not Connected";
}

@end

typedef struct {
    NSTimeInterval timestamp;
    double voltage;
    double currentAmps;
    double rfPowerWatts;
    double swr;
    double temperatureCelsius;
    BOOL voltageValid;
    BOOL currentValid;
    BOOL rfPowerValid;
    BOOL swrValid;
    BOOL temperatureValid;
} TXTelemetrySample;

static const NSInteger kMaxTelemetryHistory = 3600;

@interface TX500TelemetryEngine ()
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, strong) Lab599SerialPort *activePort;
@property (nonatomic, strong) Lab599Cancellation *token;
@property (nonatomic, strong) dispatch_queue_t pollQueue;
@property (nonatomic, copy, nullable) TXTelemetryUpdateHandler updateBlock;
@property (nonatomic, copy, nullable) TXTelemetryStatusHandler statusBlock;
@property (nonatomic, assign) uint64_t demoTick;

@property (nonatomic, assign) TXTelemetrySample *historyBuffer;
@property (nonatomic, assign) NSInteger historyCount;
@property (nonatomic, assign) NSInteger historyHead;
@property (nonatomic, assign) NSTimeInterval lastSampleTime;
@property (nonatomic, assign) NSTimeInterval lastFrequencyTime;
@property (nonatomic, assign) NSTimeInterval lastModeTime;
@property (nonatomic, assign) NSTimeInterval lastTXStateTime;
@property (nonatomic, assign) NSTimeInterval lastSMeterTime;
@property (nonatomic, assign) NSTimeInterval lastSWRMeterTime;
@property (nonatomic, assign) NSTimeInterval lastVoltageTime;
@property (nonatomic, assign) NSTimeInterval lastPowerTime;
@property (nonatomic, assign) NSTimeInterval lastSlowPollTime;
@property (nonatomic, assign) NSInteger consecutiveEmptyCycles;
@property (nonatomic, assign) BOOL reportedConnected;
@end

@implementation TX500TelemetryEngine

- (instancetype)init {
    if ((self = [super init])) {
        _pollInterval = 0.25;
        _pollQueue = dispatch_queue_create("com.lab599.telemetry", DISPATCH_QUEUE_SERIAL);
        _historyBuffer = (TXTelemetrySample *)calloc(kMaxTelemetryHistory, sizeof(TXTelemetrySample));
        _historyCount = 0;
        _historyHead = 0;
        _lastSampleTime = 0;
    }
    return self;
}

- (void)dealloc {
    [self stop];
    if (_historyBuffer) {
        free(_historyBuffer);
        _historyBuffer = NULL;
    }
}

- (void)recordHistoricalSample:(TXTelemetrySample)sample {
    if (!self.historyBuffer) return;
    self.historyBuffer[self.historyHead] = sample;
    self.historyHead = (self.historyHead + 1) % kMaxTelemetryHistory;
    if (self.historyCount < kMaxTelemetryHistory) {
        self.historyCount++;
    }
}

static void TXApplyRollingAverages(TXRollingAverages *avg, const double sums[4], const NSInteger counts[4], BOOL hasData) {
    if (!avg) return;
    avg.avg5m = counts[0] > 0 ? (sums[0] / counts[0]) : 0;
    avg.avg15m = counts[1] > 0 ? (sums[1] / counts[1]) : 0;
    avg.avg30m = counts[2] > 0 ? (sums[2] / counts[2]) : 0;
    avg.avg60m = counts[3] > 0 ? (sums[3] / counts[3]) : 0;
    avg.hasData = hasData;
}

- (void)computeAveragesForData:(TXTelemetryData *)data atTime:(NSTimeInterval)now {
    if (self.historyCount == 0 || !self.historyBuffer) return;

    NSTimeInterval windows[4] = { 300.0, 900.0, 1800.0, 3600.0 };
    double sumV[4] = {0}, sumI[4] = {0}, sumP[4] = {0}, sumS[4] = {0}, sumT[4] = {0};
    NSInteger countV[4] = {0}, countI[4] = {0}, countP[4] = {0}, countS[4] = {0}, countT[4] = {0};

    for (NSInteger i = 0; i < self.historyCount; i++) {
        NSInteger idx = (self.historyHead - 1 - i + kMaxTelemetryHistory) % kMaxTelemetryHistory;
        TXTelemetrySample s = self.historyBuffer[idx];
        NSTimeInterval age = now - s.timestamp;
        if (age < 0) age = 0;

        for (NSInteger w = 0; w < 4; w++) {
            if (age <= windows[w]) {
                if (s.voltageValid) { sumV[w] += s.voltage; countV[w]++; }
                if (s.currentValid) { sumI[w] += s.currentAmps; countI[w]++; }
                if (s.rfPowerValid) { sumP[w] += s.rfPowerWatts; countP[w]++; }
                if (s.swrValid) { sumS[w] += s.swr; countS[w]++; }
                if (s.temperatureValid) { sumT[w] += s.temperatureCelsius; countT[w]++; }
            }
        }
    }

    TXApplyRollingAverages(data.voltageAverages, sumV, countV, countV[0] > 0);
    TXApplyRollingAverages(data.currentAverages, sumI, countI, countI[0] > 0);
    TXApplyRollingAverages(data.rfPowerAverages, sumP, countP, countP[0] > 0);
    TXApplyRollingAverages(data.swrAverages, sumS, countS, countS[0] > 0);
    TXApplyRollingAverages(data.temperatureAverages, sumT, countT, countT[0] > 0);
}

- (void)startWithPort:(nullable NSString *)portPath
             interval:(NSTimeInterval)interval
               update:(TXTelemetryUpdateHandler)updateBlock
               status:(nullable TXTelemetryStatusHandler)statusBlock {
    [self stop];
    self.serialPortPath = portPath;
    self.pollInterval = interval > 0.05 ? interval : 0.25;
    self.updateBlock = updateBlock;
    self.statusBlock = statusBlock;
    self.isRunning = YES;
    self.token = [Lab599Cancellation new];
    self.lastFrequencyTime = 0;
    self.lastModeTime = 0;
    self.lastTXStateTime = 0;
    self.lastSMeterTime = 0;
    self.lastSWRMeterTime = 0;
    self.lastVoltageTime = 0;
    self.lastPowerTime = 0;
    self.lastSlowPollTime = 0;
    self.consecutiveEmptyCycles = 0;
    self.reportedConnected = NO;
    self.historyCount = 0;
    self.historyHead = 0;
    self.lastSampleTime = 0;
    if (self.historyBuffer) memset(self.historyBuffer, 0, sizeof(TXTelemetrySample) * kMaxTelemetryHistory);

    dispatch_async(self.pollQueue, ^{
        [self runLoop];
    });
}

- (void)stop {
    self.isRunning = NO;
    self.token.cancelled = YES;
    if (self.activePort) {
        [self.activePort close];
        self.activePort = nil;
    }
}

#pragma mark - Polling Loop

- (void)runLoop {
    TXTelemetryData *liveData = [TXTelemetryData new];

    if (self.demoMode) {
        if (self.statusBlock) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.statusBlock(@"Simulation / Demo Mode Active (FT8 Cycle)", YES);
            });
        }
        while (self.isRunning && self.demoMode) {
            [self stepDemo:liveData];
            [liveData evaluateAlarms];
            if (self.updateBlock) {
                TXTelemetryData *snapshot = [liveData copy];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (self.isRunning && self.updateBlock) self.updateBlock(snapshot);
                });
            }
            [NSThread sleepForTimeInterval:self.pollInterval];
        }
        return;
    }

    if (!self.serialPortPath) {
        if (self.statusBlock) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.statusBlock(@"No serial port selected", NO);
            });
        }
        return;
    }

    // Open port at 9600 baud, 8N1 via Lab599SerialPort
    NSError *openErr = nil;
    Lab599SerialPort *port = [Lab599SerialPort openPath:self.serialPortPath speed:B9600 error:&openErr];
    if (!port) {
        if (self.statusBlock) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.statusBlock(@"Failed to open serial port", NO);
            });
        }
        return;
    }
    self.activePort = port;

    if (self.statusBlock) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.statusBlock(@"Serial port opened; waiting for valid CAT replies…", NO);
        });
    }

    while (self.isRunning && !self.demoMode && !self.token.cancelled) {
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        BOOL receivedThisCycle = NO;

        // IF; is explicitly unavailable in DIG mode. Independent documented
        // queries keep frequency, mode, and PTT state accurate in every mode.
        NSString *faReply = [self sendCommand:@"FA;" timeout:0.25];
        if ([TX500TelemetryEngine parseFAReply:faReply intoData:liveData]) {
            self.lastFrequencyTime = now; receivedThisCycle = YES;
        }
        NSString *mdReply = [self sendCommand:@"MD;" timeout:0.25];
        if ([TX500TelemetryEngine parseMDReply:mdReply intoData:liveData]) {
            self.lastModeTime = now; receivedThisCycle = YES;
        }
        NSString *ptReply = [self sendCommand:@"PT;" timeout:0.25];
        if ([TX500TelemetryEngine parsePTReply:ptReply intoData:liveData]) {
            self.lastTXStateTime = now; receivedThisCycle = YES;
        }
        NSString *smReply = [self sendCommand:@"SM0;" timeout:0.25];
        if ([TX500TelemetryEngine parseSMReply:smReply intoData:liveData]) {
            self.lastSMeterTime = now; receivedThisCycle = YES;
        }

        // The protocol exposes SWR only as raw 0-30 meter dots. RM1 selects
        // that meter and RM; reads it. No undocumented dots-to-ratio conversion
        // is applied.
        if (liveData.txStateValid && liveData.isTransmitting) {
            NSString *rmReply = [self sendCommand:@"RM1;RM;" timeout:0.30];
            if ([TX500TelemetryEngine parseRMReply:rmReply intoData:liveData]) {
                self.lastSWRMeterTime = now; receivedThisCycle = YES;
            }
        } else {
            liveData.swrMeterValid = NO;
        }

        // Slow-changing values do not need to consume serial bandwidth on
        // every fast meter cycle.
        if (self.lastSlowPollTime == 0 || now - self.lastSlowPollTime >= 1.0) {
            self.lastSlowPollTime = now;
            NSString *pcReply = [self sendCommand:@"PC;" timeout:0.30];
            if ([TX500TelemetryEngine parsePCReply:pcReply intoData:liveData]) {
                self.lastPowerTime = now; receivedThisCycle = YES;
            }
            NSString *voltageReply = [self sendCommand:@"VL;" timeout:0.45];
            if ([TX500TelemetryEngine parseVLReply:voltageReply intoData:liveData]) {
                self.lastVoltageTime = now; receivedThisCycle = YES;
            }
        }

        // Expire stale values instead of silently presenting old telemetry as live.
        liveData.frequencyValid = self.lastFrequencyTime > 0 && now - self.lastFrequencyTime <= 2.0;
        liveData.modeValid = self.lastModeTime > 0 && now - self.lastModeTime <= 2.0;
        liveData.txStateValid = self.lastTXStateTime > 0 && now - self.lastTXStateTime <= 2.0;
        liveData.sMeterValid = self.lastSMeterTime > 0 && now - self.lastSMeterTime <= 2.0;
        liveData.swrMeterValid = liveData.isTransmitting && self.lastSWRMeterTime > 0 && now - self.lastSWRMeterTime <= 2.0;
        liveData.rfPowerValid = self.lastPowerTime > 0 && now - self.lastPowerTime <= 3.0;
        liveData.voltageValid = self.lastVoltageTime > 0 && now - self.lastVoltageTime <= 3.0;
        liveData.currentValid = NO;
        liveData.temperatureValid = NO;
        liveData.swrValid = NO; // CAT rev.3 provides dots, not an engineering ratio.

        if (receivedThisCycle) {
            self.consecutiveEmptyCycles = 0;
            if (!self.reportedConnected && self.statusBlock) {
                self.reportedConnected = YES;
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.statusBlock(@"Live CAT telemetry verified (9600 baud)", YES);
                });
            }
        } else {
            self.consecutiveEmptyCycles++;
            if (self.consecutiveEmptyCycles >= 3 && self.reportedConnected && self.statusBlock) {
                self.reportedConnected = NO;
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.statusBlock(@"CAT replies lost — check cable, baud rate, and Menu 35 protocol", NO);
                });
            }
        }

        [liveData evaluateAlarms];

        BOOL hasHistoricalValue = liveData.voltageValid || liveData.currentValid || liveData.rfPowerValid ||
                                  liveData.swrValid || liveData.temperatureValid;
        if (hasHistoricalValue && now - self.lastSampleTime >= 1.0) {
            self.lastSampleTime = now;
            TXTelemetrySample samp;
            memset(&samp, 0, sizeof(samp));
            samp.timestamp = now;
            samp.voltage = liveData.voltage;
            samp.currentAmps = liveData.currentAmps;
            samp.rfPowerWatts = liveData.rfPowerWatts;
            samp.swr = liveData.swr;
            samp.temperatureCelsius = liveData.temperatureCelsius;
            samp.voltageValid = liveData.voltageValid;
            samp.currentValid = liveData.currentValid;
            samp.rfPowerValid = liveData.rfPowerValid;
            samp.swrValid = liveData.swrValid;
            samp.temperatureValid = liveData.temperatureValid;
            [self recordHistoricalSample:samp];
        }
        [self computeAveragesForData:liveData atTime:now];

        if (self.updateBlock) {
            TXTelemetryData *snapshot = [liveData copy];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.isRunning && self.updateBlock) self.updateBlock(snapshot);
            });
        }

        [NSThread sleepForTimeInterval:self.pollInterval];
    }

    if (self.activePort) {
        [self.activePort close];
        self.activePort = nil;
    }
}

#pragma mark - Serial I/O Helper

- (nullable NSString *)sendCommand:(NSString *)cmd timeout:(NSTimeInterval)timeout {
    if (!self.activePort || self.token.cancelled) return nil;
    // A timed-out or partial previous reply must not be mistaken for the next
    // command's answer.
    [self.activePort discardInput:nil];
    NSData *data = [cmd dataUsingEncoding:NSASCIIStringEncoding];
    NSError *err = nil;
    if (![self.activePort writeData:data timeout:timeout cancellation:self.token error:&err]) {
        return nil;
    }

    NSMutableData *resp = [NSMutableData data];
    double end = Lab599MonotonicTime() + timeout;

    while (Lab599MonotonicTime() < end && !self.token.cancelled) {
        NSData *chunk = [self.activePort readMaximum:64 timeout:0.04 cancellation:self.token error:&err];
        if (chunk.length > 0) {
            [resp appendData:chunk];
            NSData *terminator = [@";" dataUsingEncoding:NSASCIIStringEncoding];
            NSRange endRange = [resp rangeOfData:terminator options:0 range:NSMakeRange(0, resp.length)];
            if (endRange.location != NSNotFound) {
                NSData *frame = [resp subdataWithRange:NSMakeRange(0, NSMaxRange(endRange))];
                return [[NSString alloc] initWithData:frame encoding:NSASCIIStringEncoding];
            }
        }
    }
    return resp.length > 0 ? [[NSString alloc] initWithData:resp encoding:NSASCIIStringEncoding] : nil;
}

#pragma mark - Parsers

static NSString *TXCompactCATFrame(NSString *reply, NSString *prefix) {
    if (!reply.length || !prefix.length) return nil;
    NSString *compact = [[reply componentsSeparatedByCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsJoinedByString:@""];
    NSRange start = [compact rangeOfString:prefix];
    if (start.location == NSNotFound) return nil;
    NSRange end = [compact rangeOfString:@";" options:0
                                   range:NSMakeRange(NSMaxRange(start), compact.length - NSMaxRange(start))];
    if (end.location == NSNotFound) return nil;
    return [compact substringWithRange:NSMakeRange(start.location, NSMaxRange(end) - start.location)];
}

static BOOL TXStringContainsOnlyDigits(NSString *value) {
    if (!value.length) return NO;
    return [value rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound;
}

static NSString *TXModeName(unichar mode) {
    switch (mode) {
        case '1': return @"LSB";
        case '2': return @"USB";
        case '3': return @"CW";
        case '4': return @"FM";
        case '5': return @"AM";
        case '6': return @"DIG";
        case '7': return @"CW-R";
        default: return nil;
    }
}

+ (BOOL)parseIFReply:(NSString *)reply intoData:(TXTelemetryData *)data {
    if (![reply hasPrefix:@"IF"] || reply.length < 28) return NO;
    // Format: IF[11 digits freq][5 spaces][5 digits RIT][RIT][XIT][TX:1][Mode:1]...
    NSString *clean = [reply stringByReplacingOccurrencesOfString:@";" withString:@""];
    if (clean.length < 28) return NO;

    // Frequency
    NSString *freqStr = [clean substringWithRange:NSMakeRange(2, 11)];
    uint64_t f = (uint64_t)[freqStr longLongValue];
    if (f > 0) {
        data.frequencyHz = f;
        data.frequencyValid = YES;
    }

    // TX state (index 28)
    if (clean.length > 28) {
        unichar txChar = [clean characterAtIndex:28];
        if (txChar == '0' || txChar == '1') {
            data.isTransmitting = (txChar == '1');
            data.txStateValid = YES;
        }
    }

    // Mode (index 29)
    if (clean.length > 29) {
        unichar mChar = [clean characterAtIndex:29];
        NSString *mode = TXModeName(mChar);
        if (mode) {
            data.operatingMode = mode;
            data.modeValid = YES;
        }
    }
    return data.frequencyValid || data.txStateValid || data.modeValid;
}

+ (BOOL)parseFAReply:(NSString *)reply intoData:(TXTelemetryData *)data {
    NSString *frame = TXCompactCATFrame(reply, @"FA");
    if (!frame || frame.length != 14) return NO; // FA + 11 digits + ;
    NSString *field = [frame substringWithRange:NSMakeRange(2, 11)];
    if (!TXStringContainsOnlyDigits(field)) return NO;
    uint64_t hz = field.longLongValue;
    if (hz < 500000 || hz > 56000000) return NO;
    data.frequencyHz = hz;
    data.frequencyValid = YES;
    return YES;
}

+ (BOOL)parseMDReply:(NSString *)reply intoData:(TXTelemetryData *)data {
    NSString *frame = TXCompactCATFrame(reply, @"MD");
    if (!frame || frame.length != 4) return NO;
    NSString *mode = TXModeName([frame characterAtIndex:2]);
    if (!mode) return NO;
    data.operatingMode = mode;
    data.modeValid = YES;
    return YES;
}

+ (BOOL)parsePTReply:(NSString *)reply intoData:(TXTelemetryData *)data {
    NSString *frame = TXCompactCATFrame(reply, @"PT");
    if (!frame || frame.length != 4) return NO;
    unichar state = [frame characterAtIndex:2];
    if (state != '0' && state != '1') return NO;
    data.isTransmitting = (state == '1');
    data.txStateValid = YES;
    return YES;
}

+ (BOOL)parsePCReply:(NSString *)reply intoData:(TXTelemetryData *)data {
    NSString *frame = TXCompactCATFrame(reply, @"PC");
    if (!frame || frame.length != 6) return NO; // PC + 3 digits + ;
    NSString *field = [frame substringWithRange:NSMakeRange(2, 3)];
    if (!TXStringContainsOnlyDigits(field)) return NO;
    NSInteger raw = field.integerValue;
    if (raw < 10 || raw > 100) return NO;
    // TX-500 power range is 1-10 W; PC encodes it in tenths of a watt.
    data.rfPowerWatts = raw / 10.0;
    data.rfPowerValid = YES;
    return YES;
}

+ (BOOL)parseRMReply:(NSString *)reply intoData:(TXTelemetryData *)data {
    NSString *frame = TXCompactCATFrame(reply, @"RM");
    if (!frame || frame.length != 8) return NO; // RM + type + 4 digits + ;
    unichar type = [frame characterAtIndex:2];
    NSString *field = [frame substringWithRange:NSMakeRange(3, 4)];
    if (!TXStringContainsOnlyDigits(field)) return NO;
    NSInteger val = field.integerValue;
    if (val < 0 || val > 30) return NO;

    switch (type) {
        case '0': // Raw TX power meter, explicitly documented as dots.
            data.sMeterDots = val;
            data.sMeterValid = YES;
            return YES;
        case '1': // Raw SWR meter; CAT does not define dots-to-ratio conversion.
            data.swrMeterDots = val;
            data.swrMeterValid = YES;
            return YES;
        default:
            return NO;
    }
}

+ (BOOL)parseVLReply:(NSString *)reply intoData:(TXTelemetryData *)data {
    if (!reply.length || !data) return NO;

    // Ignore harmless CR/LF/space noise and locate one complete VL frame.
    NSString *clean = [[reply componentsSeparatedByCharactersInSet:
                        [NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsJoinedByString:@""];
    NSRange prefix = [clean rangeOfString:@"VL"];
    if (prefix.location == NSNotFound) return NO;
    NSUInteger valueStart = NSMaxRange(prefix);
    NSRange suffix = [clean rangeOfString:@";" options:0
                                    range:NSMakeRange(valueStart, clean.length - valueStart)];
    if (suffix.location == NSNotFound || suffix.location == valueStart) return NO;

    NSString *field = [clean substringWithRange:NSMakeRange(valueStart, suffix.location - valueStart)];
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"0123456789."];
    if ([field rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound) return NO;

    double volts = 0.0;
    if ([field containsString:@"."]) {
        volts = field.doubleValue;
    } else {
        // Firmware revisions have represented the four-character field with
        // either one or two implied decimal places. Select the only scaling
        // that falls in the radio's plausible 7-20 V supply range.
        NSInteger raw = field.integerValue;
        double candidates[] = { raw / 10.0, raw / 100.0, raw / 1000.0 };
        for (NSUInteger i = 0; i < sizeof(candidates) / sizeof(candidates[0]); i++) {
            if (candidates[i] >= 7.0 && candidates[i] <= 20.0) {
                volts = candidates[i];
                break;
            }
        }
    }
    if (volts < 7.0 || volts > 20.0) return NO;

    data.voltage = volts;
    data.voltageValid = YES;
    return YES;
}

+ (BOOL)parseSMReply:(NSString *)reply intoData:(TXTelemetryData *)data {
    NSString *frame = TXCompactCATFrame(reply, @"SM");
    if (!frame || frame.length != 8 || [frame characterAtIndex:2] != '0') return NO;
    NSString *field = [frame substringWithRange:NSMakeRange(3, 4)];
    if (!TXStringContainsOnlyDigits(field)) return NO;
    NSInteger val = field.integerValue;
    if (val < 0 || val > 30) return NO;
    data.sMeterDots = val;
    data.sMeterValid = YES;
    return YES;
}

#pragma mark - Demo / Simulation Generator

- (void)stepDemo:(TXTelemetryData *)data {
    self.demoTick++;
    int64_t tick = (int64_t)self.demoTick;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];

    // Pre-populate 1 hour of realistic FT8 QSO history on startup
    if (self.historyCount == 0) {
        for (int s = 3600; s >= 1; s--) {
            NSTimeInterval t = now - (NSTimeInterval)s;
            int64_t pastTick = (3600 - s) * 4;
            int64_t cTick = pastTick % 120;
            BOOL tx = (cTick < 60);
            TXTelemetrySample samp;
            memset(&samp, 0, sizeof(samp));
            samp.timestamp = t;
            if (tx) {
                samp.voltage = 13.52 + ((pastTick % 4) - 2) * 0.03;
                samp.currentAmps = 2.15 + ((pastTick % 5) - 2) * 0.04;
                samp.rfPowerWatts = 9.8 + ((pastTick % 7) - 3) * 0.05;
                samp.swr = 1.22 + ((pastTick % 9) - 4) * 0.015;
                samp.temperatureCelsius = 38.0 + ((pastTick % 13) - 6) * 0.10;
            } else {
                samp.voltage = 13.80 + ((pastTick % 5) - 2) * 0.02;
                samp.currentAmps = 0.11;
                samp.rfPowerWatts = 0.0;
                samp.swr = 1.0;
                samp.temperatureCelsius = 35.0 + ((pastTick % 9) - 4) * 0.10;
            }
            samp.voltageValid = YES;
            samp.currentValid = YES;
            samp.rfPowerValid = YES;
            samp.swrValid = tx;
            samp.temperatureValid = YES;
            [self recordHistoricalSample:samp];
        }
        self.lastSampleTime = now;
    }

    // FT8 cycle: 15 seconds per phase
    // 0 to 14s: TX, 15 to 29s: RX (assuming 0.25s per tick, 60 ticks = 15s)
    int64_t cycleTick = tick % 120;
    BOOL txPhase = (cycleTick < 60);

    data.frequencyHz = 14074000;
    data.frequencyValid = YES;
    data.voltageValid = YES;
    data.operatingMode = @"DIG (FT8)";
    data.modeValid = YES;
    data.isTransmitting = txPhase;
    data.txStateValid = YES;
    data.currentValid = YES;
    data.rfPowerValid = YES;
    data.temperatureValid = YES;
    data.swrValid = txPhase;

    if (txPhase) {
        // Transmitting: RF Power ~ 9.5 to 10.0 Watts with slight modulation
        double noise = ((tick % 7) - 3) * 0.05;
        data.rfPowerWatts = fmax(0.0, 9.8 + noise);
        data.currentAmps = 2.15 + (((tick % 5) - 2) * 0.04);
        data.swr = 1.22 + (((tick % 9) - 4) * 0.015);
        data.swrMeterDots = 3 + (NSInteger)(tick % 3);
        data.swrMeterValid = YES;
        // Voltage sags slightly under load
        data.voltage = 13.5 + (((tick % 4) - 2) * 0.03);
        // Temperature slowly rises
        if (data.temperatureCelsius < 20.0) data.temperatureCelsius = 38.0;
        else if (data.temperatureCelsius < 44.0) data.temperatureCelsius += 0.08;
        data.sMeterDots = 0;
        data.sMeterValid = YES;
    } else {
        // Receiving: Power = 0W, Current = 110mA, S-meter active
        data.rfPowerWatts = 0.0;
        data.currentAmps = 0.11 + (((tick % 3) - 1) * 0.005);
        data.swr = 1.0;
        data.swrValid = NO;
        data.swrMeterValid = NO;
        data.voltage = 13.8 + (((tick % 5) - 2) * 0.02);
        // Temperature slowly cools down
        if (data.temperatureCelsius < 20.0) data.temperatureCelsius = 35.0;
        else if (data.temperatureCelsius > 34.0) data.temperatureCelsius -= 0.04;
        data.sMeterDots = 10 + (NSInteger)((tick % 12));
        data.sMeterValid = YES;
    }

    if (now - self.lastSampleTime >= 1.0) {
        self.lastSampleTime = now;
        TXTelemetrySample samp;
        memset(&samp, 0, sizeof(samp));
        samp.timestamp = now;
        samp.voltage = data.voltage;
        samp.currentAmps = data.currentAmps;
        samp.rfPowerWatts = data.rfPowerWatts;
        samp.swr = data.swr;
        samp.temperatureCelsius = data.temperatureCelsius;
        samp.voltageValid = data.voltageValid;
        samp.currentValid = data.currentValid;
        samp.rfPowerValid = data.rfPowerValid;
        samp.swrValid = data.swrValid;
        samp.temperatureValid = data.temperatureValid;
        [self recordHistoricalSample:samp];
    }
    [self computeAveragesForData:data atTime:now];
}

@end
