#import "Lab599DocsController.h"

@implementation Lab599DocItem
- (NSString *)filename {
    return self.downloadURL.lastPathComponent ?: @"file";
}
- (BOOL)isLocalAvailable {
    return self.localPath != nil && [[NSFileManager defaultManager] fileExistsAtPath:self.localPath];
}
@end

@interface Lab599DocsController () <NSURLSessionDownloadDelegate>
@property(nonatomic, strong, readwrite) NSView *view;
@property(nonatomic, strong) NSPopUpButton *categoryPopup;
@property(nonatomic, strong) NSSearchField *searchField;
@property(nonatomic, strong) NSTableView *tableView;
@property(nonatomic, strong) NSTextField *detailsLabel;
@property(nonatomic, strong) NSTextField *urlLabel;
@property(nonatomic, strong) NSProgressIndicator *downloadProgress;
@property(nonatomic, strong) NSTextField *downloadStatus;
@property(nonatomic, strong) NSButton *downloadButton;
@property(nonatomic, strong) NSButton *openLocalButton;
@property(nonatomic, strong) NSButton *openBrowserButton;
@property(nonatomic, strong) NSButton *refreshButton;

@property(nonatomic, strong) NSArray<Lab599DocItem *> *allItems;
@property(nonatomic, strong) NSArray<Lab599DocItem *> *filteredItems;
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSURLSessionDownloadTask *activeDownloadTask;
@property(nonatomic, strong) NSURL *currentDownloadDestination;
@property(nonatomic, strong) Lab599DocItem *currentlyDownloadingItem;
@end

@implementation Lab599DocsController

static NSTextField *Label(NSString *text, BOOL bold, CGFloat size, NSColor *color) {
    NSTextField *field = [NSTextField wrappingLabelWithString:text];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.font = bold ? [NSFont systemFontOfSize:size weight:NSFontWeightBold] :
                        [NSFont systemFontOfSize:size weight:NSFontWeightRegular];
    if (color) field.textColor = color;
    return field;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    config.timeoutIntervalForRequest = 25.0;
    self.session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:[NSOperationQueue mainQueue]];

    self.allItems = [self builtInDocumentationCatalog];
    [self checkLocalCopiesForItems:self.allItems];
    self.filteredItems = self.allItems;

    [self buildUI];
    [self fetchCatalogFromWeb];
    return self;
}

- (void)buildUI {
    self.view = [NSView new];
    self.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view.heightAnchor constraintEqualToConstant:410].active = YES;

    NSTextField *title = Label(@"Official Lab599 Documentation & Downloads", YES, 15, NSColor.labelColor);
    NSTextField *sub = Label(@"Browse, search, and download official manuals, firmware releases, utilities, and drivers from lab599.com and lab599.ru.", NO, 12, NSColor.secondaryLabelColor);

    // Filter controls
    self.categoryPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.categoryPopup.translatesAutoresizingMaskIntoConstraints = NO;
    [self.categoryPopup addItemsWithTitles:@[
        @"All Categories",
        @"Manuals & Guides (PDF)",
        @"Transceiver Firmware (.fw)",
        @"Software & Utilities",
        @"Drivers"
    ]];
    self.categoryPopup.target = self;
    self.categoryPopup.action = @selector(filterChanged:);

    self.searchField = [[NSSearchField alloc] initWithFrame:NSZeroRect];
    self.searchField.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchField.placeholderString = @"Search by title or filename...";
    self.searchField.target = self;
    self.searchField.action = @selector(filterChanged:);

    self.refreshButton = [NSButton buttonWithTitle:@"Refresh from Web" target:self action:@selector(refreshFromWebClicked:)];
    self.refreshButton.bezelStyle = NSBezelStyleRounded;

    NSStackView *filterRow = [NSStackView stackViewWithViews:@[
        Label(@"Category:", NO, 12, NSColor.labelColor),
        self.categoryPopup,
        self.searchField,
        self.refreshButton
    ]];
    filterRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    filterRow.alignment = NSLayoutAttributeCenterY;
    filterRow.spacing = 10;
    [self.categoryPopup.widthAnchor constraintEqualToConstant:190].active = YES;
    [self.searchField.widthAnchor constraintEqualToConstant:230].active = YES;

    // Table view
    self.tableView = [NSTableView new];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.rowHeight = 22;
    self.tableView.usesAlternatingRowBackgroundColors = YES;
    self.tableView.allowsMultipleSelection = NO;

    NSTableColumn *cTitle = [[NSTableColumn alloc] initWithIdentifier:@"title"];
    cTitle.title = @"Document / Item Name";
    cTitle.width = 320;
    [self.tableView addTableColumn:cTitle];

    NSTableColumn *cCat = [[NSTableColumn alloc] initWithIdentifier:@"category"];
    cCat.title = @"Category";
    cCat.width = 150;
    [self.tableView addTableColumn:cCat];

    NSTableColumn *cFmt = [[NSTableColumn alloc] initWithIdentifier:@"format"];
    cFmt.title = @"Format";
    cFmt.width = 65;
    [self.tableView addTableColumn:cFmt];

    NSTableColumn *cSize = [[NSTableColumn alloc] initWithIdentifier:@"size"];
    cSize.title = @"Size";
    cSize.width = 75;
    [self.tableView addTableColumn:cSize];

    NSTableColumn *cStat = [[NSTableColumn alloc] initWithIdentifier:@"status"];
    cStat.title = @"Status";
    cStat.width = 110;
    [self.tableView addTableColumn:cStat];

    NSScrollView *tableScroll = [NSScrollView new];
    tableScroll.translatesAutoresizingMaskIntoConstraints = NO;
    tableScroll.hasVerticalScroller = YES;
    tableScroll.borderType = NSBezelBorder;
    tableScroll.documentView = self.tableView;
    [tableScroll.heightAnchor constraintEqualToConstant:175].active = YES;

    // Details box
    self.detailsLabel = Label(@"Select an item above to view details.", NO, 11, NSColor.labelColor);
    self.urlLabel = Label(@"", NO, 11, NSColor.secondaryLabelColor);
    self.urlLabel.selectable = YES;
    self.urlLabel.font = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular];

    NSStackView *detailsStack = [NSStackView stackViewWithViews:@[self.detailsLabel, self.urlLabel]];
    detailsStack.translatesAutoresizingMaskIntoConstraints = NO;
    detailsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    detailsStack.alignment = NSLayoutAttributeLeading;
    detailsStack.spacing = 3;

    // Progress
    self.downloadProgress = [NSProgressIndicator new];
    self.downloadProgress.translatesAutoresizingMaskIntoConstraints = NO;
    self.downloadProgress.minValue = 0.0;
    self.downloadProgress.maxValue = 1.0;
    self.downloadProgress.indeterminate = NO;
    self.downloadProgress.hidden = YES;

    self.downloadStatus = Label(@"", NO, 11, NSColor.secondaryLabelColor);
    self.downloadStatus.hidden = YES;

    // Action buttons
    self.downloadButton = [NSButton buttonWithTitle:@"Download & Save As..." target:self action:@selector(downloadSelected:)];
    self.downloadButton.bezelStyle = NSBezelStyleRounded;
    self.downloadButton.enabled = NO;

    self.openLocalButton = [NSButton buttonWithTitle:@"Open Local File" target:self action:@selector(openLocalSelected:)];
    self.openLocalButton.bezelStyle = NSBezelStyleRounded;
    self.openLocalButton.enabled = NO;

    self.openBrowserButton = [NSButton buttonWithTitle:@"Open in Browser" target:self action:@selector(openInBrowserSelected:)];
    self.openBrowserButton.bezelStyle = NSBezelStyleRounded;
    self.openBrowserButton.enabled = NO;

    NSStackView *buttonRow = [NSStackView stackViewWithViews:@[
        self.downloadButton, self.openLocalButton, self.openBrowserButton
    ]];
    buttonRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttonRow.spacing = 10;
    buttonRow.alignment = NSLayoutAttributeCenterY;

    NSStackView *mainStack = [NSStackView stackViewWithViews:@[
        title, sub, filterRow, tableScroll, detailsStack,
        self.downloadProgress, self.downloadStatus, buttonRow
    ]];
    mainStack.translatesAutoresizingMaskIntoConstraints = NO;
    mainStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    mainStack.alignment = NSLayoutAttributeLeading;
    mainStack.spacing = 8;
    mainStack.detachesHiddenViews = YES;

    [self.view addSubview:mainStack];

    [NSLayoutConstraint activateConstraints:@[
        [mainStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [mainStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [mainStack.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [mainStack.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [filterRow.widthAnchor constraintEqualToAnchor:mainStack.widthAnchor],
        [tableScroll.widthAnchor constraintEqualToAnchor:mainStack.widthAnchor],
        [detailsStack.widthAnchor constraintEqualToAnchor:mainStack.widthAnchor],
        [self.downloadProgress.widthAnchor constraintEqualToAnchor:mainStack.widthAnchor],
        [self.downloadStatus.widthAnchor constraintEqualToAnchor:mainStack.widthAnchor]
    ]];

    [self.tableView reloadData];
}

- (void)checkLocalCopiesForItems:(NSArray<Lab599DocItem *> *)items {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *home = NSHomeDirectory();
    NSArray<NSString *> *searchDirs = @[
        @"/Users/factoreal/Downloads/TX-500",
        @"/Users/factoreal/Downloads/TX-500/Manual",
        [home stringByAppendingPathComponent:@"Downloads"],
        @"Manual",
        @".."
    ];

    for (Lab599DocItem *item in items) {
        NSString *fname = item.filename;
        item.localPath = nil;
        for (NSString *dir in searchDirs) {
            NSString *candidate = [dir stringByAppendingPathComponent:fname];
            if ([fm fileExistsAtPath:candidate]) {
                item.localPath = candidate;
                break;
            }
        }
    }
}

- (void)filterChanged:(id)sender {
    (void)sender;
    NSInteger catIdx = self.categoryPopup.indexOfSelectedItem;
    NSString *search = [self.searchField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].lowercaseString;

    NSMutableArray<Lab599DocItem *> *filtered = [NSMutableArray array];
    for (Lab599DocItem *item in self.allItems) {
        BOOL catMatch = YES;
        if (catIdx == 1 && ![item.category isEqualToString:@"Manuals & Guides"]) catMatch = NO;
        else if (catIdx == 2 && ![item.category isEqualToString:@"Firmware"]) catMatch = NO;
        else if (catIdx == 3 && ![item.category isEqualToString:@"Software & Tools"]) catMatch = NO;
        else if (catIdx == 4 && ![item.category isEqualToString:@"Drivers"]) catMatch = NO;

        if (!catMatch) continue;

        if (search.length > 0) {
            BOOL textMatch = [item.title.lowercaseString containsString:search] ||
                             [item.filename.lowercaseString containsString:search] ||
                             [item.details.lowercaseString containsString:search];
            if (!textMatch) continue;
        }

        [filtered addObject:item];
    }
    self.filteredItems = filtered;
    [self.tableView reloadData];
    [self updateSelectionDetails];
}

- (void)updateSelectionDetails {
    NSInteger row = self.tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)self.filteredItems.count) {
        self.detailsLabel.stringValue = @"Select an item above to view details.";
        self.urlLabel.stringValue = @"";
        self.downloadButton.enabled = NO;
        self.openLocalButton.enabled = NO;
        self.openBrowserButton.enabled = NO;
        return;
    }

    Lab599DocItem *item = self.filteredItems[row];
    NSString *localNote = item.isLocalAvailable ? [NSString stringWithFormat:@"\nLocal file: %@", item.localPath] : @"";
    self.detailsLabel.stringValue = [NSString stringWithFormat:@"%@  [%@, %@]\n%@%@",
        item.title, item.category, item.fileSizeString ?: @"", item.details ?: @"", localNote];
    self.urlLabel.stringValue = item.downloadURL.absoluteString ?: @"";
    self.downloadButton.enabled = YES;
    self.openLocalButton.enabled = item.isLocalAvailable;
    self.openBrowserButton.enabled = item.downloadURL != nil;
}

#pragma mark - Table View Data Source & Delegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    (void)tableView;
    return self.filteredItems.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.filteredItems.count) return nil;
    Lab599DocItem *item = self.filteredItems[row];

    NSTextField *textField = [NSTextField labelWithString:@""];
    textField.translatesAutoresizingMaskIntoConstraints = NO;
    textField.lineBreakMode = NSLineBreakByTruncatingTail;

    if ([tableColumn.identifier isEqualToString:@"title"]) {
        textField.stringValue = item.title;
        textField.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    } else if ([tableColumn.identifier isEqualToString:@"category"]) {
        textField.stringValue = item.category;
        textField.font = [NSFont systemFontOfSize:11];
        textField.textColor = NSColor.secondaryLabelColor;
    } else if ([tableColumn.identifier isEqualToString:@"format"]) {
        textField.stringValue = item.fileFormat;
        textField.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightMedium];
    } else if ([tableColumn.identifier isEqualToString:@"size"]) {
        textField.stringValue = item.fileSizeString ?: @"";
        textField.font = [NSFont systemFontOfSize:11];
        textField.textColor = NSColor.secondaryLabelColor;
    } else if ([tableColumn.identifier isEqualToString:@"status"]) {
        if (item.isLocalAvailable) {
            textField.stringValue = @"● Downloaded";
            textField.textColor = [NSColor systemGreenColor];
        } else {
            textField.stringValue = @"○ Online";
            textField.textColor = NSColor.secondaryLabelColor;
        }
        textField.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    }

    NSTableCellView *cell = [NSTableCellView new];
    cell.textField = textField;
    [cell addSubview:textField];
    [NSLayoutConstraint activateConstraints:@[
        [textField.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
        [textField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
        [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
    ]];
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    (void)notification;
    [self updateSelectionDetails];
}

#pragma mark - Actions

- (void)downloadSelected:(id)sender {
    (void)sender;
    NSInteger row = self.tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)self.filteredItems.count) return;
    Lab599DocItem *item = self.filteredItems[row];
    if (!item.downloadURL) return;

    NSSavePanel *savePanel = [NSSavePanel savePanel];
    savePanel.title = [NSString stringWithFormat:@"Save %@", item.filename];
    savePanel.nameFieldStringValue = item.filename;
    savePanel.canCreateDirectories = YES;

    [savePanel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || !savePanel.URL) return;

        self.currentDownloadDestination = savePanel.URL;
        self.currentlyDownloadingItem = item;

        self.downloadProgress.hidden = NO;
        self.downloadProgress.doubleValue = 0.0;
        self.downloadStatus.hidden = NO;
        self.downloadStatus.stringValue = [NSString stringWithFormat:@"Downloading %@...", item.filename];

        if (self.log) self.log([NSString stringWithFormat:@"Starting download: %@ -> %@", item.downloadURL.absoluteString, savePanel.URL.path]);
        if (self.statusChanged) self.statusChanged([NSString stringWithFormat:@"Downloading %@...", item.filename], 0.1);

        self.activeDownloadTask = [self.session downloadTaskWithURL:item.downloadURL];
        [self.activeDownloadTask resume];
    }];
}

- (void)openLocalSelected:(id)sender {
    (void)sender;
    NSInteger row = self.tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)self.filteredItems.count) return;
    Lab599DocItem *item = self.filteredItems[row];
    if (item.isLocalAvailable) {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:item.localPath]];
        if (self.log) self.log([NSString stringWithFormat:@"Opened local document: %@", item.localPath]);
    }
}

- (void)openInBrowserSelected:(id)sender {
    (void)sender;
    NSInteger row = self.tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)self.filteredItems.count) return;
    Lab599DocItem *item = self.filteredItems[row];
    if (item.downloadURL) {
        [[NSWorkspace sharedWorkspace] openURL:item.downloadURL];
    }
}

- (void)refreshFromWebClicked:(id)sender {
    (void)sender;
    [self fetchCatalogFromWeb];
}

#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    (void)session;
    (void)downloadTask;
    (void)bytesWritten;
    if (totalBytesExpectedToWrite > 0) {
        double p = (double)totalBytesWritten / (double)totalBytesExpectedToWrite;
        self.downloadProgress.doubleValue = p;
        self.downloadStatus.stringValue = [NSString stringWithFormat:@"Downloading %@ (%.0f%%)...",
            self.currentlyDownloadingItem.filename, p * 100.0];
        if (self.statusChanged) self.statusChanged(self.downloadStatus.stringValue, p);
    }
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location {
    (void)session;
    (void)downloadTask;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *err = nil;
    if ([fm fileExistsAtPath:self.currentDownloadDestination.path]) {
        [fm removeItemAtURL:self.currentDownloadDestination error:nil];
    }
    BOOL success = [fm moveItemAtURL:location toURL:self.currentDownloadDestination error:&err];

    self.downloadProgress.hidden = YES;
    self.downloadStatus.hidden = YES;

    if (success) {
        if (self.currentlyDownloadingItem) {
            self.currentlyDownloadingItem.localPath = self.currentDownloadDestination.path;
        }
        if (self.log) self.log([NSString stringWithFormat:@"Download completed successfully: %@", self.currentDownloadDestination.path]);
        if (self.statusChanged) self.statusChanged(@"Download completed.", 1.0);
        [self.tableView reloadData];
        [self updateSelectionDetails];

        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Download Complete";
        alert.informativeText = [NSString stringWithFormat:@"Saved to:\n%@", self.currentDownloadDestination.path];
        [alert addButtonWithTitle:@"Show in Finder"];
        [alert addButtonWithTitle:@"OK"];
        if ([alert runModal] == NSAlertFirstButtonReturn) {
            [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[self.currentDownloadDestination]];
        }
    } else {
        if (self.log) self.log([NSString stringWithFormat:@"Failed to save file: %@", err.localizedDescription]);
        if (self.statusChanged) self.statusChanged(@"Download failed.", 0.0);
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    (void)session;
    (void)task;
    if (error) {
        self.downloadProgress.hidden = YES;
        self.downloadStatus.hidden = YES;
        if (self.log) self.log([NSString stringWithFormat:@"Download error: %@", error.localizedDescription]);
        if (self.statusChanged) self.statusChanged(@"Download failed.", 0.0);
    }
}

#pragma mark - Live Scraping & Multi-Source Catalog
 
- (void)fetchCatalogFromWeb {
    NSArray<NSString *> *endpoints = @[
        @"https://lab599.com/downloads",
        @"https://lab599.ru/downloads"
    ];

    if (self.log) self.log(@"Synchronizing documentation catalog from lab599.com & lab599.ru...");

    dispatch_group_t group = dispatch_group_create();
    NSMutableDictionary<NSString *, Lab599DocItem *> *dict = [NSMutableDictionary dictionary];
    for (Lab599DocItem *it in [self builtInDocumentationCatalog]) {
        dict[it.downloadURL.absoluteString] = it;
    }

    __block BOOL anySuccess = NO;

    for (NSString *urlString in endpoints) {
        dispatch_group_enter(group);
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
        [req setValue:@"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)" forHTTPHeaderField:@"User-Agent"];

        NSURLSessionDataTask *task = [self.session dataTaskWithRequest:req completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            (void)response;
            if (data && !error) {
                NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (!html) html = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
                if (html) {
                    NSArray<Lab599DocItem *> *parsed = [self parseItemsFromHTML:html];
                    @synchronized (dict) {
                        for (Lab599DocItem *it in parsed) {
                            Lab599DocItem *existing = dict[it.downloadURL.absoluteString];
                            if (existing) {
                                if (it.fileSizeString.length > 0) existing.fileSizeString = it.fileSizeString;
                                if (it.details.length > 0) existing.details = it.details;
                            } else {
                                dict[it.downloadURL.absoluteString] = it;
                            }
                        }
                        anySuccess = YES;
                    }
                }
            }
            dispatch_group_leave(group);
        }];
        [task resume];
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        self.allItems = [dict.allValues sortedArrayUsingComparator:^NSComparisonResult(Lab599DocItem *a, Lab599DocItem *b) {
            return [a.title localizedCaseInsensitiveCompare:b.title];
        }];
        [self checkLocalCopiesForItems:self.allItems];
        [self filterChanged:nil];
        if (anySuccess) {
            if (self.log) self.log([NSString stringWithFormat:@"Catalog synchronized from lab599.com & lab599.ru: %lu items available.", (unsigned long)self.allItems.count]);
        } else {
            if (self.log) self.log([NSString stringWithFormat:@"Offline or connection failed. Using comprehensive built-in catalog (%lu items).", (unsigned long)self.allItems.count]);
        }
    });
}

- (NSArray<Lab599DocItem *> *)parseItemsFromHTML:(NSString *)html {
    NSMutableArray<Lab599DocItem *> *items = [NSMutableArray array];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"<a\\s+[^>]*href=[\"'](https?://downloads\\.lab599\\.(?:com|ru)/[^\"'\\s]+?\\.(pdf|zip|fw|dmg|apk|exe|txt))[\"'][^>]*>(.*?)</a>"
                                                                           options:NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators
                                                                             error:nil];
    NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:html options:0 range:NSMakeRange(0, html.length)];

    for (NSTextCheckingResult *m in matches) {
        NSString *urlStr = [html substringWithRange:[m rangeAtIndex:1]];
        NSString *ext = [html substringWithRange:[m rangeAtIndex:2]].lowercaseString;
        NSString *text = [html substringWithRange:[m rangeAtIndex:3]];

        NSString *clean = [text stringByReplacingOccurrencesOfString:@"<[^>]+>" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0, text.length)];
        clean = [clean stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        Lab599DocItem *it = [Lab599DocItem new];
        it.downloadURL = [NSURL URLWithString:urlStr];
        it.fileFormat = ext.uppercaseString;

        if ([clean rangeOfString:@"Kb" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [clean rangeOfString:@"MB" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [clean rangeOfString:@"Мб" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [clean rangeOfString:@"Кб" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            it.fileSizeString = clean;
        }

        if ([ext isEqualToString:@"pdf"] || [ext isEqualToString:@"txt"]) {
            it.category = @"Manuals & Guides";
        } else if ([ext isEqualToString:@"fw"]) {
            it.category = @"Firmware";
        } else if ([ext isEqualToString:@"zip"] || [ext isEqualToString:@"apk"]) {
            if ([urlStr containsString:@"FTDI"] || [urlStr containsString:@"Driver"]) {
                it.category = @"Drivers";
            } else {
                it.category = @"Software & Tools";
            }
        } else if ([ext isEqualToString:@"exe"] || [ext isEqualToString:@"dmg"]) {
            it.category = @"Drivers";
        } else {
            it.category = @"Other";
        }

        it.title = [self humanTitleForFilename:it.filename category:it.category];
        [items addObject:it];
    }
    return items;
}

- (NSString *)humanTitleForFilename:(NSString *)fname category:(NSString *)cat {
    // English & International Manuals
    if ([fname isEqualToString:@"Lab599-CAT-protocol-r3.pdf"]) return @"Lab599 CAT Protocol Specification (Rev 3)";
    if ([fname isEqualToString:@"Lab599-CAT-protocol.pdf"]) return @"Lab599 CAT Protocol Specification (Rev 1)";
    if ([fname isEqualToString:@"Lab599-TX500-User-Manual-EN-FW-v1.2.pdf"]) return @"TX-500 Discovery User Manual (English, FW v1.2)";
    if ([fname isEqualToString:@"Lab599-TX500MP-User-Manual-EN.pdf"]) return @"TX-500MP User Manual (English)";
    if ([fname isEqualToString:@"Lab599-BP550-User-Manual-EN.pdf"]) return @"BP-550 Battery Pack User Manual (English)";
    if ([fname isEqualToString:@"Lab599-DS550-User-Manual-EN.pdf"]) return @"DS-550 Desk Stand User Manual (English)";
    if ([fname isEqualToString:@"Lab599-BP-500-User-Manual-EN.pdf"]) return @"BP-500 Battery Pack User Manual (English)";
    if ([fname isEqualToString:@"Lab599-TX500-DIG-mode-setup-EN.pdf"]) return @"TX-500 Digital Modes Setup Guide (English)";
    if ([fname isEqualToString:@"Lab599-TX500-adapters-wiring-diagram.pdf"]) return @"TX-500 Adapters Wiring Diagram";
    if ([fname isEqualToString:@"Discovery-TX500-Block-Diagram.pdf"]) return @"TX-500 Discovery System Block Diagram";
    if ([fname isEqualToString:@"Lab599-EU-declaration-of-conformity.pdf"]) return @"Lab599 EU Declaration of Conformity (CE)";
    if ([fname isEqualToString:@"Lab599-Product-Catalog-2025-EN.pdf"]) return @"Lab599 Full Product Catalog 2025 (English)";
    if ([fname isEqualToString:@"Discovery-TX500-promo.pdf"]) return @"TX-500 Discovery Product Brochure";
    if ([fname isEqualToString:@"Lab599-TX500-User-Manual-ES-v02-2021.pdf"]) return @"TX-500 User Manual (Spanish)";
    if ([fname isEqualToString:@"Lab599-TX500-User-Manual-FR-v08-2020.pdf"]) return @"TX-500 User Manual (French)";

    // Russian & PRO Manuals (from lab599.ru)
    if ([fname isEqualToString:@"Lab599-TX500PRO-User-Manual-v1-22.pdf"]) return @"TX-500PRO User Manual (v1.22)";
    if ([fname isEqualToString:@"Lab599-TX500PRO-ALTAI-User-Manual-v1-22.pdf"]) return @"TX-500PRO ALTAI User Manual (v1.22)";
    if ([fname isEqualToString:@"RHM-7350-Antenna-User-Manual-RU.pdf"]) return @"RHM-7350 Antenna User Manual (Russian)";
    if ([fname isEqualToString:@"Lab599-BP550-User-Manual-RU.pdf"]) return @"BP-550 Battery Pack User Manual (Russian)";
    if ([fname isEqualToString:@"Lab599-DS550-User-Manual-RU.pdf"]) return @"DS-550 Desk Stand User Manual (Russian)";
    if ([fname isEqualToString:@"Lab599-TX500-User-Manual-RU-FW-v1.2.pdf"]) return @"TX-500 Discovery User Manual (Russian, FW v1.2)";
    if ([fname isEqualToString:@"Lab599-TX500MP-User-Manual-RU.pdf"]) return @"TX-500MP User Manual (Russian)";
    if ([fname isEqualToString:@"Lab599-TX500-DIG-mode-setup-RU.pdf"]) return @"TX-500 Digital Modes Setup Guide (Russian)";
    if ([fname isEqualToString:@"Lab599-Product-Catalog-2025-RU.pdf"]) return @"Lab599 Full Product Catalog 2025 (Russian)";
    if ([fname isEqualToString:@"TX500-Changelog-EN.txt"]) return @"TX-500 Firmware Changelog (English)";
    if ([fname isEqualToString:@"TX500-Changelog-RU.txt"]) return @"TX-500 Firmware Changelog (Russian)";
    if ([fname isEqualToString:@"TX500MP-Changelog-EN.txt"]) return @"TX-500MP Firmware Changelog (English)";
    if ([fname isEqualToString:@"TX500MP-Changelog-RU.txt"]) return @"TX-500MP Firmware Changelog (Russian)";

    // Firmware
    if ([fname hasPrefix:@"mtrx_alt"]) return [NSString stringWithFormat:@"TX-500PRO ALTAI Firmware %@", [fname stringByDeletingPathExtension]];
    if ([fname hasPrefix:@"mtrx_pro"]) return [NSString stringWithFormat:@"TX-500PRO Firmware %@", [fname stringByDeletingPathExtension]];
    if ([fname hasPrefix:@"mtrxMP"]) return [NSString stringWithFormat:@"TX-500MP Firmware %@", [fname stringByDeletingPathExtension]];
    if ([fname hasPrefix:@"mtrx"]) return [NSString stringWithFormat:@"TX-500 Discovery Firmware %@", [fname stringByDeletingPathExtension]];

    // Software & Utilities
    if ([fname isEqualToString:@"Lab599-TRX-TestCAT-1.1-EN.zip"]) return @"CAT Test Utility v1.1 (English)";
    if ([fname isEqualToString:@"Lab599-TRX-TestCAT-1.1-RU.zip"]) return @"CAT Test Utility v1.1 (Russian)";
    if ([fname isEqualToString:@"Lab599-TRX-TimeSync-EN.zip"]) return @"TRX Time Sync Utility (English)";
    if ([fname isEqualToString:@"Lab599-TRX-TimeSync.zip"]) return @"TRX Time Sync Utility (Russian)";
    if ([fname isEqualToString:@"LAB599-TRX-Remote-1.0.3-BETA.apk"]) return @"Lab599 TRX Remote App v1.0.3 BETA (Android)";
    if ([fname isEqualToString:@"Lab599-TRX-Update-EN.zip"]) return @"Firmware Update Utility (English)";
    if ([fname isEqualToString:@"Lab599-TRX-Update-RU.zip"]) return @"Firmware Update Utility (Russian)";
    if ([fname isEqualToString:@"Lab599-TRX-Mem-EN.zip"]) return @"Memory Cells Programming Utility (English)";
    if ([fname isEqualToString:@"Lab599-TRX-Mem-RU.zip"]) return @"Memory Cells Programming Utility (Russian)";
    if ([fname isEqualToString:@"Lab599-TRX-Settings-EN.zip"]) return @"Settings Backup Utility (English)";
    if ([fname isEqualToString:@"Lab599-TRX-Settings-RU.zip"]) return @"Settings Backup Utility (Russian)";

    // Drivers
    if ([fname containsString:@"FTDI"]) return @"FTDI FT232 USB Serial Driver v2.12.28";
    if ([fname containsString:@"Prolific"] || [fname containsString:@"PL2303"]) return @"Prolific PL2303 Driver Installer v1.5.0";

    return [fname stringByDeletingPathExtension];
}

- (void)refreshLocalAvailability {
    [self checkLocalCopiesForItems:self.allItems];
    [self.tableView reloadData];
    [self updateSelectionDetails];
}

- (NSArray<Lab599DocItem *> *)builtInDocumentationCatalog {
    NSMutableArray<Lab599DocItem *> *items = [NSMutableArray array];

    void (^addItem)(NSString *, NSString *, NSString *, NSString *, NSString *, NSString *) =
    ^(NSString *title, NSString *category, NSString *format, NSString *size, NSString *url, NSString *details) {
        Lab599DocItem *it = [Lab599DocItem new];
        it.title = title;
        it.category = category;
        it.fileFormat = format;
        it.fileSizeString = size;
        it.downloadURL = [NSURL URLWithString:url];
        it.details = details;
        [items addObject:it];
    };

    // =========================================================================
    // 1. MANUALS & USER GUIDES (PDF & TXT) - English, Russian, Spanish, French
    // =========================================================================
    addItem(@"TX-500 Discovery User Manual (English, FW v1.2)", @"Manuals & Guides", @"PDF", @"3.3 MB",
            @"https://downloads.lab599.com/TX500/Lab599-TX500-User-Manual-EN-FW-v1.2.pdf",
            @"Complete operational manual for Lab599 TX-500 Discovery transceiver.");
    addItem(@"TX-500 Discovery User Manual (Russian, FW v1.2)", @"Manuals & Guides", @"PDF", @"3.4 MB",
            @"https://downloads.lab599.com/TX500/Lab599-TX500-User-Manual-RU-FW-v1.2.pdf",
            @"Официальное руководство пользователя трансивера Lab599 TX-500 Discovery (на русском языке).");
    addItem(@"TX-500MP Transceiver User Manual (English)", @"Manuals & Guides", @"PDF", @"3.1 MB",
            @"https://downloads.lab599.com/TX500MP/Lab599-TX500MP-User-Manual-EN.pdf",
            @"Official operational manual for the Lab599 TX-500MP military/manpack model.");
    addItem(@"TX-500MP User Manual (Russian)", @"Manuals & Guides", @"PDF", @"3.2 MB",
            @"https://downloads.lab599.com/TX500MP/Lab599-TX500MP-User-Manual-RU.pdf",
            @"Официальное руководство пользователя трансивера Lab599 TX-500MP (на русском языке).");
    addItem(@"TX-500PRO User Manual (v1.22)", @"Manuals & Guides", @"PDF", @"4.2 MB",
            @"https://downloads.lab599.com/TX500PRO/Lab599-TX500PRO-User-Manual-v1-22.pdf",
            @"Официальное руководство пользователя трансивера Lab599 TX-500PRO.");
    addItem(@"TX-500PRO ALTAI User Manual (v1.22)", @"Manuals & Guides", @"PDF", @"4.1 MB",
            @"https://downloads.lab599.com/TX500PRO/Lab599-TX500PRO-ALTAI-User-Manual-v1-22.pdf",
            @"Официальное руководство пользователя трансивера Lab599 TX-500PRO ALTAI.");
    addItem(@"Lab599 CAT Protocol Specification (Rev 3)", @"Manuals & Guides", @"PDF", @"260 KB",
            @"https://downloads.lab599.com/DOCS/Lab599-CAT-protocol-r3.pdf",
            @"Official CAT commands reference specification including TM clock commands.");
    addItem(@"Lab599 CAT Protocol Specification (Rev 1)", @"Manuals & Guides", @"PDF", @"210 KB",
            @"https://downloads.lab599.com/Lab599-CAT-protocol.pdf",
            @"Initial CAT command set reference specification.");
    addItem(@"BP-550 Battery Pack User Manual (English)", @"Manuals & Guides", @"PDF", @"1.0 MB",
            @"https://downloads.lab599.com/BP550/Lab599-BP550-User-Manual-EN.pdf",
            @"Installation and charging guide for BP-550 rechargeable battery pack.");
    addItem(@"BP-550 Battery Pack User Manual (Russian)", @"Manuals & Guides", @"PDF", @"1.1 MB",
            @"https://downloads.lab599.com/BP550/Lab599-BP550-User-Manual-RU.pdf",
            @"Руководство пользователя аккумуляторного блока BP-550.");
    addItem(@"DS-550 Desk Stand User Manual (English)", @"Manuals & Guides", @"PDF", @"850 KB",
            @"https://downloads.lab599.com/DOCS/Lab599-DS550-User-Manual-EN.pdf",
            @"Assembly and operation instructions for DS-550 desktop mounting station.");
    addItem(@"DS-550 Desk Stand User Manual (Russian)", @"Manuals & Guides", @"PDF", @"890 KB",
            @"https://downloads.lab599.com/DS550/Lab599-DS550-User-Manual-RU.pdf",
            @"Руководство пользователя настольной подставки DS-550.");
    addItem(@"BP-500 Battery Pack User Manual (English)", @"Manuals & Guides", @"PDF", @"900 KB",
            @"https://downloads.lab599.com/BP500/Lab599-BP-500-User-Manual-EN.pdf",
            @"User manual for BP-500 battery pack module.");
    addItem(@"RHM-7350 Antenna User Manual (Russian)", @"Manuals & Guides", @"PDF", @"1.8 MB",
            @"https://downloads.lab599.com/DOCS/RHM-7350-Antenna-User-Manual-RU.pdf",
            @"Руководство пользователя портативной антенны RHM-7350.");
    addItem(@"TX-500 Digital Modes Setup Guide (English)", @"Manuals & Guides", @"PDF", @"650 KB",
            @"https://downloads.lab599.com/TX500/Lab599-TX500-DIG-mode-setup-EN.pdf",
            @"Guide for configuring WSJT-X, FT8, JS8Call, and sound interfaces with TX-500.");
    addItem(@"TX-500 Digital Modes Setup Guide (Russian)", @"Manuals & Guides", @"PDF", @"700 KB",
            @"https://downloads.lab599.com/TX500/Lab599-TX500-DIG-mode-setup-RU.pdf",
            @"Настройка TX-500 для работы цифровыми видами связи.");
    addItem(@"TX-500 Adapters Wiring Diagram", @"Manuals & Guides", @"PDF", @"450 KB",
            @"https://downloads.lab599.com/TX500/Lab599-TX500-adapters-wiring-diagram.pdf",
            @"Pinouts and wiring schematics for GX12 connectors, audio cables, and CAT adapters.");
    addItem(@"TX-500 Discovery System Block Diagram", @"Manuals & Guides", @"PDF", @"350 KB",
            @"https://downloads.lab599.com/TX500/Discovery-TX500-Block-Diagram.pdf",
            @"Hardware block diagram illustrating RF stages, DSP, and controller architecture.");
    addItem(@"Lab599 Full Product Catalog 2025 (English)", @"Manuals & Guides", @"PDF", @"6.8 MB",
            @"https://downloads.lab599.com/Lab599-Product-Catalog-2025-EN.pdf",
            @"Official 2025 catalog covering TX-500, TX-500MP, power solutions, and antennas.");
    addItem(@"Lab599 Full Product Catalog 2025 (Russian)", @"Manuals & Guides", @"PDF", @"1.6 MB",
            @"https://downloads.lab599.com/Lab599-Product-Catalog-2025-RU.pdf",
            @"Официальный каталог продукции Lab599 на 2025 год.");
    addItem(@"TX-500 User Manual (Spanish)", @"Manuals & Guides", @"PDF", @"3.2 MB",
            @"https://downloads.lab599.com/TX500/Lab599-TX500-User-Manual-ES-v02-2021.pdf",
            @"Guía del usuario oficial en español para TX-500.");
    addItem(@"TX-500 User Manual (French)", @"Manuals & Guides", @"PDF", @"2.9 MB",
            @"https://downloads.lab599.com/TX500/Lab599-TX500-User-Manual-FR-v08-2020.pdf",
            @"Manuel de l'utilisateur officiel en français pour TX-500.");
    addItem(@"Lab599 EU Declaration of Conformity (CE)", @"Manuals & Guides", @"PDF", @"280 KB",
            @"https://downloads.lab599.com/TX500/Lab599-EU-declaration-of-conformity.pdf",
            @"European Union regulatory compliance certificate.");
    addItem(@"TX-500 Discovery Promotional Brochure", @"Manuals & Guides", @"PDF", @"1.2 MB",
            @"https://downloads.lab599.com/TX500/Discovery-TX500-promo.pdf",
            @"Overview and technical specifications brochure.");
    addItem(@"TX-500 Firmware Changelog (English)", @"Manuals & Guides", @"TXT", @"16 KB",
            @"https://downloads.lab599.com/TX500/TX500-Changelog-EN.txt",
            @"Official English firmware changelog history for TX-500 Discovery.");
    addItem(@"TX-500 Complete Changelog (Russian)", @"Manuals & Guides", @"TXT", @"15 KB",
            @"https://downloads.lab599.com/TX500/TX500-Changelog-RU.txt",
            @"Полный список изменений прошивки TX-500 на русском языке.");
    addItem(@"TX-500MP Firmware Changelog (English)", @"Manuals & Guides", @"TXT", @"12 KB",
            @"https://downloads.lab599.com/TX500MP/TX500MP-Changelog-EN.txt",
            @"Official English firmware changelog history for TX-500MP.");
    addItem(@"TX-500MP Complete Changelog (Russian)", @"Manuals & Guides", @"TXT", @"12 KB",
            @"https://downloads.lab599.com/TX500MP/TX500MP-Changelog-RU.txt",
            @"Полный список изменений прошивки TX-500MP на русском языке.");

    // =========================================================================
    // 2. TRANSCEIVER FIRMWARE (.fw) - Discovery, MP, PRO, ALTAI
    // =========================================================================
    addItem(@"TX-500 Discovery Firmware v1.30.00 (Latest)", @"Firmware", @"FW", @"240 KB",
            @"https://downloads.lab599.com/TX500/mtrx1.30.00.fw",
            @"Latest stable firmware for TX-500 Discovery. Fixes battery indication and CAT response.");
    addItem(@"TX-500 Discovery Firmware v1.29.06", @"Firmware", @"FW", @"240 KB",
            @"https://downloads.lab599.com/TX500/mtrx1.29.06.fw",
            @"Stable release for TX-500 Discovery with band display improvements.");
    addItem(@"TX-500 Discovery Firmware v1.29.01", @"Firmware", @"FW", @"240 KB",
            @"https://downloads.lab599.com/TX500/mtrx1.29.01.fw",
            @"Added spectrum navigation functions and TM time-setting CAT commands.");
    addItem(@"TX-500 Discovery Firmware v1.26.06", @"Firmware", @"FW", @"236 KB",
            @"https://downloads.lab599.com/TX500/mtrx1.26.06.fw",
            @"Discovery firmware maintenance release.");
    addItem(@"TX-500 Discovery Firmware v1.25.06", @"Firmware", @"FW", @"235 KB",
            @"https://downloads.lab599.com/TX500/mtrx1.25.06.fw",
            @"Stable release for TX-500 Discovery.");
    addItem(@"TX-500 Discovery Firmware v1.23.09", @"Firmware", @"FW", @"230 KB",
            @"https://downloads.lab599.com/TX500/mtrx1.23.09.fw",
            @"Stable release for TX-500 Discovery.");
    addItem(@"TX-500 Discovery Firmware v1.16.06", @"Firmware", @"FW", @"230 KB",
            @"https://downloads.lab599.com/TX500/mtrx1.16.06.fw",
            @"Firmware release for TX-500 Discovery.");
    addItem(@"TX-500 Discovery Firmware v1.13.08", @"Firmware", @"FW", @"219 KB",
            @"https://downloads.lab599.com/TX500/mtrx1.13.08.fw",
            @"Firmware release for TX-500 Discovery.");

    addItem(@"TX-500MP Transceiver Firmware v1.30.00 (Latest)", @"Firmware", @"FW", @"224 KB",
            @"https://downloads.lab599.com/TX500MP/mtrxMP1.30.00.fw",
            @"Official firmware for TX-500MP manpack model.");
    addItem(@"TX-500MP HAM-Bands Patch v1.30.00B27", @"Firmware", @"FW", @"224 KB",
            @"https://downloads.lab599.com/TX500MP/mtrxMP1.30.00b27.fw",
            @"Targeted HAM-bands patch for TX-500MP.");
    addItem(@"TX-500MP Transceiver Firmware v1.29.01", @"Firmware", @"FW", @"220 KB",
            @"https://downloads.lab599.com/TX500MP/mtrxMP1.29.01.fw",
            @"Previous stable firmware for TX-500MP.");
    addItem(@"TX-500MP Transceiver Firmware v1.26.06", @"Firmware", @"FW", @"222 KB",
            @"https://downloads.lab599.com/TX500MP/mtrxMP1.26.06.fw",
            @"Stable release for TX-500MP.");
    addItem(@"TX-500MP Transceiver Firmware v1.25.06", @"Firmware", @"FW", @"223 KB",
            @"https://downloads.lab599.com/TX500MP/mtrxMP1.25.06.fw",
            @"Firmware release for TX-500MP.");
    addItem(@"TX-500MP Transceiver Firmware v1.24.23", @"Firmware", @"FW", @"221 KB",
            @"https://downloads.lab599.com/TX500MP/mtrxMP1.24.23.fw",
            @"Firmware release for TX-500MP.");

    addItem(@"TX-500PRO Firmware v1.29.05 (Latest)", @"Firmware", @"FW", @"225 KB",
            @"https://downloads.lab599.com/TX500PRO/mtrx_pro1.29.05.fw",
            @"Latest official release firmware for TX-500PRO.");
    addItem(@"TX-500PRO ALTAI Firmware v1.29.05", @"Firmware", @"FW", @"223 KB",
            @"https://downloads.lab599.com/TX500PRO/mtrx_alt1.29.05.fw",
            @"Official release firmware for TX-500PRO ALTAI edition.");
    addItem(@"TX-500PRO Firmware v1.23.09", @"Firmware", @"FW", @"216 KB",
            @"https://downloads.lab599.com/TX500PRO/mtrx_pro1.23.09.fw",
            @"Stable firmware release for TX-500PRO.");
    addItem(@"TX-500PRO Firmware v1.21.01", @"Firmware", @"FW", @"211 KB",
            @"https://downloads.lab599.com/TX500PRO/mtrx_pro1.21.01.fw",
            @"Previous firmware release for TX-500PRO.");
    addItem(@"TX-500PRO Firmware v1.17.13", @"Firmware", @"FW", @"205 KB",
            @"https://downloads.lab599.com/TX500PRO/mtrx_pro1.17.13.fw",
            @"Firmware release v1.17.13 for TX-500PRO.");

    // =========================================================================
    // 3. SOFTWARE & UTILITIES (ZIP & APK) - English & Russian
    // =========================================================================
    addItem(@"CAT Test Utility v1.1 (English)", @"Software & Tools", @"ZIP", @"263 KB",
            @"https://downloads.lab599.com/SW/Lab599-TRX-TestCAT-1.1-EN.zip",
            @"Lab599 official CAT testing utility (English edition).");
    addItem(@"CAT Test Utility v1.1 (Russian)", @"Software & Tools", @"ZIP", @"265 KB",
            @"https://downloads.lab599.com/SW/Lab599-TRX-TestCAT-1.1-RU.zip",
            @"Утилита тестирования CAT Lab599 (русская версия).");
    addItem(@"TRX Time Sync Utility (English)", @"Software & Tools", @"ZIP", @"258 KB",
            @"https://downloads.lab599.com/SW/Lab599-TRX-TimeSync-EN.zip",
            @"Official clock synchronization utility (English edition).");
    addItem(@"TRX Time Sync Utility (Russian)", @"Software & Tools", @"ZIP", @"260 KB",
            @"https://downloads.lab599.com/SW/Lab599-TRX-TimeSync.zip",
            @"Утилита синхронизации времени TRX (русская версия).");
    addItem(@"Lab599 TRX Remote App v1.0.3 BETA (Android)", @"Software & Tools", @"APK", @"578 KB",
            @"https://downloads.lab599.com/SW/LAB599-TRX-Remote-1.0.3-BETA.apk",
            @"Wireless / USB remote control app for Android devices.");
    addItem(@"Firmware Update Utility (English)", @"Software & Tools", @"ZIP", @"450 KB",
            @"https://downloads.lab599.com/TX500/Lab599-TRX-Update-EN.zip",
            @"Official desktop firmware updater for Lab599 radios (English).");
    addItem(@"Firmware Update Utility (Russian)", @"Software & Tools", @"ZIP", @"450 KB",
            @"https://downloads.lab599.com/TX500/Lab599-TRX-Update-RU.zip",
            @"Утилита обновления прошивки TX-500 (русская версия).");
    addItem(@"Memory Cells Programming Utility (English)", @"Software & Tools", @"ZIP", @"156 KB",
            @"https://downloads.lab599.com/TX500/Lab599-TRX-Mem-EN.zip",
            @"100-channel memory manager with .mem file support (English).");
    addItem(@"Memory Cells Programming Utility (Russian)", @"Software & Tools", @"ZIP", @"352 KB",
            @"https://downloads.lab599.com/SW/Lab599-TRX-Mem-RU.zip",
            @"Утилита работы с каналами памяти TX-500 (русская версия).");
    addItem(@"Settings Backup Utility (English)", @"Software & Tools", @"ZIP", @"85 KB",
            @"https://downloads.lab599.com/TX500/Lab599-TRX-Settings-EN.zip",
            @"Configuration backup and restore utility with .set file support (English).");
    addItem(@"Settings Backup Utility (Russian)", @"Software & Tools", @"ZIP", @"85 KB",
            @"https://downloads.lab599.com/TX500/Lab599-TRX-Settings-RU.zip",
            @"Утилита сохранения и восстановления настроек TX-500 (русская версия).");

    // =========================================================================
    // 4. DRIVERS
    // =========================================================================
    addItem(@"FTDI FT232 USB Serial Driver v2.12.28", @"Drivers", @"ZIP", @"1.8 MB",
            @"https://downloads.lab599.com/TX500/FTDI_FT232_v2.12.28.zip",
            @"Official FTDI USB-UART driver package.");
    addItem(@"Prolific PL2303 USB Serial Driver v1.5.0", @"Drivers", @"EXE", @"3.2 MB",
            @"https://downloads.lab599.com/TX500/PL2303_Prolific_DriverInstaller_v1.5.0.exe",
            @"Windows installer for Prolific USB-serial chipsets.");

    return items;
}

@end
