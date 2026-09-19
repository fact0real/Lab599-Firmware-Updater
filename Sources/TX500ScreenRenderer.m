#import "TX500ScreenRenderer.h"
#import <math.h>

@implementation TX500ScreenRenderer

+ (NSSize)nativeLCDSize {
    return NSMakeSize(256.0, 128.0);
}

+ (NSSize)nativeChassisSize {
    return NSMakeSize(840.0, 440.0);
}

+ (NSColor *)backgroundColorForTheme:(TX500ScreenTheme)theme {
    switch (theme) {
        case TX500ScreenThemeAmber:
            return [NSColor colorWithCalibratedRed:0.09 green:0.05 blue:0.00 alpha:1.0]; // Warm amber-black
        case TX500ScreenThemeCoolWhite:
            return [NSColor colorWithCalibratedRed:0.83 green:0.87 blue:0.84 alpha:1.0]; // Transflective daylight grey-green as in real photo
        case TX500ScreenThemeGreen:
            return [NSColor colorWithCalibratedRed:0.03 green:0.09 blue:0.03 alpha:1.0]; // Tactical dark green
        case TX500ScreenThemeOLED:
            return [NSColor blackColor];
    }
}

+ (NSColor *)pixelOnColorForTheme:(TX500ScreenTheme)theme {
    switch (theme) {
        case TX500ScreenThemeAmber:
            return [NSColor colorWithCalibratedRed:1.00 green:0.62 blue:0.00 alpha:1.0]; // Vibrant amber #FFA000
        case TX500ScreenThemeCoolWhite:
            return [NSColor colorWithCalibratedRed:0.10 green:0.12 blue:0.11 alpha:1.0]; // Deep crisp LCD black as in real photo
        case TX500ScreenThemeGreen:
            return [NSColor colorWithCalibratedRed:0.25 green:1.00 blue:0.30 alpha:1.0]; // Phosphor emerald green
        case TX500ScreenThemeOLED:
            return [NSColor whiteColor];
    }
}

+ (NSColor *)pixelOffColorForTheme:(TX500ScreenTheme)theme {
    switch (theme) {
        case TX500ScreenThemeAmber:
            return [NSColor colorWithCalibratedRed:0.22 green:0.13 blue:0.00 alpha:0.35];
        case TX500ScreenThemeCoolWhite:
            return [NSColor colorWithCalibratedRed:0.75 green:0.80 blue:0.76 alpha:0.40];
        case TX500ScreenThemeGreen:
            return [NSColor colorWithCalibratedRed:0.08 green:0.22 blue:0.08 alpha:0.35];
        case TX500ScreenThemeOLED:
            return [NSColor colorWithCalibratedWhite:0.12 alpha:0.30];
    }
}

#pragma mark - Primary Screen Rendering (256x128)

+ (NSImage *)renderScreenImageWithState:(TX500ScreenState *)state
                                  theme:(TX500ScreenTheme)theme
                                  scale:(CGFloat)scale
                              pixelGrid:(BOOL)pixelGrid {
    if (scale <= 0.1) scale = 2.0;

    NSSize nativeSize = [self nativeLCDSize];
    NSSize scaledSize = NSMakeSize(nativeSize.width * scale, nativeSize.height * scale);

    NSImage *image = [[NSImage alloc] initWithSize:scaledSize];
    [image lockFocus];

    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    CGContextSaveGState(ctx);

    // Scale context to draw directly in native 256 x 128 pixel coordinates
    CGContextScaleCTM(ctx, scale, scale);

    NSColor *bgColor = [self backgroundColorForTheme:theme];
    NSColor *fgColor = [self pixelOnColorForTheme:theme];
    NSColor *dimColor = [self pixelOffColorForTheme:theme];

    // Background fill
    [bgColor setFill];
    NSRectFill(NSMakeRect(0, 0, nativeSize.width, nativeSize.height));

    // Outer pixel-perfect 1px border
    [dimColor setStroke];
    NSBezierPath *border = [NSBezierPath bezierPathWithRect:NSMakeRect(0.5, 0.5, nativeSize.width - 1.0, nativeSize.height - 1.0)];
    [border setLineWidth:1.0];
    [border stroke];

    // --- Section 1: Top Soft-Key Menu Bar (Aligned with 4 top physical buttons) ---
    [self drawTopMenuBarInContext:ctx state:state fg:fgColor bg:bgColor dim:dimColor];

    // --- Section 2: Sub-Header Status Row (RX/TX, AGC, Voltage, Clock) ---
    [self drawSubHeaderStatusInContext:ctx state:state fg:fgColor bg:bgColor dim:dimColor];

    // --- Section 3: VFO-A Main Frequency & Indicators (24.889.30₀, DIG, FIL-1, AF64, RF0) ---
    [self drawVFOAInContext:ctx state:state fg:fgColor bg:bgColor dim:dimColor];

    // --- Section 4: VFO-B Secondary Frequency & Mode (10 100 000, CWR) ---
    [self drawVFOBInContext:ctx state:state fg:fgColor bg:bgColor dim:dimColor];

    // --- Section 5: S-Meter / RF Power Bar (S 1..3..5..7..9.20.40.60) ---
    [self drawSMeterInContext:ctx state:state fg:fgColor bg:bgColor dim:dimColor];

    // --- Section 6: Panadapter Spectrum (Filled Solid Bars + Passband Brackets) ---
    [self drawPanadapterInContext:ctx state:state fg:fgColor bg:bgColor dim:dimColor];

    // --- Section 7: Bottom Soft-Key Menu Bar (Aligned with 4 bottom physical buttons) ---
    [self drawBottomMenuBarInContext:ctx state:state fg:fgColor bg:bgColor dim:dimColor];

    CGContextRestoreGState(ctx);

    // Optional LCD Matrix Pixel Grid Overlay
    if (pixelGrid && scale >= 2.0) {
        CGContextSetBlendMode(ctx, kCGBlendModeNormal);
        [[NSColor colorWithCalibratedWhite:0.0 alpha:theme == TX500ScreenThemeCoolWhite ? 0.15 : 0.28] setStroke];
        CGContextSetLineWidth(ctx, 1.0);

        for (CGFloat x = 0; x < scaledSize.width; x += scale) {
            CGContextMoveToPoint(ctx, x + 0.5, 0);
            CGContextAddLineToPoint(ctx, x + 0.5, scaledSize.height);
        }
        for (CGFloat y = 0; y < scaledSize.height; y += scale) {
            CGContextMoveToPoint(ctx, 0, y + 0.5);
            CGContextAddLineToPoint(ctx, scaledSize.width, y + 0.5);
        }
        CGContextStrokePath(ctx);
    }

    [image unlockFocus];
    return image;
}

#pragma mark - Detailed Screen Sections (256x128 space, origin bottom-left)

// 1. Top Soft-Key Menu Bar (y: 116 to 127)
+ (void)drawTopMenuBarInContext:(CGContextRef)ctx
                          state:(TX500ScreenState *)state
                             fg:(NSColor *)fg
                             bg:(NSColor *)bg
                            dim:(NSColor *)dim {
    (void)ctx; (void)dim;
    // Four columns for 4 physical buttons on top of LCD
    NSArray *labels = state.topSoftKeyLabels ?: @[@"CWSPEED", @"CWPITCH", @"POWER", @"VOX"];
    CGFloat colW = 58.0;
    CGFloat startX = 6.0;
    CGFloat y = 117.0;
    CGFloat h = 9.5;

    NSFont *font = [NSFont monospacedSystemFontOfSize:7.2 weight:NSFontWeightBold];
    NSDictionary *invAttrs = @{NSFontAttributeName: font, NSForegroundColorAttributeName: bg};

    for (NSUInteger i = 0; i < 4; i++) {
        NSString *lbl = i < labels.count ? labels[i] : @"";
        if (!lbl.length) continue;

        CGFloat x = startX + (i * (colW + 4.0));
        NSRect btnRect = NSMakeRect(x, y, colW, h);

        // Inverted black/amber badge for active soft-keys
        [fg setFill];
        NSRectFill(btnRect);

        NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
        style.alignment = NSTextAlignmentCenter;
        NSMutableDictionary *dict = [invAttrs mutableCopy];
        dict[NSParagraphStyleAttributeName] = style;

        [lbl drawInRect:NSMakeRect(x, y - 0.5, colW, h) withAttributes:dict];
    }
}

// 2. Sub-Header Status Row (y: 104 to 115)
+ (void)drawSubHeaderStatusInContext:(CGContextRef)ctx
                               state:(TX500ScreenState *)state
                                  fg:(NSColor *)fg
                                  bg:(NSColor *)bg
                                 dim:(NSColor *)dim {
    (void)ctx; (void)dim;
    CGFloat y = 104.5;

    // RX / TX Indicator
    if (state.isTransmitting) {
        NSRect txRect = NSMakeRect(6.0, y, 20.0, 10.0);
        [[NSColor colorWithCalibratedRed:0.90 green:0.15 blue:0.15 alpha:1.0] setFill];
        NSRectFill(txRect);
        NSDictionary *txAttrs = @{
            NSFontAttributeName: [NSFont monospacedSystemFontOfSize:7.5 weight:NSFontWeightBlack],
            NSForegroundColorAttributeName: [NSColor whiteColor]
        };
        [@"TX" drawAtPoint:NSMakePoint(8.5, y) withAttributes:txAttrs];
    } else {
        NSDictionary *rxAttrs = @{
            NSFontAttributeName: [NSFont monospacedSystemFontOfSize:8.0 weight:NSFontWeightBold],
            NSForegroundColorAttributeName: fg
        };
        [@"RX" drawAtPoint:NSMakePoint(6.0, y) withAttributes:rxAttrs];
    }

    // AGC Mode & Value (e.g. "AGC 10")
    NSString *agcStr = [NSString stringWithFormat:@"AGC %ld", (long)(state.agcDelay > 0 ? state.agcDelay : 10)];
    NSDictionary *subAttrs = @{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:7.5 weight:NSFontWeightBold],
        NSForegroundColorAttributeName: fg
    };
    [agcStr drawAtPoint:NSMakePoint(76.0, y) withAttributes:subAttrs];

    // Power setting value (e.g. "100" or "10") under POWER soft-key
    NSString *pwrVal = @"100";
    if (state.topSoftKeyValues.count > 2 && state.topSoftKeyValues[2].length) {
        pwrVal = state.topSoftKeyValues[2];
    }
    [pwrVal drawAtPoint:NSMakePoint(146.0, y) withAttributes:subAttrs];

    // Voltage (e.g. "12.0V")
    NSString *vStr = [NSString stringWithFormat:@"%.1fV", state.supplyVoltage > 0 ? state.supplyVoltage : 12.0];
    [vStr drawAtPoint:NSMakePoint(184.0, y) withAttributes:subAttrs];

    // Clock Time (e.g. "18:32")
    NSString *clk = state.clockString ?: @"18:32";
    if (clk.length > 5 && [clk containsString:@" "]) {
        clk = [clk componentsSeparatedByString:@" "].firstObject;
    }
    if (clk.length > 5) clk = [clk substringToIndex:5];
    [clk drawAtPoint:NSMakePoint(220.0, y) withAttributes:subAttrs];
}

// 3. VFO-A Main Frequency & Mode / Filter Badges (y: 76 to 102)
+ (void)drawVFOAInContext:(CGContextRef)ctx
                    state:(TX500ScreenState *)state
                       fg:(NSColor *)fg
                       bg:(NSColor *)bg
                      dim:(NSColor *)dim {
    (void)ctx; (void)dim;
    // Letter 'A' designation on left
    NSDictionary *tagAttrs = @{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:11.0 weight:NSFontWeightBlack],
        NSForegroundColorAttributeName: fg
    };
    [@"A" drawAtPoint:NSMakePoint(6.0, 84.0) withAttributes:tagAttrs];

    // Format Frequency: 24,889,300 -> "24.889.30" with sub-Hz "0"
    uint64_t f = state.frequencyHz > 0 ? state.frequencyHz : 24889300;
    uint64_t mhz = f / 1000000;
    uint64_t khz = (f % 1000000) / 1000;
    uint64_t tens = (f % 1000) / 10;
    uint64_t ones = f % 10;

    NSString *mainDigits = [NSString stringWithFormat:@"%llu.%03llu.%02llu", mhz, khz, tens];

    // Large authentic digital typography for primary frequency
    NSFont *freqFont = [NSFont monospacedSystemFontOfSize:21.0 weight:NSFontWeightBold];
    NSDictionary *freqAttrs = @{
        NSFontAttributeName: freqFont,
        NSForegroundColorAttributeName: fg
    };
    [mainDigits drawAtPoint:NSMakePoint(24.0, 77.0) withAttributes:freqAttrs];

    // Sub-Hz digit in subscript rectangular box: "₀" as on real radio screen
    CGFloat subX = 141.0;
    CGFloat subY = 80.0;
    NSRect subBox = NSMakeRect(subX, subY, 7.5, 9.5);
    [fg setStroke];
    NSBezierPath *p = [NSBezierPath bezierPathWithRect:subBox];
    [p setLineWidth:1.0];
    [p stroke];

    NSDictionary *subAttrs = @{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:6.5 weight:NSFontWeightBold],
        NSForegroundColorAttributeName: fg
    };
    NSString *subStr = [NSString stringWithFormat:@"%llu", ones];
    [subStr drawAtPoint:NSMakePoint(subX + 1.2, subY + 0.5) withAttributes:subAttrs];

    // Mode Inverted Badge: [ DIG ]
    NSString *mode = state.operatingMode ?: @"DIG";
    if ([mode isEqualToString:@"USB"] || [mode isEqualToString:@"FSK"] || [mode isEqualToString:@"DIGITAL"]) {
        mode = @"DIG";
    }
    NSRect modeRect = NSMakeRect(152.0, 80.0, 24.0, 13.0);
    [fg setFill];
    NSRectFill(modeRect);

    NSMutableParagraphStyle *modeStyle = [NSMutableParagraphStyle new];
    modeStyle.alignment = NSTextAlignmentCenter;
    NSDictionary *modeAttrs = @{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:8.0 weight:NSFontWeightBlack],
        NSForegroundColorAttributeName: bg,
        NSParagraphStyleAttributeName: modeStyle
    };
    [mode drawInRect:NSMakeRect(152.0, 80.5, 24.0, 12.0) withAttributes:modeAttrs];

    // Filter Badges: FIL-1 and 3.10k
    NSString *filName = state.filterName ?: @"FIL-1";
    NSString *filBw = state.filterBandwidthString ?: @"3.10k";
    NSDictionary *paramAttrs = @{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:7.5 weight:NSFontWeightBold],
        NSForegroundColorAttributeName: fg
    };
    [filName drawAtPoint:NSMakePoint(180.0, 88.0) withAttributes:paramAttrs];
    [filBw drawAtPoint:NSMakePoint(180.0, 78.0) withAttributes:paramAttrs];

    // AF Gain & RF Gain Badges: AF64 and RF0
    NSString *afStr = [NSString stringWithFormat:@"AF%ld", (long)(state.afGainLevel > 0 ? state.afGainLevel : 64)];
    NSString *rfStr = [NSString stringWithFormat:@"RF%ld", (long)state.rfGainLevel];
    [afStr drawAtPoint:NSMakePoint(216.0, 88.0) withAttributes:paramAttrs];
    [rfStr drawAtPoint:NSMakePoint(216.0, 78.0) withAttributes:paramAttrs];
}

// 4. VFO-B Secondary Frequency & Mode (y: 62 to 74)
+ (void)drawVFOBInContext:(CGContextRef)ctx
                    state:(TX500ScreenState *)state
                       fg:(NSColor *)fg
                       bg:(NSColor *)bg
                      dim:(NSColor *)dim {
    (void)ctx; (void)bg; (void)dim;
    NSDictionary *tagAttrs = @{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:8.5 weight:NSFontWeightBold],
        NSForegroundColorAttributeName: fg
    };
    [@"B" drawAtPoint:NSMakePoint(6.0, 63.5) withAttributes:tagAttrs];

    uint64_t fb = state.vfoBFrequencyHz > 0 ? state.vfoBFrequencyHz : 10100000;
    uint64_t mhz = fb / 1000000;
    uint64_t khz = (fb % 1000000) / 1000;
    uint64_t hz = fb % 1000;

    // In the photo: "10 100 000" spaced format
    NSString *vfoBStr = [NSString stringWithFormat:@"%llu %03llu %03llu", mhz, khz, hz];
    NSDictionary *vfoBAttrs = @{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:10.5 weight:NSFontWeightBold],
        NSForegroundColorAttributeName: fg
    };
    [vfoBStr drawAtPoint:NSMakePoint(24.0, 62.0) withAttributes:vfoBAttrs];

    // VFO-B Mode: CWR or USB
    NSString *vfoBMode = state.vfoBMode ?: @"CWR";
    NSDictionary *bModeAttrs = @{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:8.5 weight:NSFontWeightBlack],
        NSForegroundColorAttributeName: fg
    };
    [vfoBMode drawAtPoint:NSMakePoint(118.0, 63.5) withAttributes:bModeAttrs];
}

// 5. S-Meter Calibration Scale & Segment Dots (y: 48 to 61)
+ (void)drawSMeterInContext:(CGContextRef)ctx
                      state:(TX500ScreenState *)state
                         fg:(NSColor *)fg
                         bg:(NSColor *)bg
                        dim:(NSColor *)dim {
    (void)ctx; (void)bg;
    // Letter 'S' indicator
    NSDictionary *sAttrs = @{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:8.5 weight:NSFontWeightBold],
        NSForegroundColorAttributeName: fg
    };
    [@"S" drawAtPoint:NSMakePoint(6.0, 50.0) withAttributes:sAttrs];

    if (!state.isTransmitting) {
        // RX Mode S-Meter: "1 . . 3 . . 5 . . 7 . . 9 . 20 . 40 . 60"
        NSString *scaleText = @"1 . . 3 . . 5 . . 7 . . 9 . 20 . 40 . 60";
        NSDictionary *scaleAttrs = @{
            NSFontAttributeName: [NSFont monospacedSystemFontOfSize:6.5 weight:NSFontWeightMedium],
            NSForegroundColorAttributeName: fg
        };
        [scaleText drawAtPoint:NSMakePoint(22.0, 54.5) withAttributes:scaleAttrs];

        // 30 discrete meter dot segments
        NSInteger activeDots = state.sMeterDots;
        if (activeDots < 0) activeDots = 0;
        if (activeDots > 30) activeDots = 30;

        CGFloat barX = 22.0;
        CGFloat barY = 49.0;
        for (NSInteger i = 0; i < 30; i++) {
            NSRect dot = NSMakeRect(barX + (i * 3.8), barY, 2.4, 3.5);
            if (i < activeDots) {
                [fg setFill];
            } else {
                [dim setFill];
            }
            NSRectFill(dot);
        }
    } else {
        // TX Mode: RF Power (PO) and SWR Meters
        NSDictionary *txScaleAttrs = @{
            NSFontAttributeName: [NSFont monospacedSystemFontOfSize:6.5 weight:NSFontWeightBold],
            NSForegroundColorAttributeName: fg
        };
        [@"PO   0 . 2 . 4 . 6 . 8 . 10W" drawAtPoint:NSMakePoint(22.0, 54.5) withAttributes:txScaleAttrs];

        NSInteger pwrDots = (NSInteger)((state.rfPowerWatts / 10.0) * 28.0);
        if (pwrDots < 1) pwrDots = 1;
        if (pwrDots > 30) pwrDots = 30;

        CGFloat barX = 22.0;
        CGFloat barY = 49.0;
        for (NSInteger i = 0; i < 30; i++) {
            NSRect dot = NSMakeRect(barX + (i * 3.8), barY, 2.4, 3.5);
            if (i < pwrDots) {
                [fg setFill];
            } else {
                [dim setFill];
            }
            NSRectFill(dot);
        }
    }
}

// 6. Panadapter Spectrum: Solid Filled Bars + Passband Brackets (y: 16 to 46)
+ (void)drawPanadapterInContext:(CGContextRef)ctx
                          state:(TX500ScreenState *)state
                             fg:(NSColor *)fg
                             bg:(NSColor *)bg
                            dim:(NSColor *)dim {
    (void)bg;
    CGFloat startX = 10.0;
    CGFloat endX = 246.0;
    CGFloat baselineY = 17.0;
    CGFloat maxH = 26.0;

    // Baseline axis
    [fg setStroke];
    CGContextSetLineWidth(ctx, 1.0);
    CGContextMoveToPoint(ctx, startX, baselineY);
    CGContextAddLineToPoint(ctx, endX, baselineY);
    CGContextStrokePath(ctx);

    // Filter passband brackets [       ] on the baseline
    CGFloat pbLeft = 94.0;
    CGFloat pbRight = 162.0;

    // Left bracket '['
    CGContextMoveToPoint(ctx, pbLeft + 2.0, baselineY + 5.0);
    CGContextAddLineToPoint(ctx, pbLeft, baselineY + 5.0);
    CGContextAddLineToPoint(ctx, pbLeft, baselineY - 2.0);
    CGContextStrokePath(ctx);

    // Right bracket ']'
    CGContextMoveToPoint(ctx, pbRight - 2.0, baselineY + 5.0);
    CGContextAddLineToPoint(ctx, pbRight, baselineY + 5.0);
    CGContextAddLineToPoint(ctx, pbRight, baselineY - 2.0);
    CGContextStrokePath(ctx);

    // Draw spectrum as solid filled columns (authentic Lab599 look)
    NSArray<NSNumber *> *amps = state.spectrumAmplitudes;
    NSUInteger count = amps.count;
    if (count == 0) return;

    CGFloat colW = (endX - startX) / (CGFloat)count;

    [fg setFill];
    for (NSUInteger i = 0; i < count; i++) {
        double val = [amps[i] doubleValue];
        if (val < 0.0) val = 0.0;
        if (val > 1.0) val = 1.0;

        CGFloat h = floor(val * maxH);
        if (h < 1.0) h = 1.0; // Noise floor floor

        CGFloat x = startX + (i * colW);
        NSRect barRect = NSMakeRect(x, baselineY, colW - 0.4, h);
        NSRectFill(barRect);
    }
}

// 7. Bottom Soft-Key Menu Bar (Aligned with 4 bottom physical buttons) (y: 2 to 14)
+ (void)drawBottomMenuBarInContext:(CGContextRef)ctx
                             state:(TX500ScreenState *)state
                                fg:(NSColor *)fg
                                bg:(NSColor *)bg
                               dim:(NSColor *)dim {
    (void)ctx; (void)bg; (void)dim;
    // Four soft keys matching the 4 physical buttons below LCD:
    // [ << ]   [ TONE ]   [ MON ]   [ >> ]
    NSArray *keys = state.softKeyLabels ?: @[@"<<", @"TONE", @"MON", @">>"];
    CGFloat colW = 58.0;
    CGFloat startX = 6.0;
    CGFloat y = 2.5;
    CGFloat h = 10.5;

    NSFont *font = [NSFont monospacedSystemFontOfSize:8.0 weight:NSFontWeightBold];
    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
    style.alignment = NSTextAlignmentCenter;

    NSDictionary *attrs = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: fg,
        NSParagraphStyleAttributeName: style
    };

    for (NSUInteger i = 0; i < 4; i++) {
        NSString *txt = i < keys.count ? keys[i] : @"";
        CGFloat x = startX + (i * (colW + 4.0));

        // In the photo, there are subtle cell frames or centered text
        [txt drawInRect:NSMakeRect(x, y + 0.5, colW, h) withAttributes:attrs];

        // Subtle vertical separator between soft-keys
        if (i < 3) {
            [dim setStroke];
            CGFloat divX = x + colW + 2.0;
            NSBezierPath *sep = [NSBezierPath bezierPath];
            [sep moveToPoint:NSMakePoint(divX, y + 1.0)];
            [sep lineToPoint:NSMakePoint(divX, y + h - 1.0)];
            [sep setLineWidth:0.8];
            [sep stroke];
        }
    }
}

#pragma mark - Chassis Bezel Rendering (Milled Duralumin Front Plate)

+ (NSImage *)renderChassisImageWithState:(TX500ScreenState *)state
                                   theme:(TX500ScreenTheme)theme
                               pixelGrid:(BOOL)pixelGrid {
    return [self renderChassisImageWithState:state
                                       theme:theme
                                   pixelGrid:pixelGrid
                               pressedButton:TX500ControlNone
                                   tuneAngle:0.0
                                 afGainAngle:0.0];
}

+ (NSImage *)renderChassisImageWithState:(TX500ScreenState *)state
                                   theme:(TX500ScreenTheme)theme
                               pixelGrid:(BOOL)pixelGrid
                           pressedButton:(NSInteger)pressedTag
                               tuneAngle:(CGFloat)tuneAngle
                             afGainAngle:(CGFloat)afGainAngle {
    NSSize chassisSize = [self nativeChassisSize]; // 840 x 440
    NSImage *image = [[NSImage alloc] initWithSize:chassisSize];
    [image lockFocus];

    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];

    // 1. Overall Dark CNC Anodized Duralumin Chassis
    NSRect chassisRect = NSMakeRect(0, 0, chassisSize.width, chassisSize.height);
    NSColor *cncBlack = [NSColor colorWithCalibratedRed:0.09 green:0.095 blue:0.105 alpha:1.0];
    [cncBlack setFill];
    NSBezierPath *chassisPath = [NSBezierPath bezierPathWithRoundedRect:chassisRect xRadius:14.0 yRadius:14.0];
    [chassisPath fill];

    // Milled 45-degree chamfer highlight stroke
    [[NSColor colorWithCalibratedWhite:0.25 alpha:1.0] setStroke];
    chassisPath.lineWidth = 1.5;
    [chassisPath stroke];

    // Inner bevel inset
    NSRect innerFace = NSInsetRect(chassisRect, 5.0, 5.0);
    [[NSColor colorWithCalibratedWhite:0.06 alpha:1.0] setStroke];
    NSBezierPath *innerPath = [NSBezierPath bezierPathWithRoundedRect:innerFace xRadius:10.0 yRadius:10.0];
    innerPath.lineWidth = 1.0;
    [innerPath stroke];

    // 2. Left Flank Connector Markings (DC 9-15V, REM/DATA, MIC/SP)
    [self drawLeftConnectorMarkingsInContext:ctx];

    // 3. Four Stainless Steel Hex Socket Cap Screws (Corners)
    [self drawHexScrewAtPoint:NSMakePoint(26.0, chassisSize.height - 30.0) inContext:ctx];
    [self drawHexScrewAtPoint:NSMakePoint(26.0, 30.0) inContext:ctx];
    [self drawHexScrewAtPoint:NSMakePoint(582.0, chassisSize.height - 30.0) inContext:ctx];
    [self drawHexScrewAtPoint:NSMakePoint(582.0, 30.0) inContext:ctx];

    // 4. Center LCD Glass Bezel Area
    // Inset frame: x: 74, y: 56, width: 494, height: 326
    NSRect glassFrame = NSMakeRect(74.0, 56.0, 494.0, 326.0);

    // Deep recessed frame around glass
    [[NSColor colorWithCalibratedWhite:0.03 alpha:1.0] setFill];
    NSBezierPath *recessPath = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(glassFrame, -4.0, -4.0) xRadius:8.0 yRadius:8.0];
    [recessPath fill];
    [[NSColor colorWithCalibratedWhite:0.18 alpha:1.0] setStroke];
    recessPath.lineWidth = 1.0;
    [recessPath stroke];

    // Dark protective glass face
    [[NSColor colorWithCalibratedRed:0.07 green:0.07 blue:0.08 alpha:1.0] setFill];
    NSBezierPath *glassPath = [NSBezierPath bezierPathWithRoundedRect:glassFrame xRadius:6.0 yRadius:6.0];
    [glassPath fill];

    // 5. Active LCD Screen (256 x 128 rendered at 1.84x = 472 x 236)
    CGFloat lcdW = 472.0;
    CGFloat lcdH = 236.0;
    CGFloat lcdX = glassFrame.origin.x + (glassFrame.size.width - lcdW) / 2.0;
    CGFloat lcdY = glassFrame.origin.y + 44.0; // Leave 44px at bottom for logo and text
    NSRect lcdTargetRect = NSMakeRect(lcdX, lcdY, lcdW, lcdH);

    NSImage *screenImg = [self renderScreenImageWithState:state theme:theme scale:2.0 pixelGrid:pixelGrid];
    if (screenImg) {
        CGContextSaveGState(ctx);
        // Crisp drawing of LCD
        [screenImg drawInRect:lcdTargetRect
                     fromRect:NSMakeRect(0, 0, screenImg.size.width, screenImg.size.height)
                    operation:NSCompositingOperationSourceOver
                     fraction:1.0
               respectFlipped:NO
                        hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];
        CGContextRestoreGState(ctx);

        // Inner shadow around LCD edge
        [[NSColor colorWithCalibratedWhite:0.0 alpha:0.40] setStroke];
        NSBezierPath *lcdBorder = [NSBezierPath bezierPathWithRect:lcdTargetRect];
        lcdBorder.lineWidth = 1.0;
        [lcdBorder stroke];
    }

    // 6. Brand Inscription & Logo Under LCD (On the Glass Border)
    [self drawGlassBrandAndLogoAtRect:NSMakeRect(glassFrame.origin.x + 14.0, glassFrame.origin.y + 12.0, glassFrame.size.width - 28.0, 24.0)];

    // 7. Four Top Physical Buttons (Above LCD)
    [self drawFourPhysicalButtonsInContext:ctx
                                    startX:glassFrame.origin.x + 22.0
                                         y:chassisSize.height - 42.0
                                     width:glassFrame.size.width - 44.0
                                     isTop:YES
                                pressedTag:pressedTag];

    // 8. Four Bottom Physical Buttons (Below Glass Bezel)
    [self drawFourPhysicalButtonsInContext:ctx
                                    startX:glassFrame.origin.x + 22.0
                                         y:18.0
                                     width:glassFrame.size.width - 44.0
                                     isTop:NO
                                pressedTag:pressedTag];

    // 9. Right-Side Controls: "DISCOVERY", Buttons (POWER, BAND, MODE, FILTER, MENU) & Rotary Knobs
    [self drawRightControlPanelInContext:ctx
                                  startX:610.0
                           chassisHeight:chassisSize.height
                              pressedTag:pressedTag
                               tuneAngle:tuneAngle
                             afGainAngle:afGainAngle];

    [image unlockFocus];
    return image;
}

#pragma mark - Chassis Components Helper Drawings

// Left Flank Connector Markings: DC 9-15V, REM/DATA, MIC/SP
+ (void)drawLeftConnectorMarkingsInContext:(CGContextRef)ctx {
    (void)ctx;
    NSDictionary *lblAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:8.5 weight:NSFontWeightBold],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.65 alpha:1.0]
    };

    [@"DC 9-15V" drawAtPoint:NSMakePoint(14.0, 316.0) withAttributes:lblAttrs];
    [@"REM /" drawAtPoint:NSMakePoint(16.0, 206.0) withAttributes:lblAttrs];
    [@"DATA" drawAtPoint:NSMakePoint(16.0, 194.0) withAttributes:lblAttrs];
    [@"MIC/SP" drawAtPoint:NSMakePoint(14.0, 84.0) withAttributes:lblAttrs];
}

// Four Oval/Capsule Physical Buttons (Top and Bottom)
+ (void)drawFourPhysicalButtonsInContext:(CGContextRef)ctx
                                  startX:(CGFloat)startX
                                       y:(CGFloat)y
                                   width:(CGFloat)totalW
                                   isTop:(BOOL)isTop
                              pressedTag:(NSInteger)pressedTag {
    CGFloat btnW = 54.0;
    CGFloat btnH = 15.0;
    CGFloat spacing = (totalW - (4.0 * btnW)) / 3.0;

    for (NSUInteger i = 0; i < 4; i++) {
        CGFloat x = startX + (i * (btnW + spacing));
        NSRect btnRect = NSMakeRect(x, y, btnW, btnH);
        NSInteger currentTag = isTop ? (21 + (NSInteger)i) : (31 + (NSInteger)i);
        BOOL isPressed = (pressedTag == currentTag);

        // Recessed cavity under button
        NSRect cavityRect = NSInsetRect(btnRect, -1.5, -1.5);
        [[NSColor colorWithCalibratedWhite:0.04 alpha:1.0] setFill];
        NSBezierPath *cavity = [NSBezierPath bezierPathWithRoundedRect:cavityRect xRadius:8.5 yRadius:8.5];
        [cavity fill];

        if (isPressed) {
            // Luminous golden-amber / cyan backlight glow halo
            CGContextSaveGState(ctx);
            NSColor *glow = [NSColor colorWithCalibratedRed:1.0 green:0.75 blue:0.25 alpha:0.95];
            CGContextSetShadowWithColor(ctx, CGSizeZero, 12.0, glow.CGColor);
            NSBezierPath *halo = [NSBezierPath bezierPathWithRoundedRect:btnRect xRadius:7.5 yRadius:7.5];
            [glow setFill];
            [halo fill];
            CGContextRestoreGState(ctx);

            // Depressed rubber capsule button body
            NSRect pressedRect = NSMakeRect(btnRect.origin.x, btnRect.origin.y - 1.5, btnRect.size.width, btnRect.size.height);
            NSBezierPath *btnPath = [NSBezierPath bezierPathWithRoundedRect:pressedRect xRadius:7.5 yRadius:7.5];
            NSGradient *btnGrad = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:0.10 alpha:1.0]
                                                                endingColor:[NSColor colorWithCalibratedWhite:0.18 alpha:1.0]];
            [btnGrad drawInBezierPath:btnPath angle:270.0];

            [glow setStroke];
            btnPath.lineWidth = 1.5;
            [btnPath stroke];
        } else {
            // Textured rubber capsule button body
            NSBezierPath *btnPath = [NSBezierPath bezierPathWithRoundedRect:btnRect xRadius:7.5 yRadius:7.5];
            NSGradient *btnGrad = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:0.22 alpha:1.0]
                                                                endingColor:[NSColor colorWithCalibratedWhite:0.12 alpha:1.0]];
            [btnGrad drawInBezierPath:btnPath angle:90.0];

            // Top edge highlight
            [[NSColor colorWithCalibratedWhite:0.32 alpha:1.0] setStroke];
            btnPath.lineWidth = 1.0;
            [btnPath stroke];
        }
    }
}

// Brand Inscription Under LCD: "lab 599" logo and "HF/50MHz TRANSCEIVER"
+ (void)drawGlassBrandAndLogoAtRect:(NSRect)rect {
    // Left: Official "lab 599" graphic logo
    NSImage *logoImg = [NSImage imageNamed:@"lab599_logo"];
    if (!logoImg) {
        NSString *p = [[NSBundle mainBundle] pathForResource:@"lab599_logo" ofType:@"png"];
        if (p) logoImg = [[NSImage alloc] initWithContentsOfFile:p];
    }
    if (!logoImg) {
        logoImg = [[NSImage alloc] initWithContentsOfFile:@"Resources/lab599_logo.png"];
    }

    if (logoImg) {
        CGFloat targetH = 18.0;
        CGFloat aspect = 648.0 / 234.0; // 2.769
        CGFloat targetW = targetH * aspect;
        CGFloat logoY = rect.origin.y + (rect.size.height - targetH) / 2.0;
        NSRect logoRect = NSMakeRect(rect.origin.x, logoY, targetW, targetH);
        [logoImg drawInRect:logoRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
    } else {
        NSFont *logoFont = [NSFont systemFontOfSize:15.0 weight:NSFontWeightBlack];
        NSDictionary *labAttrs = @{
            NSFontAttributeName: logoFont,
            NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.92 alpha:1.0]
        };
        NSDictionary *redAttrs = @{
            NSFontAttributeName: logoFont,
            NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.92 green:0.18 blue:0.18 alpha:1.0]
        };
        [@"lab" drawAtPoint:NSMakePoint(rect.origin.x, rect.origin.y + 2.0) withAttributes:labAttrs];
        [@"599" drawAtPoint:NSMakePoint(rect.origin.x + 32.0, rect.origin.y + 2.0) withAttributes:redAttrs];
    }

    // Right: "HF/50MHz TRANSCEIVER"
    NSDictionary *subAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:9.5 weight:NSFontWeightBold],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.75 alpha:1.0]
    };
    NSString *subText = @"HF/50MHz TRANSCEIVER";
    NSSize textSize = [subText sizeWithAttributes:subAttrs];
    CGFloat subY = rect.origin.y + (rect.size.height - textSize.height) / 2.0;
    [subText drawAtPoint:NSMakePoint(NSMaxX(rect) - textSize.width, subY) withAttributes:subAttrs];
}

// Hex Socket Head Cap Screw (Countersunk washer + 6-sided hex socket)
+ (void)drawHexScrewAtPoint:(NSPoint)center inContext:(CGContextRef)ctx {
    CGFloat radius = 8.5;
    NSRect outer = NSMakeRect(center.x - radius, center.y - radius, radius * 2.0, radius * 2.0);

    // Silver washer / screw head
    NSGradient *screwGrad = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:0.75 alpha:1.0]
                                                          endingColor:[NSColor colorWithCalibratedWhite:0.35 alpha:1.0]];
    NSBezierPath *head = [NSBezierPath bezierPathWithOvalInRect:outer];
    [screwGrad drawInBezierPath:head angle:45.0];

    [[NSColor colorWithCalibratedWhite:0.20 alpha:1.0] setStroke];
    head.lineWidth = 1.0;
    [head stroke];

    // Inner 6-sided Hexagonal Socket
    CGFloat hexR = 4.2;
    CGContextSaveGState(ctx);
    [[NSColor colorWithCalibratedWhite:0.10 alpha:1.0] setFill];
    CGContextBeginPath(ctx);
    for (int i = 0; i < 6; i++) {
        CGFloat angle = i * (M_PI / 3.0);
        CGFloat hx = center.x + hexR * cos(angle);
        CGFloat hy = center.y + hexR * sin(angle);
        if (i == 0) CGContextMoveToPoint(ctx, hx, hy);
        else CGContextAddLineToPoint(ctx, hx, hy);
    }
    CGContextClosePath(ctx);
    CGContextFillPath(ctx);
    CGContextRestoreGState(ctx);
}

// Right Control Panel: DISCOVERY, Buttons, Rotary Knobs
+ (void)drawRightControlPanelInContext:(CGContextRef)ctx
                                startX:(CGFloat)startX
                         chassisHeight:(CGFloat)chassisH
                            pressedTag:(NSInteger)pressedTag
                             tuneAngle:(CGFloat)tuneAngle
                           afGainAngle:(CGFloat)afGainAngle {
    // Header text: "DISCOVERY"
    NSDictionary *discAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:14.0 weight:NSFontWeightBlack],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.85 alpha:1.0]
    };
    [@"DISCOVERY" drawAtPoint:NSMakePoint(startX + 18.0, chassisH - 42.0) withAttributes:discAttrs];

    // Vertical Buttons Stack: POWER, BAND+, BAND-, MODE, FILTER, MENU
    NSArray *btnNames = @[@"POWER", @"BAND+", @"BAND-", @"MODE", @"FILTER", @"MENU"];
    CGFloat btnW = 60.0;
    CGFloat btnH = 19.0;
    CGFloat btnY = chassisH - 85.0;

    for (NSUInteger i = 0; i < btnNames.count; i++) {
        NSString *name = btnNames[i];
        NSInteger currentTag = (NSInteger)(i + 1); // 1 = POWER, 2 = BAND+, 3 = BAND-, 4 = MODE, 5 = FILTER, 6 = MENU
        NSRect btnRect = NSMakeRect(startX + 10.0, btnY - (i * 30.0), btnW, btnH);
        BOOL isPressed = (pressedTag == currentTag);

        // Recessed cavity under button
        NSRect cavityRect = NSInsetRect(btnRect, -1.5, -1.5);
        [[NSColor colorWithCalibratedWhite:0.04 alpha:1.0] setFill];
        NSBezierPath *cavity = [NSBezierPath bezierPathWithRoundedRect:cavityRect xRadius:7.0 yRadius:7.0];
        [cavity fill];

        if (isPressed) {
            // Luminous neon glow aura radiating from bezel
            CGContextSaveGState(ctx);
            NSColor *glow = (currentTag == 1) ?
                [NSColor colorWithCalibratedRed:1.0 green:0.22 blue:0.22 alpha:0.95] :
                [NSColor colorWithCalibratedRed:0.0 green:0.85 blue:1.0 alpha:0.95];
            CGContextSetShadowWithColor(ctx, CGSizeZero, 14.0, glow.CGColor);
            NSBezierPath *halo = [NSBezierPath bezierPathWithRoundedRect:btnRect xRadius:6.0 yRadius:6.0];
            [glow setFill];
            [halo fill];
            CGContextRestoreGState(ctx);

            // Depressed button face shifted down by 1.5px
            NSRect pressedRect = NSMakeRect(btnRect.origin.x, btnRect.origin.y - 1.5, btnRect.size.width, btnRect.size.height);
            NSBezierPath *btn = [NSBezierPath bezierPathWithRoundedRect:pressedRect xRadius:6.0 yRadius:6.0];
            NSGradient *btnGrad = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:0.10 alpha:1.0]
                                                                endingColor:[NSColor colorWithCalibratedWhite:0.16 alpha:1.0]];
            [btnGrad drawInBezierPath:btn angle:270.0];

            // Illuminated border stroke
            [glow setStroke];
            btn.lineWidth = 1.5;
            [btn stroke];

            // Shifted text with vivid highlight
            NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
            style.alignment = NSTextAlignmentCenter;
            NSColor *tColor = (currentTag == 1) ?
                [NSColor colorWithCalibratedRed:1.0 green:0.40 blue:0.40 alpha:1.0] :
                [NSColor colorWithCalibratedRed:0.85 green:0.95 blue:1.0 alpha:1.0];
            NSDictionary *attrs = @{
                NSFontAttributeName: [NSFont systemFontOfSize:8.5 weight:NSFontWeightBold],
                NSForegroundColorAttributeName: tColor,
                NSParagraphStyleAttributeName: style
            };
            NSSize textSize = [name sizeWithAttributes:attrs];
            CGFloat textY = pressedRect.origin.y + floor((btnH - textSize.height) / 2.0);
            NSRect textRect = NSMakeRect(pressedRect.origin.x, textY, btnW, textSize.height);
            [name drawInRect:textRect withAttributes:attrs];
        } else {
            // Normal button body
            NSBezierPath *btn = [NSBezierPath bezierPathWithRoundedRect:btnRect xRadius:6.0 yRadius:6.0];
            NSGradient *btnGrad = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:0.22 alpha:1.0]
                                                                endingColor:[NSColor colorWithCalibratedWhite:0.14 alpha:1.0]];
            [btnGrad drawInBezierPath:btn angle:90.0];

            [[NSColor colorWithCalibratedWhite:0.30 alpha:1.0] setStroke];
            btn.lineWidth = 1.0;
            [btn stroke];

            // Text: POWER in Red, others in White
            NSColor *textColor = [name isEqualToString:@"POWER"] ?
                [NSColor colorWithCalibratedRed:0.95 green:0.25 blue:0.25 alpha:1.0] :
                [NSColor colorWithCalibratedWhite:0.88 alpha:1.0];

            NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
            style.alignment = NSTextAlignmentCenter;
            NSDictionary *attrs = @{
                NSFontAttributeName: [NSFont systemFontOfSize:8.5 weight:NSFontWeightBold],
                NSForegroundColorAttributeName: textColor,
                NSParagraphStyleAttributeName: style
            };
            NSSize textSize = [name sizeWithAttributes:attrs];
            CGFloat textY = btnRect.origin.y + floor((btnH - textSize.height) / 2.0);
            NSRect textRect = NSMakeRect(btnRect.origin.x, textY, btnW, textSize.height);
            [name drawInRect:textRect withAttributes:attrs];
        }
    }

    // Rotary Knobs: AF GAIN (Top) and TUNE (Bottom)
    // 1. AF GAIN Knob
    CGFloat knobX = startX + 115.0;
    CGFloat afY = chassisH - 120.0;
    BOOL isAFPressed = (pressedTag == TX500ControlAFGainKnob);
    [self drawRotaryKnobAtPoint:NSMakePoint(knobX, afY)
                         radius:26.0
                          label:@"AF GAIN"
                      hasDimple:NO
                          angle:afGainAngle
                      isPressed:isAFPressed
                      inContext:ctx];

    // 2. TUNE Main VFO Knob
    CGFloat tuneY = 120.0;
    BOOL isTunePressed = (pressedTag == TX500ControlTuneKnob);
    [self drawRotaryKnobAtPoint:NSMakePoint(knobX, tuneY)
                         radius:44.0
                          label:@"TUNE"
                      hasDimple:YES
                          angle:tuneAngle
                      isPressed:isTunePressed
                      inContext:ctx];
}

// Rotary Knob with Knurled Rim, Face, and Finger Dimple / Pointer
+ (void)drawRotaryKnobAtPoint:(NSPoint)center
                       radius:(CGFloat)radius
                        label:(NSString *)label
                    hasDimple:(BOOL)hasDimple
                        angle:(CGFloat)angle
                    isPressed:(BOOL)isPressed
                    inContext:(CGContextRef)ctx {
    NSRect outer = NSMakeRect(center.x - radius, center.y - radius, radius * 2.0, radius * 2.0);

    // Recessed dark cavity behind knob
    NSRect cavity = NSInsetRect(outer, -2.0, -2.0);
    [[NSColor colorWithCalibratedWhite:0.04 alpha:1.0] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:cavity] fill];

    // If pressed or interacting, draw luminous neon cyan halo around the knob
    if (isPressed) {
        CGContextSaveGState(ctx);
        NSColor *knobGlow = [NSColor colorWithCalibratedRed:0.0 green:0.80 blue:1.0 alpha:0.85];
        CGContextSetShadowWithColor(ctx, CGSizeZero, 16.0, knobGlow.CGColor);
        NSBezierPath *glowOval = [NSBezierPath bezierPathWithOvalInRect:outer];
        [knobGlow setFill];
        [glowOval fill];
        CGContextRestoreGState(ctx);
    }

    // Knurled outer rim
    [[NSColor colorWithCalibratedWhite:0.14 alpha:1.0] setFill];
    NSBezierPath *rim = [NSBezierPath bezierPathWithOvalInRect:outer];
    [rim fill];
    [[NSColor colorWithCalibratedWhite:0.32 alpha:1.0] setStroke];
    rim.lineWidth = 1.5;
    [rim stroke];

    // Knurling radial notches around the perimeter rotating with angle
    NSInteger numKnurls = hasDimple ? 32 : 24;
    CGContextSaveGState(ctx);
    [[NSColor colorWithCalibratedWhite:0.24 alpha:0.85] setStroke];
    for (NSInteger k = 0; k < numKnurls; k++) {
        CGFloat th = (CGFloat)k * (2.0 * M_PI / (CGFloat)numKnurls) + angle;
        CGFloat x1 = center.x + (radius - 3.5) * cos(th);
        CGFloat y1 = center.y + (radius - 3.5) * sin(th);
        CGFloat x2 = center.x + radius * cos(th);
        CGFloat y2 = center.y + radius * sin(th);
        CGContextBeginPath(ctx);
        CGContextMoveToPoint(ctx, x1, y1);
        CGContextAddLineToPoint(ctx, x2, y2);
        CGContextSetLineWidth(ctx, 1.0);
        CGContextStrokePath(ctx);
    }
    CGContextRestoreGState(ctx);

    // Inner metallic knob face
    NSRect inner = NSInsetRect(outer, 4.0, 4.0);
    NSGradient *knobGrad = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:0.26 alpha:1.0]
                                                         endingColor:[NSColor colorWithCalibratedWhite:0.12 alpha:1.0]];
    NSBezierPath *face = [NSBezierPath bezierPathWithOvalInRect:inner];
    [knobGrad drawInBezierPath:face angle:60.0];

    // Finger dimple indentation (for TUNE dial) with rotating position
    if (hasDimple) {
        CGFloat dimpleR = radius * 0.28;
        CGFloat d = radius * 0.52;
        NSPoint dimpleCenter = NSMakePoint(center.x + d * cos(angle), center.y + d * sin(angle));
        NSRect dimpleRect = NSMakeRect(dimpleCenter.x - dimpleR, dimpleCenter.y - dimpleR, dimpleR * 2.0, dimpleR * 2.0);

        NSGradient *dimpleGrad = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:0.07 alpha:1.0]
                                                               endingColor:[NSColor colorWithCalibratedWhite:0.22 alpha:1.0]];
        NSBezierPath *dimple = [NSBezierPath bezierPathWithOvalInRect:dimpleRect];
        [dimpleGrad drawInBezierPath:dimple angle:240.0];
        [[NSColor colorWithCalibratedWhite:0.35 alpha:1.0] setStroke];
        dimple.lineWidth = 0.8;
        [dimple stroke];
    } else {
        // Metallic pointer line for AF GAIN dial
        CGFloat rInner = 8.0;
        CGFloat rOuter = radius - 6.0;
        CGFloat px1 = center.x + rInner * cos(angle);
        CGFloat py1 = center.y + rInner * sin(angle);
        CGFloat px2 = center.x + rOuter * cos(angle);
        CGFloat py2 = center.y + rOuter * sin(angle);

        CGContextSaveGState(ctx);
        [[NSColor colorWithCalibratedWhite:0.85 alpha:1.0] setStroke];
        CGContextBeginPath(ctx);
        CGContextMoveToPoint(ctx, px1, py1);
        CGContextAddLineToPoint(ctx, px2, py2);
        CGContextSetLineWidth(ctx, 2.0);
        CGContextSetLineCap(ctx, kCGLineCapRound);
        CGContextStrokePath(ctx);
        CGContextRestoreGState(ctx);
    }

    // Label below knob
    if (label.length) {
        NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
        style.alignment = NSTextAlignmentCenter;
        NSDictionary *lblAttrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:8.5 weight:NSFontWeightBold],
            NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.75 alpha:1.0],
            NSParagraphStyleAttributeName: style
        };
        [label drawInRect:NSMakeRect(center.x - 45.0, center.y - radius - 16.0, 90.0, 14.0) withAttributes:lblAttrs];
    }
}

#pragma mark - Export Helpers

+ (nullable NSData *)pngDataForImage:(NSImage *)image {
    if (!image) return nil;
    CGImageRef cgImage = [image CGImageForProposedRect:NULL context:nil hints:nil];
    if (!cgImage) return nil;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
    return [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

+ (nullable NSData *)jpegDataForImage:(NSImage *)image compression:(CGFloat)compression {
    if (!image) return nil;
    CGImageRef cgImage = [image CGImageForProposedRect:NULL context:nil hints:nil];
    if (!cgImage) return nil;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
    return [rep representationUsingType:NSBitmapImageFileTypeJPEG properties:@{
        NSImageCompressionFactor: @(compression)
    }];
}

@end
