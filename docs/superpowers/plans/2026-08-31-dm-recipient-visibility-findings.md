# DM Recipient Visibility — Findings (Task 4)

**Verdict: NOT reliably possible client-side. No feature implemented.** Per the spec's own instruction ("If it is NOT reliably possible, don't add a fake/heuristic implementation"), Tasks 5+ of the implementation plan were not executed — no settings toggle, no hook, nothing wired into `InitializeHooks()`.

## Method

Static string-level analysis of the actual Instagram 444.0.0 binary (`Instagram.app/Instagram`, 321.9 MB, arm64), extracted from the IPA at `C:\Users\yousi\repos\Theta project\Instagrav V444.0.0.ipa`. The binary is **not FairPlay-encrypted** (confirmed by finding plaintext occurrences of known classes like `IGFollowController`, `IGUser`, `IGDirectThread`), so its full Objective-C/Swift symbol and string table is readable. No class-dump tool was available in this environment (Windows, no Xcode/otool/class-dump/jtool2), so the investigation used direct byte-level pattern search across the whole binary rather than a structured class dump — this finds any class, property, or Swift-mangled symbol name containing a target substring, which is sufficient to answer "does anything like this exist anywhere in the binary," even without resolving full class layouts.

Searches run (see script in session scratchpad, not checked into the repo):
1. Every literal from Recipients.txt's own checklist: `recipient`, `recipientCount`, `broadcast`, `broadcastId`, `multiSend`, `multicast`, `fanout`, `sendCount`, `threadUsers`, `otherParticipants`.
2. The DM message/share item class family itself (`IGDirect*Share*`, `IGDirect*Message*`).
3. Cross-products: any string combining a share-type name (`ReelShare`/`PostShare`/`StoryShare`/`MediaShare`/`XMAMessage`) with recipient/broadcast/multi vocabulary.
4. All 405 `IGDirect*Recipient*` symbols in the binary (excluding the unrelated Broadcast Channel feature), reviewed for anything resembling a per-message recipient count or list exposed to a receiver.

## 1. Classes/methods/objects found

- **The actual DM share-item classes exist and were identified**: `IGDirectReelShare`, `IGDirectPostShare`, `IGDirectPostSundialShare`, `IGDirectStoryShare`, `IGDirectMediaPile`, `IGDirectLocationShare`, `IGDirectXMAMessage`, `IGDirectAnimatedMedia`, `IGDirectPhoto`, `IGDirectVideo`, `IGDirectVisualMessage` (the ephemeral photo/video type Zeus already hooks in `PrivateVideoGhost.m`) — found clustered together in the binary's class list, confirming this is the real family of "what kind of thing is in this DM message" types.
- **No property, method, or field on any of them mentions recipients, a count, or a broadcast/fan-out identifier.** Zero hits combining a share-type class name with recipient/broadcast/count/multi vocabulary in a single symbol.
- **`recipientCount`** (3 occurrences): part of an unrelated analytics skip-reason log string (`"result=skipped reason=recipientCount"`), not a message field.
- **`RecipientCount`** (7 occurrences): a localization template string for a group-moderator-selection UI (`"{FBTParam|selectedRecipientCount} people to be moderators"`) — completely unrelated to DM sharing.
- **`broadcastId`/`BroadcastId`/`broadcast_id`** (154 occurrences combined): all Instagram **Live** broadcast-session infrastructure (`...LevelAndJidFromPk`, `IBroadcastIdProvider`) — Instagram's livestreaming feature, unrelated to DM message sharing.
- **`IGDirectBroadcastChannel*`** (a large family, ~100+ symbols): Instagram's "Broadcast Channel" product (one-to-many creator announcement channels) — a real, distinct Instagram feature, but structurally unrelated to "did my DM get sent to other people too" (a channel is an explicit many-subscriber object both sides already see).
- **405 `IGDirect*Recipient*` symbols reviewed**: essentially all of them belong to the **share-sheet / recipient-picker** subsystem — `IGDirectRecipientPickerViewController`, `IGDirectRecipientListViewController`, `IGDirectRankedRecipientsQuery` (a GraphQL query for populating the picker's autocomplete list), `IGDirectShareRecipient` (the *sender's* model of a person they could pick), `IGDirectSuggestedRecipient`, etc. This is exclusively **compose-time, sender-side** infrastructure for choosing who to send to — none of it round-trips into the receiver's copy of a sent message.

## 2. What metadata is actually available to the receiving account

Nothing beyond what Zeus already reads today: the message's own content/type (photo, video, reel share, post share, text, etc.) and, for **group threads**, the full participant list (already readable via KVC — see `Source/Hooks/Messages/MarkAsSeen.m`'s `zeus_getParticipantsFromThreadObject`). That answers "who is in *this* conversation," which Instagram's own UI already shows for groups. It says nothing about whether the *same* shared item also went to someone else's separate 1:1 thread with the sender.

## 3. Can one recipient be reliably distinguished from multiple?

**No.** Architecturally this matches the negative result: when a user shares a post/reel to several people via the share sheet in a 1:1 context, Instagram fans that out into **separate, independent per-recipient threads** — there is no shared "broadcast envelope" object that both recipients' clients receive a copy of. Each recipient only ever sees their own thread and their own copy of the message. Whether the *same* content was also sent to someone else is inherently information that only exists on the **sender's** account (which of their own threads they posted into) — the binary evidence is consistent with Instagram never serializing that fact into any individual recipient's copy of the message, which would make sense as a deliberate privacy boundary, not an oversight.

The one case where a recipient *can* see other recipients — a group thread — is already fully visible through Instagram's own native UI (member list), and is a different question from "was this specific shared item also sent elsewhere."

## 4. Hook/data flow

N/A — infeasible. There is no class, selector, or field to hook.

## 5. What would need to change to make this possible

- Instagram would need to add a field to the DM message/share JSON payload (e.g. a `recipient_count` or `broadcast_id`) that is actually populated on the **receiving** side, not just used internally for the sender's fan-out job. Nothing in the 444.0.0 binary suggests this exists or is planned (no dead/unused field of this shape was found either — it's not a "removed in this version" situation like the Follow Confirmation selector; it appears to have never existed).
- Absent that, the only way to get this information would be **server-side correlation Zeus has no access to** (e.g. Instagram's own backend comparing fan-out jobs), which is out of scope for a client-side tweak by definition.
- If a future Instagram version introduces something like WhatsApp's "Forwarded many times" indicator (a counter embedded in the message itself, incremented and transmitted with the message data), that would change this answer — worth re-running this same string search against future binaries if that ships.

## Conclusion

Per the spec: this is being reported back rather than implemented with a heuristic. Recommendation: do not build a "same media appears in multiple threads" heuristic either — the spec explicitly warned against exactly that failure mode, and it would be actively misleading (e.g. a popular meme reposted independently by two different friends would falsely read as "sent to multiple people").
