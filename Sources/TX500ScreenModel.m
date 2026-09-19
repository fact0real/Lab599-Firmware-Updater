#import "TX500ScreenModel.h"

@implementation TX500ScreenState

- (instancetype)init {
    if ((self = [super init])) {
        // Match exact real Lab599 TX-500 photo parameters
        _frequencyHz = 24889300;       // 24.889.300 MHz (12m band FT8/DIG)
        _vfoBFrequencyHz = 10100000;   // 10.100.000 MHz (30m band CW)
        _activeVFO = 0;
        _operatingMode = @"DIG";
        _vfoBMode = @"CWR";
        _isTransmitting = NO;
        _sMeterDots = 14;              // S7 calibrated reading
        _rfPowerWatts = 10.0;
        _swr = 1.12;
        _supplyVoltage = 12.0;         // 12.0V as in real photo
        _batteryPercent = 88;
        _isBatteryPowered = YES;
        _clockString = @"18:32";
        _vfoStep = @"100 Hz";
        _isLocked = NO;
        _agcDelay = 10;                // "AGC 10" as on real screen
        _highTempAlert = NO;
        _ritActive = NO;
        _xitActive = NO;
        _ritOffsetHz = 0;
        _filterNumber = 1;
        _filterName = @"FIL-1";
        _filterBandwidthHz = 3100;
        _filterBandwidthString = @"3.10k";
        _afGainLevel = 64;             // "AF64" as in real photo
        _rfGainLevel = 0;              // "RF0" as in real photo
        _squelchLevel = 0;
        _noiseReduction = NO;
        _noiseBlanker = NO;
        _notchFilter = NO;
        _attenuator = NO;
        _preamp = NO;
        _vox = NO;
        _compressor = NO;
        _virtualIF = NO;
        _monitor = YES;
        _split = NO;
        _squelchActive = NO;

        // Top 4 soft keys (matching 4 top physical buttons on TX-500)
        _topSoftKeyLabels = @[@"CWSPEED", @"CWPITCH", @"POWER", @"VOX"];
        _topSoftKeyValues = @[@"", @"", @"100", @""];

        // Bottom 4 soft keys (matching 4 bottom physical buttons on TX-500)
        _softKeyLabels = @[@"<<", @"TONE", @"MON", @">>"];

        // Filled spectrum bars as on physical LCD
        _filledSpectrumBars = YES;

        // Authentic FT8 spectrum distribution: flat baseline with noise (0.02-0.08)
        // and a prominent digital passband peak in the center (bins 29-37)
        NSMutableArray<NSNumber *> *amps = [NSMutableArray arrayWithCapacity:64];
        for (int i = 0; i < 64; i++) {
            double baseNoise = 0.04 + (((double)((i * 7 + 13) % 11)) / 250.0);
            if (i >= 29 && i <= 36) {
                // FT8 digital audio carrier block
                baseNoise += 0.72 * (1.0 - fabs(i - 32.5) / 5.5);
            }
            if (amps) [amps addObject:@(fmin(0.95, fmax(0.02, baseNoise)))];
        }
        _spectrumAmplitudes = [amps copy];
    }
    return self;
}

- (id)copyWithZone:(nullable NSZone *)zone {
    TX500ScreenState *copy = [[[self class] allocWithZone:zone] init];
    copy.frequencyHz = self.frequencyHz;
    copy.vfoBFrequencyHz = self.vfoBFrequencyHz;
    copy.activeVFO = self.activeVFO;
    copy.operatingMode = [self.operatingMode copy];
    copy.vfoBMode = [self.vfoBMode copy];
    copy.isTransmitting = self.isTransmitting;
    copy.sMeterDots = self.sMeterDots;
    copy.rfPowerWatts = self.rfPowerWatts;
    copy.swr = self.swr;
    copy.supplyVoltage = self.supplyVoltage;
    copy.batteryPercent = self.batteryPercent;
    copy.isBatteryPowered = self.isBatteryPowered;
    copy.clockString = [self.clockString copy];
    copy.vfoStep = [self.vfoStep copy];
    copy.isLocked = self.isLocked;
    copy.agcDelay = self.agcDelay;
    copy.highTempAlert = self.highTempAlert;
    copy.ritActive = self.ritActive;
    copy.xitActive = self.xitActive;
    copy.ritOffsetHz = self.ritOffsetHz;
    copy.filterNumber = self.filterNumber;
    copy.filterName = [self.filterName copy];
    copy.filterBandwidthHz = self.filterBandwidthHz;
    copy.filterBandwidthString = [self.filterBandwidthString copy];
    copy.afGainLevel = self.afGainLevel;
    copy.rfGainLevel = self.rfGainLevel;
    copy.squelchLevel = self.squelchLevel;
    copy.noiseReduction = self.noiseReduction;
    copy.noiseBlanker = self.noiseBlanker;
    copy.notchFilter = self.notchFilter;
    copy.attenuator = self.attenuator;
    copy.preamp = self.preamp;
    copy.vox = self.vox;
    copy.compressor = self.compressor;
    copy.virtualIF = self.virtualIF;
    copy.monitor = self.monitor;
    copy.split = self.split;
    copy.squelchActive = self.squelchActive;
    copy.topSoftKeyLabels = [self.topSoftKeyLabels copy];
    copy.topSoftKeyValues = [self.topSoftKeyValues copy];
    copy.spectrumAmplitudes = [self.spectrumAmplitudes copy];
    copy.filledSpectrumBars = self.filledSpectrumBars;
    copy.softKeyLabels = [self.softKeyLabels copy];
    return copy;
}

+ (instancetype)defaultDemoState {
    return [[self alloc] init];
}

@end
