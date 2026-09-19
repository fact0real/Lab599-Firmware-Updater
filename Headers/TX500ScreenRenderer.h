#import <Cocoa/Cocoa.h>
#import "TX500ScreenModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface TX500ScreenRenderer : NSObject

// Exact dimensions of the physical Lab599 TX-500 LCD panel in dots
+ (NSSize)nativeLCDSize; // 256 x 128

// Renders the 256x128 monochrome LCD screen at the requested integer scale (e.g. 1.0 = 256x128, 2.0 = 512x256, 4.0 = 1024x512)
+ (NSImage *)renderScreenImageWithState:(TX500ScreenState *)state
                                  theme:(TX500ScreenTheme)theme
                                  scale:(CGFloat)scale
                              pixelGrid:(BOOL)pixelGrid;

typedef NS_ENUM(NSInteger, TX500ChassisControlTag) {
    TX500ControlNone = 0,
    // Right panel vertical buttons
    TX500ControlPower = 1,
    TX500ControlBandUp = 2,
    TX500ControlBandDown = 3,
    TX500ControlMode = 4,
    TX500ControlFilter = 5,
    TX500ControlMenu = 6,
    // Right panel rotary knobs
    TX500ControlTuneKnob = 10,
    TX500ControlAFGainKnob = 11,
    // Top physical soft keys (above LCD)
    TX500ControlTopKey1 = 21,
    TX500ControlTopKey2 = 22,
    TX500ControlTopKey3 = 23,
    TX500ControlTopKey4 = 24,
    // Bottom physical soft keys (below LCD)
    TX500ControlBottomKey1 = 31,
    TX500ControlBottomKey2 = 32,
    TX500ControlBottomKey3 = 33,
    TX500ControlBottomKey4 = 34
};

// Renders the screen framed in the authentic CNC-milled black anodized duralumin chassis of the TX-500
+ (NSImage *)renderChassisImageWithState:(TX500ScreenState *)state
                                   theme:(TX500ScreenTheme)theme
                               pixelGrid:(BOOL)pixelGrid;

+ (NSImage *)renderChassisImageWithState:(TX500ScreenState *)state
                                   theme:(TX500ScreenTheme)theme
                               pixelGrid:(BOOL)pixelGrid
                           pressedButton:(NSInteger)pressedTag
                               tuneAngle:(CGFloat)tuneAngle
                             afGainAngle:(CGFloat)afGainAngle;

// Image export helpers
+ (nullable NSData *)pngDataForImage:(NSImage *)image;
+ (nullable NSData *)jpegDataForImage:(NSImage *)image compression:(CGFloat)compression;

// Default theme colors
+ (NSColor *)backgroundColorForTheme:(TX500ScreenTheme)theme;
+ (NSColor *)pixelOnColorForTheme:(TX500ScreenTheme)theme;
+ (NSColor *)pixelOffColorForTheme:(TX500ScreenTheme)theme;

@end

NS_ASSUME_NONNULL_END
