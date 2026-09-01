# DM Recipient Visibility ("Sent only to you" / "Sent to multiple people") Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Determine — with binary-level evidence, not assumption — whether Instagram's DM client exposes enough information for a receiving account to reliably tell "this shared post/reel/photo/video was sent only to me" apart from "this was sent to multiple people," and only if so, add a Zeus feature that shows that distinction on shared-media DM messages.

**Architecture:** Zeus hooks Instagram's Objective-C/Swift runtime by class+selector name (`Source/Runtime/ZUGlobalsAndHooking.m` / `ZUGlobalsAndHooking`-style swizzler), reading private state via KVC (`valueForKey:`) or direct ivar access, guarded by `@try/@catch` and `ZeusFirstClass`/`ZeusHookFirst` fallback lists for version resilience (see `Source/Hooks/Messages/MarkAsSeen.m` for the canonical pattern: `zeus_getThreadFromObject`, `zeus_getParticipantsFromThreadObject`, etc.). This plan follows that same architecture. No unit-test framework exists in this repo — every existing feature is validated by building, installing on a device, and manually exercising the feature (see `ZEUS_441_TO_444_REPORT.md` §J for the house style of a test plan). This plan's verification steps follow that same manual-testing convention instead of `pytest`/`XCTest`-style automated tests.

**Tech Stack:** Objective-C, custom runtime swizzling (no Theos `%hook`), KVC/ivar introspection, Mach-O static analysis (class-dump/otool-equivalent) for the investigation phase.

**Spec:** `../../../Reipients.txt` (the feature request, one directory above the repo root at `C:\Users\yousi\repos\Theta project\Reipients.txt`)

## Global Constraints

- **Do NOT assume same content = multiple recipients.** Seeing identical media/share content in two places is not evidence of a fan-out; only ship the feature if IG's client-visible data model contains an explicit, reliable signal (a recipient list, a recipient count, or an equivalent flag) that the *receiving* account can read.
- **No fake/heuristic implementation.** If the signal isn't reliably available, this plan stops at Task 4 (the findings report) — Tasks 5+ are not executed, and nothing gets wired into `InitializeHooks()`.
- Reuse the existing Zeus architecture and UI conventions — no new hooking framework, no new settings-storage mechanism. New toggles go in the existing `SubMenuViewController`/settings-dictionary pattern in `Source/UI/SettingsViewController.m` (see the `@"Messages"` section, e.g. line 180 `@"Keep Deleted Messages"` entry).
- Every hook install must be guarded the way the rest of `Source/Hooks/Messages/*.m` is guarded: `ZeusFirstClass`/`NullHookMessageIfPresent` for class/selector resolution, `@try/@catch` around KVC reads on Swift-backed objects.
- This is a **binary evidence** project (per `ZEUS_441_TO_444_REPORT.md` §B): every claim in the Task 4 report must cite a specific class name, selector name, or ivar/property found in the actual Instagram binary — not a guess from public API docs, which do not describe DM internals.

---

## Investigation background (already gathered, do not redo)

- `Include/InstagramHeaders.h` is a **hand-curated, partial** header (595 lines) containing only what existing Zeus features already hook. It has **no** class for a DM share/media message model (no `IGDirectXmaMediaShareItem`, `IGDirectReelShareItem`, `IGDirectMediaShareItem`, or similar) and **no** class for thread participants beyond what's read via KVC string keys.
- `Source/Hooks/Messages/MarkAsSeen.m` (`zeus_getParticipantsFromThreadObject`, line ~535) proves that a **thread's own participant list** (`users` / `participants` / `otherParticipants` / `recipients` / `threadUsers`) is readable via KVC on a thread-like object. That answers "who is in this conversation" for **group threads** — Instagram's own UI already surfaces this (group member list), so it is not the novel part of this feature and is **not sufficient** to answer the actual question, which is about a single shared item's fan-out across *separate* threads/recipients, most of which the receiving account has no visibility into by definition (you cannot see someone else's 1:1 thread with the sender).
- No Objective-C/Swift class dump of the Instagram binary is checked into this repo. `ZEUS_441_TO_444_REPORT.md` was produced by "static analysis of the Zeus source tree plus Objective-C runtime-metadata extraction ... from both stripped Instagram ARM64 Mach-O binaries" — the tooling used for that extraction is not committed under `scripts/` (only `scripts/assemble.py` and `scripts/extract-substrate-from-deb.py` exist, neither of which does class-dumping). The two Instagram `.ipa` files this plan needs are already present at:
  - `C:\Users\yousi\repos\Theta project\Instagram V441.0.0.ipa`
  - `C:\Users\yousi\repos\Theta project\Instagrav V444.0.0.ipa`

---

## Task 1: Extract the Instagram 444 binary and enumerate DM/share-related classes

**Files:**
- Create (scratch, not committed): a temp working directory for the unzipped IPA and class-dump output — keep this **outside** the repo (e.g. the session scratchpad), since it is multi-hundred-MB Mach-O + JSON, not source.
- No repo files modified in this task.

**Interfaces:**
- Produces: a text/JSON dump of every Objective-C class name, selector name, and (where possible) property/ivar type encoding in the Instagram 444 binary — this is the raw input Task 2 greps over.

- [ ] **Step 1: Unzip the IPA and locate the executable**

```bash
mkdir -p /tmp/ig444 && cd /tmp/ig444
unzip -q "C:\Users\yousi\repos\Theta project\Instagrav V444.0.0.ipa" -d payload
find payload -maxdepth 3 -name "Instagram" -type f
```
Expected: one file, `payload/Payload/Instagram.app/Instagram` (the Mach-O ARM64 binary IG hides its private classes in).

- [ ] **Step 2: Run class-dump (or equivalent) against the binary**

Use whichever of these is available in the environment that will do the actual RE work (this plan does not assume a Mac is available in this session — pick one):
- `class-dump -H -o ig444_headers/ payload/Payload/Instagram.app/Instagram` (classic class-dump, needs a fat/thin Mach-O it understands — IG binaries are arm64/arm64e, class-dump handles this natively on recent versions).
- `jtool2 --class-dump payload/Payload/Instagram.app/Instagram > ig444_classdump.txt` if class-dump chokes on the encryption/exports trie.
- A pure-Python Mach-O parser (e.g. `pip install machobjc` / `LIEF` + a small script that walks `__objc_classlist`, `__objc_data`, `__objc_methname`) if neither binary tool is available — this is the same category of extraction `ZEUS_441_TO_444_REPORT.md` describes doing ("class list, superclass graph, instance/class method tables with type encodings, and the full `__objc_methname` selector universe").

Expected output: either a directory of per-class `.h` files (class-dump) or one flat text dump — either is fine for Task 2's grep step.

- [ ] **Step 3: Sanity-check the dump**

```bash
grep -c "^@interface" ig444_headers/*.h 2>/dev/null || grep -c "@interface" ig444_classdump.txt
```
Expected: tens of thousands of classes (the 441→444 report found 44,434 Obj-C classes in the 444 binary — a successful dump should be in that ballpark, not a few hundred).

---

## Task 2: Search the dump for the DM share-message model and thread/recipient metadata

**Files:** none in the repo — this task greps the Task 1 output.

**Interfaces:**
- Consumes: the class dump from Task 1.
- Produces: a shortlist of candidate class names + selector/property names to hand to Task 3 for manual disassembly/confirmation.

- [ ] **Step 1: Find the shared-media message wrapper class(es)**

```bash
grep -rli "sharemessage\|mediashare\|xmamediashare\|reelshareitem\|storyshareitem\|directshareable" ig444_headers/ 2>/dev/null
```
Also try `grep -rli "IGDirectVisualMessage\b"` (already known to Zeus from `PrivateVideoGhost.m`'s use of `_initialVisualMessage`/`_visualMediaInfo`) and read that class's full interface — it's the most likely place a "sent to multiple" flag would live if it exists at all, since it's the object wrapping a shared post/reel inside a DM.

Record: every property/ivar name and type on the winning class(es). Zeta in particularly on anything named or shaped like: `recipientCount`, `recipients`, `recipientUsers`, `broadcastId`, `broadcast_id`, `sendCount`, `multiSend`, `multicastId`, `fanoutId`, `shareId` vs `itemId` (two different IDs on the same object is a strong signal — one identifying content, one identifying the send/broadcast event), `clientContext`.

- [ ] **Step 2: Find the thread/message update classes that carry this wrapper**

```bash
grep -rli "IGDirectThreadItem\|IGDirectMessageItem\|IGDirectItem\b" ig444_headers/ 2>/dev/null
```
Read the winning class's interface for a `itemType` / `item_type` style property and confirm which case (e.g. `media_share`, `reel_share`, `story_share`, `xma`) wraps the object found in Step 1. This confirms Step 1's class is actually reachable from a rendered DM message, not a dead/unused class.

- [ ] **Step 3: Check whether any recipient-count/list field is actually populated for the receiving account**

This cannot be answered from static class shape alone — a property can exist on the class and still always be `nil`/`0` for a receiver (e.g. because the field is sender-only and the server never serializes it into the receiver's copy of the message). Grep the dump for the JSON-mapping/parsing class for this item type (often named `...ResponseModel`, `...Parser`, or has `+ (instancetype)modelFromJSON:` style methods) and check whether the field found in Step 1 is actually assigned there, or whether it's declared but always defaulted.

Record for Task 4: for each candidate field, whether it is (a) present + populated by the parser, (b) present but never assigned by the parser (dead field), or (c) not found at all.

---

## Task 3: Runtime confirmation (only if Task 2 found a live candidate field)

If Task 2 found **no** candidate field in any state (a), skip this task and go straight to Task 4 with a negative result.

**Files:** none in the repo — this is a throwaway diagnostic, not a shipped hook. If you need a temporary build to test with, create it as `Source/Hooks/Debug/RecipientFieldProbe.m` and **delete it before Task 4's report is finalized** (or before any commit) — it must never ship.

**Interfaces:**
- Consumes: the class/selector names from Task 2.
- Produces: a confirmed answer to "is the field populated on-device for a real received DM."

- [ ] **Step 1: Write a temporary log-only hook**

```objc
// Source/Hooks/Debug/RecipientFieldProbe.m — TEMPORARY, do not register in InitializeHooks() for a real release
static void (*orig_probeConfigure)(id self, SEL _cmd, id viewModel, id specFactory, id launcher);
static void hook_probeConfigure(id self, SEL _cmd, id viewModel, id specFactory, id launcher) {
    orig_probeConfigure(self, _cmd, viewModel, specFactory, launcher);
    @try {
        id metadata = [(id<IGDirectMessageViewModelProtocol>)viewModel messageMetadata];
        id shareItem = [metadata valueForKey:@"<CANDIDATE_FIELD_PATH_FROM_TASK_2>"];
        NSLog(@"[ZuRecipientProbe] shareItem=%@ class=%@ desc=%@", shareItem, [shareItem class], [shareItem description]);
    } @catch (NSException *e) {
        NSLog(@"[ZuRecipientProbe] error: %@", e);
    }
}

void ZURegisterRecipientFieldProbeHooks(void) {
    Class messageCell = ZeusFirstClass(@[
        @"_TtC19IGDirectMessageCell19IGDirectMessageCell",
        @"IGDirectMessageCell"
    ]);
    NullHookMessageIfPresent(messageCell,
        @selector(configureWithViewModel:ringViewSpecFactory:launcherSet:),
        (void *)hook_probeConfigure, &orig_probeConfigure);
}
```
Replace `<CANDIDATE_FIELD_PATH_FROM_TASK_2>` with the actual key path found in Task 2 (this is the one placeholder in this plan that is *necessarily* unknown until Task 2 completes — the spec itself requires investigating before any code can be written here).

- [ ] **Step 2: Register the probe temporarily, build, install**

Add `ZURegisterRecipientFieldProbeHooks();` to `InitializeHooks()` in `Source/Runtime/ZUTweak.m` (next to `ZURegisterKeepDeletedMessagesHooks();`), then:
```bash
./build.sh sideload
```
Install `output/Instagram_patched.ipa` on a test device (or `./build.sh` + `make install` for jailbreak, per README).

- [ ] **Step 3: Generate the two real-world cases and compare logs**

- Case A: from a second test account, share a post/reel to *only* the account under test (1:1 DM).
- Case B: from that same second test account, share the *exact same* post/reel to the account under test *and* at least one other account, in the same share sheet action.
- Capture device console output (`idevicesyslog | grep ZuRecipientProbe` or Console.app) for both cases.

Expected: if the field is real and populated, Case B's log line differs from Case A's (non-zero/non-empty recipient info only in B). If the two cases log identically, the field is not a usable signal — treat as a negative result.

- [ ] **Step 4: Remove the probe**

```bash
git rm Source/Hooks/Debug/RecipientFieldProbe.m 2>/dev/null || rm Source/Hooks/Debug/RecipientFieldProbe.m
```
Remove the `ZURegisterRecipientFieldProbeHooks();` line from `Source/Runtime/ZUTweak.m`. This step is required regardless of outcome — the probe must not ship.

---

## Task 4: Write the findings report (decision gate)

**Files:**
- Create: `docs/superpowers/plans/2026-08-31-dm-recipient-visibility-findings.md`

**Interfaces:**
- Consumes: Task 1–3 results.
- Produces: the go/no-go decision for Tasks 5+, and the exact answer format Recipients.txt asked for.

- [ ] **Step 1: Write the report answering the five questions from `Reipients.txt` verbatim**

Structure (mirror `ZEUS_441_TO_444_REPORT.md`'s evidence-table style):
1. Which Instagram classes/methods/objects were found (name every class/property from Task 2, with the binary + version it was found in).
2. What metadata is actually available to the receiving account (state explicitly whether it's populated per Task 3, not just declared).
3. Whether one recipient can be reliably distinguished from multiple (a direct yes/no, with the evidence row it rests on).
4. The exact hook/data flow that would be used **if feasible** (class → selector → field path → UI insertion point), or "N/A — infeasible" if not.
5. Limitations / cases where the result could be wrong (e.g., group threads showing member lists already covers a related-but-different case; a share re-shared by the recipient elsewhere would not be caught; server-side field could be silently dropped in a future IG version the way `mediaCell` was in the 441→444 report's §A).

- [ ] **Step 2: Decide**

- If Task 3 (or Task 2, if no candidate existed) is negative: **stop here.** Do not create any files under `Source/Hooks/`. Tell the user the feature is not reliably implementable and why, per the spec's explicit instruction ("If it is NOT reliably possible, don't add a fake/heuristic implementation").
- If positive: proceed to Task 5.

---

## Task 5 (only if Task 4 is a "go"): Add the settings toggle

**Files:**
- Modify: `Source/UI/SettingsViewController.m` — add one entry to the `@"Messages"` array (around line 180–191).

**Interfaces:**
- Produces: `ENABLED(@"Recipient Visibility")` becomes a valid guard for Task 6's hook, and a user-facing toggle appears in Settings → Messages.

- [ ] **Step 1: Add the settings entry**

```objc
@{@"title": @"Recipient Visibility", @"detail": @"Show whether a shared post/reel was sent only to you or to multiple people.", @"info": @"Uses <FIELD NAME FROM TASK 4> to determine this. <Any caveats from Task 4 §5 go here verbatim.>"},
```
Insert this into the existing `@"Messages": @[ ... ]` array from `Source/UI/SettingsViewController.m` line 180, following the exact dictionary-literal style of its neighbors (see `@"Keep Deleted Messages"` on the line right above it for the format).

- [ ] **Step 2: Build and confirm the toggle renders**

```bash
./build.sh sideload
```
Install and open Settings → Messages in the app; confirm "Recipient Visibility" appears with the detail/info text and toggles on/off (this is Zeus's existing settings infra — no new plumbing needed, this step only confirms the dictionary entry is well-formed).

---

## Task 6 (only if Task 4 is a "go"): Implement the hook and UI badge

**Files:**
- Create: `Source/Hooks/Messages/RecipientVisibility.m`
- Modify: `Source/Runtime/ZUTweak.m` — register the new hook in `InitializeHooks()`.
- Modify: `Include/InstagramHeaders.h` — add the confirmed class interface(s) from Task 2/3 (e.g. the share-item class and whatever recipient field it exposes), following the existing style (see `IGDirectUIMessageMetadata` at line 66 for the minimal-declaration convention: only declare the properties Zeus actually reads).

**Interfaces:**
- Consumes: `ENABLED(@"Recipient Visibility")` from Task 5; the confirmed class/selector/field names from Task 4.
- Produces: a badge/label on shared-media DM message cells reading "Sent only to you" or "Sent to multiple people."

- [ ] **Step 1: Declare the confirmed header shape**

Add to `Include/InstagramHeaders.h`, using the real names found in Task 2 (example shape — replace every identifier with what was actually confirmed):

```objc
@interface <ConfirmedShareItemClass> : NSObject
@property (nonatomic, readonly) <ConfirmedFieldType> <confirmedFieldName>;
@end
```

- [ ] **Step 2: Implement the hook**

Follow the `hook_directMessageCell_configure` pattern from `Source/Hooks/Messages/KeepDeletedMessages.m` (line 190) exactly — same hook point (`configureWithViewModel:ringViewSpecFactory:launcherSet:` on the `IGDirectMessageCell`/`_TtC19IGDirectMessageCell19IGDirectMessageCell` pair via `ZeusFirstClass`), same container-resolution fallback chain (`contentViewForVisualMessageViewerPresentation` → `contentView` → `self`), same `@try/@catch` discipline around every KVC read:

```objc
static void (*orig_recipientVisConfigure)(id self, SEL _cmd, id viewModel, id specFactory, id launcher);
static void hook_recipientVisConfigure(id self, SEL _cmd, id viewModel, id specFactory, id launcher) {
    orig_recipientVisConfigure(self, _cmd, viewModel, specFactory, launcher);
    if (!ENABLED(@"Recipient Visibility")) return;
    if (![viewModel conformsToProtocol:@protocol(IGDirectMessageViewModelProtocol)]) return;

    @try {
        IGDirectUIMessageMetadata *metadata = [(id<IGDirectMessageViewModelProtocol>)viewModel messageMetadata];
        id shareItem = <path to the confirmed share-item object, from Task 2/3>;
        if (!shareItem) return;

        id recipientSignal = [shareItem valueForKey:@"<confirmedFieldName>"];
        if (!recipientSignal) return;

        BOOL sentToMultiple = <the actual comparison confirmed in Task 3 — e.g. recipient count > 1, or recipient array count > 1>;
        NSString *label = sentToMultiple ? @"Sent to multiple people" : @"Sent only to you";

        UIView *container = [self respondsToSelector:@selector(contentViewForVisualMessageViewerPresentation)]
            ? [self performSelector:@selector(contentViewForVisualMessageViewerPresentation)]
            : ([self respondsToSelector:@selector(contentView)] ? [self valueForKey:@"contentView"] : (UIView *)self);
        if (!container) return;

        for (UIView *sub in container.subviews) {
            if (sub.tag == 0x5A524543 /* 'ZREC' */) { ((UILabel *)sub).text = label; return; }
        }
        UILabel *badge = [[UILabel alloc] init];
        badge.tag = 0x5A524543;
        badge.font = [UIFont systemFontOfSize:11];
        badge.textColor = [UIColor secondaryLabelColor];
        badge.text = label;
        badge.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:badge];
        [NSLayoutConstraint activateConstraints:@[
            [badge.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-2],
            [badge.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-4],
        ]];
    } @catch (NSException *e) {
        NSLog(@"[Zeus] RecipientVisibility error: %@", e);
    }
}

void ZURegisterRecipientVisibilityHooks(void) {
    Class messageCell = ZeusFirstClass(@[
        @"_TtC19IGDirectMessageCell19IGDirectMessageCell",
        @"IGDirectMessageCell"
    ]);
    NullHookMessageIfPresent(messageCell,
        @selector(configureWithViewModel:ringViewSpecFactory:launcherSet:),
        (void *)hook_recipientVisConfigure, &orig_recipientVisConfigure);
}
```

- [ ] **Step 3: Register the hook**

In `Source/Runtime/ZUTweak.m`, add `ZURegisterRecipientVisibilityHooks();` to `InitializeHooks()`, next to `ZURegisterKeepDeletedMessagesHooks();` (both hook the same message cell selector, so keeping them adjacent makes the shared hook point obvious to the next reader).

- [ ] **Step 4: Build**

```bash
./build.sh sideload
```
Expected: build succeeds with no new warnings from `RecipientVisibility.m`.

- [ ] **Step 5: Commit**

```bash
git add Include/InstagramHeaders.h Source/Hooks/Messages/RecipientVisibility.m Source/Runtime/ZUTweak.m Source/UI/SettingsViewController.m docs/superpowers/plans/2026-08-31-dm-recipient-visibility-findings.md
git commit -m "feat: add DM recipient visibility indicator (sent to one vs. multiple)"
```

---

## Task 7 (only if Task 6 shipped): Manual on-device verification

Follows the existing project convention (`ZEUS_441_TO_444_REPORT.md` §J) of manual device testing in lieu of an automated suite.

**Files:** none.

- [ ] **Step 1:** Install the build from Task 6 Step 4 on a test device.
- [ ] **Step 2:** Repeat Task 3's Case A (share to one recipient only) — confirm the badge reads "Sent only to you."
- [ ] **Step 3:** Repeat Task 3's Case B (same content shared to 2+ recipients in one action) — confirm the badge reads "Sent to multiple people" on the test account's copy.
- [ ] **Step 4:** Open an unrelated existing DM share message received before this change — confirm no crash and a badge still renders (retroactive correctness), or confirm it's correctly absent if the underlying field wasn't populated for older messages.
- [ ] **Step 5:** Toggle "Recipient Visibility" off in Settings → confirm the badge disappears without restarting the app (or note if an app restart is required, and say so in the settings `"info"` text from Task 5).
- [ ] **Step 6:** Regression-check one adjacent feature that shares the same hook point — Keep Deleted Messages (Task's sibling hook on the same selector) — still colors deleted-message bubbles correctly with Recipient Visibility also enabled.

**Exit criterion:** badge text matches ground truth in both the single- and multi-recipient cases across at least 2 separate real share actions each; toggle fully disables the feature; no regression in Keep Deleted Messages.

---

## Self-Review Notes

- **Spec coverage:** All 5 numbered questions in `Reipients.txt` are answered by Task 4's report structure. The "search existing codebase first" instruction is satisfied by the Investigation Background section (already done, cites `MarkAsSeen.m` and `InstagramHeaders.h`). The "use existing hooking patterns" instruction is satisfied by Task 6 explicitly copying `KeepDeletedMessages.m`'s hook point and container-resolution chain. The "don't implement if not feasible" instruction is enforced as a hard stop at Task 4 Step 2.
- **Placeholder scan:** The only bracketed placeholders left (`<CANDIDATE_FIELD_PATH_FROM_TASK_2>`, `<ConfirmedShareItemClass>`, etc.) are ones the spec itself says cannot be filled in before investigation — every other step has concrete file paths, function names, and full code.
- **Type consistency:** `ZURegisterRecipientVisibilityHooks()` (Task 6) matches the `void ZURegisterXHooks(void)` signature convention used by every existing register function seen in `ZUTweak.m`'s `InitializeHooks()`. The hook signature `(id self, SEL _cmd, id viewModel, id specFactory, id launcher)` matches `hook_directMessageCell_configure` in `KeepDeletedMessages.m` exactly, since it hooks the identical selector.

---

Plan complete and saved to `docs/superpowers/plans/2026-08-31-dm-recipient-visibility.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
