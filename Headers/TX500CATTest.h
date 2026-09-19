#import <Foundation/Foundation.h>
#import "Lab599SerialPort.h"

typedef NS_ENUM(NSInteger, TXCATCode) {
    TXCATOK = 0, TXCATPortError = 1, TXCATNoReply = 2,
    TXCATWrongLength = 3, TXCATUnexpectedID = 4
};
typedef struct {
    double responseTimeout;
    double cycleInterval;
    double settleDelay;
    NSUInteger maximumChecks; // 0: repeat until cancelled; 1: single check
} TXCATOptions;

FOUNDATION_EXPORT TXCATOptions TXDefaultCATOptions(void);
FOUNDATION_EXPORT TXCATCode TXClassifyCATReply(NSData *reply);

@interface TXCATSummary : NSObject <NSCopying>
@property(nonatomic) NSUInteger checks;
@property(nonatomic) NSUInteger passed;
@property(nonatomic) NSUInteger failed;
@property(nonatomic) BOOL cancelled;
@property(nonatomic) BOOL connectionFailed;
@property(nonatomic) TXCATCode lastCode;
@property(nonatomic) double responseMilliseconds;
@property(nonatomic, copy) NSString *lastReply;
@property(nonatomic, copy) NSString *message;
@end

// Sends only ID; and accepts exactly the five replies in official TestCAT 1.1.
// update receives independent snapshots, safe to hand to the main queue.
FOUNDATION_EXPORT TXCATSummary *TXRunCATTest(NSString *path, TXCATOptions options,
    Lab599Cancellation *token, void (^update)(TXCATSummary *), void (^log)(NSString *));
