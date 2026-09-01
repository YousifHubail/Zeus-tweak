#import "Include/ZUProfileAnalyzerDiffEngine.h"
#import "Include/ZUProfileAnalyzerTypes.h"

/** Profile analyzer report set math (mutual / subtract / intersect on user equality by pk). */

static NSArray<ZUProfileAnalyzerUser *> *ZUPANSubtract(NSArray<ZUProfileAnalyzerUser *> *a, NSSet<ZUProfileAnalyzerUser *> *bSet) {
    if (!a.count) return @[];
    NSMutableArray<ZUProfileAnalyzerUser *> *out = [NSMutableArray arrayWithCapacity:a.count];
    for (ZUProfileAnalyzerUser *u in a) {
        if (![bSet containsObject:u]) [out addObject:u];
    }
    return out;
}

static NSArray<ZUProfileAnalyzerUser *> *ZUPANIntersect(NSArray<ZUProfileAnalyzerUser *> *a, NSSet<ZUProfileAnalyzerUser *> *bSet) {
    if (!a.count) return @[];
    NSMutableArray<ZUProfileAnalyzerUser *> *out = [NSMutableArray arrayWithCapacity:a.count];
    for (ZUProfileAnalyzerUser *u in a) {
        if ([bSet containsObject:u]) [out addObject:u];
    }
    return out;
}

static NSArray<ZUProfileAnalyzerUser *> *ZUPANEnrichWithByPK(NSArray<ZUProfileAnalyzerUser *> *users, NSDictionary<NSString *, ZUProfileAnalyzerUser *> *byPK) {
    if (!byPK.count) return users;
    NSMutableArray<ZUProfileAnalyzerUser *> *out = [NSMutableArray arrayWithCapacity:users.count];
    for (ZUProfileAnalyzerUser *u in users) {
        ZUProfileAnalyzerUser *e = (u.pk.length && byPK[u.pk]) ? byPK[u.pk] : u;
        [out addObject:e];
    }
    return out;
}

@implementation ZUProfileAnalyzerDiffEngine

+ (NSDictionary<NSString *, ZUProfileAnalyzerUser *> *)usersByPKFromSnapshot:(ZUProfileAnalyzerSnapshot *)snapshot {
    NSMutableDictionary<NSString *, ZUProfileAnalyzerUser *> *byPK = [NSMutableDictionary dictionary];
    for (ZUProfileAnalyzerUser *u in snapshot.followers) if (u.pk.length) byPK[u.pk] = u;
    for (ZUProfileAnalyzerUser *u in snapshot.following) if (u.pk.length) byPK[u.pk] = u;
    return [byPK copy];
}

+ (ZUProfileAnalyzerDiffResult *)diffBetweenPreviousSnapshot:(ZUProfileAnalyzerSnapshot *)previous currentSnapshot:(ZUProfileAnalyzerSnapshot *)current usersByPK:(NSDictionary<NSString *, ZUProfileAnalyzerUser *> *)usersByPK {
    NSSet<ZUProfileAnalyzerUser *> *followersSet = [NSSet setWithArray:current.followers];
    NSSet<ZUProfileAnalyzerUser *> *followingSet = [NSSet setWithArray:current.following];

    NSArray<ZUProfileAnalyzerUser *> *mutual = ZUPANIntersect(current.followers, followingSet);
    NSArray<ZUProfileAnalyzerUser *> *notBack = ZUPANSubtract(current.following, followersSet);
    NSArray<ZUProfileAnalyzerUser *> *youDont = ZUPANSubtract(current.followers, followingSet);

    NSArray<ZUProfileAnalyzerUser *> *gained = @[], *lost = @[], *addF = @[], *remF = @[];
    if (previous) {
        NSSet<ZUProfileAnalyzerUser *> *prevFollowers = [NSSet setWithArray:previous.followers];
        NSSet<ZUProfileAnalyzerUser *> *prevFollowing = [NSSet setWithArray:previous.following];
        gained = ZUPANSubtract(current.followers, prevFollowers);
        lost = ZUPANSubtract(previous.followers, followersSet);
        addF = ZUPANSubtract(current.following, prevFollowing);
        remF = ZUPANSubtract(previous.following, followingSet);
    }

    ZUProfileAnalyzerDiffResult *r = [[ZUProfileAnalyzerDiffResult alloc] init];
    r.mutualFollowers = ZUPANEnrichWithByPK(mutual, usersByPK);
    r.notFollowingMeBack = ZUPANEnrichWithByPK(notBack, usersByPK);
    r.youDontFollowBack = ZUPANEnrichWithByPK(youDont, usersByPK);
    r.followersGained = ZUPANEnrichWithByPK(gained, usersByPK);
    r.followersLost = ZUPANEnrichWithByPK(lost, usersByPK);
    r.followingAdded = ZUPANEnrichWithByPK(addF, usersByPK);
    r.followingRemoved = ZUPANEnrichWithByPK(remF, usersByPK);
    return r;
}

@end
