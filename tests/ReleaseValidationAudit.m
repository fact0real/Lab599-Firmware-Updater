#import "../Headers/TX500Transfer.h"

// A release-readiness check, not a transfer simulation. This file never calls
// TXFlashFirmware and never opens a serial port. Altered images exist only in
// memory; the supplied firmware file is left unchanged.
// Exit 2 means an intended release guardrail is currently missing.
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) {
            fprintf(stderr, "Usage: ReleaseValidationAudit path/to/mtrx1.30.00.fw\n");
            return 1;
        }
        NSData *original = [NSData dataWithContentsOfFile:@(argv[1])];
        if (![TXFirmwareSHA256(original) isEqualToString:
            @"2162fed7d27987507c8b412f3d38478c0a670a906a0c747578d7c975ad5a04ea"] ||
            TXFirmwareValidationError(original) != nil) {
            fprintf(stderr, "ERROR: Expected the verified Discovery 1.30.00 fixture.\n");
            return 1;
        }
        printf("PASS: Verified reference firmware is accepted.\n");

        NSMutableData *corrupted = [original mutableCopy];
        ((uint8_t *)corrupted.mutableBytes)[32] ^= 1;
        NSData *truncated = [original subdataWithRange:NSMakeRange(0, original.length / 2)];
        NSMutableData *extended = [original mutableCopy];
        [extended appendData:[NSData dataWithLength:16]];
        NSMutableData *fabricated = [NSMutableData dataWithLength:17];
        memcpy(fabricated.mutableBytes, "BL20", 4);
        NSArray *images = @[corrupted, truncated, extended, fabricated];
        NSArray *labels = @[@"Payload with one flipped bit", @"Truncated file (half length)",
                            @"File with 16 appended zero bytes", @"Fabricated 17-byte BL20 container"];
        NSUInteger gaps = 0;
        for (NSUInteger index = 0; index < images.count; index++) {
            NSString *rejection = TXFirmwareValidationError(images[index]);
            if (rejection == nil) {
                gaps++;
                printf("GAP: %s is accepted by the preflight validator.\n", [labels[index] UTF8String]);
            } else {
                printf("PASS: %s is rejected before serial access.\n", [labels[index] UTF8String]);
            }
        }
        printf("Release validation gaps: %lu. No serial device was accessed.\n", (unsigned long)gaps);
        return gaps ? 2 : 0;
    }
}
