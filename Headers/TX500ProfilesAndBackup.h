#import <Foundation/Foundation.h>
#import "TX500Configuration.h"

NS_ASSUME_NONNULL_BEGIN

// =============================================================================
// CSV Import & Export for Memory Channels
// =============================================================================

NSString *TXExportMemoryToCSV(NSArray<TXMemoryChannel *> *channels);
NSArray<TXMemoryChannel *> * _Nullable TXImportMemoryFromCSV(NSString *csvString, NSError **error);

// =============================================================================
// Operating Profiles (پروفایل‌های کاری)
// =============================================================================

@interface TXOperatingProfile : NSObject
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSString *details;
@property(nonatomic, strong) NSArray<TXMemoryChannel *> *channels;
@property(nonatomic) BOOL isBuiltIn;
@end

@interface TXProfileManager : NSObject
+ (NSArray<TXOperatingProfile *> *)builtInProfiles;
+ (NSArray<TXOperatingProfile *> *)userProfiles;
+ (BOOL)saveUserProfileNamed:(NSString *)name channels:(NSArray<TXMemoryChannel *> *)channels error:(NSError **)error;
+ (BOOL)deleteUserProfileNamed:(NSString *)name error:(NSError **)error;
+ (NSString *)profilesDirectoryPath;
@end

// =============================================================================
// Backup Comparison Engine (مقایسهٔ پشتیبان‌ها)
// =============================================================================

@interface TXSettingsDiffItem : NSObject
@property(nonatomic) NSUInteger address; // 1000 to 2023
@property(nonatomic) uint8_t valueA;
@property(nonatomic) uint8_t valueB;
@property(nonatomic, copy) NSString *changeDescription;
@end

@interface TXSettingsComparisonResult : NSObject
@property(nonatomic) NSUInteger totalSettings; // 1024
@property(nonatomic) NSUInteger differencesCount;
@property(nonatomic, copy) NSString *summary;
@property(nonatomic, strong) NSArray<TXSettingsDiffItem *> *diffItems;
@end

TXSettingsComparisonResult *TXCompareSettings(NSData *dataA, NSData *dataB, NSString *nameA, NSString *nameB);

typedef NS_ENUM(NSInteger, TXChannelDiffStatus) {
    TXChannelDiffIdentical = 0,
    TXChannelDiffModified,
    TXChannelDiffAdded,
    TXChannelDiffCleared
};

@interface TXMemoryDiffItem : NSObject
@property(nonatomic) NSUInteger channelIndex; // 00 to 99
@property(nonatomic, strong) TXMemoryChannel *channelA;
@property(nonatomic, strong) TXMemoryChannel *channelB;
@property(nonatomic) TXChannelDiffStatus status;
@property(nonatomic, copy) NSString *statusText;
@end

@interface TXMemoryComparisonResult : NSObject
@property(nonatomic) NSUInteger totalChannels; // 100
@property(nonatomic) NSUInteger differencesCount;
@property(nonatomic) NSUInteger identicalCount;
@property(nonatomic, copy) NSString *summary;
@property(nonatomic, strong) NSArray<TXMemoryDiffItem *> *diffItems;
@end

TXMemoryComparisonResult *TXCompareMemory(NSArray<TXMemoryChannel *> *bankA, NSArray<TXMemoryChannel *> *bankB, NSString *nameA, NSString *nameB);

NS_ASSUME_NONNULL_END
