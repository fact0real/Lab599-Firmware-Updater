#import "Lab599ToolsController.h"
#import "TX500CATTest.h"
#import "TX500Configuration.h"
#import "TX500Transfer.h"
#import "TX500ProfilesAndBackup.h"
#import "TX500SettingsModel.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface Lab599ToolsController ()
@property(nonatomic, strong, readwrite) NSView *view;
@property(nonatomic, strong) NSArray<NSView *> *panels;
@property(nonatomic, strong) NSMutableArray<NSControl *> *controls;
@property(nonatomic, strong) NSButton *catOnce, *catStart, *stop, *settingsRead, *settingsWrite, *settingsSave, *settingsCompare;
@property(nonatomic, strong) NSButton *memoryRead, *memoryWrite, *memorySave, *memoryCompare, *csvImport, *csvExport;
@property(nonatomic, strong) NSPopUpButton *profilesPopup;
@property(nonatomic, strong) NSTextField *catResult, *catCounts, *settingsInfo, *memoryInfo, *frequency;
@property(nonatomic, strong) NSPopUpButton *mode, *preAtt;
@property(nonatomic, strong) NSTableView *table;
@property(nonatomic, strong) Lab599Cancellation *token;
@property(nonatomic, copy) NSData *settingsData;
@property(nonatomic, strong) NSMutableArray<TXMemoryChannel *> *channels;
@property(nonatomic, copy) NSString *settingsSource;
@property(nonatomic) BOOL busy, hasPorts, settingsDirty, memoryDirty, memoryReady;
@property(nonatomic) NSInteger tool;

// CAT Studio UI Controls
@property(nonatomic, strong) NSTextField *catModelLabel;
@property(nonatomic, strong) NSTextField *catFreqDisplay;
@property(nonatomic, strong) NSTextField *catModeBadge;
@property(nonatomic, strong) NSTextField *catPowerBadge;
@property(nonatomic, strong) NSTextField *catFilterBadge;
@property(nonatomic, strong) NSTextField *catPreampBadge;
@property(nonatomic, strong) NSTextField *catVoltageBadge;
@property(nonatomic, strong) NSTextField *catSMeterBadge;
@property(nonatomic, strong) NSButton *catReadAllButton;

@property(nonatomic, strong) NSTextField *catFreqInputField;
@property(nonatomic, strong) NSButton *catSetFreqButton;
@property(nonatomic, strong) NSPopUpButton *catModePopup;
@property(nonatomic, strong) NSButton *catSetModeButton;
@property(nonatomic, strong) NSPopUpButton *catPowerPopup;
@property(nonatomic, strong) NSButton *catSetPowerButton;
@property(nonatomic, strong) NSButton *catPreampToggle;
@property(nonatomic, strong) NSButton *catAttenuatorToggle;
@property(nonatomic, strong) NSSegmentedControl *catFilterSegment;
@property(nonatomic, strong) NSMutableArray<NSButton *> *bandButtons;

@property(nonatomic, strong) NSTextField *catCommandInput;
@property(nonatomic, strong) NSButton *catSendCommandButton;
@property(nonatomic, strong) NSTextView *catTerminalTextView;
@property(nonatomic, strong) NSButton *catClearTerminalButton;
@property(nonatomic, strong) NSButton *catCopyTerminalButton;
@property(nonatomic, strong) NSMutableArray<NSButton *> *quickCmdButtons;


// Settings Editor
@property(nonatomic, strong) NSTableView *settingsTable;
@property(nonatomic, strong) NSArray<TXSettingsItem *> *allSettingsItems;
@property(nonatomic, strong) NSArray<TXSettingsItem *> *filteredSettingsItems;
@property(nonatomic, strong) NSPopUpButton *settingsCategoryFilter;
@property(nonatomic, strong) NSTextField *settingEditField;
@property(nonatomic, strong) NSTextField *settingEditLabel;
@property(nonatomic, strong) NSButton *settingApplyButton;
@property(nonatomic, strong) NSButton *settingsExportJson, *settingsImportJson;

// Backup Comparison Sheet
@property(nonatomic, strong) NSWindow *compareSheet;
@property(nonatomic, strong) NSTableView *compareTable;
@property(nonatomic, strong) NSTextField *compareSummaryLabel;
@property(nonatomic, strong) TXSettingsComparisonResult *activeSettingsDiff;
@property(nonatomic, strong) TXMemoryComparisonResult *activeMemoryDiff;
@property(nonatomic) BOOL isSettingsComparison;
@end

@implementation Lab599ToolsController

static NSTextField *Label(NSString *text) {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.textColor = NSColor.secondaryLabelColor;
    return label;
}

static NSStackView *Stack(NSArray<NSView *> *views, BOOL vertical) {
    NSStackView *s = [NSStackView stackViewWithViews:views];
    s.orientation = vertical ? NSUserInterfaceLayoutOrientationVertical : NSUserInterfaceLayoutOrientationHorizontal;
    s.alignment = vertical ? NSLayoutAttributeLeading : NSLayoutAttributeCenterY;
    s.spacing = 10;
    return s;
}

static NSTextField *CreateBadge(NSString *text, NSColor *bgColor, NSColor *textColor) {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightSemibold];
    label.textColor = textColor ?: NSColor.labelColor;
    label.wantsLayer = YES;
    label.layer.backgroundColor = (bgColor ?: [NSColor colorWithCalibratedWhite:0.5 alpha:0.15]).CGColor;
    label.layer.cornerRadius = 4.0;
    label.alignment = NSTextAlignmentCenter;
    return label;
}

static NSBox *CreateCardWithView(NSView *innerView) {
    NSBox *box = [NSBox new];
    box.boxType = NSBoxCustom;
    box.borderWidth = 1.0;
    box.cornerRadius = 8.0;
    box.borderColor = [NSColor separatorColor];
    box.fillColor = [NSColor colorWithCalibratedWhite:0.5 alpha:0.04];
    box.translatesAutoresizingMaskIntoConstraints = NO;
    innerView.translatesAutoresizingMaskIntoConstraints = NO;
    [box addSubview:innerView];
    [NSLayoutConstraint activateConstraints:@[
        [innerView.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:12],
        [innerView.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-12],
        [innerView.topAnchor constraintEqualToAnchor:box.topAnchor constant:10],
        [innerView.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-10]
    ]];
    return box;
}

static NSString *ToolsFormatFreq(uint64_t hz) {
    uint64_t m = hz / 1000000;
    uint64_t k = (hz % 1000000) / 1000;
    uint64_t h = hz % 1000;
    return [NSString stringWithFormat:@"%llu.%03llu.%03llu MHz", m, k, h];
}

static NSString *ToolsModeNameFromCode(NSInteger code) {
    switch (code) {
        case 1: return @"LSB";
        case 2: return @"USB";
        case 3: return @"CW";
        case 4: return @"FM";
        case 5: return @"AM";
        case 6: return @"DIG (FSK)";
        case 7: return @"CWR";
        default: return @"USB";
    }
}

- (NSButton *)button:(NSString *)title action:(SEL)action tag:(NSInteger)tag {
    NSButton *b = [NSButton buttonWithTitle:title target:self action:action];
    b.tag = tag;
    [self.controls addObject:b];
    return b;
}

- (NSView *)buildCATStudioView {
    // =========================================================================
    // LEFT COLUMN: Live State Inspector (Card 1) + Quick Control (Card 2)
    // =========================================================================

    // --- Card 1: Live State Inspector ---
    NSTextField *c1Title = [NSTextField labelWithString:@"Live State Inspector"];
    c1Title.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    c1Title.textColor = NSColor.labelColor;

    self.catReadAllButton = [NSButton buttonWithTitle:@"Read All from Radio" target:self action:@selector(readRadioStateAction:)];
    self.catReadAllButton.bezelStyle = NSBezelStyleRounded;
    self.catReadAllButton.controlSize = NSControlSizeSmall;
    [self.controls addObject:self.catReadAllButton];

    NSStackView *c1Header = [NSStackView stackViewWithViews:@[c1Title, self.catReadAllButton]];
    c1Header.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    c1Header.distribution = NSStackViewDistributionEqualSpacing;

    // Dark OLED-style frequency & model banner
    self.catModelLabel = [NSTextField labelWithString:@"Transceiver Model: Lab599 TX-500 Discovery"];
    self.catModelLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    self.catModelLabel.textColor = [NSColor secondaryLabelColor];

    self.catFreqDisplay = [NSTextField labelWithString:@"— . — . — MHz"];
    self.catFreqDisplay.font = [NSFont monospacedDigitSystemFontOfSize:22 weight:NSFontWeightBold];
    self.catFreqDisplay.textColor = [NSColor colorWithCalibratedRed:0.25 green:0.75 blue:1.0 alpha:1.0];
    self.catFreqDisplay.alignment = NSTextAlignmentLeft;

    NSStackView *freqBoxInner = Stack(@[self.catModelLabel, self.catFreqDisplay], YES);
    freqBoxInner.spacing = 2;
    freqBoxInner.edgeInsets = NSEdgeInsetsMake(6, 10, 6, 10);

    NSBox *freqBanner = [NSBox new];
    freqBanner.boxType = NSBoxCustom;
    freqBanner.cornerRadius = 6.0;
    freqBanner.borderWidth = 1.0;
    freqBanner.borderColor = [NSColor colorWithCalibratedWhite:0.3 alpha:0.4];
    freqBanner.fillColor = [NSColor colorWithCalibratedRed:0.06 green:0.08 blue:0.11 alpha:0.9];
    freqBanner.translatesAutoresizingMaskIntoConstraints = NO;
    [freqBanner addSubview:freqBoxInner];
    freqBoxInner.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [freqBoxInner.leadingAnchor constraintEqualToAnchor:freqBanner.leadingAnchor],
        [freqBoxInner.trailingAnchor constraintEqualToAnchor:freqBanner.trailingAnchor],
        [freqBoxInner.topAnchor constraintEqualToAnchor:freqBanner.topAnchor],
        [freqBoxInner.bottomAnchor constraintEqualToAnchor:freqBanner.bottomAnchor]
    ]];

    // Telemetry Badges (2 rows of 3 badges)
    self.catModeBadge = CreateBadge(@"MODE: —", nil, nil);
    self.catPowerBadge = CreateBadge(@"PWR: —", nil, nil);
    self.catFilterBadge = CreateBadge(@"FIL: —", nil, nil);
    self.catPreampBadge = CreateBadge(@"PRE: —", nil, nil);
    self.catVoltageBadge = CreateBadge(@"VOLT: —", nil, nil);
    self.catSMeterBadge = CreateBadge(@"S-MTR: —", nil, nil);

    for (NSTextField *b in @[self.catModeBadge, self.catPowerBadge, self.catFilterBadge, self.catPreampBadge, self.catVoltageBadge, self.catSMeterBadge]) {
        [b.heightAnchor constraintEqualToConstant:22].active = YES;
    }

    NSStackView *badgeRow1 = Stack(@[self.catModeBadge, self.catPowerBadge, self.catFilterBadge], NO);
    badgeRow1.distribution = NSStackViewDistributionFillEqually;
    badgeRow1.spacing = 6;

    NSStackView *badgeRow2 = Stack(@[self.catPreampBadge, self.catVoltageBadge, self.catSMeterBadge], NO);
    badgeRow2.distribution = NSStackViewDistributionFillEqually;
    badgeRow2.spacing = 6;

    NSStackView *c1Inner = Stack(@[c1Header, freqBanner, badgeRow1, badgeRow2], YES);
    c1Inner.spacing = 8;
    NSBox *card1 = CreateCardWithView(c1Inner);

    // --- Card 2: Quick Control & Band Presets ---
    NSTextField *c2Title = [NSTextField labelWithString:@"Quick Control & Band Presets"];
    c2Title.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];

    // Frequency tuning row
    self.catFreqInputField = [NSTextField new];
    self.catFreqInputField.placeholderString = @"Frequency in Hz (e.g. 14074000)";
    self.catFreqInputField.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    self.catFreqInputField.target = self;
    self.catFreqInputField.action = @selector(setFrequencyAction:);

    self.catSetFreqButton = [NSButton buttonWithTitle:@"Tune" target:self action:@selector(setFrequencyAction:)];
    self.catSetFreqButton.bezelStyle = NSBezelStyleRounded;
    self.catSetFreqButton.controlSize = NSControlSizeSmall;
    [self.catSetFreqButton.widthAnchor constraintEqualToConstant:65].active = YES;
    [self.controls addObjectsFromArray:@[self.catFreqInputField, self.catSetFreqButton]];

    NSTextField *hzLabel = Label(@"Tune Hz:");
    hzLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    [hzLabel.widthAnchor constraintEqualToConstant:55].active = YES;

    NSStackView *freqRow = Stack(@[hzLabel, self.catFreqInputField, self.catSetFreqButton], NO);
    freqRow.spacing = 6;

    // Band Presets (2 tidy rows: 80m-17m and 15m-6m)
    self.bandButtons = [NSMutableArray array];
    struct { const char *band; uint64_t freq; } bands[] = {
        {"80m", 3573000}, {"40m", 7074000}, {"30m", 10136000},
        {"20m", 14074000}, {"17m", 18100000}, {"15m", 21074000},
        {"12m", 24915000}, {"10m", 28074000}, {"6m", 50313000}
    };
    NSMutableArray *bandRow1Views = [NSMutableArray array];
    NSMutableArray *bandRow2Views = [NSMutableArray array];
    for (int i = 0; i < 9; i++) {
        NSButton *bb = [NSButton buttonWithTitle:@(bands[i].band) target:self action:@selector(bandPresetClicked:)];
        bb.tag = (NSInteger)bands[i].freq;
        bb.bezelStyle = NSBezelStyleInline;
        bb.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
        [self.bandButtons addObject:bb];
        [self.controls addObject:bb];
        if (i < 5) {
            [bandRow1Views addObject:bb];
        } else {
            [bandRow2Views addObject:bb];
        }
    }
    NSStackView *bandRow1 = Stack(bandRow1Views, NO);
    bandRow1.distribution = NSStackViewDistributionFillEqually;
    bandRow1.spacing = 5;

    NSStackView *bandRow2 = Stack(bandRow2Views, NO);
    bandRow2.distribution = NSStackViewDistributionFillEqually;
    bandRow2.spacing = 5;

    // Mode & RF Power Row
    self.catModePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.catModePopup addItemsWithTitles:@[@"LSB", @"USB", @"CW", @"FM", @"AM", @"DIG (FSK)", @"CWR"]];
    [self.catModePopup selectItemWithTitle:@"USB"];
    self.catModePopup.controlSize = NSControlSizeSmall;
    self.catModePopup.font = [NSFont systemFontOfSize:11];

    self.catSetModeButton = [NSButton buttonWithTitle:@"Set Mode" target:self action:@selector(setModeAction:)];
    self.catSetModeButton.bezelStyle = NSBezelStyleRounded;
    self.catSetModeButton.controlSize = NSControlSizeSmall;

    self.catPowerPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.catPowerPopup addItemsWithTitles:@[@"1 W", @"2 W", @"3 W", @"5 W", @"7 W", @"10 W"]];
    [self.catPowerPopup selectItemWithTitle:@"10 W"];
    self.catPowerPopup.controlSize = NSControlSizeSmall;
    self.catPowerPopup.font = [NSFont systemFontOfSize:11];

    self.catSetPowerButton = [NSButton buttonWithTitle:@"Set Power" target:self action:@selector(setPowerAction:)];
    self.catSetPowerButton.bezelStyle = NSBezelStyleRounded;
    self.catSetPowerButton.controlSize = NSControlSizeSmall;

    [self.controls addObjectsFromArray:@[self.catModePopup, self.catSetModeButton, self.catPowerPopup, self.catSetPowerButton]];

    NSStackView *modeGroup = Stack(@[Label(@"Mode:"), self.catModePopup, self.catSetModeButton], NO);
    modeGroup.spacing = 4;

    NSStackView *powerGroup = Stack(@[Label(@"RF Pwr:"), self.catPowerPopup, self.catSetPowerButton], NO);
    powerGroup.spacing = 4;

    NSStackView *modePowerRow = Stack(@[modeGroup, [NSView new], powerGroup], NO);
    modePowerRow.distribution = NSStackViewDistributionEqualSpacing;

    // Frontend toggles row
    self.catPreampToggle = [NSButton checkboxWithTitle:@"Preamp" target:self action:@selector(togglePreampAction:)];
    self.catPreampToggle.controlSize = NSControlSizeSmall;
    self.catPreampToggle.font = [NSFont systemFontOfSize:11];

    self.catAttenuatorToggle = [NSButton checkboxWithTitle:@"Attenuator" target:self action:@selector(toggleAttenuatorAction:)];
    self.catAttenuatorToggle.controlSize = NSControlSizeSmall;
    self.catAttenuatorToggle.font = [NSFont systemFontOfSize:11];

    self.catFilterSegment = [NSSegmentedControl segmentedControlWithLabels:@[@"FIL 1", @"FIL 2", @"FIL 3"]
                                                              trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                    target:self
                                                                    action:@selector(filterChangedAction:)];
    self.catFilterSegment.selectedSegment = 0;
    self.catFilterSegment.controlSize = NSControlSizeSmall;
    [self.controls addObjectsFromArray:@[self.catPreampToggle, self.catAttenuatorToggle, self.catFilterSegment]];

    NSStackView *frontendRow = Stack(@[
        Label(@"Frontend:"),
        self.catPreampToggle,
        self.catAttenuatorToggle,
        Label(@"|"),
        Label(@"Filter:"),
        self.catFilterSegment
    ], NO);
    frontendRow.spacing = 6;

    NSStackView *c2Inner = Stack(@[c2Title, freqRow, bandRow1, bandRow2, modePowerRow, frontendRow], YES);
    c2Inner.spacing = 7;
    NSBox *card2 = CreateCardWithView(c2Inner);

    NSStackView *leftColumn = Stack(@[card1, card2], YES);
    leftColumn.spacing = 10;

    // =========================================================================
    // RIGHT COLUMN: Interactive Terminal (Card 3) + Diagnostics (Card 4)
    // =========================================================================

    // --- Card 3: Interactive CAT Command Terminal ---
    NSTextField *c3Title = [NSTextField labelWithString:@"CAT Command Terminal & Live Log"];
    c3Title.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];

    self.catClearTerminalButton = [NSButton buttonWithTitle:@"Clear" target:self action:@selector(clearTerminalAction:)];
    self.catClearTerminalButton.bezelStyle = NSBezelStyleInline;
    self.catClearTerminalButton.controlSize = NSControlSizeSmall;

    self.catCopyTerminalButton = [NSButton buttonWithTitle:@"Copy Log" target:self action:@selector(copyTerminalLogAction:)];
    self.catCopyTerminalButton.bezelStyle = NSBezelStyleInline;
    self.catCopyTerminalButton.controlSize = NSControlSizeSmall;

    [self.controls addObjectsFromArray:@[self.catClearTerminalButton, self.catCopyTerminalButton]];

    NSStackView *c3Header = [NSStackView stackViewWithViews:@[c3Title, self.catClearTerminalButton, self.catCopyTerminalButton]];
    c3Header.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    c3Header.spacing = 6;

    // Command Input Row
    self.catCommandInput = [NSTextField new];
    self.catCommandInput.placeholderString = @"Raw CAT Command (e.g. FA; MD2; PC005;)";
    self.catCommandInput.font = [NSFont fontWithName:@"Menlo" size:11.5] ?: [NSFont monospacedSystemFontOfSize:11.5 weight:NSFontWeightRegular];
    self.catCommandInput.target = self;
    self.catCommandInput.action = @selector(sendCommandAction:);

    self.catSendCommandButton = [NSButton buttonWithTitle:@"Send" target:self action:@selector(sendCommandAction:)];
    self.catSendCommandButton.bezelStyle = NSBezelStyleRounded;
    self.catSendCommandButton.controlSize = NSControlSizeSmall;
    self.catSendCommandButton.keyEquivalent = @"\r"; // Enter triggers send!
    [self.catSendCommandButton.widthAnchor constraintEqualToConstant:60].active = YES;

    [self.controls addObjectsFromArray:@[self.catCommandInput, self.catSendCommandButton]];

    NSTextField *cmdPrompt = [NSTextField labelWithString:@"CMD >"];
    cmdPrompt.font = [NSFont fontWithName:@"Menlo" size:11] ?: [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightBold];
    cmdPrompt.textColor = [NSColor systemGreenColor];

    NSStackView *cmdInputRow = Stack(@[cmdPrompt, self.catCommandInput, self.catSendCommandButton], NO);
    cmdInputRow.spacing = 6;

    // Quick Command Preset Chips
    self.quickCmdButtons = [NSMutableArray array];
    NSArray *chips = @[@"FA;", @"MD;", @"PC;", @"IF;", @"VL;", @"ID;", @"SM0;", @"FL;"];
    NSMutableArray *chipViews = [NSMutableArray array];
    for (NSString *cmd in chips) {
        NSButton *cb = [NSButton buttonWithTitle:cmd target:self action:@selector(quickCommandChipClicked:)];
        cb.identifier = cmd;
        cb.bezelStyle = NSBezelStyleInline;
        cb.font = [NSFont fontWithName:@"Menlo" size:10.5] ?: [NSFont monospacedSystemFontOfSize:10.5 weight:NSFontWeightMedium];
        [self.quickCmdButtons addObject:cb];
        [self.controls addObject:cb];
        [chipViews addObject:cb];
    }
    NSStackView *chipsRow = Stack(chipViews, NO);
    chipsRow.distribution = NSStackViewDistributionFillEqually;
    chipsRow.spacing = 4;

    // Terminal Monospace Text View
    NSScrollView *termScroll = [NSScrollView new];
    termScroll.hasVerticalScroller = YES;
    termScroll.borderType = NSBezelBorder;
    [termScroll.heightAnchor constraintEqualToConstant:145].active = YES;

    self.catTerminalTextView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 420, 145)];
    self.catTerminalTextView.editable = NO;
    self.catTerminalTextView.selectable = YES;
    self.catTerminalTextView.backgroundColor = [NSColor colorWithCalibratedRed:0.07 green:0.08 blue:0.10 alpha:1.0];
    self.catTerminalTextView.textColor = [NSColor colorWithCalibratedRed:0.35 green:0.92 blue:0.45 alpha:1.0];
    self.catTerminalTextView.font = [NSFont fontWithName:@"Menlo" size:11] ?: [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    self.catTerminalTextView.autoresizingMask = NSViewWidthSizable;
    self.catTerminalTextView.textContainer.widthTracksTextView = YES;
    self.catTerminalTextView.textContainerInset = NSMakeSize(6, 6);
    termScroll.documentView = self.catTerminalTextView;

    NSStackView *c3Inner = Stack(@[c3Header, cmdInputRow, chipsRow, termScroll], YES);
    c3Inner.spacing = 6;
    NSBox *card3 = CreateCardWithView(c3Inner);

    // --- Card 4: Diagnostics & Latency Ping ---
    NSTextField *c4Title = [NSTextField labelWithString:@"Diagnostics & Latency Ping"];
    c4Title.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];

    self.catResult = Label(@"Ready to test CAT communication.");
    self.catResult.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightMedium];
    self.catResult.textColor = NSColor.labelColor;

    self.catOnce = [self button:@"Ping Once" action:@selector(startCAT:) tag:1];
    self.catOnce.bezelStyle = NSBezelStyleRounded;
    self.catOnce.controlSize = NSControlSizeSmall;

    self.catStart = [self button:@"Continuous Ping" action:@selector(startCAT:) tag:0];
    self.catStart.bezelStyle = NSBezelStyleRounded;
    self.catStart.controlSize = NSControlSizeSmall;

    self.catCounts = Label(@"Checks: 0    Passed: 0    Failed: 0    RTT: —");
    self.catCounts.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];

    NSStackView *pingRow = Stack(@[self.catOnce, self.catStart, [NSView new]], NO);
    pingRow.spacing = 8;

    NSTextField *pttGuard = Label(@"🛡️ PTT Guard: Test queries are safe & read-only. Transmitter is never keyed.");
    pttGuard.font = [NSFont systemFontOfSize:10 weight:NSFontWeightRegular];
    pttGuard.textColor = NSColor.secondaryLabelColor;

    NSStackView *c4Inner = Stack(@[c4Title, self.catResult, pingRow, self.catCounts, pttGuard], YES);
    c4Inner.spacing = 5;
    NSBox *card4 = CreateCardWithView(c4Inner);

    NSStackView *rightColumn = Stack(@[card3, card4], YES);
    rightColumn.spacing = 10;

    // Symmetrical 2-Column Container
    NSStackView *studioView = [NSStackView stackViewWithViews:@[leftColumn, rightColumn]];
    studioView.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    studioView.alignment = NSLayoutAttributeTop;
    studioView.distribution = NSStackViewDistributionFillEqually;
    studioView.spacing = 12;

    // Anchor widths to guarantee full column width utilization
    [card1.widthAnchor constraintEqualToAnchor:leftColumn.widthAnchor].active = YES;
    [card2.widthAnchor constraintEqualToAnchor:leftColumn.widthAnchor].active = YES;
    [card3.widthAnchor constraintEqualToAnchor:rightColumn.widthAnchor].active = YES;
    [card4.widthAnchor constraintEqualToAnchor:rightColumn.widthAnchor].active = YES;

    [freqBanner.widthAnchor constraintEqualToAnchor:c1Inner.widthAnchor].active = YES;
    [badgeRow1.widthAnchor constraintEqualToAnchor:c1Inner.widthAnchor].active = YES;
    [badgeRow2.widthAnchor constraintEqualToAnchor:c1Inner.widthAnchor].active = YES;
    [freqRow.widthAnchor constraintEqualToAnchor:c2Inner.widthAnchor].active = YES;
    [bandRow1.widthAnchor constraintEqualToAnchor:c2Inner.widthAnchor].active = YES;
    [bandRow2.widthAnchor constraintEqualToAnchor:c2Inner.widthAnchor].active = YES;
    [modePowerRow.widthAnchor constraintEqualToAnchor:c2Inner.widthAnchor].active = YES;
    [frontendRow.widthAnchor constraintEqualToAnchor:c2Inner.widthAnchor].active = YES;
    [c3Header.widthAnchor constraintEqualToAnchor:c3Inner.widthAnchor].active = YES;
    [cmdInputRow.widthAnchor constraintEqualToAnchor:c3Inner.widthAnchor].active = YES;
    [chipsRow.widthAnchor constraintEqualToAnchor:c3Inner.widthAnchor].active = YES;
    [termScroll.widthAnchor constraintEqualToAnchor:c3Inner.widthAnchor].active = YES;

    return studioView;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.controls = [NSMutableArray array];
    self.channels = [TXEmptyMemory() mutableCopy];
    self.view = [NSView new];
    self.view.translatesAutoresizingMaskIntoConstraints = NO;

    // CAT Studio & Diagnostics Panel
    NSView *cat = [self buildCATStudioView];

    // Settings Panel
    self.settingsInfo = Label(@"No settings backup loaded. Read the radio or open an existing .set file.");
    self.settingsRead = [self button:@"Read Radio" action:@selector(readRadio:) tag:1];
    self.settingsWrite = [self button:@"Restore to Radio…" action:@selector(writeRadio:) tag:1];
    self.settingsSave = [self button:@"Save .set…" action:@selector(saveBackup:) tag:1];
    self.settingsCompare = [self button:@"Compare .set…" action:@selector(compareSettingsAction:) tag:1];
    self.settingsExportJson = [self button:@"Export JSON…" action:@selector(exportJsonSettingsAction:) tag:1];
    self.settingsImportJson = [self button:@"Import JSON…" action:@selector(importJsonSettingsAction:) tag:1];

    NSView *settingsRow1 = Stack(@[
        self.settingsRead,
        [self button:@"Open .set…" action:@selector(loadBackup:) tag:1],
        self.settingsSave,
        self.settingsCompare,
        self.settingsWrite
    ], NO);

    self.settingsCategoryFilter = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.settingsCategoryFilter addItemsWithTitles:@[
        @"All Categories",
        @"VFO & Bands",
        @"DSP Filters",
        @"Equalizer & Audio",
        @"CW & Keyer",
        @"Transmitter & VOX",
        @"Receiver & DSP",
        @"Panadapter & Display"
    ]];
    self.settingsCategoryFilter.target = self;
    self.settingsCategoryFilter.action = @selector(settingsCategoryFilterChanged:);
    [self.controls addObjectsFromArray:@[self.settingsCategoryFilter, self.settingsExportJson, self.settingsImportJson]];

    NSView *settingsRow2 = Stack(@[
        Label(@"Category:"),
        self.settingsCategoryFilter,
        Label(@"|"),
        self.settingsExportJson,
        self.settingsImportJson
    ], NO);

    self.settingsTable = [NSTableView new];
    self.settingsTable.delegate = self;
    self.settingsTable.dataSource = self;
    self.settingsTable.rowHeight = 22;
    self.settingsTable.usesAlternatingRowBackgroundColors = YES;

    NSArray *sTitles = @[@"Category", @"Parameter / Setting", @"Addr", @"Value", @"Range / Unit", @"Details"];
    NSArray *sIds = @[@"category", @"name", @"address", @"value", @"unit", @"details"];
    int sWidths[] = {120, 190, 55, 140, 110, 200};
    for (NSUInteger i = 0; i < sTitles.count; i++) {
        NSTableColumn *c = [[NSTableColumn alloc] initWithIdentifier:sIds[i]];
        c.title = sTitles[i];
        c.width = sWidths[i];
        c.editable = NO;
        [self.settingsTable addTableColumn:c];
    }

    NSScrollView *settingsScroll = [NSScrollView new];
    settingsScroll.hasVerticalScroller = YES;
    settingsScroll.borderType = NSBezelBorder;
    settingsScroll.documentView = self.settingsTable;
    [settingsScroll.heightAnchor constraintEqualToConstant:340].active = YES;

    self.settingEditLabel = Label(@"Select a setting:");
    self.settingEditLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    self.settingEditField = [NSTextField new];
    self.settingEditField.placeholderString = @"New value";
    [self.settingEditField.widthAnchor constraintEqualToConstant:160].active = YES;
    self.settingEditField.target = self;
    self.settingEditField.action = @selector(editSettingAction:);
    self.settingApplyButton = [self button:@"Apply Change" action:@selector(editSettingAction:) tag:0];
    [self.controls addObjectsFromArray:@[self.settingEditField, self.settingApplyButton]];

    NSView *settingsEditorRow = Stack(@[
        self.settingEditLabel,
        self.settingEditField,
        self.settingApplyButton
    ], NO);

    NSView *settings = Stack(@[
        settingsRow1,
        settingsRow2,
        settingsScroll,
        settingsEditorRow,
        self.settingsInfo,
        Label(@"Compatible with official Settings utility. Changes update the exact 1024-byte block in memory.")
    ], YES);

    [settingsScroll.widthAnchor constraintEqualToAnchor:settings.widthAnchor].active = YES;

    // Memory Panel
    self.memoryInfo = Label(@"Open a .mem file, read the radio, or create a new bank of 100 channels.");
    self.memoryRead = [self button:@"Read Radio" action:@selector(readRadio:) tag:2];
    self.memoryWrite = [self button:@"Write 100 Channels…" action:@selector(writeRadio:) tag:2];
    self.memorySave = [self button:@"Save .mem…" action:@selector(saveBackup:) tag:2];
    self.memoryCompare = [self button:@"Compare .mem…" action:@selector(compareMemoryAction:) tag:2];
    self.csvImport = [self button:@"Import CSV…" action:@selector(importCSVAction:) tag:2];
    self.csvExport = [self button:@"Export CSV…" action:@selector(exportCSVAction:) tag:2];

    self.profilesPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self populateProfilesMenu];
    self.profilesPopup.target = self;
    self.profilesPopup.action = @selector(profileSelected:);
    [self.controls addObject:self.profilesPopup];

    NSView *memoryRow1 = Stack(@[
        self.memoryRead,
        [self button:@"Open .mem…" action:@selector(loadBackup:) tag:2],
        self.memorySave,
        self.memoryCompare,
        [self button:@"New Bank" action:@selector(newBank:) tag:2],
        self.memoryWrite
    ], NO);

    NSView *memoryRow2 = Stack(@[
        Label(@"Operating Profiles:"),
        self.profilesPopup,
        Label(@"|"),
        self.csvImport,
        self.csvExport
    ], NO);

    self.table = [NSTableView new];
    self.table.delegate = self;
    self.table.dataSource = self;
    self.table.rowHeight = 22;
    self.table.usesAlternatingRowBackgroundColors = YES;

    NSArray *titles = @[@"Channel", @"Frequency (Hz)", @"Mode", @"PreAtt"];
    NSArray *identifiers = @[@"channel", @"frequency", @"mode", @"preAtt"];
    for (NSUInteger i = 0; i < titles.count; i++) {
        NSTableColumn *c = [[NSTableColumn alloc] initWithIdentifier:identifiers[i]];
        c.title = titles[i];
        c.width = (i == 1 ? 240 : 140);
        c.editable = NO;
        [self.table addTableColumn:c];
    }

    NSScrollView *scroll = [NSScrollView new];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    scroll.documentView = self.table;
    [scroll.heightAnchor constraintEqualToConstant:340].active = YES;

    self.frequency = [NSTextField new];
    self.frequency.placeholderString = @"100000–56000000";
    [self.frequency.widthAnchor constraintEqualToConstant:155].active = YES;
    self.mode = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.mode addItemsWithTitles:@[@"LSB", @"USB", @"CW", @"FM", @"AM", @"CWR", @"DIG (USB)"]];
    self.preAtt = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.preAtt addItemsWithTitles:@[@"Off", @"PRE", @"ATT"]];
    [self.controls addObjectsFromArray:@[self.frequency, self.mode, self.preAtt]];

    NSView *editor = Stack(@[
        Label(@"Hz:"), self.frequency, self.mode, self.preAtt,
        [self button:@"Apply to Row" action:@selector(editChannel:) tag:0],
        [self button:@"Clear Row" action:@selector(editChannel:) tag:1]
    ], NO);

    NSView *memory = Stack(@[
        memoryRow1,
        memoryRow2,
        scroll,
        editor,
        self.memoryInfo,
        Label(@"Edits stay in this bank until Write is clicked. DIG uses the USB code, as in the original utility.")
    ], YES);

    [scroll.widthAnchor constraintEqualToAnchor:memory.widthAnchor].active = YES;

    self.panels = @[cat, settings, memory];
    for (NSView *panel in self.panels) {
        panel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:panel];
        [NSLayoutConstraint activateConstraints:@[
            [panel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [panel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [panel.topAnchor constraintEqualToAnchor:self.view.topAnchor]
        ]];
        if (panel != cat) {
            for (NSView *child in ((NSStackView *)panel).arrangedSubviews) {
                if ([child isKindOfClass:NSTextField.class]) {
                    [child.widthAnchor constraintEqualToAnchor:panel.widthAnchor].active = YES;
                }
            }
        }
    }

    self.stop = [NSButton buttonWithTitle:@"Stop" target:self action:@selector(stopOperation:)];
    self.stop.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.stop];
    [NSLayoutConstraint activateConstraints:@[
        [self.view.heightAnchor constraintEqualToConstant:520],
        [self.stop.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.stop.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    [self selectTool:0];
    return self;
}

- (void)selectTool:(NSInteger)tool {
    if (self.busy) return;
    self.tool = tool;
    for (NSUInteger i = 0; i < self.panels.count; i++) {
        self.panels[i].hidden = ((NSInteger)i != tool);
    }
    [self refresh];
}

- (void)portsAvailable:(BOOL)available {
    self.hasPorts = available;
    [self refresh];
}

- (void)refresh {
    for (NSControl *c in self.controls) c.enabled = !self.busy;
    self.table.enabled = !self.busy;
    self.stop.enabled = self.busy;
    self.stop.hidden = !self.busy;

    // CAT Controls
    BOOL canCAT = !self.busy && self.hasPorts;
    self.catOnce.enabled = self.catStart.enabled = canCAT;
    self.catReadAllButton.enabled = canCAT;
    self.catSetFreqButton.enabled = canCAT;
    self.catSetModeButton.enabled = canCAT;
    self.catSetPowerButton.enabled = canCAT;
    self.catSendCommandButton.enabled = canCAT;
    self.catPreampToggle.enabled = canCAT;
    self.catAttenuatorToggle.enabled = canCAT;
    self.catFilterSegment.enabled = canCAT;
    for (NSButton *b in self.bandButtons) b.enabled = canCAT;
    for (NSButton *b in self.quickCmdButtons) b.enabled = canCAT;

    // Settings & Memory
    self.settingsRead.enabled = self.memoryRead.enabled = canCAT;
    self.settingsSave.enabled = !self.busy && self.settingsData != nil;
    self.settingsCompare.enabled = !self.busy;
    self.settingsWrite.enabled = self.settingsSave.enabled && self.hasPorts;
    self.memorySave.enabled = !self.busy && self.memoryReady;
    self.memoryCompare.enabled = !self.busy;
    self.csvExport.enabled = !self.busy && self.memoryReady;
    self.csvImport.enabled = !self.busy;
    self.profilesPopup.enabled = !self.busy;
    self.memoryWrite.enabled = self.memorySave.enabled && self.hasPorts;
}

- (void)alert:(NSString *)title message:(NSString *)message {
    NSAlert *a = [NSAlert new];
    a.messageText = title;
    a.informativeText = message ?: @"Unknown error";
    [a addButtonWithTitle:@"OK"];
    [a beginSheetModalForWindow:self.window completionHandler:nil];
}

- (BOOL)confirm:(NSString *)title message:(NSString *)message button:(NSString *)button {
    NSAlert *a = [NSAlert new];
    a.messageText = title;
    a.informativeText = message;
    [a addButtonWithTitle:button];
    [a addButtonWithTitle:@"Cancel"];
    return [a runModal] == NSAlertFirstButtonReturn;
}

- (BOOL)confirmReplacement:(NSInteger)kind {
    BOOL dirty = (kind == 1 ? self.settingsDirty : self.memoryDirty);
    return !dirty || [self confirm:@"Replace the unsaved bank?"
                           message:@"Save your current backup first if you want to keep it. This replaces only the data open in the app."
                            button:@"Replace"];
}

- (BOOL)confirmDiscard {
    return (!self.settingsDirty && !self.memoryDirty) || [self confirm:@"Close with unsaved backups?"
        message:@"Settings or memory changes have not been saved to a file."
         button:@"Close Without Saving"];
}

- (void)begin {
    self.busy = YES;
    self.token = [Lab599Cancellation new];
    [self refresh];
    if (self.activityChanged) self.activityChanged(YES);
}

- (void)end {
    self.busy = NO;
    self.token = nil;
    [self refresh];
    if (self.activityChanged) self.activityChanged(NO);
}

- (void)stopOperation:(id)sender {
    (void)sender;
    self.token.cancelled = YES;
    self.stop.enabled = NO;
    if (self.statusChanged) self.statusChanged(@"Stopping and closing the serial port…", 0);
}

#pragma mark - CAT Studio & Test

- (void)appendTerminalTX:(NSString *)cmd {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.catTerminalTextView) return;
        NSDateFormatter *df = [NSDateFormatter new];
        df.dateFormat = @"HH:mm:ss.SSS";
        NSString *ts = [df stringFromDate:[NSDate date]];
        NSString *line = [NSString stringWithFormat:@"[%@] TX >> %@\n", ts, cmd];
        
        NSDictionary *attrs = @{
            NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.3 green:0.8 blue:1.0 alpha:1.0],
            NSFontAttributeName: [NSFont fontWithName:@"Menlo" size:11] ?: [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular]
        };
        NSAttributedString *astr = [[NSAttributedString alloc] initWithString:line attributes:attrs];
        [self.catTerminalTextView.textStorage appendAttributedString:astr];
        [self.catTerminalTextView scrollToEndOfDocument:nil];
    });
}

- (void)appendTerminalRX:(NSString *)reply latency:(double)latency error:(BOOL)isErr {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.catTerminalTextView) return;
        NSDateFormatter *df = [NSDateFormatter new];
        df.dateFormat = @"HH:mm:ss.SSS";
        NSString *ts = [df stringFromDate:[NSDate date]];
        NSString *line = [NSString stringWithFormat:@"[%@] RX << %@ (%.0f ms)\n", ts, reply ?: @"(none)", latency];
        
        NSColor *color = isErr ? [NSColor colorWithCalibratedRed:1.0 green:0.4 blue:0.4 alpha:1.0] :
                                 [NSColor colorWithCalibratedRed:0.35 green:0.95 blue:0.45 alpha:1.0];
        NSDictionary *attrs = @{
            NSForegroundColorAttributeName: color,
            NSFontAttributeName: [NSFont fontWithName:@"Menlo" size:11] ?: [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular]
        };
        NSAttributedString *astr = [[NSAttributedString alloc] initWithString:line attributes:attrs];
        [self.catTerminalTextView.textStorage appendAttributedString:astr];
        [self.catTerminalTextView scrollToEndOfDocument:nil];
    });
}

- (void)clearTerminalAction:(id)sender {
    (void)sender;
    [self.catTerminalTextView.textStorage setAttributedString:[NSAttributedString new]];
}

- (void)copyTerminalLogAction:(id)sender {
    (void)sender;
    NSString *text = self.catTerminalTextView.string ?: @"";
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:text forType:NSPasteboardTypeString];
    if (self.statusChanged) self.statusChanged(@"CAT Terminal log copied to clipboard.", 0);
}

- (void)updateRadioStateUI:(TXRadioState *)state {
    if (state.modelID.length) self.catModelLabel.stringValue = [NSString stringWithFormat:@"Transceiver Model: %@", state.modelID];
    if (state.frequencyDisplay.length) {
        self.catFreqDisplay.stringValue = state.frequencyDisplay;
        self.catFreqInputField.stringValue = [NSString stringWithFormat:@"%llu", state.frequencyHz];
    }
    self.catModeBadge.stringValue = [NSString stringWithFormat:@"MODE: %@", state.operatingMode ?: @"—"];
    self.catPowerBadge.stringValue = [NSString stringWithFormat:@"PWR: %.0f W", state.rfPowerWatts];
    self.catFilterBadge.stringValue = [NSString stringWithFormat:@"FIL: FL%ld", (long)state.filterNumber];
    self.catPreampBadge.stringValue = [NSString stringWithFormat:@"PRE: %@", state.preampOn ? @"ON" : @"OFF"];
    self.catVoltageBadge.stringValue = [NSString stringWithFormat:@"VOLT: %.1f V", state.voltage];
    self.catSMeterBadge.stringValue = [NSString stringWithFormat:@"S-MTR: S%ld", (long)MIN(9, state.sMeterDots / 3)];

    // Sync input controls with read values
    if (state.operatingMode.length) {
        [self.catModePopup selectItemWithTitle:state.operatingMode];
    }
    if (state.rfPowerWatts > 0) {
        NSString *pTitle = [NSString stringWithFormat:@"%ld W", (long)round(state.rfPowerWatts)];
        NSInteger idx = [self.catPowerPopup indexOfItemWithTitle:pTitle];
        if (idx >= 0) [self.catPowerPopup selectItemAtIndex:idx];
    }
    if (state.filterNumber >= 1 && state.filterNumber <= 3) {
        self.catFilterSegment.selectedSegment = state.filterNumber - 1;
    }
    self.catPreampToggle.state = state.preampOn ? NSControlStateValueOn : NSControlStateValueOff;
    self.catAttenuatorToggle.state = state.attenuatorOn ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)updateStateFromCommand:(NSString *)cmd reply:(NSString *)reply {
    if ([cmd hasPrefix:@"FA"] && reply && [reply hasPrefix:@"FA"] && reply.length >= 13) {
        NSString *digits = [reply substringWithRange:NSMakeRange(2, 11)];
        uint64_t f = (uint64_t)[digits longLongValue];
        if (f > 0) {
            self.catFreqDisplay.stringValue = ToolsFormatFreq(f);
            self.catFreqInputField.stringValue = [NSString stringWithFormat:@"%llu", f];
        }
    } else if ([cmd hasPrefix:@"MD"] && reply && [reply hasPrefix:@"MD"] && reply.length >= 3) {
        int m = [[reply substringWithRange:NSMakeRange(2, 1)] intValue];
        NSString *mName = ToolsModeNameFromCode(m);
        self.catModeBadge.stringValue = [NSString stringWithFormat:@"MODE: %@", mName];
        [self.catModePopup selectItemWithTitle:mName];
    } else if ([cmd hasPrefix:@"PC"] && reply && [reply hasPrefix:@"PC"] && reply.length >= 5) {
        int p = [[reply substringWithRange:NSMakeRange(2, 3)] intValue];
        self.catPowerBadge.stringValue = [NSString stringWithFormat:@"PWR: %d W", p];
    } else if ([cmd hasPrefix:@"FL"] && reply && [reply hasPrefix:@"FL"] && reply.length >= 3) {
        int fl = [[reply substringFromIndex:2] intValue];
        self.catFilterBadge.stringValue = [NSString stringWithFormat:@"FIL: FL%d", fl];
        if (fl >= 1 && fl <= 3) self.catFilterSegment.selectedSegment = fl - 1;
    } else if ([cmd hasPrefix:@"PA"] && reply && [reply hasPrefix:@"PA"] && reply.length >= 3) {
        BOOL on = ([reply characterAtIndex:2] == '1');
        self.catPreampBadge.stringValue = [NSString stringWithFormat:@"PRE: %@", on ? @"ON" : @"OFF"];
        self.catPreampToggle.state = on ? NSControlStateValueOn : NSControlStateValueOff;
    } else if ([cmd hasPrefix:@"RA"] && reply && [reply hasPrefix:@"RA"] && reply.length >= 3) {
        int r = [[reply substringFromIndex:2] intValue];
        self.catAttenuatorToggle.state = (r > 0) ? NSControlStateValueOn : NSControlStateValueOff;
    } else if ([cmd hasPrefix:@"VL"] && reply) {
        NSString *clean = [[reply componentsSeparatedByCharactersInSet:
                            [NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsJoinedByString:@""];
        NSRange prefix = [clean rangeOfString:@"VL"];
        if (prefix.location != NSNotFound) {
            NSString *field = [clean substringFromIndex:NSMaxRange(prefix)];
            field = [field stringByReplacingOccurrencesOfString:@";" withString:@""];
            double v = field.doubleValue;
            if (v > 20.0) v = v / 10.0;
            if (v >= 7.0 && v <= 20.0) {
                self.catVoltageBadge.stringValue = [NSString stringWithFormat:@"VOLT: %.1f V", v];
            }
        }
    } else if ([cmd hasPrefix:@"ID"] && reply) {
        if ([reply containsString:@"ID019"]) self.catModelLabel.stringValue = @"Transceiver Model: Lab599 TX-500 Discovery (ID019)";
        else if ([reply containsString:@"ID500"]) self.catModelLabel.stringValue = @"Transceiver Model: Lab599 TX-500 Discovery (ID500)";
        else if ([reply containsString:@"ID501"]) self.catModelLabel.stringValue = @"Transceiver Model: Lab599 TX-500MP (ID501)";
        else if ([reply containsString:@"ID502"]) self.catModelLabel.stringValue = @"Transceiver Model: Lab599 TX-500PRO (ID502)";
        else if ([reply containsString:@"ID505"]) self.catModelLabel.stringValue = @"Transceiver Model: Lab599 TX-500PRO ALTAI (ID505)";
    }
}

- (void)readRadioStateAction:(id)sender {
    (void)sender;
    if (self.busy || !self.hasPorts) return;
    NSString *port = self.selectedPort ? self.selectedPort() : nil;
    if (!port) return;

    [self begin];
    [self appendTerminalTX:@"READ ALL (ID; IF; FA; MD; PC; FL; PA; RA; VL; SM0;)"];
    if (self.statusChanged) self.statusChanged(@"Reading comprehensive transceiver state over CAT...", 0);

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *err = nil;
        double started = Lab599MonotonicTime();
        TXRadioState *state = TXReadRadioState(port, 0.35, &err);
        double elapsed = (Lab599MonotonicTime() - started) * 1000.0;

        dispatch_async(dispatch_get_main_queue(), ^{
            [self end];
            if (state) {
                [self appendTerminalRX:[NSString stringWithFormat:@"%@ | Freq: %@ | Mode: %@ | Pwr: %.0fW | Volt: %.1fV",
                                        state.modelID, state.frequencyDisplay, state.operatingMode, state.rfPowerWatts, state.voltage]
                                latency:elapsed error:NO];
                [self updateRadioStateUI:state];
                if (self.statusChanged) self.statusChanged([NSString stringWithFormat:@"Radio state read successfully in %.0f ms.", elapsed], 1);
            } else {
                [self appendTerminalRX:err.localizedDescription ?: @"Timeout" latency:elapsed error:YES];
                if (self.statusChanged) self.statusChanged([NSString stringWithFormat:@"Failed to read radio: %@", err.localizedDescription ?: @"Port error"], 0);
            }
        });
    });
}

- (void)sendCommandAction:(id)sender {
    (void)sender;
    if (self.busy || !self.hasPorts) return;
    NSString *port = self.selectedPort ? self.selectedPort() : nil;
    if (!port) return;

    NSString *cmd = [self.catCommandInput.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!cmd.length) return;
    if (![cmd hasSuffix:@";"]) cmd = [cmd stringByAppendingString:@";"];

    [self begin];
    [self appendTerminalTX:cmd];
    if (self.statusChanged) self.statusChanged([NSString stringWithFormat:@"Sending CAT: %@", cmd], 0);

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *err = nil;
        double rtt = 0;
        NSString *reply = TXExecuteCATCommand(port, cmd, 0.4, &rtt, &err);

        dispatch_async(dispatch_get_main_queue(), ^{
            [self end];
            if (reply) {
                [self appendTerminalRX:reply latency:rtt error:NO];
                if (self.statusChanged) self.statusChanged([NSString stringWithFormat:@"Reply: %@ (%.0f ms)", reply, rtt], 1);
                [self updateStateFromCommand:cmd reply:reply];
            } else {
                [self appendTerminalRX:err ? err.localizedDescription : @"No reply / Timeout" latency:rtt error:YES];
                if (self.statusChanged) self.statusChanged([NSString stringWithFormat:@"Error sending %@: %@", cmd, err.localizedDescription ?: @"Timeout"], 0);
            }
        });
    });
}

- (void)bandPresetClicked:(NSButton *)sender {
    uint64_t freq = (uint64_t)sender.tag;
    if (freq > 0) {
        self.catFreqInputField.stringValue = [NSString stringWithFormat:@"%llu", freq];
        [self setFrequencyAction:sender];
    }
}

- (void)quickCommandChipClicked:(NSButton *)sender {
    NSString *cmd = sender.identifier;
    if (cmd.length) {
        self.catCommandInput.stringValue = cmd;
        [self sendCommandAction:sender];
    }
}

- (void)setFrequencyAction:(id)sender {
    (void)sender;
    if (self.busy || !self.hasPorts) return;
    NSString *port = self.selectedPort ? self.selectedPort() : nil;
    if (!port) return;

    NSString *raw = [self.catFreqInputField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    raw = [raw stringByReplacingOccurrencesOfString:@"," withString:@""];
    raw = [raw stringByReplacingOccurrencesOfString:@"." withString:@""];
    uint64_t freq = (uint64_t)[raw longLongValue];
    if (freq < 100000 || freq > 60000000) {
        [self alert:@"Invalid Frequency" message:@"Please enter a valid frequency between 100 kHz (100000 Hz) and 60 MHz (60000000 Hz)."];
        return;
    }

    [self begin];
    NSString *cmd = [NSString stringWithFormat:@"FA%011llu;", freq];
    [self appendTerminalTX:cmd];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *err = nil;
        double rtt = 0;
        NSString *reply = TXExecuteCATCommand(port, cmd, 0.35, &rtt, &err);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self end];
            if (!err) {
                [self appendTerminalRX:reply ?: cmd latency:rtt error:NO];
                self.catFreqDisplay.stringValue = ToolsFormatFreq(freq);
                if (self.statusChanged) self.statusChanged([NSString stringWithFormat:@"Frequency tuned to %@", ToolsFormatFreq(freq)], 1);
            } else {
                [self appendTerminalRX:err.localizedDescription ?: @"Error" latency:rtt error:YES];
            }
        });
    });
}

- (void)setModeAction:(id)sender {
    (void)sender;
    if (self.busy || !self.hasPorts) return;
    NSString *port = self.selectedPort ? self.selectedPort() : nil;
    if (!port) return;

    NSInteger idx = self.catModePopup.indexOfSelectedItem;
    NSInteger code = idx + 1;
    NSString *modeName = self.catModePopup.titleOfSelectedItem;

    [self begin];
    NSString *cmd = [NSString stringWithFormat:@"MD%ld;", (long)code];
    [self appendTerminalTX:cmd];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *err = nil;
        double rtt = 0;
        NSString *reply = TXExecuteCATCommand(port, cmd, 0.35, &rtt, &err);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self end];
            if (!err) {
                [self appendTerminalRX:reply ?: cmd latency:rtt error:NO];
                self.catModeBadge.stringValue = [NSString stringWithFormat:@"MODE: %@", modeName];
                if (self.statusChanged) self.statusChanged([NSString stringWithFormat:@"Mode set to %@", modeName], 1);
            } else {
                [self appendTerminalRX:err.localizedDescription ?: @"Error" latency:rtt error:YES];
            }
        });
    });
}

- (void)setPowerAction:(id)sender {
    (void)sender;
    if (self.busy || !self.hasPorts) return;
    NSString *port = self.selectedPort ? self.selectedPort() : nil;
    if (!port) return;

    NSString *pTitle = self.catPowerPopup.titleOfSelectedItem;
    double watts = [pTitle doubleValue];
    if (watts <= 0) watts = 10.0;

    [self begin];
    NSString *cmd = [NSString stringWithFormat:@"PC%03d;", (int)round(watts)];
    [self appendTerminalTX:cmd];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *err = nil;
        double rtt = 0;
        NSString *reply = TXExecuteCATCommand(port, cmd, 0.35, &rtt, &err);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self end];
            if (!err) {
                [self appendTerminalRX:reply ?: cmd latency:rtt error:NO];
                self.catPowerBadge.stringValue = [NSString stringWithFormat:@"PWR: %.0f W", watts];
                if (self.statusChanged) self.statusChanged([NSString stringWithFormat:@"RF Power set to %.0f W", watts], 1);
            } else {
                [self appendTerminalRX:err.localizedDescription ?: @"Error" latency:rtt error:YES];
            }
        });
    });
}

- (void)togglePreampAction:(NSButton *)sender {
    if (self.busy || !self.hasPorts) return;
    NSString *port = self.selectedPort ? self.selectedPort() : nil;
    if (!port) return;

    BOOL on = (sender.state == NSControlStateValueOn);
    [self begin];
    NSString *cmd = [NSString stringWithFormat:@"PA%d;", on ? 1 : 0];
    [self appendTerminalTX:cmd];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *err = nil;
        double rtt = 0;
        NSString *reply = TXExecuteCATCommand(port, cmd, 0.35, &rtt, &err);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self end];
            if (!err) {
                [self appendTerminalRX:reply ?: cmd latency:rtt error:NO];
                self.catPreampBadge.stringValue = [NSString stringWithFormat:@"PRE: %@", on ? @"ON" : @"OFF"];
            } else {
                [self appendTerminalRX:err.localizedDescription ?: @"Error" latency:rtt error:YES];
            }
        });
    });
}

- (void)toggleAttenuatorAction:(NSButton *)sender {
    if (self.busy || !self.hasPorts) return;
    NSString *port = self.selectedPort ? self.selectedPort() : nil;
    if (!port) return;

    BOOL on = (sender.state == NSControlStateValueOn);
    [self begin];
    NSString *cmd = [NSString stringWithFormat:@"RA%02d;", on ? 1 : 0];
    [self appendTerminalTX:cmd];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *err = nil;
        double rtt = 0;
        NSString *reply = TXExecuteCATCommand(port, cmd, 0.35, &rtt, &err);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self end];
            if (!err) {
                [self appendTerminalRX:reply ?: cmd latency:rtt error:NO];
            } else {
                [self appendTerminalRX:err.localizedDescription ?: @"Error" latency:rtt error:YES];
            }
        });
    });
}

- (void)filterChangedAction:(NSSegmentedControl *)sender {
    if (self.busy || !self.hasPorts) return;
    NSString *port = self.selectedPort ? self.selectedPort() : nil;
    if (!port) return;

    NSInteger filterNum = sender.selectedSegment + 1;
    [self begin];
    NSString *cmd = [NSString stringWithFormat:@"FL%ld;", (long)filterNum];
    [self appendTerminalTX:cmd];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *err = nil;
        double rtt = 0;
        NSString *reply = TXExecuteCATCommand(port, cmd, 0.35, &rtt, &err);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self end];
            if (!err) {
                [self appendTerminalRX:reply ?: cmd latency:rtt error:NO];
                self.catFilterBadge.stringValue = [NSString stringWithFormat:@"FIL: FL%ld", (long)filterNum];
            } else {
                [self appendTerminalRX:err.localizedDescription ?: @"Error" latency:rtt error:YES];
            }
        });
    });
}

- (void)startCAT:(NSButton *)sender {
    if (self.busy || !self.hasPorts) return;
    NSString *port = self.selectedPort ? self.selectedPort() : nil;
    if (!port) return;
    [self begin];
    TXCATOptions options = TXDefaultCATOptions();
    options.maximumChecks = sender.tag;
    self.catResult.stringValue = @"Waiting for the radio…";
    self.catCounts.stringValue = @"Checks: 0    Passed: 0    Failed: 0";
    [self appendTerminalTX:@"PING (ID;)"];
    Lab599Cancellation *token = self.token;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        TXCATSummary *result = TXRunCATTest(port, options, token, ^(TXCATSummary *s){
            dispatch_async(dispatch_get_main_queue(), ^{
                self.catResult.stringValue = [NSString stringWithFormat:@"%@\nReply: %@", s.message, s.lastReply ?: @"—"];
                self.catCounts.stringValue = [NSString stringWithFormat:@"Checks: %lu    Passed: %lu    Failed: %lu    Reply: %.0f ms",
                    (unsigned long)s.checks, (unsigned long)s.passed, (unsigned long)s.failed, s.responseMilliseconds];
                [self appendTerminalRX:s.lastReply latency:s.responseMilliseconds error:(s.lastCode != TXCATOK)];
                if (self.statusChanged) self.statusChanged(s.message, 0);
            });
        }, ^(NSString *line){
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.log) self.log(line);
            });
        });
        dispatch_async(dispatch_get_main_queue(), ^{
            [self end];
            if (self.statusChanged) {
                self.statusChanged(result.cancelled ? @"CAT test stopped. Port closed." : result.message,
                                   result.passed && !result.failed ? 1 : 0);
            }
        });
    });
}

#pragma mark - Descriptions

- (void)settingsDescription {
    self.settingsInfo.stringValue = [NSString stringWithFormat:@"%@\n1024 bytes • %@\nSHA-256: %@",
        self.settingsSource ?: @"Settings Backup",
        self.settingsDirty ? @"Not saved to a file" : @"Saved backup",
        TXFirmwareSHA256(self.settingsData)];
}

- (void)memoryDescription {
    NSUInteger used = 0;
    for (TXMemoryChannel *c in self.channels) if (c.frequency) used++;
    self.memoryInfo.stringValue = [NSString stringWithFormat:@"100 channels • %lu used • %lu empty%@",
        (unsigned long)used, (unsigned long)(100 - used), self.memoryDirty ? @" • Unsaved changes" : @""];
}

#pragma mark - Backups Load & Save

- (void)loadBackup:(NSButton *)sender {
    if (self.busy || ![self confirmReplacement:sender.tag]) return;
    NSInteger kind = sender.tag;
    NSOpenPanel *p = [NSOpenPanel openPanel];
    p.allowsMultipleSelection = NO;
    p.canChooseDirectories = NO;
    p.allowedContentTypes = @[[UTType typeWithFilenameExtension:kind == 1 ? @"set" : @"mem" conformingToType:UTTypeData]];
    [p beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response){
        if (response != NSModalResponseOK) return;
        NSError *error = nil;
        NSNumber *size = nil;
        [p.URL getResourceValue:&size forKey:NSURLFileSizeKey error:&error];
        if (size.unsignedIntegerValue != (kind == 1 ? 1024 : 600)) {
            [self alert:@"Invalid backup" message:kind == 1 ? @"A .set file must be exactly 1024 bytes." : @"A .mem file must be exactly 600 bytes."];
            return;
        }
        NSData *data = [NSData dataWithContentsOfURL:p.URL options:0 error:&error];
        if (!data) {
            [self alert:@"Cannot open backup" message:error.localizedDescription];
            return;
        }
        if (kind == 1) {
            NSString *validation = TXValidateSettings(data);
            if (validation) { [self alert:@"Invalid settings file" message:validation]; return; }
            self.settingsData = data;
            self.settingsSource = p.URL.lastPathComponent;
            self.settingsDirty = NO;
            [self updateSettingsModelFromData];
            [self settingsDescription];
        } else {
            NSArray *items = TXDecodeMemory(data, &error);
            if (!items) { [self alert:@"Invalid memory file" message:error.localizedDescription]; return; }
            self.channels = [items mutableCopy];
            self.memoryReady = YES;
            self.memoryDirty = NO;
            [self.table reloadData];
            [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
            [self memoryDescription];
            [self tableViewSelectionDidChange:[NSNotification notificationWithName:NSTableViewSelectionDidChangeNotification object:self.table]];
        }
        [self refresh];
        if (self.log) self.log([NSString stringWithFormat:@"Loaded %@ (%lu bytes).", p.URL.lastPathComponent, (unsigned long)data.length]);
    }];
}

- (void)saveBackup:(NSButton *)sender {
    if (self.busy) return;
    NSInteger kind = sender.tag;
    NSError *error = nil;
    NSData *data = (kind == 1 ? self.settingsData : TXEncodeMemory(self.channels, &error));
    if (!data) {
        [self alert:@"Cannot save backup" message:error.localizedDescription];
        return;
    }
    NSSavePanel *p = [NSSavePanel savePanel];
    p.allowedContentTypes = @[[UTType typeWithFilenameExtension:kind == 1 ? @"set" : @"mem" conformingToType:UTTypeData]];
    p.nameFieldStringValue = (kind == 1 ? @"TX-500-settings.set" : @"TX-500-memory.mem");
    [p beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response){
        if (response != NSModalResponseOK) return;
        NSError *writeError = nil;
        if (![data writeToURL:p.URL options:NSDataWritingAtomic error:&writeError]) {
            [self alert:@"Cannot save backup" message:writeError.localizedDescription];
            return;
        }
        if (kind == 1) {
            self.settingsDirty = NO;
            self.settingsSource = p.URL.lastPathComponent;
            [self settingsDescription];
        } else {
            self.memoryDirty = NO;
            [self memoryDescription];
        }
        if (self.log) self.log([NSString stringWithFormat:@"Saved %@ (%lu bytes).", p.URL.lastPathComponent, (unsigned long)data.length]);
    }];
}

- (void)newBank:(id)sender {
    (void)sender;
    if (self.busy || ![self confirmReplacement:2]) return;
    self.channels = [TXEmptyMemory() mutableCopy];
    self.memoryReady = YES;
    self.memoryDirty = YES;
    [self.table reloadData];
    [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [self tableViewSelectionDidChange:[NSNotification notificationWithName:NSTableViewSelectionDidChangeNotification object:self.table]];
    [self memoryDescription];
    [self refresh];
}

#pragma mark - Table View (Memory Channels, Settings & Comparison)

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == self.compareTable) {
        if (self.isSettingsComparison) {
            return self.activeSettingsDiff ? (NSInteger)self.activeSettingsDiff.diffItems.count : 0;
        } else {
            return self.activeMemoryDiff ? (NSInteger)self.activeMemoryDiff.diffItems.count : 0;
        }
    }
    if (tableView == self.settingsTable) {
        return self.filteredSettingsItems ? (NSInteger)self.filteredSettingsItems.count : 0;
    }
    return self.memoryReady ? 100 : 0;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView == self.settingsTable) {
        if (row < 0 || (NSUInteger)row >= self.filteredSettingsItems.count) return nil;
        TXSettingsItem *item = self.filteredSettingsItems[row];

        NSTableCellView *cell = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
        if (!cell) {
            cell = [NSTableCellView new];
            cell.identifier = tableColumn.identifier;

            NSTextField *tf = [NSTextField labelWithString:@""];
            tf.translatesAutoresizingMaskIntoConstraints = NO;
            tf.lineBreakMode = NSLineBreakByTruncatingTail;
            cell.textField = tf;
            [cell addSubview:tf];

            [NSLayoutConstraint activateConstraints:@[
                [tf.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
                [tf.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
                [tf.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
            ]];
        }

        NSTextField *tf = cell.textField;
        NSString *colId = tableColumn.identifier;
        if ([colId isEqual:@"category"]) {
            tf.stringValue = item.category ?: @"";
            tf.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
            tf.textColor = NSColor.secondaryLabelColor;
        } else if ([colId isEqual:@"name"]) {
            tf.stringValue = item.name ?: @"";
            tf.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightSemibold];
            tf.textColor = NSColor.labelColor;
        } else if ([colId isEqual:@"address"]) {
            tf.stringValue = [NSString stringWithFormat:@"%lu", (unsigned long)item.address];
            tf.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
            tf.textColor = NSColor.secondaryLabelColor;
        } else if ([colId isEqual:@"value"]) {
            tf.stringValue = [item displayValue] ?: @"";
            tf.font = [NSFont monospacedSystemFontOfSize:11.5 weight:NSFontWeightBold];
            tf.textColor = [NSColor colorWithCalibratedRed:0.20 green:0.55 blue:0.95 alpha:1.0];
        } else if ([colId isEqual:@"unit"]) {
            tf.stringValue = item.unitOrRange ?: @"";
            tf.font = [NSFont systemFontOfSize:11];
            tf.textColor = NSColor.secondaryLabelColor;
        } else if ([colId isEqual:@"details"]) {
            tf.stringValue = item.details ?: @"";
            tf.font = [NSFont systemFontOfSize:11];
            tf.textColor = NSColor.labelColor;
        }
        return cell;
    }

    if (tableView == self.table) {
        if (row < 0 || (NSUInteger)row >= self.channels.count) return nil;
        TXMemoryChannel *c = self.channels[row];

        NSTableCellView *cell = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
        if (!cell) {
            cell = [NSTableCellView new];
            cell.identifier = tableColumn.identifier;

            NSTextField *tf = [NSTextField labelWithString:@""];
            tf.translatesAutoresizingMaskIntoConstraints = NO;
            tf.lineBreakMode = NSLineBreakByTruncatingTail;
            cell.textField = tf;
            [cell addSubview:tf];

            [NSLayoutConstraint activateConstraints:@[
                [tf.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
                [tf.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
                [tf.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
            ]];
        }

        NSTextField *tf = cell.textField;
        NSString *colId = tableColumn.identifier;
        if ([colId isEqual:@"channel"]) {
            tf.stringValue = [NSString stringWithFormat:@"%02ld", (long)row];
            tf.font = [NSFont monospacedDigitSystemFontOfSize:11.5 weight:NSFontWeightBold];
            tf.textColor = NSColor.labelColor;
        } else if ([colId isEqual:@"frequency"]) {
            if (!c.frequency) {
                tf.stringValue = @"Empty";
                tf.textColor = NSColor.secondaryLabelColor;
            } else {
                tf.stringValue = [NSString stringWithFormat:@"%u Hz (%.4f MHz)", c.frequency, (double)c.frequency / 1000000.0];
                tf.textColor = NSColor.labelColor;
            }
            tf.font = [NSFont monospacedDigitSystemFontOfSize:11.5 weight:NSFontWeightMedium];
        } else if ([colId isEqual:@"mode"]) {
            tf.stringValue = @{@49:@"LSB", @50:@"USB", @51:@"CW", @52:@"FM", @53:@"AM", @55:@"CWR"}[@(c.mode)] ?: @"—";
            tf.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightMedium];
            tf.textColor = NSColor.labelColor;
        } else if ([colId isEqual:@"preAtt"]) {
            tf.stringValue = @[@"Off", @"PRE", @"ATT"][c.preAtt - '0'];
            tf.font = [NSFont systemFontOfSize:11];
            tf.textColor = NSColor.secondaryLabelColor;
        }
        return cell;
    }

    if (tableView == self.compareTable) {
        NSTableCellView *cell = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
        if (!cell) {
            cell = [NSTableCellView new];
            cell.identifier = tableColumn.identifier;

            NSTextField *tf = [NSTextField labelWithString:@""];
            tf.translatesAutoresizingMaskIntoConstraints = NO;
            tf.lineBreakMode = NSLineBreakByTruncatingTail;
            cell.textField = tf;
            [cell addSubview:tf];

            [NSLayoutConstraint activateConstraints:@[
                [tf.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
                [tf.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
                [tf.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
            ]];
        }
        cell.textField.stringValue = [self tableView:tableView objectValueForTableColumn:tableColumn row:row] ?: @"";
        cell.textField.font = [NSFont systemFontOfSize:11];
        return cell;
    }

    return nil;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if (tableView == self.compareTable) {
        if (self.isSettingsComparison) {
            TXSettingsDiffItem *item = self.activeSettingsDiff.diffItems[row];
            if ([column.identifier isEqual:@"addr"]) {
                return [NSString stringWithFormat:@"%lu - %@", (unsigned long)item.address, item.settingName ?: @"Raw Byte"];
            }
            if ([column.identifier isEqual:@"valA"]) return [NSString stringWithFormat:@"%u (0x%02X)", item.valueA, item.valueA];
            if ([column.identifier isEqual:@"valB"]) return [NSString stringWithFormat:@"%u (0x%02X)", item.valueB, item.valueB];
            if ([column.identifier isEqual:@"diff"]) return item.changeDescription;
            return @"";
        } else {
            TXMemoryDiffItem *item = self.activeMemoryDiff.diffItems[row];
            if ([column.identifier isEqual:@"ch"]) return [NSString stringWithFormat:@"CH %02lu", (unsigned long)item.channelIndex];
            if ([column.identifier isEqual:@"valA"]) {
                if (!item.channelA.frequency) return @"Empty";
                return [NSString stringWithFormat:@"%u Hz (%@, %@)", item.channelA.frequency,
                    @{@49:@"LSB",@50:@"USB",@51:@"CW",@52:@"FM",@53:@"AM",@55:@"CWR"}[@(item.channelA.mode)] ?: @"—",
                    @[@"Off",@"PRE",@"ATT"][item.channelA.preAtt>='0' && item.channelA.preAtt<='2' ? item.channelA.preAtt-'0' : 0]];
            }
            if ([column.identifier isEqual:@"valB"]) {
                if (!item.channelB.frequency) return @"Empty";
                return [NSString stringWithFormat:@"%u Hz (%@, %@)", item.channelB.frequency,
                    @{@49:@"LSB",@50:@"USB",@51:@"CW",@52:@"FM",@53:@"AM",@55:@"CWR"}[@(item.channelB.mode)] ?: @"—",
                    @[@"Off",@"PRE",@"ATT"][item.channelB.preAtt>='0' && item.channelB.preAtt<='2' ? item.channelB.preAtt-'0' : 0]];
            }
            if ([column.identifier isEqual:@"diff"]) return item.statusText;
            return @"";
        }
    }

    if (tableView == self.settingsTable) {
        if (row < 0 || (NSUInteger)row >= self.filteredSettingsItems.count) return @"";
        TXSettingsItem *item = self.filteredSettingsItems[row];
        if ([column.identifier isEqual:@"category"]) return item.category ?: @"";
        if ([column.identifier isEqual:@"name"]) return item.name ?: @"";
        if ([column.identifier isEqual:@"address"]) return [NSString stringWithFormat:@"%lu", (unsigned long)item.address];
        if ([column.identifier isEqual:@"value"]) return [item displayValue] ?: @"";
        if ([column.identifier isEqual:@"unit"]) return item.unitOrRange ?: @"";
        if ([column.identifier isEqual:@"details"]) return item.details ?: @"";
        return @"";
    }

    TXMemoryChannel *c = self.channels[row];
    if ([column.identifier isEqual:@"channel"]) return [NSString stringWithFormat:@"%02ld", (long)row];
    if (!c.frequency) return [column.identifier isEqual:@"frequency"] ? @"Empty" : @"—";
    if ([column.identifier isEqual:@"frequency"]) return @(c.frequency);
    if ([column.identifier isEqual:@"mode"]) return @{@49:@"LSB", @50:@"USB", @51:@"CW", @52:@"FM", @53:@"AM", @55:@"CWR"}[@(c.mode)];
    return @[@"Off", @"PRE", @"ATT"][c.preAtt - '0'];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    if (notification.object == self.compareTable) return;
    if (notification.object == self.settingsTable) {
        NSInteger row = self.settingsTable.selectedRow;
        if (row < 0 || (NSUInteger)row >= self.filteredSettingsItems.count) {
            self.settingEditLabel.stringValue = @"Select a setting:";
            self.settingEditField.stringValue = @"";
            self.settingEditField.placeholderString = @"";
            self.settingApplyButton.enabled = NO;
            return;
        }
        TXSettingsItem *item = self.filteredSettingsItems[row];
        self.settingEditLabel.stringValue = [NSString stringWithFormat:@"%@:", item.name];
        if (item.dataType == TXSettingsTypeModeEnum) {
            self.settingEditField.stringValue = [item displayValue];
        } else if (item.dataType == TXSettingsTypeScaleTenths) {
            self.settingEditField.stringValue = [NSString stringWithFormat:@"%.1f", (double)item.numericValue / 10.0];
        } else {
            self.settingEditField.stringValue = [NSString stringWithFormat:@"%lld", item.numericValue];
        }
        self.settingEditField.placeholderString = item.unitOrRange ?: @"";
        self.settingApplyButton.enabled = !self.busy;
        return;
    }

    NSInteger row = self.table.selectedRow;
    if (row < 0 || (NSUInteger)row >= self.channels.count) return;
    TXMemoryChannel *c = self.channels[row];
    self.frequency.stringValue = (c.frequency ? [NSString stringWithFormat:@"%u", c.frequency] : @"");
    NSUInteger index = [@[@49, @50, @51, @52, @53, @55] indexOfObject:@(c.mode)];
    [self.mode selectItemAtIndex:(index == NSNotFound ? 1 : (NSInteger)index)];
    [self.preAtt selectItemAtIndex:(c.preAtt >= '0' && c.preAtt <= '2' ? c.preAtt - '0' : 0)];
}

#pragma mark - Settings Editor Actions

- (void)updateSettingsModelFromData {
    if (!self.settingsData || self.settingsData.length != 1024) {
        self.allSettingsItems = @[];
        self.filteredSettingsItems = @[];
        [self.settingsTable reloadData];
        return;
    }
    self.allSettingsItems = [TX500SettingsModel decodeSettings:self.settingsData];
    [self settingsCategoryFilterChanged:nil];
}

- (void)settingsCategoryFilterChanged:(id)sender {
    (void)sender;
    NSString *selected = self.settingsCategoryFilter.titleOfSelectedItem;
    if (!selected || [selected isEqualToString:@"All Categories"]) {
        self.filteredSettingsItems = self.allSettingsItems;
    } else {
        NSPredicate *pred = [NSPredicate predicateWithFormat:@"category == %@", selected];
        self.filteredSettingsItems = [self.allSettingsItems filteredArrayUsingPredicate:pred];
    }
    [self.settingsTable reloadData];
    if (self.filteredSettingsItems.count > 0) {
        [self.settingsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    }
    [self tableViewSelectionDidChange:[NSNotification notificationWithName:NSTableViewSelectionDidChangeNotification object:self.settingsTable]];
}

- (void)editSettingAction:(id)sender {
    (void)sender;
    NSInteger row = self.settingsTable.selectedRow;
    if (self.busy || !self.settingsData || row < 0 || (NSUInteger)row >= self.filteredSettingsItems.count) return;
    TXSettingsItem *item = self.filteredSettingsItems[row];
    NSError *err = nil;
    if (![item setValueFromString:self.settingEditField.stringValue error:&err]) {
        [self alert:@"Invalid Setting Value" message:err.localizedDescription];
        return;
    }
    self.settingsData = [TX500SettingsModel encodeSettings:self.allSettingsItems baseData:self.settingsData];
    self.settingsDirty = YES;
    [self.settingsTable reloadData];
    [self settingsDescription];
    [self refresh];
}

- (void)exportJsonSettingsAction:(id)sender {
    (void)sender;
    if (self.busy || !self.settingsData) return;
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"json" conformingToType:UTTypeJSON]];
    panel.nameFieldStringValue = @"TX-500-settings.json";
    panel.title = @"Export Settings to JSON";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response){
        if (response != NSModalResponseOK || !panel.URL) return;
        NSError *err = nil;
        NSString *json = [TX500SettingsModel exportJSONFromSettingsData:self.settingsData error:&err];
        if (!json) {
            [self alert:@"Export Failed" message:err.localizedDescription];
            return;
        }
        if (![json writeToURL:panel.URL atomically:YES encoding:NSUTF8StringEncoding error:&err]) {
            [self alert:@"Export Failed" message:err.localizedDescription];
            return;
        }
        if (self.log) self.log([NSString stringWithFormat:@"Exported settings description to JSON: %@", panel.URL.lastPathComponent]);
        [self alert:@"Settings Export Complete" message:[NSString stringWithFormat:@"Successfully exported described settings to %@.", panel.URL.lastPathComponent]];
    }];
}

- (void)importJsonSettingsAction:(id)sender {
    (void)sender;
    if (self.busy || ![self confirmReplacement:1]) return;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"json" conformingToType:UTTypeJSON]];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;
    panel.title = @"Import Settings from JSON";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response){
        if (response != NSModalResponseOK || !panel.URL) return;
        NSError *err = nil;
        NSString *json = [NSString stringWithContentsOfURL:panel.URL encoding:NSUTF8StringEncoding error:&err];
        if (!json) {
            [self alert:@"Cannot Read File" message:err.localizedDescription];
            return;
        }
        NSData *newData = [TX500SettingsModel importJSON:json baseData:self.settingsData error:&err];
        if (!newData) {
            [self alert:@"Import Failed" message:err.localizedDescription];
            return;
        }
        self.settingsData = newData;
        self.settingsSource = panel.URL.lastPathComponent;
        self.settingsDirty = YES;
        [self updateSettingsModelFromData];
        [self settingsDescription];
        [self refresh];
        if (self.log) self.log([NSString stringWithFormat:@"Imported settings from JSON: %@", panel.URL.lastPathComponent]);
    }];
}

- (void)editChannel:(NSButton *)sender {
    NSInteger row = self.table.selectedRow;
    if (self.busy || !self.memoryReady || row < 0) return;
    TXMemoryChannel *c = [TXMemoryChannel new];
    if (!sender.tag) {
        NSString *text = [self.frequency.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSCharacterSet *nonDigits = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet];
        long long value = text.longLongValue;
        if (!text.length || [text rangeOfCharacterFromSet:nonDigits].location != NSNotFound || value < 100000 || value > 56000000) {
            [self alert:@"Invalid frequency" message:@"Enter a whole frequency from 100000 to 56000000 Hz. Use Clear Row to empty a channel."];
            return;
        }
        c.frequency = (uint32_t)value;
        c.mode = (uint8_t)((NSNumber *)@[@49, @50, @51, @52, @53, @55, @50][self.mode.indexOfSelectedItem]).intValue;
        c.preAtt = (uint8_t)('0' + self.preAtt.indexOfSelectedItem);
    }
    self.channels[row] = c;
    self.memoryDirty = YES;
    [self.table reloadData];
    [self memoryDescription];
    [self tableViewSelectionDidChange:[NSNotification notificationWithName:NSTableViewSelectionDidChangeNotification object:self.table]];
}

#pragma mark - Radio Transfer (Settings & Memory)

- (void)readRadio:(NSButton *)sender {
    if (self.busy || !self.hasPorts || ![self confirmReplacement:sender.tag]) return;
    [self transfer:sender.tag writing:NO];
}

- (void)writeRadio:(NSButton *)sender {
    if (self.busy || !self.hasPorts) return;
    if (sender.tag == 1 && !self.settingsData) return;
    if (sender.tag == 2 && !self.memoryReady) return;
    NSString *port = self.selectedPort ? self.selectedPort() : nil;
    if (!port) return;
    NSString *detail = (sender.tag == 1 ?
        [NSString stringWithFormat:@"Restore all 1024 settings bytes from %@.\nSHA-256: %@", self.settingsSource ?: @"loaded settings", TXFirmwareSHA256(self.settingsData)] :
        [NSString stringWithFormat:@"%@\nAll 100 radio memory channels will be replaced, including empty rows. The original utility's fixed memory fields are used.", self.memoryInfo.stringValue]);
    if (![self confirm:@"Write this backup to the radio?"
               message:[NSString stringWithFormat:@"%@\n\nPort: %@\nKeep the radio powered on normally and the cable connected. The app will read back and check the result.", detail, port]
                button:@"Write and Verify"]) return;
    [self transfer:sender.tag writing:YES];
}

- (void)transfer:(NSInteger)kind writing:(BOOL)writing {
    NSString *port = self.selectedPort ? self.selectedPort() : nil;
    if (!port) return;
    NSData *settings = (writing && kind == 1 ? self.settingsData : nil);
    NSArray *channels = (writing && kind == 2 ? [[NSArray alloc] initWithArray:self.channels copyItems:YES] : nil);
    [self begin];
    Lab599Cancellation *token = self.token;
    NSString *name = (kind == 1 ? @"Settings" : @"Memory");
    if (self.log) self.log([NSString stringWithFormat:@"%@: %@ on %@ at 9600 baud.", name, writing ? @"write + verify" : @"read", port]);
    if (self.statusChanged) self.statusChanged(@"Opening radio connection…", 0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        TXConfigurationProgress progress = ^(NSString *phase, NSUInteger done, NSUInteger total){
            if (done != 1 && done != total && done % 8) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.statusChanged) {
                    self.statusChanged([NSString stringWithFormat:@"%@: %lu / %lu", phase, (unsigned long)done, (unsigned long)total], (double)done / total);
                }
            });
        };
        TXConfigurationResult *result = (kind == 1 ?
            TXSettingsTransfer(port, settings, TXDefaultConfigurationOptions(), token, progress) :
            TXMemoryTransfer(port, channels, TXDefaultConfigurationOptions(), token, progress));
        dispatch_async(dispatch_get_main_queue(), ^{
            [self end];
            if (result.success && !writing) {
                if (kind == 1) {
                    self.settingsData = result.settings;
                    self.settingsSource = @"Read from radio";
                    self.settingsDirty = YES;
                    [self updateSettingsModelFromData];
                    [self settingsDescription];
                } else {
                    self.channels = [result.channels mutableCopy];
                    self.memoryReady = YES;
                    self.memoryDirty = YES;
                    [self.table reloadData];
                    [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
                    [self memoryDescription];
                }
                if (kind == 2) {
                    [self tableViewSelectionDidChange:[NSNotification notificationWithName:NSTableViewSelectionDidChangeNotification object:self.table]];
                }
            }
            [self refresh];
            if (self.statusChanged) self.statusChanged(result.message, result.success ? 1 : 0);
            if (self.log) self.log([result.message stringByAppendingString:@" Serial port closed."]);
            if (!result.success && !result.cancelled) [self alert:@"Radio operation was not confirmed" message:result.message];
        });
    });
}

#pragma mark - CSV Import & Export (ورود/خروج CSV)

- (void)exportCSVAction:(id)sender {
    (void)sender;
    if (self.busy || !self.memoryReady) return;
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"csv" conformingToType:UTTypeText]];
    panel.nameFieldStringValue = @"TX-500-channels.csv";
    panel.title = @"Export Memory Channels to CSV";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response){
        if (response != NSModalResponseOK || !panel.URL) return;
        NSString *csv = TXExportMemoryToCSV(self.channels);
        NSError *writeError = nil;
        if (![csv writeToURL:panel.URL atomically:YES encoding:NSUTF8StringEncoding error:&writeError]) {
            [self alert:@"Export Failed" message:writeError.localizedDescription];
            return;
        }
        if (self.log) self.log([NSString stringWithFormat:@"Exported 100 channels to CSV: %@", panel.URL.lastPathComponent]);
        [self alert:@"CSV Export Complete" message:[NSString stringWithFormat:@"Successfully exported 100 memory channels to %@.", panel.URL.lastPathComponent]];
    }];
}

- (void)importCSVAction:(id)sender {
    (void)sender;
    if (self.busy || ![self confirmReplacement:2]) return;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"csv" conformingToType:UTTypeText]];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;
    panel.title = @"Import Memory Channels from CSV";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response){
        if (response != NSModalResponseOK || !panel.URL) return;
        NSError *readError = nil;
        NSString *csv = [NSString stringWithContentsOfURL:panel.URL encoding:NSUTF8StringEncoding error:&readError];
        if (!csv) {
            csv = [NSString stringWithContentsOfURL:panel.URL encoding:NSASCIIStringEncoding error:&readError];
        }
        if (!csv) {
            [self alert:@"Cannot Read CSV" message:readError.localizedDescription];
            return;
        }
        NSError *parseError = nil;
        NSArray<TXMemoryChannel *> *imported = TXImportMemoryFromCSV(csv, &parseError);
        if (!imported) {
            [self alert:@"CSV Parsing Failed" message:parseError.localizedDescription];
            return;
        }
        self.channels = [imported mutableCopy];
        self.memoryReady = YES;
        self.memoryDirty = YES;
        [self.table reloadData];
        [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        [self memoryDescription];
        [self tableViewSelectionDidChange:[NSNotification notificationWithName:NSTableViewSelectionDidChangeNotification object:self.table]];
        [self refresh];

        NSUInteger used = 0;
        for (TXMemoryChannel *ch in imported) if (ch.frequency > 0) used++;
        NSString *msg = [NSString stringWithFormat:@"Imported %lu active channels from %@ into the bank. Click 'Write 100 Channels…' to write them to your transceiver.", (unsigned long)used, panel.URL.lastPathComponent];
        if (self.log) self.log(msg);
        [self alert:@"CSV Import Successful" message:msg];
    }];
}

#pragma mark - Operating Profiles (پروفایل‌های کاری)

- (void)populateProfilesMenu {
    [self.profilesPopup removeAllItems];
    [self.profilesPopup addItemWithTitle:@"Select Operating Profile…"];

    NSMenuItem *header1 = [NSMenuItem new];
    header1.title = @"── Built-in Presets ──";
    header1.enabled = NO;
    [self.profilesPopup.menu addItem:header1];

    NSArray<TXOperatingProfile *> *builtIns = [TXProfileManager builtInProfiles];
    for (TXOperatingProfile *p in builtIns) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:p.name action:NULL keyEquivalent:@""];
        item.representedObject = p;
        [self.profilesPopup.menu addItem:item];
    }

    NSMenuItem *header2 = [NSMenuItem new];
    header2.title = @"── User Profiles ──";
    header2.enabled = NO;
    [self.profilesPopup.menu addItem:header2];

    NSMenuItem *saveItem = [[NSMenuItem alloc] initWithTitle:@"💾 Save Current Bank as Profile…" action:NULL keyEquivalent:@""];
    saveItem.tag = 999;
    [self.profilesPopup.menu addItem:saveItem];

    NSArray<TXOperatingProfile *> *userProfiles = [TXProfileManager userProfiles];
    for (TXOperatingProfile *p in userProfiles) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"👤 %@", p.name] action:NULL keyEquivalent:@""];
        item.representedObject = p;
        [self.profilesPopup.menu addItem:item];
    }
}

- (void)profileSelected:(NSPopUpButton *)sender {
    NSMenuItem *item = sender.selectedItem;
    [sender selectItemAtIndex:0]; // Reset popup to title

    if (item.tag == 999) {
        // Save current as profile
        if (!self.memoryReady) {
            [self alert:@"No Memory Loaded" message:@"Open or populate a memory bank before saving it as a profile."];
            return;
        }
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Save Operating Profile";
        alert.informativeText = @"Enter a name for this custom operating profile:";
        NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 240, 24)];
        input.placeholderString = @"e.g. Field Day 2026, QRP Summit";
        alert.accessoryView = input;
        [alert addButtonWithTitle:@"Save"];
        [alert addButtonWithTitle:@"Cancel"];
        if ([alert runModal] == NSAlertFirstButtonReturn) {
            NSString *name = [input.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (!name.length) return;
            NSError *err = nil;
            if ([TXProfileManager saveUserProfileNamed:name channels:self.channels error:&err]) {
                [self populateProfilesMenu];
                if (self.log) self.log([NSString stringWithFormat:@"Saved custom operating profile: %@", name]);
                [self alert:@"Profile Saved" message:[NSString stringWithFormat:@"Operating profile '%@' was saved successfully.", name]];
            } else {
                [self alert:@"Save Failed" message:err.localizedDescription];
            }
        }
        return;
    }

    TXOperatingProfile *profile = item.representedObject;
    if (!profile) return;

    if (![self confirmReplacement:2]) return;

    self.channels = [[NSArray alloc] initWithArray:profile.channels copyItems:YES].mutableCopy;
    self.memoryReady = YES;
    self.memoryDirty = YES;
    [self.table reloadData];
    [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [self memoryDescription];
    [self tableViewSelectionDidChange:[NSNotification notificationWithName:NSTableViewSelectionDidChangeNotification object:self.table]];
    [self refresh];

    NSUInteger used = 0;
    for (TXMemoryChannel *ch in self.channels) if (ch.frequency > 0) used++;
    NSString *msg = [NSString stringWithFormat:@"Applied Operating Profile '%@' (%lu channels active). %@", profile.name, (unsigned long)used, profile.details ?: @""];
    if (self.log) self.log(msg);
    [self alert:@"Profile Applied" message:[msg stringByAppendingString:@"\n\nClick 'Write 100 Channels…' to update your radio."]];
}

#pragma mark - Backup Comparison (مقایسهٔ پشتیبان‌ها)

- (void)compareSettingsAction:(id)sender {
    (void)sender;
    if (self.busy) return;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"set" conformingToType:UTTypeData]];
    panel.allowsMultipleSelection = (self.settingsData == nil); // If none loaded, pick 2
    panel.title = (self.settingsData ? @"Select a Second .set File to Compare" : @"Select Two .set Files to Compare (Command-click to select 2)");
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response){
        if (response != NSModalResponseOK || !panel.URLs.count) return;
        NSData *dataA = nil;
        NSData *dataB = nil;
        NSString *nameA = nil;
        NSString *nameB = nil;

        if (panel.URLs.count >= 2) {
            nameA = panel.URLs[0].lastPathComponent;
            nameB = panel.URLs[1].lastPathComponent;
            dataA = [NSData dataWithContentsOfURL:panel.URLs[0]];
            dataB = [NSData dataWithContentsOfURL:panel.URLs[1]];
        } else if (self.settingsData) {
            nameA = self.settingsSource ?: @"Active Radio Settings";
            nameB = panel.URL.lastPathComponent;
            dataA = self.settingsData;
            dataB = [NSData dataWithContentsOfURL:panel.URL];
        } else {
            [self alert:@"Comparison Requires Two Files" message:@"Select two .set files by holding Command, or open one backup first before comparing."];
            return;
        }

        if (dataA.length != 1024 || dataB.length != 1024) {
            [self alert:@"Invalid Settings Files" message:@"Both .set files must be exactly 1024 bytes."];
            return;
        }

        self.isSettingsComparison = YES;
        self.activeSettingsDiff = TXCompareSettings(dataA, dataB, nameA, nameB);
        [self showCompareSheetWithTitle:@"Settings Backup Comparison (.set)"
                                summary:self.activeSettingsDiff.summary];
    }];
}

- (void)compareMemoryAction:(id)sender {
    (void)sender;
    if (self.busy) return;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"mem" conformingToType:UTTypeData]];
    panel.allowsMultipleSelection = (!self.memoryReady);
    panel.title = (self.memoryReady ? @"Select a Second .mem File to Compare" : @"Select Two .mem Files to Compare (Command-click to select 2)");
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response){
        if (response != NSModalResponseOK || !panel.URLs.count) return;
        NSArray<TXMemoryChannel *> *bankA = nil;
        NSArray<TXMemoryChannel *> *bankB = nil;
        NSString *nameA = nil;
        NSString *nameB = nil;
        NSError *err = nil;

        if (panel.URLs.count >= 2) {
            nameA = panel.URLs[0].lastPathComponent;
            nameB = panel.URLs[1].lastPathComponent;
            NSData *dA = [NSData dataWithContentsOfURL:panel.URLs[0]];
            NSData *dB = [NSData dataWithContentsOfURL:panel.URLs[1]];
            bankA = TXDecodeMemory(dA, &err);
            bankB = TXDecodeMemory(dB, &err);
        } else if (self.memoryReady) {
            nameA = @"Active Channel Bank";
            nameB = panel.URL.lastPathComponent;
            bankA = self.channels;
            NSData *dB = [NSData dataWithContentsOfURL:panel.URL];
            bankB = TXDecodeMemory(dB, &err);
        } else {
            [self alert:@"Comparison Requires Two Files" message:@"Select two .mem files by holding Command, or open one backup first before comparing."];
            return;
        }

        if (!bankA || !bankB) {
            [self alert:@"Invalid Memory Files" message:@"Both .mem files must be exactly 600 bytes and conform to TX-500 memory format."];
            return;
        }

        self.isSettingsComparison = NO;
        self.activeMemoryDiff = TXCompareMemory(bankA, bankB, nameA, nameB);
        [self showCompareSheetWithTitle:@"Memory Backup Comparison (.mem)"
                                summary:self.activeMemoryDiff.summary];
    }];
}

- (void)showCompareSheetWithTitle:(NSString *)title summary:(NSString *)summary {
    if (!self.compareSheet) {
        self.compareSheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 760, 480)
            styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskResizable)
            backing:NSBackingStoreBuffered defer:NO];
        self.compareSheet.minSize = NSMakeSize(650, 400);

        NSTextField *header = [NSTextField labelWithString:title];
        header.font = [NSFont systemFontOfSize:16 weight:NSFontWeightSemibold];
        self.compareSummaryLabel = [NSTextField wrappingLabelWithString:summary];
        self.compareSummaryLabel.textColor = NSColor.labelColor;

        self.compareTable = [NSTableView new];
        self.compareTable.delegate = self;
        self.compareTable.dataSource = self;
        self.compareTable.rowHeight = 24;
        self.compareTable.usesAlternatingRowBackgroundColors = YES;

        NSArray *columns = @[
            @{@"id": @"addr", @"title": @"Item / Address", @"width": @230},
            @{@"id": @"valA", @"title": @"Backup A (Base)", @"width": @140},
            @{@"id": @"valB", @"title": @"Backup B (Compared)", @"width": @140},
            @{@"id": @"diff", @"title": @"Difference / Status", @"width": @170}
        ];
        for (NSDictionary *col in columns) {
            NSTableColumn *tc = [[NSTableColumn alloc] initWithIdentifier:col[@"id"]];
            tc.title = col[@"title"];
            tc.width = [col[@"width"] doubleValue];
            tc.editable = NO;
            [self.compareTable addTableColumn:tc];
        }

        NSScrollView *tableScroll = [NSScrollView new];
        tableScroll.hasVerticalScroller = YES;
        tableScroll.borderType = NSBezelBorder;
        tableScroll.documentView = self.compareTable;

        NSButton *closeBtn = [NSButton buttonWithTitle:@"Close Comparison" target:self action:@selector(closeCompareSheet:)];
        closeBtn.bezelStyle = NSBezelStyleRounded;
        closeBtn.keyEquivalent = @"\033"; // Escape

        NSStackView *stack = [NSStackView stackViewWithViews:@[header, self.compareSummaryLabel, tableScroll, closeBtn]];
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        stack.orientation = NSUserInterfaceLayoutOrientationVertical;
        stack.alignment = NSLayoutAttributeLeading;
        stack.spacing = 10;
        [self.compareSheet.contentView addSubview:stack];

        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:self.compareSheet.contentView.leadingAnchor constant:20],
            [stack.trailingAnchor constraintEqualToAnchor:self.compareSheet.contentView.trailingAnchor constant:-20],
            [stack.topAnchor constraintEqualToAnchor:self.compareSheet.contentView.topAnchor constant:20],
            [stack.bottomAnchor constraintEqualToAnchor:self.compareSheet.contentView.bottomAnchor constant:-20],
            [header.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
            [self.compareSummaryLabel.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
            [tableScroll.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
            [closeBtn.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor]
        ]];
    }

    self.compareSheet.title = title;
    self.compareSummaryLabel.stringValue = summary;
    [self.compareTable reloadData];
    [self.window beginSheet:self.compareSheet completionHandler:nil];
}

- (void)closeCompareSheet:(id)sender {
    (void)sender;
    [self.window endSheet:self.compareSheet];
    [self.compareSheet orderOut:nil];
}

@end
