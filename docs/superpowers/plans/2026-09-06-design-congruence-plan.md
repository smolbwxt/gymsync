# Design congruence — every screen against the written language

Rules: `docs/superpowers/specs/2026-09-05-design-language.md`.
Findings: `docs/superpowers/plans/2026-09-05-page-audit.md` (batches B1–B11).
Evidence with anchors: `.superpowers/sdd/2026-09-04-investigations/design-love-sweep.md`,
`visual-audit-A.md`, `visual-audit-B.md` (same directory).

## Why

The first seeded CI screenshot artifact (run 33991668722, 71 captures, Onyx + sky) is the first time
the app has been looked at whole, in its own palette, against written rules. 48 of 71 screens deviate.
Nothing here is a regression: most of it is one missing token (green), one inverted component (the talk
pill), and accent spent on escape hatches and readouts across twenty screens. This plan lands the
audit's fix batches, one commit per task, each proven by a named CI capture.

**Excluded by instruction:** B5 (Home) — handled by the Home v2/v3 catalog work. B8's button-caps sweep
— dropped by owner ruling.

**Owner rulings that bind this plan (2026-09-05):**
1. Sign-in keeps its full-bleed accent. `SignInView` is not touched by any task here.
2. Heart-rate zone ramp is data colour, exempt from green/red like plate colours. `GSHeartRatePill`
   and the `heart-rate-pill` capture are not touched.
3. Buttons are not required to be caps; existing labels stay. No task renames a button label except
   where the label states a status instead of an act (paywall "Coming soon", T1.6).

## Global constraints (binding on every task)

- **Swift compiles only in CI.** No implementer can build locally. Read every file you touch in full
  before editing, mirror the idiom already in that file, keep each change small, prefer additive code.
  If a change would need a new type to compile, say so in the commit body.
- **One commit per task.** Trailer on every commit, exactly:
  ```
  Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01SMNTPsgf3mtFSr4awky8ni
  ```
- **Four-part contract for any new catalog id, in ONE commit:** `CatalogScreen` case + builder in
  `GymSyncApp/GymSync/App/CatalogHostView.swift`; the documented-id list AND count assertion in
  `GymSyncApp/GymSyncTests/CatalogScreenTests.swift` (:14–60); a `ScreenshotTests.testCatalog…`
  capture in `GymSyncApp/GymSyncUITests/ScreenshotTests.swift` (:257–320); a `docs/design/frame-map.json`
  entry. **No task in this plan adds a catalog id** — every fix is proven by an existing capture, and
  the two gaps are named in "What this plan does not decide".
- **No product-timing constants change.** `brandMoment = 1300 ms`, the 2.5 s launch cap, the 350 ms
  fade, `PTTDockRow.holdThreshold = 0.35`, `GSExpandingRing`'s 1.4 s / 0.7 s stagger, and every
  rest/turn timer stay exactly as they are.
- **No behaviour changes outside the visual/copy scope.** Do not change navigation destinations,
  repository calls, gesture state machines, entitlement gates, or persistence. The one deliberate
  exception is T8.4 (a DEBUG-only fixture guard) and T9.2 (a copy-only DB trigger body).
- **Verification is the CI screenshot artifact.** Each task names the capture ids it must visibly
  change. Push, let `.github/workflows/ios.yml`'s `screenshots` job run, download `app-screenshots`,
  and compare the named ids against the 33991668722 baseline. A task whose capture does not change is
  not done. Tasks with no capture (named explicitly) are proven by code review only.
- **Do not rename an existing `CatalogScreen` raw value.** `ScreenshotTests` and `CatalogScreenTests`
  key off the exact strings.

## Ordering and dependencies

1. **B4 and B7 first** — both are pure component work with no product decisions.
   **B7's `Color.gsSuccess` + `GSTagStyle.success` (T7.1) MUST land before T7.2–T7.6, before B1's
   T1.9 (`FEATURED`/`Active` tags share `GSTag`), and before B2's tag work.** Anything that
   recolours a tag depends on the token existing.
2. **B1 next.** Inside B1: **T1.2 (`stepperCell`) must land before B8's T8.2**, which passes a new
   label through the same function. **T1.3 (`GSInitialsAvatar` default fill) must land before T1.4**,
   or the shared leaderboard row will re-introduce accent tiles.
3. **B2 and B9 ride with B1** — same "colour discipline" review pass, independent files.
4. **B3 after B1/B2.** B3 changes surfaces on screens B1/B2 recolour (campaign detail, paywall,
   stat tiles). Landing colour first keeps each diff single-purpose.
5. **B8 after B1** (T8.2 depends on T1.2) and **after B3's T3.8** for the stat-tile screens.
6. **B11, B6, B10 are independent** and may land any time after B7.
7. **Test-fidelity last but before the next audit** — T-F.1/T-F.2 unblock captures that several
   B3 tasks currently cannot prove.
8. B5 (Home) lands separately. **T2.4 (Stats streak gold) must not be merged into the Home work** —
   it is the Stats tab, a different file.

---

# B4 — The talk control (component; 4 captures)

Today the control is two objects: an accent-outlined mic circle plus a separate bordered status bar,
sentence-case copy, no waveform, and **while transmitting the circle goes accent while the pill stays
neutral — the inverse of rule 6.** All four voice captures agree. One component owns all of it:
`PTTDockRow`, `GymSyncApp/GymSync/DesignSystem/GSComponents.swift:1360–1810`.

### T4.1 — Rebuild `PTTDockRow`'s bar as one neutral raised pill · **M**

File: `GymSyncApp/GymSync/DesignSystem/GSComponents.swift`.

- **`idleBar` (:1677–1681).** Replace the `Text("Tap to talk · hold to talk live")` body with:
  ```swift
  HStack(spacing: 8) {
      Text("HOLD TO TALK")
          .font(GSFont.bold(13, relativeTo: .body))
          .tracking(1.1)
          .foregroundStyle(theme.text)
      GSTalkingBars(color: theme.accent, barWidth: 3, maxHeight: 14)
  }
  ```
  `GSTalkingBars` is the existing waveform (`GSComponents.swift:1156–1198`) — reuse it, do not draw a
  second waveform type. This is the "small accent waveform at rest".
- **`openBar` (:1685–1696) and `holdingBar` (:1704–1719).** Both become one label:
  `Text("TALKING · RELEASE TO STOP")`, `GSFont.bold(13, relativeTo: .body)`, `.tracking(1.1)`,
  `.foregroundStyle(theme.bg)` (ink on the accent face). Drop `openBar`'s sub-caption
  "Tap toggles · press-and-hold for walkie-talkie" and `holdingBar`'s live elapsed timer — the rule
  specifies one line. **Keep both computed properties as separate symbols** so `interactiveRow`'s
  branch structure at :1636–1644 is unchanged (view identity law, see the doc comment at :1585–1601).
- **`micAndBar` (:1572–1583).** The bar's chrome becomes the pill:
  ```swift
  bar()
      .frame(maxWidth: .infinity, minHeight: 44)
      .background(RoundedRectangle(cornerRadius: 999)
          .fill(isTransmitting ? theme.accent : theme.raised3DFace))
      .padding(.bottom, 5)
      .background(RoundedRectangle(cornerRadius: 999)
          .fill(isTransmitting ? theme.accent : theme.raised3DLip))
  ```
  Delete the `theme.surface` fill and the `theme.divider` stroke overlay. Radius 999 = the chips
  radius from rule 1; lip 5 pt = the tile lip.
- **`interactiveMicCore` (:1608–1630) and `micAndBar`'s `mic()` slot.** Delete the mic circle from
  the NON-compact path only: `interactiveRow` (:1632–1646) renders `micAndBar(mic: { EmptyView() }, …)`
  so the pill is the whole control. **`compactMic` (:1490–1511) keeps `interactiveMicCore` verbatim** —
  the sound-rail call site (`GroupSessionLiveView.swift:1836`, `compact: true`) has no room for a pill.
  **Do not delete `interactiveMicCore`, `GSExpandingRing`, `pressGesture`, or any `@State` on the type.**
  The gesture must still be attached in the non-compact path: move `.contentShape(Rectangle())` and
  `.modifier(pressGesture)` onto the pill so the press behaviour is identical.
- **`transmitHero` (:1530–1556).** Delete the call site at :1464–1466 and the property. The pill now
  carries the transmitting state; the hero was the second object the rule forbids.
- **`connectingBar` (:1721–1730), `unavailableBar` (:1732–1736), `deniedRow` (:1740+)** keep their
  current copy and shape and now sit inside the same pill chrome.

Do not change: `holdThreshold`, `pressGeneration`, `handlePressBegan/handleHoldThresholdCrossed/
handleRelease`, `isHeldTransmitOwnedByThisPress`, or any `VoiceRoomService` call.

**Proves:** `app-voice-idle` (one pill, `HOLD TO TALK`, accent waveform, no circle),
`app-voice-transmitting` (solid accent pill, `TALKING · RELEASE TO STOP`, no hero),
`app-voice-connecting`, `app-voice-mic-denied` (unchanged copy, pill chrome).

### T4.2 — Re-skin the voice coach mark on the raised face · **S**

File: `GymSyncApp/GymSync/DesignSystem/GSComponents.swift`, `GSVoiceCoachMark` (:1945–1988).

The popover is a white slab on the Onyx app: `.background(theme.text)` (:1970) with `theme.bg` ink
(:1954, :1957) and a `theme.bg`-filled "Got it" button (:1964).

- `.background(theme.text)` → `.gs3DCard(cornerRadius: GSMetrics.radiusSm)` (drop the `.cornerRadius`
  at :1971 — the modifier clips).
- Title (:1954) `theme.bg` → `theme.text`. Body (:1957) `theme.bg.opacity(0.85)` → `theme.neutral500`.
- "Got it" (:1958–1966): label `theme.text` → `theme.bg`, `.background(theme.bg)` →
  `.buttonStyle(.gs3D(face: theme.accent, cornerRadius: GSMetrics.radiusSm, lipHeight: 4))`; delete
  the manual `.background` and `.buttonStyle(.plain)`.
- Pointer `Path` (:1977–1985): `.fill(theme.text)` → `.fill(theme.raised3DFace)`.

**Proves:** `app-voice-coach-mark` (dark popover, app type).

### T4.3 — Voice mixer: delete the dead toggles, quiet the readouts · **S**

File: `GymSyncApp/GymSync/DesignSystem/GSComponents.swift`, `GSVoiceMixerSheet` (:2012–…).

- **Delete** the whole toggle block, :2062–2091 (`Noise suppression`, `Hear my own voice`), and the
  two `@State` vars at :2022–2023. They are `.disabled(true)` "Coming soon" chrome backed by nothing.
  Update the type doc comment (:1990–2011) to say the toggles were removed, and remove the
  `voice-mixer-sheet` toggle note from `docs/design/accepted-deviations.json` in the same commit.
- Mic-level meter (:2040–2047): `.fill(i < 7 ? theme.accent : theme.surface)` →
  `.fill(i < 7 ? theme.neutral700 : theme.surface)`. It is a readout, not an action.
- The per-participant volume sliders and mute buttons in `mixerRow` (:2112+): any `theme.accent` used
  as a track/handle fill → `theme.neutral700`; accent stays only on the ACTIVE mute state.

**Proves:** `app-voice-mixer-sheet` (no "Coming soon" rows; neutral meter and sliders).

### T4.4 — `Voice unavailable` says what happened and how to fix it · **S**

File: `GymSyncApp/GymSync/DesignSystem/GSComponents.swift`, `unavailableBar` (:1732–1736).

Its sibling `deniedRow` (:1746–1757) is the rule-9 exemplar: "Mic access off — turn on in Settings"
with a deep-link arrow. Match its shape:

```swift
private var unavailableBar: some View {
    HStack(spacing: 10) {
        Image(systemName: "mic.slash")
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(theme.neutral500)
        Text("Voice is offline — check your connection")
            .font(GSFont.bold(13, relativeTo: .body))
            .foregroundStyle(theme.text)
        Spacer(minLength: 0)
        Text("RETRY")
            .font(GSFont.bold(11, relativeTo: .caption))
            .tracking(1.1)
            .foregroundStyle(theme.accent700)
    }
    .padding(.horizontal, 12)
}
```
Copy verbatim: `Voice is offline — check your connection` / `RETRY`. The retry ACTION already exists on
`GSVoiceUnavailableBanner.retry` (:1241) which the caller shows above the dock — this is the matching
label; do not wire a second retry path in this task.

**Proves:** `app-voice-unavailable`.

---

# B7 — Green means done (token + 6 screens)

Root cause, confirmed in the sweep and the pixels: `GSTag` has `.accent`/`.neutral`/`.outline` only
(`GSComponents.swift:194–198`), so every "completed / live / applied / present" state falls back to
accent, and the two files that do reach for green use raw `Color.green` instead of the canonical
`0x2FA45C`. **T7.1 lands first; everything else depends on it.**

### T7.1 — One green token, one tag style · **S**

Files: `GymSyncApp/GymSync/DesignSystem/GSAccent.swift` (:63–74), `GymSyncApp/GymSync/DesignSystem/GSComponents.swift` (:194–241).

- In `GSAccent.swift`'s existing `public extension Color` block, next to `gsHex`:
  ```swift
  /// Green = done or present (design language §2). One hex on every palette —
  /// like plate colours this is data colour, not a themed accent token.
  static let gsSuccess = Color.gsHex(0x2FA45C)
  /// 12% wash of `gsSuccess`, for tag/row fills.
  static let gsSuccessSoft = Color.gsHex(0x2FA45C, 0.12)
  ```
  The hex is the one `CrewRoomView.swift:47` and `GSBarLoader.swift:188,199` already use.
- In `GSComponents.swift`, add `case success` to `GSTagStyle` (:194–198) with a comment
  `// gsSuccessSoft fill, gsSuccess text — done / live / present`, and add the two branches to
  `foregroundColor` (:226–232, `return .gsSuccess`) and `backgroundColor` (:234–240,
  `return .gsSuccessSoft`).

Do not add a `success` field to `GSTheme` — it has five palette constructors and green is
palette-independent by ruling 2's logic.

**Proves:** nothing on its own (token commit). Land it, then T7.2–T7.6.

### T7.2 — Retire the three raw `Color.green` sites · **S**

- `GymSyncApp/GymSync/Features/Sessions/ProposalCardView.swift:118` `Color.green` → `.gsSuccess`;
  `:121` `Color.green.opacity(0.12)` → `.gsSuccessSoft`.
- Same file, `rowBackground` (:160–166): `case .approved: theme.accent100` → `.gsSuccessSoft`.
- `GymSyncApp/GymSync/Features/Sessions/LobbyView.swift:980` — presence dot
  `presenceSet.contains(…) ? Color.green : theme.neutral400` → `… ? .gsSuccess : theme.neutral400`.

**Proves:** no current capture (`app-lobby` lands on the crew room today; fixed by T-F.1). Code review
only this round; re-verify on `app-lobby` after T-F.1.

### T7.3 — "COMPLETED" and "LIVE" go green · **S**

- `GymSyncApp/GymSync/Features/Coach/ProgramLedgerView.swift:214–215`:
  `.foregroundStyle(enrollment.endedReason == "completed" ? theme.accent : theme.neutral500)` →
  `… ? .gsSuccess : theme.neutral500`.
- `GymSyncApp/GymSync/Features/Coach/CoachRulesView.swift:124`:
  `.foregroundStyle(rule.appliedAt != nil ? theme.accent : theme.neutral500)` →
  `… ? .gsSuccess : theme.neutral500`.

**Proves:** no capture (neither screen has a catalog id). Code review only — listed in
"What this plan does not decide" as a capture gap.

### T7.4 — `Active` tags go green · **S** (depends on T7.1)

- `GymSyncApp/GymSync/Features/Library/PlanQueueView.swift:93–94`:
  `style: entry.status == "active" ? .accent : .neutral` → `… ? .success : .neutral`.
- `GymSyncApp/GymSync/Features/Library/CampaignDetailView.swift:170–172` `windowStateTagStyle`:
  `campaign.windowState() == .active ? .accent : .neutral` → `… ? .success : .neutral`.
- `GymSyncApp/GymSync/Features/Library/CampaignsTabView.swift:96` passes `trailing: "Active"` into
  `campaignRow`; that string renders at `:266–268` in `theme.accent700`. Change `campaignRow`'s
  signature to `campaignRow(_ campaign: Campaign, trailing: String, trailingIsActive: Bool = false)`
  and colour the trailing `Text` `trailingIsActive ? .gsSuccess : theme.neutral500`. Pass
  `trailingIsActive: true` at :96 only; :112 (`countdownText`) and :131 (`"Ended"`) stay muted.
  (The muted half of this is also B1's meta-line rule — do both here, one diff.)
- `GymSyncApp/GymSync/Features/Library/CampaignDetailView.swift:273` `GSTag(text: "Completed", style: .accent)`
  → `.success`. Delete the stale trailing comment "accent tag alone signals success".

**Proves:** `app-campaigns-tab`, `app-program-active`, `app-campaign-detail-joined`,
`app-campaign-detail-unjoined`.

### T7.5 — The connected toast is presence, not an action · **S**

File: `GymSyncApp/GymSync/DesignSystem/GSComponents.swift`, `GSVoiceConnectedToast` (:1905–1933).

Rebuild as a neutral raised strip with a green check — the rule's "green means present":
- `.background(theme.accent)` (:1929) + `.cornerRadius(GSMetrics.radiusSm)` (:1930) →
  `.gs3DCard(cornerRadius: GSMetrics.radiusSm, lipHeight: 5)`.
- Checkmark (:1911–1913) `theme.bg` → `.gsSuccess`.
- "Voice connected" (:1918) `theme.bg` → `theme.text`; the group line (:1922)
  `theme.bg.opacity(0.9)` → `theme.neutral500`.
- Keep the `.shadow` at :1931.

**Proves:** `app-voice-connected-toast`.

### T7.6 — Presence and the success badge · **S**

- `GymSyncApp/GymSync/Features/Social/VenueHubViews.swift`, "Who's here" rows (:540–550): add a
  presence dot ahead of each name, matching `LobbyView`'s shape:
  ```swift
  Circle().fill(.gsSuccess).frame(width: 9, height: 9)
  ```
  inserted as the first element of the `HStack(spacing: 10)` at :541.
- `GymSyncApp/GymSync/Features/Onboarding/WelcomeView.swift:87–94` — the done badge is
  `Rectangle().fill(theme.accent)` with a `theme.bg` checkmark. `theme.accent` → `.gsSuccess`.
  *(Audit-A finding, same token, same rule; not enumerated in B7's screen list — flag it in the
  commit body so the reviewer can reject it cheaply if the owner disagrees.)*
- **Verified, no change:** `SocialTabView.swift:430–434`'s accent dot is the **unread** badge, not a
  presence dot ("badges point, they do not shout" — accent is legal there). The audit read it as
  presence. Record this in the commit body. The real crew presence signal does not exist yet — see
  "What this plan does not decide".

**Proves:** `app-venue-hub`, `app-onboarding-done`.

---

# B1 — Accent discipline (≈20 screens)

Accent is spent on: the one primary action per screen, an invitation line, the current item in a
pager or turn strip, the talk pill while transmitting. Nothing else. **A page never has two accent
buttons.**

### T1.1 — Take the accent off every escape hatch · **S**

Six toolbars, one substitution each: `.foregroundStyle(theme.accent)` → `.foregroundStyle(theme.neutral700)`.
`ScheduleSessionView.swift:190–192` is the in-repo precedent (its Cancel is already `neutral700`).

- `GymSyncApp/GymSync/Features/Stats/BodyWeightLogSheet.swift:65–66` — Cancel.
- `GymSyncApp/GymSync/Features/You/DeleteAccountSheet.swift:64–65` — Cancel.
- `GymSyncApp/GymSync/Features/Social/CreateGroupView.swift:159–160` — Cancel.
- `GymSyncApp/GymSync/Features/Moderation/ReportSheet.swift:52–53` — the `didSubmit ? "Done" : "Cancel"`
  button. **Nuance:** after submit, "Done" IS the screen's only act — keep it accent when `didSubmit`
  is true: `.foregroundStyle(didSubmit ? theme.accent : theme.neutral700)`.
- `GymSyncApp/GymSync/Features/Onboarding/HomeGymSetupView.swift:304–306` — the Skip/Cancel button.
  Its label styling is inline; set the `Text`'s `.foregroundStyle(theme.neutral700)` and remove any
  accent from the surrounding button style. Do not touch the `Set Home Gym` primary.
- `GymSyncApp/GymSync/Features/Onboarding/PushPrimingView.swift:273–279` — "Not now" already uses
  `GSGhostButtonStyle`; verify that style renders muted and, if it renders accent, add
  `.foregroundStyle(theme.neutral700)` on the `Text` at :276. Also `benefitRow` (:190–199): the three
  checkmarks at `:194` `theme.accent700` → `theme.neutral700`, and the bell badge at `:156`
  `Rectangle().fill(theme.accent)` → `.fill(theme.raised3DFace)` with the glyph (:159)
  `theme.bg` → `theme.text` — leaving "Turn on notifications" as the one accent thing.

**Proves:** `app-body-weight-log`, `app-delete-account`, `app-create-group`, `app-report-sheet`,
`app-onboarding-homegym`, `app-onboarding-homegym-searching`, `app-onboarding-push-priming`,
`app-onboarding-push-denied`.

### T1.2 — `stepperCell`: one component heals three entry surfaces · **S**

File: `GymSyncApp/GymSync/Features/Workout/LogSetSheet.swift`, free function `stepperCell` (:344–399).

Call sites healed: `LogSetSheet.swift:107` (Reps) and `:118` (Weight),
`Stats/BodyWeightLogSheet.swift:37`, `Sessions/GroupSessionLiveView.swift:3608`.

- **In the component:** `:387` the `+` glyph `theme.accent` → `theme.neutral700` (the `−` at :367 is
  already neutral).
- **In the component:** make the label the app's caps kicker (rule 3), replacing :355–357:
  ```swift
  Text(label.uppercased())
      .font(GSFont.bold(11, relativeTo: .caption))
      .tracking(1.1)
      .foregroundStyle(theme.neutral500)
      .lineLimit(1)
      .minimumScaleFactor(0.75)
  ```
  Leave `.accessibilityLabel(label)` at :382 and :371/:391 reading the un-uppercased `label`.
- **At the three call sites:** `borderColor: theme.accent` → `theme.divider`;
  `valueColor: theme.accent700` → `theme.text`. (`LogSetSheet.swift:124–125`,
  `BodyWeightLogSheet.swift:41–42`, and the matching pair in `GroupSessionLiveView.swift:3608`'s call.)
  The Reps cell at `LogSetSheet.swift:111–112` already passes `theme.divider`/`theme.text` — match it.

**Proves:** `app-body-weight-log` (flat neutral field, caps kicker, neutral steppers),
`app-plate-math` (same). **Must land before T8.2.**

### T1.3 — `GSInitialsAvatar` stops defaulting to accent · **S**

File: `GymSyncApp/GymSync/Features/Social/SocialTabView.swift`, `GSInitialsAvatar` (:601–657).

`:655` `.background(fill ?? theme.accent)` → `.background(fill ?? theme.neutral400)`, and
`:653` `.foregroundStyle(ink ?? theme.bg)` → `.foregroundStyle(ink ?? theme.text)`.

One line heals every "solid accent avatar square" the audit found: Top Lifters (5 tiles), the pump
feed post (2), campaign detail (3), the venue hub's who's-here rows, blocked users, friends. The
group rows at `SocialTabView.swift:418–424` pass an explicit `fill:`/`ink:` (`GSGroupColor`) and are
unaffected — see "What this plan does not decide" about that palette.

Update the doc comment at :605–609 to say the default is now neutral and `fill:` is the opt-in.

**Proves:** `app-top-lifters`, `app-pump-feed-post`, `app-campaign-detail-joined`, `app-venue-hub`,
`app-blocked-users`, `app-friends`. **Must land before T1.4.**

### T1.4 — One shared leaderboard row instead of six copies · **L**

Six independent implementations invented the same non-compliant decoration (rank #1 accent, accent
avatar tile):

| File | Function | Lines |
|---|---|---|
| `Features/Library/TopLiftersView.swift` | `leaderboardRow(rank:profile:)` | 87–132 |
| `Features/Library/CampaignDetailView.swift` | `leaderboardRow(rank:row:)` | 310–338 |
| `Features/Library/DiscoverWorkoutDetailView.swift` | `leaderboardRow(rank:entry:)` | 562–… |
| `Features/Sessions/GroupRecapView.swift` | `leaderboardRow(rank:row:)` | 363–406 |
| `Features/Sessions/CompletedSessionView.swift` | `participantRow(rank:stat:)` | 309–… |
| `Features/Sessions/SessionRecapView.swift` | `participantRow(rank:stat:)` | 342–… |

Add ONE component to `GymSyncApp/GymSync/DesignSystem/GSComponents.swift` (after `GSStatTile`, so it
sits with the other shared row atoms):

```swift
/// The one leaderboard row. Rank is never accent (design language §2: accent is
/// the primary action, an invitation, the current pager item, the live talk pill —
/// a rank number is none of those). "You" is marked by the neutral tint the recap
/// screens already established, never by colour on the number.
public struct GSLeaderboardRow<Trailing: View>: View {
    let rank: Int
    let name: String
    let avatarURL: URL?
    let subtitle: String?
    let isYou: Bool
    @ViewBuilder let trailing: () -> Trailing
    // rank:   GSFont.heading(15), theme.neutral700 for EVERY rank
    // avatar: GSInitialsAvatar(name:avatarURL:size: 32)   // neutral after T1.3
    // name:   GSFont.bold(13), theme.text, lineLimit(1)
    // sub:    GSFont.body(11), theme.neutral500
    // row:    .padding(.horizontal, 16).padding(.vertical, 10)
    //         .background(isYou ? theme.neutral400.opacity(0.2) : Color.clear)
}
```
`neutral400.opacity(0.2)` is the token `GroupRecapView.swift:405` and `TopLiftersView.swift:131`
already use and document as the cross-screen "which row is me" precedent.

Then replace each of the six bodies with a `GSLeaderboardRow` call, moving each screen's own trailing
content into the `trailing:` closure:
- **TopLifters**: trailing = the lifetime-volume `Text` (keep `theme.text`) over the weekly line —
  **`:121` `theme.accent` → `theme.neutral500`** (all five rows today are accent).
- **CampaignDetail**: trailing = `EmptyView()`; **delete `:335–337`'s `theme.accent100` background and
  the conditional corner radius** — `isYou` now supplies the neutral tint.
- **DiscoverWorkoutDetail**: trailing = its metric `Text`.
- **GroupRecap**: trailing = the existing kudos `GSTag` (kudos emoji are content — keep them).
- **CompletedSession / SessionRecap**: trailing = the per-participant stat block; their local
  initials `ZStack` (with `rank == 1 ? theme.accent : theme.neutral400`) is deleted in favour of
  `GSInitialsAvatar`.

**Proves:** `app-top-lifters` (no accent rank, no accent readouts, no accent tiles),
`app-campaign-detail-joined`, `app-discover-detail`, `app-group-recap`.

### T1.5 — Metadata lines go muted · **S**

Six accent text runs with no accent action on screen:
- `GymSyncApp/GymSync/Features/Library/ProgramViews.swift:118–120` — `ProgramTemplateCard`'s
  `"\(weeks) weeks · \(sessionsPerWeek) sessions/wk"` `theme.accent700` → `theme.neutral500`.
- Same file `:46–48` — `ProgramCard`'s "Complete — see your results" `theme.accent700` → `.gsSuccess`
  (it is a done state; depends on T7.1).
- Same file `:50–53` — "Week \(week) of \(weeks)" `theme.accent700` → `theme.neutral500`.
- Same file `:603–605` — `ProgramTemplateDetailView.aboutSection`'s
  `"\(weeks) weeks · \(sessionsPerWeek) sessions/wk"` `theme.accent700` → `theme.neutral500`.
- Same file `:692–694` — `exercisePickRow`'s `"Choose…"`
  `selection == nil ? theme.accent700 : theme.text` → `theme.neutral700 : theme.text`. The chevron at
  :695–697 already signals tappability.
- `CampaignsTabView.swift:266–268` — handled in T7.4; if T7.4 has not landed, do it here instead.

**Proves:** `app-campaigns-tab`, `app-program-active`, `app-program-template-detail`.

### T1.6 — Paywall: one accent, and a status stops pretending to be a button · **S**

File: `GymSyncApp/GymSync/Features/You/PaywallView.swift`.

- `featureRow` (:125–142): the title at `:135`
  `highlight == feature ? theme.accent700 : theme.text` → `theme.text` (unconditional). Keep the
  highlight legible by moving it to the glyph instead — `:130` `.foregroundStyle(theme.accent)` →
  `.foregroundStyle(highlight == feature ? theme.accent : theme.neutral500)`. Net: four accent glyphs
  and one accent title become **one** accent glyph.
- "Coming soon" (:67–76): replace the whole disabled `Button` with a line of copy —
  ```swift
  Text("Nothing to buy yet — Pro opens when the store does.")
      .font(GSFont.body(13, relativeTo: .subheadline))
      .foregroundStyle(theme.neutral500)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 12)
  ```
  Copy verbatim. Keep the `store.products.isEmpty` branch condition and both sibling branches
  (`PRO ACTIVE — …` at :60–66, the product list at :77–104) untouched.
- **Two accent purchase buttons (`Monthly` + `Yearly`, :77–104)**: unobservable in CI (no StoreKit
  fixture). Leave the code as-is and add a `// TODO(design): rule 4 — one primary. Yearly stays
  GSPrimaryButtonStyle; Monthly becomes .gs3D(face: theme.raised3DFace, lip: theme.raised3DLip)
  when a StoreKit fixture exists to prove it.` comment at :92. Do not change it blind.

**Proves:** `app-paywall` (one accent glyph, all four titles white, no disabled slab).

### T1.7 — Full-bleed accent heroes become a raised face · **M**

Four files carry the identical defect — `.background(theme.accent)` on a static header block, with
`theme.bg` used as ink throughout:

| File | Hero | Accent fill |
|---|---|---|
| `Features/Workout/SoloRecapView.swift` | `hero` :250–277 | :275 |
| `Features/Sessions/GroupRecapView.swift` | :~300–326 | :324 |
| `Features/Sessions/CompletedSessionView.swift` | `headerSection` :~230–253 | :252 |
| `Features/Sessions/SessionRecapView.swift` | :~298–324 | :322 |

For each: replace `.background(theme.accent)` + the adjacent `.cornerRadius(GSMetrics.radiusMd)` with
`.gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 7)`. `CompletedSessionView:252` has no corner
radius today (it is full-bleed page chrome) — give it the same `.gs3DCard(cornerRadius: GSMetrics.radiusMd,
lipHeight: 7)` and 16 pt horizontal padding at the call site so it reads as an object, not a slab.

Then invert every ink inside each hero, in this exact mapping:
- `theme.bg` → `theme.text`
- `theme.bg.opacity(0.85)`, `theme.bg.opacity(0.9)`, `theme.bg.opacity(0.8)` → `theme.neutral500`
- `theme.bg.opacity(0.15)` used as a chip fill → `theme.surface`

For `SoloRecapView` that is `:255`, `:260`, `:264`, and `heroStatCell` `:283`, `:287`.
For `CompletedSessionView` that is `:248`, `:252-4`, `:267`, `:271`, `:281` (grep `theme.bg` inside
the header block and convert every one).

Also `SoloRecapView.swift:295` and `GroupRecapView.swift:429` / `SessionRecapView.swift:282` — the
"YOUR PR THIS SESSION" callout's `theme.accent100` fill: leave the fill, but ensure the screen's one
accent BUTTON (`Done` / `Share Recap`) is the only accent-faced control. If `Share Recap` is
accent-faced, demote it to `.gs3D(face: theme.raised3DFace, lip: theme.raised3DLip, …)`.

**Proves:** `app-recap-solo`, `app-group-recap`. (`CompletedSessionView` and `SessionRecapView` are
reached by `app-session-recap`, which is mis-navigated today — re-verify after T-F.1.)

### T1.8 — Two primaries become one · **S**

- `GymSyncApp/GymSync/Features/Social/CreateGroupView.swift:162–171` — **delete the entire
  `ToolbarItem(placement: .confirmationAction)` block.** The body's pinned "Create Group" button
  (:~140–152) is the one primary; the toolbar item calls the identical `create()`.
- `GymSyncApp/GymSync/Features/Sessions/ScheduleSessionView.swift:193–199` — **delete the entire
  `ToolbarItem(placement: .confirmationAction)` "Next" block.** The pinned CTA at :153–183
  ("Schedule" / "Create series") calls the same `schedule()`.

Neither deletion removes a reachable action; both buttons are duplicates of a pinned CTA on the same
screen.

**Proves:** `app-create-group`. **`ScheduleSessionView` has no capture** — code review only; the
capture gap is listed at the end.

### T1.9 — Decorative accent off chips, tags and segments · **S** (depends on T7.1)

- `GymSyncApp/GymSync/Features/Social/VenueHubViews.swift:666–668` — `equipmentChip`'s
  `Capsule().strokeBorder(theme.accent, lineWidth: 1)` → `theme.divider`. These are static readouts
  in the non-owner view; the owner's tappable chips at :639–642 keep their accent face (a real
  on-state).
- `GymSyncApp/GymSync/Features/Library/CampaignDetailView.swift:219` —
  `GSTag(text: "FEATURED", style: .accent)` → `.neutral`.
- `GymSyncApp/GymSync/Features/Library/DiscoverWorkoutDetailView.swift:258` —
  `GSTag(text: DiscoverView.metricLabel(metric), style: .accent)` → `.neutral`, matching
  `DiscoverView.swift:318`'s own `.neutral` for the same chips.
- Same file, `:313–315` — the projected-weight line `"~… for you"` `theme.accent` → `theme.neutral500`.
- Same file, `sortSegmentedControl` (~:451–482) — the selected segment's solid accent block is
  heavier than the screen's primary. Change the selected fill to `theme.raised3DFace` and the
  selected label to `theme.text`; keep an accent 2 pt underline as the current-item mark (a legal
  "current item in a pager" use).

**Proves:** `app-venue-hub`, `app-campaign-detail-joined`, `app-campaign-detail-unjoined`,
`app-discover-detail`.

### T1.10 — Badges point, they do not shout · **S**

File: `GymSyncApp/GymSync/Features/Social/SocialTabView.swift:198–203`.

The Friends row carries both an accent `GSTag("1 new")` AND a separate neutral `friendCount`. Rule 4
asks for one small accent count. Wrap the plain count so it only renders when nothing is pending:
```swift
if pendingCount > 0 {
    GSTag(text: "\(pendingCount) new", style: .accent)
} else {
    Text("\(friendCount)")
        .font(GSFont.body(14, relativeTo: .subheadline))
        .foregroundStyle(theme.neutral500)
}
```

**Proves:** `app-tab-social`.

---

# B2 — Gold discipline (6 screens)

Gold has exactly two jobs: the week-streak number, and "the window is open, act now". Five sites spend
it elsewhere. **Gold ON for Home's `174` is B5's work — excluded here.**

### T2.1 — Shop and My Rack stop spending gold · **S**

- `GymSyncApp/GymSync/Features/You/ShopView.swift:45` — `card(title: "PRO", titleColor: Color.gsHex(0xE8C33A), …)`
  → `titleColor: theme.text`.
- Same file `:70–74` — the rotation countdown `Text(rotationText)` `Color.gsHex(0xE8C33A)`
  → `theme.neutral700`.
- `GymSyncApp/GymSync/Features/Shop/MyRackView.swift:402–406` — the identical countdown
  `Color.gsHex(0xE8C33A)` → `theme.neutral700`.

**Proves:** no capture (`shop`/`my-rack` have no catalog ids). Code review only; capture gap listed
at the end.

### T2.2 — The ledger's PRO gate line · **S**

`GymSyncApp/GymSync/Features/Stats/StatsTabView.swift:270–272` — the gate button's label
`Color.gsHex(0xE8C33A)` → `theme.accent700`. The button already wears `.gs3DCardStyle`
(:277), which is the neutral raised face every other gated row uses.

**Proves:** `app-tab-stats` only if the entitlement flag renders the row (audit B could not confirm
it in this state). Verify the pixel; if the row still does not render, the change is code-review-only.

### T2.3 — "Block ends" is not a gold moment · **S**

`GymSyncApp/GymSync/Features/Coach/BlockCalendarView.swift` — three uses of `blockGold`
(defined :72):
- `:185` the header `Text("ENDS …")` → `theme.accent700`.
- `:253` `fill(for:)`'s `if let last = blockEnd … { return blockGold }` → `theme.accent`.
- `:267` `legendDot(blockGold, "BLOCK ENDS")` → `legendDot(theme.accent, "BLOCK ENDS")`.
Delete the now-unused `blockGold` constant at `:72` and the "goals, streaks, finish lines" comment
that justified the broader reading.

**Proves:** no capture (`block-calendar` has no catalog id). Code review only.

### T2.4 — Gold ON: the Stats streak number · **S**

`GymSyncApp/GymSync/Features/Stats/StatsTabView.swift:412–415` — the current-streak tile renders
white. It is a week-streak number, one of gold's only two jobs:
```swift
GSStatTile(
    value: currentStreakValue,
    label: "Current streak",
    valueColor: Color.gsHex(0xF6C945)
)
```
`0xF6C945` is the hex `LobbyView.swift:1266` and `HomeView` already use for the check-in/streak gold.
**Leave the "Longest streak" tile (:416–419) white** — one gold number per card. Delete the stale
comment at :410–411 ("the old live-streak accent tint retired") and replace it with the rule citation.

**Proves:** `app-tab-stats` (the current-streak number reads gold).

---

# B9 — No decorative emoji (2 screens)

Reactions and kudos stay — they are content. Chrome does not.

### T9.1 — Session-state glyphs become SF Symbols · **S**

`GymSyncApp/GymSync/Features/Social/GroupView.swift:463–469` — `sessionRow`'s state glyphs:
```swift
if session.state == "completed" {
    Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 13, weight: .regular))
        .foregroundStyle(.gsSuccess)
} else if session.state == "abandoned" {
    Image(systemName: "xmark.circle")
        .font(.system(size: 13, weight: .regular))
        .foregroundStyle(theme.neutral500)
}
```
(Green here is the same rule-2 "done" the token serves — depends on T7.1.)

**Proves:** no capture today; `app-session-recap`/`app-lobby` pass through this list after T-F.1, so
re-verify then.

### T9.2 — The system PR announcement drops its literal 🔥 · **M**

The emoji is authored **in the database**, not the app:
`supabase/migrations/20260710000007_pr_body_format.sql:26` —
`'🔥 ' || v_username || ' hit a PR on ' || v_exercise || ': ' || …` inside
`public.announce_pr()`. `ChatView.systemMessageView` (`Features/Social/ChatView.swift:688–700`)
already renders a real `Image(systemName: "flame.fill")` beside the body, so the literal is a
duplicate there and pure chrome in `CrewRoomView.chatPreview` (`:684–693`).

Three parts, ONE commit:
1. **New migration** `supabase/migrations/20260906000001_pr_announcement_no_emoji.sql`:
   `CREATE OR REPLACE FUNCTION public.announce_pr()` copied verbatim from `20260710000007` with the
   `'🔥 ' || ` prefix removed from the body expression. Nothing else changes — same
   `SECURITY DEFINER`, same `search_path`, same guards, same `payload`.
2. **Test** `supabase/tests/pr_system_message_test.sql:74` — the expected body
   `ARRAY['🔥 pr_user_a hit a PR on Bench Press: 100 lbs']` →
   `ARRAY['pr_user_a hit a PR on Bench Press: 100 lbs']`.
3. **Client-side strip for legacy rows** (existing `chat_messages` keep their prefix). Add one
   internal helper next to `ChatMessage` in `GymSyncApp/GymSync/Models/ChatMessage.swift`:
   ```swift
   /// Legacy rows written before 20260906000001 carry a literal "🔥 " prefix
   /// (design language §2: no decorative emoji — the SF flame is the glyph).
   var displayBody: String? {
       guard let body else { return nil }
       return body.hasPrefix("🔥 ") ? String(body.dropFirst(2)) : body
   }
   ```
   Use it at `ChatView.swift:695` (`Text(message.displayBody ?? "")`) and
   `CrewRoomView.swift:691` (`return message.displayBody`).

**Proves:** `app-session-recap` (which currently lands on the crew room and shows three 🔥 lines in
the CHAT preview) — and after T-F.1, `app-chat`.

---

# B3 — Surfaces (≈10 screens)

Two raised surfaces only: the static extruded card for things you read, the sinking tappable for
things you press. Furniture stays flat. Radii are 24 / 16 / 14 / 999.

### T3.1 — Campaign detail's body onto raised cards · **M**

File: `GymSyncApp/GymSync/Features/Library/CampaignDetailView.swift`. The whole page is flat on `bg`
in both states; the only raised object is the Leave button.

- `curatedWorkoutsSection` (:191–236): wrap the workout-row `VStack` (everything under the
  `GSSectionHeader`) in `.gs3DCard(cornerRadius: GSMetrics.radiusMd)` with `.padding(.horizontal, 16)`
  outside it. Rows inside stay flat furniture with `GSDivider()` between them.
- `communitySection` (:237–260) and `myProgressSection` (:261–287): each body (progress bar + its
  labels) gets `.padding(14)` then `.gs3DCard(cornerRadius: GSMetrics.radiusSm)` then
  `.padding(.horizontal, 16)`. The two progress bars themselves stay flat — they are furniture.
- `leaderboardSection` (:288–341): wrap the row list in one
  `.gs3DCard(cornerRadius: GSMetrics.radiusMd)` + `.padding(.horizontal, 16)`. The `isYou` tint from
  T1.4 rides on the face.
- Do NOT change `.contentMargins(.bottom, 88, …)` at :94 — that inset is correct and app-wide.

**Proves:** `app-campaign-detail-joined`, `app-campaign-detail-unjoined`.

### T3.2 — Paywall's feature block is a thing you read · **S**

`GymSyncApp/GymSync/Features/You/PaywallView.swift:49–51` —
`.padding(16).background(theme.surface).cornerRadius(GSMetrics.radiusMd)` →
`.padding(16).gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 7)`.

**Proves:** `app-paywall` (the block gets the lip the button below it already has).

### T3.3 — Exercise detail and Discover detail rows · **S**

- `GymSyncApp/GymSync/Features/Library/ExerciseDetailView.swift:189–192` — `statTile`'s
  `.background(theme.surface).overlay(RoundedRectangle(…).strokeBorder(theme.divider, lineWidth: 1))`
  → `.gs3DCard(cornerRadius: GSMetrics.radiusSm, lipHeight: 5)`. The "HOW TO" card at `:131` in the
  same file already does this — match it exactly.
- Same file `:160–172` — the toolbar `+` has an empty action. **Delete the whole `ToolbarItem`**;
  a control that does nothing when tapped is not a design decision. Keep the explanatory comment as
  a one-line `// (Add-to-routine has no route from this screen — the affordance was removed 2026-09-06.)`
- `GymSyncApp/GymSync/Features/Library/DiscoverWorkoutDetailView.swift:325–329` — `exerciseRow` is a
  tappable that pushes `ExerciseDetailView`. Replace
  `.background(theme.surface).cornerRadius(GSMetrics.radiusSm).overlay(…strokeBorder…)` with nothing
  here, and put `.buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))` on the
  `NavigationLink` at `:332–333` (the same "chrome belongs to the link, the label is bare" pattern
  `DiscoverView.swift:161` and `:271` already use). Keep `.padding(12)` and `.contentShape(Rectangle())`.

**Proves:** `app-discover-detail`. **`app-exercise-detail` is mis-navigated today** — re-verify after
T-F.2.

### T3.4 — Routine Builder joins the language · **M**

File: `GymSyncApp/GymSync/Features/Library/RoutineBuilderView.swift`. Zero `gs3D` usage in the app's
busiest edit surface (reached from Routines-hub BUILDER, Edit Routine, and every Trainer prescription).

- **`exerciseRow` (:704–706)** — the per-exercise card, the "static extruded card for things you
  read": `.padding(12).background(theme.surface).overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm)
  .strokeBorder(theme.divider, lineWidth: 1))` → `.padding(12).gs3DCard(cornerRadius: GSMetrics.radiusSm,
  lipHeight: 5)`. This is the highest-value line in the file.
- **Leave flat, deliberately** (rule 1: furniture stays flat, extrusion is spent on the object, not
  on every row inside it): the routine-name field (:72–79), the description field (:84–91), the
  set-structure chips inside `exerciseRow`, and the publish-fields box (:289–293).
- **Toggle rows :225–227 and :245–247** — these are two standalone rows on the page, not furniture
  inside a card. Give each `.gs3DCard(cornerRadius: GSMetrics.radiusSm, lipHeight: 5)` in place of
  the surface+stroke pair.

**Proves:** no capture (`routine-builder` has no catalog id). Code review only; capture gap listed
at the end.

### T3.5 — The legacy Group screen gets the 3D pass · **M**

File: `GymSyncApp/GymSync/Features/Social/GroupView.swift`. It reads visibly older than every sibling.

- `themedSegmentedControl` (:136–158): keep it FLAT (rule 1 names segmented controls as furniture),
  but the selected segment's `theme.accent` fill (:147) is heavier than anything else on the screen —
  change to `theme.raised3DFace` with `theme.text` ink (:144) and add a 2 pt accent underline under
  the selected segment as the current-item mark.
- `sessionsList` (:383+): the `List` rows use `.listRowBackground(theme.surface)` (:426, :440).
  Leave the List, but the Burpee Ledger row's accent glyph at `:394` → `theme.neutral700`.
- `membersList` rows and the sticky "Leave Group" footer: give the footer's container
  `.gs3DCard(cornerRadius: GSMetrics.radiusSm)` if it currently uses a bordered box.
- **"Leave Group" (:283–292)** — `.foregroundStyle(theme.accent)` at `:287` → `theme.text`. It is a
  destructive escape, not an invitation, and it competes with the "Add" button at `:213`. It already
  wears the neutral raised face (`:291–293`); only the label colour changes.

**Proves:** no capture. Code review only.

### T3.6 — Coach Consult radii to the two canonical sizes · **M**

Six files invent radii of 10/12/13/14/15/18. Canon: cards 24 (`GSMetrics.radiusMd`), small cards 16
(`GSMetrics.radiusSm`), strips 14, chips 999. Rule: a full-width card → `radiusMd`; an inline
box/row/button → `radiusSm`; a small inline chip → 999.

| File | Lines to change | To |
|---|---|---|
| `Features/Coach/InjurySeverityView.swift` | `:53` (15) | `GSMetrics.radiusSm` |
| | `:78` (10, lipHeight 3) | `GSMetrics.radiusSm`, lipHeight 4 |
| `Features/Coach/AnchorEntryView.swift` | `:57` (15), `:107` (15) | `GSMetrics.radiusSm` |
| | `:119` (10, lipHeight 3) | `GSMetrics.radiusSm`, lipHeight 4 |
| `Features/Coach/ComfortLadderView.swift` | `:72` (14), `:119` (15) | `GSMetrics.radiusSm` |
| `Features/Coach/FocusLiftPickerView.swift` | `:91`, `:123` (15); `:176`, `:201` (14) | `GSMetrics.radiusSm` |
| `Features/Coach/HealthGateView.swift` | `:98`, `:159`, `:214`, `:257` (18) | `GSMetrics.radiusMd` |
| | `:109`, `:123`, `:188`, `:227`, `:252` (15) | `GSMetrics.radiusSm` |
| `Features/Coach/ConsultCloseView.swift` | `:152` (12), `:85` (16) | `GSMetrics.radiusSm` |
| | `:136`, `:147` (13) | `GSMetrics.radiusSm` |
| | `:65` (12), `:196` (14) | `GSMetrics.radiusSm` |

`ProgramLedgerView` and `CoachRulesView` in the same folder already reference the named constants —
match them.

**Proves:** no captures (none of the six consult screens has a catalog id). Code review only.

### T3.7 — Burpee ledger radii · **S**

`GymSyncApp/GymSync/Features/Sessions/BurpeeLedgerView.swift` — three uses of `20`:
`:224` `.clipShape(RoundedRectangle(cornerRadius: 20))`, `:275` `.gs3DCard(cornerRadius: 20)`,
`:298` `.gs3DCard(cornerRadius: 20)` → all `GSMetrics.radiusMd` (24; these are card-scale widgets).

**Proves:** `app-burpee-ledger` — mis-navigated today; re-verify after T-F.1.

### T3.8 — Stat tiles get a face instead of a dashed outline · **S**

`StatTilesRow` (`GymSyncApp/GymSync/Features/Home/StatTilesRow.swift`) is **catalog-only** —
`HomeView` removed it (see the note at `HomeView.swift:1245–1252`); the only call sites are
`CatalogHostView.swift:96–98`. So this task cannot regress production.

- `zeroCard` (:97–117): replace the dashed overlay (:113–116) with
  `.gs3DCard(cornerRadius: GSMetrics.radiusSm, lipHeight: 5)`. A dashed outline is a third surface
  idiom outside the vocabulary.
- Same block, copy: lead with the invitation (rule 9). `:100` `"No lifts logged yet"` →
  `"Log your first lift"`; `:103` keeps `"Your first workout unlocks these stats."`; the button at
  `:108` `Button("Start", …)` → `Button("Start your first workout", …)` — this is an empty-state
  invitation, not a rename of a shipped primary label.
- `offlineStaleColumn` (:129–150): `:143` `valueColor: theme.accent700` → delete the parameter (the
  `—` placeholder must not be accent). Then, for the three tiles only in THIS row, opt them into a
  face: add `raised: Bool = false` to `GSStatTile`'s init (`GSComponents.swift:592–606`) and, in its
  body (:618–621), branch —
  ```swift
  .padding(10)
  .frame(maxWidth: .infinity, alignment: .leading)
  ```
  then either `.gs3DCard(cornerRadius: GSMetrics.radiusSm, lipHeight: 5)` when `raised`, or the
  existing `.background(theme.surface).cornerRadius(GSMetrics.radiusSm)` when not.
  **Default stays `false`** — the other 21 call sites (`StatsTabView.swift:412/416`,
  `CompletedSessionView.swift:259–261`, `GroupStatsView.swift:83+`, `ExerciseHistoryView.swift:170+`,
  `SettingsView.swift:342+`) sit INSIDE raised cards, where rule 1 says furniture stays flat. Pass
  `raised: true` from `StatTilesRow` only (:56–61, :76–78, :132–144).
- Also `:146` — the error caption explains notation but names no cause and offers no retry. Change to
  `"Couldn't reach the server — · marks the last synced value. Pull to refresh."` and leave the
  values as they are.

**Proves:** `app-stattile-empty` (raised face, inviting copy), `app-stattile-error` (three faced
tiles, no accent dash).

### T3.9 — Clipping and edge affordances · **S**

- **Discover cards slice their own content.** `GymSyncApp/GymSync/Features/Library/DiscoverView.swift:349`
  `.frame(height: 78, alignment: .topLeading)` — the text zone holds name + owner + an optional
  metric-chip row + a stars/attempts row, which overflows 78 pt. Change to
  `.frame(height: 96, alignment: .topLeading)` and update the comment at :346–348 (the tile total
  becomes 84 art + 96 text + 6 lip = 186).
- **Chip rows clip flush at the right edge.** `VenueHubViews.swift:623–650` and `DiscoverView`'s
  filter chip row: move the inner `.padding(.horizontal, 16)` off the `HStack` and onto the
  `ScrollView` as `.contentMargins(.horizontal, 16, for: .scrollContent)`, so the last chip can
  scroll fully clear of the edge.
- **Routines & Programming bottom inset — verify only, no change expected.**
  `RoutinesHubView.swift:81` already carries `.contentMargins(.bottom, 88, for: .scrollContent)`,
  the app-wide dock clearance, and audit B graded `app-tab-library` **FOLLOWS**. Audit A saw the
  clipping only on the two mis-navigated captures. Confirm against the next artifact; if the last row
  is still half-hidden, raise 88 → 96 in that one file and say so in the commit body.

**Proves:** `app-discover` (no sliced "187 attempts"), `app-venue-hub` (chip row insets),
`app-tab-library` (unchanged, verified).

---

# B8 — Copy

The caps sweep is **dropped by owner ruling**; no task below renames a shipped button label.

### T8.1 — The weight kicker is derived from equipment, not hardcoded · **M**

Owner-approved convention (docket, 2026-09-03): dumbbell/kettlebell **per hand**; barbell **total
including the bar**; plate-loaded machine **total added** (the loader keeps saying "per side");
unilateral **per side**.

**One helper, three surfaces.** Add to `GymSyncApp/GymSync/Models/Units.swift`, beside
`tunerStep(unit:equipment:)` (:152–158) which already derives behaviour from the same field:

```swift
/// The weight-entry kicker for a lift (design language §9). Equipment strings
/// are the catalog's vocabulary: barbell, ez-bar, smith, dumbbell, machine,
/// cable, bodyweight. `unilateral` overrides equipment — one limb at a time is
/// always per side.
static func weightKicker(unit: WeightUnit,
                         equipment: String?,
                         unilateral: Bool? = nil) -> String {
    let base = "WEIGHT · \(unit.label.uppercased())"
    if unilateral == true { return base + " PER SIDE" }
    switch equipment {
    case "barbell", "ez-bar", "smith":  return base + " TOTAL INCL. BAR"
    case "dumbbell", "kettlebell":      return base + " PER HAND"
    case "machine":                     return base + " TOTAL ADDED"
    default:                            return base
    }
}
```
`cable` and `bodyweight` deliberately get no suffix — there is no honest convention to state.

Apply at the two live set cards (both currently render the literal `"WEIGHT · \(unit)"`):
- `GymSyncApp/GymSync/Features/Workout/WorkoutSessionView.swift:2419` — inside `soloEntryCard`
  (:2249+). `currentExercise: Exercise?` is in scope (declared :337). Replace with
  `Text(Units.weightKicker(unit: soloUnit, equipment: currentExercise?.equipment, unilateral: currentExercise?.unilateral))`.
- `GymSyncApp/GymSync/Features/Sessions/GroupSessionLiveView.swift:1595` — inside `turnEntryCard`
  (:1560+). `currentExerciseForSheet` is in scope. Same substitution with `turnUnit`.
- **Both sites sit in a `.frame(width: 229, alignment: .leading)`.** Keep the 229 and add
  `.lineLimit(1).minimumScaleFactor(0.7)` so the longer kicker shrinks rather than truncating. Do not
  widen the frame — the sibling `REPS` column is laid out against it.

**Proves:** `app-solo-live-set` (`WEIGHT · LBS TOTAL INCL. BAR` on Bench Press).

### T8.2 — The plate-math and body-weight sheets get the same kicker · **S** (depends on T1.2, T8.1)

`stepperCell` already uppercases and tracks its label after T1.2, so only the strings change:
- `GymSyncApp/GymSync/Features/Workout/LogSetSheet.swift:122` —
  `label: "Weight (\(unit.label))"` → `label: Units.weightKicker(unit: unit, equipment: exercise?.equipment, unilateral: exercise?.unilateral)`.
  (Read the file for the exact name of the exercise binding in scope; the catalog fixture passes
  `catalogFixtureExercise` — `CatalogHostView.swift:770–783`, a barbell Back Squat — so the capture
  will read `WEIGHT · LBS TOTAL INCL. BAR`.)
- `GymSyncApp/GymSync/Features/Sessions/GroupSessionLiveView.swift:3608` — same substitution using
  `currentExerciseForSheet`.
- `GymSyncApp/GymSync/Features/Stats/BodyWeightLogSheet.swift:39` — `label: "Weight (\(unit.label))"`
  → `label: "BODY WEIGHT · \(unit.label.uppercased())"` (no equipment; the sheet logs a body weight,
  and rule 9's convention table does not apply).
- `LogSetSheet.swift:109` `label: "Reps"` stays — T1.2 uppercases it in the component.

The plate row's own "per side" (`LogSetSheet.swift:502`) stays exactly as it is — the docket ruling
says the loader keeps saying "per side" while the field says "total added".

**Proves:** `app-plate-math` (`WEIGHT · LBS TOTAL INCL. BAR` replacing `Weight (lbs)`),
`app-body-weight-log`.

### T8.3 — `Abandon program` stops being red · **S**

`GymSyncApp/GymSync/Features/Library/ProgramViews.swift:374–376`:
```swift
Button("Abandon program") { confirmAbandon = true }
    .font(GSFont.bodyMedium(13, relativeTo: .subheadline))
    .foregroundStyle(theme.neutral500)
```
Red is for errors only; the confirmation dialog at `:203–210` already carries `role: .destructive`
and the "Your history stays — only the plan stops." message, which is where the weight belongs.
**Do not touch** `:181` or `:821` — those are genuine error text and stay `.red`.

**Proves:** `app-program-detail`.

### T8.4 — Make the notifications-denied fixture actually show denied · **S**

**Root cause found, and the app's denied branch is correct.** `PushPrimingView` already has a full
denied state: `deniedContent` (:203–217) renders the headline `"Notifications are off"` plus the
"Turn them back on in iOS Settings…" explanation, and `footer` (:226–257) renders **`Open Settings`**
as the primary. The screen the audit asked for exists.

The fixture is overwritten. `CatalogHostView.content_pushDenied` (:298–300) calls
`PushPrimingView(catalogAuthorizationStatus: .denied)`, whose init (`PushPrimingView.swift:359–363`)
forces the status and sets `catalogSkipCheckInitialState = true`. That flag guards **only** the
`.task` at `:106–111`. It does **not** guard `.onChange(of: scenePhase)` at `:112–115`, which fires
`handleForegroundReturn()` the moment the scene becomes `.active` after launch —
and `handleForegroundReturn()` (:337–345) calls `pushReceiver.refreshAuthorizationStatus()`
(`Services/PushReceiver.swift:22–25`), which reads the simulator's real
`UNUserNotificationCenter` status (`.notDetermined`) straight back over the forced `.denied`. The
capture then renders the priming state — hence byte-identical PNGs.

Fix, in `GymSyncApp/GymSync/Features/Onboarding/PushPrimingView.swift`:
```swift
.onChange(of: scenePhase) {
    guard scenePhase == .active else { return }
    #if DEBUG
    if catalogSkipCheckInitialState { return }
    #endif
    Task { await handleForegroundReturn() }
}
```
One guard, `#if DEBUG`, exactly mirroring the `.task` guard three lines above. No production path
changes: `catalogSkipCheckInitialState` is only ever set by the `#if DEBUG` catalog init.

Extend the flag's doc comment at `:37–46` to say it now covers both the mount check and the
foreground re-check, and why.

**Proves:** `app-onboarding-push-denied` — it must stop being byte-identical to
`app-onboarding-push-priming` and must show "Notifications are off" + `Open Settings`. **Verify by
md5**, the way the audit did.

### T8.5 — Blocked Users: a row you can read, an empty state that invites · **S**

File: `GymSyncApp/GymSync/Features/Moderation/BlockedUsersView.swift`.

- **Unblock pill, fixed width, right-aligned** (:52–56): change `Spacer()` to `Spacer(minLength: 8)`
  and give the button `.frame(width: 92)` on its label so both rows' pills share one width and one
  left edge, right-aligned to the row's 16 pt trailing inset (`listRowInsets` at :60 already sets it).
- **No hard seam** (:58): `.listRowBackground(theme.surface)` → `.listRowBackground(Color.clear)`.
  The surface currently paints only behind rows, so it stops mid-page against `theme.bg`. With clear
  rows the page is one ground and `.listRowSeparatorTint(theme.divider)` (:59) carries the structure.
- **Empty state invites** (:40–44): `title: "No blocked users"` → `title: "Nobody blocked"`;
  `message:` → `"Block someone and they land here — they won't be able to message you or send friend
  requests."` Copy verbatim.
- **Back button — verified, no change.** In production this screen is a push from `YouTabView`'s
  settings row and carries the system back button. The missing back in `app-blocked-users` is a
  catalog artifact: `CatalogHostView.content_blockedUsers` (:560+) makes it the ROOT of its own
  `NavigationStack`. Record this in the commit body; do not add a toolbar item that would double up
  in production.

**Proves:** `app-blocked-users` (two identical right-aligned pills, no mid-page seam, inviting copy).

---

# B11 — Questions above the fold (1 screen)

### T11.1 — FOCUS moves above THE PLAN · **S**

File: `GymSyncApp/GymSync/Features/Library/ProgramViews.swift`, `ProgramTemplateDetailView`'s body
`VStack` at `:560–568`.

Today: `aboutSection` → `planSection` (an eight-row week readout) → `focusSection` (three required
`Choose…` pickers) → `baselineSection` → `startSection`, with `Start program` disabled until the
pickers are answered. A question below a scroll gets answered by nobody.

Reorder to:
```swift
VStack(alignment: .leading, spacing: 20) {
    aboutSection
    focusSection
    if isPercentBased, !selectedExercises.isEmpty {
        baselineSection
    }
    planSection
    startSection
}
```
`baselineSection` follows `focusSection` because it is derived from the picks (`selectedExercises`,
:505–514) — moving it with them keeps the causal reading order. Move only these lines; do not touch
any section's internals (their accent cleanups are T1.5).

**Proves:** `app-program-template-detail` (the three `Lift / Lift 2 / Lift 3 — Choose…` rows are
visible without scrolling; THE PLAN sits below them).

---

# B6 — PR splash (1 screen)

### T6.1 — Headline first, big, in accent · **S**

File: `GymSyncApp/GymSync/Features/Sessions/PRCelebrationOverlay.swift`, the main `VStack` (:65–177).

Order today is inverted: a 40 pt accent flame lands first (:68–70), then `NEW PERSONAL RECORD` as a
small muted 12 pt kicker (:74–77), then the number, then the sweep line, then the lift. Rule 8: the
headline first, big, in accent; a line sweeps under it; then the lift and the number land with the
ring.

- **Delete** `:68–72` (the flame `Image` and its 16 pt spacer) and `:74–79` (the muted kicker and its
  14 pt spacer).
- **Delete** the capsule at `:107–109` (the underline under the number) — it becomes the sweep line
  under the headline.
- **Replace** the leading `Spacer()` at `:66` with:
  ```swift
  Color.clear.frame(height: 72)

  Text("New personal record.")
      .font(GSFont.heading(34, relativeTo: .largeTitle))
      .foregroundStyle(theme.accent)
      .multilineTextAlignment(.center)

  Color.clear.frame(height: 12)

  Capsule().fill(theme.accent)
      .frame(width: 96, height: 3)

  Spacer()
  ```
  Copy verbatim, including the full stop — it is the string rule 8 names.
- Everything from the number `HStack` (:84–106) down is unchanged and still lands inside the
  concentric accent rings at `:60–63` (the "ring" the rule names), because the trailing `Spacer()`
  at `:145` keeps the block centred.
- **No kudos row exists on this splash** — do not add one; the trophy chip at `:127–143` is a real SF
  Symbol, not a kudos row, and both audits cleared it. The delta line at `:120–125` stays accent.

**Proves:** `app-pr-celebration` (`New personal record.` large and accent at the top, sweep line
under it, number and ring below, no flame glyph leading).

---

# B10 — You tab (1 screen, the v5 proof)

The widget words are right (`STATS`, `SHOP`, `ROUTINES & PROGRAMMING`, `COACH`, `SETTINGS`). What is
wrong: every line under a word is a **contents list**, not a state sentence, and the milestone hero
is absent.

**The milestone hero needs its own spec.** The approved v5 direction is "the render must NOT sit in a
sectioned tile — blend into the hero as one display" (docket, owner round 6), driven by the Blender
frame sets from `tools/milestone-render/` on `feat/milestone-render-pipeline` — not yet on master.
Wiring it needs decisions this plan cannot make: which asset set ships (340×900 tile at 41 frames vs
the Earth→moon set), how the frames are bundled and paged (`round(progress × 40)` + neighbour
cross-fade), the landmark silhouette assets per rung, and what happens on the hero when no milestone
is in reach. **Write `docs/superpowers/specs/2026-09-06-you-milestone-hero-design.md` before any
implementation task.** B10 below is scoped to the half the audit flagged that needs no new assets.

### T10.1 — State sentences under the words · **S**

File: `GymSyncApp/GymSync/Features/You/YouTabView.swift`. Replace each widget's contents list with
one sentence of live state. Where no live datum exists yet, the sentence states what the door is for
in second person — not a list of its contents.

- `statsHero` (:224): `"Volume · PRs · body weight · history"` →
  `"You've lifted \(lifetimeVolumeText) — see where it's going."`, derived from
  `appState.currentProfile?.lifetimeVolumeLifted` through `StatMath.compactNumber` +
  `Units.fromPounds(_:to: ThemeStore.shared.weightUnit)`, the exact chain
  `TopLiftersView.swift:115` already uses. When the profile is nil, fall back to
  `"Your volume, PRs, body weight and history live here."`
- `routinesWidget` — `routinesFaceText` (:268–275) already carries real state
  (`"\(n) of \(limit) slots filled"`). Rewrite it as a sentence:
  `guard let routineCount else { return "Build a routine, or start from someone else's." }` and
  `"\(routineCount) of \(limit) slots filled — build another, or start from someone else's."`
  (and for the over-limit branch, `"\(routineCount) routines on file."`).
- `coachWidget` (:285–286): per the owner's round-6 note ("drop the grey line, bigger Coach, no coach
  name; a line like 'Build my workouts'; the badge drives attention") —
  `"Your ongoing chat, your program, the research"` → `"Build my workouts."` Raise the widget title
  size for `COACH` only, inside `widgetCard` (:368+) via a new `titleSize: CGFloat = 17` parameter,
  passing `titleSize: 24` from `coachWidget`. Add the corner badge: an accent count in the top-right
  of the coach card when something waits — **wire it to a value the view already has or pass `nil`**;
  do not add a repository call in this task.
- `shopWidget` (:313): `"Pro, the soundboard rack, and training with a personal trainer"` →
  `"Pro, this week's rack, and hiring a trainer."`
- `settingsWidget` (:342): `"Account, appearance, notifications, home gym"` →
  `"Your account, your palette, your gym, your alerts."`

Each face `Text` keeps its existing `.lineLimit(2).fixedSize(horizontal: false, vertical: true)` and
the comment above it explaining why.

**Proves:** `app-tab-you` (each card carries a sentence; the dead vertical gap between word and line
closes because the lines are longer).

### T10.2 — Write the milestone-hero spec (no code) · **S**

Deliverable: `docs/superpowers/specs/2026-09-06-you-milestone-hero-design.md`, covering the frame-set
choice, the bundling and paging strategy, the landmark ladder and mass-vessel families from the
docket, the honest-count label rule ("visible plates are symbolic; the honest count goes in the
label"), and the no-milestone-in-reach state. No `YouTabView` code changes until the owner signs it.

**Proves:** nothing in CI. It is the gate for the hero work.

---

# Test-fidelity fixes (so the next audit can see every screen)

12 captures cannot be judged: 8 land on the wrong screen, 2 mid-load, 2 are debug harnesses. Fixing
them unblocks proof for T7.2, T7.3, T9.1, T3.3, T3.7 and T1.7.

### T-F.1 — Route the five crew-room captures correctly · **M**

File: `GymSyncApp/GymSyncUITests/ScreenshotTests.swift`.

**Cause, confirmed:** `SocialTabView.swift:137–141` pushes **`CrewRoomView`**, not `GroupView`. The
crew-room redesign moved the four sub-tabs (`Chat / Members / Sessions / Stats`,
`GroupView.swift:13–18`) behind the room's **MANAGE** toolbar item
(`CrewRoomView.swift:78–87`). Every `app.buttons["Sessions"]` lookup therefore times out and the walk
falls through to whatever is on screen — the crew room. The four crew-room captures are four separate
failed navigations, not one repeated screenshot.

Add one helper beside `openPushCrew` (:343–351):
```swift
/// Crew room → GroupView (behind MANAGE) → a named sub-tab.
/// `CrewRoomView.swift:78-87` puts GroupView behind a `MANAGE` toolbar item;
/// GroupView's own segmented control (GroupView.swift:136-158) renders each
/// SubTab's rawValue as plain Text, so an exact-match button lookup works.
private func openManageSubTab(_ app: XCUIApplication, _ tab: String) {
    let manage = app.buttons["MANAGE"]
    if manage.waitForExistence(timeout: 10) { manage.tap(); settle() }
    let subTab = app.buttons[tab]
    if subTab.waitForExistence(timeout: 10) { subTab.tap(); settle() }
}
```

Then:
- **`testChat` (:353–362).** The crew room opens chat as a **sheet** from its `THE CHAT` preview card
  (`CrewRoomView.swift:578–581` sets `showChat`; the sheet at `:101–107` presents `ChatView`). After
  `openPushCrew`, tap `app.buttons.matching(NSPredicate(format: "label CONTAINS 'THE CHAT'")).firstMatch`,
  `settle()`, then capture. Delete the stale comment at :358–359 ("GroupView's subTab defaults to
  .chat") — it describes the pre-redesign push.
- **`testLobby` (:364–391).** Replace the `sessionsTab` block (:371–375) with
  `openManageSubTab(app, "Sessions")`. Keep the `'Lobby Open'` caption match (:383–389) — the caption
  is still what `GroupView.sessionRow` renders.
- **`testSessionRecap` (:393–417).** Same replacement for :400–404; keep the `'Completed'` match.
- **`testBurpeeLedger` (:419–449).** **Do not go through MANAGE.** The crew room has its own
  `burpeeLedgerRow` NavigationLink (`CrewRoomView.swift:528–531`) labelled `BURPEES`. Replace
  :426–447 with a `label CONTAINS 'BURPEES'` match on the crew room itself. Update the comment.
- **`testGroupStats` (:451–469).** Replace the `statsTab` block (:463–467) with
  `openManageSubTab(app, "Stats")`. The comment at :458–462 already explains the plain-Text lookup —
  keep it, add that MANAGE is now the first hop.

**Proves:** `app-chat`, `app-lobby`, `app-session-recap`, `app-burpee-ledger`, `app-group-stats` each
render the screen their id names.

### T-F.2 — Route the two Routines-hub captures · **S**

- **`testExerciseDetail` (:509–533).** `openYouWidget(app, label: "Routines and programming")` then
  `app.buttons["Exercises"]` (:514) then `app.cells.firstMatch` (:523). The walk lands on the hub, so
  one of the two hops misses. `RoutinesHubView`'s `exercisesRow` (:66) is a `NavigationLink` inside a
  `.gs3DCardStyle` button whose label composes a glyph + text — the exact-match `app.buttons["Exercises"]`
  will not match a composed label. Change to
  `app.buttons.matching(NSPredicate(format: "label CONTAINS 'Exercises'")).firstMatch` with a
  `waitForExistence(timeout: 10)` guard, and add a `settle()` after the tap before the `app.cells`
  lookup. Keep the two settle cycles at :530–531.
- **`testLibraryExercises` (:173+).** Same predicate change wherever it does the exact-match lookup.

**Proves:** `app-exercise-detail`, `app-library-exercises`.

### T-F.3 — `app-routine-detail` mid-load, and the tab-highlight non-bug · **S**

- **Mid-load.** `testRoutineDetail` (:491–507) taps the routine card and calls `settle()` **once**
  (inside `openYouWidget`), then captures — while the detail's `.task` fetch is still in flight.
  Every other deep capture that waits on a network fetch uses two settle cycles
  (`testExerciseDetail:530–531`, `testActivityFeed:564–565`). Add
  ```swift
  settle()
  settle()
  ```
  before `attachScreenshot` at :506, with the same comment those two carry.
- **The "tab-selection bug" is not a bug — verified.** The capture highlights **You** while showing a
  Library screen because the Routines hub IS a You-tab destination: `testRoutineDetail` navigates via
  `openYouWidget(app, label: "Routines and programming")` (:494), and `YouTabView.swift:114–123`
  pushes `RoutinesHubView` from the You tab. Record this in the commit body; make no code change.

**Proves:** `app-routine-detail` (content instead of a spinner).

### T-F.4 — Correct the stale `ci_test_user_2` comments · **S**

The screenshot suite signs in as the `TEST_USER_EMAIL` account (`ios.yml:164`, `:218` →
`TEST_RUNNER_UITEST_EMAIL`), which is `ci_test_user` — the account the QA seed builds the world for
(`ios.yml:192, 202`, `scripts/seed_qa_fixtures.js --username "$CI_TEST_USERNAME"`). `ci_test_user_2`
is the **counterpart** the unit tests query as a friend/block target
(`SessionKudosTests.swift:41`: "Organizer (me, ci_test_user) + invitee (ci_test_user_2)"), never the
account that signs in.

- `GymSyncApp/GymSyncUITests/ScreenshotTests.swift:12` — "This account (ci_test_user_2 — same one the
  GymSyncTests unit test target uses)" → name the `TEST_USER_EMAIL`/`CI_TEST_USERNAME` account and
  say `ci_test_user_2` is the counterpart the unit tests query, not the signed-in identity.
- `GymSyncApp/GymSyncUITests/ScreenshotTests.swift:324` — "Reachable via the deterministic
  `ci_test_user_2` fixture world" → the `CI_TEST_USERNAME` account's world.
- `.github/workflows/ios.yml:147` — "(same ci_test_user_2 account GymSyncTests already signs in as)"
  → the `TEST_USER_EMAIL` account.
- **The fourth reference does not exist.** `CatalogHostView.swift:1476` carries no `ci_test_user_2`
  mention on master (`028602c`); the file was corrected by `a29ad5e` ("docs(p2): correct four stale
  code comments"). Say so in the commit body rather than inventing a fix. There are **three** stale
  comments, not four.

Comment-only; no code touched.

**Proves:** nothing in CI (comments). Verified by `grep -rn ci_test_user_2` returning only the unit
tests and `scripts/create_second_test_user.js`, all of which are correct.

---

## What this plan does not decide

1. **`GSGroupColor` vs the colour vocabulary.** The crew avatar tile reads orange because
   `SocialTabView.swift:418–424` paints it with `GSGroupColor.color(for:)` — the deliberate Okabe-Ito
   group-identity palette from the 2026-07-20 redesign spec (`DesignSystem/GSGroupColor.swift:16–29`),
   built to be colourblind-safe and independent of the user's accent. The 2026-09-05 design language
   does not mention a second identity palette. **Owner call:** keep `GSGroupColor` and write it into
   rule 2 alongside plate colours and the HR ramp, or retire it for neutral tiles. No task touches it.
2. **A real crew presence signal.** B7 asks for a green crew presence dot, but the Crews tab has no
   presence data — `SocialTabView.swift:430–434`'s accent dot is the **unread** badge (a legal
   rule-4 use). Lobby and the venue hub have real presence and are fixed (T7.2, T7.6). Adding crew
   presence is a product feature, not a recolour.
3. **The You milestone hero.** Needs `docs/superpowers/specs/2026-09-06-you-milestone-hero-design.md`
   (T10.2) and the Blender frame sets merged from `feat/milestone-render-pipeline`. Not scoped here.
4. **Settings behind the gear.** Rule 10 says settings live behind the gear on You;
   `YouTabView.swift:71–73` ships Settings as a full-width widget (owner-placed, 2026-08-16). Audit B
   flagged it; batch B10 did not. Real estate the owner has lived in for a month is kept until the
   owner says otherwise.
5. **The paywall's two purchase buttons.** Unobservable without a StoreKit fixture
   (`PaywallView.swift:77–104` only renders once `store.products` is non-empty). T1.6 leaves a TODO
   rather than changing it blind. **Owner/eng call:** add a StoreKit fixture + catalog id, or accept
   the code-only note.
6. **Capture gaps.** These screens have real fixes in this plan and no CI capture to prove them:
   `ScheduleSessionView` (T1.8), `ShopView`/`MyRackView` (T2.1), `BlockCalendarView` (T2.3),
   `ProgramLedgerView`/`CoachRulesView` (T7.3), `RoutineBuilderView` (T3.4), the legacy `GroupView`
   (T3.5, T9.1), and the six Coach Consult screens (T3.6). Each would need a new catalog id under
   the four-part contract (and a `FLOOR` bump once the screenshot-pipeline-fix plan lands its
   count check). **Owner/eng call:** which of these earn a capture.
7. **Two audit items outside every batch**, recorded so they are not lost: `app-heart-rate-monitor`
   (its only action, "Scan", is a raised neutral with no accent primary; "No monitor paired yet."
   states a fact where an empty state should invite) and `app-pump-composer` (the banner is
   horizontally starved — the title wraps into the accent timer and `Skip` is flush to the card edge).
   Neither appears in B1–B11.
8. **Two seed-side items from the audit's test-fidelity list, deliberately out of scope** per the
   task brief: the seed's "0 lbs PR" chat lines for bodyweight Murph sets, and the CI account's
   streak inflation reset after the residue cleanup.
