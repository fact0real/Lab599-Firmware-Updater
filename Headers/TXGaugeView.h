#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TXGaugeColorZone) {
    TXGaugeZoneNormal,
    TXGaugeZoneWarning,
    TXGaugeZoneCritical
};

@interface TXGaugeView : NSView

@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *unit;
@property (nonatomic, copy) NSString *valueFormat; // e.g. @"%.1f"
@property (nonatomic, assign) double minValue;
@property (nonatomic, assign) double maxValue;
@property (nonatomic, assign) double currentValue;
@property (nonatomic, assign) double peakValue;
@property (nonatomic, assign) double warningThreshold;
@property (nonatomic, assign) double criticalThreshold;
@property (nonatomic, assign) BOOL invertThresholds; // If true, lower values are critical (e.g. low voltage)
@property (nonatomic, copy, nullable) NSString *alertText;
@property (nonatomic, assign) BOOL isAlertActive;

// Custom nominal range (for drawing color arcs)
@property (nonatomic, assign) double greenStart;
@property (nonatomic, assign) double greenEnd;
@property (nonatomic, assign) double yellowStart;
@property (nonatomic, assign) double yellowEnd;
@property (nonatomic, assign) double redStart;
@property (nonatomic, assign) double redEnd;

@property (nonatomic, copy, nullable) NSString *subBadge;

// Rolling Averages across 5m, 15m, 30m, 60m
@property (nonatomic, assign) double avg5m;
@property (nonatomic, assign) double avg15m;
@property (nonatomic, assign) double avg30m;
@property (nonatomic, assign) double avg60m;
@property (nonatomic, assign) BOOL hasAverages;
@property (nonatomic, assign) NSInteger selectedAvgWindow; // 0=5m, 1=15m, 2=30m, 3=60m, -1=none

- (instancetype)initWithTitle:(NSString *)title
                         unit:(NSString *)unit
                          min:(double)min
                          max:(double)max
                       format:(NSString *)format;

- (void)setValue:(double)value animated:(BOOL)animated;
- (void)setAverages5m:(double)m5 m15:(double)m15 m30:(double)m30 m60:(double)m60;
- (void)resetPeak;

@end

NS_ASSUME_NONNULL_END
