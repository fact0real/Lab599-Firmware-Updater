#import <Foundation/Foundation.h>

typedef struct {
    double acknowledgementTimeout;
    double writeTimeout;
    double settleDelay;
} TXTransferOptions;

FOUNDATION_EXPORT TXTransferOptions TXDefaultTransferOptions(void);
FOUNDATION_EXPORT NSString *TXFirmwareValidationError(NSData *firmware);
FOUNDATION_EXPORT NSString *TXFirmwareSHA256(NSData *firmware);

@interface TXTransferResult : NSObject
@property(nonatomic) BOOL success;
@property(nonatomic) BOOL headerAccepted;
@property(nonatomic) BOOL finalAcknowledged;
@property(nonatomic) NSUInteger bytesSubmitted;
@property(nonatomic, copy) NSString *phase;
@property(nonatomic, copy) NSString *failure;
@end

// Opens the explicitly selected port. It does not retry a failed transfer.
FOUNDATION_EXPORT TXTransferResult *TXFlashFirmware(
    NSData *firmware, NSString *port, TXTransferOptions options,
    void (^progress)(NSUInteger submitted, NSUInteger total),
    void (^log)(NSString *message));
