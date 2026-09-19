#import <Cocoa/Cocoa.h>

@interface Lab599FeedbackController : NSObject

@property(nonatomic, strong, readonly) NSView *view;
@property(nonatomic, weak) NSWindow *window;
@property(nonatomic, copy) NSString *(^selectedPortProvider)(void);
@property(nonatomic, copy) void (^log)(NSString *message);
@property(nonatomic, copy) void (^statusChanged)(NSString *text, double progress);

// Interactive UI elements exposed for testing and interaction
@property(nonatomic, strong, readonly) NSSegmentedControl *categoryPicker;
@property(nonatomic, strong, readonly) NSSegmentedControl *priorityPicker;
@property(nonatomic, strong, readonly) NSTextField *callsignField;
@property(nonatomic, strong, readonly) NSTextField *contactField;
@property(nonatomic, strong, readonly) NSTextField *titleField;
@property(nonatomic, strong, readonly) NSTextView *detailsView;
@property(nonatomic, strong, readonly) NSButton *diagnosticsCheckbox;
@property(nonatomic, strong, readonly) NSTextView *diagnosticsView;

- (void)refreshDiagnostics;
- (NSString *)generateIssueMarkdown;
- (NSURL *)generateGitHubIssueURL;
- (void)copyMarkdownToClipboard;
- (void)openGitHubIssue;
- (void)clearForm;

@end
