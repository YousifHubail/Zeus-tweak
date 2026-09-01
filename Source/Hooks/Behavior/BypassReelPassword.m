static char kZeusBypassTimerKey;
static char kZeusBypassConstraintsKey;
static char kZeusBypassObserversKey;
static char kZeusBypassShareStateKey;
static char kZeusBypassOriginalFrameKey;
static char kZeusHotColdPrevCorrectKey;
static char kZeusHotColdStaleCountKey;
static char kZeusHotColdPrevTypedLenKey;
static char kZeusBypassDisplayLinkKey;
static char kZeusBypassDisplayLinkTargetKey;
static char kZeusBypassButtonTargetKey;

static void ZeusTeardownBypassButton(UIButton *button);
static void ZeusGlobalDestroyBypassArtifacts(void);
static void ZeusAdjustBypassElevation(UIButton *button, UIView *container, UIView *root, id owner);
static BOOL ZeusViewIsOnscreen(UIView *view, UIView *root);

static BOOL ZeusIsShareClass(UIViewController *vc) {
    static Class DirectShareClass = Nil;
    static Class PartialModalNavClass = Nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        DirectShareClass = NSClassFromString(@"IGDirectShareSheetContainerViewController");
        PartialModalNavClass = NSClassFromString(@"IGDSPartialModalSheetNavigationController");
    });
    return (DirectShareClass && [vc isKindOfClass:DirectShareClass]) || (PartialModalNavClass && [vc isKindOfClass:PartialModalNavClass]);
}

static NSArray<UIWindow *> *ZeusPrimaryWindows(void) {
    if (![UIApplication respondsToSelector:@selector(sharedApplication)]) { return @[]; }
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                if (ws.windows.count > 0) { return ws.windows; }
            }
        }
    }
    return UIApplication.sharedApplication.windows ?: @[];
}

static BOOL ZeusIsShareSheetPresented(void) {
    NSArray<UIWindow *> *windows = ZeusPrimaryWindows();
    for (UIWindow *w in windows) {
        if (w.hidden) { continue; }
        UIViewController *vc = w.rootViewController;
        if (!vc) { continue; }
        UIViewController *top = vc;
        while (top.presentedViewController) { top = top.presentedViewController; }
        UIViewController *cursor = top;
        while (cursor) {
            if (ZeusIsShareClass(cursor)) { return YES; }
            cursor = cursor.presentingViewController;
        }
    }
    return NO;
}

static CGFloat ZeusMatchScore(NSString *typedRaw, NSString *answerRaw) {
    if (typedRaw.length == 0 || answerRaw.length == 0) { return 0.0; }
    NSString *typed = [typedRaw lowercaseString];
    NSString *answer = [answerRaw lowercaseString];
    NSUInteger minLen = MIN(typed.length, answer.length);
    NSUInteger correct = 0;
    for (NSUInteger i = 0; i < minLen; i++) {
        unichar ct = [typed characterAtIndex:i];
        unichar ca = [answer characterAtIndex:i];
        if (ct == ca) { correct++; } else { break; }
    }
    CGFloat ratio = (CGFloat)correct / (CGFloat)answer.length;
    if (ratio < 0) ratio = 0; if (ratio > 1) ratio = 1;
    return ratio;
}

static NSString *ZeusTemperatureLabel(CGFloat score) {
    if (score >= 0.95) return @"Scorching! 🔥🔥";
    if (score >= 0.75) return @"Hot 🔥";
    if (score >= 0.55) return @"Warm 🙂";
    if (score >= 0.35) return @"Cool 🆒";
    if (score >= 0.15) return @"Cold 🧊";
    return @"Ice Cold ❄️";
}

@interface ZeusBypassDisplayLinkTarget : NSObject
@property (nonatomic, weak) UIButton *button;
@property (nonatomic, weak) UIView *container;
@property (nonatomic, weak) UIView *root;
@property (nonatomic, weak) id owner;
- (void)tick:(CADisplayLink *)link;
@end
static BOOL ZeusViewIsOnscreen(UIView *view, UIView *root) {
	if (!view || !view.window) { return NO; }
	if (!root) { root = view.window; }
	// Check visibility in hierarchy
	for (UIView *v = view; v != nil; v = v.superview) {
		if (v.hidden || v.alpha < 0.01) { return NO; }
	}
	// Check intersection with root bounds
	CGRect rectInRoot = [view convertRect:view.bounds toView:root];
	CGRect intersection = CGRectIntersection(rectInRoot, root.bounds);
	if (CGRectIsNull(intersection) || CGRectIsEmpty(intersection)) { return NO; }
	// Require a minimal visible area to avoid false positives
	CGFloat minArea = 20.0 * 20.0;
	CGFloat area = intersection.size.width * intersection.size.height;
	return area >= minArea;
}

@implementation ZeusBypassDisplayLinkTarget
- (void)tick:(CADisplayLink *)link {
    UIButton *button = self.button;
    if (!button) { [link invalidate]; return; }
    UIView *root = self.root ?: button.window;
    id owner = self.owner;
    if (!owner || !root) {
        ZeusTeardownBypassButton(button);
        [link invalidate];
        return;
    }
    if (button.superview != root) { return; }
    UITextField *textField = nil; @try { textField = [owner valueForKey:@"_passwordTextField"]; } @catch (__unused NSException *e) {}
	if (!textField || !textField.window || !ZeusViewIsOnscreen(textField, root)) {
        ZeusTeardownBypassButton(button);
        [link invalidate];
        return;
    }
    CGRect tfFrameInRoot = [textField convertRect:textField.bounds toView:root];
    CGFloat btnWidth = 100.0;
    CGFloat btnHeight = 40.0;
    CGFloat targetX = CGRectGetMidX(tfFrameInRoot) - (btnWidth * 0.5);
    CGFloat targetY = CGRectGetMaxY(tfFrameInRoot) + 20.0;

    button.frame = CGRectMake(targetX, targetY, btnWidth, btnHeight);
}
@end

@interface ZeusBypassButtonTarget : NSObject
@property (nonatomic, weak) UIButton *button;
@property (nonatomic, weak) UIView *container;
@property (nonatomic, weak) UIView *root;
@property (nonatomic, weak) id owner;
- (void)handleTap:(id)sender;
@end

@implementation ZeusBypassButtonTarget
- (void)handleTap:(id)sender {
	id owner = self.owner;
	if (!owner) {
		UIResponder *responder = [sender isKindOfClass:[UIResponder class]] ? (UIResponder *)sender : self.button;
		while (responder && ![responder isKindOfClass:[UIViewController class]]) {
			responder = responder.nextResponder;
		}
		owner = (UIViewController *)responder;
	}
	if (!owner) { return; }

	UITextField *tf = nil;
	NSString *ans = nil;
	@try {
		tf = [owner valueForKey:@"_passwordTextField"];
		ans = [owner valueForKey:@"_answer"];
	} @catch (__unused NSException *e) {
		tf = nil;
		ans = nil;
	}
	if ([tf isKindOfClass:[UITextField class]]) {
		[tf setText:ans ?: @""];
	}
	if ([owner respondsToSelector:@selector(_didTapSubmitButton)]) {
		[owner performSelector:@selector(_didTapSubmitButton)];
	}

	UIButton *btn = self.button;
	if (!btn) {
		UIView *searchRoot = self.container ?: self.root ?: (self.button ? self.button.window : nil);
		if (!searchRoot && [UIApplication respondsToSelector:@selector(sharedApplication)]) {
			searchRoot = UIApplication.sharedApplication.keyWindow;
		}
		btn = (UIButton *)[searchRoot viewWithTag:869321];
	}
	if (!btn) {
		ZeusGlobalDestroyBypassArtifacts();
		return;
	}
	btn.userInteractionEnabled = NO;
	[UIView animateWithDuration:0.2
		animations:^{
			btn.alpha = 0.0;
		} completion:^(BOOL finished) {
			ZeusTeardownBypassButton(btn);
			ZeusGlobalDestroyBypassArtifacts();
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
				[ZeusHelper showLoadToast:@"Bypassed Password" subtitle:[NSString stringWithFormat:@"Password was \"%@\".", ans ?: @""] icon:[ZeusHelper imageFromEmojiString:@"🤦‍♂️" width:300] autoHide:4 openURL:nil];
			});
		}];
}
@end

static void ZeusTeardownBypassButton(UIButton *button) {
    if (!button) { return; }
    [button removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
    NSTimer *timer = objc_getAssociatedObject(button, &kZeusBypassTimerKey);
    if (timer) { [timer invalidate]; objc_setAssociatedObject(button, &kZeusBypassTimerKey, nil, OBJC_ASSOCIATION_ASSIGN); }
    NSArray *observers = objc_getAssociatedObject(button, &kZeusBypassObserversKey);
    if ([observers isKindOfClass:[NSArray class]]) {
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        for (id obs in observers) {
            if (obs && obs != [NSNull null]) { [nc removeObserver:obs]; }
        }
        objc_setAssociatedObject(button, &kZeusBypassObserversKey, nil, OBJC_ASSOCIATION_ASSIGN);
    }
    NSArray *saved = objc_getAssociatedObject(button, &kZeusBypassConstraintsKey);
    if (saved) { [NSLayoutConstraint deactivateConstraints:saved]; objc_setAssociatedObject(button, &kZeusBypassConstraintsKey, nil, OBJC_ASSOCIATION_ASSIGN); }
    CADisplayLink *link = objc_getAssociatedObject(button, &kZeusBypassDisplayLinkKey);
    if (link) { [link invalidate]; objc_setAssociatedObject(button, &kZeusBypassDisplayLinkKey, nil, OBJC_ASSOCIATION_ASSIGN); }
    objc_setAssociatedObject(button, &kZeusBypassDisplayLinkTargetKey, nil, OBJC_ASSOCIATION_ASSIGN);
    id owner = nil;
    UIResponder *responder = button.nextResponder;
    while (responder && ![responder isKindOfClass:[UIViewController class]]) { responder = responder.nextResponder; }
    owner = responder;
    UILabel *tTitle = nil;
    @try { if (owner) { tTitle = [owner valueForKey:@"_titleLabel"]; } } @catch (__unused NSException *e) {}
    if ([tTitle isKindOfClass:[UILabel class]]) {
        UIView *hc = [tTitle.superview viewWithTag:869322];
        [hc removeFromSuperview];
    }
    @try {
        UITextField *tf = owner ? [owner valueForKey:@"_passwordTextField"] : nil;
        if ([tf isKindOfClass:[UITextField class]]) {
            [tf removeTarget:nil action:NULL forControlEvents:UIControlEventEditingChanged];
            objc_setAssociatedObject(tf, &kZeusHotColdPrevCorrectKey, nil, OBJC_ASSOCIATION_ASSIGN);
            objc_setAssociatedObject(tf, &kZeusHotColdPrevTypedLenKey, nil, OBJC_ASSOCIATION_ASSIGN);
            objc_setAssociatedObject(tf, &kZeusHotColdStaleCountKey, nil, OBJC_ASSOCIATION_ASSIGN);
        }
    } @catch (__unused NSException *e) {}
    [button removeFromSuperview];
    NSArray<UIWindow *> *windows = ZeusPrimaryWindows();
    for (UIWindow *w in windows) {
        UIView *v = [w viewWithTag:869321];
        if (v) { [v removeFromSuperview]; }
        UIView *assist = [w viewWithTag:869322];
        if (assist) { [assist removeFromSuperview]; }
    }
    objc_setAssociatedObject(button, &kZeusBypassOriginalFrameKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(button, &kZeusBypassShareStateKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

static void ZeusGlobalDestroyBypassArtifacts(void) {
    NSArray<UIWindow *> *windows = ZeusPrimaryWindows();
    for (UIWindow *w in windows) {
        UIView *maybeButton = [w viewWithTag:869321];
        if ([maybeButton isKindOfClass:[UIButton class]]) {
            ZeusTeardownBypassButton((UIButton *)maybeButton);
        } else if (maybeButton) {
            [maybeButton removeFromSuperview];
        }
        UIView *assist = [w viewWithTag:869322];
        if (assist) { [assist removeFromSuperview]; }
    }
}

static void ZeusUpdateBypassButtonPlacement(UIButton *button, UIView *container, UIView *root, id owner) {
    if (!button) { return; }
    if (!owner || !container) { ZeusTeardownBypassButton(button); return; }
    if (button.superview != container) {
        NSArray *saved = objc_getAssociatedObject(button, &kZeusBypassConstraintsKey);
        if (saved) { [NSLayoutConstraint deactivateConstraints:saved]; objc_setAssociatedObject(button, &kZeusBypassConstraintsKey, nil, OBJC_ASSOCIATION_ASSIGN); }
        [button removeFromSuperview];
        [container addSubview:button];
        [button setTranslatesAutoresizingMaskIntoConstraints:NO];
    }
    UITextField *textField = nil;
    @try { textField = [owner valueForKey:@"_passwordTextField"]; } @catch (__unused NSException *e) { textField = nil; }
    if (!textField) { ZeusTeardownBypassButton(button); return; }
    NSArray *existing = objc_getAssociatedObject(button, &kZeusBypassConstraintsKey);
    if (!existing || existing.count == 0) {
        NSArray *constraints = @[
            [button.topAnchor constraintEqualToAnchor:textField.bottomAnchor constant:20],
            [button.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
            [button.widthAnchor constraintEqualToConstant:100],
            [button.heightAnchor constraintEqualToConstant:40]
        ];
        [NSLayoutConstraint activateConstraints:constraints];
        objc_setAssociatedObject(button, &kZeusBypassConstraintsKey, constraints, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    button.layer.zPosition = 10000;
    [container bringSubviewToFront:button];
}

static void ZeusAdjustBypassElevation(UIButton *button, UIView *container, UIView *root, id owner) {
	if (!button || !container || !owner) { return; }
	if (!root) {
		root = container.window ?: container;
		while (root.superview) { root = root.superview; }
	}
	UITextField *visibleTF = nil;
	@try { visibleTF = [owner valueForKey:@"_passwordTextField"]; } @catch (__unused NSException *e) { visibleTF = nil; }
	if (![visibleTF isKindOfClass:[UITextField class]] || visibleTF.window == nil || !ZeusViewIsOnscreen(visibleTF, root)) {
		// No on-screen field: keep button within container (not elevated), disable interaction
		CADisplayLink *link = objc_getAssociatedObject(button, &kZeusBypassDisplayLinkKey);
		if (link) { [link invalidate]; objc_setAssociatedObject(button, &kZeusBypassDisplayLinkKey, nil, OBJC_ASSOCIATION_ASSIGN); }
		objc_setAssociatedObject(button, &kZeusBypassDisplayLinkTargetKey, nil, OBJC_ASSOCIATION_ASSIGN);
		if (button.superview != container) {
			[button removeFromSuperview];
			[container addSubview:button];
			[button setTranslatesAutoresizingMaskIntoConstraints:NO];
		}
		if ([visibleTF isKindOfClass:[UITextField class]]) {
			ZeusUpdateBypassButtonPlacement(button, container, root, owner);
		}
		button.userInteractionEnabled = NO;
		button.layer.zPosition = 0;
		button.hidden = YES;
		return;
	}
	BOOL sharePresented = ZeusIsShareSheetPresented();

	if (!sharePresented) {
		// Elevate to window/root with display link placement for reliable taps
		// Remove any container constraints
		NSArray *saved = objc_getAssociatedObject(button, &kZeusBypassConstraintsKey);
		if (saved) { [NSLayoutConstraint deactivateConstraints:saved]; objc_setAssociatedObject(button, &kZeusBypassConstraintsKey, nil, OBJC_ASSOCIATION_ASSIGN); }
		if (button.superview != root) {
			[button removeFromSuperview];
			[root addSubview:button];
			[button setTranslatesAutoresizingMaskIntoConstraints:YES];
		}
		// Start (or keep) the display link to track the text field position
		ZeusBypassDisplayLinkTarget *target = objc_getAssociatedObject(button, &kZeusBypassDisplayLinkTargetKey);
		CADisplayLink *link = objc_getAssociatedObject(button, &kZeusBypassDisplayLinkKey);
		if (!target || !link) {
			target = [ZeusBypassDisplayLinkTarget new];
			target.button = button;
			target.container = container;
			target.root = root;
			target.owner = owner;
			link = [CADisplayLink displayLinkWithTarget:target selector:@selector(tick:)];
			[link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
			objc_setAssociatedObject(button, &kZeusBypassDisplayLinkTargetKey, target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			objc_setAssociatedObject(button, &kZeusBypassDisplayLinkKey, link, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		}
		button.userInteractionEnabled = YES;
		button.layer.zPosition = 100000;
		[root bringSubviewToFront:button];
		button.hidden = NO;
	} else {
		// Push back into container with constraints and disable interaction to avoid intercepting
		CADisplayLink *link = objc_getAssociatedObject(button, &kZeusBypassDisplayLinkKey);
		if (link) { [link invalidate]; objc_setAssociatedObject(button, &kZeusBypassDisplayLinkKey, nil, OBJC_ASSOCIATION_ASSIGN); }
		objc_setAssociatedObject(button, &kZeusBypassDisplayLinkTargetKey, nil, OBJC_ASSOCIATION_ASSIGN);
		if (button.superview != container) {
			[button removeFromSuperview];
			[container addSubview:button];
			[button setTranslatesAutoresizingMaskIntoConstraints:NO];
		}
		ZeusUpdateBypassButtonPlacement(button, container, root, owner);
		button.userInteractionEnabled = NO;
		button.layer.zPosition = 0;
		[container sendSubviewToBack:button];
		button.hidden = YES;
	}
}
static void (*orig_bypassReelPassword)(id self, SEL _cmd);
static void hook_bypassReelPassword(id self, SEL _cmd) {
    orig_bypassReelPassword(self, _cmd);

    if (ENABLED(@"Bypass Reel Password")) {
        @try {
            UIView *container = [self valueForKey:@"_containerView"];
            if (container) {
                ZeusGlobalDestroyBypassArtifacts();
                UITextField *textField = [self valueForKey:@"_passwordTextField"];
                NSString *answer = [self valueForKey:@"_answer"];

                UIButton *bypassButton = [UIButton buttonWithType:UIButtonTypeSystem];
                [bypassButton setTitle:@"Bypass" forState:UIControlStateNormal];
                [bypassButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
                [bypassButton setBackgroundColor:UIColor.clearColor];
                bypassButton.layer.cornerRadius = 20.0;
                bypassButton.layer.masksToBounds = YES;

                UILabel *titleLabel = [self valueForKey:@"_titleLabel"];
                if (titleLabel && titleLabel.superview) {
                    UIView *hotColdContainer = [titleLabel.superview viewWithTag:869322];
                    if (!hotColdContainer) {
                        hotColdContainer = [[UIView alloc] initWithFrame:CGRectZero];
                        hotColdContainer.tag = 869322;
                        hotColdContainer.translatesAutoresizingMaskIntoConstraints = NO;

                        UILabel *tempLabel = [[UILabel alloc] initWithFrame:CGRectZero];
                        tempLabel.tag = 869323;
                        tempLabel.text = @"Ice Cold ❄️";
                        tempLabel.textAlignment = NSTextAlignmentCenter;
                        tempLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
                        tempLabel.textColor = UIColor.secondaryLabelColor ?: [UIColor colorWithWhite:1 alpha:0.8];
                        tempLabel.translatesAutoresizingMaskIntoConstraints = NO;

                        UIProgressView *progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
                        progress.tag = 869324;
                        progress.progressTintColor = [UIColor systemPinkColor] ?: [UIColor colorWithRed:1.0 green:0.2 blue:0.6 alpha:1.0];
                        progress.trackTintColor = [UIColor colorWithWhite:1 alpha:0.15];
                        progress.layer.cornerRadius = 2.0;
                        progress.clipsToBounds = YES;
                        progress.translatesAutoresizingMaskIntoConstraints = NO;

                        [hotColdContainer addSubview:tempLabel];
                        [hotColdContainer addSubview:progress];
                        [titleLabel.superview addSubview:hotColdContainer];

                        [NSLayoutConstraint activateConstraints:@[
                            [hotColdContainer.bottomAnchor constraintEqualToAnchor:titleLabel.topAnchor constant:-8], [hotColdContainer.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
                            [hotColdContainer.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],

                            [tempLabel.topAnchor constraintEqualToAnchor:hotColdContainer.topAnchor], [tempLabel.leadingAnchor constraintEqualToAnchor:hotColdContainer.leadingAnchor], [tempLabel.trailingAnchor constraintEqualToAnchor:hotColdContainer.trailingAnchor],

                            [progress.topAnchor constraintEqualToAnchor:tempLabel.bottomAnchor constant:4], [progress.leadingAnchor constraintEqualToAnchor:hotColdContainer.leadingAnchor], [progress.trailingAnchor constraintEqualToAnchor:hotColdContainer.trailingAnchor],
                            [progress.heightAnchor constraintEqualToConstant:4], [progress.bottomAnchor constraintEqualToAnchor:hotColdContainer.bottomAnchor]
                        ]];
                    }
                }

                BOOL sharePresented = ZeusIsShareSheetPresented();
                UIView *root = container.window;
                if (!root) {
                    root = container;
                    while (root.superview) {
                        root = root.superview;
                    }
                }
                if ([root viewWithTag:869321] || [container viewWithTag:869321]) {
                    return;
                }
                bypassButton.tag = 869321;
                ZeusSetCaptureHiding(bypassButton);
                UIView *initialParent = container;
                [initialParent addSubview:bypassButton];

                UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
                UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
                blurView.userInteractionEnabled = NO;
                blurView.layer.cornerRadius = 20.0;
                blurView.layer.masksToBounds = YES;
                blurView.layer.borderWidth = 1.0;
                blurView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.12].CGColor;
                blurView.frame = bypassButton.bounds;
                blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                [bypassButton insertSubview:blurView atIndex:0];

                [bypassButton setTranslatesAutoresizingMaskIntoConstraints:NO];
                NSArray *constraints = @[
                    [bypassButton.topAnchor constraintEqualToAnchor:textField.bottomAnchor constant:20], [bypassButton.centerXAnchor constraintEqualToAnchor:container.centerXAnchor], [bypassButton.widthAnchor constraintEqualToConstant:100],
                    [bypassButton.heightAnchor constraintEqualToConstant:40]
                ];
                [NSLayoutConstraint activateConstraints:constraints];
                objc_setAssociatedObject(bypassButton, &kZeusBypassConstraintsKey, constraints, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

                container.userInteractionEnabled = YES;
                bypassButton.userInteractionEnabled = YES;
                bypassButton.exclusiveTouch = YES;
                bypassButton.layer.zPosition = 10000;
                [initialParent bringSubviewToFront:bypassButton];
				ZeusAdjustBypassElevation(bypassButton, container, root, self);

                __weak typeof(self) weakSelf = self;
                __weak UIView *weakContainer = container;
                __weak UIView *weakRoot = root;
                __weak UIButton *weakButton = bypassButton;
                __weak UIProgressView *weakProgress = (UIProgressView *)[[titleLabel.superview viewWithTag:869322] viewWithTag:869324];
                __weak UILabel *weakTempLabel = (UILabel *)[[titleLabel.superview viewWithTag:869322] viewWithTag:869323];

                [((UITextField *)textField) addAction:[UIAction actionWithHandler:^(UIAction *action) {
                    UITextField *tfEdit = (UITextField *)textField;
                    NSString *typed = tfEdit.text ?: @"";
                    NSString *ansFull = [weakSelf valueForKey:@"_answer"] ?: @"";

                    NSUInteger minLen = MIN(typed.length, ansFull.length);
                    NSUInteger correct = 0;
                    for (NSUInteger i = 0; i < minLen; i++) {
                        if ([[typed lowercaseString] characterAtIndex:i] == [[ansFull lowercaseString] characterAtIndex:i]) {
                            correct++;
                        } else {
                            break;
                        }
                    }

                    NSNumber *prevCorrectNum = objc_getAssociatedObject(tfEdit, &kZeusHotColdPrevCorrectKey);
                    NSNumber *prevTypedLenNum = objc_getAssociatedObject(tfEdit, &kZeusHotColdPrevTypedLenKey);
                    NSNumber *staleCountNum = objc_getAssociatedObject(tfEdit, &kZeusHotColdStaleCountKey);
                    NSUInteger prevCorrect = prevCorrectNum ? [prevCorrectNum unsignedIntegerValue] : 0;
                    NSUInteger prevTypedLen = prevTypedLenNum ? [prevTypedLenNum unsignedIntegerValue] : 0;
                    NSUInteger staleCount = staleCountNum ? [staleCountNum unsignedIntegerValue] : 0;

                    BOOL typedMore = typed.length > prevTypedLen;
                    if (correct > prevCorrect) {
                        staleCount = 0;  // improvement resets stagnation
                    } else if (typedMore && correct == prevCorrect) {
                        staleCount += 1;
                    } else if (typed.length < prevTypedLen) {
                        staleCount = (staleCount > 0) ? staleCount - 1 : 0;
                    } else {
                    }

                    objc_setAssociatedObject(tfEdit, &kZeusHotColdPrevCorrectKey, @(correct), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    objc_setAssociatedObject(tfEdit, &kZeusHotColdPrevTypedLenKey, @(typed.length), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    objc_setAssociatedObject(tfEdit, &kZeusHotColdStaleCountKey, @(staleCount), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

                    CGFloat baseScore = ZeusMatchScore(typed, ansFull);
                    CGFloat adjusted = baseScore;
                    if (staleCount > 2) {
                        CGFloat decay = 0.05f * (CGFloat)(staleCount - 2);
                        adjusted = MAX(0.0f, baseScore - decay);
                    }

                    if (weakProgress) {
                        [weakProgress setProgress:adjusted animated:YES];
                    }
                    if (weakTempLabel) {
                        weakTempLabel.text = ZeusTemperatureLabel(adjusted);
                    }
                }] forControlEvents:UIControlEventEditingChanged];

				ZeusBypassButtonTarget *tapTarget = [ZeusBypassButtonTarget new];
				tapTarget.button = bypassButton;
				tapTarget.container = weakContainer;
				tapTarget.root = weakRoot;
				tapTarget.owner = weakSelf;
				[bypassButton addTarget:tapTarget action:@selector(handleTap:) forControlEvents:UIControlEventTouchUpInside];
				if (@available(iOS 14.0, *)) {
					[bypassButton addAction:[UIAction actionWithHandler:^(__unused UIAction *a) {
						[tapTarget handleTap:bypassButton];
					}] forControlEvents:UIControlEventPrimaryActionTriggered];
				}
				objc_setAssociatedObject(bypassButton, &kZeusBypassButtonTargetKey, tapTarget, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

                [initialParent bringSubviewToFront:bypassButton];

                id willPresentObs = [[NSNotificationCenter defaultCenter] addObserverForName:UIWindowDidBecomeKeyNotification
                                                                                    object:nil
                                                                                    queue:NSOperationQueue.mainQueue
                                                                                usingBlock:^(NSNotification *_Nonnull note) {
                                                                                    if (!weakSelf) { ZeusTeardownBypassButton(weakButton); return; }
                                                                                    ZeusUpdateBypassButtonPlacement(weakButton, weakContainer, weakRoot, weakSelf);
																					ZeusAdjustBypassElevation(weakButton, weakContainer, weakRoot, weakSelf);
                                                                                }];
                id didPresentObs = [[NSNotificationCenter defaultCenter] addObserverForName:UIWindowDidResignKeyNotification
                                                                                    object:nil
                                                                                    queue:NSOperationQueue.mainQueue
                                                                                usingBlock:^(NSNotification *_Nonnull note) {
                                                                                if (!weakSelf) { ZeusTeardownBypassButton(weakButton); return; }
                                                                                ZeusUpdateBypassButtonPlacement(weakButton, weakContainer, weakRoot, weakSelf);
																				ZeusAdjustBypassElevation(weakButton, weakContainer, weakRoot, weakSelf);
                                                                                }];
                id appActiveObs = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                                                    object:nil
                                                                                    queue:NSOperationQueue.mainQueue
                                                                                usingBlock:^(NSNotification *_Nonnull note) {
                                                                                if (!weakSelf) { ZeusTeardownBypassButton(weakButton); return; }
                                                                                ZeusUpdateBypassButtonPlacement(weakButton, weakContainer, weakRoot, weakSelf);
																				ZeusAdjustBypassElevation(weakButton, weakContainer, weakRoot, weakSelf);
                                                                                }];
                id appForegroundObs = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillEnterForegroundNotification
                                                                                        object:nil
                                                                                        queue:NSOperationQueue.mainQueue
                                                                                    usingBlock:^(NSNotification *_Nonnull note) {
                                                                                    if (!weakSelf) { ZeusTeardownBypassButton(weakButton); return; }
                                                                                    ZeusUpdateBypassButtonPlacement(weakButton, weakContainer, weakRoot, weakSelf);
																					ZeusAdjustBypassElevation(weakButton, weakContainer, weakRoot, weakSelf);
                                                                                    }];
                NSTimer *guardTimer = [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer * _Nonnull t) {
                    if (!weakSelf || !weakButton || !weakContainer) { [t invalidate]; return; }
                    UITextField *guardTF = nil; @try { guardTF = [weakSelf valueForKey:@"_passwordTextField"]; } @catch (__unused NSException *e) { guardTF = nil; }
					UIView *ownerView = nil; @try { ownerView = [weakSelf valueForKey:@"view"]; } @catch (__unused NSException *e) { ownerView = nil; }
					if (!guardTF || ![guardTF isKindOfClass:[UITextField class]] || guardTF.window == nil || ![ownerView isKindOfClass:[UIView class]] || ownerView.window == nil) {
						// Keep the button, just adjust elevation back to container mode
						ZeusAdjustBypassElevation(weakButton, weakContainer, weakRoot, weakSelf);
						return;
					}
					ZeusAdjustBypassElevation(weakButton, weakContainer, weakRoot, weakSelf);
                }];
                [[NSRunLoop mainRunLoop] addTimer:guardTimer forMode:NSRunLoopCommonModes];
                objc_setAssociatedObject(weakButton, &kZeusBypassTimerKey, guardTimer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

                NSArray *observers = @[ willPresentObs ?: [NSNull null], didPresentObs ?: [NSNull null], appActiveObs ?: [NSNull null], appForegroundObs ?: [NSNull null] ];
                objc_setAssociatedObject(bypassButton, &kZeusBypassObserversKey, observers, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        } @catch (NSException *e) {
            NSLog(@"Error in bypassReelPassword: %@", e);
        }
    }
}

void ZURegisterBypassReelPasswordHooks(void) {
    NullHookMessageEx(objc_getClass("IGMediaOverlayProfileWithPasswordView"), @selector(layoutSubviews), (void *)hook_bypassReelPassword, &orig_bypassReelPassword);
}