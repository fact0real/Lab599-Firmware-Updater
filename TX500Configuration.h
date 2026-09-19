#import <Foundation/Foundation.h>
#import "Lab599SerialPort.h"

// Compatible with Settings 1.0 (.set) and TRXMem 1.03 (.mem).
@interface TXMemoryChannel : NSObject <NSCopying>
@property(nonatomic) uint32_t frequency;
@property(nonatomic) uint8_t mode; // ASCII 1=LSB, 2=USB/DIG, 3=CW, 4=FM, 5=AM, 7=CWR
@property(nonatomic) uint8_t preAtt; // ASCII 0=off, 1=PRE, 2=ATT
@end

NSString *TXValidateSettings(NSData *data);
NSArray<TXMemoryChannel *> *TXDecodeMemory(NSData *data, NSError **error);
NSData *TXEncodeMemory(NSArray<TXMemoryChannel *> *channels, NSError **error);
NSArray<TXMemoryChannel *> *TXEmptyMemory(void);
NSString *TXValidateChannel(TXMemoryChannel *channel);
NSData *TXSettingsReadCommand(NSUInteger index);
NSData *TXSettingsWriteCommand(NSUInteger index, uint8_t value);
NSInteger TXSettingsReplyValue(NSData *reply);
NSData *TXMemoryReadCommand(NSUInteger index);
NSData *TXMemoryWriteCommand(NSUInteger index, TXMemoryChannel *channel);
TXMemoryChannel *TXParseMemoryReply(NSData *reply, NSError **error);

typedef struct { double replyTimeout, settleDelay, memoryWriteDelay; BOOL setMemorySignals; } TXConfigurationOptions;
TXConfigurationOptions TXDefaultConfigurationOptions(void);
@interface TXConfigurationResult : NSObject
@property(nonatomic) BOOL success, cancelled;
@property(nonatomic) NSUInteger completed, attemptedWrites, verified;
@property(nonatomic, copy) NSString *message;
@property(nonatomic, copy) NSData *settings;
@property(nonatomic, copy) NSArray<TXMemoryChannel *> *channels;
@end
typedef void (^TXConfigurationProgress)(NSString *phase, NSUInteger done, NSUInteger total);
// Passing nil data/channels reads. Passing a complete validated backup writes,
// then reads back every byte/channel before reporting success.
TXConfigurationResult *TXSettingsTransfer(NSString *path, NSData *data, TXConfigurationOptions options,
    Lab599Cancellation *token, TXConfigurationProgress progress);
TXConfigurationResult *TXMemoryTransfer(NSString *path, NSArray<TXMemoryChannel *> *channels,
    TXConfigurationOptions options, Lab599Cancellation *token, TXConfigurationProgress progress);
