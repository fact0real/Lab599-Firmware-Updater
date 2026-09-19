#import <Cocoa/Cocoa.h>
#import "TX500TelemetryEngine.h"
#import "TXGaugeView.h"

NS_ASSUME_NONNULL_BEGIN

@interface Lab599TelemetryController : NSObject

@property (nonatomic, strong, readonly) NSView *view;
@property (nonatomic, strong, readonly) TX500TelemetryEngine *engine;
@property (nonatomic, copy, nullable) NSString *(^selectedPortProvider)(void);
@property (nonatomic, copy, nullable) void (^logHandler)(NSString *line);
@property (nonatomic, copy, nullable) void (^onTelemetryData)(TXTelemetryData *data);

- (void)startMonitoring;
- (void)startDemoMonitoring;
- (void)stopMonitoring;

@end

NS_ASSUME_NONNULL_END
