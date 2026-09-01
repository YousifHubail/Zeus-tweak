static BOOL (*orig_hideCreateGroupButton)(id self, SEL _cmd);
static BOOL hook_hideCreateGroupButton(id self, SEL _cmd) {
    if (!ENABLED(@"Hide \"Create Group\" Button")) {
        return orig_hideCreateGroupButton(self, _cmd);
    }
    return NO;
}

static BOOL (*orig_hideCreateGroupButton2)(id self, SEL _cmd, BOOL animated);
static BOOL hook_hideCreateGroupButton2(id self, SEL _cmd, BOOL animated) {
    if (!ENABLED(@"Hide \"Create Group\" Button")) {
        return orig_hideCreateGroupButton2(self, _cmd, animated);
    }

    return NO;
}

static void (*orig_hideCreateGroupButton3)(id self, SEL _cmd);
static void hook_hideCreateGroupButton3(id self, SEL _cmd) {
    if (!ENABLED(@"Hide \"Create Group\" Button")) {
        return orig_hideCreateGroupButton3(self, _cmd);
    }

    [self removeFromSuperview];
}

void ZURegisterHideCreateGroupButtonHooks(void) {
    // Both mangled names below previously had the wrong length prefix (27/39 instead
    // of the correct 29/38), so neither ever resolved on 441 or 444; fixed here.
    Class bottomButtons = ZeusFirstClass(@[
        @"_TtC12IGShareSheet29IGSharesheetBottomButtonsView",
        @"IGShareSheet.IGSharesheetBottomButtonsView"
    ]);
    NullHookMessageIfPresent(bottomButtons, @selector(secondaryButtonTappedWithButton:), (void *)hook_hideCreateGroupButton, &orig_hideCreateGroupButton);

    Class bottomContainer = ZeusFirstClass(@[
        @"_TtC12IGShareSheet38IGShareSheetBottomButtonsViewContainer",
        @"IGShareSheet.IGShareSheetBottomButtonsViewContainer"
    ]);
    NullHookMessageIfPresent(bottomContainer, @selector(setSecondaryButtonEnabled:animated:), (void *)hook_hideCreateGroupButton2, &orig_hideCreateGroupButton2);

    Class facepile = ZeusFirstClass(@[
        @"_TtC12IGShareSheet45IGShareSheetCreateOrSendToGroupFacepileButton",
        @"IGShareSheet.IGShareSheetCreateOrSendToGroupFacepileButton"
    ]);
    NullHookMessageIfPresent(facepile, @selector(layoutSubviews), (void *)hook_hideCreateGroupButton3, &orig_hideCreateGroupButton3);
}