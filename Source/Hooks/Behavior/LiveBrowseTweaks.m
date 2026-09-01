#import "Include.h"
#import "Include/InstagramHeaders.h"
#import "Include/ZeusTweakCommon.h"
#import "Include/ZeusHelper.h"
#import <objc/runtime.h>

/* Live viewer count polling + comment strip toggle. */

static void zeus_disableLiveViewerCountPuller(id feedbackController) {
    Ivar pullerIvar = class_getInstanceVariable([feedbackController class], "_viewCountPuller");
    if (!pullerIvar) return;
    id puller = object_getIvar(feedbackController, pullerIvar);
    if (!puller) return;

    Ivar activeIvar = NULL;
    Ivar timerIvar = NULL;
    for (Class c = [puller class]; c && c != [NSObject class]; c = class_getSuperclass(c)) {
        if (!activeIvar) activeIvar = class_getInstanceVariable(c, "_isActive");
        if (!timerIvar) timerIvar = class_getInstanceVariable(c, "_nextFetchTimer");
        if (activeIvar && timerIvar) break;
    }
    if (activeIvar) {
        ptrdiff_t off = ivar_getOffset(activeIvar);
        *(BOOL *)((char *)(__bridge void *)puller + off) = NO;
    }
    if (timerIvar) {
        id timer = object_getIvar(puller, timerIvar);
        if (timer && [timer respondsToSelector:@selector(invalidate)])
            ((void (*)(id, SEL))objc_msgSend)(timer, @selector(invalidate));
    }
}

static void (*orig_liveFeedbackStart)(id, SEL);
static void hook_liveFeedbackStart(id self, SEL _cmd) {
    orig_liveFeedbackStart(self, _cmd);
    if (ENABLED(@"Live Without Viewer List"))
        zeus_disableLiveViewerCountPuller(self);
}

static __weak UIViewController *zeus_activeLiveCommentsVC = nil;
static BOOL zeus_liveCommentsHidden = NO;
static const void *kZeusLiveHeartLPKey = &kZeusLiveHeartLPKey;

static void zeus_hideCommentCollections(UIView *root, BOOL hide, int depth) {
    if (!root || depth > 8) return;
    for (UIView *sub in root.subviews) {
        if ([sub isKindOfClass:[UICollectionView class]]) {
            sub.alpha = hide ? 0.0 : 1.0;
            sub.userInteractionEnabled = !hide;
            continue;
        }
        zeus_hideCommentCollections(sub, hide, depth + 1);
    }
}

static void zeus_applyLiveCommentsVisibility(void) {
    if (!zeus_activeLiveCommentsVC || !zeus_activeLiveCommentsVC.isViewLoaded) return;
    zeus_hideCommentCollections(zeus_activeLiveCommentsVC.view, zeus_liveCommentsHidden, 0);
}

@interface ZeusLiveCommentToggle : NSObject
+ (instancetype)shared;
- (void)heartLongPress:(UILongPressGestureRecognizer *)g;
@end

@implementation ZeusLiveCommentToggle
+ (instancetype)shared {
    static ZeusLiveCommentToggle *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [ZeusLiveCommentToggle new]; });
    return s;
}
- (void)heartLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    if (!ENABLED(@"Live Comments Sheet Toggle")) return;
    zeus_liveCommentsHidden = !zeus_liveCommentsHidden;
    zeus_applyLiveCommentsVisibility();
    if (ENABLED(@"Show Banners")) {
        NSString *t = zeus_liveCommentsHidden ? @"Comment list hidden" : @"Comment list visible";
        [ZeusHelper showToastWithTitle:@"Live" subtitle:t icon:[UIImage systemImageNamed:@"bubble.left.and.bubble.right"] autoHide:2 openURL:nil];
    }
}
@end

static void zeus_attachHeartLongPress(UIView *v) {
    if (!v || objc_getAssociatedObject(v, kZeusLiveHeartLPKey)) return;
    UILongPressGestureRecognizer *g = [[UILongPressGestureRecognizer alloc] initWithTarget:[ZeusLiveCommentToggle shared] action:@selector(heartLongPress:)];
    g.minimumPressDuration = 0.5;
    g.cancelsTouchesInView = YES;
    [v addGestureRecognizer:g];
    objc_setAssociatedObject(v, kZeusLiveHeartLPKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void (*orig_liveFooterLayout)(id, SEL);
static void hook_liveFooterLayout(id self, SEL _cmd) {
    orig_liveFooterLayout(self, _cmd);
    if (!ENABLED(@"Live Comments Sheet Toggle")) return;
    Ivar iv = class_getInstanceVariable([self class], "_likeButton");
    if (!iv) return;
    UIView *btn = object_getIvar(self, iv);
    if (btn) zeus_attachHeartLongPress(btn);
}

static void (*orig_liveCommentsAppear)(id, SEL, BOOL);
static void hook_liveCommentsAppear(id self, SEL _cmd, BOOL anim) {
    orig_liveCommentsAppear(self, _cmd, anim);
    zeus_activeLiveCommentsVC = (UIViewController *)self;
    zeus_liveCommentsHidden = NO;
    zeus_applyLiveCommentsVisibility();
}

static void (*orig_liveCommentsDisappear)(id, SEL, BOOL);
static void hook_liveCommentsDisappear(id self, SEL _cmd, BOOL anim) {
    if (zeus_activeLiveCommentsVC == (UIViewController *)self) zeus_activeLiveCommentsVC = nil;
    orig_liveCommentsDisappear(self, _cmd, anim);
}

void ZURegisterLiveBrowseTweaksHooks(void) {
    Class feedback = objc_getClass("IGLiveFeedbackController");
    if (feedback) NullHookMessageEx(feedback, @selector(start), (void *)hook_liveFeedbackStart, &orig_liveFeedbackStart);
    Class footer = objc_getClass("IGLiveFooterButtonsView");
    if (footer) NullHookMessageEx(footer, @selector(layoutSubviews), (void *)hook_liveFooterLayout, &orig_liveFooterLayout);
    Class comments = objc_getClass("IGLiveCommentsContainerViewController");
    if (comments) {
        NullHookMessageEx(comments, @selector(viewDidAppear:), (void *)hook_liveCommentsAppear, &orig_liveCommentsAppear);
        NullHookMessageEx(comments, @selector(viewWillDisappear:), (void *)hook_liveCommentsDisappear, &orig_liveCommentsDisappear);
    }
}
