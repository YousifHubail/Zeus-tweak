#import "Include/ZUProfileAnalyzerAPIClient.h"

NSString * const ZUProfileAnalyzerAPIBaseURL = @"https://i.instagram.com/api/v1/";

@implementation ZUProfileAnalyzerAPIClient

+ (NSString *)fullURLWithEndpointPath:(NSString *)path queryParams:(NSDictionary<NSString *, NSString *> *)params {
    NSString *trimmed = path;
    if ([trimmed hasPrefix:@"/"]) trimmed = [trimmed substringFromIndex:1];
    NSString *base = ZUProfileAnalyzerAPIBaseURL;
    NSString *pathOnly = [base hasSuffix:@"/"] ? [base stringByAppendingString:trimmed] : [base stringByAppendingFormat:@"/%@", trimmed];
    if (!params || params.count == 0) return pathOnly;
    NSURLComponents *c = [NSURLComponents componentsWithString:pathOnly];
    if (!c) return pathOnly;
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
    for (NSString *key in params) {
        NSString *val = params[key];
        if (key.length && val) [items addObject:[NSURLQueryItem queryItemWithName:key value:val]];
    }
    c.queryItems = items;
    return c.URL.absoluteString ?: pathOnly;
}

- (void)GETWithEndpointPath:(NSString *)path queryParams:(NSDictionary<NSString *, NSString *> *)params success:(void (^)(NSDictionary * _Nullable))success failure:(void (^)(NSError * _Nonnull))failure {
    NSString *urlString = [self.class fullURLWithEndpointPath:path queryParams:params];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        if (failure) failure([NSError errorWithDomain:@"ZUProfileAnalyzer" code:-1 userInfo:@{ NSLocalizedDescriptionKey: @"Invalid URL" }]);
        return;
    }
    id<ZUProfileAnalyzerAPIClientNetworkDelegate> delegate = _networkDelegate;
    if (!delegate) {
        if (failure) failure([NSError errorWithDomain:@"ZUProfileAnalyzer" code:-2 userInfo:@{ NSLocalizedDescriptionKey: @"No network delegate" }]);
        return;
    }
    [delegate performGETRequestWithURL:url success:success failure:failure];
}

@end
