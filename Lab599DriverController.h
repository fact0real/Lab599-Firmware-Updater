#import <Cocoa/Cocoa.h>

@interface Lab599DriverController : NSObject

@property(nonatomic, strong, readonly) NSView *view;
@property(nonatomic, weak) NSWindow *window;
@property(nonatomic, copy) void (^log)(NSString *message);
@property(nonatomic, copy) void (^statusChanged)(NSString *text, double progress);
@property(nonatomic, copy) void (^activityChanged)(BOOL busy);

- (void)checkDriverStatus;
- (void)refreshDevices;
- (NSImage *)loadRadioImage;

@end
