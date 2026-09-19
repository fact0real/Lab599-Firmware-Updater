#import <Cocoa/Cocoa.h>

@interface Lab599DocItem : NSObject
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *category;
@property(nonatomic, copy) NSString *fileFormat;
@property(nonatomic, copy) NSString *fileSizeString;
@property(nonatomic, copy) NSString *details;
@property(nonatomic, strong) NSURL *downloadURL;
@property(nonatomic, copy) NSString *localPath;
@property(nonatomic, readonly) BOOL isLocalAvailable;
@property(nonatomic, readonly) NSString *filename;
@end

@interface Lab599DocsController : NSObject <NSTableViewDataSource, NSTableViewDelegate>

@property(nonatomic, strong, readonly) NSView *view;
@property(nonatomic, weak) NSWindow *window;
@property(nonatomic, copy) void (^log)(NSString *message);
@property(nonatomic, copy) void (^statusChanged)(NSString *text, double progress);
@property(nonatomic, copy) void (^activityChanged)(BOOL busy);

- (void)fetchCatalogFromWeb;
- (void)refreshLocalAvailability;
- (NSArray<Lab599DocItem *> *)builtInDocumentationCatalog;
- (NSArray<Lab599DocItem *> *)parseItemsFromHTML:(NSString *)html;

@end
