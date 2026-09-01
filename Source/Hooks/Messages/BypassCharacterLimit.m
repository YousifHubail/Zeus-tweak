static NSMutableSet<NSString *> *zeusThreadsShownBanner = nil;
static NSMutableDictionary<NSString *, NSString *> *zeusLastTextByKey = nil;
static NSMutableDictionary<NSString *, NSNumber *> *zeusLastShownAtByKey = nil;
static NSMutableDictionary<NSString *, NSNumber *> *zeusEmptySinceByKey = nil;
static NSMutableDictionary<NSString *, NSString *> *zeusPinnedKeyByVC = nil;
static NSString *const kZeusGlobalKey = @"__zeus_global__";
static const NSTimeInterval kZeusShowThrottleSeconds = 5.0; // prevent rapid re-triggering
extern BOOL zeus_hasUnreadFromRecipient(id threadVC);
void zeus_showMarkedAsSeenToastDeferred(void);
void zeus_performMarkLastMessageAsSeen(id threadViewController, id listViewController);
id zeus_activeDirectThreadViewController(void);
static const NSTimeInterval kZeusEmptyStableSeconds = 0.75; // require empty to be stable before reset
static void (*orig_directComposer2)(id self, SEL _cmd);
static void hook_directComposer2(id self, SEL _cmd) {
    @try {
        orig_directComposer2(self, _cmd);

        if (ENABLED(@"Seen On Typing")) {
            IGUser *lastSender = nil;

            UIViewController *viewController = [ZeusHelper nearestViewController:self];
            UIViewController *ballsThreadVC = nil;
            id msgListDataSource = nil;
            if ([viewController isKindOfClass:NSClassFromString(@"IGDirectComposerViewController")]) {
                ballsThreadVC = [viewController valueForKey:@"delegate"];
                msgListDataSource = [ballsThreadVC valueForKey:@"_messageListDataSource"];
                id lastSenderImg = [msgListDataSource performSelector:@selector(mostRecentMessageSenderProfileImage)];
                //lastSender = [lastSenderImg valueForKey:@"_profileImage_user"];
                
                // check if lastSenderImg has ivar '_profileImage_user' or '_profileImageModel_user'
                Ivar profileImageUserIvar = class_getInstanceVariable([lastSenderImg class], "_profileImage_user");
                if (profileImageUserIvar) {
                    lastSender = object_getIvar(lastSenderImg, profileImageUserIvar);
                } else {
                    profileImageUserIvar = class_getInstanceVariable([lastSenderImg class], "_profileImageModel_user");
                    if (profileImageUserIvar) {
                        lastSender = object_getIvar(lastSenderImg, profileImageUserIvar);
                    }
                }
            }
            if (!ballsThreadVC) {
                Class threadCls = NSClassFromString(@"IGDirectThreadViewController");
                UIResponder *r = viewController;
                while (r) {
                    if (threadCls && [r isKindOfClass:threadCls]) { ballsThreadVC = (id)r; break; }
                    r = [r nextResponder];
                }
            }

            NSString *currentText = [self valueForKey:@"text"];

            // Resolve a stable thread identifier for deduping the toast across multiple composers of the same thread
            NSString *threadIdentifier = nil;
            @try {
                id thread = nil;
                if (ballsThreadVC) {
                    @try { thread = [ballsThreadVC valueForKey:@"thread"]; } @catch (__unused NSException *e) {}
                    if (!thread) {
                        @try { thread = [ballsThreadVC valueForKey:@"_thread"]; } @catch (__unused NSException *e) {}
                    }
                }
                if (!thread && msgListDataSource) {
                    @try { thread = [msgListDataSource valueForKey:@"thread"]; } @catch (__unused NSException *e) {}
                    if (!thread) {
                        @try { thread = [msgListDataSource valueForKey:@"_thread"]; } @catch (__unused NSException *e) {}
                    }
                }

                id candidate = nil;
                if (thread) {
                    @try { candidate = [thread valueForKey:@"threadId"]; } @catch (__unused NSException *e) {}
                    if (!candidate) { @try { candidate = [thread valueForKey:@"threadID"]; } @catch (__unused NSException *e) {} }
                    if (!candidate) { @try { candidate = [thread valueForKey:@"identifier"]; } @catch (__unused NSException *e) {} }
                    if (!candidate) { @try { candidate = [thread valueForKey:@"pk"]; } @catch (__unused NSException *e) {} }
                }
                if (!candidate && ballsThreadVC) {
                    @try { candidate = [ballsThreadVC valueForKey:@"threadId"]; } @catch (__unused NSException *e) {}
                    if (!candidate) { @try { candidate = [ballsThreadVC valueForKey:@"threadID"]; } @catch (__unused NSException *e) {} }
                }

                if ([candidate isKindOfClass:[NSNumber class]]) {
                    threadIdentifier = [(NSNumber *)candidate stringValue];
                } else if ([candidate isKindOfClass:[NSString class]]) {
                    threadIdentifier = (NSString *)candidate;
                }
            } @catch (__unused NSException *e) {}

            // Build a stable dedupe key: prefer thread id, else sender id/username, else global.
            // Pin the chosen key per thread VC so it doesn't flap between candidates.
            NSString *candidateKey = nil;
            if (threadIdentifier.length > 0) {
                candidateKey = threadIdentifier;
            } else if (lastSender) {
                id senderId = nil;
                @try { senderId = [lastSender valueForKey:@"pk"]; } @catch (__unused NSException *e) {}
                if (!senderId) { @try { senderId = [lastSender valueForKey:@"identifier"]; } @catch (__unused NSException *e) {} }
                if (!senderId) { @try { senderId = [lastSender valueForKey:@"username"]; } @catch (__unused NSException *e) {} }
                if ([senderId isKindOfClass:[NSNumber class]]) {
                    candidateKey = [(NSNumber *)senderId stringValue];
                } else if ([senderId isKindOfClass:[NSString class]]) {
                    candidateKey = (NSString *)senderId;
                }
            }
            if (candidateKey.length == 0) {
                candidateKey = kZeusGlobalKey;
            }

            if (zeusPinnedKeyByVC == nil) {
                zeusPinnedKeyByVC = [NSMutableDictionary dictionary];
            }
            NSString *vcKey = nil;
            if (ballsThreadVC) {
                vcKey = [NSString stringWithFormat:@"%p", ballsThreadVC];
            } else if (viewController) {
                vcKey = [NSString stringWithFormat:@"%p", viewController];
            } else {
                vcKey = @"__no_vc__";
            }
            NSString *stableKey = zeusPinnedKeyByVC[vcKey];
            if (stableKey.length == 0) {
                stableKey = candidateKey ?: kZeusGlobalKey;
                zeusPinnedKeyByVC[vcKey] = stableKey;
            }

            if (zeusLastTextByKey == nil) { zeusLastTextByKey = [NSMutableDictionary dictionary]; }
            if (zeusThreadsShownBanner == nil) { zeusThreadsShownBanner = [NSMutableSet set]; }
            if (zeusLastShownAtByKey == nil) { zeusLastShownAtByKey = [NSMutableDictionary dictionary]; }
            if (zeusEmptySinceByKey == nil) { zeusEmptySinceByKey = [NSMutableDictionary dictionary]; }

            NSString *previousTextForKey = zeusLastTextByKey[stableKey];
            NSString *normalizedCurrent = currentText ?: @"";

            // First observation for this key: store and do not trigger
            if (previousTextForKey == nil) {
                zeusLastTextByKey[stableKey] = normalizedCurrent;
            } else if (![normalizedCurrent isEqualToString:previousTextForKey]) {
                // Text actually changed for this conversation/user
                BOOL alreadyShown = [zeusThreadsShownBanner containsObject:stableKey];
                BOOL transitionedFromEmptyToNonEmpty = (previousTextForKey.length == 0 && normalizedCurrent.length > 0);
                NSTimeInterval now = CACurrentMediaTime();
                NSNumber *lastShownNum = zeusLastShownAtByKey[stableKey];
                NSTimeInterval lastShown = lastShownNum != nil ? [lastShownNum doubleValue] : 0.0;
                BOOL throttled = (now - lastShown) < kZeusShowThrottleSeconds;

                id unreadHint = zeus_activeDirectThreadViewController() ?: ballsThreadVC;
                if (transitionedFromEmptyToNonEmpty && lastSender && !alreadyShown && !throttled && zeus_hasUnreadFromRecipient(unreadHint)) {
                    [zeusThreadsShownBanner addObject:stableKey];
                    zeusLastShownAtByKey[stableKey] = @(now);
                    id composerView = self;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        Class threadCls = NSClassFromString(@"IGDirectThreadViewController");
                        id threadVC = nil;
                        UIResponder *r = composerView;
                        while (r) {
                            if (threadCls && [r isKindOfClass:threadCls]) { threadVC = (id)r; break; }
                            r = [r nextResponder];
                        }
                        if (!threadVC) threadVC = zeus_activeDirectThreadViewController();
                        if (!threadVC) threadVC = unreadHint;
                        if (!threadVC) return;
                        zeus_performMarkLastMessageAsSeen(threadVC, nil);
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            id retryVC = threadVC;
                            if (!retryVC || ![retryVC isKindOfClass:[UIViewController class]]) {
                                retryVC = zeus_activeDirectThreadViewController();
                            }
                            if (retryVC && zeus_hasUnreadFromRecipient(retryVC)) {
                                zeus_performMarkLastMessageAsSeen(retryVC, nil);
                            }
                            zeus_showMarkedAsSeenToastDeferred();
                        });
                    });
                }
                zeusLastTextByKey[stableKey] = normalizedCurrent;
            }

            // Only clear the shown flag if input has been empty continuously for a short period
            NSTimeInterval now = CACurrentMediaTime();
            if (normalizedCurrent.length == 0) {
                NSNumber *emptySinceNum = zeusEmptySinceByKey[stableKey];
                if (!emptySinceNum) {
                    zeusEmptySinceByKey[stableKey] = @(now);
                } else if ((now - [emptySinceNum doubleValue]) >= kZeusEmptyStableSeconds) {
                    [zeusThreadsShownBanner removeObject:stableKey];
                }
            } else {
                [zeusEmptySinceByKey removeObjectForKey:stableKey];
            }
        }

        if (!ENABLED(@"Bypass Character Limit")) {
            return;
        }
        
        if (!self) {
            return;
        }
        
        Ivar characterLimitIvar = class_getInstanceVariable([self class], "_characterLimit");
        if (!characterLimitIvar) {
            NSLog(@"Character limit ivar not found");
            return;
        }
        
        NSInteger characterLimit = 99999999;
        object_setIvar(self, characterLimitIvar, @(characterLimit));
    } @catch (NSException *exception) {
        NSLog(@"Error in character limit bypass: %@", exception);
    }
}

void ZURegisterBypassCharacterLimitHooks(void) {
    Class composer = ZeusFirstClass(@[
        @"IGDirectComposer",
        @"_TtC16IGDirectComposer16IGDirectComposer",
    ]);
    NullHookMessageIfPresent(composer, @selector(layoutSubviews), (void *)hook_directComposer2, &orig_directComposer2);
}