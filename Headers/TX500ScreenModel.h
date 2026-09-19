#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TX500ScreenTheme) {
    TX500ScreenThemeAmber = 0,     // Authentic Lab599 warm amber/orange backlight
    TX500ScreenThemeCoolWhite = 1, // Transflective daylight crisp monochrome (as in real photo)
    TX500ScreenThemeGreen = 2,     // Military / night-vision tactical emerald green
    TX500ScreenThemeOLED = 3       // High-contrast inverted black & phosphor white
};

@interface TX500ScreenState : NSObject <NSCopying>

// Frequencies & Modes
@property (nonatomic, assign) uint64_t frequencyHz;
@property (nonatomic, assign) uint64_t vfoBFrequencyHz;
@property (nonatomic, assign) NSInteger activeVFO; // 0 = VFO A, 1 = VFO B
@property (nonatomic, copy) NSString *operatingMode; // "USB", "LSB", "CW", "CWR", "DIG", "AM", "FM"
@property (nonatomic, copy) NSString *vfoBMode;      // e.g. "CWR", "USB", "CW", "LSB"
@property (nonatomic, assign) BOOL isTransmitting;

// Signal & Meters
@property (nonatomic, assign) NSInteger sMeterDots; // 0 to 30 dots
@property (nonatomic, assign) double rfPowerWatts;  // 0.0 to 10.0 W
@property (nonatomic, assign) double swr;           // 1.0 to 5.0

// Supply & Battery
@property (nonatomic, assign) double supplyVoltage; // Volts (9.0 - 15.0V)
@property (nonatomic, assign) NSInteger batteryPercent; // 0 - 100%
@property (nonatomic, assign) BOOL isBatteryPowered;

// Clock & Tuning Status
@property (nonatomic, copy) NSString *clockString; // e.g. "18:32"
@property (nonatomic, copy) NSString *vfoStep;     // e.g. "100 Hz", "10 Hz", "1 kHz"
@property (nonatomic, assign) BOOL isLocked;       // VFO lock
@property (nonatomic, assign) NSInteger agcDelay;  // 1 to 10 (e.g. AGC 10)
@property (nonatomic, assign) BOOL highTempAlert;

// RIT & XIT
@property (nonatomic, assign) BOOL ritActive;
@property (nonatomic, assign) BOOL xitActive;
@property (nonatomic, assign) NSInteger ritOffsetHz; // e.g. +120, -50

// Filter & Audio
@property (nonatomic, assign) NSInteger filterNumber; // 1 to 4
@property (nonatomic, copy) NSString *filterName;     // e.g. "FIL-1", "FIL-2"
@property (nonatomic, assign) NSInteger filterBandwidthHz; // e.g. 3100, 2400, 500
@property (nonatomic, copy) NSString *filterBandwidthString; // e.g. "3.10k", "2.40k"
@property (nonatomic, assign) NSInteger afGainLevel; // 0 to 100 (e.g. AF64)
@property (nonatomic, assign) NSInteger rfGainLevel; // 0 to 100 (e.g. RF0)
@property (nonatomic, assign) NSInteger squelchLevel; // 0 to 100

// DSP & Feature Flags
@property (nonatomic, assign) BOOL noiseReduction; // NR
@property (nonatomic, assign) BOOL noiseBlanker;   // NB
@property (nonatomic, assign) BOOL notchFilter;    // NOTCH / NF
@property (nonatomic, assign) BOOL attenuator;     // ATT (20dB)
@property (nonatomic, assign) BOOL preamp;         // PRE
@property (nonatomic, assign) BOOL vox;            // VOX
@property (nonatomic, assign) BOOL compressor;     // CMP / CMR
@property (nonatomic, assign) BOOL virtualIF;      // DIF
@property (nonatomic, assign) BOOL monitor;        // MON
@property (nonatomic, assign) BOOL split;          // SPL
@property (nonatomic, assign) BOOL squelchActive;  // SQL

// Top Soft Key Row (4 physical buttons on top of LCD)
@property (nonatomic, copy) NSArray<NSString *> *topSoftKeyLabels; // e.g. @["CWSPEED", "CWPITCH", "POWER", "VOX"]
@property (nonatomic, copy) NSArray<NSString *> *topSoftKeyValues; // e.g. @["", "", "100", ""]

// Spectrum / Panadapter data (64 normalized amplitude values: 0.0 to 1.0)
@property (nonatomic, copy) NSArray<NSNumber *> *spectrumAmplitudes;
@property (nonatomic, assign) BOOL filledSpectrumBars; // Solid filled bars as on physical radio

// Bottom Soft Key Menu Labels (4 physical buttons at bottom of LCD)
@property (nonatomic, copy) NSArray<NSString *> *softKeyLabels; // e.g. @["<<", "TONE", "MON", ">>"]

+ (instancetype)defaultDemoState;

@end

NS_ASSUME_NONNULL_END
