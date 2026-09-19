#import <Foundation/Foundation.h>
#import "../Headers/TX500TelemetryEngine.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) {
            fprintf(stderr, "usage: TelemetryLiveProbe /dev/cu.device\n");
            return 2;
        }

        NSString *path = [NSString stringWithUTF8String:argv[1]];
        TX500TelemetryEngine *engine = [TX500TelemetryEngine new];
        __block TXTelemetryData *received = nil;
        __block NSString *lastStatus = @"";
        [engine startWithPort:path interval:0.25 update:^(TXTelemetryData *data) {
            if (data.frequencyValid && data.modeValid && data.txStateValid &&
                data.sMeterValid && data.rfPowerValid && data.voltageValid) {
                received = data;
            }
        } status:^(NSString *status, BOOL connected) {
            (void)connected;
            lastStatus = status;
        }];

        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:6.0];
        while (!received && [deadline timeIntervalSinceNow] > 0) {
            [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode
                                  beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        [engine stop];

        if (!received) {
            fprintf(stderr, "FAIL: %s\n", lastStatus.UTF8String);
            return 1;
        }
        printf("PASS: %.6f MHz, %s, %s, SM=%ld/30, PC=%.1f W, VL=%.1f V, current=N/A, temp=N/A\n",
               (double)received.frequencyHz / 1000000.0,
               received.operatingMode.UTF8String,
               received.isTransmitting ? "TX" : "RX",
               (long)received.sMeterDots,
               received.rfPowerWatts,
               received.voltage);
    }
    return 0;
}
