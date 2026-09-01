/*
 * Tweak entry point: install all feature hooks (no DRM / license gates).
 */

static void InitializeHooks(void) {
    if (hooksInitialized) return;
    hooksInitialized = YES;

    ZURegisterStoryAutoAdvanceHooks();
    ZURegisterTabBarHooks();
    ZURegisterSettingsEntryHooks();
    ZURegisterExternalBrowserHooks();
    ZURegisterDateFormatHooks();
    ZURegisterLiquidGlassHooks();
    ZURegisterTapControlsHooks();
    ZURegisterFullLastActiveHooks();
    ZURegisterSendFileHooks();
    ZURegisterNavigationHooks();
    ZURegisterHideAdsCoreHooks();
    ZURegisterHideFeedFilteringHooks();
    ZURegisterSavePostHook();
    ZURegisterHideTypingIndicatorHooks();
    ZURegisterKeepDeletedMessagesHooks();
    ZURegisterSaveProfilePicturesHooks();
    ZURegisterScreenshotProtectionProviderHooks();
    ZURegisterSundialViewerUFIHooks();
    ZURegisterFollowStatusIndicatorHooks();
    ZURegisterHideSearchesRecentStoreHooks();
    ZURegisterLikeConfirmationHooks();
    ZURegisterFollowConfirmationHooks();
    ZURegisterLockInstagramHooks();
    ZURegisterScreenshotObserverHook();
    ZURegisterHideExploreGridHooks();
    ZURegisterCallConfirmationHooks();
    ZURegisterMarkAsSeenThreadAndReactionHooks();
    ZURegisterPrivateVideoGhostHooks();
    ZURegisterStorySeenLocalOnlyHooks();
    ZURegisterStoryGhostHooks();
    ZURegisterHideTabsHooks();
    ZURegisterDismissIGDSPromoDialogHooks();
    ZURegisterNoBrainrotHooks();
    ZURegisterExploreRefreshConfirmationHooks();
    ZURegisterBypassCharacterLimitHooks();
    ZURegisterMarkAsSeenSeenOnSendHook();
    ZURegisterShakeToOpenHooks();
    ZURegisterSettingsButtonHooks();
    ZURegisterCreateGroupConfirmationHooks();
    ZURegisterHideCreateGroupButtonHooks();
    ZURegisterBypassReelPasswordHooks();
    ZURegisterHideSuggestedReelsHooks();
    ZURegisterSaveAudioMessageHooks();
    ZURegisterUploadAudioMessageHooks();
    ZURegisterHideCreateButtonHooks();
    ZURegisterVanishModeConfirmationHooks();
    ZURegisterStorySeenOnHooks();
    ZURegisterLiveBrowseTweaksHooks();
    ZURegisterCommentTextCopyHooks();
    ZURegisterGetStoryMentionsHooks();
    ZURegisterSaveAudioNotesHooks();
    ZURegisterSortUserGridPostsHooks();
    ZURegisterFeedUsernameSpoofHooks();
    ZURegisterToastDismissHooks();
    ZURegisterHideTestFlightNagHooks();

    dispatch_async(dispatch_get_main_queue(), ^{
        ZURegisterDeferredDBBHooks();

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (ENABLED(@"Load Banner")) {
                NSString *title = [NSString stringWithFormat:@"Zeus %s | Instagram %s", ZEUS_VERSION, appVersion.UTF8String];
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    UIImage *icon = [ZeusHelper imageFromEmojiString:@"🚀" width:300];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [ZeusHelper showLoadToast:@"Success!" subtitle:title icon:icon autoHide:4 openURL:nil];
                    });
                });
            }
        });

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            // One-shot: mark seen BEFORE presenting so a present/NUX crash cannot loop forever.
            NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
            if ([defs objectForKey:@"ZeusFirst"]) return;
            [defs setValue:@"ZeusFirst" forKey:@"ZeusFirst"];
            [defs synchronize];

            @try {
                UIViewController *top = [ZeusHelper topViewController];
                if (!top || top.beingPresented || top.isBeingDismissed) return;
                // Avoid stacking on another fullscreen modal (e.g. TestFlight nag).
                if (top.presentedViewController) return;
                NSString *topName = NSStringFromClass(object_getClass(top));
                if ([topName containsString:@"TestFlight"] || [topName containsString:@"SecurityViewController"]) return;

                StoryGesturesNuxViewController *vc = [StoryGesturesNuxViewController new];
                vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
                [top presentViewController:vc animated:YES completion:nil];
            } @catch (NSException *e) {
                NSLog(@"[Zeus] NUX presentation failed: %@", e);
            }
        });

        // Log remaining hook misses; don't block launch with an alert.
        // Use UTF8 %s so Console doesn't redact lines as <private>.
        FailedHooksEnsureInit();
        [sFailedHookLock lock];
        NSArray *failed = [sFailedHookLines copy];
        [sFailedHookLines removeAllObjects];
        [sFailedHookLock unlock];
        if (failed.count) {
            // fprintf bypasses os_log privacy redaction (<private>).
            fprintf(stderr, "[Zeus] %lu hook install miss(es):\n", (unsigned long)failed.count);
            for (NSString *line in failed) {
                fprintf(stderr, "[Zeus] miss: %s\n", line.UTF8String ?: "(null)");
            }
            fflush(stderr);
        }
    });
}

#ifdef SIDELOAD
static void RunSideloadSetupOnce(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        @try {
            fakeGroupContainerURL = [NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/FakeGroupContainers"] isDirectory:YES];
            loadKeychainAccessGroup();
            NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
            NSString *appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
            if (caches) {
                [ZeusHelper createDirectoryIfNotExists:[NSURL fileURLWithPath:[caches stringByAppendingPathComponent:@"MobileConfig"] isDirectory:YES]];
                [ZeusHelper createDirectoryIfNotExists:[NSURL fileURLWithPath:[caches stringByAppendingPathComponent:@"FBMobileConfig"] isDirectory:YES]];
            }
            if (appSupport) {
                [ZeusHelper createDirectoryIfNotExists:[NSURL fileURLWithPath:[appSupport stringByAppendingPathComponent:@"MobileConfig"] isDirectory:YES]];
                [ZeusHelper createDirectoryIfNotExists:[NSURL fileURLWithPath:[appSupport stringByAppendingPathComponent:@"FBMobileConfig"] isDirectory:YES]];
            }
            // Optional IG/FB classes — silent if absent (avoids noisy "1 miss" + nil-class records).
            NullHookMessageIfPresent(objc_getClass("FBSDKKeychainStore"), @selector(accessGroup), (void *)hook_accessGroup_FBSDKKeychainStore, &orig_accessGroup_FBSDKKeychainStore);
            NullHookMessageIfPresent(objc_getClass("FBKeychainItemController"), @selector(accessGroup), (void *)hook_accessGroup_FBKeychainItemController, &orig_accessGroup_FBKeychainItemController);
            NullHookMessageIfPresent(objc_getClass("UICKeyChainStore"), @selector(accessGroup), (void *)hook_accessGroup_UICKeyChainStore, &orig_accessGroup_UICKeyChainStore);
            NullHookMessageIfPresent(objc_getClass("UICKeyChainStore"), @selector(keyChainStoreWithService:accessGroup:), (void *)hook_UIC_keyChainStoreWithServiceAccessGroup, &orig_UIC_keyChainStoreWithServiceAccessGroup);
            NullHookMessageIfPresent(objc_getClass("LSKeychainItemController"), @selector(initWithServiceID:accessGroup:userID:isSynchronizable:), (void *)hook_LS_initWithServiceIDAccessGroupUserIDSync, &orig_LS_initWithServiceIDAccessGroupUserIDSync);
            NullHookMessageIfPresent(objc_getClass("LSKeychainItemController"), @selector(initWithServiceID:accessGroup:userID:), (void *)hook_LS_initWithServiceIDAccessGroupUserID, &orig_LS_initWithServiceIDAccessGroupUserID);
            NullHookMessageIfPresent(objc_getClass("LSKeychainItemController"), @selector(initSynchronizableItemWithServiceID:accessGroup:userID:), (void *)hook_LS_initSynchronizableItem, &orig_LS_initSynchronizableItem);
            NullHookMessageIfPresent(objc_getClass("NSDictionary"), @selector(queryWithAccessGroupKey:), (void *)hook_NSDictionary_queryWithAccessGroupKey, &orig_NSDictionary_queryWithAccessGroupKey);
            NullHookMessageIfPresent(objc_getClass("FWAFBKeychainSecureStore"), @selector(keychainSecureStoreByInferringBundleIDWithAccessGroup:), (void *)hook_FWA_keychainSecureStoreByInferring, &orig_FWA_keychainSecureStoreByInferring);
            NullHookMessageIfPresent(objc_getClass("IGCloudTrustTokenCloudStore"), @selector(initWithAccessGroup:), (void *)hook_IGCloudTrust_initWithAccessGroup, &orig_IGCloudTrust_initWithAccessGroup);
            // Install mkdir hook before containerURL — containerURL uses orig_createDirectoryAtPath.
            NullHookMessageEx(objc_getClass("NSFileManager"), @selector(createDirectoryAtPath:withIntermediateDirectories:attributes:error:), (void *)hook_createDirectoryAtPath, &orig_createDirectoryAtPath);
            NullHookMessageEx(objc_getClass("NSFileManager"), @selector(containerURLForSecurityApplicationGroupIdentifier:), (void *)hook_NSFileManager, &orig_NSFileManager);
            if (!orig_NSFileManager || !orig_createDirectoryAtPath) {
                NSLog(@"[Zeus] Sideload NSFileManager hooks incomplete (orig_container=%p orig_mkdir=%p)",
                      orig_NSFileManager, orig_createDirectoryAtPath);
            } else {
                NSLog(@"[Zeus] Sideload keychain/container hooks installed");
            }
        } @catch (NSException *e) {
            NSLog(@"[Zeus] Sideload setup exception: %@", e);
        }
    });
}
#endif

static void StartTweakWhenReady(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIApplicationState state = UIApplication.sharedApplication.applicationState;
        if (state == UIApplicationStateBackground) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                StartTweakWhenReady();
            });
            return;
        }
        InitializeHooks();
    });
}

static void ObserveAppLifecycle(void) {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(__unused NSNotification *note) {
        StartTweakWhenReady();
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(__unused NSNotification *note) {
        StartTweakWhenReady();
        [ZUProfileAnalyzerViewController prefetchProfileImageIfNeeded];
    }];
    StartTweakWhenReady();
#ifdef SIDELOAD
    RunSideloadSetupOnce();
#endif
    [ZUProfileAnalyzerViewController prefetchProfileImageIfNeeded];
}

__attribute__((constructor))
static void ZeusLoad(void) {
#ifdef SIDELOAD
    install_fishhook_rebindings();
    RunSideloadSetupOnce();
    dispatch_async(dispatch_get_main_queue(), ^{ RunSideloadSetupOnce(); });
#endif

    ZURegisterLiquidGlassTabBarEarlyHooks();

    appVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *zeusProject = [NSString stringWithUTF8String:ZEUS_PROJECT];
    if ([zeusProject hasPrefix:@"zeus "]) {
        zeusProject = [zeusProject substringFromIndex:6];
    }
    NSLog(@"Zeus %@ | Instagram %s | Hello!", zeusProject, appVersion.UTF8String);

    [ZeusHelper cleanupTemporaryMediaFiles];

    dispatch_async(dispatch_get_main_queue(), ^{
        ObserveAppLifecycle();
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [ZUProfileAnalyzerViewController prefetchProfileImageIfNeeded];
    });
}

__attribute__((destructor))
static void ZeusUnload(void) {
    NSLog(@"Zeus %s | Instagram %s | Goodbye!", ZEUS_VERSION, appVersion.UTF8String);
}
