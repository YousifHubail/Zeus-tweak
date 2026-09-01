#import <UIKit/UIKit.h>

/// Edits a list of usernames stored in NSUserDefaults (e.g. auto-mark lists for Story Ghost / Mark As Seen).
/// Set listKey and listTitle before presenting. listKey is the NSUserDefaults key for the array of NSString usernames.
@interface ZeusUserListEditorViewController : UITableViewController
@property (nonatomic, copy) NSString *listKey;
@property (nonatomic, copy) NSString *listTitle;
@end
