#import "Lab599FirmwareCatalog.h"
#import "TX500Transfer.h"
#import <CommonCrypto/CommonDigest.h>

@implementation Lab599FirmwareItem

- (NSString *)displayTitle {
    if (self.isLatest) {
        return [NSString stringWithFormat:@"%@  [Latest - %@]", self.title, self.fileSizeString ?: @""];
    }
    return [NSString stringWithFormat:@"%@  [%@]", self.title, self.fileSizeString ?: @""];
}

@end

@interface Lab599FirmwareCatalog () <NSURLSessionDownloadDelegate>
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, copy) void (^currentProgressHandler)(double, int64_t, int64_t);
@property(nonatomic, copy) void (^currentCompletionHandler)(NSURL * _Nullable, NSString * _Nullable, NSError * _Nullable);
@property(nonatomic, strong) NSURL *currentDestinationURL;
@end

@implementation Lab599FirmwareCatalog

+ (instancetype)sharedCatalog {
    static Lab599FirmwareCatalog *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[Lab599FirmwareCatalog alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        config.timeoutIntervalForRequest = 20.0;
        config.timeoutIntervalForResource = 60.0;
        self.session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
    }
    return self;
}

+ (NSArray<Lab599FirmwareItem *> *)fallbackFirmwareCatalog {
    NSMutableArray<Lab599FirmwareItem *> *items = [NSMutableArray array];

    Lab599FirmwareItem *tx500Latest = [Lab599FirmwareItem new];
    tx500Latest.title = @"TX-500 Firmware v1.30.00";
    tx500Latest.model = @"TX-500 Discovery";
    tx500Latest.version = @"1.30.00";
    tx500Latest.fileSizeString = @"240 KB";
    tx500Latest.downloadURL = [NSURL URLWithString:@"https://downloads.lab599.com/TX500/mtrx1.30.00.fw"];
    tx500Latest.changelog = @"Official TX-500 Discovery release.\n- Improved battery indicator\n- Audio engine and CAT improvements";
    tx500Latest.isLatest = YES;
    [items addObject:tx500Latest];

    Lab599FirmwareItem *tx500Prev = [Lab599FirmwareItem new];
    tx500Prev.title = @"TX-500 Firmware v1.29.06";
    tx500Prev.model = @"TX-500 Discovery";
    tx500Prev.version = @"1.29.06";
    tx500Prev.fileSizeString = @"240 KB";
    tx500Prev.downloadURL = [NSURL URLWithString:@"https://downloads.lab599.com/TX500/mtrx1.29.06.fw"];
    tx500Prev.changelog = @"Stable release for TX-500 Discovery.";
    tx500Prev.isLatest = NO;
    [items addObject:tx500Prev];

    Lab599FirmwareItem *mpLatest = [Lab599FirmwareItem new];
    mpLatest.title = @"TX-500MP Firmware v1.30.00";
    mpLatest.model = @"TX-500MP";
    mpLatest.version = @"1.30.00";
    mpLatest.fileSizeString = @"224 KB";
    mpLatest.downloadURL = [NSURL URLWithString:@"https://downloads.lab599.com/TX500MP/mtrxMP1.30.00.fw"];
    mpLatest.changelog = @"Official TX-500MP release.\n- Optimized for TX-500MP transceiver hardware.";
    mpLatest.isLatest = YES;
    [items addObject:mpLatest];

    Lab599FirmwareItem *mpPatch = [Lab599FirmwareItem new];
    mpPatch.title = @"TX-500MP HAM-Bands Patch v1.30.00B27";
    mpPatch.model = @"TX-500MP";
    mpPatch.version = @"1.30.00B27";
    mpPatch.fileSizeString = @"224 KB";
    mpPatch.downloadURL = [NSURL URLWithString:@"https://downloads.lab599.com/TX500MP/mtrxMP1.30.00b27.fw"];
    mpPatch.changelog = @"HAM-Bands Patch for TX-500MP.";
    mpPatch.isLatest = NO;
    [items addObject:mpPatch];

    return items;
}

- (void)fetchAvailableFirmwaresWithCompletion:(void (^)(NSArray<Lab599FirmwareItem *> *items, NSError * _Nullable error))completion {
    NSURL *url = [NSURL URLWithString:@"https://lab599.com/downloads"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)" forHTTPHeaderField:@"User-Agent"];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        (void)response;
        if (error || !data) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion([Lab599FirmwareCatalog fallbackFirmwareCatalog], error);
            });
            return;
        }

        NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!html) html = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
        if (!html) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion([Lab599FirmwareCatalog fallbackFirmwareCatalog], [NSError errorWithDomain:@"Lab599" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Unable to decode web content"}]);
            });
            return;
        }

        NSArray<Lab599FirmwareItem *> *parsed = [self parseFirmwareItemsFromHTML:html];
        if (parsed.count == 0) {
            parsed = [Lab599FirmwareCatalog fallbackFirmwareCatalog];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(parsed, nil);
        });
    }];
    [task resume];
}

- (NSArray<Lab599FirmwareItem *> *)parseFirmwareItemsFromHTML:(NSString *)html {
    NSMutableArray<Lab599FirmwareItem *> *results = [NSMutableArray array];
    NSMutableDictionary<NSString *, Lab599FirmwareItem *> *itemByUrl = [NSMutableDictionary dictionary];

    // Find all links to .fw files
    NSRegularExpression *linkRegex = [NSRegularExpression regularExpressionWithPattern:@"<a\\s+[^>]*href=[\"'](https?://downloads\\.lab599\\.com/[^\"'\\s]+\\.fw)[\"'][^>]*>(.*?)</a>"
                                                                               options:NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators
                                                                                 error:nil];
    NSArray<NSTextCheckingResult *> *matches = [linkRegex matchesInString:html options:0 range:NSMakeRange(0, html.length)];

    for (NSTextCheckingResult *match in matches) {
        NSString *urlString = [html substringWithRange:[match rangeAtIndex:1]];
        NSString *rawText = [html substringWithRange:[match rangeAtIndex:2]];

        NSString *cleanText = [rawText stringByReplacingOccurrencesOfString:@"<[^>]+>" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0, rawText.length)];
        cleanText = [cleanText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        Lab599FirmwareItem *existing = itemByUrl[urlString];
        if (!existing) {
            existing = [Lab599FirmwareItem new];
            existing.downloadURL = [NSURL URLWithString:urlString];
            itemByUrl[urlString] = existing;
            [results addObject:existing];
        }

        if (cleanText.length > 0) {
            if ([cleanText rangeOfString:@"Kb" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                [cleanText rangeOfString:@"MB" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                existing.fileSizeString = cleanText;
            } else if ([cleanText rangeOfString:@"Firmware" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                       [cleanText rangeOfString:@"Patch" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                existing.title = cleanText;
            }
        }
    }

    // Determine model and fallback titles for each item
    for (Lab599FirmwareItem *item in results) {
        NSString *path = item.downloadURL.path;
        if ([path containsString:@"TX500MP"] || [item.title containsString:@"TX-500MP"]) {
            item.model = @"TX-500MP";
        } else if ([path containsString:@"TX500"] || [item.title containsString:@"TX-500"]) {
            item.model = @"TX-500 Discovery";
        } else {
            item.model = @"Lab599 Transceiver";
        }

        if (!item.title || item.title.length == 0) {
            item.title = [NSString stringWithFormat:@"%@ %@", item.model, item.downloadURL.lastPathComponent];
        }

        // Extract version
        NSRegularExpression *verRegex = [NSRegularExpression regularExpressionWithPattern:@"v?(\\d+\\.\\d+\\.\\d+([A-Za-z0-9]+)?)"
                                                                                  options:NSRegularExpressionCaseInsensitive
                                                                                    error:nil];
        NSTextCheckingResult *verMatch = [verRegex firstMatchInString:item.title options:0 range:NSMakeRange(0, item.title.length)];
        if (verMatch) {
            item.version = [item.title substringWithRange:[verMatch rangeAtIndex:1]];
        } else {
            item.version = item.downloadURL.lastPathComponent.stringByDeletingPathExtension;
        }

        // Search for nearby changelog in HTML
        NSRange urlRange = [html rangeOfString:item.downloadURL.absoluteString];
        if (urlRange.location != NSNotFound) {
            NSUInteger searchStart = urlRange.location;
            NSUInteger searchLen = MIN((NSUInteger)2500, html.length - searchStart);
            NSString *window = [html substringWithRange:NSMakeRange(searchStart, searchLen)];
            NSRange changelogRange = [window rangeOfString:@"Changelog:"];
            if (changelogRange.location != NSNotFound) {
                NSUInteger clStart = changelogRange.location;
                NSUInteger clLen = MIN((NSUInteger)800, window.length - clStart);
                NSString *clChunk = [window substringWithRange:NSMakeRange(clStart, clLen)];
                NSRange endDiv = [clChunk rangeOfString:@"</div>"];
                if (endDiv.location != NSNotFound) {
                    clChunk = [clChunk substringToIndex:endDiv.location];
                }
                NSString *cleanCL = [clChunk stringByReplacingOccurrencesOfString:@"<br\\s*/?>|</li>" withString:@"\n" options:NSRegularExpressionSearch range:NSMakeRange(0, clChunk.length)];
                cleanCL = [cleanCL stringByReplacingOccurrencesOfString:@"<[^>]+>" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0, cleanCL.length)];
                cleanCL = [cleanCL stringByReplacingOccurrencesOfString:@"&nbsp;" withString:@" "];
                cleanCL = [cleanCL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (cleanCL.length > 0) {
                    item.changelog = cleanCL;
                }
            }
        }
    }

    // Mark the latest version per model
    NSMutableSet<NSString *> *seenModels = [NSMutableSet set];
    for (Lab599FirmwareItem *item in results) {
        if (![seenModels containsObject:item.model] && ![item.title containsString:@"Patch"]) {
            item.isLatest = YES;
            [seenModels addObject:item.model];
        }
    }

    return results;
}

- (NSURLSessionDownloadTask *)downloadFirmware:(Lab599FirmwareItem *)item
                                     progress:(void (^)(double progress, int64_t bytesWritten, int64_t totalExpected))progressHandler
                                   completion:(void (^)(NSURL * _Nullable localFileURL, NSString * _Nullable sha256, NSError * _Nullable error))completionHandler {
    self.currentProgressHandler = progressHandler;
    self.currentCompletionHandler = completionHandler;

    NSString *cacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject
                          stringByAppendingPathComponent:@"Lab599FirmwareUpdater"];
    [[NSFileManager defaultManager] createDirectoryAtPath:cacheDir withIntermediateDirectories:YES attributes:nil error:nil];
    self.currentDestinationURL = [NSURL fileURLWithPath:[cacheDir stringByAppendingPathComponent:item.downloadURL.lastPathComponent]];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:item.downloadURL];
    [request setValue:@"Mozilla/5.0" forHTTPHeaderField:@"User-Agent"];

    NSURLSessionDownloadTask *task = [self.session downloadTaskWithRequest:request];
    [task resume];
    return task;
}

#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    (void)session;
    (void)downloadTask;
    (void)bytesWritten;
    if (self.currentProgressHandler) {
        double p = totalBytesExpectedToWrite > 0 ? (double)totalBytesWritten / (double)totalBytesExpectedToWrite : 0.0;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.currentProgressHandler(p, totalBytesWritten, totalBytesExpectedToWrite);
        });
    }
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location {
    (void)session;
    (void)downloadTask;
    NSError *error = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:self.currentDestinationURL.path]) {
        [[NSFileManager defaultManager] removeItemAtURL:self.currentDestinationURL error:nil];
    }
    [[NSFileManager defaultManager] moveItemAtURL:location toURL:self.currentDestinationURL error:&error];
    if (error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.currentCompletionHandler) self.currentCompletionHandler(nil, nil, error);
        });
        return;
    }

    NSData *data = [NSData dataWithContentsOfURL:self.currentDestinationURL options:0 error:&error];
    if (!data) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.currentCompletionHandler) self.currentCompletionHandler(nil, nil, error);
        });
        return;
    }

    NSString *validation = TXFirmwareValidationError(data);
    if (validation) {
        NSError *vError = [NSError errorWithDomain:@"Lab599" code:-2 userInfo:@{NSLocalizedDescriptionKey: validation}];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.currentCompletionHandler) self.currentCompletionHandler(nil, nil, vError);
        });
        return;
    }

    NSString *hash = TXFirmwareSHA256(data);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.currentCompletionHandler) {
            self.currentCompletionHandler(self.currentDestinationURL, hash, nil);
        }
    });
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    (void)session;
    (void)task;
    if (error && self.currentCompletionHandler) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.currentCompletionHandler(nil, nil, error);
        });
    }
}

@end
