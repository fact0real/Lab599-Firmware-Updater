#import "TX500Configuration.h"
#import <math.h>

static BOOL Fail(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"Lab599Configuration" code:1
        userInfo:@{NSLocalizedDescriptionKey:message}];
    return NO;
}
@implementation TXMemoryChannel
- (instancetype)init { if ((self = [super init])) { _mode = '0'; _preAtt = '0'; } return self; }
- (id)copyWithZone:(NSZone *)zone {
    TXMemoryChannel *c = [TXMemoryChannel new]; c.frequency = self.frequency;
    c.mode = self.mode; c.preAtt = self.preAtt; return c;
}
@end
@implementation TXConfigurationResult
@end
NSString *TXValidateSettings(NSData *data) {
    return data.length == 1024 ? nil : @"A Lab599 .set backup must contain exactly 1024 bytes.";
}
NSString *TXValidateChannel(TXMemoryChannel *c) {
    if (!c) return @"Missing memory channel.";
    if (!c.frequency) return nil; // Empty slots in original files may have unused mode bytes.
    if (c.frequency < 100000 || c.frequency > 56000000) return @"Frequency must be 100000–56000000 Hz, or zero for an empty channel.";
    if (!strchr("123457", c.mode) || !c.mode) return @"Unsupported memory mode.";
    if (c.preAtt < '0' || c.preAtt > '2') return @"PreAtt must be Off, PRE or ATT.";
    return nil;
}
NSArray<TXMemoryChannel *> *TXEmptyMemory(void) {
    NSMutableArray *items = [NSMutableArray array];
    for (int i=0; i<100; i++) [items addObject:[TXMemoryChannel new]];
    return items;
}
NSArray<TXMemoryChannel *> *TXDecodeMemory(NSData *data, NSError **error) {
    if (data.length != 600) { Fail(error, @"A Lab599 .mem file must contain exactly 600 bytes (100 channels)."); return nil; }
    const uint8_t *p = data.bytes;
    NSMutableArray *items = [NSMutableArray array];
    for (NSUInteger i=0; i<100; i++, p+=6) {
        TXMemoryChannel *c = [TXMemoryChannel new];
        c.frequency = (uint32_t)p[0] | ((uint32_t)p[1]<<8) | ((uint32_t)p[2]<<16) | ((uint32_t)p[3]<<24);
        c.mode = p[4]; c.preAtt = p[5];
        NSString *problem = TXValidateChannel(c);
        if (problem) { Fail(error, [NSString stringWithFormat:@"Channel %02lu: %@", (unsigned long)i, problem]); return nil; }
        [items addObject:c];
    }
    return items;
}
NSData *TXEncodeMemory(NSArray<TXMemoryChannel *> *channels, NSError **error) {
    if (channels.count != 100) { Fail(error, @"Exactly 100 channels are required."); return nil; }
    NSMutableData *data = [NSMutableData dataWithLength:600]; uint8_t *p = data.mutableBytes;
    for (TXMemoryChannel *c in channels) {
        NSString *problem = TXValidateChannel(c); if (problem) { Fail(error, problem); return nil; }
        for (unsigned j=0; j<4; j++) p[j] = (c.frequency >> (8*j)) & 255;
        p[4] = c.mode; p[5] = c.preAtt; p+=6;
    }
    return data;
}
static NSData *ASCII(NSString *s) { return [s dataUsingEncoding:NSASCIIStringEncoding]; }
NSData *TXSettingsReadCommand(NSUInteger index) {
    return index<1024 ? ASCII([NSString stringWithFormat:@"XL%lu;", (unsigned long)index+1000]) : nil;
}
NSData *TXSettingsWriteCommand(NSUInteger index, uint8_t value) {
    return index<1024 ? ASCII([NSString stringWithFormat:@"XS%lu %u;", (unsigned long)index+1000, value]) : nil;
}
static long long Decimal(const uint8_t *p, NSUInteger n) {
    long long value=0;
    for (NSUInteger i=0; i<n; i++) { if (p[i]<'0' || p[i]>'9') return -1; value=value*10+p[i]-'0'; }
    return value;
}
NSInteger TXSettingsReplyValue(NSData *reply) {
    if (reply.length!=6) return -1;
    // Original client reads decimal bytes at offsets 2..4. It does not inspect
    // the framing bytes; do not invent undocumented ACK/header values.
    long long n=Decimal((const uint8_t *)reply.bytes+2,3);
    return n>=0 && n<=255 ? (NSInteger)n : -1;
}
NSData *TXMemoryReadCommand(NSUInteger index) {
    return index<100 ? ASCII([NSString stringWithFormat:@"MR00%02lu;", (unsigned long)index]) : nil;
}
NSData *TXMemoryWriteCommand(NSUInteger index, TXMemoryChannel *c) {
    if (index>=100 || TXValidateChannel(c)) return nil;
    return ASCII([NSString stringWithFormat:@"MW00%02lu%011u%c%c0000000000000000000000        ;",
        (unsigned long)index, c.frequency, c.frequency ? c.mode : '0', c.frequency ? c.preAtt : '0']);
}
TXMemoryChannel *TXParseMemoryReply(NSData *reply, NSError **error) {
    if (reply.length != 50) { Fail(error,@"Expected a 50-byte memory response."); return nil; }
    const uint8_t *p=reply.bytes; long long hz=Decimal(p+6,11);
    if (hz<0 || hz>UINT32_MAX) { Fail(error,@"Invalid frequency in the memory response."); return nil; }
    TXMemoryChannel *c=[TXMemoryChannel new]; c.frequency=(uint32_t)hz; c.mode=p[17]; c.preAtt=p[18];
    NSString *problem=TXValidateChannel(c); if (problem) { Fail(error,problem); return nil; }
    if (!c.frequency) { c.mode='0'; c.preAtt='0'; }
    return c;
}
TXConfigurationOptions TXDefaultConfigurationOptions(void) {
    return (TXConfigurationOptions){.replyTimeout=1.0,.settleDelay=0.1,.memoryWriteDelay=0.1,.setMemorySignals=YES};
}
static BOOL ValidOptions(TXConfigurationOptions o) {
    return isfinite(o.replyTimeout) && o.replyTimeout>0 && o.replyTimeout<=10 &&
        isfinite(o.settleDelay) && o.settleDelay>=0 && o.settleDelay<=10 &&
        isfinite(o.memoryWriteDelay) && o.memoryWriteDelay>=0 && o.memoryWriteDelay<=10;
}
static NSData *ReadExact(Lab599SerialPort *port, NSUInteger size, TXConfigurationOptions o,
                         Lab599Cancellation *token, NSError **error) {
    NSMutableData *data=[NSMutableData data]; double deadline=Lab599MonotonicTime()+o.replyTimeout;
    while (data.length<size) {
        double left=deadline-Lab599MonotonicTime();
        if (left<=0) { Fail(error,[NSString stringWithFormat:@"Incomplete response (%lu/%lu bytes).",(unsigned long)data.length,(unsigned long)size]); return nil; }
        // One extra byte detects an overlong frame instead of silently truncating.
        NSData *chunk=[port readMaximum:size+1-data.length timeout:left cancellation:token error:error];
        if (!chunk) return nil;
        [data appendData:chunk];
        if (data.length>size) { Fail(error,@"Unexpected extra serial data. Close other CAT applications."); return nil; }
    }
    return data;
}
static NSData *Exchange(Lab599SerialPort *port, NSData *command, NSUInteger size,
                         TXConfigurationOptions o, Lab599Cancellation *token, NSError **error) {
    if (![port writeData:command timeout:o.replyTimeout cancellation:token error:error]) return nil;
    return ReadExact(port,size,o,token,error);
}
static void Finish(TXConfigurationResult *r, NSError *error, Lab599Cancellation *token, NSString *kind, BOOL writing) {
    r.cancelled=token.cancelled;
    r.success=!error && !r.cancelled;
    if (r.success) r.message=writing ? [NSString stringWithFormat:@"%@ written and read-back verified.",kind] : [NSString stringWithFormat:@"%@ read successfully.",kind];
    else r.message=[NSString stringWithFormat:@"%@ %@%@",r.cancelled ? @"Stopped." : @"Transfer failed.",
        error.localizedDescription ?: @"",r.attemptedWrites ? [NSString stringWithFormat:@" Up to %lu items may have changed; %lu read-back checks passed. Read the radio again before retrying.",(unsigned long)r.attemptedWrites,(unsigned long)r.verified] : @""];
}
TXConfigurationResult *TXSettingsTransfer(NSString *path, NSData *data, TXConfigurationOptions o,
    Lab599Cancellation *token, TXConfigurationProgress progress) {
    TXConfigurationResult *r=[TXConfigurationResult new]; NSError *error=nil;
    if (!token) token=[Lab599Cancellation new];
    if (!progress) progress=^(NSString *phase,NSUInteger done,NSUInteger total){};
    data=[data copy];
    NSString *problem=data ? TXValidateSettings(data) : nil;
    if (problem || !ValidOptions(o)) { r.message=problem ?: @"Invalid configuration timing options."; return r; }
    if (token.cancelled) { Finish(r,nil,token,@"Settings",data!=nil); return r; }
    Lab599SerialPort *port=[Lab599SerialPort openPath:path speed:B9600 error:&error];
    NSMutableData *received=[NSMutableData dataWithLength:1024]; uint8_t *bytes=received.mutableBytes;
    if (port && Lab599Pause(o.settleDelay,token) && [port discardInput:&error]) {
        if (data) for (NSUInteger i=0; i<1024 && !token.cancelled; i++) {
            r.attemptedWrites=i+1;
            if (!Exchange(port,TXSettingsWriteCommand(i,((const uint8_t *)data.bytes)[i]),4,o,token,&error)) break;
            r.completed=i+1; progress(@"Writing settings",i+1,1024);
        }
        if (!error && !token.cancelled) for (NSUInteger i=0; i<1024 && !token.cancelled; i++) {
            NSData *reply=Exchange(port,TXSettingsReadCommand(i),6,o,token,&error);
            if (!reply) break;
            NSInteger value=TXSettingsReplyValue(reply);
            if (value<0) { Fail(&error,[NSString stringWithFormat:@"Invalid settings response at byte %lu.",(unsigned long)i]); break; }
            bytes[i]=(uint8_t)value;
            if (data && bytes[i]!=((const uint8_t *)data.bytes)[i]) { Fail(&error,[NSString stringWithFormat:@"Settings read-back mismatch at byte %lu.",(unsigned long)i]); break; }
            if (data) r.verified=i+1; else r.completed=i+1;
            progress(data ? @"Verifying settings" : @"Reading settings",i+1,1024);
        }
    }
    [port close]; Finish(r,error,token,@"Settings",data!=nil);
    if (r.success) r.settings=received;
    return r;
}
TXConfigurationResult *TXMemoryTransfer(NSString *path, NSArray<TXMemoryChannel *> *channels,
    TXConfigurationOptions o, Lab599Cancellation *token, TXConfigurationProgress progress) {
    TXConfigurationResult *r=[TXConfigurationResult new]; NSError *error=nil;
    if (!token) token=[Lab599Cancellation new];
    if (!progress) progress=^(NSString *phase,NSUInteger done,NSUInteger total){};
    NSData *snapshot=channels ? TXEncodeMemory(channels,&error) : nil;
    channels=snapshot ? TXDecodeMemory(snapshot,&error) : nil;
    if (error || !ValidOptions(o)) { r.message=error.localizedDescription ?: @"Invalid configuration timing options."; return r; }
    if (token.cancelled) { Finish(r,nil,token,@"Memory",channels!=nil); return r; }
    Lab599SerialPort *port=[Lab599SerialPort openPath:path speed:B9600 error:&error];
    NSMutableArray *received=[NSMutableArray array];
    if (port && (!o.setMemorySignals || [port assertDTRAndRTS:&error]) &&
        Lab599Pause(o.settleDelay,token) && [port discardInput:&error]) {
        if (channels) for (NSUInteger i=0; i<100 && !token.cancelled; i++) {
            r.attemptedWrites=i+1;
            if (![port writeData:TXMemoryWriteCommand(i,channels[i]) timeout:o.replyTimeout cancellation:token error:&error]) break;
            // Original waits for the output queue to drain, not a radio ACK.
            // Pace writes, then verify with MR reads on the same connection.
            if (!Lab599Pause(o.memoryWriteDelay,token)) break;
            r.completed=i+1; progress(@"Writing memory",i+1,100);
        }
        if (!error && !token.cancelled) for (NSUInteger i=0; i<100 && !token.cancelled; i++) {
            NSData *reply=Exchange(port,TXMemoryReadCommand(i),50,o,token,&error);
            if (!reply) break;
            TXMemoryChannel *c=TXParseMemoryReply(reply,&error);
            if (!c) break;
            if (channels) {
                TXMemoryChannel *expected=channels[i];
                if (c.frequency!=expected.frequency || (c.frequency && (c.mode!=expected.mode || c.preAtt!=expected.preAtt))) {
                    Fail(&error,[NSString stringWithFormat:@"Memory read-back mismatch at channel %02lu.",(unsigned long)i]); break;
                }
                r.verified=i+1;
            } else r.completed=i+1;
            [received addObject:c]; progress(channels ? @"Verifying memory" : @"Reading memory",i+1,100);
        }
    }
    [port close]; Finish(r,error,token,@"Memory",channels!=nil);
    if (r.success) r.channels=received;
    return r;
}
