#import "TX500SettingsModel.h"

static NSString * const kModeNames[] = {
    @"LSB", @"LSB", @"USB", @"CW", @"FM", @"AM", @"DIG", @"CWR"
};

@implementation TXSettingsItem

- (id)copyWithZone:(NSZone *)zone {
    TXSettingsItem *copy = [[[self class] allocWithZone:zone] init];
    copy.category = self.category;
    copy.name = self.name;
    copy.address = self.address;
    copy.byteOffset = self.byteOffset;
    copy.byteLength = self.byteLength;
    copy.dataType = self.dataType;
    copy.numericValue = self.numericValue;
    copy.unitOrRange = self.unitOrRange;
    copy.minValue = self.minValue;
    copy.maxValue = self.maxValue;
    copy.details = self.details;
    return copy;
}

- (NSString *)displayValue {
    switch (self.dataType) {
        case TXSettingsTypeModeEnum: {
            if (self.numericValue >= 0 && self.numericValue <= 7) {
                return kModeNames[self.numericValue];
            }
            return [NSString stringWithFormat:@"Mode %lld", self.numericValue];
        }
        case TXSettingsTypeScaleTenths: {
            return [NSString stringWithFormat:@"%.1f", (double)self.numericValue / 10.0];
        }
        case TXSettingsTypeInt8: {
            return [NSString stringWithFormat:@"%d", (int8_t)self.numericValue];
        }
        case TXSettingsTypeUInt32LE: {
            if ([self.unitOrRange isEqualToString:@"Hz"]) {
                NSNumberFormatter *fmt = [NSNumberFormatter new];
                fmt.numberStyle = NSNumberFormatterDecimalStyle;
                return [NSString stringWithFormat:@"%@ Hz (%.4f MHz)",
                        [fmt stringFromNumber:@(self.numericValue)], (double)self.numericValue / 1000000.0];
            }
            return [NSString stringWithFormat:@"%llu", (unsigned long long)self.numericValue];
        }
        case TXSettingsTypeUInt16LE:
        case TXSettingsTypeUInt8:
        default:
            return [NSString stringWithFormat:@"%lld", self.numericValue];
    }
}

- (BOOL)setValueFromString:(NSString *)newStr error:(NSError **)error {
    NSString *trimmed = [newStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    int64_t val = 0;

    if (self.dataType == TXSettingsTypeModeEnum) {
        NSString *up = [trimmed uppercaseString];
        if ([up isEqualToString:@"LSB"]) val = 0;
        else if ([up isEqualToString:@"USB"]) val = 2;
        else if ([up isEqualToString:@"CW"]) val = 3;
        else if ([up isEqualToString:@"FM"]) val = 4;
        else if ([up isEqualToString:@"AM"]) val = 5;
        else if ([up isEqualToString:@"DIG"] || [up isEqualToString:@"DIG (USB)"]) val = 6;
        else if ([up isEqualToString:@"CWR"]) val = 7;
        else {
            val = [trimmed longLongValue];
            if (val < 0 || val > 7) {
                if (error) *error = [NSError errorWithDomain:@"TXSettings" code:1
                    userInfo:@{NSLocalizedDescriptionKey: @"Invalid Mode. Valid: LSB, USB, CW, FM, AM, DIG, CWR."}];
                return NO;
            }
        }
    } else if (self.dataType == TXSettingsTypeScaleTenths) {
        double d = [trimmed doubleValue];
        val = (int64_t)round(d * 10.0);
    } else {
        // Strip out any suffix like " Hz" or " MHz" or commas
        NSString *clean = [trimmed stringByReplacingOccurrencesOfString:@"," withString:@""];
        clean = [clean stringByReplacingOccurrencesOfString:@" Hz" withString:@""];
        clean = [clean stringByReplacingOccurrencesOfString:@"%" withString:@""];
        val = [clean longLongValue];
    }

    if (val < self.minValue || val > self.maxValue) {
        if (error) *error = [NSError errorWithDomain:@"TXSettings" code:2
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Value %lld is out of range [%lld, %lld].",
                                                    val, self.minValue, self.maxValue]}];
        return NO;
    }

    self.numericValue = val;
    return YES;
}

@end

@implementation TX500SettingsModel

static NSArray<NSString *> *kBandNames(void) {
    return @[
        @"160m VFO A", @"160m VFO B",
        @"80m VFO A",  @"80m VFO B",
        @"60m VFO A",  @"60m VFO B",
        @"40m VFO A",  @"40m VFO B",
        @"30m VFO A",  @"30m VFO B",
        @"20m VFO A",  @"20m VFO B",
        @"17m VFO A",  @"17m VFO B",
        @"15m VFO A",  @"15m VFO B",
        @"12m VFO A",  @"12m VFO B",
        @"10m VFO A",  @"10m VFO B",
        @"6m VFO A",   @"6m VFO B",
        @"GEN 1 VFO A", @"GEN 1 VFO B",
        @"GEN 2 VFO A", @"GEN 2 VFO B",
        @"GEN 3 VFO A", @"GEN 3 VFO B",
        @"GEN 4 VFO A", @"GEN 4 VFO B",
        @"GEN 5 VFO A", @"GEN 5 VFO B",
        @"GEN 6 VFO A", @"GEN 6 VFO B"
    ];
}

+ (NSArray<TXSettingsItem *> *)decodeSettings:(NSData *)data {
    if (data.length < 1024) return @[];
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSMutableArray<TXSettingsItem *> *list = [NSMutableArray array];

    void (^addItem)(NSString *, NSString *, NSUInteger, NSUInteger, NSUInteger, TXSettingsDataType, int64_t, int64_t, NSString *, NSString *) =
        ^(NSString *cat, NSString *name, NSUInteger off, NSUInteger len, NSUInteger addr, TXSettingsDataType type, int64_t minV, int64_t maxV, NSString *unit, NSString *det) {
            TXSettingsItem *item = [TXSettingsItem new];
            item.category = cat;
            item.name = name;
            item.byteOffset = off;
            item.byteLength = len;
            item.address = addr;
            item.dataType = type;
            item.minValue = minV;
            item.maxValue = maxV;
            item.unitOrRange = unit;
            item.details = det;

            if (len == 1) {
                if (type == TXSettingsTypeInt8) {
                    item.numericValue = (int8_t)bytes[off];
                } else {
                    item.numericValue = bytes[off];
                }
            } else if (len == 2) {
                item.numericValue = (uint16_t)(bytes[off] | (bytes[off + 1] << 8));
            } else if (len == 4) {
                item.numericValue = (uint32_t)(bytes[off] | (bytes[off + 1] << 8) | (bytes[off + 2] << 16) | (bytes[off + 3] << 24));
            }
            [list addObject:item];
        };

    // 1. VFO & Band Settings (34 slots * 16 bytes = 544 bytes, off 4..547)
    NSArray<NSString *> *bNames = kBandNames();
    for (NSUInteger b = 0; b < 34; b++) {
        NSUInteger off = 4 + b * 16;
        NSString *slotName = bNames[b];
        addItem(@"VFO & Bands", [NSString stringWithFormat:@"%@ Frequency", slotName],
                off, 4, 1000 + off, TXSettingsTypeUInt32LE, 0, 56000000, @"Hz", @"Default frequency for this band slot");
        addItem(@"VFO & Bands", [NSString stringWithFormat:@"%@ Mode", slotName],
                off + 4, 1, 1000 + off + 4, TXSettingsTypeModeEnum, 0, 7, @"LSB/USB/CW/FM/AM/DIG/CWR", @"Operating modulation mode");
        addItem(@"VFO & Bands", [NSString stringWithFormat:@"%@ Filter Preset", slotName],
                off + 5, 1, 1000 + off + 5, TXSettingsTypeUInt8, 0, 3, @"FL1..FL4 (0..3)", @"Active DSP filter preset");
    }

    // 2. DSP Filter Bandwidths (off 552..607)
    struct { NSString *name; NSUInteger off; } filters[] = {
        {@"DIG RX FL1 Bandwidth", 552}, {@"DIG RX FL2 Bandwidth", 554},
        {@"DIG RX FL3 Bandwidth", 556}, {@"DIG RX FL4 Bandwidth", 558},
        {@"SSB RX FL4 Bandwidth", 560}, {@"SSB RX FL3 Bandwidth", 562},
        {@"SSB RX FL2 Bandwidth", 564}, {@"SSB RX FL1 Bandwidth", 566},
        {@"CW RX FL4 Bandwidth",  568}, {@"CW RX FL3 Bandwidth",  570},
        {@"CW RX FL2 Bandwidth",  572}, {@"CW RX FL1 Bandwidth",  574},
        {@"AM RX FL4 Bandwidth",  576}, {@"AM RX FL3 Bandwidth",  578},
        {@"AM RX FL2 Bandwidth",  580}, {@"AM RX FL1 Bandwidth",  582},
        {@"FM RX FL4 Bandwidth",  584}, {@"FM RX FL3 Bandwidth",  586},
        {@"FM RX FL2 Bandwidth",  588}, {@"FM RX FL1 Bandwidth",  590},
        {@"CW TX FL1 Bandwidth",  592}, {@"CW TX FL2 Bandwidth",  594},
        {@"SSB TX FL1 Bandwidth", 596}, {@"SSB TX FL2 Bandwidth", 598},
        {@"AM TX FL1 Bandwidth",  600}, {@"AM TX FL2 Bandwidth",  602},
        {@"FM TX FL1 Bandwidth",  604}, {@"FM TX FL2 Bandwidth",  606}
    };
    for (size_t i = 0; i < sizeof(filters)/sizeof(filters[0]); i++) {
        addItem(@"DSP Filters", filters[i].name, filters[i].off, 2, 1000 + filters[i].off,
                TXSettingsTypeUInt16LE, 50, 12000, @"Hz", @"DSP filter bandwidth preset");
    }

    // 3. Audio & Equalizer (Menu 17)
    addItem(@"Equalizer & Audio", @"RX Equalizer High (HF)", 616, 1, 1616, TXSettingsTypeUInt8, 1, 100, @"1–100 %", @"Receiver high-frequency audio response (Default: 50)");
    addItem(@"Equalizer & Audio", @"RX Equalizer Low (LF)", 617, 1, 1617, TXSettingsTypeUInt8, 1, 100, @"1–100 %", @"Receiver low-frequency bass audio response (Default: 100)");
    addItem(@"Equalizer & Audio", @"RX Equalizer Mid (MF)", 618, 1, 1618, TXSettingsTypeUInt8, 1, 100, @"1–100 %", @"Receiver midrange audio response (Default: 75)");
    addItem(@"Equalizer & Audio", @"TX Equalizer High (HF)", 619, 1, 1619, TXSettingsTypeUInt8, 1, 100, @"1–100 %", @"Transmitter high-frequency audio response (Default: 50)");
    addItem(@"Equalizer & Audio", @"TX Equalizer Low (LF)", 620, 1, 1620, TXSettingsTypeUInt8, 1, 100, @"1–100 %", @"Transmitter low-frequency audio response (Default: 100)");
    addItem(@"Equalizer & Audio", @"TX Equalizer Mid (MF)", 621, 1, 1621, TXSettingsTypeUInt8, 1, 100, @"1–100 %", @"Transmitter midrange audio response (Default: 100)");

    // 4. CW & Keyer (Menu 10..13)
    addItem(@"CW & Keyer", @"CW Sidetone Pitch", 608, 2, 1608, TXSettingsTypeUInt16LE, 400, 1200, @"400–1200 Hz", @"CW tone frequency and RX passband center (Default: 700 Hz)");
    addItem(@"CW & Keyer", @"CW Keyer Speed", 610, 1, 1610, TXSettingsTypeUInt8, 10, 300, @"10–300 cpm (2–60 wpm)", @"Internal electronic keyer speed (Default: 100 cpm)");
    addItem(@"CW & Keyer", @"CW Keyer Weight", 630, 1, 1630, TXSettingsTypeUInt8, 1, 10, @"Ratio 2:1–4.5:1", @"Dot-to-dash ratio of electronic keyer");
    addItem(@"CW & Keyer", @"VOX Delay (CW)", 614, 2, 1614, TXSettingsTypeUInt16LE, 100, 10000, @"100–10000 ms", @"Semi-break-in hold delay after keying stops (Default: 400 ms)");

    // 5. Transmitter & VOX (Menu 00, 03, 04, 09, 19)
    addItem(@"Transmitter & VOX", @"RF Output Power", 622, 1, 1622, TXSettingsTypeUInt8, 10, 100, @"10–100 %", @"Transmitter RF output power percentage (Default: 100%)");
    addItem(@"Transmitter & VOX", @"Digital Line Gain (DIG)", 624, 1, 1624, TXSettingsTypeUInt8, 1, 100, @"1–100", @"Line audio input gain for digital modes (Default: 20)");
    addItem(@"Transmitter & VOX", @"Microphone Gain (MIC)", 625, 1, 1625, TXSettingsTypeUInt8, 1, 100, @"1–100", @"Microphone audio input level (Default: 5)");
    addItem(@"Transmitter & VOX", @"Speech Compressor (CMR)", 628, 1, 1628, TXSettingsTypeUInt8, 1, 100, @"1–100", @"SSB speech processor compression level (Default: 5)");
    addItem(@"Transmitter & VOX", @"VOX Delay (MIC)", 612, 2, 1612, TXSettingsTypeUInt16LE, 100, 10000, @"100–10000 ms", @"Voice-operated TX hold time after speech stops (Default: 1000 ms)");
    addItem(@"Transmitter & VOX", @"Tune Tone RF Power", 676, 1, 1676, TXSettingsTypeUInt8, 10, 100, @"10–100 %", @"Test tune signal output power percentage (Default: 35%)");

    // 6. Receiver & DSP (Menu 01, 02, 05, 06)
    addItem(@"Receiver & DSP", @"AGC Time Constant (CW)", 631, 1, 1631, TXSettingsTypeUInt8, 1, 10, @"1–10 (Slow to Fast)", @"CW Automatic Gain Control speed (Default: 5)");
    addItem(@"Receiver & DSP", @"AGC Time Constant (SSB)", 632, 1, 1632, TXSettingsTypeUInt8, 1, 10, @"1–10 (Slow to Fast)", @"SSB Automatic Gain Control speed (Default: 3)");
    addItem(@"Receiver & DSP", @"AGC Time Constant (AM)", 633, 1, 1633, TXSettingsTypeUInt8, 1, 10, @"1–10 (Slow to Fast)", @"AM Automatic Gain Control speed (Default: 3)");
    addItem(@"Receiver & DSP", @"Noise Reduction Level (NR)", 623, 1, 1623, TXSettingsTypeUInt8, 1, 100, @"1–100", @"DSP digital noise reduction effectiveness (Default: 50)");
    addItem(@"Receiver & DSP", @"Noise Blanker Level (NB)", 629, 1, 1629, TXSettingsTypeUInt8, 40, 100, @"40–100", @"Impulse noise blanker threshold (Default: 50)");
    addItem(@"Receiver & DSP", @"Receiver RF Gain", 627, 1, 1627, TXSettingsTypeUInt8, 0, 100, @"0–100", @"Front-end RF attenuation/gain stage");

    // 7. Panadapter & Spectrum Display (Menu 23, 24)
    addItem(@"Panadapter & Display", @"TX Panadapter Scale", 644, 1, 1644, TXSettingsTypeScaleTenths, 1, 50, @"0.1–5.0 x", @"Spectrum vertical amplitude scale in TX (Default: 2.7)");
    addItem(@"Panadapter & Display", @"TX Panadapter Baseline Shift", 645, 1, 1645, TXSettingsTypeInt8, -100, 100, @"-100 to +100 dB", @"Spectrum baseline vertical offset in TX (Default: 20)");
    addItem(@"Panadapter & Display", @"TX Panadapter Averaging", 646, 1, 1646, TXSettingsTypeUInt8, 1, 100, @"1–100", @"Spectrum frame smoothing in TX (Default: 5)");
    addItem(@"Panadapter & Display", @"RX Panadapter Scale", 647, 1, 1647, TXSettingsTypeScaleTenths, 1, 50, @"0.1–5.0 x", @"Spectrum vertical amplitude scale in RX (Default: 0.9)");
    addItem(@"Panadapter & Display", @"RX Panadapter Baseline Shift", 648, 1, 1648, TXSettingsTypeInt8, -100, 100, @"-100 to +100 dB", @"Spectrum baseline vertical offset in RX (Default: 30)");
    addItem(@"Panadapter & Display", @"RX Panadapter Averaging", 649, 1, 1649, TXSettingsTypeUInt8, 1, 100, @"1–100", @"Spectrum frame smoothing in RX (Default: 5)");
    addItem(@"Panadapter & Display", @"Beacon Interval", 655, 1, 1655, TXSettingsTypeUInt8, 0, 240, @"0–240 s (0=Off)", @"Cyclic beacon transmission interval in seconds (Default: 0)");

    return [list copy];
}

+ (NSData *)encodeSettings:(NSArray<TXSettingsItem *> *)items baseData:(nullable NSData *)baseData {
    NSMutableData *data;
    if (baseData && baseData.length == 1024) {
        data = [baseData mutableCopy];
    } else {
        data = [NSMutableData dataWithLength:1024];
        uint8_t *b = data.mutableBytes;
        // Standard Magic
        b[0] = 0x55; b[1] = 0xaa; b[2] = 0xab; b[3] = 0x26;
    }

    uint8_t *bytes = data.mutableBytes;
    for (TXSettingsItem *item in items) {
        NSUInteger off = item.byteOffset;
        if (off + item.byteLength > 1024) continue;

        if (item.byteLength == 1) {
            bytes[off] = (uint8_t)(item.numericValue & 0xFF);
        } else if (item.byteLength == 2) {
            bytes[off] = (uint8_t)(item.numericValue & 0xFF);
            bytes[off + 1] = (uint8_t)((item.numericValue >> 8) & 0xFF);
        } else if (item.byteLength == 4) {
            bytes[off] = (uint8_t)(item.numericValue & 0xFF);
            bytes[off + 1] = (uint8_t)((item.numericValue >> 8) & 0xFF);
            bytes[off + 2] = (uint8_t)((item.numericValue >> 16) & 0xFF);
            bytes[off + 3] = (uint8_t)((item.numericValue >> 24) & 0xFF);
        }
    }
    return [data copy];
}

+ (NSString *)descriptionForAddress:(NSUInteger)address {
    if (address < 1000 || address > 2023) return @"Unknown Address";
    if (address >= 1000 && address <= 1003) return @"Header / Signature (0x55 0xAA)";

    if (address >= 1004 && address <= 1547) {
        NSUInteger rel = address - 1004;
        NSUInteger slot = rel / 16;
        NSUInteger field = rel % 16;
        NSArray<NSString *> *bNames = kBandNames();
        NSString *name = (slot < bNames.count) ? bNames[slot] : [NSString stringWithFormat:@"Slot %lu", (unsigned long)slot];
        if (field < 4) return [NSString stringWithFormat:@"%@ Frequency Byte %lu", name, (unsigned long)field];
        if (field == 4) return [NSString stringWithFormat:@"%@ Mode", name];
        if (field == 5) return [NSString stringWithFormat:@"%@ Filter Preset", name];
        return [NSString stringWithFormat:@"%@ Config Byte %lu", name, (unsigned long)field];
    }

    switch (address) {
        case 1608: case 1609: return @"CW Sidetone Pitch (Hz)";
        case 1610: return @"CW Keyer Speed (cpm)";
        case 1612: case 1613: return @"VOX Delay - Voice/MIC (ms)";
        case 1614: case 1615: return @"VOX Delay - CW Semi-Break-In (ms)";
        case 1616: return @"RX Equalizer High (HF %)";
        case 1617: return @"RX Equalizer Low (LF %)";
        case 1618: return @"RX Equalizer Mid (MF %)";
        case 1619: return @"TX Equalizer High (HF %)";
        case 1620: return @"TX Equalizer Low (LF %)";
        case 1621: return @"TX Equalizer Mid (MF %)";
        case 1622: return @"Transmitter RF Output Power (%)";
        case 1623: return @"DSP Noise Reduction (NR Level)";
        case 1624: return @"Digital Line Input Gain (DIG)";
        case 1625: return @"Microphone Input Gain (MIC)";
        case 1626: return @"VOX Delay - Digital";
        case 1627: return @"Receiver RF Gain";
        case 1628: return @"Speech Compressor (CMR Level)";
        case 1629: return @"DSP Noise Blanker (NB Level)";
        case 1630: return @"CW Keyer Weight Ratio";
        case 1631: return @"AGC Speed (CW)";
        case 1632: return @"AGC Speed (SSB)";
        case 1633: return @"AGC Speed (AM)";
        case 1644: return @"TX Panadapter Scale";
        case 1645: return @"TX Panadapter Baseline Shift";
        case 1646: return @"TX Panadapter Averaging";
        case 1647: return @"RX Panadapter Scale";
        case 1648: return @"RX Panadapter Baseline Shift";
        case 1649: return @"RX Panadapter Averaging";
        case 1655: return @"Beacon Interval (seconds)";
        case 1674: case 1675: return @"Tune Mode Sidetone Pitch";
        case 1676: return @"Tune Mode Output Power (%)";
        default:
            if (address >= 1548 && address <= 1607) {
                return [NSString stringWithFormat:@"DSP Filter Bandwidth Preset (Addr %lu)", (unsigned long)address];
            }
            if (address >= 1680) {
                return [NSString stringWithFormat:@"Reserved Area (Addr %lu)", (unsigned long)address];
            }
            return [NSString stringWithFormat:@"Radio Setting (Addr %lu)", (unsigned long)address];
    }
}

+ (NSString *)categoryForAddress:(NSUInteger)address {
    if (address < 1004) return @"System";
    if (address <= 1547) return @"VFO & Bands";
    if (address <= 1607) return @"DSP Filters";
    if (address == 1608 || address == 1609 || address == 1610 || address == 1614 || address == 1615 || address == 1630) return @"CW & Keyer";
    if (address >= 1616 && address <= 1621) return @"Equalizer & Audio";
    if (address == 1612 || address == 1613 || address == 1622 || address == 1624 || address == 1625 || address == 1628 || address == 1676) return @"Transmitter & VOX";
    if (address == 1623 || address == 1627 || address == 1629 || (address >= 1631 && address <= 1633)) return @"Receiver & DSP";
    if (address >= 1644 && address <= 1655) return @"Panadapter & Display";
    return @"System";
}

+ (nullable NSString *)exportJSONFromSettingsData:(NSData *)data error:(NSError **)error {
    NSArray<TXSettingsItem *> *items = [self decodeSettings:data];
    if (!items.count) {
        if (error) *error = [NSError errorWithDomain:@"TXSettings" code:10
            userInfo:@{NSLocalizedDescriptionKey: @"Failed to decode settings data."}];
        return nil;
    }

    NSMutableArray *arr = [NSMutableArray array];
    for (TXSettingsItem *item in items) {
        [arr addObject:@{
            @"category": item.category ?: @"",
            @"name": item.name ?: @"",
            @"address": @(item.address),
            @"value": @(item.numericValue),
            @"display": [item displayValue] ?: @"",
            @"unit_range": item.unitOrRange ?: @"",
            @"details": item.details ?: @""
        }];
    }

    NSDictionary *root = @{
        @"format": @"Lab599 TX-500 Settings Description",
        @"version": @"1.0",
        @"sha256": data.description ?: @"",
        @"settings": arr
    };

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:error];
    return jsonData ? [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] : nil;
}

+ (nullable NSData *)importJSON:(NSString *)json baseData:(nullable NSData *)baseData error:(NSError **)error {
    NSData *jsonData = [json dataUsingEncoding:NSUTF8StringEncoding];
    if (!jsonData) {
        if (error) *error = [NSError errorWithDomain:@"TXSettings" code:11
            userInfo:@{NSLocalizedDescriptionKey: @"Invalid UTF-8 string in JSON input."}];
        return nil;
    }

    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:error];
    if (![root isKindOfClass:[NSDictionary class]]) return nil;

    NSArray *settingsArr = root[@"settings"];
    if (![settingsArr isKindOfClass:[NSArray class]]) {
        if (error) *error = [NSError errorWithDomain:@"TXSettings" code:12
            userInfo:@{NSLocalizedDescriptionKey: @"Missing 'settings' array in JSON root."}];
        return nil;
    }

    // Start with decoded items from baseData, or default
    NSArray<TXSettingsItem *> *items = [self decodeSettings:baseData ?: [NSMutableData dataWithLength:1024]];
    NSMutableDictionary<NSNumber *, TXSettingsItem *> *byAddr = [NSMutableDictionary dictionary];
    for (TXSettingsItem *it in items) {
        byAddr[@(it.address)] = it;
    }

    for (NSDictionary *dict in settingsArr) {
        NSNumber *addr = dict[@"address"];
        NSNumber *val = dict[@"value"];
        if (addr && val && byAddr[addr]) {
            byAddr[addr].numericValue = [val longLongValue];
        }
    }

    return [self encodeSettings:items baseData:baseData];
}

@end
