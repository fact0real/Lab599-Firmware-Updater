#import "Lab599TelemetryController.h"

@interface Lab599TelemetryController ()

@property (nonatomic, strong) NSView *view;
@property (nonatomic, strong) TX500TelemetryEngine *engine;

// Gauges
@property (nonatomic, strong) TXGaugeView *powerGauge;
@property (nonatomic, strong) TXGaugeView *swrGauge;
@property (nonatomic, strong) TXGaugeView *voltGauge;
@property (nonatomic, strong) TXGaugeView *currentGauge;
@property (nonatomic, strong) TXGaugeView *tempGauge;

// Header displays
@property (nonatomic, strong) NSTextField *freqDisplay;
@property (nonatomic, strong) NSTextField *modeBadge;
@property (nonatomic, strong) NSTextField *txrxBadge;
@property (nonatomic, strong) NSLevelIndicator *sMeterBar;
@property (nonatomic, strong) NSTextField *sMeterLabel;
@property (nonatomic, strong) NSTextField *connStatusLabel;

// Controls
@property (nonatomic, strong) NSButton *toggleButton;
@property (nonatomic, strong) NSButton *demoCheckbox;
@property (nonatomic, strong) NSPopUpButton *ratePopup;

// Guard status pills
@property (nonatomic, strong) NSTextField *voltGuard;
@property (nonatomic, strong) NSTextField *swrGuard;
@property (nonatomic, strong) NSTextField *tempGuard;
@property (nonatomic, strong) NSSegmentedControl *avgSegment;

@end

@implementation Lab599TelemetryController

- (instancetype)init {
    if ((self = [super init])) {
        _engine = [TX500TelemetryEngine new];
        [self buildUI];
    }
    return self;
}

- (void)buildUI {
    self.view = [NSView new];
    self.view.translatesAutoresizingMaskIntoConstraints = NO;

    // 1. Radio Status Card (Top)
    NSView *statusCard = [NSView new];
    statusCard.translatesAutoresizingMaskIntoConstraints = NO;
    statusCard.wantsLayer = YES;
    statusCard.layer.cornerRadius = 8.0;
    statusCard.layer.borderWidth = 1.0;
    statusCard.layer.borderColor = [NSColor colorWithCalibratedWhite:0.5 alpha:0.25].CGColor;
    statusCard.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.5 alpha:0.08].CGColor;

    self.freqDisplay = [NSTextField labelWithString:@"14.074.000 MHz"];
    self.freqDisplay.font = [NSFont monospacedDigitSystemFontOfSize:20 weight:NSFontWeightHeavy];
    self.freqDisplay.textColor = [NSColor labelColor];

    self.modeBadge = [NSTextField labelWithString:@"DIG (FT8)"];
    self.modeBadge.font = [NSFont systemFontOfSize:11 weight:NSFontWeightBold];
    self.modeBadge.textColor = [NSColor systemBlueColor];

    self.txrxBadge = [NSTextField labelWithString:@"● RECEIVE"];
    self.txrxBadge.font = [NSFont systemFontOfSize:12 weight:NSFontWeightHeavy];
    self.txrxBadge.textColor = [NSColor systemGreenColor];

    // S-Meter
    self.sMeterLabel = [NSTextField labelWithString:@"S-Meter:"];
    self.sMeterLabel.font = [NSFont systemFontOfSize:10 weight:NSFontWeightMedium];
    self.sMeterLabel.textColor = [NSColor secondaryLabelColor];

    self.sMeterBar = [[NSLevelIndicator alloc] initWithFrame:NSZeroRect];
    self.sMeterBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.sMeterBar.levelIndicatorStyle = NSLevelIndicatorStyleContinuousCapacity;
    self.sMeterBar.minValue = 0;
    self.sMeterBar.maxValue = 30;
    self.sMeterBar.doubleValue = 12;
    self.sMeterBar.warningValue = 20;
    self.sMeterBar.criticalValue = 27;

    // Controls Row in Status Card
    self.toggleButton = [NSButton buttonWithTitle:@"Start Monitoring" target:self action:@selector(toggleMonitoring:)];
    self.toggleButton.bezelStyle = NSBezelStyleRounded;

    self.demoCheckbox = [NSButton checkboxWithTitle:@"Demo / Sim Mode" target:self action:@selector(demoToggled:)];
    self.demoCheckbox.state = NSControlStateValueOff;

    self.ratePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.ratePopup addItemsWithTitles:@[@"100 ms (Fast)", @"250 ms (Normal)", @"500 ms (Eco)"]];
    [self.ratePopup selectItemAtIndex:1];
    self.ratePopup.target = self;
    self.ratePopup.action = @selector(rateChanged:);

    NSStackView *freqStack = [NSStackView stackViewWithViews:@[self.freqDisplay, self.modeBadge, self.txrxBadge]];
    freqStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    freqStack.spacing = 10;
    freqStack.alignment = NSLayoutAttributeCenterY;

    NSStackView *smeterStack = [NSStackView stackViewWithViews:@[self.sMeterLabel, self.sMeterBar]];
    smeterStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    smeterStack.spacing = 6;
    smeterStack.alignment = NSLayoutAttributeCenterY;
    [self.sMeterBar.widthAnchor constraintEqualToConstant:140].active = YES;

    NSStackView *controlsStack = [NSStackView stackViewWithViews:@[smeterStack, self.ratePopup, self.demoCheckbox, self.toggleButton]];
    controlsStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    controlsStack.spacing = 12;
    controlsStack.alignment = NSLayoutAttributeCenterY;

    NSStackView *headerInner = [NSStackView stackViewWithViews:@[freqStack, controlsStack]];
    headerInner.translatesAutoresizingMaskIntoConstraints = NO;
    headerInner.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    headerInner.distribution = NSStackViewDistributionFill;
    headerInner.alignment = NSLayoutAttributeCenterY;
    [statusCard addSubview:headerInner];

    [NSLayoutConstraint activateConstraints:@[
        [headerInner.leadingAnchor constraintEqualToAnchor:statusCard.leadingAnchor constant:12],
        [headerInner.trailingAnchor constraintEqualToAnchor:statusCard.trailingAnchor constant:-12],
        [headerInner.topAnchor constraintEqualToAnchor:statusCard.topAnchor constant:8],
        [headerInner.bottomAnchor constraintEqualToAnchor:statusCard.bottomAnchor constant:-8],
    ]];

    // 2. Gauges Setup
    // Top Row: 2 Primary Gauges (Power, SWR)
    self.powerGauge = [[TXGaugeView alloc] initWithTitle:@"RF OUTPUT POWER" unit:@"W" min:0.0 max:12.0 format:@"%.1f"];
    self.powerGauge.greenStart = 0.0;
    self.powerGauge.greenEnd = 10.0;
    self.powerGauge.yellowStart = 10.0;
    self.powerGauge.yellowEnd = 11.0;
    self.powerGauge.redStart = 11.0;
    self.powerGauge.redEnd = 12.0;

    self.swrGauge = [[TXGaugeView alloc] initWithTitle:@"ANTENNA SWR" unit:@":1" min:1.0 max:5.0 format:@"%.2f"];
    self.swrGauge.greenStart = 1.0;
    self.swrGauge.greenEnd = 1.5;
    self.swrGauge.yellowStart = 1.5;
    self.swrGauge.yellowEnd = 2.5;
    self.swrGauge.redStart = 3.0;
    self.swrGauge.redEnd = 5.0;

    NSStackView *topGauges = [NSStackView stackViewWithViews:@[self.powerGauge, self.swrGauge]];
    topGauges.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    topGauges.distribution = NSStackViewDistributionFillEqually;
    topGauges.spacing = 14;
    [self.powerGauge.heightAnchor constraintEqualToConstant:172].active = YES;
    [self.swrGauge.heightAnchor constraintEqualToConstant:172].active = YES;

    // Bottom Row: 3 System Gauges (Voltage, Current, Temp)
    self.voltGauge = [[TXGaugeView alloc] initWithTitle:@"SUPPLY / BATTERY" unit:@"V" min:8.0 max:16.0 format:@"%.1f"];
    self.voltGauge.redStart = 15.0;
    self.voltGauge.redEnd = 16.0;
    self.voltGauge.yellowStart = 9.5;
    self.voltGauge.yellowEnd = 10.5;
    self.voltGauge.greenStart = 10.5;
    self.voltGauge.greenEnd = 14.8;
    self.voltGauge.currentValue = 13.8;

    self.currentGauge = [[TXGaugeView alloc] initWithTitle:@"CURRENT DRAIN" unit:@"A" min:0.0 max:4.0 format:@"%.2f"];
    self.currentGauge.greenStart = 0.0;
    self.currentGauge.greenEnd = 2.5;
    self.currentGauge.yellowStart = 2.5;
    self.currentGauge.yellowEnd = 3.2;
    self.currentGauge.redStart = 3.2;
    self.currentGauge.redEnd = 4.0;
    self.currentGauge.currentValue = 0.11;

    self.tempGauge = [[TXGaugeView alloc] initWithTitle:@"PA TEMPERATURE" unit:@"°C" min:10.0 max:80.0 format:@"%.1f"];
    self.tempGauge.greenStart = 10.0;
    self.tempGauge.greenEnd = 45.0;
    self.tempGauge.yellowStart = 45.0;
    self.tempGauge.yellowEnd = 58.0;
    self.tempGauge.redStart = 60.0;
    self.tempGauge.redEnd = 80.0;
    self.tempGauge.currentValue = 32.0;

    NSStackView *bottomGauges = [NSStackView stackViewWithViews:@[self.voltGauge, self.currentGauge, self.tempGauge]];
    bottomGauges.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    bottomGauges.distribution = NSStackViewDistributionFillEqually;
    bottomGauges.spacing = 14;
    [self.voltGauge.heightAnchor constraintEqualToConstant:172].active = YES;
    [self.currentGauge.heightAnchor constraintEqualToConstant:172].active = YES;
    [self.tempGauge.heightAnchor constraintEqualToConstant:172].active = YES;

    // 3. Safety Guard Banner & Multi-Interval Controls (Bottom)
    self.voltGuard = [NSTextField labelWithString:@"⚡ Voltage: Normal (<15V)"];
    self.voltGuard.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    self.voltGuard.textColor = [NSColor systemGreenColor];

    self.swrGuard = [NSTextField labelWithString:@"📶 SWR: Normal (<3.0)"];
    self.swrGuard.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    self.swrGuard.textColor = [NSColor systemGreenColor];

    self.tempGuard = [NSTextField labelWithString:@"🌡️ Thermal: Normal (<60°C)"];
    self.tempGuard.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    self.tempGuard.textColor = [NSColor systemGreenColor];

    NSTextField *avgLabel = [NSTextField labelWithString:@"Averages:"];
    avgLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    avgLabel.textColor = [NSColor secondaryLabelColor];

    self.avgSegment = [NSSegmentedControl segmentedControlWithLabels:@[@"All", @"5m", @"15m", @"30m", @"60m"]
                                                        trackingMode:NSSegmentSwitchTrackingSelectOne
                                                              target:self
                                                              action:@selector(avgIntervalChanged:)];
    self.avgSegment.selectedSegment = 0;
    self.avgSegment.controlSize = NSControlSizeSmall;

    NSButton *resetPeakBtn = [NSButton buttonWithTitle:@"Reset Peaks" target:self action:@selector(resetPeaks:)];
    resetPeakBtn.bezelStyle = NSBezelStyleInline;

    NSStackView *guardsStack = [NSStackView stackViewWithViews:@[self.voltGuard, self.swrGuard, self.tempGuard, avgLabel, self.avgSegment, resetPeakBtn]];
    guardsStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    guardsStack.spacing = 12;
    guardsStack.alignment = NSLayoutAttributeCenterY;

    self.connStatusLabel = [NSTextField labelWithString:@"Ready. Click 'Start Monitoring' or enable 'Demo / Sim Mode'."];
    self.connStatusLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
    self.connStatusLabel.textColor = [NSColor secondaryLabelColor];

    // Master Vertical Stack
    NSStackView *master = [NSStackView stackViewWithViews:@[statusCard, topGauges, bottomGauges, guardsStack, self.connStatusLabel]];
    master.translatesAutoresizingMaskIntoConstraints = NO;
    master.orientation = NSUserInterfaceLayoutOrientationVertical;
    master.spacing = 10;
    master.alignment = NSLayoutAttributeLeading;
    [self.view addSubview:master];

    [NSLayoutConstraint activateConstraints:@[
        [master.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [master.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [master.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:4],
        [master.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.bottomAnchor],
        [statusCard.widthAnchor constraintEqualToAnchor:master.widthAnchor],
        [topGauges.widthAnchor constraintEqualToAnchor:master.widthAnchor],
        [bottomGauges.widthAnchor constraintEqualToAnchor:master.widthAnchor]
    ]];
}

#pragma mark - Actions

- (void)toggleMonitoring:(id)sender {
    if (self.engine.isRunning) {
        [self stopMonitoring];
    } else {
        [self startMonitoring];
    }
}

- (void)startDemoMonitoring {
    self.demoCheckbox.state = NSControlStateValueOn;
    self.engine.demoMode = YES;
    [self startMonitoring];
}

- (void)startMonitoring {
    NSString *port = self.selectedPortProvider ? self.selectedPortProvider() : nil;
    if (!self.demoCheckbox.state && !port) {
        self.connStatusLabel.stringValue = @"No serial port selected. Select a CAT port above or enable Demo Mode.";
        return;
    }

    NSTimeInterval interval = 0.25;
    if (self.ratePopup.indexOfSelectedItem == 0) interval = 0.10;
    else if (self.ratePopup.indexOfSelectedItem == 2) interval = 0.50;

    self.engine.demoMode = (self.demoCheckbox.state == NSControlStateValueOn);
    self.toggleButton.title = @"Stop Monitoring";

    __weak typeof(self) weakSelf = self;
    [self.engine startWithPort:port interval:interval update:^(TXTelemetryData * _Nonnull data) {
        [weakSelf applyTelemetryData:data];
    } status:^(NSString * _Nonnull status, BOOL isConnected) {
        weakSelf.connStatusLabel.stringValue = status;
        weakSelf.connStatusLabel.textColor = isConnected ? [NSColor labelColor] : [NSColor systemRedColor];
    }];

    if (self.logHandler) {
        self.logHandler([NSString stringWithFormat:@"Live telemetry monitoring started (%@, %.0f ms interval).",
                         self.engine.demoMode ? @"Demo Mode" : (port ?: @"Direct"), interval * 1000.0]);
    }
}

- (void)stopMonitoring {
    [self.engine stop];
    self.toggleButton.title = @"Start Monitoring";
    self.connStatusLabel.stringValue = @"Telemetry monitoring stopped.";
    if (self.logHandler) {
        self.logHandler(@"Live telemetry monitoring stopped.");
    }
}

- (void)demoToggled:(id)sender {
    if (self.engine.isRunning) {
        // Restart with new demo mode setting
        [self startMonitoring];
    }
}

- (void)rateChanged:(id)sender {
    if (self.engine.isRunning) {
        [self startMonitoring];
    }
}

- (void)resetPeaks:(id)sender {
    [self.powerGauge resetPeak];
    [self.swrGauge resetPeak];
    [self.voltGauge resetPeak];
    [self.currentGauge resetPeak];
    [self.tempGauge resetPeak];
}

- (void)avgIntervalChanged:(NSSegmentedControl *)sender {
    NSInteger sel = sender.selectedSegment;
    // 0 = All (-1), 1 = 5m (0), 2 = 15m (1), 3 = 30m (2), 4 = 60m (3)
    NSInteger windowIndex = sel - 1;
    self.powerGauge.selectedAvgWindow = windowIndex;
    self.swrGauge.selectedAvgWindow = windowIndex;
    self.voltGauge.selectedAvgWindow = windowIndex;
    self.currentGauge.selectedAvgWindow = windowIndex;
    self.tempGauge.selectedAvgWindow = windowIndex;
    [self.powerGauge setNeedsDisplay:YES];
    [self.swrGauge setNeedsDisplay:YES];
    [self.voltGauge setNeedsDisplay:YES];
    [self.currentGauge setNeedsDisplay:YES];
    [self.tempGauge setNeedsDisplay:YES];
}

#pragma mark - Live Update Dispatch

- (void)applyTelemetryData:(TXTelemetryData *)d {
    // Frequency
    if (d.frequencyHz > 0) {
        double mhz = (double)d.frequencyHz / 1000000.0;
        self.freqDisplay.stringValue = [NSString stringWithFormat:@"%.3f MHz", mhz];
    }

    // Mode
    if (d.operatingMode.length > 0) {
        self.modeBadge.stringValue = [NSString stringWithFormat:@"[ %@ ]", d.operatingMode];
    }

    // TX / RX State
    if (d.isTransmitting) {
        self.txrxBadge.stringValue = @"● TRANSMITTING";
        self.txrxBadge.textColor = [NSColor systemRedColor];
    } else {
        self.txrxBadge.stringValue = @"● RECEIVING";
        self.txrxBadge.textColor = [NSColor systemGreenColor];
    }

    // S-Meter
    self.sMeterBar.doubleValue = d.sMeterDots;

    // Update Gauges
    [self.powerGauge setValue:d.rfPowerWatts animated:YES];
    [self.swrGauge setValue:d.swr animated:YES];
    [self.voltGauge setValue:d.voltage animated:YES];
    [self.currentGauge setValue:d.currentAmps animated:YES];
    [self.tempGauge setValue:d.temperatureCelsius animated:YES];

    // Update Multi-Interval Rolling Averages (5m, 15m, 30m, 60m)
    if (d.rfPowerAverages && d.rfPowerAverages.hasData) {
        [self.powerGauge setAverages5m:d.rfPowerAverages.avg5m
                                   m15:d.rfPowerAverages.avg15m
                                   m30:d.rfPowerAverages.avg30m
                                   m60:d.rfPowerAverages.avg60m];
    }
    if (d.swrAverages && d.swrAverages.hasData) {
        [self.swrGauge setAverages5m:d.swrAverages.avg5m
                                 m15:d.swrAverages.avg15m
                                 m30:d.swrAverages.avg30m
                                 m60:d.swrAverages.avg60m];
    }
    if (d.voltageAverages && d.voltageAverages.hasData) {
        [self.voltGauge setAverages5m:d.voltageAverages.avg5m
                                  m15:d.voltageAverages.avg15m
                                  m30:d.voltageAverages.avg30m
                                  m60:d.voltageAverages.avg60m];
    }
    if (d.currentAverages && d.currentAverages.hasData) {
        [self.currentGauge setAverages5m:d.currentAverages.avg5m
                                     m15:d.currentAverages.avg15m
                                     m30:d.currentAverages.avg30m
                                     m60:d.currentAverages.avg60m];
    }
    if (d.temperatureAverages && d.temperatureAverages.hasData) {
        [self.tempGauge setAverages5m:d.temperatureAverages.avg5m
                                  m15:d.temperatureAverages.avg15m
                                  m30:d.temperatureAverages.avg30m
                                  m60:d.temperatureAverages.avg60m];
    }

    // Alerts on Gauges
    self.voltGauge.isAlertActive = d.overvoltageAlert || d.lowVoltageAlert;
    self.voltGauge.alertText = d.overvoltageAlert ? @"OVERVOLTAGE >15V" : (d.lowVoltageAlert ? @"LOW BATTERY" : nil);

    self.swrGauge.isAlertActive = d.highSWRAlert;
    self.swrGauge.alertText = d.highSWRAlert ? @"HIGH SWR ≥ 3.0" : nil;

    self.tempGauge.isAlertActive = d.overtempAlert;
    self.tempGauge.alertText = d.overtempAlert ? @"PA OVERHEAT >60°C" : nil;

    if (self.onTelemetryData) {
        self.onTelemetryData(d);
    }

    // Bottom Safety Pills
    if (d.overvoltageAlert) {
        self.voltGuard.stringValue = @"⚠️ OVERVOLTAGE ALERT (>15.0V)!";
        self.voltGuard.textColor = [NSColor systemRedColor];
    } else if (d.isBatteryPackPowered) {
        self.voltGuard.stringValue = [NSString stringWithFormat:@"🔋 BP-500/550 Pack: %.1fV (%ld%%) • Hold PWR during update", d.voltage, (long)d.batteryPercent];
        self.voltGuard.textColor = [NSColor systemOrangeColor];
    } else if (d.isExternalDCPowered) {
        self.voltGuard.stringValue = [NSString stringWithFormat:@"⚡ External PSU: %.1fV • Safe for update", d.voltage];
        self.voltGuard.textColor = [NSColor systemGreenColor];
    } else {
        self.voltGuard.stringValue = [NSString stringWithFormat:@"⚡ Voltage Guard: OK (%.1fV • %ld%%)", d.voltage, (long)d.batteryPercent];
        self.voltGuard.textColor = [NSColor systemGreenColor];
    }

    if (d.highSWRAlert) {
        self.swrGuard.stringValue = @"⚠️ HIGH SWR PROTECT: Power Throttled";
        self.swrGuard.textColor = [NSColor systemRedColor];
    } else {
        self.swrGuard.stringValue = [NSString stringWithFormat:@"📶 SWR Guard: OK (%.2f:1)", d.swr];
        self.swrGuard.textColor = [NSColor systemGreenColor];
    }

    if (d.overtempAlert) {
        self.tempGuard.stringValue = @"⚠️ THERMAL INHIBIT: PA HOT (>60°C)";
        self.tempGuard.textColor = [NSColor systemRedColor];
    } else {
        self.tempGuard.stringValue = [NSString stringWithFormat:@"🌡️ Thermal Guard: OK (%.1f°C)", d.temperatureCelsius];
        self.tempGuard.textColor = [NSColor systemGreenColor];
    }
}

@end
