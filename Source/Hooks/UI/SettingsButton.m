#import "Include.h"

static void (*orig_settingButtonInFeedView)(id self, SEL _cmd);

// Per-instance guard key
static char kZeusSettingsButtonOnceKey;

static void hook_settingButtonInFeedView(id self, SEL _cmd) {
	if (orig_settingButtonInFeedView) orig_settingButtonInFeedView(self, _cmd);

	@try {
		// Ensure custom logic runs only once per instance
		NSNumber *alreadyRan = objc_getAssociatedObject(self, &kZeusSettingsButtonOnceKey);
		if ([alreadyRan boolValue]) {
			return;
		}

		// Safely access expected subviews
		NSArray<UIView *> *subviews = [self subviews];
		if (subviews.count <= 1) {
			return;
		}
		UIView *headerView = subviews[1];
		if (headerView.subviews.count <= 1) {
			return;
		}

		IGBadgeButton *likeButton = (IGBadgeButton *)headerView.subviews[1];
		if (![likeButton isKindOfClass:[UIView class]]) {
			return;
		}

		for (UIView *view in headerView.subviews) {
			if ([view isKindOfClass:[UIButton class]] && view.tag == 777) {
				[view removeFromSuperview];
			}
		}

		UIButton *settingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
		settingsButton.tag = 777;
		UIImage *gearImage = [UIImage systemImageNamed:@"gear"];
		[settingsButton setImage:gearImage forState:UIControlStateNormal];
		settingsButton.tintColor = [UIColor labelColor];

		CGFloat spacing = 18.0;
		CGRect likeFrame = likeButton.frame;
		CGSize buttonSize = likeFrame.size.width > 0 && likeFrame.size.height > 0 ? likeFrame.size : CGSizeMake(32, 32);
		settingsButton.frame = CGRectMake(CGRectGetMinX(likeFrame) - buttonSize.width - spacing,
										 likeFrame.origin.y,
										 buttonSize.width,
										 buttonSize.height);

		ZeusSetCaptureHiding(settingsButton);
		// Always add the gear. It used to be suppressed whenever Shake To Open was
		// enabled, leaving no visible entry point at all if the shake hook or the
		// tab-bar long-press ever stopped firing.
		[headerView addSubview:settingsButton];

		[settingsButton addAction:[UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
			@try {
				SettingsViewController *settingsVC = [[SettingsViewController alloc] init];
				UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:settingsVC];
				navController.modalPresentationStyle = UIModalPresentationPageSheet;
				[[ZeusHelper topViewController] presentViewController:navController animated:YES completion:nil];
			} @catch (NSException *exception) {
				NSLog(@"Error presenting settings: %@", exception);
			}
		}] forControlEvents:UIControlEventTouchUpInside];

		objc_setAssociatedObject(self, &kZeusSettingsButtonOnceKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	} @catch (NSException *exception) {
		NSLog(@"[Zeus] SettingsButton layout hook: %@", exception);
	}
}

void ZURegisterSettingsButtonHooks(void) {
    Class header = ZeusFirstClass(@[
        @"_TtC16IGHomeFeedHeader20IGHomeFeedHeaderView",
        @"IGHomeFeedHeaderView"
    ]);
    NullHookMessageIfPresent(header, @selector(layoutSubviews), (void *)hook_settingButtonInFeedView, &orig_settingButtonInFeedView);
}