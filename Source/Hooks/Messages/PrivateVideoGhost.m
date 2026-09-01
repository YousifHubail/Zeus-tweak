static BOOL videoPlayed = NO;

@class IGVideo;
static void downloadHDVideo(IGVideo *inputVideo);

// Same media resolved by the download button below, factored out so the
// silent pre-cache (for Keep Deleted Messages) and the download button can
// both use it. Unlike the download button's own >1-version guard (it wants
// the *best* quality), a single available version is still worth caching
// here — any playable copy beats none once the sender deletes the message
// and the live URL stops resolving.
static NSArray<NSURL *> *zeus_visualMessageMediaURLs(id self) {
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    @try {
        id initialVisualMessage = [self valueForKey:@"_initialVisualMessage"];
        id visualMediaInfo = [initialVisualMessage valueForKey:@"_visualMediaInfo"];
        id media = [visualMediaInfo valueForKey:@"media"];
        if ([media valueForKey:@"_video_video"]) {
            IGVideo *video = [media valueForKey:@"_video_video"];
            for (NSURL *url in video.allVideoURLs ?: [NSSet set]) {
                if ([url isKindOfClass:[NSURL class]]) [urls addObject:url];
            }
        }
        if ([media valueForKey:@"_photo_photo"]) {
            IGPhoto *photo = [media valueForKey:@"_photo_photo"];
            NSArray *originalImageVersions = [photo valueForKey:@"_originalImageVersions"];
            if (originalImageVersions.count > 0) {
                id photoURLObj = [originalImageVersions lastObject];
                NSURL *url = [photoURLObj valueForKey:@"url"];
                if ([url isKindOfClass:[NSURL class]]) [urls addObject:url];
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"[Zeus] zeus_visualMessageMediaURLs error: %@", exception);
    }
    return urls;
}

static void (*orig_visualmsgghostbuttons)(IGDirectVisualMessageViewerController *self, SEL _cmd);
static void hook_visualmsgghostbuttons(IGDirectVisualMessageViewerController *self, SEL _cmd) {
    orig_visualmsgghostbuttons(self, _cmd);

    UIView *containerView = [self valueForKey:@"view"];
    if (!containerView || ![containerView isKindOfClass:[UIView class]]) {
        NSLog(@"Failed to get valid container view");
        return;
    }

    // Keep Deleted Messages only blocks the message row from being removed;
    // the sender deleting it can still kill the live CDN URL server-side, so
    // photo/video content silently fails to (re)load afterward. Grab a local
    // copy the first time it's viewed (while the URL is still live) so there's
    // something to fall back to once it isn't.
    BOOL keepDeletedEnabled = ENABLED(@"Keep Deleted Messages");
    NSArray<NSURL *> *mediaURLs = keepDeletedEnabled ? zeus_visualMessageMediaURLs(self) : @[];
    NSMutableArray<NSString *> *cachedPaths = [NSMutableArray array];
    for (NSURL *url in mediaURLs) {
        [[MessagesManager sharedManager] cacheMediaIfNeededFromURL:url];
        NSString *cached = [[MessagesManager sharedManager] cachedMediaPathForURL:url];
        if (cached) [cachedPaths addObject:cached];
    }

    UIButton *downloadButton = [UIButton buttonWithType:UIButtonTypeSystem];
    @try {
        NSData *data = [[NSUserDefaults standardUserDefaults] objectForKey:@"Save Button Color_Color"];
        UIColor *color = [NSKeyedUnarchiver unarchivedObjectOfClass:[UIColor class] fromData:data error:nil];
        [downloadButton setTintColor:color ?: [UIColor labelColor]];
    } @catch (NSException *exception) {
        NSLog(@"Error setting download button color: %@", exception);
        [downloadButton setTintColor:[UIColor labelColor]];
    }
    [downloadButton setImage:[UIImage systemImageNamed:@"arrow.down"] forState:UIControlStateNormal];
    downloadButton.layer.shadowColor = [UIColor blackColor].CGColor;
    downloadButton.layer.shadowOpacity = 0.4;
    downloadButton.layer.shadowOffset = CGSizeMake(-2, 0);
    downloadButton.layer.shadowRadius = 3;
    downloadButton.layer.masksToBounds = NO;
    [downloadButton setTranslatesAutoresizingMaskIntoConstraints:false];

    UIButton *seenButton = [UIButton buttonWithType:UIButtonTypeSystem];
    @try {
        NSData *data = [[NSUserDefaults standardUserDefaults] objectForKey:@"Seen Button Color_Color"];
        UIColor *color = [NSKeyedUnarchiver unarchivedObjectOfClass:[UIColor class] fromData:data error:nil];
        [seenButton setTintColor:color ?: [UIColor labelColor]];
    } @catch (NSException *exception) {
        NSLog(@"Error setting seen button color: %@", exception);
        [seenButton setTintColor:[UIColor labelColor]];
    }
    [seenButton setImage:[UIImage systemImageNamed:@"eye"] forState:UIControlStateNormal];
    seenButton.layer.shadowColor = [UIColor blackColor].CGColor;
    seenButton.layer.shadowOpacity = 0.4;
    seenButton.layer.shadowOffset = CGSizeMake(-2, 0);
    seenButton.layer.shadowRadius = 3;
    seenButton.layer.masksToBounds = NO;
    [seenButton setTranslatesAutoresizingMaskIntoConstraints:false];

    UIButton *restoreButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [restoreButton setTintColor:[UIColor systemGreenColor]];
    [restoreButton setImage:[UIImage systemImageNamed:@"arrow.counterclockwise"] forState:UIControlStateNormal];
    restoreButton.layer.shadowColor = [UIColor blackColor].CGColor;
    restoreButton.layer.shadowOpacity = 0.4;
    restoreButton.layer.shadowOffset = CGSizeMake(-2, 0);
    restoreButton.layer.shadowRadius = 3;
    restoreButton.layer.masksToBounds = NO;
    [restoreButton setTranslatesAutoresizingMaskIntoConstraints:false];

    BOOL downloadVideos = ENABLED(@"Save Media");
    BOOL hideSeenState = ENABLED(@"Private Media Ghost");
    BOOL showRestore = cachedPaths.count > 0;

    ZeusSetCaptureHiding(downloadButton);
    ZeusSetCaptureHiding(seenButton);
    ZeusSetCaptureHiding(restoreButton);

    @try {
        // Stack whichever buttons are enabled bottom-up, each 20pt above the
        // previous, so any combination of the three lays out correctly.
        NSMutableArray<UIButton *> *stackedButtons = [NSMutableArray array];
        if (downloadVideos) [stackedButtons addObject:downloadButton];
        if (hideSeenState) [stackedButtons addObject:seenButton];
        if (showRestore) [stackedButtons addObject:restoreButton];

        UIButton *previousButton = nil;
        for (UIButton *button in stackedButtons) {
            [containerView addSubview:button];
            NSLayoutYAxisAnchor *bottomAnchor = previousButton ? previousButton.topAnchor : containerView.bottomAnchor;
            CGFloat constant = previousButton ? -20 : -150;
            [NSLayoutConstraint activateConstraints:@[
                [button.bottomAnchor constraintEqualToAnchor:bottomAnchor constant:constant],
                [button.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor constant:-8],
                [button.widthAnchor constraintEqualToConstant:30],
                [button.heightAnchor constraintEqualToConstant:30]
            ]];
            previousButton = button;
        }

        if (showRestore) {
            [restoreButton addAction:[UIAction actionWithHandler:^(UIAction *action) {
                MediaSelectionViewController *mediaSelectionViewController = [[MediaSelectionViewController alloc] init];
                NSMutableArray<NSString *> *extensions = [NSMutableArray array];
                for (NSString *path in cachedPaths) {
                    [extensions addObject:path.pathExtension.length > 0 ? path.pathExtension : @"dat"];
                }
                [mediaSelectionViewController saveFilesToCameraRoll:cachedPaths extensions:extensions];
                if (ENABLED(@"Show Banners")) {
                    [ZeusHelper showToastWithTitle:@"Restored from local backup!" subtitle:@"Saved before it could vanish." icon:[UIImage systemImageNamed:@"checkmark.circle.fill"] autoHide:4 openURL:[NSURL URLWithString:@"photos-redirect://"]];
                }
            }] forControlEvents:UIControlEventTouchUpInside];
        }

        if (hideSeenState) {
            __weak typeof(self) weakSelf = self;
            [seenButton addAction:[UIAction actionWithHandler:^(UIAction *action) {
                UIView *containView = [self valueForKey:@"_viewerContainerView"];
                UIView *medView = [containView valueForKey:@"mediaView"];
                if ([medView isKindOfClass:NSClassFromString(@"IGStoryModernVideoView")]) {
                    [self performSelector:@selector(storyPlayerMediaViewDidPlay:) withObject:medView];
                    videoPlayed = YES;
                }

                if ([medView isKindOfClass:NSClassFromString(@"IGStoryPhotoView")]) {
                    [self storyPlayerMediaViewDidLoad:medView loadSource:0 networkRequestSummary:0];
                    videoPlayed = YES;
                }

                if (ENABLED(@"Show Banners")) {
                    [ZeusHelper showToastWithTitle:@"Marked as seen!" subtitle:@"They know we are here." icon:[ZeusHelper imageFromEmojiString:@"👀" width:60] autoHide:4 openURL:nil];
                }
            }] forControlEvents:UIControlEventTouchUpInside];
        }

        if (downloadVideos) {
            __weak typeof(self) weakSelf = self;
            [downloadButton addAction:[UIAction actionWithHandler:^(UIAction *action) {
                id initialVisualMessage = [self valueForKey:@"_initialVisualMessage"];
                id visualMediaInfo = [initialVisualMessage valueForKey:@"_visualMediaInfo"];
                id media = [visualMediaInfo valueForKey:@"media"];
                if ([media valueForKey:@"_video_video"]) {
                    IGVideo *video = [media valueForKey:@"_video_video"];
                    downloadHDVideo(video);
                }

                if ([media valueForKey:@"_photo_photo"]) {
                    IGPhoto *photo = [media valueForKey:@"_photo_photo"];
                    NSArray *originalImageVersions = [photo valueForKey:@"_originalImageVersions"];
                    if (originalImageVersions.count > 1) {
                        id photoURL = [originalImageVersions lastObject];
                        NSURL *url = [photoURL valueForKey:@"url"];
                        MediaSelectionViewController *mediaSelectionViewController = [[MediaSelectionViewController alloc] init];
                        [mediaSelectionViewController downloadMediaToTemp:url completion:^(NSString *filePath, NSString *fileExtension){
                            if (ENABLED(@"Show Banners")) {
                                NSInteger saveMethod = [[NSUserDefaults standardUserDefaults] integerForKey:@"Save Method_SegmentIndex"];
                                if (saveMethod == 0) {
                                    [ZeusHelper showToastWithTitle:@"Saved to camera roll!" subtitle:@"Tap here to go to camera roll." icon:[UIImage systemImageNamed:@"checkmark.circle.fill"] autoHide:4 openURL:[NSURL URLWithString:@"photos-redirect://"]];
                                } else {
                                    [ZeusHelper showToastWithTitle:@"Saved!" subtitle:@"Saved to local folder." icon:[UIImage systemImageNamed:@"checkmark.circle.fill"] autoHide:4 openURL:nil];
                                }
                            }
                        }];
                    }
                }
            }] forControlEvents:UIControlEventTouchUpInside];
        }
    } @catch (NSException *exception) {
        NSLog(@"Error adding buttons: %@", exception);
    }
}

static void (*orig_visualmsgghostvideo)(id self, SEL _cmd, id arg1);
static void hook_visualmsgghostvideo(id self, SEL _cmd, id arg1) {
    if (!ENABLED(@"Private Media Ghost")) {
        return orig_visualmsgghostvideo(self, _cmd, arg1);
    }

    if (videoPlayed) {
        orig_visualmsgghostvideo(self, _cmd, arg1);
        videoPlayed = NO;
    }
}

static void (*orig_visualmsgghostphoto)(id self, SEL _cmd, id arg1, id arg2, id arg3, id arg4);
static void hook_visualmsgghostphoto(id self, SEL _cmd, id arg1, id arg2, id arg3, id arg4) {
    if (!ENABLED(@"Private Media Ghost")) {
        return orig_visualmsgghostphoto(self, _cmd, arg1, arg2, arg3, arg4);
    }

    if (videoPlayed) {
        orig_visualmsgghostphoto(self, _cmd, arg1, arg2, arg3, arg4);
        videoPlayed = NO;
    }
}

void ZURegisterPrivateVideoGhostHooks(void) {
    NullHookMessageEx(objc_getClass("IGDirectVisualMessageViewerController"), @selector(viewDidLoad), (void *)hook_visualmsgghostbuttons, &orig_visualmsgghostbuttons);
    NullHookMessageEx(objc_getClass("IGDirectVisualMessageViewerController"), @selector(storyPlayerMediaViewDidPlay:), (void *)hook_visualmsgghostvideo, &orig_visualmsgghostvideo);
    NullHookMessageEx(objc_getClass("IGStoryPhotoView"), @selector(progressImageView:didLoadImage:loadSource:networkRequestSummary:), (void *)hook_visualmsgghostphoto, &orig_visualmsgghostphoto);
}