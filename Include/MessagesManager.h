#import <Foundation/Foundation.h>

@interface MessagesManager : NSObject
+(instancetype)sharedManager;
-(void)saveDeletedMessageWithID:(NSString *)messageID;
-(BOOL)messageExistsWithID:(NSString *)messageID;
-(NSString *)dateForDeletedMessageWithID:(NSString *)messageID;
-(NSMutableDictionary *)loadPlistData;
-(void)savePlistData:(NSDictionary *)data;

// Local media cache so a DM photo/video already viewed once can still be
// recovered after the sender deletes it (the live CDN URL stops resolving,
// but bytes already on disk don't depend on that).
-(NSString *)cachedMediaPathForURL:(NSURL *)url;
-(void)cacheMediaIfNeededFromURL:(NSURL *)url;
@end
