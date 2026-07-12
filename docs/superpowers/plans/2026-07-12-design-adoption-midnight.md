# Gym Sync — Design Adoption (Midnight) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adopt the design counterpart's "Modernist/Gym Sync" design system across the whole app — midnight palette as the sole shipped theme (more palettes later) — restyling every existing surface to the committed design canvas.

**Architecture:** A Swift token layer (`GSTheme`) mirroring the design system's CSS variables, injected via SwiftUI Environment; Archivo replaces system type; a small component kit (flush-left buttons, zero-radius cards, tags, 2px rules) that every screen consumes. Then tab-by-tab restyles whose single source of truth is the versioned design canvas at `docs/design/Gym Sync App Designs.dc.html` (+ `docs/design/_ds/.../readme.md` for system rules).

**Design authority (user decision 2026-07-12):** when app and design disagree, DESIGN WINS; iterate via TestFlight. Default and only palette in this plan: **midnight**. Desktop scrollbars/demo animations in the canvas are canvas chrome, NOT app spec.

**Tech Stack:** unchanged; plus bundled Archivo (OFL) font files.

## Global Constraints

- All prior engineering constraints apply (repositories untouched — this plan is VIEW-LAYER ONLY except font/theme plumbing; CI-verified; no print/force-unwraps).
- **Zero functional regressions**: every existing behavior (realtime, dedup guards, scenePhase refetch, markRead, navigation targets, organizer gating) must survive restyling. Reviewers treat any logic-line change as suspect.
- **Midnight tokens (verbatim from canvas — the Swift source of truth):**
  - bg `#13161c`, surface `#1e232c`, text `#eef2f7`, divider `white 15%`
  - accent `#38bdf8`, accent600 `#22a6e4`, accent700 `#7dd3fc`, accent100 `#0e2c3a`, accent200 `#123a4d`, accent300 `#17506b`, accent800 `#bae6fd`
  - neutral100 `#1a1e26`, 300 `#2b3038`, 400 `#3a414b`, 500 `#6b7280`, 700 `#9aa2ae`, 800 `#cfd4db`, 900 `#eef2f7`
- **System rules (from `_ds` readme — binding):** zero corner radius everywhere; flush-LEFT labels including inside buttons; 2px dividers (divider color) between major sections; accent used sparingly (primary action + small emphasis); grayscale images; Lucide-style iconography (approximate with SF Symbols nearest-equivalents — do NOT add an icon package in this pass).
- **Type:** Archivo (`Archivo-Regular/Medium/SemiBold/Bold` static TTFs) via `GSFont` helpers; dynamic-type-scaled with `UIFontMetrics`-equivalent (`.custom(_:size:relativeTo:)`).
- Branch `feature/design-midnight`; PR `--base master`; standard CI loop on that branch.
- 3b executes AFTER this plan ships (its Live Session view will be built to the canvas design directly).

## Explicitly deferred

- Palette picker + modernist/ink/arena palettes (tokens may be encoded but only midnight ships/selects).
- Screens for features that don't exist yet (Live Session/3b, soundboard+voice/3c, PTT/3e, PR moment animation) — their designs are consumed by those phases' plans.
- True Lucide icon bundling; grayscale image pipeline (no user photos render outside avatars yet — avatars keep color, deviation noted).

## File Structure

```
GymSyncApp/GymSync/DesignSystem/
├── GSTheme.swift            # Task 1 (tokens, Environment key, midnight palette)
├── GSFont.swift             # Task 1 (Archivo helpers)
├── GSComponents.swift       # Task 1 (GSButtonStyle, GSCard, GSTag, GSDivider, GSSectionHeader)
└── Fonts/Archivo-*.ttf      # Task 1 (4 statics; project.yml resources + UIAppFonts)
Tasks 2-7 modify: RootView/App chrome, Onboarding views, HomeView, Library views,
Social views (ChatView incl. typing/image/reaction states), Stats+You views,
Workout (solo + LogSetSheet), Sessions views (ScheduleSessionView, LobbyView,
SeriesEditorView, ProposalCardView, SessionInProgressView placeholder styling).
GymSyncApp/GymSyncTests/DesignSystemTests.swift   # Task 1
```

---

### Task 0: Branch

- [ ] `cd /g/Projects/GymSync && git checkout master && git pull --ff-only && git checkout -b feature/design-midnight`

---

### Task 1: Foundation — tokens, Archivo, component kit

**Files:** Create the four `DesignSystem/` files + font TTFs; Modify `GymSyncApp/project.yml` (resources + `UIAppFonts` Info.plist keys); Test `GymSyncTests/DesignSystemTests.swift`.

**Interfaces (Tasks 2-7 compile against):**
- `struct GSTheme` with static `let midnight: GSTheme` exposing `Color` properties named exactly: `bg, surface, text, divider, accent, accent100, accent200, accent300, accent600, accent700, accent800, neutral100, neutral300, neutral400, neutral500, neutral700, neutral800, neutral900` (values from Global Constraints; Color(hex:) initializer included) + `EnvironmentValues.gsTheme` (default `.midnight`).
- `enum GSFont`: `static func heading(_ size: CGFloat, relativeTo: Font.TextStyle) -> Font` (Archivo SemiBold), `body(...)` (Regular), `bodyMedium(...)`, `bold(...)` — `.custom("Archivo-...", size:, relativeTo:)`.
- Components (all zero-radius, flush-left):
  - `GSPrimaryButtonStyle` / `GSSecondaryButtonStyle` / `GSGhostButtonStyle` (`ButtonStyle`s: full-width variants put the label leading-aligned with trailing spacer; pressed state = accent600 fill / tint per system rules)
  - `GSCard { content }` (surface fill, NO radius, optional 1px neutral300 border)
  - `GSTag(text:style: .accent/.neutral/.outline)`
  - `GSDivider()` (2px, divider color)
  - `GSSectionHeader(_ text:)` (uppercase-tracking kicker style per canvas)
- Font acquisition: download Archivo statics from Google Fonts GitHub (`https://github.com/google/fonts/raw/main/ofl/archivo/...` — implementer verifies exact raw URLs; the repo hosts variable fonts, so if statics aren't available, instantiate the 4 weights from the variable TTF is NOT possible in CI — instead download from `https://fonts.google.com/download?family=Archivo` zip via curl and extract the 4 static weights; commit the TTFs + OFL.txt).
- project.yml: add `resources: [GymSync/DesignSystem/Fonts]`-style include (XcodeGen: add the folder to target sources — .ttf in sources folder are auto-bundled as resources; verify) + Info.plist `UIAppFonts` listing the 4 filenames.
- Tests: `UIFont(name: "Archivo-Regular", size: 12)` etc. non-nil for all 4 (proves bundling + Info.plist); GSTheme.midnight.accent equals expected RGBA (Color comparison via UIColor components).
- CI loop; commit `feat(design): midnight token layer, Archivo, GS component kit`.

---

### Task 2: App chrome + root theming

**Files:** Modify `App/RootView.swift`, `App/GymSyncApp.swift`; the You tab gains an "Appearance" row (static "Midnight" for now).

Contract: dark color scheme forced (`.preferredColorScheme(.dark)` at root); `.environment(\.gsTheme, .midnight)`; TabView styled per canvas dock (bg surface, accent selection, Archivo labels — via UITabBarAppearance in an `init` or `.toolbarBackground`); NavigationStack bars: surface background, Archivo titles (UINavigationBarAppearance with the custom font). List/Form backgrounds → `bg` (scrollContentBackground hidden + background). Read the canvas "Home · Library · Social · Stats · You" section for dock treatment. CI green; commit `feat(design): app chrome — themed tab dock, nav bars, root palette`.

---

### Task 3: Onboarding restyle

**Files:** Modify `Onboarding/SignInView.swift`, `UsernameView.swift`, (gym-setup view — READ Features/Onboarding for its name), `OnboardingCoordinator.swift` if it owns chrome.

Source: canvas sections "Onboarding", "Pick your username", "Set your home gym", "You're in,". Contract: restyle to tokens/components; SIWA button keeps Apple's required style but sits on themed ground; flush-left headings, GSPrimary CTAs. NO logic changes. CI; commit `feat(design): onboarding in midnight`.

---

### Task 4: Home + Stats + You

**Files:** Modify `Home/HomeView.swift`, `Stats/*.swift` (READ all four), `You/YouTabView.swift`.

Source: canvas "Good morning, Alex", "Stats", "You". Contract: greeting header pattern, upcoming-session cards as GSCards with 🔁/time meta per canvas, join-code row styled, quick actions as flush-left buttons; Stats: chart containers in GSCard, Archivo axis-free styling (Swift Charts foregroundStyle → accent), PR hall list with GSTags; You: settings rows + Appearance row from Task 2 relocated here if cleaner. NO logic changes. CI; commit `feat(design): home, stats, you in midnight`.

---

### Task 5: Library + Solo workout

**Files:** Modify `Library/*.swift` (all five), `Workout/WorkoutSessionView.swift`, `Workout/LogSetSheet.swift`.

Source: canvas "Library", "Routines & the exercise library", "Bench Press", "Exercise history", "Solo workout" (+ RPE/log-set treatments — canvas has 10 RPE mentions; match its stepper/slider treatment). Contract: exercise rows with kicker/meta layout, detail page hero (grayscale rule N/A — no photos yet), routine builder restyled, LogSetSheet per canvas log-set card (reps/weight/RPE controls). NO logic changes. CI; commit `feat(design): library + solo workout in midnight`.

---

### Task 6: Social — friends, groups, chat (stateful)

**Files:** Modify `Social/*.swift` (SocialTabView, FriendsView, CreateGroupView, GroupView, ChatView).

Source: canvas "Social", "Friends, groups & chat" — INCLUDING its designed states: typing indicator treatment, image-message bubble, reaction pills, unread markers. Contract: group rows w/ avatar treatment + unread per canvas; chat bubbles flush-left architecture per canvas (system messages centered per existing behavior unless canvas dictates otherwise — canvas wins), input bar styling, PhotosPicker button placement per canvas. PRESERVE all behavior (dedup, markRead, realtime, scenePhase). CI; commit `feat(design): social + chat in midnight`.

---

### Task 7: Sessions surfaces — scheduling, lobby, accountability

**Files:** Modify `Sessions/ScheduleSessionView.swift`, `LobbyView.swift`, `ProposalCardView.swift`, `SeriesEditorView.swift`, `SessionInProgressView.swift` (placeholder gets themed shell only).

Source: canvas "Scheduling, lobby & accountability" — the newest section, includes: repeats/weekday-chip treatment, series rows, proposal cards with Approve/Veto buttons, burpee/penalty banner treatment, room-code display, check-in states. Contract: WeekdayRuleEditor chips per canvas; proposal cards match approve/veto/resolved states; lobby participant rows (presence/check-in iconography per canvas); Manage menu unchanged functionally. PRESERVE all behavior. CI; commit `feat(design): scheduling + lobby in midnight`.

---

### Task 8: Ship

- [ ] Full suite: pgTAP untouched-green sanity + CI green.
- [ ] `gh pr create --base master --title "Design adoption: Midnight" ...` (summary + note: view-layer only, design canvas at docs/design is source of truth).
- [ ] Merge (auto-TestFlight) → device QA: every tab walked against the canvas side-by-side; regression sweep (realtime chat, series scheduling, lobby round-trip via qa scripts); expect iteration rounds per user ("we will iterate with testing").
- [ ] Post-QA: 3b executes next, building Live Session to the canvas design.

---

## Self-Review Notes

- View-layer-only discipline stated in Global Constraints and repeated in every restyle task; reviewers gate on it.
- Canvas file committed at `docs/design/` (versioned; subagents read specific `<h1/h2>` sections named in each task).
- Fonts: acquisition path has a primary and fallback strategy; bundling verified by a hermetic UIFont test (real CI signal).
- Avatars stay color (deviation from grayscale-photography rule, documented) — grayscaling user faces reads as "deceased" in common UI convention; canvas treats avatars with initials mostly anyway.
- Task granularity = one CI cycle each, sized to review gates; Tasks 3-7 are contract-style (implementers read canvas + existing views).
