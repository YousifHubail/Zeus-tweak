#import <Foundation/Foundation.h>
@class ZUProfileAnalyzerSnapshot;
@class ZUProfileAnalyzerDiffResult;
@class ZUProfileAnalyzerUser;

NS_ASSUME_NONNULL_BEGIN

@interface ZUProfileAnalyzerDiffEngine : NSObject
+ (nullable ZUProfileAnalyzerDiffResult *)diffBetweenPreviousSnapshot:(nullable ZUProfileAnalyzerSnapshot *)previous currentSnapshot:(ZUProfileAnalyzerSnapshot *)current usersByPK:(NSDictionary<NSString *, ZUProfileAnalyzerUser *> *)usersByPK;
+ (NSDictionary<NSString *, ZUProfileAnalyzerUser *> *)usersByPKFromSnapshot:(ZUProfileAnalyzerSnapshot *)snapshot;
@end

NS_ASSUME_NONNULL_END
