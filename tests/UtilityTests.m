#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <util.h>
#import <poll.h>
#import <unistd.h>
#import <fcntl.h>
#import "../TX500CATTest.h"
#import "../TX500Configuration.h"

static void Check(BOOL ok, NSString *label) { if(!ok) { fprintf(stderr,"FAIL: %s\n",label.UTF8String); exit(1); } }
static NSData *ASCII(NSString *s) { return [s dataUsingEncoding:NSASCIIStringEncoding]; }
static NSString *String(NSData *d) { return [[NSString alloc] initWithData:d encoding:NSASCIIStringEncoding]; }
static NSString *Command(int fd, Lab599Cancellation *stop) {
    NSMutableData *d=[NSMutableData data]; double end=Lab599MonotonicTime()+2;
    while(!stop.cancelled && Lab599MonotonicTime()<end && d.length<100) {
        struct pollfd p={.fd=fd,.events=POLLIN};
        if(poll(&p,1,10)>0 && (p.revents&POLLIN)) {
            uint8_t b; if(read(fd,&b,1)==1) { [d appendBytes:&b length:1]; if(b==';') return String(d); }
        }
    }
    return nil;
}
static void Reply(int fd, NSString *text, BOOL split) {
    NSData *d=ASCII(text);
    if(split) { Check(write(fd,d.bytes,2)==2,@"fragment one"); usleep(2000);
        Check(write(fd,(const uint8_t *)d.bytes+2,d.length-2)==(ssize_t)d.length-2,@"fragment two"); }
    else Check(write(fd,d.bytes,d.length)==(ssize_t)d.length,@"emulator reply");
}
static TXConfigurationOptions Options(void) {
    TXConfigurationOptions o=TXDefaultConfigurationOptions(); o.settleDelay=.001;
    o.replyTimeout=.12; o.memoryWriteDelay=.001; o.setMemorySignals=NO; return o;
}
static NSMutableData *SettingsFixture(void) {
    NSMutableData *data=[NSMutableData dataWithLength:1024]; uint8_t *p=data.mutableBytes;
    for(NSUInteger i=0;i<1024;i++) p[i]=(uint8_t)(i*37); return data;
}
static NSArray *MemoryFixture(void) {
    NSArray *items=TXEmptyMemory();
    for(NSUInteger i=0;i<100;i++) {
        TXMemoryChannel *c=items[i]; if(i%9==0) continue;
        c.frequency=(uint32_t)(100000+i*500000); c.mode="123457"[i%6]; c.preAtt='0'+i%3;
    }
    return items;
}
static NSString *MemoryResponse(NSUInteger i, TXMemoryChannel *c) {
    return [NSString stringWithFormat:@"MR00%02lu%011u%c%c0000000000000000000000        ;",(unsigned long)i,c.frequency,c.mode,c.preAtt];
}
static void ConfigurationScenario(BOOL memory, BOOL writing, NSString *fault) {
    int master,slave; char path[256]; Check(openpty(&master,&slave,path,NULL,NULL)==0,@"pty");
    Lab599Cancellation *stop=[Lab599Cancellation new],*cancel=[Lab599Cancellation new];
    NSMutableData *device=writing ? [NSMutableData dataWithLength:1024] : SettingsFixture();
    NSMutableArray *bank=[(writing ? TXEmptyMemory() : MemoryFixture()) mutableCopy];
    __block NSUInteger reads=0,writes=0; __block BOOL masterClosed=NO;
    dispatch_semaphore_t done=dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{ @autoreleasepool {
        for(;;) {
            NSString *cmd=Command(master,stop); if(!cmd) break;
            struct termios t; Check(tcgetattr(slave,&t)==0 && cfgetispeed(&t)==B9600 &&
                (t.c_cflag&CSIZE)==CS8 && !(t.c_cflag&(PARENB|CSTOPB|CRTSCTS)) && !(t.c_iflag&(IXON|IXOFF)),@"9600/8N1/flow off");
            if([fault isEqual:@"disconnect"]) { close(master); masterClosed=YES; break; }
            if([fault isEqual:@"timeout"]) continue;
            if([cmd hasPrefix:@"XS"]) {
                unsigned address,value; int length=0;
                Check(sscanf(cmd.UTF8String,"XS%u %u;%n",&address,&value,&length)==2 && length==(int)cmd.length &&
                    address==1000+writes && value<=255,@"Exact ordered settings write command");
                ((uint8_t *)device.mutableBytes)[writes++]=(uint8_t)value;
                Reply(master,[fault isEqual:@"shortack"] ? @"?;" : @"XS0;",NO);
            } else if([cmd hasPrefix:@"XL"]) {
                Check([cmd isEqual:[NSString stringWithFormat:@"XL%lu;",(unsigned long)(1000+reads)]],@"Ordered settings read query");
                uint8_t value=((const uint8_t *)device.bytes)[reads++];
                if([fault isEqual:@"mismatch"]) value^=1;
                NSString *response=[NSString stringWithFormat:@"XL%03u;",value];
                if([fault isEqual:@"malformed"]) response=@"XL999;";
                if([fault isEqual:@"extra"]) response=@"XL001;extra";
                Reply(master,response,[fault isEqual:@"fragmented"]);
            } else if([cmd hasPrefix:@"MW"]) {
                Check(cmd.length==50 && [[cmd substringWithRange:NSMakeRange(4,2)] integerValue]==(NSInteger)writes,@"50-byte memory writes in order");
                Check([[cmd substringFromIndex:19] isEqual:@"0000000000000000000000        ;"],@"Exact original memory suffix");
                TXMemoryChannel *c=[TXMemoryChannel new]; c.frequency=(uint32_t)[[cmd substringWithRange:NSMakeRange(6,11)] longLongValue];
                c.mode=[cmd characterAtIndex:17];c.preAtt=[cmd characterAtIndex:18];bank[writes++]=c;
                // No ACK: original Memory utility only drains its output queue.
            } else if([cmd hasPrefix:@"MR"]) {
                Check([cmd isEqual:[NSString stringWithFormat:@"MR00%02lu;",(unsigned long)reads]],@"Ordered memory read query");
                TXMemoryChannel *c=[bank[reads] copy];
                if([fault isEqual:@"mismatch"]) c.frequency=123456;
                NSString *response=MemoryResponse(reads++,c);
                if([fault isEqual:@"malformed"]) response=[response stringByReplacingCharactersInRange:NSMakeRange(6,1) withString:@"X"];
                if([fault isEqual:@"short"]) response=[response substringToIndex:49];
                Reply(master,response,[fault isEqual:@"fragmented"]);
            } else Check(NO,[NSString stringWithFormat:@"Unexpected radio command %@",cmd]);
        }
        dispatch_semaphore_signal(done);
    }});
    TXConfigurationProgress progress=^(NSString *phase,NSUInteger count,NSUInteger total){
        if([fault isEqual:@"cancel"] && count==8) cancel.cancelled=YES;
    };
    TXConfigurationResult *r=memory ? TXMemoryTransfer(@(path),writing ? MemoryFixture() : nil,Options(),cancel,progress) :
        TXSettingsTransfer(@(path),writing ? SettingsFixture() : nil,Options(),cancel,progress);
    stop.cancelled=YES;
    Check(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC))==0,@"emulator exits");
    BOOL success=!fault.length || [fault isEqual:@"fragmented"];
    Check(r.success==success,[NSString stringWithFormat:@"%@ %@: %@",memory ? @"Memory" : @"Settings",fault,r.message]);
    if(success) {
        NSUInteger count=memory ? 100 : 1024; Check(reads==count && writes==(writing ? count : 0),@"Full bank transferred once");
        Check(!writing || r.verified==count,@"Read-back all writes");
        if(memory) Check([TXEncodeMemory(r.channels,NULL) isEqual:TXEncodeMemory(MemoryFixture(),NULL)],@"memory roundtrip");
        else Check([r.settings isEqual:SettingsFixture()],@"all settings bytes roundtrip");
    } else { Check(r.message.length>0 && !r.settings && !r.channels,@"No partial backup presented as complete"); }
    if([fault isEqual:@"cancel"]) Check(r.cancelled && r.completed==8 && reads+writes==8,@"Cancellation stops at item boundary without extra commands");
    if(writing && !success) Check(r.attemptedWrites>0 && [r.message containsString:@"may have changed"],@"Partial write is disclosed");
    if(!masterClosed) {
        // TIOCEXCL should be released by the worker (Darwin keeps the original pty
        // slave open, so clearing exclusive here is only test cleanup).
        close(master);
    }
    close(slave);
    printf("PASS: %s %s %s\n",memory ? "Memory" : "Settings",writing ? "write + verify" : "read",fault.UTF8String);
}
static void CATScenario(NSArray<NSString *> *replies, BOOL cancel, BOOL fragmented) {
    int master,slave;char path[256];Check(openpty(&master,&slave,path,NULL,NULL)==0,@"CAT pty");
    Lab599Cancellation *token=[Lab599Cancellation new],*stop=[Lab599Cancellation new];
    __block NSUInteger queries=0;
    dispatch_semaphore_t done=dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{ @autoreleasepool {
        for(NSString *reply in replies) {
            NSString *cmd=Command(master,stop); if(!cmd) break; Check([cmd isEqual:@"ID;"],@"CAT sends only ID;"); queries++;
            if(reply.length) Reply(master,reply,fragmented);
            if(cancel) { usleep(20000);token.cancelled=YES;break; }
        }
        dispatch_semaphore_signal(done);
    }});
    TXCATOptions o=TXDefaultCATOptions(); o.maximumChecks=replies.count;o.responseTimeout=.15;o.cycleInterval=.03;o.settleDelay=.001;
    double started=Lab599MonotonicTime();TXCATSummary *r=TXRunCATTest(@(path),o,token,nil,nil);
    stop.cancelled=YES;Check(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC))==0,@"CAT emulator stops");
    if(cancel) Check(r.cancelled && Lab599MonotonicTime()-started<.25 && queries==1,@"Bounded CAT cancellation");
    else {
        NSUInteger passed=0;for(NSString *reply in replies) if([@[@"ID019;",@"ID500;",@"ID501;",@"ID502;",@"ID505;"] containsObject:reply]) passed++;
        Check(r.checks==replies.count && r.passed==passed && r.failed==replies.count-passed && !r.connectionFailed,@"CAT counts and recovery");
    }
    close(master);close(slave);printf("PASS: CAT %s (%lu queries)\n",cancel ? "cancel" : "response sequence",(unsigned long)queries);
}
int main(void) { @autoreleasepool {
    int master,slave;char path[256];Check(openpty(&master,&slave,path,NULL,NULL)==0,@"transport pty");close(slave);
    NSError *serialError=nil;
    Lab599SerialPort *owner=[Lab599SerialPort openPath:@(path) speed:B9600 error:&serialError];
    Check(owner!=nil,@"transport opens");
    int other=open(path,O_RDWR|O_NOCTTY|O_NONBLOCK);
    // This macOS PTY driver accepts TIOCEXCL but permits another open even
    // for a non-root process. Do not claim physical-driver exclusivity from
    // a PTY test. The application still requires TIOCEXCL to succeed.
    if(other>=0) { close(other); printf("NOTE: Host PTY does not enforce TIOCEXCL; physical-driver exclusivity remains unverified.\n"); }
    else Check(errno==EBUSY,@"exclusive port reports busy");
    double start=Lab599MonotonicTime();
    Check(![owner readMaximum:6 timeout:.03 cancellation:nil error:&serialError] && serialError.code==Lab599SerialTimeout && Lab599MonotonicTime()-start<.15,@"bounded transport read");
    [owner close];[owner close];
    other=open(path,O_RDWR|O_NOCTTY|O_NONBLOCK);Check(other>=0,@"port released after close");close(other);close(master);
    printf("PASS: Serial configuration, bounded reads and release\n");
    Check([TXSettingsReadCommand(0) isEqual:ASCII(@"XL1000;")] && [TXSettingsReadCommand(1023) isEqual:ASCII(@"XL2023;")],@"Settings address endpoints");
    Check([TXSettingsWriteCommand(0,0) isEqual:ASCII(@"XS1000 0;")] && [TXSettingsWriteCommand(1023,255) isEqual:ASCII(@"XS2023 255;")],@"Unsigned decimal settings fixtures");
    Check(!TXSettingsReadCommand(1024) && !TXMemoryReadCommand(100),@"Address range checks");
    Check(TXSettingsReplyValue(ASCII(@"XL000;"))==0 && TXSettingsReplyValue(ASCII(@"XL255;"))==255 && TXSettingsReplyValue(ASCII(@"XL256;"))==-1 && TXSettingsReplyValue(ASCII(@"XL-01;"))==-1,@"Strict settings payload");
    TXMemoryChannel *channel=[TXMemoryChannel new];channel.frequency=7100000;channel.mode='1';channel.preAtt='2';
    Check([TXMemoryWriteCommand(99,channel) isEqual:ASCII(@"MW009900007100000120000000000000000000000        ;")],@"Independent 50-byte wire fixture");
    NSMutableArray *bank=[TXEmptyMemory() mutableCopy];bank[0]=channel;NSData *encoded=TXEncodeMemory(bank,NULL);
    const uint8_t fixture[]={0x60,0x56,0x6c,0x00,0x31,0x32};
    Check(encoded.length==600 && memcmp(encoded.bytes,fixture,6)==0,@"Independent little-endian .mem fixture");
    Check([TXEncodeMemory(TXDecodeMemory(encoded,NULL),NULL) isEqual:encoded],@"File roundtrip");
    for(NSUInteger n=599;n<=601;n+=2) Check(!TXDecodeMemory([NSMutableData dataWithLength:n],NULL),@"Wrong memory size rejected");
    Check(TXValidateSettings([NSMutableData dataWithLength:1023])!=nil && TXValidateSettings([NSMutableData dataWithLength:1025])!=nil,@"Wrong settings size rejected");
    NSMutableData *corrupt=[encoded mutableCopy];((uint8_t *)corrupt.mutableBytes)[4]='9';Check(!TXDecodeMemory(corrupt,NULL),@"Unknown active mode rejected");
    channel.frequency=99999;Check(TXValidateChannel(channel)!=nil,@"Frequency low bound");channel.frequency=56000001;Check(TXValidateChannel(channel)!=nil,@"Frequency high bound");
    printf("PASS: Binary formats, command fixtures, input validation\n");
    for(NSString *s in @[@"ID019;",@"ID500;",@"ID501;",@"ID502;",@"ID505;"]) Check(TXClassifyCATReply(ASCII(s))==TXCATOK,@"Original ID accepted");
    Check(TXClassifyCATReply(ASCII(@"ID503;"))==TXCATUnexpectedID && TXClassifyCATReply(ASCII(@"ID;"))==TXCATWrongLength,@"Original CAT error distinctions");
    CATScenario(@[@"ID019;",@"ID500;",@"ID501;",@"ID502;",@"ID505;"],NO,YES);
    CATScenario(@[@"",@"ID;",@"ID503;",@"ID500;extra",@"ID500;"],NO,NO);
    CATScenario(@[@""],YES,NO);
    for(NSNumber *mem in @[@NO,@YES]) {
        ConfigurationScenario(mem.boolValue,NO,@"fragmented");ConfigurationScenario(mem.boolValue,YES,@"");
        ConfigurationScenario(mem.boolValue,YES,@"mismatch");ConfigurationScenario(mem.boolValue,NO,@"malformed");
        ConfigurationScenario(mem.boolValue,NO,@"timeout");ConfigurationScenario(mem.boolValue,NO,@"disconnect");
        ConfigurationScenario(mem.boolValue,NO,@"cancel");ConfigurationScenario(mem.boolValue,YES,@"cancel");
    }
    ConfigurationScenario(NO,YES,@"shortack");ConfigurationScenario(NO,NO,@"extra");ConfigurationScenario(YES,NO,@"short");
    Lab599Cancellation *cancel=[Lab599Cancellation new];cancel.cancelled=YES;
    Check(TXSettingsTransfer(@"/does-not-exist",nil,Options(),cancel,nil).cancelled,@"Cancel before port access");
    Check(!TXMemoryTransfer(@"/does-not-exist",MemoryFixture(),Options(),nil,nil).success,@"Missing port");
    TXConfigurationOptions invalid=Options();invalid.replyTimeout=0;
    Check([TXSettingsTransfer(@"/does-not-exist",nil,invalid,nil,nil).message containsString:@"timing"],@"Invalid timeout rejected before I/O");
    printf("All Utility tests passed. Only pseudo-terminals were used; no physical radio was accessed.\n");
}return 0;}
