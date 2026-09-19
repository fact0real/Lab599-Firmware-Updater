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

// Transceiver Live State Snapshot
@interface TXRadioState : NSObject <NSCopying>
@property(nonatomic) uint64_t frequencyHz;
@property(nonatomic, copy) NSString *frequencyDisplay; // e.g. "14.074.000 MHz"
@property(nonatomic, copy) NSString *operatingMode;    // e.g. "USB", "LSB", "CW", "DIG", "FM", "AM"
@property(nonatomic) NSInteger modeCode;               // 1-7
@property(nonatomic) double rfPowerWatts;              // 1.0 - 10.0
@property(nonatomic) NSInteger filterNumber;           // 1, 2, 3
@property(nonatomic) BOOL preampOn;
@property(nonatomic) BOOL attenuatorOn;
@property(nonatomic) double voltage;                   // e.g. 13.8 V
@property(nonatomic) NSInteger sMeterDots;             // 0-30
@property(nonatomic, copy) NSString *modelID;          // e.g. "ID019 (Lab599 TX-500)"
@property(nonatomic) BOOL isTransmitting;
@property(nonatomic, copy) NSString *rawIFReply;
@property(nonatomic, copy) NSString *rawFAReply;
@property(nonatomic, copy) NSString *rawMDReply;
@property(nonatomic, copy) NSString *rawPCReply;
@end

// Sends only ID; and accepts exactly the five replies in official TestCAT 1.1.
// update receives independent snapshots, safe to hand to the main queue.
FOUNDATION_EXPORT TXCATSummary *TXRunCATTest(NSString *path, TXCATOptions options,
    Lab599Cancellation *token, void (^update)(TXCATSummary *), void (^log)(NSString *));

// Interactive Command & Control API
FOUNDATION_EXPORT NSString *TXExecuteCATCommand(NSString *path, NSString *command,
    NSTimeInterval timeout, double *roundtripMs, NSError **error);

FOUNDATION_EXPORT TXRadioState *TXReadRadioState(NSString *path,
    NSTimeInterval timeout, NSError **error);

FOUNDATION_EXPORT BOOL TXSetRadioFrequency(NSString *path, uint64_t freqHz, NSError **error);
FOUNDATION_EXPORT BOOL TXSetRadioMode(NSString *path, NSInteger modeCode, NSError **error);
FOUNDATION_EXPORT BOOL TXSetRadioPower(NSString *path, double watts, NSError **error);
FOUNDATION_EXPORT BOOL TXSetRadioPreamp(NSString *path, BOOL on, NSError **error);
FOUNDATION_EXPORT BOOL TXSetRadioAttenuator(NSString *path, BOOL on, NSError **error);
FOUNDATION_EXPORT BOOL TXSetRadioFilter(NSString *path, NSInteger filterNumber, NSError **error);

