#import <Cocoa/Cocoa.h>

// Owns CAT, Settings and Memory UI; serial engines remain UI-independent.
@interface Lab599ToolsController : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@property(nonatomic, strong, readonly) NSView *view;
@property(nonatomic, weak) NSWindow *window;
@property(nonatomic, copy) NSString *(^selectedPort)(void);
@property(nonatomic, copy) void (^activityChanged)(BOOL busy);
@property(nonatomic, copy) void (^statusChanged)(NSString *text, double progress);
@property(nonatomic, copy) void (^log)(NSString *message);
- (void)selectTool:(NSInteger)tool; // CAT=0, Settings=1, Memory=2
- (void)portsAvailable:(BOOL)available;
- (BOOL)confirmDiscard;
@end
