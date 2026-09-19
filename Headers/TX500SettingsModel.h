#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TXSettingsDataType) {
    TXSettingsTypeUInt8 = 0,
    TXSettingsTypeInt8,
    TXSettingsTypeUInt16LE,
    TXSettingsTypeUInt32LE,
    TXSettingsTypeModeEnum,
    TXSettingsTypeScaleTenths
};

@interface TXSettingsItem : NSObject <NSCopying>
@property(nonatomic, copy) NSString *category;
@property(nonatomic, copy) NSString *name;
@property(nonatomic) NSUInteger address;      // 1000..2023
@property(nonatomic) NSUInteger byteOffset;   // 0..1023
@property(nonatomic) NSUInteger byteLength;   // 1, 2, or 4
@property(nonatomic) TXSettingsDataType dataType;
@property(nonatomic) int64_t numericValue;
@property(nonatomic, copy) NSString *unitOrRange;
@property(nonatomic) int64_t minValue;
@property(nonatomic) int64_t maxValue;
@property(nonatomic, copy) NSString *details;

- (NSString *)displayValue;
- (BOOL)setValueFromString:(NSString *)newStr error:(NSError **)error;
@end

@interface TX500SettingsModel : NSObject

+ (NSArray<TXSettingsItem *> *)decodeSettings:(NSData *)data;
+ (NSData *)encodeSettings:(NSArray<TXSettingsItem *> *)items baseData:(nullable NSData *)baseData;
+ (NSString *)descriptionForAddress:(NSUInteger)address;
+ (NSString *)categoryForAddress:(NSUInteger)address;
+ (nullable NSString *)exportJSONFromSettingsData:(NSData *)data error:(NSError **)error;
+ (nullable NSData *)importJSON:(NSString *)json baseData:(nullable NSData *)baseData error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
