#import <Foundation/Foundation.h>
#import <termios.h>

FOUNDATION_EXPORT NSString *const Lab599SerialErrorDomain;
typedef NS_ENUM(NSInteger, Lab599SerialError) {
    Lab599SerialCancelled = 1,
    Lab599SerialTimeout,
    Lab599SerialIOError
};

// Cooperative cancellation shared between the UI and a serial worker.
@interface Lab599Cancellation : NSObject
@property(atomic) BOOL cancelled;
@end

// A single-owner, bounded, nonblocking transport for CAT modules.
// The owner must call close on its worker before giving another module the port.
@interface Lab599SerialPort : NSObject
+ (instancetype)openPath:(NSString *)path speed:(speed_t)speed error:(NSError **)error;
- (BOOL)discardInput:(NSError **)error;
- (BOOL)assertDTRAndRTS:(NSError **)error;
- (BOOL)writeData:(NSData *)data timeout:(double)timeout cancellation:(Lab599Cancellation *)token error:(NSError **)error;
- (NSData *)readMaximum:(NSUInteger)maximum timeout:(double)timeout cancellation:(Lab599Cancellation *)token error:(NSError **)error;
- (void)close;
@end

FOUNDATION_EXPORT double Lab599MonotonicTime(void);
FOUNDATION_EXPORT BOOL Lab599Pause(double seconds, Lab599Cancellation *token);
