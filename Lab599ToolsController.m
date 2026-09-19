#import "Lab599ToolsController.h"
#import "TX500CATTest.h"
#import "TX500Configuration.h"
#import "TX500Transfer.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface Lab599ToolsController ()
@property(nonatomic, strong, readwrite) NSView *view;
@property(nonatomic, strong) NSArray<NSView *> *panels;
@property(nonatomic, strong) NSMutableArray<NSControl *> *controls;
@property(nonatomic, strong) NSButton *catOnce, *catStart, *stop, *settingsRead, *settingsWrite, *settingsSave;
@property(nonatomic, strong) NSButton *memoryRead, *memoryWrite, *memorySave;
@property(nonatomic, strong) NSTextField *catResult, *catCounts, *settingsInfo, *memoryInfo, *frequency;
@property(nonatomic, strong) NSPopUpButton *mode, *preAtt;
@property(nonatomic, strong) NSTableView *table;
@property(nonatomic, strong) Lab599Cancellation *token;
@property(nonatomic, copy) NSData *settingsData;
@property(nonatomic, strong) NSMutableArray<TXMemoryChannel *> *channels;
@property(nonatomic, copy) NSString *settingsSource;
@property(nonatomic) BOOL busy, hasPorts, settingsDirty, memoryDirty, memoryReady;
@property(nonatomic) NSInteger tool;
@end

@implementation Lab599ToolsController
static NSTextField *Label(NSString *text) {
    NSTextField *label=[NSTextField wrappingLabelWithString:text];
    label.textColor=NSColor.secondaryLabelColor; return label;
}
static NSStackView *Stack(NSArray<NSView *> *views, BOOL vertical) {
    NSStackView *s=[NSStackView stackViewWithViews:views];
    s.orientation=vertical ? NSUserInterfaceLayoutOrientationVertical : NSUserInterfaceLayoutOrientationHorizontal;
    s.alignment=vertical ? NSLayoutAttributeLeading : NSLayoutAttributeCenterY;
    s.spacing=10; return s;
}
- (NSButton *)button:(NSString *)title action:(SEL)action tag:(NSInteger)tag {
    NSButton *b=[NSButton buttonWithTitle:title target:self action:action]; b.tag=tag;
    [self.controls addObject:b]; return b;
}
- (instancetype)init {
    if (!(self=[super init])) return nil;
    self.controls=[NSMutableArray array]; self.channels=[TXEmptyMemory() mutableCopy];
    self.view=[NSView new]; self.view.translatesAutoresizingMaskIntoConstraints=NO;
    self.catResult=Label(@"Ready. Tests the radio identification command used by Lab599 TestCAT 1.1.");
    self.catResult.font=[NSFont systemFontOfSize:17 weight:NSFontWeightMedium];
    self.catCounts=Label(@"Checks: 0    Passed: 0    Failed: 0");
    self.catCounts.font=[NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightRegular];
    self.catOnce=[self button:@"Test Once" action:@selector(startCAT:) tag:1];
    self.catStart=[self button:@"Start Continuous Test" action:@selector(startCAT:) tag:0];
    NSView *cat=Stack(@[self.catResult,self.catCounts,Stack(@[self.catOnce,self.catStart],NO),
        Label(@"Shows the returned ID, response time and error count. This test does not change frequency or activate transmission.")],YES);

    self.settingsInfo=Label(@"No settings backup loaded. Read the radio or open an existing .set file.");
    self.settingsRead=[self button:@"Read Radio" action:@selector(readRadio:) tag:1];
    self.settingsWrite=[self button:@"Restore to Radio…" action:@selector(writeRadio:) tag:1];
    self.settingsSave=[self button:@"Save .set…" action:@selector(saveBackup:) tag:1];
    NSView *settings=Stack(@[Label(@"Back up and restore the complete 1024-byte settings block. Save a backup before restoring another file."),
        Stack(@[self.settingsRead,[self button:@"Open .set…" action:@selector(loadBackup:) tag:1],self.settingsSave,self.settingsWrite],NO),
        self.settingsInfo,Label(@"Compatible with the original Settings utility. Individual setting names are not exposed by that utility; the backup is preserved as a complete block.")],YES);

    self.memoryInfo=Label(@"Open a .mem file, read the radio, or create a new bank of 100 channels.");
    self.memoryRead=[self button:@"Read Radio" action:@selector(readRadio:) tag:2];
    self.memoryWrite=[self button:@"Write 100 Channels…" action:@selector(writeRadio:) tag:2];
    self.memorySave=[self button:@"Save .mem…" action:@selector(saveBackup:) tag:2];
    NSView *memoryButtons=Stack(@[self.memoryRead,[self button:@"Open .mem…" action:@selector(loadBackup:) tag:2],self.memorySave,
        [self button:@"New Bank" action:@selector(newBank:) tag:2],self.memoryWrite],NO);
    self.table=[NSTableView new]; self.table.delegate=self; self.table.dataSource=self;
    self.table.rowHeight=23; self.table.usesAlternatingRowBackgroundColors=YES;
    NSArray *titles=@[@"Channel",@"Frequency (Hz)",@"Mode",@"PreAtt"];
    NSArray *identifiers=@[@"channel",@"frequency",@"mode",@"preAtt"];
    for (NSUInteger i=0;i<titles.count;i++) {
        NSTableColumn *c=[[NSTableColumn alloc] initWithIdentifier:identifiers[i]];
        c.title=titles[i]; c.width=(i==1 ? 240 : 140); c.editable=NO; [self.table addTableColumn:c];
    }
    NSScrollView *scroll=[NSScrollView new]; scroll.hasVerticalScroller=YES;
    scroll.borderType=NSBezelBorder; scroll.documentView=self.table;
    [scroll.heightAnchor constraintEqualToConstant:165].active=YES;
    self.frequency=[NSTextField new]; self.frequency.placeholderString=@"100000–56000000";
    [self.frequency.widthAnchor constraintEqualToConstant:155].active=YES;
    self.mode=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.mode addItemsWithTitles:@[@"LSB",@"USB",@"CW",@"FM",@"AM",@"CWR",@"DIG (USB)"]];
    self.preAtt=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.preAtt addItemsWithTitles:@[@"Off",@"PRE",@"ATT"]];
    [self.controls addObjectsFromArray:@[self.frequency,self.mode,self.preAtt]];
    NSView *editor=Stack(@[Label(@"Hz:"),self.frequency,self.mode,self.preAtt,
        [self button:@"Apply to Row" action:@selector(editChannel:) tag:0],
        [self button:@"Clear Row" action:@selector(editChannel:) tag:1]],NO);
    NSView *memory=Stack(@[memoryButtons,scroll,editor,self.memoryInfo,
        Label(@"Edits stay in this bank until Write is clicked. DIG uses the USB code, as in the original utility.")],YES);
    [scroll.widthAnchor constraintEqualToAnchor:memory.widthAnchor].active=YES;
    self.panels=@[cat,settings,memory];
    for (NSView *panel in self.panels) {
        panel.translatesAutoresizingMaskIntoConstraints=NO; [self.view addSubview:panel];
        [NSLayoutConstraint activateConstraints:@[[panel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [panel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [panel.topAnchor constraintEqualToAnchor:self.view.topAnchor]]];
        for (NSView *child in ((NSStackView *)panel).arrangedSubviews)
            if ([child isKindOfClass:NSTextField.class]) [child.widthAnchor constraintEqualToAnchor:panel.widthAnchor].active=YES;
    }
    self.stop=[NSButton buttonWithTitle:@"Stop" target:self action:@selector(stopOperation:)];
    self.stop.translatesAutoresizingMaskIntoConstraints=NO; [self.view addSubview:self.stop];
    [NSLayoutConstraint activateConstraints:@[[self.view.heightAnchor constraintEqualToConstant:365],
        [self.stop.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.stop.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]]];
    [self selectTool:0]; return self;
}
- (void)selectTool:(NSInteger)tool {
    if (self.busy) return; self.tool=tool;
    for (NSUInteger i=0;i<self.panels.count;i++) self.panels[i].hidden=(NSInteger)i!=tool;
    [self refresh];
}
- (void)portsAvailable:(BOOL)available { self.hasPorts=available; [self refresh]; }
- (void)refresh {
    for (NSControl *c in self.controls) c.enabled=!self.busy;
    self.table.enabled=!self.busy;
    self.stop.enabled=self.busy; self.stop.hidden=!self.busy;
    self.catOnce.enabled=self.catStart.enabled=self.settingsRead.enabled=self.memoryRead.enabled=!self.busy && self.hasPorts;
    self.settingsSave.enabled=!self.busy && self.settingsData!=nil;
    self.settingsWrite.enabled=self.settingsSave.enabled && self.hasPorts;
    self.memorySave.enabled=!self.busy && self.memoryReady;
    self.memoryWrite.enabled=self.memorySave.enabled && self.hasPorts;
}
- (void)alert:(NSString *)title message:(NSString *)message {
    NSAlert *a=[NSAlert new]; a.messageText=title; a.informativeText=message ?: @"Unknown error";
    [a addButtonWithTitle:@"OK"]; [a beginSheetModalForWindow:self.window completionHandler:nil];
}
- (BOOL)confirm:(NSString *)title message:(NSString *)message button:(NSString *)button {
    NSAlert *a=[NSAlert new]; a.messageText=title; a.informativeText=message;
    [a addButtonWithTitle:button]; [a addButtonWithTitle:@"Cancel"];
    return [a runModal]==NSAlertFirstButtonReturn;
}
- (BOOL)confirmReplacement:(NSInteger)kind {
    BOOL dirty=kind==1 ? self.settingsDirty : self.memoryDirty;
    return !dirty || [self confirm:@"Replace the unsaved bank?" message:@"Save your current backup first if you want to keep it. This replaces only the data open in the app." button:@"Replace"];
}
- (BOOL)confirmDiscard {
    return (!self.settingsDirty && !self.memoryDirty) || [self confirm:@"Close with unsaved backups?"
        message:@"Settings or memory changes have not been saved to a file." button:@"Close Without Saving"];
}
- (void)begin {
    self.busy=YES; self.token=[Lab599Cancellation new]; [self refresh];
    if (self.activityChanged) self.activityChanged(YES);
}
- (void)end {
    self.busy=NO; self.token=nil; [self refresh]; if (self.activityChanged) self.activityChanged(NO);
}
- (void)stopOperation:(id)sender {
    self.token.cancelled=YES; self.stop.enabled=NO;
    if (self.statusChanged) self.statusChanged(@"Stopping and closing the serial port…",0);
}
- (void)startCAT:(NSButton *)sender {
    if (self.busy || !self.hasPorts) return;
    NSString *port=self.selectedPort ? self.selectedPort() : nil; if (!port) return;
    [self begin]; TXCATOptions options=TXDefaultCATOptions(); options.maximumChecks=sender.tag;
    self.catResult.stringValue=@"Waiting for the radio…"; self.catCounts.stringValue=@"Checks: 0    Passed: 0    Failed: 0";
    Lab599Cancellation *token=self.token;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        TXCATSummary *result=TXRunCATTest(port,options,token,^(TXCATSummary *s){
            dispatch_async(dispatch_get_main_queue(),^{
                self.catResult.stringValue=[NSString stringWithFormat:@"%@\nReply: %@",s.message,s.lastReply ?: @"—"];
                self.catCounts.stringValue=[NSString stringWithFormat:@"Checks: %lu    Passed: %lu    Failed: %lu    Reply: %.0f ms",(unsigned long)s.checks,(unsigned long)s.passed,(unsigned long)s.failed,s.responseMilliseconds];
                if (self.statusChanged) self.statusChanged(s.message,0);
            });
        },^(NSString *line){dispatch_async(dispatch_get_main_queue(),^{if(self.log) self.log(line);});});
        dispatch_async(dispatch_get_main_queue(),^{
            [self end]; if (self.statusChanged) self.statusChanged(result.cancelled ? @"CAT test stopped. Port closed." : result.message,result.passed && !result.failed ? 1 : 0);
        });
    });
}
- (void)settingsDescription {
    self.settingsInfo.stringValue=[NSString stringWithFormat:@"%@\n1024 bytes • %@\nSHA-256: %@",self.settingsSource,
        self.settingsDirty ? @"Not saved to a file" : @"Saved backup", TXFirmwareSHA256(self.settingsData)];
}
- (void)memoryDescription {
    NSUInteger used=0; for(TXMemoryChannel *c in self.channels) if(c.frequency) used++;
    self.memoryInfo.stringValue=[NSString stringWithFormat:@"100 channels • %lu used • %lu empty%@",(unsigned long)used,(unsigned long)(100-used),self.memoryDirty ? @" • Unsaved changes" : @""];
}
- (void)loadBackup:(NSButton *)sender {
    if (self.busy || ![self confirmReplacement:sender.tag]) return;
    NSInteger kind=sender.tag; NSOpenPanel *p=[NSOpenPanel openPanel];
    p.allowsMultipleSelection=NO; p.canChooseDirectories=NO;
    p.allowedContentTypes=@[[UTType typeWithFilenameExtension:kind==1 ? @"set" : @"mem" conformingToType:UTTypeData]];
    [p beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response){
        if(response!=NSModalResponseOK) return;
        NSError *error=nil; NSNumber *size=nil; [p.URL getResourceValue:&size forKey:NSURLFileSizeKey error:&error];
        if(size.unsignedIntegerValue!=(kind==1 ? 1024 : 600)) { [self alert:@"Invalid backup" message:kind==1 ? @"A .set file must be exactly 1024 bytes." : @"A .mem file must be exactly 600 bytes."]; return; }
        NSData *data=[NSData dataWithContentsOfURL:p.URL options:0 error:&error];
        if(!data) { [self alert:@"Cannot open backup" message:error.localizedDescription]; return; }
        if(kind==1) {
            NSString *validation=TXValidateSettings(data);
            if(validation) { [self alert:@"Invalid settings file" message:validation]; return; }
            self.settingsData=data; self.settingsSource=p.URL.lastPathComponent; self.settingsDirty=NO; [self settingsDescription];
        }
        else {
            NSArray *items=TXDecodeMemory(data,&error); if(!items) { [self alert:@"Invalid memory file" message:error.localizedDescription]; return; }
            self.channels=[items mutableCopy]; self.memoryReady=YES; self.memoryDirty=NO;
            [self.table reloadData]; [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO]; [self memoryDescription];
            [self tableViewSelectionDidChange:[NSNotification notificationWithName:NSTableViewSelectionDidChangeNotification object:self.table]];
        }
        [self refresh]; if(self.log) self.log([NSString stringWithFormat:@"Loaded %@ (%lu bytes).",p.URL.lastPathComponent,(unsigned long)data.length]);
    }];
}
- (void)saveBackup:(NSButton *)sender {
    if(self.busy) return; NSInteger kind=sender.tag; NSError *error=nil;
    NSData *data=kind==1 ? self.settingsData : TXEncodeMemory(self.channels,&error);
    if(!data) { [self alert:@"Cannot save backup" message:error.localizedDescription]; return; }
    NSSavePanel *p=[NSSavePanel savePanel];
    p.allowedContentTypes=@[[UTType typeWithFilenameExtension:kind==1 ? @"set" : @"mem" conformingToType:UTTypeData]];
    p.nameFieldStringValue=kind==1 ? @"TX-500-settings.set" : @"TX-500-memory.mem";
    [p beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response){
        if(response!=NSModalResponseOK) return; NSError *writeError=nil;
        if(![data writeToURL:p.URL options:NSDataWritingAtomic error:&writeError]) { [self alert:@"Cannot save backup" message:writeError.localizedDescription]; return; }
        if(kind==1) { self.settingsDirty=NO; self.settingsSource=p.URL.lastPathComponent; [self settingsDescription]; }
        else { self.memoryDirty=NO; [self memoryDescription]; }
        if(self.log) self.log([NSString stringWithFormat:@"Saved %@ (%lu bytes).",p.URL.lastPathComponent,(unsigned long)data.length]);
    }];
}
- (void)newBank:(id)sender {
    if(self.busy || ![self confirmReplacement:2]) return;
    self.channels=[TXEmptyMemory() mutableCopy]; self.memoryReady=YES; self.memoryDirty=YES;
    [self.table reloadData]; [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [self tableViewSelectionDidChange:[NSNotification notificationWithName:NSTableViewSelectionDidChangeNotification object:self.table]];
    [self memoryDescription]; [self refresh];
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.memoryReady ? 100 : 0; }
- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    TXMemoryChannel *c=self.channels[row];
    if([column.identifier isEqual:@"channel"]) return [NSString stringWithFormat:@"%02ld",(long)row];
    if(!c.frequency) return [column.identifier isEqual:@"frequency"] ? @"Empty" : @"—";
    if([column.identifier isEqual:@"frequency"]) return @(c.frequency);
    if([column.identifier isEqual:@"mode"]) return @{@49:@"LSB",@50:@"USB",@51:@"CW",@52:@"FM",@53:@"AM",@55:@"CWR"}[@(c.mode)];
    return @[@"Off",@"PRE",@"ATT"][c.preAtt-'0'];
}
- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row=self.table.selectedRow; if(row<0) return; TXMemoryChannel *c=self.channels[row];
    self.frequency.stringValue=c.frequency ? [NSString stringWithFormat:@"%u",c.frequency] : @"";
    NSUInteger index=[@[@49,@50,@51,@52,@53,@55] indexOfObject:@(c.mode)];
    [self.mode selectItemAtIndex:index==NSNotFound ? 1 : (NSInteger)index];
    [self.preAtt selectItemAtIndex:c.preAtt>='0' && c.preAtt<='2' ? c.preAtt-'0' : 0];
}
- (void)editChannel:(NSButton *)sender {
    NSInteger row=self.table.selectedRow; if(self.busy || !self.memoryReady || row<0) return;
    TXMemoryChannel *c=[TXMemoryChannel new];
    if(!sender.tag) {
        NSString *text=[self.frequency.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSCharacterSet *nonDigits=[[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet];
        long long value=text.longLongValue;
        if(!text.length || [text rangeOfCharacterFromSet:nonDigits].location!=NSNotFound || value<100000 || value>56000000) {
            [self alert:@"Invalid frequency" message:@"Enter a whole frequency from 100000 to 56000000 Hz. Use Clear Row to empty a channel."]; return;
        }
        c.frequency=(uint32_t)value; c.mode=(uint8_t)[@[@49,@50,@51,@52,@53,@55,@50][self.mode.indexOfSelectedItem] intValue];
        c.preAtt=(uint8_t)('0'+self.preAtt.indexOfSelectedItem);
    }
    self.channels[row]=c; self.memoryDirty=YES; [self.table reloadData]; [self memoryDescription];
    [self tableViewSelectionDidChange:[NSNotification notificationWithName:NSTableViewSelectionDidChangeNotification object:self.table]];
}
- (void)readRadio:(NSButton *)sender {
    if(self.busy || !self.hasPorts || ![self confirmReplacement:sender.tag]) return;
    [self transfer:sender.tag writing:NO];
}
- (void)writeRadio:(NSButton *)sender {
    if(self.busy || !self.hasPorts) return;
    if(sender.tag==1 && !self.settingsData) return;
    if(sender.tag==2 && !self.memoryReady) return;
    NSString *port=self.selectedPort ? self.selectedPort() : nil; if(!port) return;
    NSString *detail=sender.tag==1 ? [NSString stringWithFormat:@"Restore all 1024 settings bytes from %@.\nSHA-256: %@",self.settingsSource,TXFirmwareSHA256(self.settingsData)] :
        [NSString stringWithFormat:@"%@\nAll 100 radio memory channels will be replaced, including empty rows. The original utility's fixed memory fields are used.",self.memoryInfo.stringValue];
    if(![self confirm:@"Write this backup to the radio?" message:[NSString stringWithFormat:@"%@\n\nPort: %@\nKeep the radio powered on normally and the cable connected. The app will read back and check the result.",detail,port] button:@"Write and Verify"]) return;
    [self transfer:sender.tag writing:YES];
}
- (void)transfer:(NSInteger)kind writing:(BOOL)writing {
    NSString *port=self.selectedPort ? self.selectedPort() : nil; if(!port) return;
    NSData *settings=writing && kind==1 ? self.settingsData : nil;
    NSArray *channels=writing && kind==2 ? [[NSArray alloc] initWithArray:self.channels copyItems:YES] : nil;
    [self begin]; Lab599Cancellation *token=self.token;
    NSString *name=kind==1 ? @"Settings" : @"Memory";
    if(self.log) self.log([NSString stringWithFormat:@"%@: %@ on %@ at 9600 baud.",name,writing ? @"write + verify" : @"read",port]);
    if(self.statusChanged) self.statusChanged(@"Opening radio connection…",0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        TXConfigurationProgress progress=^(NSString *phase,NSUInteger done,NSUInteger total){
            if(done!=1 && done!=total && done%8) return;
            dispatch_async(dispatch_get_main_queue(),^{if(self.statusChanged) self.statusChanged([NSString stringWithFormat:@"%@: %lu / %lu",phase,(unsigned long)done,(unsigned long)total],(double)done/total);});
        };
        TXConfigurationResult *result=kind==1 ? TXSettingsTransfer(port,settings,TXDefaultConfigurationOptions(),token,progress) :
            TXMemoryTransfer(port,channels,TXDefaultConfigurationOptions(),token,progress);
        dispatch_async(dispatch_get_main_queue(),^{
            [self end];
            if(result.success && !writing) {
                if(kind==1) { self.settingsData=result.settings; self.settingsSource=@"Read from radio"; self.settingsDirty=YES; [self settingsDescription]; }
                else { self.channels=[result.channels mutableCopy]; self.memoryReady=YES; self.memoryDirty=YES;
                    [self.table reloadData]; [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO]; [self memoryDescription]; }
                if(kind==2) [self tableViewSelectionDidChange:[NSNotification notificationWithName:NSTableViewSelectionDidChangeNotification object:self.table]];
            }
            [self refresh]; if(self.statusChanged) self.statusChanged(result.message,result.success ? 1 : 0);
            if(self.log) self.log([result.message stringByAppendingString:@" Serial port closed."]);
            if(!result.success && !result.cancelled) [self alert:@"Radio operation was not confirmed" message:result.message];
        });
    });
}
@end
