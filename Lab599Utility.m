#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "TX500Transfer.h"
#import "TX500TimeSync.h"
#import "Lab599FirmwareCatalog.h"
#import "Lab599ToolsController.h"
#import "Lab599DriverController.h"
#import "Lab599DocsController.h"

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSPopUpButton *portMenu;
@property(nonatomic, strong) NSTextField *firmwareName;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) NSProgressIndicator *progressBar;
@property(nonatomic, strong) NSButton *updateButton;
@property(nonatomic, strong) NSButton *refreshButton;
@property(nonatomic, strong) NSButton *chooseButton;
@property(nonatomic, strong) NSButton *onlineButton;
@property(nonatomic, strong) NSTextView *logView;
@property(nonatomic, strong) NSURL *firmwareURL;
@property(nonatomic, strong) id activity;
@property(nonatomic) BOOL busy;
@property(nonatomic) BOOL hasPorts;
@property(nonatomic, strong) NSSegmentedControl *operationPicker;
@property(nonatomic, strong) NSStackView *portRow;
@property(nonatomic, strong) NSView *firmwareRow;
@property(nonatomic, strong) NSView *timeRow;
@property(nonatomic, strong) NSTextField *instructions;
@property(nonatomic, strong) NSTextField *clockPreview;
@property(nonatomic, strong) NSPopUpButton *timeZoneMenu;
@property(nonatomic, strong) NSButton *syncButton;
@property(nonatomic, strong) NSTimer *clockTimer;
@property(nonatomic, strong) Lab599ToolsController *tools;
@property(nonatomic, strong) Lab599DriverController *driverController;
@property(nonatomic, strong) Lab599DocsController *docsController;

// Online Firmware Sheet components
@property(nonatomic, strong) NSWindow *catalogSheet;
@property(nonatomic, strong) NSPopUpButton *modelFilterPopup;
@property(nonatomic, strong) NSPopUpButton *catalogPopup;
@property(nonatomic, strong) NSTextView *changelogView;
@property(nonatomic, strong) NSProgressIndicator *downloadProgress;
@property(nonatomic, strong) NSTextField *downloadStatusLabel;
@property(nonatomic, strong) NSButton *downloadActionBtn;
@property(nonatomic, strong) NSButton *refreshCatalogBtn;
@property(nonatomic, strong) NSArray<Lab599FirmwareItem *> *catalogItems;
@property(nonatomic, strong) NSArray<Lab599FirmwareItem *> *filteredItems;
@property(nonatomic, strong) NSURLSessionDownloadTask *activeDownloadTask;

// About Window
@property(nonatomic, strong) NSWindow *aboutWindow;

// Radio Hardware Preview
@property(nonatomic, strong) NSBox *radioPreviewBox;
@property(nonatomic, strong) NSImageView *radioImageView;
@property(nonatomic, strong) NSTextField *radioModelLabel;
@property(nonatomic, strong) NSTextField *radioSpecsLabel;
@property(nonatomic, strong) NSTextField *radioCompatibilityBadge;
@end

@implementation AppDelegate

- (NSTextField *)label:(NSString *)text {
    NSTextField *field = [NSTextField labelWithString:text];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    return field;
}

- (void)appendLog:(NSString *)message {
    NSAssert([NSThread isMainThread], @"UI logging must run on the main thread.");
    NSDateFormatter *df = [NSDateFormatter new];
    df.dateFormat = @"HH:mm:ss";
    NSString *entry = [NSString stringWithFormat:@"[%@] %@\n", [df stringFromDate:[NSDate date]], message];
    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: NSColor.labelColor
    };
    [self.logView.textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:entry attributes:attributes]];
    if (self.logView.textStorage.length > 200000) [self.logView.textStorage deleteCharactersInRange:NSMakeRange(0, self.logView.textStorage.length - 150000)];
    [self.logView scrollRangeToVisible:NSMakeRange(self.logView.string.length, 0)];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 950, 920)
        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"Lab599 Utility";
    self.window.delegate = self;
    self.window.minSize = NSMakeSize(920, 890);
    [self.window center];

    // Menus
    NSMenu *menu = [NSMenu new];
    NSMenuItem *appItem = [NSMenuItem new];
    [menu addItem:appItem];
    NSMenu *appMenu = [NSMenu new];
    NSMenuItem *aboutItem = [appMenu addItemWithTitle:@"About Lab599 Utility" action:@selector(showAboutWindow:) keyEquivalent:@""];
    aboutItem.target = self;
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Hide Lab599 Utility" action:@selector(hide:) keyEquivalent:@"h"];
    NSMenuItem *hideOthers = [appMenu addItemWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
    hideOthers.keyEquivalentModifierMask = NSEventModifierFlagOption | NSEventModifierFlagCommand;
    [appMenu addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit Lab599 Utility" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;

    NSMenuItem *fileItem = [NSMenuItem new];
    [menu addItem:fileItem];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItemWithTitle:@"Choose Firmware File..." action:@selector(chooseFirmware:) keyEquivalent:@"o"];
    [fileMenu addItemWithTitle:@"Download from Lab599..." action:@selector(openCatalogSheet:) keyEquivalent:@"d"];
    [fileMenu addItemWithTitle:@"Save Diagnostic Log..." action:@selector(saveLog:) keyEquivalent:@"s"];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Close Window" action:@selector(performClose:) keyEquivalent:@"w"];
    fileItem.submenu = fileMenu;

    NSMenuItem *editItem = [[NSMenuItem alloc] initWithTitle:@"Edit" action:NULL keyEquivalent:@""];
    [menu addItem:editItem];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Undo" action:NSSelectorFromString(@"undo:") keyEquivalent:@"z"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    editItem.submenu = editMenu;

    NSMenuItem *helpItem = [[NSMenuItem alloc] initWithTitle:@"Help" action:NULL keyEquivalent:@""];
    [menu addItem:helpItem];
    NSMenu *helpMenu = [[NSMenu alloc] initWithTitle:@"Help"];
    NSMenuItem *helpAbout = [helpMenu addItemWithTitle:@"About Lab599 Utility" action:@selector(showAboutWindow:) keyEquivalent:@""];
    helpAbout.target = self;
    [helpMenu addItem:[NSMenuItem separatorItem]];
    [helpMenu addItemWithTitle:@"Official Lab599 Downloads Website" action:@selector(openLab599Website:) keyEquivalent:@""];
    [helpMenu addItemWithTitle:@"GitHub Project (EP2AES)" action:@selector(openGitHubRepo:) keyEquivalent:@""];
    helpItem.submenu = helpMenu;

    NSApp.mainMenu = menu;

    // Header
    NSTextField *heading = [self label:@"Lab599 Utility"];
    heading.font = [NSFont systemFontOfSize:22 weight:NSFontWeightSemibold];

    NSTextField *instructions = [NSTextField wrappingLabelWithString:
        @"Connect the CAT-USB cable and stable external power. Close other radio applications. On your transceiver (TX-500 Discovery / TX-500MP), hold the third top function key while pressing POWER. Start only when the screen displays \"The loader is waiting...\". Keep power and cable connected until completion."];
    instructions.textColor = NSColor.secondaryLabelColor;
    self.instructions = instructions;
    self.operationPicker = [NSSegmentedControl segmentedControlWithLabels:@[
        @"Firmware Update", @"Time Sync", @"CAT Test", @"Settings", @"Memory", @"Driver Install", @"Documentation"
    ] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(operationChanged:)];
    self.operationPicker.selectedSegment = 0;

    NSArray<NSString *> *symbols = @[
        @"cpu",
        @"clock",
        @"antenna.radiowaves.left.and.right",
        @"slider.horizontal.3",
        @"memorychip",
        @"wrench.and.screwdriver",
        @"doc.text"
    ];
    for (NSUInteger i = 0; i < symbols.count; i++) {
        NSImage *img = [NSImage imageWithSystemSymbolName:symbols[i] accessibilityDescription:nil];
        if (img) {
            [self.operationPicker setImage:img forSegment:i];
        }
    }

    // Serial Port Selection Row
    self.portMenu = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.portMenu.translatesAutoresizingMaskIntoConstraints = NO;
    self.refreshButton = [NSButton buttonWithTitle:@"Refresh" target:self action:@selector(refreshPorts:)];
    NSStackView *portRow = [NSStackView stackViewWithViews:@[[self label:@"Serial port:"], self.portMenu, self.refreshButton]];
    portRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    portRow.alignment = NSLayoutAttributeCenterY;
    portRow.spacing = 10;
    [self.portMenu.widthAnchor constraintEqualToConstant:390].active = YES;
    self.portRow = portRow;

    // Firmware Selection Row
    self.firmwareName = [self label:@"No firmware selected"];
    self.firmwareName.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [self.firmwareName.widthAnchor constraintEqualToConstant:310].active = YES;
    self.chooseButton = [NSButton buttonWithTitle:@"Choose .fw..." target:self action:@selector(chooseFirmware:)];
    self.onlineButton = [NSButton buttonWithTitle:@"Download from Lab599..." target:self action:@selector(openCatalogSheet:)];
    NSStackView *fileRow = [NSStackView stackViewWithViews:@[[self label:@"Firmware:"], self.firmwareName, self.chooseButton, self.onlineButton]];
    fileRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    fileRow.alignment = NSLayoutAttributeCenterY;
    fileRow.spacing = 8;
    self.firmwareRow = fileRow;
    self.radioPreviewBox = [self buildRadioPreviewBox];

    // Time synchronization is a separate operation in normal radio mode.
    self.timeZoneMenu = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.timeZoneMenu addItemsWithTitles:@[@"Mac local time", @"UTC"]];
    self.timeZoneMenu.target = self;
    self.timeZoneMenu.action = @selector(updateClockPreview:);
    self.clockPreview = [self label:@""];
    self.clockPreview.font = [NSFont monospacedDigitSystemFontOfSize:14 weight:NSFontWeightMedium];
    NSStackView *timeRow = [NSStackView stackViewWithViews:@[[self label:@"Set radio clock to:"], self.timeZoneMenu, self.clockPreview]];
    timeRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    timeRow.alignment = NSLayoutAttributeCenterY;
    timeRow.spacing = 12;
    self.timeRow = timeRow;
    timeRow.hidden = YES;

    // Progress and Status
    self.progressBar = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    self.progressBar.minValue = 0;
    self.progressBar.maxValue = 1;
    self.progressBar.indeterminate = NO;
    self.statusLabel = [NSTextField wrappingLabelWithString:@"Select the transceiver's serial port and choose or download the firmware file."];
    self.statusLabel.textColor = NSColor.secondaryLabelColor;
    [self.statusLabel.heightAnchor constraintGreaterThanOrEqualToConstant:38].active = YES;

    // Action Buttons Row (About button moved to macOS Application Menu per requirements)
    self.updateButton = [NSButton buttonWithTitle:@"Update Firmware" target:self action:@selector(startUpdate:)];
    self.updateButton.bezelStyle = NSBezelStyleRounded;
    self.updateButton.keyEquivalent = @"\r";
    self.syncButton = [NSButton buttonWithTitle:@"Synchronize Clock" target:self action:@selector(startTimeSync:)];
    self.syncButton.bezelStyle = NSBezelStyleRounded;
    self.syncButton.hidden = YES;
    NSButton *saveButton = [NSButton buttonWithTitle:@"Save Diagnostic Log..." target:self action:@selector(saveLog:)];
    NSStackView *buttonRow = [NSStackView stackViewWithViews:@[self.updateButton, self.syncButton, saveButton]];
    buttonRow.detachesHiddenViews = YES;
    buttonRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttonRow.spacing = 12;

    // Log Scroll View
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    self.logView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 720, 200)];
    self.logView.editable = NO;
    self.logView.selectable = YES;
    self.logView.richText = NO;
    self.logView.verticallyResizable = YES;
    self.logView.horizontallyResizable = NO;
    self.logView.autoresizingMask = NSViewWidthSizable;
    self.logView.textContainer.widthTracksTextView = YES;
    self.logView.textContainerInset = NSMakeSize(8, 8);
    scroll.documentView = self.logView;
    [scroll.heightAnchor constraintEqualToConstant:100].active = YES;

    __weak AppDelegate *weakSelf = self;

    self.tools = [Lab599ToolsController new];
    self.tools.window = self.window;
    self.tools.selectedPort = ^NSString * { return weakSelf.hasPorts ? weakSelf.portMenu.selectedItem.title : nil; };
    self.tools.log = ^(NSString *message) { [weakSelf appendLog:message]; };
    self.tools.statusChanged = ^(NSString *message, double progress) {
        weakSelf.statusLabel.stringValue = message; weakSelf.progressBar.doubleValue = progress;
    };
    self.tools.activityChanged = ^(BOOL busy) { [weakSelf setToolsBusy:busy]; };
    self.tools.view.hidden = YES;

    // Driver Controller
    self.driverController = [Lab599DriverController new];
    self.driverController.window = self.window;
    self.driverController.log = ^(NSString *message) { [weakSelf appendLog:message]; };
    self.driverController.statusChanged = ^(NSString *message, double progress) {
        weakSelf.statusLabel.stringValue = message; weakSelf.progressBar.doubleValue = progress;
    };
    self.driverController.activityChanged = ^(BOOL busy) { [weakSelf setToolsBusy:busy]; };
    self.driverController.view.hidden = YES;

    // Documentation Controller
    self.docsController = [Lab599DocsController new];
    self.docsController.window = self.window;
    self.docsController.log = ^(NSString *message) { [weakSelf appendLog:message]; };
    self.docsController.statusChanged = ^(NSString *message, double progress) {
        weakSelf.statusLabel.stringValue = message; weakSelf.progressBar.doubleValue = progress;
    };
    self.docsController.activityChanged = ^(BOOL busy) { [weakSelf setToolsBusy:busy]; };
    self.docsController.view.hidden = YES;

    // Main Layout Stack
    NSStackView *stack = [NSStackView stackViewWithViews:@[
        heading, self.operationPicker, instructions,
        portRow, fileRow, self.radioPreviewBox, timeRow, self.tools.view, self.driverController.view, self.docsController.view,
        self.progressBar, self.statusLabel,
        buttonRow,
        [self label:@"Diagnostic log:"], scroll
    ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8;
    stack.detachesHiddenViews = YES;
    [self.window.contentView addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.window.contentView.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:self.window.contentView.trailingAnchor constant:-24],
        [stack.topAnchor constraintEqualToAnchor:self.window.contentView.topAnchor constant:24],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:self.window.contentView.bottomAnchor constant:-24],
        [instructions.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [self.radioPreviewBox.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [self.tools.view.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [self.driverController.view.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [self.docsController.view.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [self.progressBar.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [self.statusLabel.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [scroll.widthAnchor constraintEqualToAnchor:stack.widthAnchor]
    ]];

    [self appendLog:@"Lab599 Utility 2.5 initialized."];
    [self appendLog:@"BL20 protocol engine ready: 57600 baud, 8N1, two-ACK header+payload cycle."];
    [self appendLog:@"TimeSync ready: 9600 baud, TM set/query with clock read-back verification."];
    [self refreshPorts:nil];
    [self updateClockPreview:nil];
    self.clockTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(updateClockPreview:) userInfo:nil repeats:YES];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

#pragma mark - Serial Ports

- (void)refreshPorts:(id)sender {
    if (self.busy) return;
    NSString *previous = self.portMenu.selectedItem.title;
    NSArray<NSString *> *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/dev" error:NULL] ?: @[];
    NSPredicate *match = [NSPredicate predicateWithBlock:^BOOL(NSString *name, NSDictionary *bindings) {
        (void)bindings;
        return [name hasPrefix:@"cu."] &&
               ![name.lowercaseString containsString:@"bluetooth"] &&
               ![name.lowercaseString containsString:@"debug"] &&
               ![name.lowercaseString containsString:@"wlan"];
    }];
    NSArray *ports = [[names filteredArrayUsingPredicate:match] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    [self.portMenu removeAllItems];
    self.hasPorts = ports.count > 0;
    if (!self.hasPorts) {
        [self.portMenu addItemWithTitle:@"No serial ports found"];
    }
    for (NSString *name in ports) {
        [self.portMenu addItemWithTitle:[@"/dev/" stringByAppendingString:name]];
    }
    if (previous && [self.portMenu itemWithTitle:previous]) {
        [self.portMenu selectItemWithTitle:previous];
    }
    self.portMenu.enabled = self.hasPorts;
    self.updateButton.enabled = self.hasPorts && self.firmwareURL != nil;
    self.syncButton.enabled = self.hasPorts;
    [self.tools portsAvailable:self.hasPorts];
    if (sender) {
        self.statusLabel.stringValue = self.hasPorts ?
            @"Select the serial port connected to your Lab599 transceiver." :
            @"Connect the CAT-USB adapter and click Refresh. A working serial driver (FTDI/Prolific) is required.";
    }
}

#pragma mark - Operation Selection & Time Synchronization

- (NSTimeZone *)selectedTimeZone {
    return self.timeZoneMenu.indexOfSelectedItem == 1 ? [NSTimeZone timeZoneForSecondsFromGMT:0] : NSTimeZone.localTimeZone;
}

- (void)updateClockPreview:(id)sender {
    (void)sender;
    NSTimeZone *zone = [self selectedTimeZone];
    NSData *command = TXTimeSetCommand(NSDate.date, zone);
    NSString *time = [[[NSString alloc] initWithData:command encoding:NSASCIIStringEncoding] substringWithRange:NSMakeRange(2, 8)];
    self.clockPreview.stringValue = [NSString stringWithFormat:@"%@  (%@)", time, zone.name];
}

- (void)operationChanged:(id)sender {
    (void)sender;
    if (self.busy) return;
    NSInteger operation = self.operationPicker.selectedSegment;
    BOOL isFW = (operation == 0);
    BOOL isSync = (operation == 1);
    BOOL isTools = (operation >= 2 && operation <= 4);
    BOOL isDriver = (operation == 5);
    BOOL isDocs = (operation == 6);

    self.tools.view.hidden = !isTools;
    if (isTools) [self.tools selectTool:operation - 2];

    self.driverController.view.hidden = !isDriver;
    if (isDriver) [self.driverController checkDriverStatus];

    self.docsController.view.hidden = !isDocs;
    if (isDocs) [self.docsController refreshLocalAvailability];

    self.portRow.hidden = (isDriver || isDocs);
    self.firmwareRow.hidden = !isFW;
    self.radioPreviewBox.hidden = !isFW;
    self.timeRow.hidden = !isSync;

    self.updateButton.hidden = !isFW;
    self.syncButton.hidden = !isSync;
    self.updateButton.keyEquivalent = isFW ? @"\r" : @"";
    self.syncButton.keyEquivalent = isSync ? @"\r" : @"";
    self.progressBar.doubleValue = 0;

    if (isFW) {
        self.instructions.stringValue = @"Connect the CAT-USB cable and stable external power. Close other radio applications. On your transceiver (TX-500 Discovery / TX-500MP), hold the third top function key while pressing POWER. Start only when the screen displays \"The loader is waiting...\". Keep power and cable connected until completion.";
        self.statusLabel.stringValue = @"Select the transceiver's serial port and choose or download the firmware file.";
    } else if (isSync) {
        self.instructions.stringValue = @"Turn the radio on normally with POWER. Connect the CAT-USB cable, use CAT at 9600 baud, and close other radio applications. Choose Mac local time or UTC below. Synchronization uses your Mac's clock; check its accuracy in System Settings. No firmware file is needed.";
        self.statusLabel.stringValue = @"Ready to synchronize the radio clock in normal operating mode.";
    } else if (isTools) {
        self.instructions.stringValue = @"Turn the radio on normally. Connect its CAT-USB cable, set CAT to 9600 baud and close other radio applications.";
        self.statusLabel.stringValue = @"Ready. File editing and backup saving also work without a connected radio.";
    } else if (isDriver) {
        self.instructions.stringValue = @"Mandatory FTDI D2XX runtime installation for macOS (Apple Silicon & Intel). Fixes serial callout instantiation and ensures non-blocking communication in WSJT-X.";
        self.statusLabel.stringValue = @"Ready to manage and verify FTDI D2XX serial driver.";
    } else if (isDocs) {
        self.instructions.stringValue = @"Official Lab599 product documentation, user manuals, firmware releases, utilities, and drivers. Download directly or open local copies.";
        self.statusLabel.stringValue = @"Browse and download official Lab599 resources.";
    }
    [self updateClockPreview:nil];
}

- (void)setToolsBusy:(BOOL)busy {
    self.busy = busy;
    self.operationPicker.enabled = self.timeZoneMenu.enabled = self.refreshButton.enabled = !busy;
    self.chooseButton.enabled = self.onlineButton.enabled = !busy;
    self.portMenu.enabled = !busy && self.hasPorts;
    self.updateButton.enabled = !busy && self.hasPorts && self.firmwareURL != nil;
    self.syncButton.enabled = !busy && self.hasPorts;
    if (busy) {
        self.activity = [NSProcessInfo.processInfo beginActivityWithOptions:(NSActivityUserInitiated | NSActivityIdleSystemSleepDisabled) reason:@"Lab599 Utility radio operation"];
    } else {
        if (self.activity) [NSProcessInfo.processInfo endActivity:self.activity];
        self.activity = nil; [self refreshPorts:nil];
    }
}

- (void)startTimeSync:(id)sender {
    (void)sender;
    if (self.busy || self.operationPicker.selectedSegment != 1) return;
    NSString *port = self.portMenu.selectedItem.title;
    if (!self.hasPorts || ![port hasPrefix:@"/dev/cu."]) return;
    NSTimeZone *zone = [[self selectedTimeZone] copy];
    self.busy = YES;
    self.operationPicker.enabled = NO;
    self.timeZoneMenu.enabled = NO;
    self.syncButton.enabled = NO;
    self.updateButton.enabled = NO;
    self.portMenu.enabled = NO;
    self.refreshButton.enabled = NO;
    self.chooseButton.enabled = NO;
    self.onlineButton.enabled = NO;
    self.progressBar.indeterminate = YES;
    [self.progressBar startAnimation:nil];
    self.statusLabel.stringValue = @"Setting the radio clock and checking its response...";
    self.activity = [NSProcessInfo.processInfo beginActivityWithOptions:(NSActivityUserInitiated | NSActivityIdleSystemSleepDisabled)
        reason:@"Synchronizing Lab599 radio clock"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        TXTimeSyncResult *result = TXSynchronizeTime(port, zone, TXDefaultTimeSyncOptions(), nil, ^(NSString *message) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self appendLog:message]; });
        });
        dispatch_async(dispatch_get_main_queue(), ^{
            self.busy = NO;
            [NSProcessInfo.processInfo endActivity:self.activity];
            self.activity = nil;
            self.operationPicker.enabled = YES;
            self.timeZoneMenu.enabled = YES;
            self.refreshButton.enabled = YES;
            self.chooseButton.enabled = YES;
            self.onlineButton.enabled = YES;
            [self.progressBar stopAnimation:nil];
            self.progressBar.indeterminate = NO;
            self.progressBar.doubleValue = result.success ? 1 : 0;
            [self refreshPorts:nil];
            if (result.success) {
                self.statusLabel.stringValue = [NSString stringWithFormat:@"Clock synchronized: %@ (%@). Radio read-back verified.", result.radioTime, zone.name];
            } else {
                self.statusLabel.stringValue = @"Clock synchronization was not confirmed. Check the diagnostic log.";
                [self showAlert:@"Clock synchronization was not confirmed" message:result.failure warning:YES];
            }
        });
    });
}

#pragma mark - Radio Hardware Preview (Firmware Update)

- (NSImage *)loadRadioImage {
    NSImage *image = [NSImage imageNamed:@"tx500_radio"];
    if (image) return image;
    NSString *resPath = [[NSBundle mainBundle] pathForResource:@"tx500_radio" ofType:@"png"];
    if (resPath && [[NSFileManager defaultManager] fileExistsAtPath:resPath]) {
        image = [[NSImage alloc] initWithContentsOfFile:resPath];
        if (image) return image;
    }
    NSString *bundleDir = [[NSBundle mainBundle] bundlePath];
    NSArray<NSString *> *candidates = @[
        [bundleDir stringByAppendingPathComponent:@"Contents/Resources/tx500_radio.png"],
        @"assets/tx500_radio.png",
        @"../assets/tx500_radio.png",
        @"Manual/tx500_radio_discovery.png",
        @"../Manual/tx500_radio_discovery.png",
        @"/Users/factoreal/Downloads/TX-500/Updater/assets/tx500_radio.png",
        @"/Users/factoreal/Downloads/TX-500/Manual/tx500_radio_discovery.png"
    ];
    for (NSString *path in candidates) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            image = [[NSImage alloc] initWithContentsOfFile:path];
            if (image) return image;
        }
    }
    return nil;
}

- (NSBox *)buildRadioPreviewBox {
    NSBox *box = [NSBox new];
    box.titlePosition = NSNoTitle;
    box.boxType = NSBoxCustom;
    box.cornerRadius = 8.0;
    box.borderWidth = 1.0;
    box.borderColor = [NSColor separatorColor];
    box.fillColor = [NSColor controlBackgroundColor];
    box.translatesAutoresizingMaskIntoConstraints = NO;

    NSImageView *imageView = [NSImageView new];
    imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    imageView.image = [self loadRadioImage];
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.radioImageView = imageView;

    self.radioModelLabel = [NSTextField labelWithString:@"Target Radio: Lab599 Discovery TX-500"];
    self.radioModelLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightBold];

    self.radioSpecsLabel = [NSTextField wrappingLabelWithString:@"Target Specs: 256×128 Monochrome LCD • 32-bit Floating-Point DSP • All-Aluminum CNC Waterproof Chassis"];
    self.radioSpecsLabel.textColor = NSColor.secondaryLabelColor;
    self.radioSpecsLabel.font = [NSFont systemFontOfSize:11];

    self.radioCompatibilityBadge = [NSTextField labelWithString:@"● Model Verification: Select or download a .fw file above to verify radio compatibility."];
    self.radioCompatibilityBadge.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    self.radioCompatibilityBadge.textColor = NSColor.secondaryLabelColor;

    NSStackView *textStack = [NSStackView stackViewWithViews:@[self.radioModelLabel, self.radioSpecsLabel, self.radioCompatibilityBadge]];
    textStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    textStack.alignment = NSLayoutAttributeLeading;
    textStack.spacing = 3;
    textStack.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *hStack = [NSStackView stackViewWithViews:@[imageView, textStack]];
    hStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    hStack.alignment = NSLayoutAttributeCenterY;
    hStack.spacing = 14;
    hStack.translatesAutoresizingMaskIntoConstraints = NO;
    [box.contentView addSubview:hStack];

    [NSLayoutConstraint activateConstraints:@[
        [imageView.widthAnchor constraintEqualToConstant:150],
        [imageView.heightAnchor constraintEqualToConstant:80],
        [hStack.leadingAnchor constraintEqualToAnchor:box.contentView.leadingAnchor constant:12],
        [hStack.trailingAnchor constraintEqualToAnchor:box.contentView.trailingAnchor constant:-12],
        [hStack.topAnchor constraintEqualToAnchor:box.contentView.topAnchor constant:7],
        [hStack.bottomAnchor constraintEqualToAnchor:box.contentView.bottomAnchor constant:-7],
        [textStack.trailingAnchor constraintEqualToAnchor:hStack.trailingAnchor]
    ]];

    return box;
}

- (void)updateRadioPreviewForFirmwareData:(NSData *)data url:(NSURL *)url {
    if (!data || data.length < 16) {
        self.radioModelLabel.stringValue = @"Target Radio: Lab599 Discovery TX-500";
        self.radioCompatibilityBadge.stringValue = @"● Model Verification: Select or download a .fw file above to verify radio compatibility.";
        self.radioCompatibilityBadge.textColor = NSColor.secondaryLabelColor;
        return;
    }

    const uint8_t *bytes = (const uint8_t *)data.bytes;
    BOOL isDiscovery = (memcmp(bytes + 12, "\xaa\xb4\x1a\xc6", 4) == 0);
    BOOL isMP = (memcmp(bytes + 12, "\x96\x3b\xcd\xf4", 4) == 0) || [url.lastPathComponent containsString:@"MP"];

    if (isDiscovery) {
        self.radioModelLabel.stringValue = @"Target Radio: Lab599 Discovery TX-500";
        self.radioSpecsLabel.stringValue = @"256×128 Monochrome LCD • 32-bit Floating-Point DSP • All-Aluminum CNC Waterproof Chassis";
        self.radioCompatibilityBadge.stringValue = @"✓ Hardware Match Confirmed: Lab599 TX-500 Discovery (BL20 Model ID: 0xc61ab4aa)";
        self.radioCompatibilityBadge.textColor = [NSColor colorWithSRGBRed:0.1 green:0.65 blue:0.25 alpha:1.0];
    } else if (isMP) {
        self.radioModelLabel.stringValue = @"Target Radio: Lab599 TX-500MP (Manpack)";
        self.radioSpecsLabel.stringValue = @"192×96 Monochrome LCD • 32-bit Floating-Point DSP • Manpack Form Factor";
        self.radioCompatibilityBadge.stringValue = @"⚠️ Notice: Firmware is targeted for TX-500MP hardware (BL20 Model ID: 0x963bcdf4). Do not flash to Discovery.";
        self.radioCompatibilityBadge.textColor = [NSColor colorWithSRGBRed:0.85 green:0.45 blue:0.0 alpha:1.0];
    } else {
        self.radioModelLabel.stringValue = @"Target Radio: Custom / Unknown Lab599 Hardware";
        self.radioCompatibilityBadge.stringValue = @"⚠️ Unrecognized Hardware ID. Verify model before flashing.";
        self.radioCompatibilityBadge.textColor = NSColor.systemOrangeColor;
    }
}

#pragma mark - Local Firmware Loading

- (void)chooseFirmware:(id)sender {
    (void)sender;
    if (self.busy) return;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"fw" conformingToType:UTTypeData]];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;
    panel.title = @"Select Lab599 Firmware File";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || !panel.URL) return;
        NSError *readError = nil;
        NSData *data = [NSData dataWithContentsOfURL:panel.URL options:0 error:&readError];
        NSString *problem = data ? TXFirmwareValidationError(data) : readError.localizedDescription;
        if (problem) {
            [self showAlert:@"Firmware could not be loaded" message:problem warning:YES];
            return;
        }
        [self setLoadedFirmwareURL:panel.URL firmwareData:data isOnlineDownload:NO];
    }];
}

- (void)setLoadedFirmwareURL:(NSURL *)url firmwareData:(NSData *)data isOnlineDownload:(BOOL)isOnline {
    self.firmwareURL = url;
    self.firmwareName.stringValue = url.lastPathComponent;
    self.firmwareName.toolTip = url.path;
    NSString *hash = TXFirmwareSHA256(data);
    NSString *source = isOnline ? @"Online Download" : @"Local File";
    [self appendLog:[NSString stringWithFormat:@"Loaded %@ (%lu bytes, %@). SHA-256: %@",
        url.lastPathComponent, (unsigned long)data.length, source, hash]];

    if ([hash isEqualToString:@"2162fed7d27987507c8b412f3d38478c0a670a906a0c747578d7c975ad5a04ea"]) {
        [self appendLog:@"Matches verified official TX-500 Discovery v2.00.00 release."];
    }
    self.statusLabel.stringValue = [NSString stringWithFormat:@"Firmware ready: %@. Check that transceiver displays \"The loader is waiting...\".", url.lastPathComponent];
    self.updateButton.enabled = self.hasPorts;
    [self updateRadioPreviewForFirmwareData:data url:url];
}

#pragma mark - Online Firmware Catalog Sheet

- (void)openCatalogSheet:(id)sender {
    (void)sender;
    if (self.busy) return;

    if (!self.catalogSheet) {
        [self buildCatalogSheet];
    }

    [self.window beginSheet:self.catalogSheet completionHandler:nil];
    [self fetchCatalogList];
}

- (void)buildCatalogSheet {
    self.catalogSheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 620, 480)
        styleMask:(NSWindowStyleMaskTitled)
        backing:NSBackingStoreBuffered defer:NO];
    self.catalogSheet.title = @"Official Lab599 Firmware Catalog";

    NSTextField *title = [self label:@"Download Official Firmware from lab599.com"];
    title.font = [NSFont systemFontOfSize:16 weight:NSFontWeightSemibold];

    NSTextField *desc = [NSTextField wrappingLabelWithString:
        @"Firmware releases retrieved directly from https://lab599.com/downloads. Select your transceiver model, pick the version, and click Download & Select."];
    desc.textColor = NSColor.secondaryLabelColor;

    // Filter by model
    NSTextField *modelLabel = [self label:@"Radio model:"];
    self.modelFilterPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.modelFilterPopup addItemWithTitle:@"All Models"];
    [self.modelFilterPopup addItemWithTitle:@"TX-500 Discovery"];
    [self.modelFilterPopup addItemWithTitle:@"TX-500MP"];
    self.modelFilterPopup.target = self;
    self.modelFilterPopup.action = @selector(filterChanged:);
    NSStackView *modelRow = [NSStackView stackViewWithViews:@[modelLabel, self.modelFilterPopup]];
    modelRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    modelRow.spacing = 10;

    // Firmware version selection
    NSTextField *verLabel = [self label:@"Available release:"];
    self.catalogPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.catalogPopup.target = self;
    self.catalogPopup.action = @selector(catalogSelectionChanged:);
    [self.catalogPopup.widthAnchor constraintEqualToConstant:360].active = YES;
    self.refreshCatalogBtn = [NSButton buttonWithTitle:@"Check for Updates" target:self action:@selector(fetchCatalogList)];
    NSStackView *catalogRow = [NSStackView stackViewWithViews:@[verLabel, self.catalogPopup, self.refreshCatalogBtn]];
    catalogRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    catalogRow.spacing = 8;

    // Changelog preview
    NSTextField *clLabel = [self label:@"Release notes / Changelog:"];
    NSScrollView *clScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    clScroll.hasVerticalScroller = YES;
    clScroll.borderType = NSBezelBorder;
    self.changelogView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 560, 110)];
    self.changelogView.editable = NO;
    self.changelogView.richText = NO;
    self.changelogView.verticallyResizable = YES;
    self.changelogView.textContainer.widthTracksTextView = YES;
    self.changelogView.textContainerInset = NSMakeSize(6, 6);
    self.changelogView.font = [NSFont systemFontOfSize:12];
    clScroll.documentView = self.changelogView;
    [clScroll.heightAnchor constraintEqualToConstant:110].active = YES;

    // Progress & Status
    self.downloadProgress = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    self.downloadProgress.minValue = 0.0;
    self.downloadProgress.maxValue = 1.0;
    self.downloadProgress.indeterminate = NO;
    self.downloadProgress.displayedWhenStopped = YES;
    self.downloadStatusLabel = [self label:@"Connecting to lab599.com..."];
    self.downloadStatusLabel.textColor = NSColor.secondaryLabelColor;

    // Buttons
    self.downloadActionBtn = [NSButton buttonWithTitle:@"Download & Select" target:self action:@selector(startDownloadSelectedFirmware:)];
    self.downloadActionBtn.bezelStyle = NSBezelStyleRounded;
    self.downloadActionBtn.keyEquivalent = @"\r";
    NSButton *closeBtn = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(closeCatalogSheet:)];
    NSStackView *actionRow = [NSStackView stackViewWithViews:@[self.downloadActionBtn, closeBtn]];
    actionRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    actionRow.spacing = 10;

    NSStackView *sheetStack = [NSStackView stackViewWithViews:@[
        title, desc,
        modelRow, catalogRow,
        clLabel, clScroll,
        self.downloadProgress, self.downloadStatusLabel,
        actionRow
    ]];
    sheetStack.translatesAutoresizingMaskIntoConstraints = NO;
    sheetStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    sheetStack.alignment = NSLayoutAttributeLeading;
    sheetStack.spacing = 11;
    [self.catalogSheet.contentView addSubview:sheetStack];

    [NSLayoutConstraint activateConstraints:@[
        [sheetStack.leadingAnchor constraintEqualToAnchor:self.catalogSheet.contentView.leadingAnchor constant:20],
        [sheetStack.trailingAnchor constraintEqualToAnchor:self.catalogSheet.contentView.trailingAnchor constant:-20],
        [sheetStack.topAnchor constraintEqualToAnchor:self.catalogSheet.contentView.topAnchor constant:20],
        [sheetStack.bottomAnchor constraintLessThanOrEqualToAnchor:self.catalogSheet.contentView.bottomAnchor constant:-20],
        [desc.widthAnchor constraintEqualToAnchor:sheetStack.widthAnchor],
        [clScroll.widthAnchor constraintEqualToAnchor:sheetStack.widthAnchor],
        [self.downloadProgress.widthAnchor constraintEqualToAnchor:sheetStack.widthAnchor],
        [self.downloadStatusLabel.widthAnchor constraintEqualToAnchor:sheetStack.widthAnchor]
    ]];
}

- (void)fetchCatalogList {
    self.downloadStatusLabel.stringValue = @"Checking https://lab599.com/downloads for latest firmwares...";
    self.refreshCatalogBtn.enabled = NO;
    self.downloadActionBtn.enabled = NO;
    self.downloadProgress.indeterminate = YES;
    [self.downloadProgress startAnimation:nil];

    [[Lab599FirmwareCatalog sharedCatalog] fetchAvailableFirmwaresWithCompletion:^(NSArray<Lab599FirmwareItem *> *items, NSError *error) {
        self.downloadProgress.indeterminate = NO;
        [self.downloadProgress stopAnimation:nil];
        self.refreshCatalogBtn.enabled = YES;
        self.catalogItems = items;
        if (error) {
            self.downloadStatusLabel.stringValue = [NSString stringWithFormat:@"Notice: using fallback catalog (%@)", error.localizedDescription];
        } else {
            self.downloadStatusLabel.stringValue = [NSString stringWithFormat:@"Found %lu firmware releases on lab599.com.", (unsigned long)items.count];
        }
        [self updateCatalogPopupForFilter];
    }];
}

- (void)filterChanged:(id)sender {
    (void)sender;
    [self updateCatalogPopupForFilter];
}

- (void)updateCatalogPopupForFilter {
    NSString *filter = self.modelFilterPopup.selectedItem.title;
    NSMutableArray<Lab599FirmwareItem *> *filtered = [NSMutableArray array];
    for (Lab599FirmwareItem *item in self.catalogItems) {
        if ([filter isEqualToString:@"All Models"] ||
            [item.model rangeOfString:filter options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [filtered addObject:item];
        }
    }
    self.filteredItems = filtered;
    [self.catalogPopup removeAllItems];
    for (Lab599FirmwareItem *item in filtered) {
        [self.catalogPopup addItemWithTitle:item.displayTitle];
    }
    self.downloadActionBtn.enabled = filtered.count > 0;
    [self catalogSelectionChanged:nil];
}

- (void)catalogSelectionChanged:(id)sender {
    (void)sender;
    NSInteger index = self.catalogPopup.indexOfSelectedItem;
    if (index >= 0 && index < (NSInteger)self.filteredItems.count) {
        Lab599FirmwareItem *item = self.filteredItems[index];
        NSString *cl = item.changelog ?: @"No specific changelog published for this release.";
        NSString *info = [NSString stringWithFormat:@"Model: %@\nVersion: %@\nDownload: %@\n\n%@",
                          item.model, item.version, item.downloadURL.absoluteString, cl];
        self.changelogView.string = info;
    } else {
        self.changelogView.string = @"";
    }
}

- (void)startDownloadSelectedFirmware:(id)sender {
    (void)sender;
    NSInteger index = self.catalogPopup.indexOfSelectedItem;
    if (index < 0 || index >= (NSInteger)self.filteredItems.count) return;
    Lab599FirmwareItem *selectedItem = self.filteredItems[index];

    self.downloadActionBtn.enabled = NO;
    self.modelFilterPopup.enabled = NO;
    self.catalogPopup.enabled = NO;
    self.refreshCatalogBtn.enabled = NO;
    self.downloadProgress.indeterminate = NO;
    self.downloadProgress.doubleValue = 0.0;
    self.downloadStatusLabel.stringValue = [NSString stringWithFormat:@"Downloading %@...", selectedItem.title];

    self.activeDownloadTask = [[Lab599FirmwareCatalog sharedCatalog] downloadFirmware:selectedItem
        progress:^(double progress, int64_t bytesWritten, int64_t totalExpected) {
            self.downloadProgress.doubleValue = progress;
            self.downloadStatusLabel.stringValue = [NSString stringWithFormat:@"Downloading: %.1f%% (%lld KB / %lld KB)",
                progress * 100.0, bytesWritten / 1024, totalExpected / 1024];
        }
        completion:^(NSURL * _Nullable localFileURL, NSString * _Nullable sha256, NSError * _Nullable error) {
            self.modelFilterPopup.enabled = YES;
            self.catalogPopup.enabled = YES;
            self.refreshCatalogBtn.enabled = YES;
            self.downloadActionBtn.enabled = YES;

            if (error || !localFileURL) {
                self.downloadStatusLabel.stringValue = [NSString stringWithFormat:@"Download failed: %@", error.localizedDescription];
                [self showAlert:@"Download Error" message:error.localizedDescription warning:YES];
                return;
            }

            self.downloadProgress.doubleValue = 1.0;
            self.downloadStatusLabel.stringValue = @"Download complete and verified!";
            [self appendLog:[NSString stringWithFormat:@"Successfully downloaded official %@ (SHA-256: %@) from %@", selectedItem.title, sha256 ?: @"", selectedItem.downloadURL]];

            NSData *data = [NSData dataWithContentsOfURL:localFileURL];
            [self setLoadedFirmwareURL:localFileURL firmwareData:data isOnlineDownload:YES];
            [self.window endSheet:self.catalogSheet];
        }];
}

- (void)closeCatalogSheet:(id)sender {
    (void)sender;
    if (self.activeDownloadTask && self.activeDownloadTask.state == NSURLSessionTaskStateRunning) {
        [self.activeDownloadTask cancel];
        self.activeDownloadTask = nil;
    }
    [self.window endSheet:self.catalogSheet];
}

#pragma mark - About Window

- (void)showAboutWindow:(id)sender {
    (void)sender;
    if (!self.aboutWindow) {
        self.aboutWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 540, 540)
            styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
            backing:NSBackingStoreBuffered defer:NO];
        self.aboutWindow.title = @"About Lab599 Utility";
        self.aboutWindow.releasedWhenClosed = NO;
        [self.aboutWindow center];

        // Icon
        NSImage *icon = [NSImage imageNamed:@"AppIcon"];
        if (!icon) {
            NSString *iconPath = [[NSBundle mainBundle] pathForResource:@"AppIcon" ofType:@"icns"];
            if (iconPath) icon = [[NSImage alloc] initWithContentsOfFile:iconPath];
        }
        if (!icon) {
            icon = [[NSWorkspace sharedWorkspace] iconForFile:[[NSBundle mainBundle] bundlePath]];
        }
        NSImageView *iconView = [NSImageView imageViewWithImage:icon];
        iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
        [iconView.widthAnchor constraintEqualToConstant:72].active = YES;
        [iconView.heightAnchor constraintEqualToConstant:72].active = YES;

        // Information text
        NSTextField *appName = [self label:@"Lab599 Utility"];
        appName.font = [NSFont systemFontOfSize:20 weight:NSFontWeightBold];

        NSTextField *appVer = [self label:@"Version 2.5 (Build 11, Universal macOS)"];
        appVer.textColor = NSColor.secondaryLabelColor;
        appVer.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];

        NSTextField *hwLabel = [self label:@"Supported Hardware: Lab599 TX-500 Discovery, TX-500MP & TX-500PRO"];
        hwLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
        hwLabel.textColor = [NSColor colorWithCalibratedRed:0.12 green:0.50 blue:0.90 alpha:1.0];

        NSTextField *authorLabel = [self label:@"Developed by EP2AES (factoreal)"];
        authorLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];

        NSTextField *callsignLabel = [self label:@"Ham Radio Callsign: EP2AES  •  Email: EP2AES@asis.sh"];
        callsignLabel.textColor = NSColor.secondaryLabelColor;
        callsignLabel.font = [NSFont systemFontOfSize:11];

        // Features Card Box
        NSBox *featuresBox = [NSBox new];
        featuresBox.boxType = NSBoxCustom;
        featuresBox.cornerRadius = 8.0;
        featuresBox.borderWidth = 1.0;
        featuresBox.borderColor = [NSColor separatorColor];
        featuresBox.fillColor = [NSColor controlBackgroundColor];
        featuresBox.translatesAutoresizingMaskIntoConstraints = NO;

        NSTextField *boxTitle = [self label:@"Radio Management & Diagnostic Features"];
        boxTitle.font = [NSFont systemFontOfSize:12 weight:NSFontWeightBold];

        NSTextField *featuresList = [NSTextField wrappingLabelWithString:
            @"• Firmware Updates with automatic MCU model detection (Discovery vs MP) & BL20 verification\n"
            @"• Precision Real-Time Clock (RTC) synchronization with host time / UTC\n"
            @"• Real-time CAT command terminal and transceiver diagnostics\n"
            @"• EEPROM Settings backup, restore & side-by-side visual diff comparison\n"
            @"• 100-channel memory manager, operating profiles (SOTA/POTA, FT8, Contest) & CSV import/export\n"
            @"• FTDI D2XX USB serial driver installation & system diagnostics\n"
            @"• Official Lab599 documentation, schematics & firmware downloads library"];
        featuresList.textColor = NSColor.labelColor;
        featuresList.font = [NSFont systemFontOfSize:11];

        NSStackView *boxStack = [NSStackView stackViewWithViews:@[boxTitle, featuresList]];
        boxStack.orientation = NSUserInterfaceLayoutOrientationVertical;
        boxStack.alignment = NSLayoutAttributeLeading;
        boxStack.spacing = 5;
        boxStack.translatesAutoresizingMaskIntoConstraints = NO;
        [featuresBox.contentView addSubview:boxStack];

        [NSLayoutConstraint activateConstraints:@[
            [boxStack.leadingAnchor constraintEqualToAnchor:featuresBox.contentView.leadingAnchor constant:12],
            [boxStack.trailingAnchor constraintEqualToAnchor:featuresBox.contentView.trailingAnchor constant:-12],
            [boxStack.topAnchor constraintEqualToAnchor:featuresBox.contentView.topAnchor constant:10],
            [boxStack.bottomAnchor constraintEqualToAnchor:featuresBox.contentView.bottomAnchor constant:-10],
            [featuresList.widthAnchor constraintEqualToAnchor:boxStack.widthAnchor]
        ]];

        NSTextField *disclaimer = [NSTextField wrappingLabelWithString:
            @"Independent software created for the amateur radio community. Protocols and file formats reverse-engineered from original tools."];
        disclaimer.textColor = NSColor.tertiaryLabelColor;
        disclaimer.font = [NSFont systemFontOfSize:10];
        disclaimer.alignment = NSTextAlignmentCenter;

        // GitHub button
        NSButton *gitBtn = [NSButton buttonWithTitle:@"View on GitHub: https://github.com/fact0real/Lab599-Firmware-Updater"
                                              target:self
                                              action:@selector(openGitHubRepo:)];
        gitBtn.bezelStyle = NSBezelStyleInline;

        NSButton *webBtn = [NSButton buttonWithTitle:@"Official Lab599 Website: https://lab599.com"
                                              target:self
                                              action:@selector(openLab599Website:)];
        webBtn.bezelStyle = NSBezelStyleInline;

        NSButton *closeBtn = [NSButton buttonWithTitle:@"Close" target:self action:@selector(closeAboutWindow:)];
        closeBtn.bezelStyle = NSBezelStyleRounded;
        closeBtn.keyEquivalent = @"\r";

        NSStackView *aboutStack = [NSStackView stackViewWithViews:@[
            iconView, appName, appVer, hwLabel, authorLabel, callsignLabel, featuresBox, disclaimer, gitBtn, webBtn, closeBtn
        ]];
        aboutStack.translatesAutoresizingMaskIntoConstraints = NO;
        aboutStack.orientation = NSUserInterfaceLayoutOrientationVertical;
        aboutStack.alignment = NSLayoutAttributeCenterX;
        aboutStack.spacing = 8;
        [self.aboutWindow.contentView addSubview:aboutStack];

        [NSLayoutConstraint activateConstraints:@[
            [aboutStack.leadingAnchor constraintEqualToAnchor:self.aboutWindow.contentView.leadingAnchor constant:20],
            [aboutStack.trailingAnchor constraintEqualToAnchor:self.aboutWindow.contentView.trailingAnchor constant:-20],
            [aboutStack.topAnchor constraintEqualToAnchor:self.aboutWindow.contentView.topAnchor constant:16],
            [aboutStack.bottomAnchor constraintLessThanOrEqualToAnchor:self.aboutWindow.contentView.bottomAnchor constant:-16],
            [featuresBox.widthAnchor constraintEqualToAnchor:aboutStack.widthAnchor],
            [disclaimer.widthAnchor constraintEqualToAnchor:aboutStack.widthAnchor]
        ]];
    }
    [self.aboutWindow center];
    [self.aboutWindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)closeAboutWindow:(id)sender {
    (void)sender;
    if (self.aboutWindow) {
        [self.aboutWindow orderOut:nil];
    }
}

- (void)openGitHubRepo:(id)sender {
    (void)sender;
    NSURL *url = [NSURL URLWithString:@"https://github.com/fact0real/Lab599-Firmware-Updater"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)openLab599Website:(id)sender {
    (void)sender;
    NSURL *url = [NSURL URLWithString:@"https://lab599.com/downloads"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

#pragma mark - Diagnostic Logs & Alerts

- (void)saveLog:(id)sender {
    (void)sender;
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[UTTypePlainText];
    panel.nameFieldStringValue = @"Lab599-Utility-log.txt";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        NSError *error = nil;
        if (![self.logView.string writeToURL:panel.URL atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
            [self showAlert:@"Log could not be saved" message:error.localizedDescription warning:YES];
        }
    }];
}

- (void)showAlert:(NSString *)title message:(NSString *)message warning:(BOOL)warning {
    NSAlert *alert = [NSAlert new];
    alert.alertStyle = warning ? NSAlertStyleWarning : NSAlertStyleInformational;
    alert.messageText = title;
    alert.informativeText = message;
    [alert addButtonWithTitle:@"OK"];
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

#pragma mark - Firmware Update Process

- (void)startUpdate:(id)sender {
    (void)sender;
    if (self.busy || self.operationPicker.selectedSegment != 0) return;
    NSString *port = self.portMenu.selectedItem.title;
    if (!self.hasPorts || ![port hasPrefix:@"/dev/cu."] || !self.firmwareURL) return;

    NSError *error = nil;
    NSData *firmware = [NSData dataWithContentsOfURL:self.firmwareURL options:0 error:&error];
    NSString *problem = firmware ? TXFirmwareValidationError(firmware) : error.localizedDescription;
    if (problem) {
        [self showAlert:@"Firmware could not be loaded" message:problem warning:YES];
        return;
    }

    NSAlert *confirmation = [NSAlert new];
    confirmation.alertStyle = NSAlertStyleWarning;
    confirmation.messageText = @"Start the firmware update?";
    confirmation.informativeText = [NSString stringWithFormat:
        @"Firmware: %@\nPort: %@\n\nThe transceiver must display \"The loader is waiting...\" and have stable external power. Keep power and USB cable firmly connected throughout the update.",
        self.firmwareURL.lastPathComponent, port];
    [confirmation addButtonWithTitle:@"Start Update"];
    [confirmation addButtonWithTitle:@"Cancel"];
    if ([confirmation runModal] != NSAlertFirstButtonReturn) return;

    self.busy = YES;
    self.operationPicker.enabled = NO;
    self.syncButton.enabled = NO;
    self.timeZoneMenu.enabled = NO;
    self.updateButton.enabled = NO;
    self.portMenu.enabled = NO;
    self.chooseButton.enabled = NO;
    self.onlineButton.enabled = NO;
    self.refreshButton.enabled = NO;
    self.progressBar.doubleValue = 0;
    self.statusLabel.stringValue = @"Starting the update...";
    [self appendLog:[NSString stringWithFormat:@"Starting transfer of %@ on %@.", self.firmwareURL.lastPathComponent, port]];

    self.activity = [[NSProcessInfo processInfo] beginActivityWithOptions:(NSActivityUserInitiated | NSActivityIdleSystemSleepDisabled)
        reason:@"Transferring Lab599 firmware"];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        TXTransferResult *result = TXFlashFirmware(firmware, port, TXDefaultTransferOptions(),
            ^(NSUInteger sent, NSUInteger total) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.progressBar.doubleValue = (double)sent / total;
                    self.statusLabel.stringValue = sent == total ?
                        @"File sent. Waiting for transceiver's final confirmation..." :
                        [NSString stringWithFormat:@"Sending firmware: %lu / %lu bytes (%.1f%%)",
                            (unsigned long)sent, (unsigned long)total, 100.0 * sent / total];
                });
            },
            ^(NSString *message) {
                dispatch_async(dispatch_get_main_queue(), ^{ [self appendLog:message]; });
            });

        dispatch_async(dispatch_get_main_queue(), ^{
            self.busy = NO;
            self.operationPicker.enabled = YES;
            self.timeZoneMenu.enabled = YES;
            [[NSProcessInfo processInfo] endActivity:self.activity];
            self.activity = nil;
            self.chooseButton.enabled = YES;
            self.onlineButton.enabled = YES;
            self.refreshButton.enabled = YES;
            [self refreshPorts:nil];

            if (result.success) {
                self.progressBar.doubleValue = 1;
                self.statusLabel.stringValue = @"Update acknowledged by the transceiver. Restart the radio and check firmware version.";
                [self showAlert:@"Firmware transfer complete"
                        message:@"The radio returned its final OK confirmation. Check its display, then power-cycle the transceiver and verify the firmware version."
                        warning:NO];
            } else {
                self.statusLabel.stringValue = [NSString stringWithFormat:@"Stopped during %@. Check diagnostic log.", result.phase];
                [self showAlert:@"Firmware update was not confirmed"
                        message:[NSString stringWithFormat:@"%@\n\nIf the radio reports \"The firmware is not sent\", power-cycle into Loader mode again before retrying. Save the diagnostic log for troubleshooting.", result.failure]
                        warning:YES];
            }
        });
    });
}

#pragma mark - Window and App Lifecycle

- (BOOL)windowShouldClose:(NSWindow *)sender {
    (void)sender;
    if (!self.busy) { [NSApp terminate:nil]; return NO; }
    NSBeep();
    return NO;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    (void)sender;
    if (!self.busy) return [self.tools confirmDiscard] ? NSTerminateNow : NSTerminateCancel;
    NSBeep();
    return NSTerminateCancel;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return YES;
}

@end

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [AppDelegate new];
        app.delegate = delegate;
        app.activationPolicy = NSApplicationActivationPolicyRegular;
        [app run];
    }
    return 0;
}
