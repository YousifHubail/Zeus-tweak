#import "Include/ZeusThemePickerViewController.h"
#import "Include/ZeusTheme.h"

// A list rather than a segmented control: with nine themes a segment truncated
// every label to two characters. Each row shows the accent, the name and a short
// description, and selecting one repaints this screen immediately so the choice
// can be judged without leaving settings.
@interface ZeusThemePickerViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation ZeusThemePickerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Theme";

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds
                                                  style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64.0;
    [self.view addSubview:self.tableView];

    [self applyTheme];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self applyTheme];
}

- (void)applyTheme {
    [ZeusTheme applyToTableView:self.tableView navigationController:self.navigationController];
    self.view.backgroundColor = self.tableView.backgroundColor;
    [self.tableView reloadData];
}

#pragma mark - Table view

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[ZeusTheme allThemes].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"Applies to Zeus screens only. Instagram keeps its own appearance.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *const kID = @"ZeusThemeCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:kID];
    }

    NSArray<ZeusTheme *> *themes = [ZeusTheme allThemes];
    if (indexPath.row >= (NSInteger)themes.count) return cell;
    ZeusTheme *theme = themes[indexPath.row];
    BOOL isSelected = (indexPath.row == [ZeusTheme selectedIndex]);

    cell.textLabel.text = theme.name;
    cell.detailTextLabel.text = theme.detail;
    cell.detailTextLabel.numberOfLines = 0;

    // Swatch showing the accent over the theme background, so each row previews
    // the pairing rather than the accent alone.
    CGFloat side = 30.0;
    UIView *swatch = [[UIView alloc] initWithFrame:CGRectMake(0, 0, side, side)];
    swatch.backgroundColor = theme.cellBackground ?: [UIColor systemGray5Color];
    swatch.layer.cornerRadius = side / 2.0;
    swatch.layer.borderWidth = 1.0;
    swatch.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.15].CGColor;
    swatch.clipsToBounds = YES;

    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(side * 0.25, side * 0.25, side * 0.5, side * 0.5)];
    dot.backgroundColor = theme.accent;
    dot.layer.cornerRadius = (side * 0.5) / 2.0;
    [swatch addSubview:dot];
    cell.imageView.image = nil;
    for (UIView *old in cell.contentView.subviews) {
        if (old.tag == 8801) [old removeFromSuperview];
    }
    swatch.tag = 8801;
    cell.accessoryView = swatch;

    // Selected row is marked with the accent, since a checkmark alone reads
    // poorly against the darker themes.
    cell.textLabel.font = isSelected ? [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]
                                     : [UIFont systemFontOfSize:17 weight:UIFontWeightRegular];

    ZeusTheme *active = [ZeusTheme currentTheme];
    cell.backgroundColor = active.cellBackground ?: [UIColor secondarySystemGroupedBackgroundColor];
    cell.contentView.backgroundColor = [UIColor clearColor];
    cell.textLabel.textColor = isSelected ? active.accent
                                          : (active.primaryText ?: [UIColor labelColor]);
    cell.detailTextLabel.textColor = active.secondaryText ?: [UIColor secondaryLabelColor];

    UIView *selectedBG = [UIView new];
    selectedBG.backgroundColor = [active.accent colorWithAlphaComponent:0.18];
    cell.selectedBackgroundView = selectedBG;

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row == [ZeusTheme selectedIndex]) return;

    [ZeusTheme setSelectedIndex:indexPath.row];

    // Repaint in place. The notification posted above updates the screens
    // underneath, so backing out shows the new theme already applied.
    [UIView transitionWithView:self.view
                      duration:0.22
                       options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{
        [self applyTheme];
    } completion:nil];
}

@end
