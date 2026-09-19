#import <Foundation/Foundation.h>
#import "Lab599SerialPort.h"

NS_ASSUME_NONNULL_BEGIN

@interface TXRollingAverages : NSObject <NSCopying>
@property (nonatomic, assign) double avg5m;
@property (nonatomic, assign) double avg15m;
@property (nonatomic, assign) double avg30m;
@property (nonatomic, assign) double avg60m;
@property (nonatomic, assign) BOOL hasData;
@end

@interface TXTelemetryData : NSObject <NSCopying>

@property (nonatomic, assign) double voltage;            // Volts (9.0 - 15.0V)
@property (nonatomic, assign) BOOL voltageValid;          // YES only after a real VL; reply (or demo sample)
@property (nonatomic, assign) double currentAmps;         // Reserved until CAT exposes a real current measurement
@property (nonatomic, assign) BOOL currentValid;
@property (nonatomic, assign) double rfPowerWatts;        // Configured TX power from PC; (1.0 - 10.0W), not measured RF
@property (nonatomic, assign) BOOL rfPowerValid;
@property (nonatomic, assign) double swr;                 // Engineering SWR ratio, currently unavailable in live CAT
@property (nonatomic, assign) BOOL swrValid;
@property (nonatomic, assign) NSInteger swrMeterDots;     // Raw documented RM1 meter value (0 - 30 dots)
@property (nonatomic, assign) BOOL swrMeterValid;
@property (nonatomic, assign) double temperatureCelsius;  // Reserved until CAT exposes a real PA temperature
@property (nonatomic, assign) BOOL temperatureValid;
@property (nonatomic, assign) uint64_t frequencyHz;       // Frequency in Hz
@property (nonatomic, assign) BOOL frequencyValid;
@property (nonatomic, copy) NSString *operatingMode;      // "USB", "DIG", "CW", "LSB", "AM", "FM"
@property (nonatomic, assign) BOOL modeValid;
@property (nonatomic, assign) BOOL isTransmitting;        // YES if radio is in TX mode
@property (nonatomic, assign) BOOL txStateValid;
@property (nonatomic, assign) NSInteger sMeterDots;       // 0 to 30 dots
@property (nonatomic, assign) BOOL sMeterValid;            // SM0 is S-meter in RX, power meter in TX
@property (nonatomic, assign) NSInteger batteryPercent;   // Estimated 0 - 100% for 3S Li-ion
@property (nonatomic, assign, readonly) BOOL isBatteryPackPowered; // YES if voltage <= 12.8V and > 7.0V (BP-500 / BP-550)
@property (nonatomic, assign, readonly) BOOL isExternalDCPowered;  // YES if voltage > 13.0V (13.8V External DC)
@property (nonatomic, assign) BOOL overvoltageAlert;      // Voltage > 15.0V
@property (nonatomic, assign) BOOL lowVoltageAlert;       // Voltage < 9.5V
@property (nonatomic, assign) BOOL highSWRAlert;          // SWR >= 3.0
@property (nonatomic, assign) BOOL overtempAlert;         // Temp > 60.0°C

// Rolling averages across 5m, 15m, 30m, and 60m
@property (nonatomic, strong) TXRollingAverages *voltageAverages;
@property (nonatomic, strong) TXRollingAverages *currentAverages;
@property (nonatomic, strong) TXRollingAverages *rfPowerAverages;
@property (nonatomic, strong) TXRollingAverages *swrAverages;
@property (nonatomic, strong) TXRollingAverages *temperatureAverages;

- (void)evaluateAlarms;
- (NSString *)powerSourceDescription;

@end

typedef void (^TXTelemetryUpdateHandler)(TXTelemetryData *data);
typedef void (^TXTelemetryStatusHandler)(NSString *status, BOOL isConnected);

@interface TX500TelemetryEngine : NSObject

@property (nonatomic, assign, readonly) BOOL isRunning;
@property (nonatomic, assign) BOOL demoMode;
@property (nonatomic, assign) NSTimeInterval pollInterval; // Default: 0.25s (250ms)
@property (nonatomic, copy, nullable) NSString *serialPortPath;

- (void)startWithPort:(nullable NSString *)portPath
             interval:(NSTimeInterval)interval
               update:(TXTelemetryUpdateHandler)updateBlock
               status:(nullable TXTelemetryStatusHandler)statusBlock;

- (void)stop;

// Simulation step
- (void)stepDemo:(TXTelemetryData *)data;

// Protocol frame parsers (public for unit testing)
+ (BOOL)parseIFReply:(NSString *)reply intoData:(TXTelemetryData *)data;
+ (BOOL)parseFAReply:(NSString *)reply intoData:(TXTelemetryData *)data;
+ (BOOL)parseMDReply:(NSString *)reply intoData:(TXTelemetryData *)data;
+ (BOOL)parsePTReply:(NSString *)reply intoData:(TXTelemetryData *)data;
+ (BOOL)parsePCReply:(NSString *)reply intoData:(TXTelemetryData *)data;
+ (BOOL)parseRMReply:(NSString *)reply intoData:(TXTelemetryData *)data;
+ (BOOL)parseSMReply:(NSString *)reply intoData:(TXTelemetryData *)data;
+ (BOOL)parseVLReply:(NSString *)reply intoData:(TXTelemetryData *)data;

@end

NS_ASSUME_NONNULL_END
