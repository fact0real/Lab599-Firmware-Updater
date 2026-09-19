#import "Lab599FeedbackController.h"
#import <sys/sysctl.h>

static NSString * const kFeedbackCallsignKey = @"Lab599FeedbackCallsign";
static NSString * const kFeedbackContactKey = @"Lab599FeedbackContact";
static NSString * const kGitHubRepoURL = @"https://github.com/fact0real/Lab599-Utility";
static NSString * const kGitHubIssuesURL = @"https://github.com/fact0real/Lab599-Utility/issues";
static NSString * const kGitHubNewIssueURL = @"https://github.com/fact0real/Lab599-Utility/issues/new";

@interface Lab599FeedbackController () <NSTextFieldDelegate, NSTextViewDelegate>

@property(nonatomic, strong, readwrite) NSView *view;
@property(nonatomic, strong, readwrite) NSSegmentedControl *categoryPicker;
@property(nonatomic, strong, readwrite) NSSegmentedControl *priorityPicker;
@property(nonatomic, strong, readwrite) NSTextField *callsignField;
@property(nonatomic, strong, readwrite) NSTextField *contactField;
@property(nonatomic, strong, readwrite) NSTextField *titleField;
@property(nonatomic, strong, readwrite) NSTextView *detailsView;
@property(nonatomic, strong, readwrite) NSButton *diagnosticsCheckbox;
@property(nonatomic, strong, readwrite) NSTextView *diagnosticsView;

@property(nonatomic, strong) NSTextField *detailsPlaceholder;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) NSButton *openIssueButton;
@property(nonatomic, strong) NSButton *markdownCopyButton;
@property(nonatomic, strong) NSButton *clearButton;
@property(nonatomic, strong) NSBox *diagnosticsCard;

@end

@interface Lab599DetailsTextView : NSTextView
@property(nonatomic, weak) NSTextField *placeholderLabel;
@end

@implementation Lab599DetailsTextView
- (void)setString:(NSString *)string {
    [super setString:string];
    self.placeholderLabel.hidden = (string.length > 0);
}
- (void)didChangeText {
    [super didChangeText];
    self.placeholderLabel.hidden = (self.string.length > 0);
}
@end

@implementation Lab599FeedbackController

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
    [self loadSavedPreferences];
    [self refreshDiagnostics];
    return self;
}

- (void)loadSavedPreferences {
    NSString *savedCallsign = [[NSUserDefaults standardUserDefaults] stringForKey:kFeedbackCallsignKey];
    if (savedCallsign.length > 0) {
        self.callsignField.stringValue = savedCallsign;
    }
    NSString *savedContact = [[NSUserDefaults standardUserDefaults] stringForKey:kFeedbackContactKey];
    if (savedContact.length > 0) {
        self.contactField.stringValue = savedContact;
    }
}

- (void)savePreferences {
    NSString *callsign = [self.callsignField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *contact = [self.contactField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [[NSUserDefaults standardUserDefaults] setObject:callsign forKey:kFeedbackCallsignKey];
    [[NSUserDefaults standardUserDefaults] setObject:contact forKey:kFeedbackContactKey];
}

- (void)buildUI {
    self.view = [NSView new];
    self.view.translatesAutoresizingMaskIntoConstraints = NO;

    // =========================================================================
    // HEADER ROW
    // =========================================================================
    NSImageView *iconView = nil;
    if (@available(macOS 11.0, *)) {
        NSImage *icon = [NSImage imageWithSystemSymbolName:@"bubble.left.and.bubble.right.fill" accessibilityDescription:@"Feedback"];
        if (!icon) icon = [NSImage imageWithSystemSymbolName:@"text.bubble.fill" accessibilityDescription:@"Feedback"];
        if (icon) {
            iconView = [NSImageView imageViewWithImage:icon];
            iconView.translatesAutoresizingMaskIntoConstraints = NO;
            iconView.contentTintColor = [NSColor colorWithSRGBRed:0.0 green:0.48 blue:1.0 alpha:1.0];
            [iconView.widthAnchor constraintEqualToConstant:26].active = YES;
            [iconView.heightAnchor constraintEqualToConstant:26].active = YES;
        }
    }

    NSTextField *titleHeader = CreateLabel(@"Lab599 Feedback & Suggestions", YES, 15, NSColor.labelColor);
    NSTextField *subHeader = CreateLabel(@"Share feature requests, report shortcomings/bugs, or submit transceiver & utility feedback anytime.", NO, 11, NSColor.secondaryLabelColor);

    NSStackView *titleStack = [NSStackView stackViewWithViews:@[titleHeader, subHeader]];
    titleStack.translatesAutoresizingMaskIntoConstraints = NO;
    titleStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    titleStack.alignment = NSLayoutAttributeLeading;
    titleStack.spacing = 2;

    NSButton *viewIssuesBtn = [NSButton buttonWithTitle:@"View All GitHub Issues" target:self action:@selector(openGitHubIssuesPage:)];
    viewIssuesBtn.translatesAutoresizingMaskIntoConstraints = NO;
    viewIssuesBtn.bezelStyle = NSBezelStyleRounded;
    viewIssuesBtn.controlSize = NSControlSizeSmall;
    if (@available(macOS 11.0, *)) {
        viewIssuesBtn.image = [NSImage imageWithSystemSymbolName:@"arrow.up.right.square" accessibilityDescription:nil];
        viewIssuesBtn.imagePosition = NSImageLeading;
    }

    NSMutableArray *headerViews = [NSMutableArray array];
    if (iconView) [headerViews addObject:iconView];
    [headerViews addObject:titleStack];

    NSStackView *headerLeft = [NSStackView stackViewWithViews:headerViews];
    headerLeft.translatesAutoresizingMaskIntoConstraints = NO;
    headerLeft.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    headerLeft.alignment = NSLayoutAttributeCenterY;
    headerLeft.spacing = 10;

    NSView *headerRow = [NSView new];
    headerRow.translatesAutoresizingMaskIntoConstraints = NO;
    [headerRow addSubview:headerLeft];
    [headerRow addSubview:viewIssuesBtn];

    [NSLayoutConstraint activateConstraints:@[
        [headerLeft.leadingAnchor constraintEqualToAnchor:headerRow.leadingAnchor],
        [headerLeft.topAnchor constraintEqualToAnchor:headerRow.topAnchor],
        [headerLeft.bottomAnchor constraintEqualToAnchor:headerRow.bottomAnchor],
        [viewIssuesBtn.trailingAnchor constraintEqualToAnchor:headerRow.trailingAnchor],
        [viewIssuesBtn.centerYAnchor constraintEqualToAnchor:headerRow.centerYAnchor]
    ]];

    // =========================================================================
    // CATEGORY & PRIORITY ROW
    // =========================================================================
    NSTextField *catLabel = CreateLabel(@"Category:", YES, 11, NSColor.labelColor);
    self.categoryPicker = [NSSegmentedControl segmentedControlWithLabels:@[
        @"✨ Feature", @"🪲 Bug", @"📡 Radio / CAT", @"💬 Suggestion"
    ] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(categoryChanged:)];
    self.categoryPicker.translatesAutoresizingMaskIntoConstraints = NO;
    self.categoryPicker.selectedSegment = 0;

    NSTextField *prioLabel = CreateLabel(@"Priority:", YES, 11, NSColor.labelColor);
    self.priorityPicker = [NSSegmentedControl segmentedControlWithLabels:@[
        @"Normal", @"High", @"Urgent"
    ] trackingMode:NSSegmentSwitchTrackingSelectOne target:nil action:nil];
    self.priorityPicker.translatesAutoresizingMaskIntoConstraints = NO;
    self.priorityPicker.selectedSegment = 0;

    NSBox *catPrioSep = [NSBox new];
    catPrioSep.translatesAutoresizingMaskIntoConstraints = NO;
    catPrioSep.boxType = NSBoxSeparator;
    [catPrioSep.heightAnchor constraintEqualToConstant:18].active = YES;

    NSStackView *categoryRow = [NSStackView stackViewWithViews:@[
        catLabel, self.categoryPicker, catPrioSep, prioLabel, self.priorityPicker
    ]];
    categoryRow.translatesAutoresizingMaskIntoConstraints = NO;
    categoryRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    categoryRow.alignment = NSLayoutAttributeCenterY;
    categoryRow.spacing = 12;

    // =========================================================================
    // CALLSIGN & CONTACT ROW
    // =========================================================================
    NSTextField *callsignLbl = CreateLabel(@"Your Callsign:", YES, 11, NSColor.labelColor);
    self.callsignField = [NSTextField textFieldWithString:@""];
    self.callsignField.translatesAutoresizingMaskIntoConstraints = NO;
    self.callsignField.placeholderString = @"e.g. EP2AES";
    self.callsignField.delegate = self;
    [self.callsignField.widthAnchor constraintEqualToConstant:150].active = YES;

    NSTextField *contactLbl = CreateLabel(@"Your Email / Contact (Optional):", YES, 11, NSColor.labelColor);
    self.contactField = [NSTextField textFieldWithString:@""];
    self.contactField.translatesAutoresizingMaskIntoConstraints = NO;
    self.contactField.placeholderString = @"e.g. factoreal@asis.sh";
    self.contactField.delegate = self;
    [self.contactField.widthAnchor constraintEqualToConstant:240].active = YES;

    NSStackView *userRow = [NSStackView stackViewWithViews:@[
        callsignLbl, self.callsignField, contactLbl, self.contactField
    ]];
    userRow.translatesAutoresizingMaskIntoConstraints = NO;
    userRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    userRow.alignment = NSLayoutAttributeCenterY;
    userRow.spacing = 12;

    // =========================================================================
    // TITLE / SUMMARY ROW
    // =========================================================================
    NSTextField *titleLbl = CreateLabel(@"Title / Summary:", YES, 11, NSColor.labelColor);
    self.titleField = [NSTextField textFieldWithString:@""];
    self.titleField.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleField.placeholderString = @"Brief summary of your request or issue...";
    self.titleField.delegate = self;

    // =========================================================================
    // DETAILS BOX
    // =========================================================================
    NSTextField *detailsLbl = CreateLabel(@"Details:", YES, 11, NSColor.labelColor);
    NSTextField *detailsHint = CreateLabel(@"Please specify desired behavior, steps to reproduce, or suggestions.", NO, 10, NSColor.secondaryLabelColor);

    NSView *detailsHeader = [NSView new];
    detailsHeader.translatesAutoresizingMaskIntoConstraints = NO;
    [detailsHeader addSubview:detailsLbl];
    [detailsHeader addSubview:detailsHint];
    [NSLayoutConstraint activateConstraints:@[
        [detailsLbl.leadingAnchor constraintEqualToAnchor:detailsHeader.leadingAnchor],
        [detailsLbl.centerYAnchor constraintEqualToAnchor:detailsHeader.centerYAnchor],
        [detailsHint.trailingAnchor constraintEqualToAnchor:detailsHeader.trailingAnchor],
        [detailsHint.centerYAnchor constraintEqualToAnchor:detailsHeader.centerYAnchor],
        [detailsHeader.heightAnchor constraintEqualToConstant:16]
    ]];



    NSScrollView *detailsScroll = [NSScrollView new];
    detailsScroll.translatesAutoresizingMaskIntoConstraints = NO;
    detailsScroll.hasVerticalScroller = YES;
    detailsScroll.borderType = NSBezelBorder;

    Lab599DetailsTextView *dtv = [[Lab599DetailsTextView alloc] initWithFrame:NSMakeRect(0, 0, 700, 110)];
    dtv.editable = YES;
    dtv.selectable = YES;
    dtv.richText = NO;
    dtv.verticallyResizable = YES;
    dtv.horizontallyResizable = NO;
    dtv.autoresizingMask = NSViewWidthSizable;
    dtv.textContainer.widthTracksTextView = YES;
    dtv.textContainerInset = NSMakeSize(6, 6);
    dtv.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
    dtv.delegate = self;
    self.detailsView = dtv;
    detailsScroll.documentView = self.detailsView;
    [detailsScroll.heightAnchor constraintEqualToConstant:105].active = YES;

    // Placeholder inside text view
    self.detailsPlaceholder = CreateLabel(@"Describe your proposal, shortcoming, or bug in detail...", NO, 11, NSColor.placeholderTextColor);
    dtv.placeholderLabel = self.detailsPlaceholder;
    [self.detailsView addSubview:self.detailsPlaceholder];
    [NSLayoutConstraint activateConstraints:@[
        [self.detailsPlaceholder.leadingAnchor constraintEqualToAnchor:self.detailsView.leadingAnchor constant:8],
        [self.detailsPlaceholder.topAnchor constraintEqualToAnchor:self.detailsView.topAnchor constant:6]
    ]];

    // =========================================================================
    // DIAGNOSTICS SNAPSHOT CARD
    // =========================================================================
    self.diagnosticsCheckbox = [NSButton checkboxWithTitle:@"Include system & radio diagnostics (helps solve issues faster)" target:self action:@selector(toggleDiagnostics:)];
    self.diagnosticsCheckbox.translatesAutoresizingMaskIntoConstraints = NO;
    self.diagnosticsCheckbox.state = NSControlStateValueOn;
    self.diagnosticsCheckbox.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];

    self.diagnosticsCard = CreateCardBox();
    self.diagnosticsView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 700, 60)];
    self.diagnosticsView.editable = NO;
    self.diagnosticsView.selectable = YES;
    self.diagnosticsView.drawsBackground = NO;
    self.diagnosticsView.font = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular];
    self.diagnosticsView.textColor = NSColor.secondaryLabelColor;

    NSScrollView *diagScroll = [NSScrollView new];
    diagScroll.translatesAutoresizingMaskIntoConstraints = NO;
    diagScroll.borderType = NSNoBorder;
    diagScroll.drawsBackground = NO;
    diagScroll.hasVerticalScroller = NO;
    diagScroll.documentView = self.diagnosticsView;
    [diagScroll.heightAnchor constraintEqualToConstant:56].active = YES;

    [self.diagnosticsCard.contentView addSubview:diagScroll];
    [NSLayoutConstraint activateConstraints:@[
        [diagScroll.leadingAnchor constraintEqualToAnchor:self.diagnosticsCard.contentView.leadingAnchor constant:8],
        [diagScroll.trailingAnchor constraintEqualToAnchor:self.diagnosticsCard.contentView.trailingAnchor constant:-8],
        [diagScroll.topAnchor constraintEqualToAnchor:self.diagnosticsCard.contentView.topAnchor constant:4],
        [diagScroll.bottomAnchor constraintEqualToAnchor:self.diagnosticsCard.contentView.bottomAnchor constant:-4]
    ]];

    // =========================================================================
    // BOTTOM TOOLBAR & ACTION BUTTONS
    // =========================================================================
    self.statusLabel = CreateLabel(@"Ready. Issues will be opened at github.com/fact0real/Lab599-Utility", NO, 11, NSColor.secondaryLabelColor);

    self.clearButton = [NSButton buttonWithTitle:@"Clear" target:self action:@selector(clearForm)];
    self.clearButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.clearButton.bezelStyle = NSBezelStyleRounded;

    self.markdownCopyButton = [NSButton buttonWithTitle:@"Copy Markdown" target:self action:@selector(copyMarkdownToClipboard)];
    self.markdownCopyButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.markdownCopyButton.bezelStyle = NSBezelStyleRounded;
    if (@available(macOS 11.0, *)) {
        self.markdownCopyButton.image = [NSImage imageWithSystemSymbolName:@"doc.on.doc" accessibilityDescription:nil];
        self.markdownCopyButton.imagePosition = NSImageLeading;
    }

    self.openIssueButton = [NSButton buttonWithTitle:@"Open GitHub Issue" target:self action:@selector(openGitHubIssue)];
    self.openIssueButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.openIssueButton.bezelStyle = NSBezelStyleRounded;
    self.openIssueButton.keyEquivalent = @"\r";
    if (@available(macOS 11.0, *)) {
        self.openIssueButton.image = [NSImage imageWithSystemSymbolName:@"arrow.up.right.square.fill" accessibilityDescription:nil];
        self.openIssueButton.imagePosition = NSImageLeading;
    }

    NSStackView *actionsRight = [NSStackView stackViewWithViews:@[
        self.clearButton, self.markdownCopyButton, self.openIssueButton
    ]];
    actionsRight.translatesAutoresizingMaskIntoConstraints = NO;
    actionsRight.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    actionsRight.alignment = NSLayoutAttributeCenterY;
    actionsRight.spacing = 8;

    NSView *bottomRow = [NSView new];
    bottomRow.translatesAutoresizingMaskIntoConstraints = NO;
    [bottomRow addSubview:self.statusLabel];
    [bottomRow addSubview:actionsRight];
    [NSLayoutConstraint activateConstraints:@[
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:bottomRow.leadingAnchor],
        [self.statusLabel.centerYAnchor constraintEqualToAnchor:bottomRow.centerYAnchor],
        [actionsRight.trailingAnchor constraintEqualToAnchor:bottomRow.trailingAnchor],
        [actionsRight.centerYAnchor constraintEqualToAnchor:bottomRow.centerYAnchor],
        [bottomRow.heightAnchor constraintEqualToConstant:32]
    ]];

    // =========================================================================
    // MASTER VERTICAL STACK
    // =========================================================================
    NSStackView *masterStack = [NSStackView stackViewWithViews:@[
        headerRow,
        categoryRow,
        userRow,
        titleLbl, self.titleField,
        detailsHeader, detailsScroll,
        self.diagnosticsCheckbox, self.diagnosticsCard,
        bottomRow
    ]];
    masterStack.translatesAutoresizingMaskIntoConstraints = NO;
    masterStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    masterStack.alignment = NSLayoutAttributeLeading;
    masterStack.spacing = 6;
    masterStack.detachesHiddenViews = YES;

    [self.view addSubview:masterStack];
    [NSLayoutConstraint activateConstraints:@[
        [masterStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [masterStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [masterStack.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [masterStack.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [headerRow.widthAnchor constraintEqualToAnchor:masterStack.widthAnchor],
        [categoryRow.widthAnchor constraintEqualToAnchor:masterStack.widthAnchor],
        [userRow.widthAnchor constraintEqualToAnchor:masterStack.widthAnchor],
        [self.titleField.widthAnchor constraintEqualToAnchor:masterStack.widthAnchor],
        [detailsHeader.widthAnchor constraintEqualToAnchor:masterStack.widthAnchor],
        [detailsScroll.widthAnchor constraintEqualToAnchor:masterStack.widthAnchor],
        [self.diagnosticsCard.widthAnchor constraintEqualToAnchor:masterStack.widthAnchor],
        [bottomRow.widthAnchor constraintEqualToAnchor:masterStack.widthAnchor]
    ]];

    [self.view.heightAnchor constraintEqualToConstant:470].active = YES;
}

#pragma mark - Diagnostics Engine

- (NSString *)hardwareModelIdentifier {
    size_t len = 0;
    sysctlbyname("hw.model", NULL, &len, NULL, 0);
    if (len) {
        char *model = malloc(len);
        if (model) {
            sysctlbyname("hw.model", model, &len, NULL, 0);
            NSString *result = [NSString stringWithUTF8String:model];
            free(model);
            return result ?: @"Mac";
        }
    }
    return @"Mac";
}

- (NSString *)cpuArchitectureName {
#if defined(__arm64__)
    return @"Apple Silicon (arm64)";
#elif defined(__x86_64__)
    return @"Intel (x86_64)";
#else
    return @"Universal";
#endif
}

- (NSString *)ftdiDriverStatusString {
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:@"/usr/local/lib/libftd2xx.1.4.35.dylib"] ||
        [fm fileExistsAtPath:@"/usr/local/lib/libftd2xx.dylib"]) {
        return @"Installed & Authorized (v1.4.35)";
    }
    return @"Not Installed";
}

- (void)refreshDiagnostics {
    NSString *appVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"2.7";
    NSString *appBuild = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"13";
    NSString *osVersion = [[NSProcessInfo processInfo] operatingSystemVersionString];
    NSString *hwModel = [self hardwareModelIdentifier];
    NSString *arch = [self cpuArchitectureName];
    NSString *driverStatus = [self ftdiDriverStatusString];

    NSString *selectedPort = self.selectedPortProvider ? self.selectedPortProvider() : nil;
    if (!selectedPort.length) selectedPort = @"No active port selected";

    NSString *diagText = [NSString stringWithFormat:
        @"• Lab599 Utility: Version %@ (Build %@, Universal) | Host: %@ (%@)\n"
        @"• macOS: %@\n"
        @"• FTDI D2XX Driver: %@\n"
        @"• Active Port: %@ | Hardware Target: Lab599 TX-500 Discovery / MP / PRO",
        appVersion, appBuild, hwModel, arch, osVersion, driverStatus, selectedPort];

    self.diagnosticsView.string = diagText;
}

- (void)toggleDiagnostics:(id)sender {
    (void)sender;
    BOOL enabled = (self.diagnosticsCheckbox.state == NSControlStateValueOn);
    self.diagnosticsCard.hidden = !enabled;
}

- (void)categoryChanged:(id)sender {
    (void)sender;
    NSInteger cat = self.categoryPicker.selectedSegment;
    if (cat == 0) {
        self.titleField.placeholderString = @"e.g. Feature request: add export for ADIF/Cabrillo log notes";
    } else if (cat == 1) {
        self.titleField.placeholderString = @"e.g. Bug: serial timeout occurred during CAT Test at 19200 baud";
    } else if (cat == 2) {
        self.titleField.placeholderString = @"e.g. Radio/CAT: TX-500MP shows PTT delay when keying via AD-502";
    } else {
        self.titleField.placeholderString = @"e.g. Suggestion: add shortcut to refresh documentation catalog";
    }
}

#pragma mark - Form Actions & Reset

- (void)clearForm {
    self.titleField.stringValue = @"";
    self.detailsView.string = @"";
    self.detailsPlaceholder.hidden = NO;
    self.priorityPicker.selectedSegment = 0;
    self.statusLabel.stringValue = @"Form cleared. Ready for new feedback.";
    self.statusLabel.textColor = NSColor.secondaryLabelColor;
}

- (void)controlTextDidChange:(NSNotification *)obj {
    NSTextField *field = (NSTextField *)obj.object;
    if (field == self.callsignField || field == self.contactField) {
        [self savePreferences];
    }
}

- (void)textDidChange:(NSNotification *)notification {
    (void)notification;
    self.detailsPlaceholder.hidden = (self.detailsView.string.length > 0);
}

#pragma mark - Markdown & URL Generation

- (NSString *)categoryNameForSegment:(NSInteger)seg {
    switch (seg) {
        case 0: return @"Feature";
        case 1: return @"Bug";
        case 2: return @"Radio / CAT";
        case 3: return @"Suggestion";
        default: return @"Feedback";
    }
}

- (NSString *)gitHubLabelsForCategory:(NSInteger)seg {
    switch (seg) {
        case 0: return @"enhancement";
        case 1: return @"bug";
        case 2: return @"hardware,cat";
        case 3: return @"suggestion";
        default: return @"feedback";
    }
}

- (NSString *)priorityNameForSegment:(NSInteger)seg {
    switch (seg) {
        case 1: return @"High";
        case 2: return @"Urgent";
        default: return @"Normal";
    }
}

- (NSString *)generateIssueMarkdown {
    [self savePreferences];
    [self refreshDiagnostics];

    NSString *title = [self.titleField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!title.length) title = @"(No title provided)";

    NSString *details = [self.detailsView.string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!details.length) details = @"(No detailed description provided)";

    NSString *callsign = [self.callsignField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!callsign.length) callsign = @"N/A";

    NSString *contact = [self.contactField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!contact.length) contact = @"N/A";

    NSString *category = [self categoryNameForSegment:self.categoryPicker.selectedSegment];
    NSString *priority = [self priorityNameForSegment:self.priorityPicker.selectedSegment];

    NSMutableString *md = [NSMutableString string];
    [md appendFormat:@"### Summary\n%@\n\n", title];
    [md appendFormat:@"### Metadata\n"];
    [md appendFormat:@"- **Category**: %@\n", category];
    [md appendFormat:@"- **Priority**: %@\n", priority];
    [md appendFormat:@"- **Callsign**: %@\n", callsign];
    [md appendFormat:@"- **Contact**: %@\n\n", contact];

    [md appendFormat:@"### Details & Description\n%@\n\n", details];

    if (self.diagnosticsCheckbox.state == NSControlStateValueOn) {
        NSString *appVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"2.7";
        NSString *appBuild = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"13";
        NSString *osVersion = [[NSProcessInfo processInfo] operatingSystemVersionString];
        NSString *hwModel = [self hardwareModelIdentifier];
        NSString *arch = [self cpuArchitectureName];
        NSString *driverStatus = [self ftdiDriverStatusString];
        NSString *selectedPort = self.selectedPortProvider ? self.selectedPortProvider() : nil;
        if (!selectedPort.length) selectedPort = @"None selected";

        NSDateFormatter *isoDf = [NSDateFormatter new];
        isoDf.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
        isoDf.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
        NSString *utcTimestamp = [isoDf stringFromDate:[NSDate date]];

        [md appendString:@"---\n"];
        [md appendString:@"### System & Radio Diagnostics\n"];
        [md appendFormat:@"- **Lab599 Utility Version**: %@ (Build %@, Universal)\n", appVersion, appBuild];
        [md appendFormat:@"- **Operating System**: macOS %@\n", osVersion];
        [md appendFormat:@"- **Hardware Architecture**: %@ (%@)\n", hwModel, arch];
        [md appendFormat:@"- **FTDI D2XX Driver**: %@\n", driverStatus];
        [md appendFormat:@"- **Active Serial Port**: %@\n", selectedPort];
        [md appendFormat:@"- **Target Radio Models**: Lab599 TX-500 Discovery / TX-500MP / TX-500PRO\n"];
        [md appendFormat:@"- **Report Timestamp**: %@\n", utcTimestamp];
    }

    return [md copy];
}

static NSString *URLEncodeQueryComponent(NSString *string) {
    NSMutableCharacterSet *allowed = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
    [allowed removeCharactersInString:@"&=+?#/:;@"];
    return [string stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: string;
}

- (NSURL *)generateGitHubIssueURL {
    NSString *category = [self categoryNameForSegment:self.categoryPicker.selectedSegment];
    NSString *labels = [self gitHubLabelsForCategory:self.categoryPicker.selectedSegment];

    NSString *userTitle = [self.titleField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!userTitle.length) userTitle = @"Feedback / Report";
    NSString *fullTitle = [NSString stringWithFormat:@"[%@] %@", category, userTitle];

    NSString *bodyMarkdown = [self generateIssueMarkdown];

    NSString *encTitle = URLEncodeQueryComponent(fullTitle);
    NSString *encLabels = URLEncodeQueryComponent(labels);
    NSString *encBody = URLEncodeQueryComponent(bodyMarkdown);

    NSString *urlString = [NSString stringWithFormat:@"%@?title=%@&body=%@&labels=%@",
                           kGitHubNewIssueURL, encTitle, encBody, encLabels];

    // If query string exceeds standard browser limit (~2000 chars), fall back to title + labels only
    if (urlString.length > 2200) {
        urlString = [NSString stringWithFormat:@"%@?title=%@&labels=%@", kGitHubNewIssueURL, encTitle, encLabels];
    }

    return [NSURL URLWithString:urlString];
}

- (void)copyMarkdownToClipboard {
    NSString *md = [self generateIssueMarkdown];
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:md forType:NSPasteboardTypeString];

    self.statusLabel.stringValue = @"✓ Markdown report copied to clipboard! Ready to paste into GitHub.";
    self.statusLabel.textColor = [NSColor colorWithSRGBRed:0.1 green:0.65 blue:0.25 alpha:1.0];
    if (self.log) self.log(@"Feedback report copied to clipboard in Markdown format.");
}

- (void)openGitHubIssue {
    NSString *title = [self.titleField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *details = [self.detailsView.string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (!title.length && !details.length) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Please provide a title or description";
        alert.informativeText = @"Before opening a GitHub Issue, please summarize your issue or suggestion in the Title or Details field.";
        alert.alertStyle = NSAlertStyleWarning;
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return;
    }

    // Always copy markdown to clipboard first for safety
    [self copyMarkdownToClipboard];

    NSURL *url = [self generateGitHubIssueURL];
    if (url) {
        [[NSWorkspace sharedWorkspace] openURL:url];
        self.statusLabel.stringValue = @"✓ GitHub Issue page opened in browser! (Report also copied to clipboard)";
        self.statusLabel.textColor = [NSColor colorWithSRGBRed:0.0 green:0.48 blue:1.0 alpha:1.0];
        if (self.log) self.log([NSString stringWithFormat:@"Opened GitHub Issues: %@", url.absoluteString]);
    }
}

- (void)openGitHubIssuesPage:(id)sender {
    (void)sender;
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:kGitHubIssuesURL]];
}

@end
