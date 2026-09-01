/* Zeus entry point inside Instagram Settings and privacy.
 *
 * That screen is SwiftUI, not Bloks and not UIKit. A runtime probe showed the
 * profile hamburger pushing:
 *     Settings2Views.IGSettingsHostingController<Settings2Views.IGSettingScreenView>
 * i.e. a UIHostingController subclass wrapping the SwiftUI view IGSettingScreenView.
 *
 * Consequences:
 *   - There is no UITableViewDataSource to append a row to. The rows come from
 *     IGSettings2Renderer.SettingScreenViewModel, a pure Swift type with no
 *     Objective-C dispatch, so it cannot be swizzled.
 *   - The host controller, however, inherits from UIViewController, so its
 *     lifecycle methods ARE ordinary ObjC selectors and are safe to swizzle.
 *
 * So we attach to the host controller and add a Zeus button to its navigation
 * item. Detection is by class-name substring because the host is a Swift
 * generic: its runtime name is a mangled specialisation, and matching the whole
 * mangled string would break the moment Meta changes the generic parameter.
 */

static char kZeusSettingsEntryOnceKey;

static void (*orig_settingsEntry_viewDidAppear)(id, SEL, BOOL) = NULL;

@interface ZeusSettingsEntryTarget : NSObject
+ (instancetype)shared;
- (void)openZeus;
@end

@implementation ZeusSettingsEntryTarget
+ (instancetype)shared {
    static ZeusSettingsEntryTarget *t;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ t = [ZeusSettingsEntryTarget new]; });
    return t;
}
- (void)openZeus {
    @try {
        SettingsViewController *vc = [[SettingsViewController alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationPageSheet;
        [[ZeusHelper topViewController] presentViewController:nav animated:YES completion:nil];
    } @catch (NSException *e) {
        NSLog(@"[Zeus] settings entry: %@", e);
    }
}
@end

static void hook_settingsEntry_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (orig_settingsEntry_viewDidAppear) orig_settingsEntry_viewDidAppear(self, _cmd, animated);
    @try {
        NSString *cls = NSStringFromClass([self class]);
        if (![cls containsString:@"IGSettingScreenView"]) return;
        if (![self isKindOfClass:[UIViewController class]]) return;

        UIViewController *vc = (UIViewController *)self;
        if ([objc_getAssociatedObject(vc, &kZeusSettingsEntryOnceKey) boolValue]) return;

        UIImage *gear = [UIImage systemImageNamed:@"gearshape.fill"];
        UIBarButtonItem *item =
            [[UIBarButtonItem alloc] initWithImage:gear
                                             style:UIBarButtonItemStylePlain
                                            target:[ZeusSettingsEntryTarget shared]
                                            action:@selector(openZeus)];
        item.tintColor = [ZeusHelper iotaPinkColor];

        // Append rather than replace: SwiftUI may already own a toolbar item.
        NSMutableArray *items =
            [NSMutableArray arrayWithArray:vc.navigationItem.rightBarButtonItems ?: @[]];
        [items insertObject:item atIndex:0];
        vc.navigationItem.rightBarButtonItems = items;

        objc_setAssociatedObject(vc, &kZeusSettingsEntryOnceKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } @catch (NSException *e) {
        NSLog(@"[Zeus] settings entry hook: %@", e);
    }
}

void ZURegisterSettingsEntryHooks(void) {
    NullHookMessageEx([UIViewController class], @selector(viewDidAppear:),
                      (void *)hook_settingsEntry_viewDidAppear, &orig_settingsEntry_viewDidAppear);
}
