static void (*orig_shakeToOpen)(id self, SEL _cmd, int arg1);
static void hook_shakeToOpen(id self, SEL _cmd, int arg1) {
    @try {
#ifndef SIDELOAD
        if (!ENABLED(@"Shake To Open")) {
            orig_shakeToOpen(self, _cmd, arg1);
            return;
        }
#else
        // Sideload rescue hatch: shake ALWAYS opens Zeus settings, pref or not.
        // Every other entry point is anchored to Instagram UI -- the Home tab
        // long-press (_homeButtonLongPressed:) and the gear injected into
        // IGHomeFeedHeaderView. Turning on Liquid Glass flips Instagram to the
        // Homecoming floating tab bar, which drops the Home tab and reshapes the
        // feed header -- killing both at once and stranding the user with no way
        // back into the settings needed to turn it off. UIMotionEvent is UIKit,
        // so this path survives any Instagram redesign.
#endif
        
        if (arg1 == 1) {
            UIViewController *topController = [ZeusHelper topViewController];
            if (!topController) {
                return;
            }
            
            // Check if settings are already open
            if ([topController isKindOfClass:NSClassFromString(@"SettingsViewController")] || 
                [topController.presentedViewController isKindOfClass:NSClassFromString(@"SettingsViewController")] ||
                [topController isKindOfClass:[%c(IGPartialModalSheetViewController) class]]) {
                return;
            }
            
            // Present settings
            SettingsViewController *vc = [[SettingsViewController alloc] init];
            if (!vc) {
                NSLog(@"Failed to create SettingsViewController");
                return;
            }
            
            UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:vc];
            if (!navController) {
                NSLog(@"Failed to create NavigationController");
                return;
            }
            
            navController.modalPresentationStyle = UIModalPresentationPageSheet;
            UIViewController *rootViewController = [UIApplication sharedApplication].keyWindow.rootViewController;
            if (!rootViewController) {
                NSLog(@"No root view controller found");
                return;
            }
            
            [rootViewController presentViewController:navController animated:YES completion:nil];
        }
    } @catch (NSException *exception) {
        NSLog(@"Error in shake to open: %@", exception);
        // Fallback to original behavior
        orig_shakeToOpen(self, _cmd, arg1);
    }
}

void ZURegisterShakeToOpenHooks(void) {
    NullHookMessageEx(objc_getClass("UIMotionEvent"), @selector(setShakeState:), (void *)hook_shakeToOpen, &orig_shakeToOpen);
}