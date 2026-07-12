# Design vs. Implementation Audit — 2026-07-12

Auditor: Claude Code  
Scope: All Feature views vs. canvas `Gym Sync App Designs.dc.html` + design-system rules from `_ds/modernist-.../readme.md`  
QA trigger: device report — "some buttons are misarranged, too small, or don't work"

---

## 1. Summary Table

| Screen / View | Canvas Section | Parity Verdict |
|---|---|---|
| SignInView | Onboarding → Sign In | **Match** (accent hero, SIWA button, flush-left copy) |
| UsernameView | Onboarding → Username | **Deviates** — only 2 progress pips (canvas shows 3 pips; Step is labeled "2 OF 2" but canvas shows "2 OF 3") |
| OnboardingCoordinator | Onboarding → Home Gym + You're set | **Not built** (Home Gym screen absent; "You're set" welcome screen absent) |
| HomeView | Home tab | **Deviates** — canvas shows PR card + routine card + stat pills; implementation shows "Upcoming Sessions" + "Join with Code" only. Canvas's "Start Solo Workout" CTA missing. |
| LibraryTabView / RoutinesListView | Library tab | **Match** (segmented sub-tab, routine cards, + button) |
| RoutineBuilderView | Library → Routine Builder | **Deviates** — uses SwiftUI Form instead of custom card layout; drag handle is a non-interactive image icon rather than a real drag affordance in the canvas's card list |
| SocialTabView | Social tab | **Match** (Friends row, Groups list, + New Group) |
| ChatView | Social → Friends/Groups/Chat | **Match** (input bar, bubbles, mic hold, soundboard echo) |
| StatsTabView | Stats tab | **Deviates** — canvas shows bar chart + recent PRs table; implementation shows only Lifetime Volume + "View sessions" link + per-exercise list. Weekly volume chart and PRs table not implemented. |
| YouTabView | You tab | **Deviates** — canvas shows avatar card, stat tiles, settings rows (Edit Profile / Home Gym / Notifications / Apple Health); implementation shows only "Theme: Midnight" row + Sign Out. All settings rows absent. |
| WorkoutSessionView | Solo workout → In Progress | **Match** (accent exercise card, logged sets table, sticky Log Set button) |
| LogSetSheet | Solo workout → Log Set | **Match** (stepper cells, RPE bar, Fail + Save) |
| LobbyView | Scheduling → Lobby | **Match** (room code banner, check-in card, participants, proposals, action bar) |
| ScheduleSessionView | Scheduling → New Session | **Match** (who/when/routine/repeat) |
| GroupSessionLiveView | Live Session (Comms) | **Match** (turn card, soundboard dock, penalty banner, set feed, end bar) |
| SessionRecapView | Live Session → Recap | **Match** (hero banner, leaderboard, Done) |
| CompletedSessionView | (no dedicated canvas section) | **No design** (implemented but undesigned) |
| SessionInProgressView | (thin router) | **No design** — pass-through only |
| ExerciseHistoryView | Exercise History | **Match** (trend chart placeholder, set history) |
| ActivityFeedView | (no canvas section) | **No design** |
| FriendsView | Friends, groups & chat → Friends | **Match** |
| GroupView | Friends, groups & chat → Group | **Match** |
| ProposalCardView | Scheduling → Lobby | **Match** (vote meter, Veto/Approve buttons) |
| SeriesEditorView | Scheduling (implied) | **No design** |

---

## 2. Deviations from Canvas

### 2.1 YouTabView — Missing settings rows (HIGH)
**File:** `GymSyncApp/GymSync/Features/You/YouTabView.swift` (entire view)  
**Canvas shows:** Avatar card (initials + username + member since), stat tiles (Lifetime volume / Workouts logged), four settings rows: Edit Profile, Home Gym, Notifications, Apple Health Sync, each with a trailing chevron. Sign Out at bottom in accent-700 color.  
**Built:** Only "Theme: Midnight" (non-interactive display row) + Sign Out button. Avatar, stat tiles, and all four settings rows are absent.  
**Severity:** HIGH — a significant portion of the You tab is missing.

### 2.2 HomeView — Wrong content model (HIGH)
**File:** `GymSyncApp/GymSync/Features/Home/HomeView.swift`  
**Canvas shows:** Greeting header, "Start Solo Workout" primary CTA, PR card (accent-fill), Today's routine card, 3-tile stat row (workouts this week / lifetime lbs / PRs this month).  
**Built:** Greeting header, "+ Schedule Session" CTA (different primary action), Upcoming Sessions list, Join with Code text field. Solo workout entry, PR card, routine card, and stat tiles are all absent.  
**Severity:** HIGH — core home screen content replaced by sessions-only view.

### 2.3 StatsTabView — Bar chart and PRs table absent (MEDIUM)
**File:** `GymSyncApp/GymSync/Features/Stats/StatsTabView.swift`  
**Canvas shows:** Lifetime volume hero card, weekly volume bar chart, Recent PRs table (Exercise / Best / Date columns).  
**Built:** Lifetime volume card only; bar chart replaced by "View sessions" link + per-exercise navigation list; PRs table absent.  
**Severity:** MEDIUM.

### 2.4 UsernameView — Step count mislabeled (LOW)
**File:** `GymSyncApp/GymSync/Features/Onboarding/UsernameView.swift`, line 26  
**Canvas shows:** "STEP 2 OF 3" with three progress pips.  
**Built:** "STEP 2 OF 2" with two pips (Home Gym step was never built).  
**Severity:** LOW — label is internally consistent with the missing Home Gym screen, but inconsistent with the canvas.

### 2.5 LibraryTabView — Segmented picker is system style, not DS style (LOW)
**File:** `GymSyncApp/GymSync/Features/Library/LibraryTabView.swift`, line 16  
**Canvas shows:** A custom flat-style segmented control (`seg`/`seg-opt` DS class) — no rounded corners, accent fill on selected item.  
**Built:** `Picker` with `.pickerStyle(.segmented)` — renders as iOS native capsule-rounded segmented control, violating zero-corner-radius rule.  
**Severity:** LOW — visible on every Library tab open.

### 2.6 SocialTabView — Group rows missing last message preview (LOW)
**File:** `GymSyncApp/GymSync/Features/Social/SocialTabView.swift`, `groupRow()` (line 134–168)  
**Canvas shows:** Group row with name + last message preview text below.  
**Built:** Only group name; last message preview line absent.  
**Severity:** LOW.

### 2.7 LogSetSheet — Drag handle uses RoundedRectangle (LOW)
**File:** `GymSyncApp/GymSync/Features/Workout/LogSetSheet.swift`, line 45  
**Canvas shows:** A simple rectangular pill handle (2px square per DS zero-radius rule).  
**Built:** `RoundedRectangle(cornerRadius: 2)` — minor but technically violates the zero-radius rule.  
**Severity:** LOW.

### 2.8 ChatView — Soundboard echo uses RoundedRectangle (LOW)
**File:** `GymSyncApp/GymSync/Features/Social/ChatView.swift`, line 475  
**Built:** `RoundedRectangle(cornerRadius: 0)` — zero radius is correct but `RoundedRectangle` should just be `Rectangle()` per DS rules; functionally equivalent but inconsistent.  
**Severity:** LOW / informational.

### 2.9 WorkoutSessionView — Solo recap deviates significantly from canvas (MEDIUM)
**File:** `GymSyncApp/GymSync/Features/Workout/WorkoutSessionView.swift`, `completionCard` (line 244–274)  
**Canvas shows:** Accent hero banner with large duration timer (52px font), 3-stat row (TOTAL LBS / SETS / PRs), PR celebration card, per-exercise breakdown table, Apple Health sync card, Done button.  
**Built:** Accent banner with "Workout Complete" text (not a duration), 2-cell stats row (SETS / TOTAL LBS), Done button. No per-exercise breakdown, no PR card, no Apple Health sync card.  
**Severity:** MEDIUM.

---

## 3. Implemented-but-Undesigned Inventory

These views are fully built but have no canvas section:

| File | Description |
|---|---|
| `Features/Sessions/CompletedSessionView.swift` | Historical session detail with duration editor — no canvas equivalent |
| `Features/Sessions/SessionInProgressView.swift` | Thin router; pass-through only |
| `Features/Sessions/SeriesEditorView.swift` | Edit a recurring session series |
| `Features/Stats/ActivityFeedView.swift` | Session activity feed |
| `Features/Stats/TrendChartView.swift` | Per-exercise trend chart |
| `App/RootView.swift` — `MainTabView` | Tab bar itself uses system `TabView`; canvas shows a custom sticky bottom bar |

---

## 4. Designed-but-Unbuilt Inventory

Canvas sections with no corresponding implementation file:

| Canvas Section | What's Missing |
|---|---|
| Onboarding → Home Gym (screen 3) | Home gym map picker, geofence setup, Skip + Set Home Gym CTAs |
| Onboarding → You're set (screen 4) | Confirmation screen with "Build first routine" + "Add friends" shortcut cards |
| You tab → Profile avatar card | Initials avatar + display name + member-since |
| You tab → Stat tiles | Lifetime volume + Workouts logged |
| You tab → Settings rows | Edit Profile / Home Gym / Notifications / Apple Health Sync |
| Home tab → Start Solo Workout CTA | Primary button launching a solo session |
| Home tab → PR card | Accent card showing most recent PR |
| Home tab → Today's routine card | Routine preview card |
| Home tab → Stat row | 3-tile weekly summary |
| Stats tab → Weekly volume bar chart | 6-bar bar chart with accent current-week bar |
| Stats tab → Recent PRs table | Exercise / Best / Date 3-column table |
| Live session → Solo recap → Full recap | Duration hero, PR card, per-exercise table, Apple Health sync card |
| Empty/error states | "No crew yet" empty state, offline reconnecting pill, voice-unavailable banner, inline error toast, permission priming screen |

---

## 5. Button / Interaction Defect Candidates

### DEFECT-1 — "End Session" X button in GroupSessionLiveView: 30×30 tap target (TOO SMALL)
**File:** `GymSyncApp/GymSync/Features/Sessions/GroupSessionLiveView.swift`, line 368–376  
**Evidence:**
```swift
Button { showEndConfirmation = true } label: {
    Image(systemName: "xmark")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(theme.neutral700)
        .frame(width: 30, height: 30)    // <-- 30×30, below 44pt minimum
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
}
.buttonStyle(.plain)
```
The frame is 30×30 pt with no additional padding. This is 14pt short of the iOS 44pt minimum tap target. This button ends the session for all participants — failing to tap it reliably is a high-severity interaction failure. No `.contentShape(Rectangle())` with a larger frame is present.  
**Defect type:** Too-small tap target.

---

### DEFECT-2 — "Pencil / Edit Duration" button in CompletedSessionView: 16pt icon + 8pt padding = 32pt effective (TOO SMALL)
**File:** `GymSyncApp/GymSync/Features/Sessions/CompletedSessionView.swift`, line 150–160  
**Evidence:**
```swift
Button { showEditSheet = true } label: {
    Image(systemName: "pencil")
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(theme.accent)
        .padding(8)           // 16 + 8×2 = 32pt — still below 44pt
        .background(theme.surface)
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
}
```
Effective tap area is approximately 32×32 pt (16px icon + 8px padding each side). `.contentShape(Rectangle())` is not applied, so the hit-test area matches the visual bounds. Missing the 44pt iOS minimum by ~12pt.  
**Defect type:** Too-small tap target.

---

### DEFECT-3 — Username suggestion buttons: no minimum height, vertical padding only 6pt (TOO SMALL)
**File:** `GymSyncApp/GymSync/Features/Onboarding/UsernameView.swift`, line 121–135  
**Evidence:**
```swift
Button { username = suggestion; ... } label: {
    Text("@\(suggestion)")
        .font(GSFont.bodyMedium(12, relativeTo: .caption))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)     // 12px text + 12px padding = ~24pt total height
        .frame(minWidth: 0)
        // No minHeight; no contentShape
}
.buttonStyle(.plain)
```
At 12pt font + 6pt top/bottom padding the buttons are roughly 24pt tall — less than half the iOS 44pt minimum. Three suggestion buttons on the onboarding screen will be frequently mis-tapped.  
**Defect type:** Too-small tap target.

---

### DEFECT-4 — "Edit Routine" link in LobbyView: `.buttonStyle(.plain)` on icon+text HStack without `.contentShape(Rectangle())` (POSSIBLY-BROKEN)
**File:** `GymSyncApp/GymSync/Features/Sessions/LobbyView.swift`, line 546–559  
**Evidence:**
```swift
Button {
    showProposalComposer = true
} label: {
    HStack(spacing: 6) {
        Image(systemName: "pencil.and.list.clipboard")
            .font(.system(size: 14))
        Text("Edit Routine")
            .font(GSFont.bodyMedium(14, relativeTo: .body))
    }
    .foregroundStyle(theme.accent)
}
.buttonStyle(.plain)
.padding(.horizontal, 16)
.padding(.bottom, 8)
```
`.buttonStyle(.plain)` on an `HStack` without `.contentShape(Rectangle())` means hit-testing falls through the transparent gap between the icon and text. On a real device, tapping the space between icon and label text will not trigger the button. The button also has no vertical padding in the label itself, making it approximately 14–17pt tall.  
**Defect type:** Possibly-broken (hit-test gap) + too-small.

---

### DEFECT-5 — Veto button in ProposalCardView: 7pt vertical padding = ~26pt total height (TOO SMALL)
**File:** `GymSyncApp/GymSync/Features/Sessions/ProposalCardView.swift`, line 52–63  
**Evidence:**
```swift
Button { Task { await onVeto() } } label: {
    Text("Veto")
        .font(GSFont.bold(12, relativeTo: .caption))
        .foregroundStyle(theme.text)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)     // 12pt font + 14pt padding ≈ 26pt
        .background(theme.surface)
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
}
.buttonStyle(.plain)
```
Same issue on "Approve" (`.padding(.vertical, 7)`). Both vote action buttons in the proposal card are ~26pt tall. On device in a crowded proposal card these are reliably mis-tapped. No `.contentShape` expansion.  
**Defect type:** Too-small tap target.

---

### DEFECT-6 — Mic button in ChatView: `onLongPressGesture` on a non-Button view (POSSIBLY-BROKEN)
**File:** `GymSyncApp/GymSync/Features/Social/ChatView.swift`, line 249–291  
**Evidence:**
```swift
private var micButton: some View {
    Image(systemName: "mic")
        ...
        .frame(width: 38, height: 38)
        ...
        .onLongPressGesture(minimumDuration: 0.15, pressing: { pressing in ... }, perform: { })
        .disabled(isSendingVoice)
```
The `micButton` is a bare `Image` with `onLongPressGesture` — not a `Button`. When `.disabled(isSendingVoice)` is true, `disabled()` has no effect on `onLongPressGesture` (it only disables button controls). The disable check is also not enforced inside the `pressing:` closure. Additionally, in a `ScrollView`-embedded context (within the input bar `VStack` in the `ChatView` `VStack`), `onLongPressGesture` competes with the scroll gesture recognizer; scroll attempts can accidentally start the recording. No `contentShape(Rectangle())` is present, but the 38×38 frame is adequate in itself.  
**Defect type:** Possibly-broken (`.disabled` ineffective; gesture conflicts; no visual feedback for disabled state).

---

### DEFECT-7 — "Check In" button in LobbyView: uses `.buttonStyle(.plain)` with a hand-rolled label — no `contentShape` (POSSIBLY-BROKEN)
**File:** `GymSyncApp/GymSync/Features/Sessions/LobbyView.swift`, line 605–632  
**Evidence:**
```swift
Button { Task { await initiateCheckIn() } } label: {
    HStack {
        if isCheckingIn { ProgressView()...; Text("Checking in…")... }
        else { Image(systemName: "location.circle.fill")...; Text("Check In")... }
        Spacer()
    }
    .foregroundStyle(theme.accent)
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity)
    .background(theme.accent100)
    .overlay(Rectangle().strokeBorder(theme.accent, lineWidth: 1))
}
.buttonStyle(.plain)
.disabled(isCheckingIn)
```
`.buttonStyle(.plain)` on a label that contains `Spacer()` — the `Spacer` does not extend hit-testing; without `.contentShape(Rectangle())` the area between the icon text and the trailing edge of the button is a dead tap zone. The button is full-width visually but only hits on the actual image/text glyphs. On device this makes tapping the right side of the Check In button fail silently.  
**Defect type:** Misarranged / possibly-broken (dead hit-test zone on Spacer region).

---

### DEFECT-8 — Solo Workout "End" toolbar button: text button styled with `.tint` instead of full 44pt bar button (MISARRANGED)
**File:** `GymSyncApp/GymSync/Features/Workout/WorkoutSessionView.swift`, line 107–112  
**Evidence:**
```swift
ToolbarItem(placement: .topBarTrailing) {
    Button("End") { Task { await endSession() } }
        .font(GSFont.bodyMedium(14, relativeTo: .body))
        .tint(theme.accent)
}
```
Canvas shows a `btn btn-secondary` style "Finish" button next to an elapsed timer in the navigation bar. The implementation has a plain text "End" toolbar button — no elapsed timer alongside it. The canvas treatment is a bordered button; the implementation uses a system tint-colored text link with no visible border or background, which looks like a destructive inline text link rather than a contained CTA.  
**Defect type:** Misarranged vs. canvas + missing elapsed timer.

---

### DEFECT-9 — Tab bar uses system TabView instead of custom sticky bottom bar (MISARRANGED)
**File:** `GymSyncApp/GymSync/App/RootView.swift`, line 36–57  
**Canvas shows:** Custom sticky bottom bar with 2px top border, icon + 10pt label, no rounded tab bar chrome.  
**Built:** System iOS `TabView` — renders with default translucent tab bar background, rounded icons at system sizes, no 2px divider. The tab icons also use system `.fill` variants not present in the canvas.  
**Defect type:** Misarranged — diverges from system rules and canvas layout. System tab bar has its own internal gesture handling that can conflict with gestures near the screen bottom.

---

### DEFECT-10 — "Lock in & Start" and "Log Set & Pass" buttons: flush-left label unexpectedly places content left of center on short text (MISARRANGED)
**File:** `GymSyncApp/GymSync/Features/Sessions/LobbyView.swift`, line 645–663 (action bar)  
**File:** `GymSyncApp/GymSync/Features/Sessions/GroupSessionLiveView.swift`, line 439–455 (turn card)  
These are hand-rolled buttons (not using `GSPrimaryButtonStyle`) built with `HStack { Text ... Spacer() }` inside a `.buttonStyle(.plain)`. The design-system rule is flush-left labels (which these correctly implement). However, because they don't use `GSPrimaryButtonStyle`, they miss `.contentShape(Rectangle())`, making any tap on the `Spacer()` portion of the full-width button a dead zone — same pattern as DEFECT-7.  
**Defect type:** Possibly-broken (Spacer hit-test dead zone).

---

## Appendix: Design System Rules Checklist

| Rule | Status |
|---|---|
| Zero corner radius | Mostly respected; `RoundedRectangle(cornerRadius: 2)` in LogSetSheet line 45 is a minor violation |
| Flush-left button labels | Respected where `GSPrimaryButtonStyle` / `GSSecondaryButtonStyle` are used; violated on hand-rolled `.buttonStyle(.plain)` CTAs |
| 2px dividers | `GSDivider` used throughout; some places use `Rectangle().fill(theme.divider).frame(height: 1)` (1px) instead |
| Midnight tokens | Consistently used via `GSTheme.midnight` |
| Archivo font | Consistently used via `GSFont`; system font used for icons only (acceptable) |
| Accent used sparingly | Respected |
| No hardcoded hex colors | Respected; all colors from `theme.*` |
| 44pt minimum tap targets | Violated in DEFECT-1, 2, 3, 5 |
| `contentShape(Rectangle())` on `.plain` buttons | Missing in DEFECT-4, 7, 10 |
