#import <Cocoa/Cocoa.h>
#import "../Headers/TX500ScreenModel.h"
#import "../Headers/TX500ScreenRenderer.h"
#import "../Headers/TX500ScreenCaptureController.h"

static void Check(BOOL passed, NSString *message) {
    if (!passed) {
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
        exit(1);
    }
}

int main(void) {
    @autoreleasepool {
        printf("Running TX-500 Screen Rendering & Capture Unit Tests (V2)...\n");

        // 1. Native LCD dimensions test
        NSSize nativeSize = [TX500ScreenRenderer nativeLCDSize];
        Check(nativeSize.width == 256.0 && nativeSize.height == 128.0, @"Native TX-500 LCD size must be 256x128 pixels");

        // 2. Screen Model & default state test (matching physical radio photo)
        TX500ScreenState *state = [TX500ScreenState defaultDemoState];
        Check(state != nil, @"Default demo state must be non-nil");
        Check(state.frequencyHz == 24889300, @"Default frequency must be 24.889.300 Hz (12m DIG)");
        Check([state.operatingMode isEqualToString:@"DIG"], @"Default operating mode must be DIG");
        Check(state.vfoBFrequencyHz == 10100000, @"Default VFO-B frequency must be 10.100.000 Hz");
        Check([state.vfoBMode isEqualToString:@"CWR"], @"Default VFO-B mode must be CWR");
        Check(state.supplyVoltage == 12.0, @"Default supply voltage must be 12.0V");
        Check([state.filterName isEqualToString:@"FIL-1"], @"Default filter must be FIL-1");
        Check([state.filterBandwidthString isEqualToString:@"3.10k"], @"Default filter bandwidth must be 3.10k");
        Check(state.afGainLevel == 64, @"Default AF Gain must be 64");
        Check(state.rfGainLevel == 0, @"Default RF Gain must be 0");
        Check(state.topSoftKeyLabels.count == 4, @"Top soft-keys must have 4 items");
        Check(state.softKeyLabels.count == 4, @"Bottom soft-keys must have 4 items");
        Check(state.spectrumAmplitudes.count == 64, @"Spectrum amplitudes must contain 64 frequency bins");

        // 3. State Copying test
        TX500ScreenState *stateCopy = [state copy];
        Check(stateCopy != state, @"Copied state must be a distinct object");
        Check(stateCopy.frequencyHz == state.frequencyHz, @"Frequency preserved in copy");
        Check([stateCopy.operatingMode isEqualToString:state.operatingMode], @"Mode preserved in copy");
        Check([stateCopy.vfoBMode isEqualToString:state.vfoBMode], @"VFO-B mode preserved in copy");
        Check(stateCopy.sMeterDots == state.sMeterDots, @"S-meter dots preserved in copy");
        Check(stateCopy.topSoftKeyLabels.count == 4, @"Top soft-keys preserved in copy");

        // 4. Renderer: Native 1x (256x128) Screen Image test
        NSImage *screen1x = [TX500ScreenRenderer renderScreenImageWithState:state
                                                                     theme:TX500ScreenThemeCoolWhite
                                                                     scale:1.0
                                                                 pixelGrid:NO];
        Check(screen1x != nil, @"1x screen image must be non-nil");
        Check(NSEqualSizes(screen1x.size, NSMakeSize(256, 128)), @"1x screen image size must be exactly 256x128");

        // 5. Renderer: Integer Scaling (2x = 512x256, 4x = 1024x512)
        NSImage *screen2x = [TX500ScreenRenderer renderScreenImageWithState:state
                                                                     theme:TX500ScreenThemeCoolWhite
                                                                     scale:2.0
                                                                 pixelGrid:YES];
        Check(screen2x != nil, @"2x screen image must be non-nil");
        Check(NSEqualSizes(screen2x.size, NSMakeSize(512, 256)), @"2x screen image size must be exactly 512x256");

        NSImage *screen4x = [TX500ScreenRenderer renderScreenImageWithState:state
                                                                     theme:TX500ScreenThemeAmber
                                                                     scale:4.0
                                                                 pixelGrid:YES];
        Check(screen4x != nil, @"4x screen image must be non-nil");
        Check(NSEqualSizes(screen4x.size, NSMakeSize(1024, 512)), @"4x screen image size must be exactly 1024x512");

        // 6. Theme tests (Amber, Cool White, Green, OLED)
        TX500ScreenTheme themes[] = {
            TX500ScreenThemeAmber,
            TX500ScreenThemeCoolWhite,
            TX500ScreenThemeGreen,
            TX500ScreenThemeOLED
        };
        const char *themeNames[] = {"Amber", "CoolWhite", "Green", "OLED"};

        for (int i = 0; i < 4; i++) {
            NSImage *themeImg = [TX500ScreenRenderer renderScreenImageWithState:state
                                                                          theme:themes[i]
                                                                          scale:2.0
                                                                      pixelGrid:YES];
            Check(themeImg != nil, [NSString stringWithFormat:@"Theme %s image must render successfully", themeNames[i]]);

            NSData *png = [TX500ScreenRenderer pngDataForImage:themeImg];
            Check(png.length > 1000, [NSString stringWithFormat:@"Theme %s PNG export must produce valid data", themeNames[i]]);

            // Verify PNG magic bytes: 0x89 'P' 'N' 'G'
            const unsigned char *bytes = (const unsigned char *)png.bytes;
            Check(bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47,
                  [NSString stringWithFormat:@"Theme %s PNG must have valid PNG magic header", themeNames[i]]);

            NSString *outPath = [NSString stringWithFormat:@"build/tx500_screen_sample_%s.png", themeNames[i]];
            [png writeToFile:outPath atomically:YES];
        }

        // 7. Chassis Bezel Rendering test (840x440)
        NSImage *chassisImg = [TX500ScreenRenderer renderChassisImageWithState:state
                                                                         theme:TX500ScreenThemeCoolWhite
                                                                     pixelGrid:YES];
        Check(chassisImg != nil, @"Chassis bezel image must render successfully");
        Check(NSEqualSizes(chassisImg.size, NSMakeSize(840, 440)), @"Chassis bezel size must be 840x440");

        NSData *chassisPng = [TX500ScreenRenderer pngDataForImage:chassisImg];
        Check(chassisPng.length > 5000, @"Chassis PNG export must produce valid data");
        [chassisPng writeToFile:@"build/tx500_chassis_sample.png" atomically:YES];

        // 8. JPEG export test
        NSData *chassisJpg = [TX500ScreenRenderer jpegDataForImage:chassisImg compression:0.90];
        Check(chassisJpg.length > 2000, @"Chassis JPEG export must produce valid data");
        const unsigned char *jpgBytes = (const unsigned char *)chassisJpg.bytes;
        Check(jpgBytes[0] == 0xFF && jpgBytes[1] == 0xD8, @"JPEG must have valid SOI marker 0xFFD8");

        // 9. Transmit State Rendering test (RF Power & SWR meters)
        TX500ScreenState *txState = [state copy];
        txState.isTransmitting = YES;
        txState.rfPowerWatts = 10.0;
        txState.swr = 1.15;
        NSImage *txScreen = [TX500ScreenRenderer renderScreenImageWithState:txState
                                                                      theme:TX500ScreenThemeCoolWhite
                                                                      scale:2.0
                                                                  pixelGrid:YES];
        Check(txScreen != nil, @"TX mode screen must render successfully");

        // 10. Controller initialization and live components test
        TX500ScreenCaptureController *controller = [TX500ScreenCaptureController new];
        Check(controller != nil, @"TX500ScreenCaptureController must initialize");
        Check(controller.view != nil, @"Controller view must be created");
        Check(controller.currentTheme == TX500ScreenThemeCoolWhite, @"Default theme is CoolWhite matching real photo");
        Check(controller.showChassisBezel == YES, @"Default shows chassis bezel");

        // 11. Empty S-meter test (0 dots on silent radio)
        TX500ScreenState *emptySmState = [state copy];
        emptySmState.sMeterDots = 0;
        NSImage *emptySmImg = [TX500ScreenRenderer renderScreenImageWithState:emptySmState
                                                                        theme:TX500ScreenThemeCoolWhite
                                                                        scale:2.0
                                                                    pixelGrid:NO];
        Check(emptySmImg != nil, @"Empty S-meter screen must render successfully");

        // 12. Filter Preset switching test (FIL-2, FIL-3, FIL-4)
        TX500ScreenState *filState = [state copy];
        filState.filterNumber = 2;
        filState.filterName = @"FIL-2";
        filState.filterBandwidthString = @"2.40k";
        NSImage *filImg = [TX500ScreenRenderer renderScreenImageWithState:filState
                                                                    theme:TX500ScreenThemeCoolWhite
                                                                    scale:2.0
                                                                pixelGrid:NO];
        Check(filImg != nil, @"Switched filter screen must render successfully");

        // 13. Mode badge test: USB operatingMode maps to DIG badge
        TX500ScreenState *usbState = [state copy];
        usbState.operatingMode = @"USB";
        NSImage *usbImg = [TX500ScreenRenderer renderScreenImageWithState:usbState
                                                                    theme:TX500ScreenThemeCoolWhite
                                                                    scale:2.0
                                                                pixelGrid:NO];
        Check(usbImg != nil, @"USB to DIG mode screen must render successfully");

        // 14. Official logo asset test
        NSImage *logoAsset = [[NSImage alloc] initWithContentsOfFile:@"Resources/lab599_logo.png"];
        Check(logoAsset != nil, @"Resources/lab599_logo.png must exist and be loadable");
        Check(NSEqualSizes(logoAsset.size, NSMakeSize(648, 234)), @"Official logo dimensions must be 648x234");

        // 15. Pressed Button & Bezel Glow rendering tests
        NSImage *pressedBandImg = [TX500ScreenRenderer renderChassisImageWithState:state
                                                                             theme:TX500ScreenThemeCoolWhite
                                                                         pixelGrid:YES
                                                                     pressedButton:TX500ControlBandUp
                                                                         tuneAngle:0.0
                                                                       afGainAngle:0.0];
        Check(pressedBandImg != nil, @"Chassis with pressed BAND+ button must render successfully");
        Check(NSEqualSizes(pressedBandImg.size, NSMakeSize(840, 440)), @"Chassis size must remain 840x440");

        NSImage *pressedPwrImg = [TX500ScreenRenderer renderChassisImageWithState:state
                                                                            theme:TX500ScreenThemeAmber
                                                                        pixelGrid:YES
                                                                    pressedButton:TX500ControlPower
                                                                        tuneAngle:1.2
                                                                      afGainAngle:-0.5];
        Check(pressedPwrImg != nil, @"Chassis with pressed POWER button and knob angles must render successfully");

        // 16. Controller interactive BAND+ and BAND- stepping tests
        controller.screenState.frequencyHz = 14074000ULL; // 20m FT8
        [controller handleChassisControlPress:TX500ControlBandUp atChassisPoint:NSMakePoint(640, 335)];
        Check(controller.screenState.frequencyHz == 18100000ULL, @"BAND+ from 20m must advance to 17m (18.100 MHz)");

        [controller handleChassisControlPress:TX500ControlBandDown atChassisPoint:NSMakePoint(640, 305)];
        Check(controller.screenState.frequencyHz == 14074000ULL, @"BAND- from 17m must step down to 20m (14.074 MHz)");

        // 17. Controller interactive MODE and FILTER cycling tests
        controller.screenState.operatingMode = @"USB";
        [controller handleChassisControlPress:TX500ControlMode atChassisPoint:NSMakePoint(640, 275)];
        Check([controller.screenState.operatingMode isEqualToString:@"CW"], @"MODE cycle from USB must switch to CW");

        controller.screenState.filterNumber = 1;
        [controller handleChassisControlPress:TX500ControlFilter atChassisPoint:NSMakePoint(640, 245)];
        Check(controller.screenState.filterNumber == 2, @"FILTER cycle from FIL-1 must switch to FIL-2");

        // 18. Controller interactive TUNE VFO and AF GAIN knob deltas
        uint64_t beforeFreq = controller.screenState.frequencyHz;
        [controller handleTuneKnobDelta:1.0];
        Check(controller.screenState.frequencyHz == beforeFreq + 500ULL, @"TUNE knob delta +1.0 must increment frequency by 500 Hz");

        NSInteger beforeAF = controller.screenState.afGainLevel;
        [controller handleAFGainKnobDelta:1.0];
        Check(controller.screenState.afGainLevel == beforeAF + 5, @"AF GAIN knob delta +1.0 must increment gain by 5");

        // 19. Controller interactive Soft Keys (Top & Bottom)
        controller.screenState.preamp = NO;
        [controller handleChassisControlPress:TX500ControlTopKey1 atChassisPoint:NSMakePoint(120, 405)];
        Check(controller.screenState.preamp == YES, @"Top Key 1 must toggle Preamp to ON");

        [controller handleChassisControlPress:TX500ControlBottomKey2 atChassisPoint:NSMakePoint(250, 25)];
        Check(controller.screenState.split == YES, @"Bottom Key 2 must toggle SPLIT to ON");

        printf("ALL TX-500 SCREEN CAPTURE AND RENDERING TESTS PASSED SUCCESSFULLY! ✓\n");
    }
    return 0;
}
