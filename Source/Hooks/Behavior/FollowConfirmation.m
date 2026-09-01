#import "Include/ZeusHelper.h"

static void (*orig_followConfirmation)(id self, SEL _cmd);
static void hook_followConfirmation(id self, SEL _cmd) {
    if (!ENABLED(@"Follow Confirmation")) {
        orig_followConfirmation(self, _cmd);
        return;
    }
    
    // Swift IGFollowController on 444 isn't guaranteed KVC-compliant like the old ObjC one.
    NSInteger userFollowStatus = [ZeusValueForKey(ZeusValueForKey(self, @"user"), @"followStatus") integerValue];
    
    if (userFollowStatus == 2) {
        [ZeusHelper showCustomAlertWithActions:@"✋ Woah! Hold up!" description:@"Are you sure you want to follow this user?" actions:@[
            @{
                @"title": @"Yes, follow them!",
                @"handler": ^(id sender) {
                    orig_followConfirmation(self, _cmd);
                }
            },
            @{
                @"title": @"No, I'm good.",
                @"handler": ^(id sender) {
                    // Do nothing, just cancel
                }
            }
        ]];
    } else {
        orig_followConfirmation(self, _cmd);
    }
}

void ZURegisterFollowConfirmationHooks(void) {
    // IG 444 rewrote IGFollowController in Swift and dropped the leading-underscore
    // _didPressFollowButton entry point. The Swift class exposes
    // didPressFollowButtonFromControlEvent (button target/action) and
    // tryToggleFriendship (the actual follow/unfollow decision point) instead;
    // try both, preferring the direct rename. _didPressFollowButton is kept last
    // so a 441 build (plain IGFollowController) still resolves from this same call.
    BOOL hooked = ZeusHookFirst(@[
        @"_TtC11IGFollowing18IGFollowController",
        @"IGFollowing.IGFollowController",
        @"IGFollowController"
    ], @[
        @"didPressFollowButtonFromControlEvent",
        @"tryToggleFriendship",
        @"_didPressFollowButton"
    ], (void *)hook_followConfirmation, &orig_followConfirmation);

    if (!hooked) {
        RecordFailedHookLine(@"Follow Confirmation — no candidate class/selector resolved");
    }
}