#import <Foundation/Foundation.h>

typedef struct {
    double responseTimeout;
    double writeTimeout;
    double settleDelay;
    double commandDelay;
} TXTimeSyncOptions;

FOUNDATION_EXPORT TXTimeSyncOptions TXDefaultTimeSyncOptions(void);
// ASCII, independent of the user's locale/calendar; no date or zone is sent.
FOUNDATION_EXPORT NSData *TXTimeSetCommand(NSDate *date, NSTimeZone *zone);
// Returns seconds since midnight, or -1 unless the entire 11-byte frame is valid.
FOUNDATION_EXPORT NSInteger TXParseTimeReply(NSData *frame);
FOUNDATION_EXPORT BOOL TXTimeReplyMatches(NSInteger sent, NSInteger received, double elapsed);

@interface TXTimeSyncResult : NSObject
@property(nonatomic) BOOL success;
@property(nonatomic) BOOL timeCommandSent;
@property(nonatomic) NSUInteger bytesSubmitted;
@property(nonatomic, copy) NSString *phase;
@property(nonatomic, copy) NSString *failure;
@property(nonatomic, copy) NSString *requestedTime;
@property(nonatomic, copy) NSString *radioTime;
@end

// Opens only the selected path, uses 9600/8N1, and closes it on every exit.
// Call off the main thread. A nil clock uses NSDate.date; injection is for tests.
FOUNDATION_EXPORT TXTimeSyncResult *TXSynchronizeTime(NSString *port, NSTimeZone *zone,
    TXTimeSyncOptions options, NSDate *(^clock)(void), void (^log)(NSString *));
