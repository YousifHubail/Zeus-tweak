#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted when the selected theme changes, so open Zeus screens can repaint
/// without being dismissed and reopened.
FOUNDATION_EXPORT NSNotificationName const ZeusThemeDidChangeNotification;

/// A colour scheme for Zeus menus only. Nothing here touches Instagram UI.
@interface ZeusTheme : NSObject

@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *detail;
@property (nonatomic, strong, readonly) UIColor *accent;
@property (nonatomic, strong, readonly, nullable) UIColor *background;
@property (nonatomic, strong, readonly, nullable) UIColor *cellBackground;
@property (nonatomic, strong, readonly, nullable) UIColor *primaryText;
@property (nonatomic, strong, readonly, nullable) UIColor *secondaryText;

/// Every selectable theme, in picker order. ADD NEW THEMES HERE.
+ (NSArray<ZeusTheme *> *)allThemes;
+ (NSArray<NSString *> *)themeNames;

+ (ZeusTheme *)currentTheme;
+ (NSInteger)selectedIndex;
/// Persists the choice and posts ZeusThemeDidChangeNotification.
+ (void)setSelectedIndex:(NSInteger)index;

+ (void)applyToTableView:(nullable UITableView *)tableView
    navigationController:(nullable UINavigationController *)navigationController;
+ (void)decorateCell:(nullable UITableViewCell *)cell;

@end

NS_ASSUME_NONNULL_END
