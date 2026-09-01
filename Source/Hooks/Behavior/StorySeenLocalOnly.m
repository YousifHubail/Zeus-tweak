#import "Include.h"
#import "Include/ZeusTweakCommon.h"
#import <objc/runtime.h>

/* Block story seen uploads while optionally leaving local/UI state untouched. */

#pragma mark - Networker ivar swap (idempotent merges)

static __weak id zeusLegacySeenUploader = nil;
static __weak id zeusSundialSeenManager = nil;
/** IDA: story marks can use `-[IGUserSession reelSeenStateUploader]` in parallel to pending-store uploaders. */
static __weak id zeusReelSeenStateUploader = nil;

/** Each entry: @{ @"obj": upload object, @"ivar": @(ivar_ptr), @"was": prior networker } */
static NSMutableArray<NSDictionary *> *zeusSeenNetSwapRecords = nil;

static BOOL zeus_seenClassHintsUploader(__unsafe_unretained id obj) {
    if (!obj) return NO;
    NSString *n = NSStringFromClass(object_getClass(obj));
    NSRange su = [n rangeOfString:@"SeenStateUploader"];
    if (su.location != NSNotFound) return YES;
    NSRange ss = [n rangeOfString:@"StorySeen"];
    NSRange up = [n rangeOfString:@"Upload"];
    if (ss.location != NSNotFound && up.location != NSNotFound) return YES;
    return NO;
}

static BOOL zeus_seenClassHintsSwiftManager(__unsafe_unretained id obj) {
    if (!obj) return NO;
    NSString *n = NSStringFromClass(object_getClass(obj));
    if ([n rangeOfString:@"SundialSeenState"].location != NSNotFound) return YES;
    if ([n rangeOfString:@"IGSundialSeenStateManager"].location != NSNotFound) return YES;
    return NO;
}

static BOOL zeus_classHintsSeenNetworkingHost(__unsafe_unretained id obj) {
    if (!obj) return NO;
    if (zeus_seenClassHintsUploader(obj) || zeus_seenClassHintsSwiftManager(obj)) return YES;
    NSString *n = NSStringFromClass(object_getClass(obj));
    if ([n rangeOfString:@"SeenState"].location != NSNotFound) return YES;
    if ([n rangeOfString:@"PendingSeen"].location != NSNotFound) return YES;
    if ([n rangeOfString:@"StorySeen"].location != NSNotFound) return YES;
    return NO;
}

static BOOL zeus_ivarNameHintsInjectableNetworkService(NSString *iname) {
    if (!iname.length) return NO;
    NSString *l = iname.lowercaseString;
    if ([l containsString:@"networker"]) return YES;
    if ([l containsString:@"graphql"] && ![l containsString:@"schema"]) return YES;
    if ([l containsString:@"tigon"]) return YES;
    if ([l containsString:@"bladerunner"]) return YES;
    if ([l isEqualToString:@"msi"]) return YES;
    return NO;
}

/** Fullscreen VC / section: only nil networking ivars clearly tied to story seen. */
static BOOL zeus_ivarNameHintsStoryReceiptNetwork(NSString *iname) {
    if (!zeus_ivarNameHintsInjectableNetworkService(iname)) return NO;
    NSString *l = iname.lowercaseString;
    return [l containsString:@"seen"] || [l containsString:@"pending"] || [l containsString:@"receipt"]
        || [l containsString:@"sundial"] || [l containsString:@"upload"] || [l containsString:@"state"];
}

static BOOL zeus_holderAcceptsNetworkishStrip(__unsafe_unretained id holder) {
    if (!holder) return NO;
    // Only strip known seen-upload hosts. Never touch the story viewer / section
    // controller — nil'ing their "state"/"upload" ivars crashes didMarkItemAsSeen.
    return zeus_classHintsSeenNetworkingHost(holder);
}

static __unsafe_unretained id zeusHarvestSection = nil;
static __unsafe_unretained id zeusHarvestViewer = nil;

static NSString *zeus_swapKey(id obj, Ivar iv) {
    return [NSString stringWithFormat:@"%p|%p", obj, iv];
}

static void zeus_recordNilNetworkishIvar(id holder, Ivar iv) {
    if (!holder || !iv) return;
    NSString *iname = @(ivar_getName(iv));
    BOOL allow = NO;
    if (zeus_classHintsSeenNetworkingHost(holder))
        allow = zeus_ivarNameHintsInjectableNetworkService(iname);
    else if (zeus_holderAcceptsNetworkishStrip(holder))
        allow = zeus_ivarNameHintsStoryReceiptNetwork(iname);
    if (!allow) return;

    const char *enc = ivar_getTypeEncoding(iv);
    if (!enc || enc[0] != '@') return;
    id cur = nil;
    @try { cur = object_getIvar(holder, iv); } @catch (__unused NSException *e) {}
    if (!cur || cur == holder) return;
    if ([cur isKindOfClass:[NSNumber class]] || [cur isKindOfClass:[NSString class]]) return;

    NSString *k = zeus_swapKey(holder, iv);
    if (zeusSeenNetSwapRecords) {
        for (NSDictionary *rec in zeusSeenNetSwapRecords) {
            if ([rec[@"key"] isEqualToString:k]) return;
        }
    }
    @try { object_setIvar(holder, iv, nil); } @catch (__unused NSException *e) { return; }
    NSDictionary *entry = @{ @"obj": holder, @"ivar": @((NSUInteger)(uintptr_t)iv), @"was": cur, @"key": k };
    if (!zeusSeenNetSwapRecords)
        zeusSeenNetSwapRecords = [NSMutableArray array];
    [zeusSeenNetSwapRecords addObject:entry];
}

static void zeus_stripNetworkishIvarsOnHolder(id holder) {
    if (!zeus_holderAcceptsNetworkishStrip(holder)) return;
    for (Class cls = object_getClass(holder); cls; cls = class_getSuperclass(cls)) {
        unsigned ivc = 0;
        Ivar *ivlist = class_copyIvarList(cls, &ivc);
        if (!ivlist) continue;
        for (unsigned i = 0; i < ivc; i++)
            zeus_recordNilNetworkishIvar(holder, ivlist[i]);
        free(ivlist);
    }
}

static void zeus_seenHarvestUploadersWalkingIvars(id root, NSUInteger maxDepth, NSMutableSet<id> *visited) {
    if (!root || maxDepth == 0) return;
    if ([visited containsObject:root]) return;
    [visited addObject:root];

    for (Class cls = object_getClass(root); cls; cls = class_getSuperclass(cls)) {
        unsigned ivc = 0;
        Ivar *ivlist = class_copyIvarList(cls, &ivc);
        if (!ivlist) continue;
        for (unsigned i = 0; i < ivc; i++) {
            Ivar iv = ivlist[i];
            const char *enc = ivar_getTypeEncoding(iv);
            if (!enc || enc[0] != '@') continue;

            NSString *iname = @(ivar_getName(iv));
            NSString *lower = [iname lowercaseString];
            BOOL interest = ([lower containsString:@"seen"] || [lower containsString:@"upload"] || [lower containsString:@"sundial"]
                || [lower containsString:@"reel"]);
            id val = nil;
            @try { val = object_getIvar(root, iv); } @catch (__unused NSException *e) {}
            if (!val || val == root) continue;

            if ([val isKindOfClass:[NSNumber class]]
                || [val isKindOfClass:[NSString class]]
                || [val isKindOfClass:[NSValue class]]
                || [val isKindOfClass:[NSDate class]])
                continue;

            if (zeus_seenClassHintsUploader(val))
                zeusLegacySeenUploader = val;
            else if (zeus_seenClassHintsSwiftManager(val))
                zeusSundialSeenManager = val;

            /* One extra hop helps when IG nests uploader/man inside a coordinator. */
            if (interest && ![val isKindOfClass:[UIView class]])
                zeus_seenHarvestUploadersWalkingIvars(val, maxDepth - 1u, visited);
        }
        free(ivlist);
    }
}

void ZUStorySeenReceiptNetworkGuardHarvestFromContext(id fullscreenSectionController, id storyViewer) {
    if (!ENABLED(@"Seen Receipts Stay Local")) return;
    NSMutableSet *seen = [NSMutableSet setWithCapacity:8];
    zeus_seenHarvestUploadersWalkingIvars(fullscreenSectionController, 2u, seen);
    [seen removeAllObjects];
    zeus_seenHarvestUploadersWalkingIvars(storyViewer, 3u, seen);
    /* Section view models often retain the sundial/live uploader graphs. */
    @try {
        id vmSec = nil;
        if (fullscreenSectionController)
            vmSec = [fullscreenSectionController valueForKey:@"viewModel"];
        zeus_seenHarvestUploadersWalkingIvars(vmSec, 3u, [NSMutableSet set]);
    } @catch (__unused NSException *e) {}
    @try {
        id vmTop = nil;
        if (storyViewer) {
            @try { vmTop = [storyViewer valueForKey:@"currentViewModel"]; } @catch (__unused NSException *e2) {}
            if (!vmTop)
                vmTop = [storyViewer valueForKey:@"viewModel"];
        }
        zeus_seenHarvestUploadersWalkingIvars(vmTop, 3u, [NSMutableSet set]);
    } @catch (__unused NSException *e) {}

    /* Session-scoped reel uploader (IGUserSession) — critical path on newer IG. */
    void (^grabReel)(id) = ^(id host) {
        if (!host) return;
        id session = nil;
        @try { session = [host valueForKey:@"userSession"]; } @catch (__unused NSException *e) {}
        if (!session)
            @try { session = [host valueForKey:@"_userSession"]; } @catch (__unused NSException *e) {}
        if (!session) return;
        SEL sr = NSSelectorFromString(@"reelSeenStateUploader");
        if (![session respondsToSelector:sr]) return;
        id reel = ((id (*)(id, SEL))objc_msgSend)(session, sr);
        if (reel) zeusReelSeenStateUploader = reel;
    };
    @try {
        grabReel(storyViewer);
        grabReel(fullscreenSectionController);
    } @catch (__unused NSException *e) {}
}

static void zeus_seenNilUploaderNetworkerRecording(id upl) {
    if (!upl) return;
    Class uplCls = object_getClass(upl);
    Ivar netIv = class_getInstanceVariable(uplCls, "_networker");
    if (!netIv) netIv = class_getInstanceVariable(uplCls, "networker");
    if (!netIv) return;
    id cur = nil;
    @try { cur = object_getIvar(upl, netIv); } @catch (__unused NSException *e) {}
    if (!cur) return;
    NSString *k = zeus_swapKey(upl, netIv);
    BOOL already = NO;
    if (zeusSeenNetSwapRecords) {
        for (NSDictionary *rec in zeusSeenNetSwapRecords) {
            if ([rec[@"key"] isEqualToString:k]) {
                already = YES;
                break;
            }
        }
    }
    if (already) return;
    @try {
        object_setIvar(upl, netIv, nil);
    } @catch (__unused NSException *e) { return; }

    if (!zeusSeenNetSwapRecords)
        zeusSeenNetSwapRecords = [NSMutableArray array];
    NSDictionary *entry = @{ @"obj": upl, @"ivar": @((NSUInteger)(uintptr_t)netIv), @"was": cur, @"key": k };
    [zeusSeenNetSwapRecords addObject:entry];
}

static void zeus_applySeenNetworkerSwapPass(void) {
    if (!zeusSeenNetSwapRecords)
        zeusSeenNetSwapRecords = [NSMutableArray array];

    zeus_seenNilUploaderNetworkerRecording(zeusLegacySeenUploader);
    zeus_seenNilUploaderNetworkerRecording(zeusReelSeenStateUploader);

    id mgr = zeusSundialSeenManager;
    if (mgr) {
        Class mgrCls = object_getClass(mgr);
        for (NSString *ivName in @[ @"seenStateUploader", @"seenStateUploaderDeprecated" ]) {
            Ivar mgrIv = class_getInstanceVariable(mgrCls, [ivName UTF8String]);
            if (!mgrIv) continue;
            id upl = nil;
            @try { upl = object_getIvar(mgr, mgrIv); } @catch (__unused NSException *e) {}
            zeus_seenNilUploaderNetworkerRecording(upl);
        }
    }

    /* Strip GraphQL / Tigon / alternate network injections (names vary by IG build). */
    zeus_stripNetworkishIvarsOnHolder(zeusLegacySeenUploader);
    zeus_stripNetworkishIvarsOnHolder(zeusReelSeenStateUploader);
    zeus_stripNetworkishIvarsOnHolder(zeusSundialSeenManager);
    zeus_stripNetworkishIvarsOnHolder(zeusHarvestSection);
    zeus_stripNetworkishIvarsOnHolder(zeusHarvestViewer);
}

void ZUStorySeenReceiptNetworkGuardEnterWithContext(id fullscreenSectionController, id storyViewer) {
    if (!ENABLED(@"Seen Receipts Stay Local")) return;
    zeusHarvestSection = fullscreenSectionController;
    zeusHarvestViewer = storyViewer;
    ZUStorySeenReceiptNetworkGuardHarvestFromContext(fullscreenSectionController, storyViewer);
    zeus_applySeenNetworkerSwapPass();
}

void ZUStorySeenReceiptNetworkGuardResealAfterMark(id fullscreenSectionController, id storyViewer) {
    if (!ENABLED(@"Seen Receipts Stay Local")) return;
    id sec = fullscreenSectionController ?: zeusHarvestSection;
    id vc = storyViewer ?: zeusHarvestViewer;
    ZUStorySeenReceiptNetworkGuardHarvestFromContext(sec, vc);
    zeus_applySeenNetworkerSwapPass();
}

void ZUStorySeenReceiptNetworkGuardEnter(void) {
    ZUStorySeenReceiptNetworkGuardEnterWithContext(nil, nil);
}

void ZUStorySeenReceiptNetworkGuardLeave(void) {
    if (!zeusSeenNetSwapRecords.count) return;
    /* Restore in reverse so nested edits collapse safely. */
    for (NSUInteger i = zeusSeenNetSwapRecords.count; i > 0; i--) {
        NSDictionary *entry = zeusSeenNetSwapRecords[i - 1];
        id obj = entry[@"obj"];
        NSUInteger ivOpaque = [(NSNumber *)entry[@"ivar"] unsignedIntegerValue];
        Ivar iv = (Ivar)(uintptr_t)ivOpaque;
        id was = entry[@"was"];
        if (!obj || !iv) continue;
        @try { object_setIvar(obj, iv, was); } @catch (__unused NSException *e) {}
    }
    [zeusSeenNetSwapRecords removeAllObjects];
}

static id (*orig_pendingStoreInit)(id, SEL, id, id, id, BOOL);
static id hook_pendingStoreInit(id self, SEL _cmd, id sessionPK, id uploader, id fileMgr, BOOL bgTask) {
    if (uploader) zeusLegacySeenUploader = uploader;
    return orig_pendingStoreInit(self, _cmd, sessionPK, uploader, fileMgr, bgTask);
}

static id (*orig_sundialMgrInit)(id, SEL, id, id, id, id);
static id hook_sundialMgrInit(id self, SEL _cmd, id networker, id diskMgr, id launcherSet, id announcer) {
    id res = orig_sundialMgrInit(self, _cmd, networker, diskMgr, launcherSet, announcer);
    if (res) zeusSundialSeenManager = res;
    return res;
}

#pragma mark - Uploader hooks

static BOOL zeus_blockSeenReceipts(void) {
    return ENABLED(@"Seen Receipts Stay Local");
}

static void (*orig_sundialUploadSeenStateIfNecessary)(id, SEL);
static void hook_sundialUploadSeenStateIfNecessary(id self, SEL _cmd) {
    if (zeus_blockSeenReceipts()) return;
    orig_sundialUploadSeenStateIfNecessary(self, _cmd);
}

static void (*orig_sundialAppendSeenState)(id, SEL, id);
static void hook_sundialAppendSeenState(id self, SEL _cmd, id payload) {
    if (zeus_blockSeenReceipts()) return;
    orig_sundialAppendSeenState(self, _cmd, payload);
}

static void (*orig_uploadSeenMedia)(id, SEL, id);
static void hook_uploadSeenMedia(id self, SEL _cmd, id media) {
    if (zeus_blockSeenReceipts()) return;
    orig_uploadSeenMedia(self, _cmd, media);
}

static void (*orig_uploadSeenState)(id, SEL);
static void hook_uploadSeenState(id self, SEL _cmd) {
    if (zeus_blockSeenReceipts()) return;
    orig_uploadSeenState(self, _cmd);
}

static void (*orig_uploadSeenStateArg)(id, SEL, id);
static void hook_uploadSeenStateArg(id self, SEL _cmd, id arg1) {
    if (zeus_blockSeenReceipts()) return;
    orig_uploadSeenStateArg(self, _cmd, arg1);
}

static void (*orig_sendSeenReceipt)(id, SEL, id);
static void hook_sendSeenReceipt(id self, SEL _cmd, id arg1) {
    if (zeus_blockSeenReceipts()) return;
    orig_sendSeenReceipt(self, _cmd, arg1);
}

static void (*orig_sendSeenRequestForCurrentItem)(id, SEL);
static void hook_sendSeenRequestForCurrentItem(id self, SEL _cmd) {
    if (zeus_blockSeenReceipts()) return;
    orig_sendSeenRequestForCurrentItem(self, _cmd);
}

static void (*orig_sendSeenRequestForCurrentItemPriv)(id, SEL);
static void hook_sendSeenRequestForCurrentItemPriv(id self, SEL _cmd) {
    if (zeus_blockSeenReceipts()) return;
    orig_sendSeenRequestForCurrentItemPriv(self, _cmd);
}

static void (*orig_enqueueSeenStateForMedia)(id, SEL, id);
static void hook_enqueueSeenStateForMedia(id self, SEL _cmd, id media) {
    if (zeus_blockSeenReceipts()) return;
    orig_enqueueSeenStateForMedia(self, _cmd, media);
}

static void (*orig_uploadSeenStateWithStoryItem)(id, SEL, id);
static void hook_uploadSeenStateWithStoryItem(id self, SEL _cmd, id storyItem) {
    if (zeus_blockSeenReceipts()) return;
    orig_uploadSeenStateWithStoryItem(self, _cmd, storyItem);
}

static void (*orig_enqueueSeenStateWithStoryItem)(id, SEL, id);
static void hook_enqueueSeenStateWithStoryItem(id self, SEL _cmd, id storyItem) {
    if (zeus_blockSeenReceipts()) return;
    orig_enqueueSeenStateWithStoryItem(self, _cmd, storyItem);
}

static void (*orig_sectionFlushQueuedSeenRequests)(id, SEL);
static void hook_sectionFlushQueuedSeenRequests(id self, SEL _cmd) {
    if (zeus_blockSeenReceipts()) return;
    orig_sectionFlushQueuedSeenRequests(self, _cmd);
}

static void (*orig_sectionFlushQueuedSeenRequestsPriv)(id, SEL);
static void hook_sectionFlushQueuedSeenRequestsPriv(id self, SEL _cmd) {
    if (zeus_blockSeenReceipts()) return;
    orig_sectionFlushQueuedSeenRequestsPriv(self, _cmd);
}

static void (*orig_sectionEnqueueSeenForPlayhead)(id, SEL);
static void hook_sectionEnqueueSeenForPlayhead(id self, SEL _cmd) {
    if (zeus_blockSeenReceipts()) return;
    orig_sectionEnqueueSeenForPlayhead(self, _cmd);
}

#pragma mark - Pending store (blocks secondary flush paths)

static void (*orig_pendingFlushSeenStates)(id, SEL);
static void hook_pendingFlushSeenStates(id self, SEL _cmd) {
    if (zeus_blockSeenReceipts()) return;
    orig_pendingFlushSeenStates(self, _cmd);
}

static void (*orig_pendingFlushSeenStatesPriv)(id, SEL);
static void hook_pendingFlushSeenStatesPriv(id self, SEL _cmd) {
    if (zeus_blockSeenReceipts()) return;
    orig_pendingFlushSeenStatesPriv(self, _cmd);
}

static void (*orig_pendingUploadSeenStates)(id, SEL);
static void hook_pendingUploadSeenStates(id self, SEL _cmd) {
    if (zeus_blockSeenReceipts()) return;
    orig_pendingUploadSeenStates(self, _cmd);
}

static void (*orig_pendingUploadSeenStatesPriv)(id, SEL);
static void hook_pendingUploadSeenStatesPriv(id self, SEL _cmd) {
    if (zeus_blockSeenReceipts()) return;
    orig_pendingUploadSeenStatesPriv(self, _cmd);
}

static void (*orig_storyViewerDisappear)(id, SEL, BOOL);
static void hook_storyViewerDisappear(id self, SEL _cmd, BOOL anim) {
    ZUStorySeenReceiptNetworkGuardLeave();
    orig_storyViewerDisappear(self, _cmd, anim);
}

void ZURegisterStorySeenLocalOnlyHooks(void) {
    Class pending = objc_getClass("IGStoryPendingSeenStateStore");
    SEL pendingSel = NSSelectorFromString(@"initWithUserSessionPK:uploader:fileManager:uploadInBackgroundTask:");
    if (pending && class_getInstanceMethod(pending, pendingSel))
        NullHookMessageEx(pending, pendingSel, (void *)hook_pendingStoreInit, &orig_pendingStoreInit);
    if (pending) {
        NullHookMessageIfPresent(pending, NSSelectorFromString(@"flushPendingSeenStates"),
            (void *)hook_pendingFlushSeenStates, &orig_pendingFlushSeenStates);
        NullHookMessageIfPresent(pending, NSSelectorFromString(@"_flushPendingSeenStates"),
            (void *)hook_pendingFlushSeenStatesPriv, &orig_pendingFlushSeenStatesPriv);
        NullHookMessageIfPresent(pending, NSSelectorFromString(@"uploadPendingSeenStates"),
            (void *)hook_pendingUploadSeenStates, &orig_pendingUploadSeenStates);
        NullHookMessageIfPresent(pending, NSSelectorFromString(@"_uploadPendingSeenStates"),
            (void *)hook_pendingUploadSeenStatesPriv, &orig_pendingUploadSeenStatesPriv);
    }

    Class sundialMgr = objc_getClass("_TtC23IGSundialSeenStateSwift25IGSundialSeenStateManager");
    SEL mgrSel = NSSelectorFromString(@"initWithNetworker:diskManager:launcherSet:seenStateManagerAnnouncer:");
    if (sundialMgr && class_getInstanceMethod(sundialMgr, mgrSel))
        NullHookMessageEx(sundialMgr, mgrSel, (void *)hook_sundialMgrInit, &orig_sundialMgrInit);
    if (sundialMgr) {
        NullHookMessageIfPresent(sundialMgr, @selector(uploadSeenStateIfNecessary), (void *)hook_sundialUploadSeenStateIfNecessary,
            &orig_sundialUploadSeenStateIfNecessary);
        NullHookMessageIfPresent(sundialMgr, @selector(appendSeenState:), (void *)hook_sundialAppendSeenState, &orig_sundialAppendSeenState);
    }

    Class viewer = objc_getClass("IGStoryViewerViewController");
    if (viewer)
        NullHookMessageEx(viewer, @selector(viewWillDisappear:), (void *)hook_storyViewerDisappear, &orig_storyViewerDisappear);

    /* Legacy ObjC uploader selectors often disappear once Swift wraps receipts; suppression still runs via networker-nil + fullscreen hook. */
    Class uploader = objc_getClass("IGStorySeenStateUploader");
    if (uploader) {
        NullHookMessageIfPresent(uploader, @selector(uploadSeenStateWithMedia:), (void *)hook_uploadSeenMedia, &orig_uploadSeenMedia);
        NullHookMessageIfPresent(uploader, @selector(uploadSeenState), (void *)hook_uploadSeenState, &orig_uploadSeenState);
        NullHookMessageIfPresent(uploader, NSSelectorFromString(@"_uploadSeenState:"), (void *)hook_uploadSeenStateArg, &orig_uploadSeenStateArg);
        NullHookMessageIfPresent(uploader, @selector(sendSeenReceipt:), (void *)hook_sendSeenReceipt, &orig_sendSeenReceipt);
        NullHookMessageIfPresent(uploader, NSSelectorFromString(@"enqueueSeenStateForMedia:"), (void *)hook_enqueueSeenStateForMedia, &orig_enqueueSeenStateForMedia);
        NullHookMessageIfPresent(uploader, NSSelectorFromString(@"uploadSeenStateWithStoryItem:"), (void *)hook_uploadSeenStateWithStoryItem, &orig_uploadSeenStateWithStoryItem);
        NullHookMessageIfPresent(uploader, NSSelectorFromString(@"enqueueSeenStateWithStoryItem:"), (void *)hook_enqueueSeenStateWithStoryItem, &orig_enqueueSeenStateWithStoryItem);
    }

    Class section = objc_getClass("IGStoryFullscreenSectionController");
    if (section) {
        NullHookMessageIfPresent(section, @selector(sendSeenRequestForCurrentItem), (void *)hook_sendSeenRequestForCurrentItem, &orig_sendSeenRequestForCurrentItem);
        NullHookMessageIfPresent(section, NSSelectorFromString(@"_sendSeenRequestForCurrentItem"), (void *)hook_sendSeenRequestForCurrentItemPriv, &orig_sendSeenRequestForCurrentItemPriv);
        NullHookMessageIfPresent(section, NSSelectorFromString(@"flushQueuedSeenRequests"), (void *)hook_sectionFlushQueuedSeenRequests, &orig_sectionFlushQueuedSeenRequests);
        NullHookMessageIfPresent(section, NSSelectorFromString(@"_flushQueuedSeenRequests"), (void *)hook_sectionFlushQueuedSeenRequestsPriv, &orig_sectionFlushQueuedSeenRequestsPriv);
        NullHookMessageIfPresent(section, NSSelectorFromString(@"enqueueSeenRequestForPlayhead"), (void *)hook_sectionEnqueueSeenForPlayhead, &orig_sectionEnqueueSeenForPlayhead);
    }
}
