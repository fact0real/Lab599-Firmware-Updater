#import "TX500TelemetryEngine.h"
#import <termios.h>
#import <fcntl.h>
#import <unistd.h>
#import <poll.h>

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
        _voltage = 13.8;
        _currentAmps = 0.11;
        _rfPowerWatts = 0.0;
        _swr = 1.0;
        _temperatureCelsius = 32.0;
        _frequencyHz = 14074000;
        _operatingMode = @"USB";
        _isTransmitting = NO;
        _sMeterDots = 12;
        _batteryPercent = 100;
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
    copy.currentAmps = self.currentAmps;
    copy.rfPowerWatts = self.rfPowerWatts;
    copy.swr = self.swr;
    copy.temperatureCelsius = self.temperatureCelsius;
    copy.frequencyHz = self.frequencyHz;
    copy.operatingMode = [self.operatingMode copy];
    copy.isTransmitting = self.isTransmitting;
    copy.sMeterDots = self.sMeterDots;
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
    self.overvoltageAlert = (self.voltage > 15.0);
    self.lowVoltageAlert = (self.voltage < 9.5);
    self.highSWRAlert = (self.swr >= 3.0);
    self.overtempAlert = (self.temperatureCelsius > 60.0);

    // Estimate 3S Li-ion battery pack percentage (9.6V empty to 12.6V full)
    if (self.voltage <= 9.6) {
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
    return (self.voltage > 7.0 && self.voltage <= 12.8);
}

- (BOOL)isExternalDCPowered {
    return (self.voltage > 13.0);
}

- (NSString *)powerSourceDescription {
    if (self.isExternalDCPowered) {
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
    NSInteger count[4] = {0};

    for (NSInteger i = 0; i < self.historyCount; i++) {
        NSInteger idx = (self.historyHead - 1 - i + kMaxTelemetryHistory) % kMaxTelemetryHistory;
        TXTelemetrySample s = self.historyBuffer[idx];
        NSTimeInterval age = now - s.timestamp;
        if (age < 0) age = 0;

        for (NSInteger w = 0; w < 4; w++) {
            if (age <= windows[w]) {
                sumV[w] += s.voltage;
                sumI[w] += s.currentAmps;
                sumP[w] += s.rfPowerWatts;
                sumS[w] += s.swr;
                sumT[w] += s.temperatureCelsius;
                count[w]++;
            }
        }
    }

    // Fallback if window hasn't accumulated enough samples
    for (NSInteger w = 0; w < 4; w++) {
        if (count[w] == 0 && self.historyCount > 0) {
            for (NSInteger i = 0; i < self.historyCount; i++) {
                TXTelemetrySample s = self.historyBuffer[i];
                sumV[w] += s.voltage;
                sumI[w] += s.currentAmps;
                sumP[w] += s.rfPowerWatts;
                sumS[w] += s.swr;
                sumT[w] += s.temperatureCelsius;
            }
            count[w] = self.historyCount;
        }
    }

    BOOL hasData = (self.historyCount > 0);
    TXApplyRollingAverages(data.voltageAverages, sumV, count, hasData);
    TXApplyRollingAverages(data.currentAverages, sumI, count, hasData);
    TXApplyRollingAverages(data.rfPowerAverages, sumP, count, hasData);
    TXApplyRollingAverages(data.swrAverages, sumS, count, hasData);
    TXApplyRollingAverages(data.temperatureAverages, sumT, count, hasData);
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
            self.statusBlock(@"Connected to transceiver CAT port (9600 baud)", YES);
        });
    }

    while (self.isRunning && !self.demoMode && !self.token.cancelled) {
        // 1. Query Transceiver State (IF;)
        NSString *ifReply = [self sendCommand:@"IF;" timeout:0.15];
        if (ifReply) {
            [TX500TelemetryEngine parseIFReply:ifReply intoData:liveData];
        }

        // 2. Query S-Meter (SM;) in RX, or Meters (RM;) in TX
        if (liveData.isTransmitting) {
            NSString *rmPwr = [self sendCommand:@"RM0;" timeout:0.15];
            if (rmPwr) [TX500TelemetryEngine parseRMReply:rmPwr intoData:liveData];

            NSString *rmSwr = [self sendCommand:@"RM1;" timeout:0.15];
            if (rmSwr) [TX500TelemetryEngine parseRMReply:rmSwr intoData:liveData];

            NSString *rmCur = [self sendCommand:@"RM4;" timeout:0.15];
            if (rmCur) [TX500TelemetryEngine parseRMReply:rmCur intoData:liveData];
        } else {
            NSString *sm = [self sendCommand:@"SM0;" timeout:0.15];
            if (sm) [TX500TelemetryEngine parseSMReply:sm intoData:liveData];
            liveData.rfPowerWatts = 0.0;
            liveData.currentAmps = 0.11; // 110 mA base consumption
        }

        // 3. Query Temperature & Voltage
        NSString *rmVolt = [self sendCommand:@"RM5;" timeout:0.15];
        if (rmVolt) [TX500TelemetryEngine parseRMReply:rmVolt intoData:liveData];

        NSString *rmTemp = [self sendCommand:@"RM6;" timeout:0.15];
        if (rmTemp) [TX500TelemetryEngine parseRMReply:rmTemp intoData:liveData];

        [liveData evaluateAlarms];

        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if (now - self.lastSampleTime >= 1.0) {
            self.lastSampleTime = now;
            TXTelemetrySample samp;
            samp.timestamp = now;
            samp.voltage = liveData.voltage;
            samp.currentAmps = liveData.currentAmps;
            samp.rfPowerWatts = liveData.rfPowerWatts;
            samp.swr = liveData.swr;
            samp.temperatureCelsius = liveData.temperatureCelsius;
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
            const char *bytes = (const char *)resp.bytes;
            if (bytes[resp.length - 1] == ';') {
                return [[NSString alloc] initWithData:resp encoding:NSASCIIStringEncoding];
            }
        }
    }
    return resp.length > 0 ? [[NSString alloc] initWithData:resp encoding:NSASCIIStringEncoding] : nil;
}

#pragma mark - Parsers

+ (BOOL)parseIFReply:(NSString *)reply intoData:(TXTelemetryData *)data {
    if (![reply hasPrefix:@"IF"] || reply.length < 28) return NO;
    // Format: IF[11 digits freq][5 spaces][5 digits RIT][RIT][XIT][TX:1][Mode:1]...
    NSString *clean = [reply stringByReplacingOccurrencesOfString:@";" withString:@""];
    if (clean.length < 28) return NO;

    // Frequency
    NSString *freqStr = [clean substringWithRange:NSMakeRange(2, 11)];
    uint64_t f = (uint64_t)[freqStr longLongValue];
    if (f > 0) data.frequencyHz = f;

    // TX state (index 28)
    if (clean.length > 28) {
        unichar txChar = [clean characterAtIndex:28];
        data.isTransmitting = (txChar == '1');
    }

    // Mode (index 29)
    if (clean.length > 29) {
        unichar mChar = [clean characterAtIndex:29];
        switch (mChar) {
            case '1': data.operatingMode = @"LSB"; break;
            case '2': data.operatingMode = @"USB"; break;
            case '3': data.operatingMode = @"CW"; break;
            case '4': data.operatingMode = @"FM"; break;
            case '5': data.operatingMode = @"AM"; break;
            case '6': data.operatingMode = @"DIG"; break;
            case '7': data.operatingMode = @"CWR"; break;
            default: data.operatingMode = @"USB"; break;
        }
    }
    return YES;
}

+ (BOOL)parseRMReply:(NSString *)reply intoData:(TXTelemetryData *)data {
    if (![reply hasPrefix:@"RM"] || reply.length < 4) return NO;
    // RM[type 1][val 4];
    NSString *body = [[reply stringByReplacingOccurrencesOfString:@"RM" withString:@""]
                      stringByReplacingOccurrencesOfString:@";" withString:@""];
    if (body.length < 2) return NO;

    unichar type = [body characterAtIndex:0];
    int val = [[body substringFromIndex:1] intValue];

    switch (type) {
        case '0': // Power (0 - 30 dots -> 0 - 10 Watts)
            data.rfPowerWatts = (val / 30.0) * 10.0;
            break;
        case '1': // SWR (0 - 30 dots -> 1.0 to 5.0)
            data.swr = 1.0 + ((val / 30.0) * 4.0);
            break;
        case '4': // Current (0 - 30 dots -> 0 to 3.5 Amperes)
            data.currentAmps = 0.11 + ((val / 30.0) * 3.39);
            break;
        case '5': // Voltage (e.g. tenths of volt or direct dots)
            if (val > 50 && val < 200) data.voltage = val / 10.0;
            else if (val <= 30) data.voltage = 9.0 + ((val / 30.0) * 6.0);
            break;
        case '6': // Temp (e.g. degrees C directly or dots)
            if (val >= 10 && val <= 90) data.temperatureCelsius = (double)val;
            else if (val <= 30) data.temperatureCelsius = 20.0 + ((val / 30.0) * 60.0);
            break;
        default:
            return NO;
    }
    return YES;
}

+ (BOOL)parseSMReply:(NSString *)reply intoData:(TXTelemetryData *)data {
    if (![reply hasPrefix:@"SM"] || reply.length < 4) return NO;
    NSString *body = [[reply stringByReplacingOccurrencesOfString:@"SM" withString:@""]
                      stringByReplacingOccurrencesOfString:@";" withString:@""];
    if (body.length < 2) return NO;
    int val = [[body substringFromIndex:1] intValue];
    data.sMeterDots = val;
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
            [self recordHistoricalSample:samp];
        }
        self.lastSampleTime = now;
    }

    // FT8 cycle: 15 seconds per phase
    // 0 to 14s: TX, 15 to 29s: RX (assuming 0.25s per tick, 60 ticks = 15s)
    int64_t cycleTick = tick % 120;
    BOOL txPhase = (cycleTick < 60);

    data.frequencyHz = 14074000;
    data.operatingMode = @"DIG (FT8)";
    data.isTransmitting = txPhase;

    if (txPhase) {
        // Transmitting: RF Power ~ 9.5 to 10.0 Watts with slight modulation
        double noise = ((tick % 7) - 3) * 0.05;
        data.rfPowerWatts = fmax(0.0, 9.8 + noise);
        data.currentAmps = 2.15 + (((tick % 5) - 2) * 0.04);
        data.swr = 1.22 + (((tick % 9) - 4) * 0.015);
        // Voltage sags slightly under load
        data.voltage = 13.5 + (((tick % 4) - 2) * 0.03);
        // Temperature slowly rises
        if (data.temperatureCelsius < 44.0) data.temperatureCelsius += 0.08;
        data.sMeterDots = 0;
    } else {
        // Receiving: Power = 0W, Current = 110mA, S-meter active
        data.rfPowerWatts = 0.0;
        data.currentAmps = 0.11 + (((tick % 3) - 1) * 0.005);
        data.swr = 1.0;
        data.voltage = 13.8 + (((tick % 5) - 2) * 0.02);
        // Temperature slowly cools down
        if (data.temperatureCelsius > 34.0) data.temperatureCelsius -= 0.04;
        data.sMeterDots = 10 + (NSInteger)((tick % 12));
    }

    if (now - self.lastSampleTime >= 1.0) {
        self.lastSampleTime = now;
        TXTelemetrySample samp;
        samp.timestamp = now;
        samp.voltage = data.voltage;
        samp.currentAmps = data.currentAmps;
        samp.rfPowerWatts = data.rfPowerWatts;
        samp.swr = data.swr;
        samp.temperatureCelsius = data.temperatureCelsius;
        [self recordHistoricalSample:samp];
    }
    [self computeAveragesForData:data atTime:now];
}

@end
