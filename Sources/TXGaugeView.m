#import "TXGaugeView.h"
#import <math.h>

@interface TXGaugeView ()
@property (nonatomic, assign) double displayedValue;
@end

@implementation TXGaugeView

- (BOOL)isFlipped {
    return YES;
}

- (instancetype)initWithTitle:(NSString *)title
                         unit:(NSString *)unit
                          min:(double)min
                          max:(double)max
                       format:(NSString *)format {
    if ((self = [super initWithFrame:NSMakeRect(0, 0, 200, 172)])) {
        _title = [title copy];
        _unit = [unit copy];
        _minValue = min;
        _maxValue = max;
        _valueFormat = [format copy] ?: @"%.1f";
        _currentValue = min;
        _displayedValue = min;
        _peakValue = min;
        _selectedAvgWindow = -1;
        _hasAverages = NO;
        _greenStart = min;
        _greenEnd = max * 0.7;
        _yellowStart = max * 0.7;
        _yellowEnd = max * 0.9;
        _redStart = max * 0.9;
        _redEnd = max;
        self.wantsLayer = YES;
    }
    return self;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    return [self initWithTitle:@"GAUGE" unit:@"" min:0 max:100 format:@"%.0f"];
}

- (void)setValue:(double)value animated:(BOOL)animated {
    (void)animated;
    if (value < self.minValue) value = self.minValue;
    if (value > self.maxValue) value = self.maxValue;
    _currentValue = value;
    if (value > _peakValue) {
        _peakValue = value;
    }
    _displayedValue = value;
    [self setNeedsDisplay:YES];
}

- (void)setAverages5m:(double)m5 m15:(double)m15 m30:(double)m30 m60:(double)m60 {
    _avg5m = m5;
    _avg15m = m15;
    _avg30m = m30;
    _avg60m = m60;
    _hasAverages = YES;
    [self setNeedsDisplay:YES];
}

- (void)resetPeak {
    _peakValue = _currentValue;
    [self setNeedsDisplay:YES];
}

#pragma mark - Geometry & Angle Conversion (isFlipped = YES)

// In flipped coordinates (y goes down):
// 155° is bottom-left (start), 270° is top (mid), 385° / 25° is bottom-right (end).
static const double kDialStartDegrees = 155.0;
static const double kDialSweepDegrees = 230.0;

- (double)angleForValue:(double)val {
    if (self.maxValue <= self.minValue) return kDialStartDegrees;
    double clamped = fmin(fmax(val, self.minValue), self.maxValue);
    double fraction = (clamped - self.minValue) / (self.maxValue - self.minValue);
    return kDialStartDegrees + (fraction * kDialSweepDegrees);
}

- (CGFloat)degreesToRadians:(double)deg {
    return (CGFloat)(deg * M_PI / 180.0);
}

#pragma mark - Drawing

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    NSRect bounds = self.bounds;
    CGFloat W = bounds.size.width;
    CGFloat H = bounds.size.height;
    if (W < 50 || H < 50) return;

    BOOL isDark = (self.effectiveAppearance.name == NSAppearanceNameDarkAqua);

    // 1. Card Container (Rounded Background + Subtle Border)
    CGFloat cornerRadius = 10.0;
    NSRect cardRect = NSInsetRect(bounds, 0.5, 0.5);
    NSBezierPath *cardPath = [NSBezierPath bezierPathWithRoundedRect:cardRect xRadius:cornerRadius yRadius:cornerRadius];
    NSColor *cardBg = isDark ? [NSColor colorWithCalibratedWhite:0.13 alpha:0.95] : [NSColor colorWithCalibratedWhite:0.98 alpha:0.95];
    [cardBg setFill];
    [cardPath fill];

    NSColor *cardBorder = isDark ? [NSColor colorWithCalibratedWhite:0.24 alpha:1.0] : [NSColor colorWithCalibratedWhite:0.86 alpha:1.0];
    [cardBorder setStroke];
    cardPath.lineWidth = 1.0;
    [cardPath stroke];

    // ==========================================
    // ZONE 1: HEADER (y = 0 .. 28)
    // ==========================================
    NSDictionary *titleAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11.0 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
    };
    [self.title drawAtPoint:NSMakePoint(14.0, 7.0) withAttributes:titleAttrs];

    // Header Right Badge (Peak value or subBadge)
    NSString *badgeText = self.subBadge;
    if (!badgeText && self.peakValue > self.minValue) {
        badgeText = [NSString stringWithFormat:@"PK: %@ %@", [NSString stringWithFormat:self.valueFormat, self.peakValue], self.unit];
    }
    if (badgeText.length > 0) {
        NSDictionary *badgeAttrs = @{
            NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:9.5 weight:NSFontWeightMedium],
            NSForegroundColorAttributeName: isDark ? [NSColor colorWithCalibratedWhite:0.75 alpha:1.0] : [NSColor colorWithCalibratedWhite:0.35 alpha:1.0]
        };
        NSSize bSize = [badgeText sizeWithAttributes:badgeAttrs];
        CGFloat bW = bSize.width + 10.0;
        CGFloat bH = 17.0;
        CGFloat bX = W - 14.0 - bW;
        CGFloat bY = 6.5;

        NSRect bRect = NSMakeRect(bX, bY, bW, bH);
        NSBezierPath *bPath = [NSBezierPath bezierPathWithRoundedRect:bRect xRadius:4.0 yRadius:4.0];
        NSColor *bFill = isDark ? [NSColor colorWithCalibratedWhite:0.22 alpha:0.8] : [NSColor colorWithCalibratedWhite:0.91 alpha:0.9];
        [bFill setFill];
        [bPath fill];
        [badgeText drawAtPoint:NSMakePoint(bX + 5.0, bY + 1.5) withAttributes:badgeAttrs];
    }

    // Header Divider Line
    CGContextSaveGState(ctx);
    CGContextSetStrokeColorWithColor(ctx, [NSColor colorWithCalibratedWhite:0.5 alpha:0.12].CGColor);
    CGContextSetLineWidth(ctx, 0.5);
    CGContextMoveToPoint(ctx, 12.0, 28.0);
    CGContextAddLineToPoint(ctx, W - 12.0, 28.0);
    CGContextStrokePath(ctx);
    CGContextRestoreGState(ctx);

    // ==========================================
    // ZONE 2: DIAL CHAMBER (y = 29 .. 112)
    // ==========================================
    CGPoint center = CGPointMake(W / 2.0, 93.0);
    CGFloat radius = fmin(fmin(W * 0.26, 48.0), (H - 75.0) * 0.52);
    CGFloat arcWidth = 5.5;

    // Background Full Track Arc
    CGContextSaveGState(ctx);
    CGContextSetLineWidth(ctx, arcWidth);
    CGContextSetLineCap(ctx, kCGLineCapRound);
    NSColor *trackColor = [NSColor colorWithCalibratedWhite:0.5 alpha:0.16];
    CGContextSetStrokeColorWithColor(ctx, trackColor.CGColor);
    CGContextAddArc(ctx, center.x, center.y, radius,
                    [self degreesToRadians:kDialStartDegrees],
                    [self degreesToRadians:kDialStartDegrees + kDialSweepDegrees],
                    0);
    CGContextStrokePath(ctx);
    CGContextRestoreGState(ctx);

    // Color Segments (Green, Yellow, Red)
    void (^drawSegment)(double, double, NSColor *) = ^(double valStart, double valEnd, NSColor *color) {
        if (valEnd <= valStart) return;
        double a1 = [self angleForValue:valStart];
        double a2 = [self angleForValue:valEnd];
        CGContextSaveGState(ctx);
        CGContextSetLineWidth(ctx, arcWidth);
        CGContextSetLineCap(ctx, kCGLineCapButt);
        CGContextSetStrokeColorWithColor(ctx, color.CGColor);
        CGContextAddArc(ctx, center.x, center.y, radius, [self degreesToRadians:a1], [self degreesToRadians:a2], 0);
        CGContextStrokePath(ctx);
        CGContextRestoreGState(ctx);
    };

    drawSegment(self.greenStart, self.greenEnd, [NSColor colorWithCalibratedRed:0.18 green:0.80 blue:0.38 alpha:0.90]);
    drawSegment(self.yellowStart, self.yellowEnd, [NSColor colorWithCalibratedRed:0.98 green:0.72 blue:0.15 alpha:0.90]);
    drawSegment(self.redStart, self.redEnd, [NSColor colorWithCalibratedRed:0.95 green:0.26 blue:0.22 alpha:0.95]);

    // Min & Max scale labels at arc endpoints (placed cleanly outside arc feet)
    NSDictionary *limitAttrs = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:8.5 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor tertiaryLabelColor]
    };
    NSString *minStr = [NSString stringWithFormat:self.valueFormat, self.minValue];
    NSString *maxStr = [NSString stringWithFormat:self.valueFormat, self.maxValue];

    double minAngleRad = [self degreesToRadians:kDialStartDegrees];
    double maxAngleRad = [self degreesToRadians:kDialStartDegrees + kDialSweepDegrees];

    NSSize minSize = [minStr sizeWithAttributes:limitAttrs];
    NSSize maxSize = [maxStr sizeWithAttributes:limitAttrs];

    CGPoint minPt = CGPointMake(center.x + (radius + 10.0) * cos(minAngleRad) - minSize.width * 0.85,
                                center.y + (radius + 10.0) * sin(minAngleRad) - minSize.height * 0.2);
    CGPoint maxPt = CGPointMake(center.x + (radius + 10.0) * cos(maxAngleRad) - maxSize.width * 0.15,
                                center.y + (radius + 10.0) * sin(maxAngleRad) - maxSize.height * 0.2);

    [minStr drawAtPoint:minPt withAttributes:limitAttrs];
    [maxStr drawAtPoint:maxPt withAttributes:limitAttrs];

    // Radial Ticks (subtle notches along inner arc rim)
    NSInteger numTicks = 6;
    for (NSInteger i = 0; i <= numTicks; i++) {
        double tickVal = self.minValue + (i * (self.maxValue - self.minValue) / numTicks);
        double tickAngle = [self angleForValue:tickVal];
        CGFloat rad = [self degreesToRadians:tickAngle];

        CGFloat r1 = radius - (arcWidth / 2.0) - 1.5;
        CGFloat r2 = r1 - 3.5;

        CGPoint p1 = CGPointMake(center.x + r1 * cos(rad), center.y + r1 * sin(rad));
        CGPoint p2 = CGPointMake(center.x + r2 * cos(rad), center.y + r2 * sin(rad));

        CGContextSaveGState(ctx);
        CGContextSetStrokeColorWithColor(ctx, [NSColor colorWithCalibratedWhite:0.5 alpha:0.4].CGColor);
        CGContextSetLineWidth(ctx, 1.0);
        CGContextMoveToPoint(ctx, p1.x, p1.y);
        CGContextAddLineToPoint(ctx, p2.x, p2.y);
        CGContextStrokePath(ctx);
        CGContextRestoreGState(ctx);
    }

    // Peak Hold Marker (Orange outer notch)
    if (self.peakValue > self.minValue) {
        double peakAngle = [self angleForValue:self.peakValue];
        CGFloat peakRad = [self degreesToRadians:peakAngle];
        CGFloat pr1 = radius + arcWidth / 2.0 + 1.0;
        CGFloat pr2 = pr1 + 4.0;
        CGPoint pp1 = CGPointMake(center.x + pr1 * cos(peakRad), center.y + pr1 * sin(peakRad));
        CGPoint pp2 = CGPointMake(center.x + pr2 * cos(peakRad), center.y + pr2 * sin(peakRad));

        CGContextSaveGState(ctx);
        CGContextSetStrokeColorWithColor(ctx, [NSColor systemOrangeColor].CGColor);
        CGContextSetLineWidth(ctx, 2.0);
        CGContextMoveToPoint(ctx, pp1.x, pp1.y);
        CGContextAddLineToPoint(ctx, pp2.x, pp2.y);
        CGContextStrokePath(ctx);
        CGContextRestoreGState(ctx);
    }

    // Analog Needle
    double needleAngle = [self angleForValue:self.displayedValue];
    CGFloat needleRad = [self degreesToRadians:needleAngle];
    CGFloat needleLen = radius - 3.0;

    CGPoint needleTip = CGPointMake(center.x + needleLen * cos(needleRad), center.y + needleLen * sin(needleRad));
    CGFloat baseRadius = 3.0;
    CGFloat perpRad = needleRad + M_PI_2;
    CGPoint needleBase1 = CGPointMake(center.x + baseRadius * cos(perpRad), center.y + baseRadius * sin(perpRad));
    CGPoint needleBase2 = CGPointMake(center.x - baseRadius * cos(perpRad), center.y - baseRadius * sin(perpRad));
    // Subtle tail counterweight (extends 6pt opposite to needle)
    CGPoint needleTail = CGPointMake(center.x - 6.0 * cos(needleRad), center.y - 6.0 * sin(needleRad));

    CGContextSaveGState(ctx);
    CGContextSetShadowWithColor(ctx, CGSizeMake(0, 1.5), 3.0, [NSColor colorWithCalibratedWhite:0 alpha:0.25].CGColor);

    NSColor *needleColor = self.isAlertActive ? [NSColor systemRedColor] : [NSColor labelColor];
    CGContextSetFillColorWithColor(ctx, needleColor.CGColor);
    CGContextMoveToPoint(ctx, needleBase1.x, needleBase1.y);
    CGContextAddLineToPoint(ctx, needleTip.x, needleTip.y);
    CGContextAddLineToPoint(ctx, needleBase2.x, needleBase2.y);
    CGContextAddLineToPoint(ctx, needleTail.x, needleTail.y);
    CGContextClosePath(ctx);
    CGContextFillPath(ctx);

    // Center Metallic Pivot Hub
    CGContextSetFillColorWithColor(ctx, isDark ? [NSColor colorWithCalibratedWhite:0.28 alpha:1.0].CGColor : [NSColor colorWithCalibratedWhite:0.75 alpha:1.0].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(center.x - 5.5, center.y - 5.5, 11.0, 11.0));
    CGContextSetFillColorWithColor(ctx, needleColor.CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(center.x - 2.5, center.y - 2.5, 5.0, 5.0));
    CGContextRestoreGState(ctx);

    // ==========================================
    // ZONE 3: DIGITAL VALUE READOUT (y = 114 .. 138)
    // ==========================================
    NSString *valStr = [NSString stringWithFormat:self.valueFormat, self.currentValue];
    NSString *fullValStr;
    if (self.unit.length > 0) {
        if ([self.unit hasPrefix:@":"]) {
            fullValStr = [NSString stringWithFormat:@"%@%@", valStr, self.unit];
        } else {
            fullValStr = [NSString stringWithFormat:@"%@ %@", valStr, self.unit];
        }
    } else {
        fullValStr = valStr;
    }

    NSColor *digitColor = self.isAlertActive ? [NSColor systemRedColor] : [NSColor labelColor];
    NSDictionary *valAttrs = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:17.0 weight:NSFontWeightBold],
        NSForegroundColorAttributeName: digitColor
    };
    NSSize valSize = [fullValStr sizeWithAttributes:valAttrs];
    CGPoint valPt = CGPointMake(center.x - valSize.width / 2.0, 116.0);
    [fullValStr drawAtPoint:valPt withAttributes:valAttrs];

    // ==========================================
    // ZONE 4: ROLLING AVERAGES FOOTER (y = 142 .. H - 1)
    // ==========================================
    CGFloat footY = 142.0;
    CGFloat footH = H - footY - 1.0;
    if (footH > 15.0) {
        NSRect footRect = NSMakeRect(3.0, footY, W - 6.0, footH);
        NSBezierPath *footPath = [NSBezierPath bezierPathWithRoundedRect:footRect xRadius:7.0 yRadius:7.0];
        NSColor *footBg = isDark ? [NSColor colorWithCalibratedWhite:0.18 alpha:0.75] : [NSColor colorWithCalibratedWhite:0.93 alpha:0.85];
        [footBg setFill];
        [footPath fill];

        // 4 Columns: 5m, 15m, 30m, 60m
        NSArray<NSString *> *intervals = @[@"5m", @"15m", @"30m", @"60m"];
        double avgValues[4] = { self.avg5m, self.avg15m, self.avg30m, self.avg60m };
        CGFloat colW = (W - 10.0) / 4.0;

        for (NSInteger i = 0; i < 4; i++) {
            CGFloat colX = 5.0 + (i * colW);

            // Highlight pill if this window is selected
            if (self.selectedAvgWindow == i) {
                NSRect selRect = NSMakeRect(colX + 2.0, footY + 2.0, colW - 4.0, footH - 4.0);
                NSBezierPath *selPath = [NSBezierPath bezierPathWithRoundedRect:selRect xRadius:4.0 yRadius:4.0];
                [[NSColor.systemBlueColor colorWithAlphaComponent:0.2] setFill];
                [selPath fill];
            }

            NSString *valDisplay = self.hasAverages ? [NSString stringWithFormat:self.valueFormat, avgValues[i]] : @"--";
            NSString *cellStr = [NSString stringWithFormat:@"%@: %@", intervals[i], valDisplay];

            NSDictionary *cellAttrs = @{
                NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:9.0 weight:NSFontWeightMedium],
                NSForegroundColorAttributeName: (self.selectedAvgWindow == i) ? [NSColor labelColor] : [NSColor secondaryLabelColor]
            };
            NSSize cellSize = [cellStr sizeWithAttributes:cellAttrs];
            CGPoint cellPt = CGPointMake(colX + (colW - cellSize.width) / 2.0, footY + (footH - cellSize.height) / 2.0);
            [cellStr drawAtPoint:cellPt withAttributes:cellAttrs];

            // Vertical divider dot between columns
            if (i < 3) {
                CGFloat divX = colX + colW;
                CGContextSaveGState(ctx);
                CGContextSetStrokeColorWithColor(ctx, [NSColor colorWithCalibratedWhite:0.5 alpha:0.18].CGColor);
                CGContextSetLineWidth(ctx, 0.5);
                CGContextMoveToPoint(ctx, divX, footY + 4.0);
                CGContextAddLineToPoint(ctx, divX, footY + footH - 4.0);
                CGContextStrokePath(ctx);
                CGContextRestoreGState(ctx);
            }
        }
    }
}

@end
