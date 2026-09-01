#import "Include/ZeusTheme.h"

NSNotificationName const ZeusThemeDidChangeNotification = @"ZeusThemeDidChangeNotification";

// Settings keys follow the conventions the settings screen already uses.
static NSString *const kZeusThemeSelectionKey = @"Zeus Theme_SegmentIndex";
static NSString *const kZeusThemeCustomKey    = @"Custom Theme Color_Color";

static UIColor *ZeusThemeHex(uint32_t rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

@interface ZeusTheme ()
@property (nonatomic, copy, readwrite) NSString *name;
@property (nonatomic, copy, readwrite) NSString *detail;
@property (nonatomic, strong, readwrite) UIColor *accent;
@property (nonatomic, strong, readwrite, nullable) UIColor *background;
@property (nonatomic, strong, readwrite, nullable) UIColor *cellBackground;
@property (nonatomic, strong, readwrite, nullable) UIColor *primaryText;
@property (nonatomic, strong, readwrite, nullable) UIColor *secondaryText;
@end

@implementation ZeusTheme

+ (instancetype)name:(NSString *)name
              detail:(NSString *)detail
              accent:(UIColor *)accent
          background:(nullable UIColor *)background
                cell:(nullable UIColor *)cell
             primary:(nullable UIColor *)primary
           secondary:(nullable UIColor *)secondary {
    ZeusTheme *t = [ZeusTheme new];
    t.name = name;
    t.detail = detail;
    t.accent = accent;
    t.background = background;
    t.cellBackground = cell;
    t.primaryText = primary;
    t.secondaryText = secondary;
    return t;
}

#pragma mark - Registry

+ (NSArray<ZeusTheme *> *)allThemes {
    static NSArray<ZeusTheme *> *themes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        themes = @[
            // ----------------------------------------------------------------
            // ADD OR REPLACE THEMES HERE. The picker list, the accent used across
            // every Zeus screen and the saved selection all derive from this
            // array, so a new entry needs no other change anywhere.
            //
            // ORDER MATTERS: the selection persists as an index, so inserting a
            // theme above an existing one silently changes what an already saved
            // choice means. Append, do not insert. Custom must stay last.
            // ----------------------------------------------------------------
            [self name:@"Midnight" detail:@"Cool blue on deep navy"
                accent:ZeusThemeHex(0x4DA3FF) background:ZeusThemeHex(0x0B0F16)
                  cell:ZeusThemeHex(0x151C27) primary:ZeusThemeHex(0xF2F5F9)
             secondary:ZeusThemeHex(0x8A94A6)],

            [self name:@"Bolt" detail:@"Classic pink on true black"
                accent:ZeusThemeHex(0xFF69B4) background:ZeusThemeHex(0x000000)
                  cell:ZeusThemeHex(0x1C1C1E) primary:ZeusThemeHex(0xFFFFFF)
             secondary:ZeusThemeHex(0x8E8E93)],

            [self name:@"Olympus" detail:@"Gold leaf on warm charcoal"
                accent:ZeusThemeHex(0xE8B44A) background:ZeusThemeHex(0x0F0E0B)
                  cell:ZeusThemeHex(0x1B1915) primary:ZeusThemeHex(0xF6F2E8)
             secondary:ZeusThemeHex(0x9A9284)],

            [self name:@"Thunderhead" detail:@"Violet on ink purple"
                accent:ZeusThemeHex(0xA78BFA) background:ZeusThemeHex(0x100D1A)
                  cell:ZeusThemeHex(0x1B1728) primary:ZeusThemeHex(0xF3F0FA)
             secondary:ZeusThemeHex(0x9189A8)],

            [self name:@"Aegis" detail:@"Teal on black spruce"
                accent:ZeusThemeHex(0x2DD4BF) background:ZeusThemeHex(0x081413)
                  cell:ZeusThemeHex(0x111F1E) primary:ZeusThemeHex(0xEAF5F3)
             secondary:ZeusThemeHex(0x7E9996)],

            [self name:@"Ember" detail:@"Orange on burnt umber"
                accent:ZeusThemeHex(0xFF7043) background:ZeusThemeHex(0x140D0A)
                  cell:ZeusThemeHex(0x211714) primary:ZeusThemeHex(0xFAF0EC)
             secondary:ZeusThemeHex(0xA38C84)],

            [self name:@"Terminal" detail:@"Phosphor green on near black"
                accent:ZeusThemeHex(0x4ADE80) background:ZeusThemeHex(0x070A08)
                  cell:ZeusThemeHex(0x0F1512) primary:ZeusThemeHex(0xE6F5EA)
             secondary:ZeusThemeHex(0x7D9887)],

            [self name:@"Daylight" detail:@"The one light theme, brand pink"
                accent:ZeusThemeHex(0xE0457B) background:ZeusThemeHex(0xF2F2F7)
                  cell:ZeusThemeHex(0xFFFFFF) primary:ZeusThemeHex(0x11141A)
             secondary:ZeusThemeHex(0x6E7480)],

            // Accent is overridden at read time by the Custom Theme Color setting.
            [self name:@"Custom" detail:@"Your own accent on true black"
                accent:ZeusThemeHex(0xFF69B4) background:ZeusThemeHex(0x000000)
                  cell:ZeusThemeHex(0x1C1C1E) primary:ZeusThemeHex(0xFFFFFF)
             secondary:ZeusThemeHex(0x8E8E93)],
        ];
    });
    return themes;
}

+ (NSArray<NSString *> *)themeNames {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (ZeusTheme *t in [self allThemes]) {
        [names addObject:t.name];
    }
    return [names copy];
}

#pragma mark - Selection

+ (UIColor *)storedCustomAccent {
    NSData *data = [[NSUserDefaults standardUserDefaults] objectForKey:kZeusThemeCustomKey];
    if (![data isKindOfClass:[NSData class]]) return nil;
    UIColor *color = nil;
    @try {
        color = [NSKeyedUnarchiver unarchivedObjectOfClass:[UIColor class] fromData:data error:nil];
    } @catch (__unused NSException *e) {}
    return color;
}

+ (NSInteger)selectedIndex {
    NSInteger index = [[NSUserDefaults standardUserDefaults] integerForKey:kZeusThemeSelectionKey];
    if (index < 0 || index >= (NSInteger)[self allThemes].count) index = 0;
    return index;
}

+ (void)setSelectedIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)[self allThemes].count) return;
    [[NSUserDefaults standardUserDefaults] setInteger:index forKey:kZeusThemeSelectionKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:ZeusThemeDidChangeNotification
                                                        object:nil];
}

+ (ZeusTheme *)currentTheme {
    ZeusTheme *theme = [self allThemes][[self selectedIndex]];
    if ([theme.name isEqualToString:@"Custom"]) {
        // Assign unconditionally. allThemes is a shared singleton, so setting the
        // accent only when a stored colour exists would keep showing a stale one
        // after the custom colour was cleared.
        UIColor *custom = [self storedCustomAccent];
        theme.accent = custom ?: ZeusThemeHex(0xFF69B4);
    }
    return theme;
}

#pragma mark - Application

+ (void)applyToTableView:(UITableView *)tableView
    navigationController:(UINavigationController *)navigationController {
    ZeusTheme *theme = [self currentTheme];

    if (tableView) {
        tableView.backgroundColor = theme.background ?: [UIColor systemGroupedBackgroundColor];
    }
    if (navigationController) {
        navigationController.navigationBar.tintColor = theme.accent;
        if (theme.background) {
            // A themed screen needs an opaque bar, otherwise the scroll edge
            // appearance shows the system colour behind the themed table.
            UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
            [appearance configureWithOpaqueBackground];
            appearance.backgroundColor = theme.background;
            if (theme.primaryText) {
                appearance.titleTextAttributes = @{NSForegroundColorAttributeName: theme.primaryText};
                appearance.largeTitleTextAttributes = @{NSForegroundColorAttributeName: theme.primaryText};
            }
            navigationController.navigationBar.standardAppearance = appearance;
            navigationController.navigationBar.scrollEdgeAppearance = appearance;
            navigationController.navigationBar.compactAppearance = appearance;
        }
    }
}

+ (void)decorateCell:(UITableViewCell *)cell {
    if (!cell) return;
    ZeusTheme *theme = [self currentTheme];

    if (theme.cellBackground) {
        cell.backgroundColor = theme.cellBackground;
        cell.contentView.backgroundColor = [UIColor clearColor];
        UIView *selected = [UIView new];
        selected.backgroundColor = [theme.accent colorWithAlphaComponent:0.18];
        cell.selectedBackgroundView = selected;
    }
    if (theme.primaryText) cell.textLabel.textColor = theme.primaryText;
    if (theme.secondaryText) cell.detailTextLabel.textColor = theme.secondaryText;
}

@end
