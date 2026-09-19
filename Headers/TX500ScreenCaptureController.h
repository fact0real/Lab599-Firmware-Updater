#import <Cocoa/Cocoa.h>
#import "TX500ScreenModel.h"
#import "TX500ScreenRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@interface TX500ScreenCaptureController : NSObject

@property (nonatomic, strong, readonly) NSView *view;
@property (nonatomic, weak, nullable) NSWindow *window;
@property (nonatomic, copy, nullable) NSString *(^selectedPortProvider)(void);
@property (nonatomic, copy, nullable) void (^logHandler)(NSString *line);
@property (nonatomic, copy, nullable) void (^statusHandler)(NSString *line, double progress);

// State & Appearance
@property (nonatomic, strong) TX500ScreenState *screenState;
@property (nonatomic, assign) TX500ScreenTheme currentTheme;
@property (nonatomic, assign) BOOL showChassisBezel;
@property (nonatomic, assign) BOOL showPixelGrid;
@property (nonatomic, assign) CGFloat displayScale;
@property (nonatomic, assign) BOOL liveSyncActive;
@property (nonatomic, assign) BOOL demoModeActive;
@property (nonatomic, assign) CGFloat tuneAngle;
@property (nonatomic, assign) CGFloat afGainAngle;
@property (nonatomic, assign) NSInteger pressedTag;

// Actions
- (void)renderAndUpdateDisplay;
- (void)handleChassisControlPress:(TX500ChassisControlTag)tag atChassisPoint:(NSPoint)pt;
- (void)handleTuneKnobDelta:(CGFloat)delta;
- (void)handleAFGainKnobDelta:(CGFloat)delta;
- (void)startLiveSync;
- (void)stopLiveSync;
- (void)startDemoTimer;
- (void)refreshSnapshotFromRadio;
- (void)copyScreenshotToClipboard;
- (void)saveScreenshotDialog;

@end

NS_ASSUME_NONNULL_END
