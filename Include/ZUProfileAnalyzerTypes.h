//
// ZUProfileAnalyzerTypes.h
// Profile Analyzer types for Zeus (track who follows/unfollows you).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZUProfileAnalyzerUser : NSObject
@property (nonatomic, copy) NSString *pk;
@property (nonatomic, copy) NSString *username;
@property (nonatomic, copy, nullable) NSString *fullName;
@property (nonatomic, copy, nullable) NSString *profilePicURL;
@property (nonatomic, copy, nullable) NSString *profilePicID;
@property (nonatomic, assign) BOOL isPrivate;
@property (nonatomic, assign) BOOL isVerified;
- (instancetype)initWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)toDictionary;
/** API user row (pk_id, profile_pic_id, …). */
+ (nullable instancetype)userFromAPIDictionary:(NSDictionary *)dict;
@end

@interface ZUProfileAnalyzerSnapshot : NSObject
@property (nonatomic, copy) NSString *userPK;
@property (nonatomic, copy) NSDate *scannedAt;
@property (nonatomic, copy) NSArray<ZUProfileAnalyzerUser *> *followers;
@property (nonatomic, copy) NSArray<ZUProfileAnalyzerUser *> *following;
/** API-reported counts from users/<pk>/info/; -1 if not stored. Use for display when >= 0. */
@property (nonatomic, assign) NSInteger apiFollowersCount;
@property (nonatomic, assign) NSInteger apiFollowingCount;
/** Optional; from user info snapshot. */
@property (nonatomic, assign) NSInteger mediaCount;
- (instancetype)initWithUserPK:(NSString *)userPK scannedAt:(NSDate *)scannedAt followers:(NSArray<ZUProfileAnalyzerUser *> *)followers following:(NSArray<ZUProfileAnalyzerUser *> *)following;
@end

@interface ZUProfileAnalyzerDiffResult : NSObject
@property (nonatomic, copy) NSArray<ZUProfileAnalyzerUser *> *followersGained;
@property (nonatomic, copy) NSArray<ZUProfileAnalyzerUser *> *followersLost;
@property (nonatomic, copy) NSArray<ZUProfileAnalyzerUser *> *followingAdded;
@property (nonatomic, copy) NSArray<ZUProfileAnalyzerUser *> *followingRemoved;
@property (nonatomic, copy) NSArray<ZUProfileAnalyzerUser *> *mutualFollowers;
@property (nonatomic, copy) NSArray<ZUProfileAnalyzerUser *> *notFollowingMeBack;
@property (nonatomic, copy) NSArray<ZUProfileAnalyzerUser *> *youDontFollowBack;
@end

@interface ZUProfileAnalyzerResult : NSObject
@property (nonatomic, strong) ZUProfileAnalyzerSnapshot *currentSnapshot;
@property (nonatomic, strong, nullable) ZUProfileAnalyzerSnapshot *previousSnapshot;
@property (nonatomic, strong, nullable) ZUProfileAnalyzerDiffResult *diff;
@property (nonatomic, assign) NSInteger followersCount;
@property (nonatomic, assign) NSInteger followingCount;
@end

typedef void (^ZUProfileAnalyzerProgressBlock)(NSString * _Nullable message, NSInteger count);
typedef void (^ZUProfileAnalyzerCompletion)(ZUProfileAnalyzerResult * _Nullable result, NSError * _Nullable error);

NS_ASSUME_NONNULL_END
