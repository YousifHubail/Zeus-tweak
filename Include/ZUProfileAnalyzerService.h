//
// Profile analyzer service — pagination + guards — using TH networking.
//

#import <Foundation/Foundation.h>
@class ZUProfileAnalyzerAPIClient;
@class ZUProfileAnalyzerSnapshot;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ZUProfileAnalyzerServiceError) {
    ZUProfileAnalyzerServiceErrorNoSession = 1,
    ZUProfileAnalyzerServiceErrorTooManyFollowers,
    ZUProfileAnalyzerServiceErrorNetwork,
    ZUProfileAnalyzerServiceErrorCancelled,
    /** Repeated requests after backoff still rejected (likely Instagram throttle / spam block). */
    ZUProfileAnalyzerServiceErrorRateLimited,
};

/** Refuse analysis above this follower count (rate-limit / practicality). */
extern const NSInteger ZUProfileAnalyzerMaxAnalyzableFollowers;

typedef void (^ZUProfileAnalyzerHeaderInfoBlock)(NSDictionary *userInfo);
typedef void (^ZUProfileAnalyzerFractionProgressBlock)(NSString *status, double fraction);

@interface ZUProfileAnalyzerService : NSObject

@property (nonatomic, readonly) BOOL isRunning;

- (instancetype)initWithAPIClient:(ZUProfileAnalyzerAPIClient *)client userPK:(NSString *)userPK;

- (void)runForSelfWithHeaderInfo:(nullable ZUProfileAnalyzerHeaderInfoBlock)headerInfo
                        progress:(nullable ZUProfileAnalyzerFractionProgressBlock)progress
                      completion:(void (^)(ZUProfileAnalyzerSnapshot * _Nullable snapshot, NSError * _Nullable error))completion;

- (void)cancel;

@end

NS_ASSUME_NONNULL_END
