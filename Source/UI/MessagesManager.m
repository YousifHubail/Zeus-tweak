#import "Include/MessagesManager.h"
#import "Include/CustomToastView.h"
#import "Include/ZeusHelper.h"

#define ENABLED(setting) [[NSUserDefaults standardUserDefaults] boolForKey:[NSString stringWithFormat:@"%@_Enabled", setting]]

@implementation MessagesManager

NSString *const plistFileName = @"deleted_messages.plist";

// Image generation moved to ZeusHelper

// Toast functionality moved to ZeusHelper

// Haptic feedback moved to ZeusHelper

+ (instancetype)sharedManager {
    static MessagesManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (NSString *)plistPath {
    NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    return [documentsDirectory stringByAppendingPathComponent:plistFileName];
}

- (NSMutableDictionary *)loadPlistData {
    NSString *path = [self plistPath];
    NSMutableDictionary *data = [NSMutableDictionary dictionaryWithContentsOfFile:path];
    if (!data) {
        data = [NSMutableDictionary dictionary];
    }
    return data;
}

- (void)savePlistData:(NSDictionary *)data {
    NSString *path = [self plistPath];
    [data writeToFile:path atomically:YES];
}

- (void)saveDeletedMessageWithID:(NSString *)messageID {
    if (messageID.length == 0) {
        NSLog(@"Message ID cannot be empty.");
        return;
    }
    
    NSMutableDictionary *plistData = [self loadPlistData];
    NSString *currentDate = [[NSDate date] description];
    plistData[messageID] = currentDate;
    [self savePlistData:plistData];

    if (ENABLED(@"Show Banners")) {
        [ZeusHelper showToastWithTitle:@"Someone deleted a message." subtitle:nil icon:[ZeusHelper imageFromEmojiString:@"🗑️" width:60] autoHide:4 openURL:nil];
    }
}

- (BOOL)messageExistsWithID:(NSString *)messageID {
    if (messageID.length == 0) {
        NSLog(@"Message ID cannot be empty.");
        return NO;
    }
    
    NSMutableDictionary *plistData = [self loadPlistData];
    return plistData[messageID] != nil;
}

- (NSString *)dateForDeletedMessageWithID:(NSString *)messageID {
    if (messageID.length == 0) {
        NSLog(@"Message ID cannot be empty.");
        return nil;
    }

    NSMutableDictionary *plistData = [self loadPlistData];
    return plistData[messageID];
}

- (NSString *)mediaCacheDirectory {
    NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *dir = [documentsDirectory stringByAppendingPathComponent:@"ZeusDeletedMedia"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:dir]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return dir;
}

// Filesystem-safe cache key for a URL; djb2 is enough since we only need
// stable uniqueness per-URL, not cryptographic strength.
- (NSString *)cacheKeyForURL:(NSURL *)url {
    NSString *s = url.absoluteString;
    if (s.length == 0) return nil;
    unsigned long hash = 5381;
    for (NSUInteger i = 0; i < s.length; i++) {
        hash = ((hash << 5) + hash) + [s characterAtIndex:i];
    }
    NSString *ext = url.pathExtension.length > 0 ? url.pathExtension : @"dat";
    return [NSString stringWithFormat:@"%lu.%@", hash, ext];
}

- (NSString *)cachedMediaPathForURL:(NSURL *)url {
    NSString *key = [self cacheKeyForURL:url];
    if (!key) return nil;
    NSString *path = [[self mediaCacheDirectory] stringByAppendingPathComponent:key];
    return [[NSFileManager defaultManager] fileExistsAtPath:path] ? path : nil;
}

// Fire-and-forget: downloads the resource once and leaves it on disk. Safe to
// call on every render of a message's media — it's a no-op once cached, and
// this is what lets the content survive after the sender deletes it (the
// live URL can stop resolving, but bytes already saved locally don't care).
- (void)cacheMediaIfNeededFromURL:(NSURL *)url {
    if (!url || [self cachedMediaPathForURL:url]) return;
    NSString *key = [self cacheKeyForURL:url];
    if (!key) return;
    NSString *destPath = [[self mediaCacheDirectory] stringByAppendingPathComponent:key];
    NSString *tmpPath = [destPath stringByAppendingPathExtension:@"part"];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || data.length == 0) return;
        [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
        if (![data writeToFile:tmpPath atomically:YES]) return;
        [[NSFileManager defaultManager] removeItemAtPath:destPath error:nil];
        [[NSFileManager defaultManager] moveItemAtPath:tmpPath toPath:destPath error:nil];
    }];
    [task resume];
}
@end