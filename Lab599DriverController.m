#import "Lab599DriverController.h"
#import <dlfcn.h>
#import <sys/xattr.h>

@interface Lab599DriverController ()
@property(nonatomic, strong, readwrite) NSView *view;
@property(nonatomic, strong) NSTextField *statusTitleLabel;
@property(nonatomic, strong) NSTextField *statusDetailLabel;
@property(nonatomic, strong) NSTextField *portsDetailLabel;
@property(nonatomic, strong) NSImageView *radioImageView;
@property(nonatomic, strong) NSButton *installButton;
@property(nonatomic, strong) NSButton *fixGatekeeperButton;
@property(nonatomic, strong) NSButton *verifyButton;
@property(nonatomic, strong) NSButton *uninstallButton;
@property(nonatomic, strong) NSButton *manualButton;
@property(nonatomic) BOOL isDriverInstalled;
@property(nonatomic) BOOL isQuarantined;
@end

@implementation Lab599DriverController

static NSTextField *CreateLabel(NSString *text, BOOL bold, CGFloat size, NSColor *color) {
    NSTextField *field = [NSTextField wrappingLabelWithString:text];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.font = bold ? [NSFont systemFontOfSize:size weight:NSFontWeightBold] :
                        [NSFont systemFontOfSize:size weight:NSFontWeightRegular];
    if (color) field.textColor = color;
    return field;
}

static NSBox *CreateCardBox(void) {
    NSBox *box = [NSBox new];
    box.translatesAutoresizingMaskIntoConstraints = NO;
    box.boxType = NSBoxCustom;
    box.cornerRadius = 8.0;
    box.borderWidth = 1.0;
    box.borderColor = [NSColor separatorColor];
    box.fillColor = [NSColor colorWithCalibratedWhite:0.5 alpha:0.04];
    return box;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    [self buildUI];
    [self checkDriverStatus];
    return self;
}

- (NSImage *)loadRadioImage {
    // 1. Try bundle resource
    NSImage *image = [NSImage imageNamed:@"tx500_radio"];
    if (image) return image;

    NSString *resPath = [[NSBundle mainBundle] pathForResource:@"tx500_radio" ofType:@"png"];
    if (resPath && [[NSFileManager defaultManager] fileExistsAtPath:resPath]) {
        image = [[NSImage alloc] initWithContentsOfFile:resPath];
        if (image) return image;
    }

    // 2. Relative paths (dev/runtime/tests)
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

- (void)buildUI {
    self.view = [NSView new];
    self.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view.heightAnchor constraintEqualToConstant:465].active = YES;

    // =========================================================================
    // CARD 1: Radio Hardware Identification & Target Specs (Height: 128)
    // =========================================================================
    NSBox *radioCard = CreateCardBox();

    // Left: Radio Image Container & View
    self.radioImageView = [NSImageView new];
    self.radioImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.radioImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    self.radioImageView.imageAlignment = NSImageAlignCenter;
    self.radioImageView.image = [self loadRadioImage];
    self.radioImageView.wantsLayer = YES;
    self.radioImageView.layer.cornerRadius = 6.0;
    self.radioImageView.layer.masksToBounds = YES;

    NSBox *imageContainer = [NSBox new];
    imageContainer.translatesAutoresizingMaskIntoConstraints = NO;
    imageContainer.boxType = NSBoxCustom;
    imageContainer.cornerRadius = 6.0;
    imageContainer.borderWidth = 1.0;
    imageContainer.borderColor = [NSColor colorWithCalibratedWhite:0.5 alpha:0.25];
    imageContainer.fillColor = [NSColor colorWithCalibratedWhite:0.0 alpha:0.08];

    [imageContainer.contentView addSubview:self.radioImageView];
    [NSLayoutConstraint activateConstraints:@[
        [self.radioImageView.leadingAnchor constraintEqualToAnchor:imageContainer.contentView.leadingAnchor constant:4],
        [self.radioImageView.trailingAnchor constraintEqualToAnchor:imageContainer.contentView.trailingAnchor constant:-4],
        [self.radioImageView.topAnchor constraintEqualToAnchor:imageContainer.contentView.topAnchor constant:4],
        [self.radioImageView.bottomAnchor constraintEqualToAnchor:imageContainer.contentView.bottomAnchor constant:-4],
        [imageContainer.widthAnchor constraintEqualToConstant:220],
        [imageContainer.heightAnchor constraintEqualToConstant:106]
    ]];

    // Right: Hardware Specs Stack
    NSTextField *radioTitle = CreateLabel(@"Lab599 TX-500 Discovery / TX-500MP", YES, 14, NSColor.labelColor);
    NSTextField *radioSubtitle = CreateLabel(@"Ultra-Compact All-Band, All-Mode HF/6m Transceiver (5–10W)", NO, 11, NSColor.secondaryLabelColor);

    NSTextField *specCable = CreateLabel(@"• Interface Cable: Lab599 AD-502 (GX12 7-Pin to USB-A CAT Cable)", NO, 11, NSColor.labelColor);
    NSTextField *specChipset = CreateLabel(@"• USB Chipset: FTDI FT232R / FT-X Series UART (VID: 0x0403, PID: 0x6001 / 0x6015)", NO, 11, NSColor.labelColor);
    NSTextField *specDriver = CreateLabel(@"• Target Driver: FTDI D2XX Direct Architecture (libftd2xx.1.4.35.dylib)", NO, 11, NSColor.secondaryLabelColor);
    NSTextField *specArch = CreateLabel(@"• Compatibility: macOS Universal (Apple Silicon M1–M4 & Intel x86_64)", NO, 11, NSColor.secondaryLabelColor);

    NSStackView *specsStack = [NSStackView stackViewWithViews:@[
        radioTitle, radioSubtitle, specCable, specChipset, specDriver, specArch
    ]];
    specsStack.translatesAutoresizingMaskIntoConstraints = NO;
    specsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    specsStack.alignment = NSLayoutAttributeLeading;
    specsStack.spacing = 3;

    NSStackView *card1HStack = [NSStackView stackViewWithViews:@[imageContainer, specsStack]];
    card1HStack.translatesAutoresizingMaskIntoConstraints = NO;
    card1HStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    card1HStack.alignment = NSLayoutAttributeCenterY;
    card1HStack.spacing = 16;

    [radioCard.contentView addSubview:card1HStack];
    [NSLayoutConstraint activateConstraints:@[
        [card1HStack.leadingAnchor constraintEqualToAnchor:radioCard.contentView.leadingAnchor constant:12],
        [card1HStack.trailingAnchor constraintEqualToAnchor:radioCard.contentView.trailingAnchor constant:-12],
        [card1HStack.topAnchor constraintEqualToAnchor:radioCard.contentView.topAnchor constant:8],
        [card1HStack.bottomAnchor constraintEqualToAnchor:radioCard.contentView.bottomAnchor constant:-8],
        [radioCard.heightAnchor constraintEqualToConstant:128]
    ]];

    // =========================================================================
    // CARD 2: Driver Status & System Diagnostics (Height: 96)
    // =========================================================================
    NSBox *statusCard = CreateCardBox();

    self.statusTitleLabel = CreateLabel(@"Checking driver status...", YES, 13, NSColor.labelColor);
    self.statusDetailLabel = CreateLabel(@"", NO, 11, NSColor.secondaryLabelColor);
    self.statusDetailLabel.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];

    self.portsDetailLabel = CreateLabel(@"Scanning USB serial ports...", NO, 11, NSColor.secondaryLabelColor);
    self.portsDetailLabel.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];

    NSButton *refreshStatusBtn = [NSButton buttonWithTitle:@"Refresh Status & Ports" target:self action:@selector(checkDriverStatus)];
    refreshStatusBtn.bezelStyle = NSBezelStyleInline;

    NSView *statusSpacer = [NSView new];
    statusSpacer.translatesAutoresizingMaskIntoConstraints = NO;
    [statusSpacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *statusTopRow = [NSStackView stackViewWithViews:@[self.statusTitleLabel, statusSpacer, refreshStatusBtn]];
    statusTopRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    statusTopRow.alignment = NSLayoutAttributeCenterY;
    statusTopRow.spacing = 8;

    NSStackView *statusVStack = [NSStackView stackViewWithViews:@[
        statusTopRow, self.statusDetailLabel, self.portsDetailLabel
    ]];
    statusVStack.translatesAutoresizingMaskIntoConstraints = NO;
    statusVStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    statusVStack.alignment = NSLayoutAttributeLeading;
    statusVStack.spacing = 4;

    [statusCard.contentView addSubview:statusVStack];
    [NSLayoutConstraint activateConstraints:@[
        [statusVStack.leadingAnchor constraintEqualToAnchor:statusCard.contentView.leadingAnchor constant:12],
        [statusVStack.trailingAnchor constraintEqualToAnchor:statusCard.contentView.trailingAnchor constant:-12],
        [statusVStack.topAnchor constraintEqualToAnchor:statusCard.contentView.topAnchor constant:8],
        [statusVStack.bottomAnchor constraintEqualToAnchor:statusCard.contentView.bottomAnchor constant:-8],
        [statusCard.heightAnchor constraintEqualToConstant:96],
        [statusTopRow.widthAnchor constraintEqualToAnchor:statusVStack.widthAnchor]
    ]];

    // =========================================================================
    // ACTION BUTTONS ROW (Height: 30)
    // =========================================================================
    self.installButton = [NSButton buttonWithTitle:@"Install / Update Driver" target:self action:@selector(installDriver:)];
    self.installButton.bezelStyle = NSBezelStyleRounded;

    self.fixGatekeeperButton = [NSButton buttonWithTitle:@"Fix Gatekeeper & Authorize" target:self action:@selector(fixGatekeeper:)];
    self.fixGatekeeperButton.bezelStyle = NSBezelStyleRounded;
    self.fixGatekeeperButton.hidden = YES;

    self.verifyButton = [NSButton buttonWithTitle:@"Verify Installation" target:self action:@selector(verifyDriver:)];
    self.verifyButton.bezelStyle = NSBezelStyleRounded;

    self.uninstallButton = [NSButton buttonWithTitle:@"Uninstall Driver" target:self action:@selector(uninstallDriver:)];
    self.uninstallButton.bezelStyle = NSBezelStyleRounded;

    self.manualButton = [NSButton buttonWithTitle:@"Open FT8 macOS Guide (PDF)" target:self action:@selector(openGuidePDF:)];
    self.manualButton.bezelStyle = NSBezelStyleRounded;

    NSStackView *actionRow = [NSStackView stackViewWithViews:@[
        self.installButton, self.fixGatekeeperButton, self.verifyButton, self.uninstallButton, self.manualButton
    ]];
    actionRow.translatesAutoresizingMaskIntoConstraints = NO;
    actionRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    actionRow.spacing = 10;
    actionRow.alignment = NSLayoutAttributeCenterY;
    actionRow.detachesHiddenViews = YES;
    [actionRow.heightAnchor constraintEqualToConstant:32].active = YES;

    // =========================================================================
    // CARD 3: Radio Menu Configuration & Guide (Height: 165)
    // =========================================================================
    NSBox *guideCard = CreateCardBox();

    NSTextField *guideHeader = CreateLabel(@"Radio Menu Configuration & WSJT-X Guide (tx500_ft8_macos_v6):", YES, 12, NSColor.labelColor);

    // Left Column: Radio Menu Checklist
    NSTextField *col1Title = CreateLabel(@"TX-500 Front-Panel Menu Steps:", YES, 11, NSColor.labelColor);
    NSTextField *step1 = CreateLabel(@"1. Power on TX-500 Discovery / TX-500MP normally.", NO, 11, NSColor.secondaryLabelColor);
    NSTextField *step2 = CreateLabel(@"2. Menu 34 (CAT Protocol) -> Set to TS2000 (Kenwood compatible).", NO, 11, NSColor.secondaryLabelColor);
    NSTextField *step3 = CreateLabel(@"3. Menu 35 (CAT Rate) -> Set to 9600 baud.", NO, 11, NSColor.secondaryLabelColor);
    NSTextField *step4 = CreateLabel(@"4. Cable: Reconnect AD-502 USB cable after driver install.", NO, 11, NSColor.secondaryLabelColor);

    NSStackView *col1Stack = [NSStackView stackViewWithViews:@[col1Title, step1, step2, step3, step4]];
    col1Stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    col1Stack.alignment = NSLayoutAttributeLeading;
    col1Stack.spacing = 3;
    [col1Stack.widthAnchor constraintEqualToConstant:380].active = YES;

    // Right Column: Technical & Digital Mode Notes
    NSTextField *col2Title = CreateLabel(@"macOS & Digital Mode Reference:", YES, 11, NSColor.labelColor);
    NSTextField *note1 = CreateLabel(@"• macOS Sequoia / Sonoma: Default CDC serial driver drops callout nodes; FTDI D2XX solves this.", NO, 11, NSColor.secondaryLabelColor);
    NSTextField *note2 = CreateLabel(@"• WSJT-X / JTDX Rig: Choose \"Kenwood TS-2000\", 9600 baud, 8N1, PTT: CAT.", NO, 11, NSColor.secondaryLabelColor);
    NSTextField *note3 = CreateLabel(@"• Gatekeeper: If macOS displays \"libftd2xx Not Opened\", click \"Fix Gatekeeper & Authorize\".", NO, 11, NSColor.secondaryLabelColor);

    NSStackView *col2Stack = [NSStackView stackViewWithViews:@[col2Title, note1, note2, note3]];
    col2Stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    col2Stack.alignment = NSLayoutAttributeLeading;
    col2Stack.spacing = 3;
    [col2Stack.widthAnchor constraintEqualToConstant:430].active = YES;

    NSStackView *guideColumns = [NSStackView stackViewWithViews:@[col1Stack, col2Stack]];
    guideColumns.translatesAutoresizingMaskIntoConstraints = NO;
    guideColumns.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    guideColumns.alignment = NSLayoutAttributeTop;
    guideColumns.spacing = 16;

    NSStackView *guideVStack = [NSStackView stackViewWithViews:@[guideHeader, guideColumns]];
    guideVStack.translatesAutoresizingMaskIntoConstraints = NO;
    guideVStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    guideVStack.alignment = NSLayoutAttributeLeading;
    guideVStack.spacing = 6;

    [guideCard.contentView addSubview:guideVStack];
    [NSLayoutConstraint activateConstraints:@[
        [guideVStack.leadingAnchor constraintEqualToAnchor:guideCard.contentView.leadingAnchor constant:12],
        [guideVStack.trailingAnchor constraintEqualToAnchor:guideCard.contentView.trailingAnchor constant:-12],
        [guideVStack.topAnchor constraintEqualToAnchor:guideCard.contentView.topAnchor constant:8],
        [guideVStack.bottomAnchor constraintEqualToAnchor:guideCard.contentView.bottomAnchor constant:-8],
        [guideCard.heightAnchor constraintEqualToConstant:165],
        [guideColumns.widthAnchor constraintEqualToAnchor:guideVStack.widthAnchor]
    ]];

    // =========================================================================
    // MAIN STACK LAYOUT
    // =========================================================================
    NSStackView *mainStack = [NSStackView stackViewWithViews:@[
        radioCard, statusCard, actionRow, guideCard
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
        [radioCard.widthAnchor constraintEqualToAnchor:mainStack.widthAnchor],
        [statusCard.widthAnchor constraintEqualToAnchor:mainStack.widthAnchor],
        [actionRow.widthAnchor constraintEqualToAnchor:mainStack.widthAnchor],
        [guideCard.widthAnchor constraintEqualToAnchor:mainStack.widthAnchor]
    ]];
}

- (NSString *)locateDriverSourceDirectory {
    // 1. Check inside application bundle Resources/ftdi
    NSString *bundlePath = [[NSBundle mainBundle] pathForResource:@"ftdi" ofType:nil];
    if (bundlePath && [[NSFileManager defaultManager] fileExistsAtPath:[bundlePath stringByAppendingPathComponent:@"libftd2xx.1.4.35.dylib"]]) {
        return bundlePath;
    }

    // 2. Check relative to executable (dev/build mode)
    NSString *execDir = [[NSBundle mainBundle] bundlePath];
    NSArray<NSString *> *candidates = @[
        [execDir stringByAppendingPathComponent:@"Contents/Resources/ftdi"],
        [execDir stringByAppendingPathComponent:@"assets/ftdi"],
        @"assets/ftdi",
        @"../assets/ftdi",
        @"../FTDICHIP",
        @"FTDICHIP",
        @"/Users/factoreal/Downloads/TX-500/Updater/assets/ftdi",
        @"/Users/factoreal/Downloads/TX-500/FTDICHIP"
    ];

    for (NSString *cand in candidates) {
        NSString *dylibPath = [cand stringByAppendingPathComponent:@"build/libftd2xx.1.4.35.dylib"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:dylibPath]) {
            return cand;
        }
        dylibPath = [cand stringByAppendingPathComponent:@"libftd2xx.1.4.35.dylib"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:dylibPath]) {
            return cand;
        }
    }
    return nil;
}

- (void)checkDriverStatus {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dylibPath = @"/usr/local/lib/libftd2xx.dylib";
    NSString *targetDylib = @"/usr/local/lib/libftd2xx.1.4.35.dylib";
    NSString *headerPath = @"/usr/local/include/ftd2xx.h";
    NSString *winTypesPath = @"/usr/local/include/WinTypes.h";

    BOOL dylibExists = [fm fileExistsAtPath:dylibPath];
    BOOL targetExists = [fm fileExistsAtPath:targetDylib];
    BOOL headerExists = [fm fileExistsAtPath:headerPath];
    BOOL winTypesExists = [fm fileExistsAtPath:winTypesPath];

    // Check quarantine attribute without dlopen (dlopen triggers Gatekeeper popups if quarantined)
    ssize_t qTarget = targetExists ? getxattr([targetDylib fileSystemRepresentation], "com.apple.quarantine", NULL, 0, 0, 0) : -1;
    ssize_t qDylib = dylibExists ? getxattr([dylibPath fileSystemRepresentation], "com.apple.quarantine", NULL, 0, 0, 0) : -1;
    self.isQuarantined = (qTarget > 0 || qDylib > 0);
    self.isDriverInstalled = (dylibExists || targetExists);

    if (self.isDriverInstalled && self.isQuarantined) {
        self.statusTitleLabel.stringValue = @"▲ FTDI Driver: Blocked by macOS Gatekeeper (Quarantine Active)";
        self.statusTitleLabel.textColor = [NSColor systemOrangeColor];
        self.statusDetailLabel.stringValue =
            @"File installed in /usr/local/lib, but Gatekeeper blocked it (\"libftd2xx Not Opened\"). Click \"Fix Gatekeeper & Authorize\" below.";
        self.fixGatekeeperButton.hidden = NO;
        self.installButton.title = @"Reinstall Driver";
        self.uninstallButton.enabled = YES;
    } else if (self.isDriverInstalled && !self.isQuarantined) {
        self.statusTitleLabel.stringValue = @"● FTDI D2XX Driver: Installed & Authorized (v1.4.35)";
        self.statusTitleLabel.textColor = [NSColor systemGreenColor];
        self.statusDetailLabel.stringValue = [NSString stringWithFormat:
            @"Runtime: %@ (Universal: arm64 & x86_64) | Headers: /usr/local/include (ftd2xx.h: %@, WinTypes.h: %@)",
            targetExists ? targetDylib : dylibPath,
            headerExists ? @"Present" : @"Missing",
            winTypesExists ? @"Present" : @"Missing"
        ];
        self.fixGatekeeperButton.hidden = YES;
        self.installButton.title = @"Reinstall / Repair Driver";
        self.uninstallButton.enabled = YES;
    } else {
        self.statusTitleLabel.stringValue = @"○ FTDI D2XX Driver: NOT Installed";
        self.statusTitleLabel.textColor = [NSColor systemRedColor];
        self.statusDetailLabel.stringValue = @"FTDI D2XX runtime is missing from /usr/local/lib. Click Install below to configure.";
        self.fixGatekeeperButton.hidden = YES;
        self.installButton.title = @"Install FTDI D2XX Driver";
        self.uninstallButton.enabled = NO;
    }

    [self refreshDevices];
}

- (void)refreshDevices {
    NSArray<NSString *> *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/dev" error:NULL] ?: @[];
    NSMutableArray<NSString *> *ftdiPorts = [NSMutableArray array];

    for (NSString *name in names) {
        if ([name hasPrefix:@"cu.usbserial"] || [name hasPrefix:@"cu.FT"]) {
            [ftdiPorts addObject:[@"/dev/" stringByAppendingString:name]];
        }
    }

    if (ftdiPorts.count > 0) {
        self.portsDetailLabel.stringValue = [NSString stringWithFormat:@"✓ Connected FTDI CAT Port: %@ (Ready for 9600 baud)", [ftdiPorts componentsJoinedByString:@", "]];
        self.portsDetailLabel.textColor = [NSColor systemGreenColor];
    } else {
        self.portsDetailLabel.stringValue = @"○ Connected FTDI CAT Port: None currently active. Connect AD-502 CAT-USB cable to your Mac.";
        self.portsDetailLabel.textColor = [NSColor secondaryLabelColor];
    }
}

- (void)installDriver:(id)sender {
    (void)sender;
    NSString *sourceDir = [self locateDriverSourceDirectory];
    if (!sourceDir) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Driver Source Files Not Found";
        alert.informativeText = @"Could not locate libftd2xx.1.4.35.dylib in the application bundle or local folders.";
        alert.alertStyle = NSAlertStyleCritical;
        [alert runModal];
        return;
    }

    NSString *dylibSrc = [sourceDir stringByAppendingPathComponent:@"libftd2xx.1.4.35.dylib"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:dylibSrc]) {
        dylibSrc = [sourceDir stringByAppendingPathComponent:@"build/libftd2xx.1.4.35.dylib"];
    }
    NSString *headerSrc = [sourceDir stringByAppendingPathComponent:@"ftd2xx.h"];
    NSString *winTypesSrc = [sourceDir stringByAppendingPathComponent:@"WinTypes.h"];

    if (![[NSFileManager defaultManager] fileExistsAtPath:dylibSrc] ||
        ![[NSFileManager defaultManager] fileExistsAtPath:headerSrc] ||
        ![[NSFileManager defaultManager] fileExistsAtPath:winTypesSrc]) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Incomplete Driver Package";
        alert.informativeText = [NSString stringWithFormat:@"One or more required files (dylib or headers) are missing in %@.", sourceDir];
        alert.alertStyle = NSAlertStyleCritical;
        [alert runModal];
        return;
    }

    if (self.log) self.log(@"Starting automated FTDI D2XX driver installation...");
    if (self.statusChanged) self.statusChanged(@"Requesting administrator privileges for driver installation...", 0.3);

    // Build privileged command string with automatic quarantine removal & signing
    NSString *commands = [NSString stringWithFormat:
        @"mkdir -p /usr/local/lib /usr/local/include && "
        @"/bin/cp '%@' /usr/local/lib/libftd2xx.1.4.35.dylib && "
        @"/bin/ln -sf /usr/local/lib/libftd2xx.1.4.35.dylib /usr/local/lib/libftd2xx.dylib && "
        @"/bin/cp '%@' /usr/local/include/ftd2xx.h && "
        @"/bin/cp '%@' /usr/local/include/WinTypes.h && "
        @"/bin/chmod 755 /usr/local/lib/libftd2xx.1.4.35.dylib && "
        @"/bin/chmod 644 /usr/local/include/ftd2xx.h /usr/local/include/WinTypes.h && "
        @"/usr/bin/xattr -cr /usr/local/lib/libftd2xx* /usr/local/include/ftd2xx* /usr/local/include/WinTypes* 2>/dev/null && "
        @"/usr/bin/codesign --force --sign - /usr/local/lib/libftd2xx.1.4.35.dylib 2>/dev/null || true",
        dylibSrc, headerSrc, winTypesSrc
    ];

    // Escape for AppleScript string
    NSString *escapedCmd = [commands stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    escapedCmd = [escapedCmd stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];

    NSString *scriptSource = [NSString stringWithFormat:@"do shell script \"%@\" with administrator privileges", escapedCmd];
    NSAppleScript *appleScript = [[NSAppleScript alloc] initWithSource:scriptSource];
    NSDictionary *errorInfo = nil;

    NSAppleEventDescriptor *result = [appleScript executeAndReturnError:&errorInfo];

    if (errorInfo != nil || result == nil) {
        NSString *errDesc = errorInfo[NSAppleScriptErrorMessage] ?: @"User cancelled or failed authorization.";
        if (self.log) self.log([NSString stringWithFormat:@"Driver installation error: %@", errDesc]);
        if (self.statusChanged) self.statusChanged(@"Driver installation cancelled or failed.", 0.0);

        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Driver Installation Incomplete";
        alert.informativeText = errDesc;
        alert.alertStyle = NSAlertStyleWarning;
        [alert runModal];
        return;
    }

    if (self.log) self.log(@"FTDI D2XX runtime installed and authorized in /usr/local/lib.");
    if (self.statusChanged) self.statusChanged(@"FTDI D2XX driver successfully installed and verified.", 1.0);

    [self checkDriverStatus];

    NSAlert *success = [NSAlert new];
    success.messageText = @"Driver Installed Successfully";
    success.informativeText =
        @"FTDI D2XX v1.4.35 runtime and header files have been installed to /usr/local/lib and /usr/local/include.\n\n"
        @"Gatekeeper quarantine attributes have been cleared.\n\n"
        @"Important: Please disconnect and reconnect your AD-502 CAT-USB adapter cable now so macOS assigns the driver properly.";
    success.alertStyle = NSAlertStyleInformational;
    [success runModal];
}

- (void)fixGatekeeper:(id)sender {
    (void)sender;
    if (self.log) self.log(@"Requesting authorization to clear Gatekeeper quarantine on FTDI driver...");
    if (self.statusChanged) self.statusChanged(@"Authorizing FTDI driver with administrator privileges...", 0.5);

    NSString *cmd = @"/usr/bin/xattr -cr /usr/local/lib/libftd2xx* /usr/local/include/ftd2xx* /usr/local/include/WinTypes* 2>/dev/null && /usr/bin/codesign --force --sign - /usr/local/lib/libftd2xx.1.4.35.dylib 2>/dev/null || true";
    NSString *escapedCmd = [cmd stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    NSString *scriptSource = [NSString stringWithFormat:@"do shell script \"%@\" with administrator privileges", escapedCmd];
    NSAppleScript *appleScript = [[NSAppleScript alloc] initWithSource:scriptSource];
    NSDictionary *errorInfo = nil;
    NSAppleEventDescriptor *result = [appleScript executeAndReturnError:&errorInfo];

    if (errorInfo != nil || result == nil) {
        NSString *errDesc = errorInfo[NSAppleScriptErrorMessage] ?: @"Authorization cancelled or failed.";
        if (self.log) self.log([NSString stringWithFormat:@"Gatekeeper authorization error: %@", errDesc]);
        if (self.statusChanged) self.statusChanged(@"Gatekeeper authorization cancelled.", 0.0);
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Authorization Incomplete";
        alert.informativeText = errDesc;
        alert.alertStyle = NSAlertStyleWarning;
        [alert runModal];
        return;
    }

    if (self.log) self.log(@"Gatekeeper quarantine successfully cleared from /usr/local/lib/libftd2xx*.");
    if (self.statusChanged) self.statusChanged(@"Driver authorized. Gatekeeper warning resolved.", 1.0);
    [self checkDriverStatus];

    NSAlert *success = [NSAlert new];
    success.messageText = @"Gatekeeper Warning Resolved";
    success.informativeText =
        @"The quarantine attribute has been successfully cleared from the FTDI driver.\n\n"
        @"macOS Gatekeeper will no longer block \"libftd2xx.1.4.35.dylib\" or show \"Not Opened\" warnings.";
    success.alertStyle = NSAlertStyleInformational;
    [success runModal];
}

- (void)verifyDriver:(id)sender {
    (void)sender;
    [self checkDriverStatus];
    if (!self.isDriverInstalled) {
        if (self.log) self.log(@"Driver verification failed: runtime missing from /usr/local/lib.");
        if (self.statusChanged) self.statusChanged(@"FTDI driver not installed.", 0.0);
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Driver Not Installed";
        alert.informativeText = @"FTDI D2XX runtime was not found in /usr/local/lib. Please click 'Install / Update Driver' first.";
        alert.alertStyle = NSAlertStyleWarning;
        [alert runModal];
        return;
    }
    if (self.isQuarantined) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Driver Quarantined by macOS Gatekeeper";
        alert.informativeText = @"The driver file has the macOS quarantine attribute attached, which triggers the \"libftd2xx Not Opened\" popup.\n\nPlease click 'Fix Gatekeeper & Authorize' first to remove the quarantine flag.";
        alert.alertStyle = NSAlertStyleWarning;
        [alert runModal];
        return;
    }

    void *handle = dlopen("/usr/local/lib/libftd2xx.dylib", RTLD_LAZY);
    if (handle) {
        dlclose(handle);
        if (self.log) self.log(@"Driver verification passed: /usr/local/lib/libftd2xx.dylib loaded successfully via dlopen.");
        if (self.statusChanged) self.statusChanged(@"FTDI driver verified active.", 1.0);
        NSAlert *success = [NSAlert new];
        success.messageText = @"Driver Verification Passed";
        success.informativeText = @"The FTDI D2XX dynamic library is valid, authorized, and ready for use with WSJT-X.";
        success.alertStyle = NSAlertStyleInformational;
        [success runModal];
    } else {
        const char *err = dlerror();
        NSString *errStr = err ? [NSString stringWithUTF8String:err] : @"Dynamic library failed to load.";
        if (self.log) self.log([NSString stringWithFormat:@"Driver verification failed: %@", errStr]);
        if (self.statusChanged) self.statusChanged(@"Driver load failed.", 0.0);
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Driver Verification Failed";
        alert.informativeText = errStr;
        alert.alertStyle = NSAlertStyleCritical;
        [alert runModal];
    }
}

- (void)uninstallDriver:(id)sender {
    (void)sender;
    NSAlert *confirm = [NSAlert new];
    confirm.messageText = @"Uninstall FTDI D2XX Driver?";
    confirm.informativeText = @"This will remove /usr/local/lib/libftd2xx* and /usr/local/include/ftd2xx.h. Administrator privileges will be required.";
    [confirm addButtonWithTitle:@"Uninstall"];
    [confirm addButtonWithTitle:@"Cancel"];
    confirm.alertStyle = NSAlertStyleWarning;

    if ([confirm runModal] != NSAlertFirstButtonReturn) return;

    NSString *cmd = @"/bin/rm -f /usr/local/lib/libftd2xx* /usr/local/include/ftd2xx.h /usr/local/include/WinTypes.h";
    NSString *escapedCmd = [cmd stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    NSString *scriptSource = [NSString stringWithFormat:@"do shell script \"%@\" with administrator privileges", escapedCmd];
    NSAppleScript *appleScript = [[NSAppleScript alloc] initWithSource:scriptSource];
    NSDictionary *errorInfo = nil;
    [appleScript executeAndReturnError:&errorInfo];

    if (errorInfo != nil) {
        NSString *errDesc = errorInfo[NSAppleScriptErrorMessage] ?: @"Removal cancelled or failed.";
        if (self.log) self.log([NSString stringWithFormat:@"Driver uninstall error: %@", errDesc]);
        return;
    }

    if (self.log) self.log(@"FTDI D2XX driver files removed from /usr/local/lib.");
    if (self.statusChanged) self.statusChanged(@"FTDI driver uninstalled.", 0.0);
    [self checkDriverStatus];
}

- (void)openGuidePDF:(id)sender {
    (void)sender;
    NSArray<NSString *> *candidates = @[
        @"/Users/factoreal/Downloads/TX-500/Manual/tx500_ft8_macos_v6.pdf",
        @"Manual/tx500_ft8_macos_v6.pdf",
        @"../Manual/tx500_ft8_macos_v6.pdf"
    ];
    for (NSString *cand in candidates) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:cand]) {
            [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:cand]];
            if (self.log) self.log([NSString stringWithFormat:@"Opened manual: %@", cand]);
            return;
        }
    }
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Guide PDF Not Found";
    alert.informativeText = @"tx500_ft8_macos_v6.pdf could not be found in the Manual directory.";
    alert.alertStyle = NSAlertStyleInformational;
    [alert runModal];
}

@end
