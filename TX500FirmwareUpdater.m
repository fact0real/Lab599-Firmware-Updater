#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "TX500Transfer.h"

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property(nonatomic) NSWindow *window;
@property(nonatomic) NSPopUpButton *portMenu;
@property(nonatomic) NSTextField *firmwareName;
@property(nonatomic) NSTextField *statusLabel;
@property(nonatomic) NSProgressIndicator *progressBar;
@property(nonatomic) NSButton *updateButton;
@property(nonatomic) NSButton *refreshButton;
@property(nonatomic) NSButton *chooseButton;
@property(nonatomic) NSTextView *logView;
@property(nonatomic) NSURL *firmwareURL;
@property(nonatomic) id activity;
@property(nonatomic) BOOL busy;
@property(nonatomic) BOOL hasPorts;
@end

@implementation AppDelegate

- (NSTextField *)label:(NSString *)text {
    NSTextField *field = [NSTextField labelWithString:text];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    return field;
}

- (void)appendLog:(NSString *)message {
    NSAssert([NSThread isMainThread], @"UI logging must run on the main thread.");
    NSString *entry = [NSString stringWithFormat:@"%@  %@\n", [NSDate date].description, message];
    NSDictionary *attributes = @{NSFontAttributeName: [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: NSColor.labelColor};
    [self.logView.textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:entry attributes:attributes]];
    [self.logView scrollRangeToVisible:NSMakeRange(self.logView.string.length, 0)];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 770, 650)
        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"TX-500 Firmware Updater 1.1";
    self.window.delegate = self;
    [self.window center];

    NSMenu *menu = [NSMenu new];
    NSMenuItem *appItem = [NSMenuItem new];
    [menu addItem:appItem];
    NSMenu *appMenu = [NSMenu new];
    [appMenu addItemWithTitle:@"Quit TX-500 Firmware Updater" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;
    NSMenuItem *editItem = [[NSMenuItem alloc] initWithTitle:@"Edit" action:NULL keyEquivalent:@""];
    [menu addItem:editItem];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    editItem.submenu = editMenu;
    NSApp.mainMenu = menu;

    NSTextField *heading = [self label:@"Lab599 TX-500 Firmware Updater"];
    heading.font = [NSFont systemFontOfSize:22 weight:NSFontWeightSemibold];
    NSTextField *subtitle = [self label:@"Version 1.1  |  Unofficial native macOS utility"];
    subtitle.textColor = NSColor.secondaryLabelColor;
    NSTextField *instructions = [NSTextField wrappingLabelWithString:
        @"Connect the CAT-USB cable and stable external power. Close other radio applications. For TX-500 Discovery, hold the third top function key while pressing POWER. Start only when the radio shows \"The loader is waiting...\". Keep power and the cable connected until the radio confirms completion."];
    instructions.textColor = NSColor.secondaryLabelColor;

    self.portMenu = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.portMenu.translatesAutoresizingMaskIntoConstraints = NO;
    self.refreshButton = [NSButton buttonWithTitle:@"Refresh" target:self action:@selector(refreshPorts:)];
    NSStackView *portRow = [NSStackView stackViewWithViews:@[[self label:@"Serial port:"], self.portMenu, self.refreshButton]];
    portRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    portRow.alignment = NSLayoutAttributeCenterY;
    portRow.spacing = 10;
    [self.portMenu.widthAnchor constraintEqualToConstant:390].active = YES;

    self.firmwareName = [self label:@"No firmware selected"];
    self.firmwareName.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [self.firmwareName.widthAnchor constraintEqualToConstant:390].active = YES;
    self.chooseButton = [NSButton buttonWithTitle:@"Choose .fw..." target:self action:@selector(chooseFirmware:)];
    NSStackView *fileRow = [NSStackView stackViewWithViews:@[[self label:@"Firmware:"], self.firmwareName, self.chooseButton]];
    fileRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    fileRow.alignment = NSLayoutAttributeCenterY;
    fileRow.spacing = 10;

    self.progressBar = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    self.progressBar.minValue = 0;
    self.progressBar.maxValue = 1;
    self.progressBar.indeterminate = NO;
    self.statusLabel = [NSTextField wrappingLabelWithString:@"Select the radio's serial port and the correct firmware file."];
    self.statusLabel.textColor = NSColor.secondaryLabelColor;
    [self.statusLabel.heightAnchor constraintGreaterThanOrEqualToConstant:38].active = YES;
    self.updateButton = [NSButton buttonWithTitle:@"Update Firmware" target:self action:@selector(startUpdate:)];
    NSButton *saveButton = [NSButton buttonWithTitle:@"Save Diagnostic Log..." target:self action:@selector(saveLog:)];
    NSStackView *buttonRow = [NSStackView stackViewWithViews:@[self.updateButton, saveButton]];
    buttonRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttonRow.spacing = 12;

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    self.logView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 700, 190)];
    self.logView.editable = NO;
    self.logView.selectable = YES;
    self.logView.richText = NO;
    self.logView.verticallyResizable = YES;
    self.logView.horizontallyResizable = NO;
    self.logView.autoresizingMask = NSViewWidthSizable;
    self.logView.textContainer.widthTracksTextView = YES;
    self.logView.textContainerInset = NSMakeSize(8, 8);
    scroll.documentView = self.logView;
    [scroll.heightAnchor constraintEqualToConstant:190].active = YES;

    NSStackView *stack = [NSStackView stackViewWithViews:@[heading, subtitle, instructions,
        portRow, fileRow, self.progressBar, self.statusLabel, buttonRow, [self label:@"Diagnostic log"], scroll]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 13;
    [self.window.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.window.contentView.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:self.window.contentView.trailingAnchor constant:-24],
        [stack.topAnchor constraintEqualToAnchor:self.window.contentView.topAnchor constant:24],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:self.window.contentView.bottomAnchor constant:-24],
        [instructions.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [self.progressBar.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [self.statusLabel.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [scroll.widthAnchor constraintEqualToAnchor:stack.widthAnchor]
    ]];
    [self appendLog:@"Updater 1.1. Protocol: 16-byte header -> OK -> full payload -> final OK."];
    [self refreshPorts:nil];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)refreshPorts:(id)sender {
    if (self.busy) return;
    NSString *previous = self.portMenu.selectedItem.title;
    NSArray<NSString *> *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/dev" error:NULL] ?: @[];
    NSPredicate *match = [NSPredicate predicateWithBlock:^BOOL(NSString *name, NSDictionary *bindings) {
        return [name hasPrefix:@"cu."] && ![name.lowercaseString containsString:@"bluetooth"] &&
            ![name.lowercaseString containsString:@"debug"];
    }];
    NSArray *ports = [[names filteredArrayUsingPredicate:match] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    [self.portMenu removeAllItems];
    self.hasPorts = ports.count > 0;
    if (!self.hasPorts) [self.portMenu addItemWithTitle:@"No serial ports found"];
    for (NSString *name in ports) [self.portMenu addItemWithTitle:[@"/dev/" stringByAppendingString:name]];
    if (previous && [self.portMenu itemWithTitle:previous]) [self.portMenu selectItemWithTitle:previous];
    self.portMenu.enabled = self.hasPorts;
    self.updateButton.enabled = self.hasPorts && self.firmwareURL != nil;
    if (sender) self.statusLabel.stringValue = self.hasPorts ? @"Select the port connected to the radio's CAT cable." :
        @"Connect the CAT-USB adapter and click Refresh. A working serial driver is required.";
}

- (void)chooseFirmware:(id)sender {
    if (self.busy) return;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"fw" conformingToType:UTTypeData]];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || !panel.URL) return;
        NSError *readError = nil;
        NSData *data = [NSData dataWithContentsOfURL:panel.URL options:0 error:&readError];
        NSString *problem = data ? TXFirmwareValidationError(data) : readError.localizedDescription;
        if (problem) { [self showAlert:@"Firmware could not be loaded" message:problem warning:YES]; return; }
        self.firmwareURL = panel.URL;
        self.firmwareName.stringValue = panel.URL.lastPathComponent;
        self.firmwareName.toolTip = panel.URL.path;
        NSString *hash = TXFirmwareSHA256(data);
        [self appendLog:[NSString stringWithFormat:@"Selected %@ (%lu bytes). SHA-256: %@",
            panel.URL.lastPathComponent, (unsigned long)data.length, hash]];
        if ([hash isEqualToString:@"2162fed7d27987507c8b412f3d38478c0a670a906a0c747578d7c975ad5a04ea"])
            [self appendLog:@"Matches the TX-500 Discovery v1.30.00 download checked on 2026-09-18."];
        self.statusLabel.stringValue = @"Ready. Check that this firmware is for your exact radio model and that Loader is waiting.";
        self.updateButton.enabled = self.hasPorts;
    }];
}

- (void)saveLog:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[UTTypePlainText];
    panel.nameFieldStringValue = @"TX500-updater-log.txt";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        NSError *error = nil;
        if (![self.logView.string writeToURL:panel.URL atomically:YES encoding:NSUTF8StringEncoding error:&error])
            [self showAlert:@"Log could not be saved" message:error.localizedDescription warning:YES];
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

- (void)startUpdate:(id)sender {
    if (self.busy) return;
    NSString *port = self.portMenu.selectedItem.title;
    if (!self.hasPorts || ![port hasPrefix:@"/dev/cu."] || !self.firmwareURL) return;
    NSError *error = nil;
    NSData *firmware = [NSData dataWithContentsOfURL:self.firmwareURL options:0 error:&error];
    NSString *problem = firmware ? TXFirmwareValidationError(firmware) : error.localizedDescription;
    if (problem) { [self showAlert:@"Firmware could not be loaded" message:problem warning:YES]; return; }

    NSAlert *confirmation = [NSAlert new];
    confirmation.alertStyle = NSAlertStyleWarning;
    confirmation.messageText = @"Start the firmware update?";
    confirmation.informativeText = [NSString stringWithFormat:
        @"File: %@\nPort: %@\n\nThe radio must show \"The loader is waiting...\" and have stable external power. Keep power and the cable connected throughout the update.",
        self.firmwareURL.lastPathComponent, port];
    [confirmation addButtonWithTitle:@"Start Update"];
    [confirmation addButtonWithTitle:@"Cancel"];
    if ([confirmation runModal] != NSAlertFirstButtonReturn) return;

    self.busy = YES;
    self.updateButton.enabled = NO;
    self.portMenu.enabled = NO;
    self.chooseButton.enabled = NO;
    self.refreshButton.enabled = NO;
    self.progressBar.doubleValue = 0;
    self.statusLabel.stringValue = @"Starting the update...";
    [self appendLog:[NSString stringWithFormat:@"Starting %@ on %@.", self.firmwareURL.lastPathComponent, port]];
    self.activity = [[NSProcessInfo processInfo] beginActivityWithOptions:(NSActivityUserInitiated | NSActivityIdleSystemSleepDisabled)
        reason:@"Transferring TX-500 firmware"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        TXTransferResult *result = TXFlashFirmware(firmware, port, TXDefaultTransferOptions(),
            ^(NSUInteger sent, NSUInteger total) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.progressBar.doubleValue = (double)sent / total;
                    self.statusLabel.stringValue = sent == total ? @"File sent. Waiting for the radio's final confirmation..." :
                        [NSString stringWithFormat:@"Sending firmware: %lu / %lu bytes (%.1f%%)",
                            (unsigned long)sent, (unsigned long)total, 100.0 * sent / total];
                });
            },
            ^(NSString *message) {
                dispatch_async(dispatch_get_main_queue(), ^{ [self appendLog:message]; });
            });
        dispatch_async(dispatch_get_main_queue(), ^{
            self.busy = NO;
            [[NSProcessInfo processInfo] endActivity:self.activity];
            self.activity = nil;
            self.chooseButton.enabled = YES;
            self.refreshButton.enabled = YES;
            [self refreshPorts:nil];
            if (result.success) {
                self.progressBar.doubleValue = 1;
                self.statusLabel.stringValue = @"Update acknowledged by the radio. Restart it and check the firmware version.";
                [self showAlert:@"Firmware transfer complete" message:@"The radio returned its final OK. Check its display, then turn it off and on and verify the firmware version." warning:NO];
            } else {
                self.statusLabel.stringValue = [NSString stringWithFormat:@"Stopped during %@. See the diagnostic log.", result.phase];
                [self showAlert:@"Firmware update was not confirmed" message:[NSString stringWithFormat:
                    @"%@\n\nDo not treat this as a successful update. If the radio reports \"The firmware is not sent\", re-enter Loader before another attempt. If it is still programming, keep power connected. Save the diagnostic log for troubleshooting.", result.failure] warning:YES];
            }
        });
    });
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
    if (!self.busy) return YES;
    NSBeep();
    return NO;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    if (!self.busy) return NSTerminateNow;
    NSBeep();
    return NSTerminateCancel;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [AppDelegate new];
        app.delegate = delegate;
        app.activationPolicy = NSApplicationActivationPolicyRegular;
        [app run];
    }
    return 0;
}
