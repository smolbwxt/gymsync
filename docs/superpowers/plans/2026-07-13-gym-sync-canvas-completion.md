# Gym Sync — Canvas Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build/align every designed-but-unbuilt or drifted surface: the new "Next phases" canvas section (Settings Hub, notification priming/denied/preferences redraws), Burpee Ledger, empty/offline/error states, and palette activation (Arena/Ink/Modernist live).

**Architecture:** View-layer work plus two small data additions (crew penalty aggregates for the ledger; a `default_rest_seconds` user setting) and a GSTheme multi-palette extension with persistence.

**Specs (authority order):**
1. `.superpowers/new-canvas-section.diff` — the designer's new section SOURCE (exact styles/copy; render pipeline can't capture these frames — the markup is the contract). Covers T1/T2. NOTE: the last frame (PTT variants) is tail-truncated; PTT is 3e scope anyway.
2. Rendered proofs `.superpowers/proofs/`: p25-burpee-ledger, p30-empty-offline, p31-errors, p33-theme-picker, p34-session-detail (older sections, fully valid).
3. Canvas palette CSS (committed canvas head, `<style>` block): all four palettes' token sets — the Swift source of truth for T5.

## Global Constraints

- GSTheme/GSFont tokens only; zero-radius; flush-left rows; centered commit-CTAs; 44pt hit areas with SMALL drawn boxes via invisible padding (designer ruling #1); 2px section dividers; uppercase tracked kickers; no Timers.
- Migrations append-only, next free `20260717000001`; db push + pgTAP conventions as established.
- Branch `feature/canvas-completion` (exists, base 5abcd3f). Specific-file adds. CI green per task. PR `--base master` at the end; merge per standing authorization.
- Implementers WRITE THEIR REPORT FILE BEFORE starting any CI watch (3 prior yield-before-report incidents).
- PTT frames (p39/p40) are 3e scope — do NOT build any PTT UI in this phase.
- Recorded deviation policy: canvas silent on data plumbing — reuse existing repositories/patterns; document judgment calls in reports.

---

### Task 1: Notification surfaces alignment (priming, denied, preferences)

**Files:** Modify `Features/Onboarding/PushPrimingView.swift`, `Features/You/NotificationPreferencesView.swift`, `GymSyncTests/PushRegistrationTests.swift` (label test if labels move).

**Spec:** new-canvas-section.diff frames "Notif Priming", "Notif · Denied", "Notif Preferences" — read the markup; every style/copy value is explicit.

Contract deltas from shipped v1 (verify each against the diff, not memory):
- Priming: subtitle "We'll ping you only for the things that matter mid-training. You can fine-tune every category later."; bullets reworded: "A heads-up when the lobby opens" / "A nudge the moment it's your turn" / "A ping when a friend adds you" (accent700 check icons, 2.6 stroke); headline 34pt; icon square 60 accent w/ 30pt bell; CTA "Turn on notifications" (centered, 15pt/14pad); "Not now" ghost CENTERED (align-self center).
- Denied: back button visible (30×30 drawn, 44pt hit); crossed-bell in a BORDERED (divider, 2px) square, 50%-muted icon color; copy "Turn them back on in iOS Settings to get turn alerts, session reminders, and friend pings. Your category preferences are saved and waiting."; CTA "Open Settings" full-width justify-BETWEEN with trailing ↗ icon. This is BOTH the onboarding-denied and re-entry design → wire `PushPrimingView(isOnboarding: false)` from the preferences screen's denied banner "Open" → resolves the dead-code question: the denied variant becomes the re-entry destination (update the banner action) — keep the banner itself too per its own frame.
- Preferences: GROUPED into "Sessions" (Session invites, 15-minute reminders, Lobby is open, It's your turn, Idle session nudges) and "Social & chat" (Friend requests, Crew PRs, Late-arrival pings, Mentions in chat, Leaderboard changes) — 1px-bordered group boxes, internal 1px dividers, h6 kickers at 60% text; CUSTOM SQUARE toggles (46×27 accent track, 21×21 bg knob right; off = neutral300 track, neutral500 knob left; disabled-looking label at 60% when off) replacing system Toggle — build `GSToggle` in GSComponents (public, Bool binding, 44pt hit with small drawn box); system-denied banner per its frame (card, 3px accent left border, "Disabled in iOS Settings" / "Saved here, but won't apply until re-enabled." + compact "Open" secondary button).
- Keep: category keys, repository semantics, label test (update grouping/labels if any label text changed — cross-check all 10 against the diff).

CI green (report BEFORE watch). Commit `feat(design): notif priming/denied/prefs aligned to canvas redraws; GSToggle`.

---

### Task 2: You tab → Settings Hub

**Files:** Modify `Features/You/YouTabView.swift`; Create `Features/You/RestTimerSettingView.swift` (tiny); Migration `supabase/migrations/20260717000001_user_settings.sql` + pgTAP `supabase/tests/user_settings_test.sql`; Modify `Models/Profile.swift` or new `Models/UserSettings.swift` (read conventions first).

**Spec:** diff frame "Settings Hub".

Contract:
- Compact profile header row (52 avatar square, name 17pt, @username muted 12pt, small "Edit" secondary button — INERT for now w/ recorded note, Edit Profile screen is future).
- "Settings" group box (1px border, internal dividers): icon rows (18pt accent outline icons per the diff's SVGs → nearest SF Symbols) with VALUE PREVIEWS: Appearance → current palette name (wires to T5's picker); Notifications → "On/Off" from authorization status (→ existing NotificationPreferencesView); Home Gym → current gym name or "Not set" (→ existing gym editor sheet); Default rest timer → "m:ss" (→ new RestTimerSettingView: simple preset list 1:00/1:30/2:00/2:30/3:00 + custom stepper; persists).
- `user_settings` table (user_id pk → profiles cascade, default_rest_seconds int default 120, palette text default 'midnight' CHECK in 4, updated_at) owner-only RLS; repository (get-or-default, upsert) + pgTAP (owner rw, outsider denied, defaults).
- Sign out: centered secondary, accent700 (per diff).
- The existing avatar card/stat tiles: the hub frame REPLACES the old You-tab layout for the settings area but KEEP the stat tiles between profile row and Settings group (recorded deviation — canvas hub omits them; they're recent parity work and data-valuable; flag for designer).
- Solo workout rest timer (visual-parity-1 added one): read its current source of duration; wire it to default_rest_seconds.

CI + pgTAP green. Commit `feat(design): you settings hub + user_settings (rest timer, palette persistence)`.

---

### Task 3: Burpee Ledger

**Files:** Create `Features/Sessions/BurpeeLedgerView.swift`; Modify entry point (read p25 proof + GroupSessionLiveView/GroupView to find the designed entry — likely from the live session penalty banner and/or group screen); `Models/SessionRepository.swift` or new query file for aggregates.

**Spec:** proof image `.superpowers/proofs/p25-burpee-ledger.jpeg` (READ as image — fully rendered) + its canvas markup if ambiguous.

Contract: per-person crew debt list (avatar, name, owed count, paid state), totals, history of penalty events; data from session_participants penalty columns (burpees_owed etc. — READ the schema/engine RPCs; aggregate per user across the group's sessions; a single SQL view or repository query — no schema change unless required; if a paid/cleared concept doesn't exist in schema, render owed-only and record the gap for product). Match the proof's layout/kickers/tags. 44pt/tokens/etc.

CI green. Commit `feat(sessions): burpee ledger per canvas`.

---

### Task 4: Empty / offline / error states

**Files:** Modify `Features/Social/SocialTabView.swift` (+FriendsView), `Features/Home/HomeView.swift`, `DesignSystem/GSComponents.swift` (GSEmptyState, GSOfflineBanner, GSErrorToast/inline-retry as the proofs dictate), others as the proofs show.

**Spec:** proofs p30-empty-offline, p31-errors (READ as images) + canvas markup for exact copy.

Contract: "No crew yet" social empty state (illustration square + copy + CTA per proof); offline "reconnecting" pill (where the proof anchors it — likely global/topbar; wire to a simple reachability signal — check if any connectivity monitoring exists; if none, NWPathMonitor in a small service); inline error with Retry per p31 (apply to the screens the proof shows; voice-unavailable banner is 3e — skip). Only build states the proofs actually show; wire empties where data-empty conditions already exist (Social groups empty, Friends empty, Home no-sessions).

CI green. Commit `feat(design): empty/offline/error states per canvas`.

---

### Task 5: Palette activation (Arena / Ink / Modernist)

**Files:** Modify `DesignSystem/GSTheme.swift` (3 new palettes — token values TRANSCRIBED from the committed canvas `<style>` block's `.gs-theme[data-palette=...]` rules — exact hexes), `App/GymSyncApp.swift`/RootView (theme injection becomes dynamic), Create `Features/You/AppearanceView.swift`; uses T2's user_settings.palette for persistence.

**Spec:** proof p33-theme-picker (READ as image) + canvas palette CSS.

Contract: AppearanceView per proof (4 rows: tri-color swatch strip 22×40×3, name + subtitle e.g. "Charcoal · electric cyan", selected = accent border + check); selection updates environment theme LIVE (whole app re-renders — the gsTheme environment key already exists; add an @Observable ThemeStore seeded from user_settings, persisted on change, defaulting midnight; verify dark `preferredColorScheme` handling for LIGHT palettes — modernist is light: colorScheme must follow palette (add lightness flag per palette)); Settings Hub Appearance row shows current name + navigates here. DesignSystemTests: token spot-checks for the 3 new palettes (exact hex per canvas).

CI green. Commit `feat(design): palette activation — arena/ink/modernist live with persistence`.

---

### Task 6: Ship

- [ ] pgTAP + deno + iOS CI green; opus whole-branch final review (ledger minors roll-up); PR `--base master`; merge per standing authorization; watch deploys.
- [ ] Device-QA additions: settings hub navigation ×4, rest-timer setting respected in solo workout, palette switch live/persists/relaunch, notif screens match redraws, burpee ledger totals, empty/offline states.

## Self-Review Notes
- T1/T2 consume the diff spec (complete for those frames); T3/T4/T5 consume intact older proofs — truncation affects nothing in-scope (PTT excluded; addendum trio explicitly out until the full canvas arrives).
- Cross-task: GSToggle (T1) reused by nothing else yet; user_settings (T2) consumed by T5 (palette) + solo rest timer; ThemeStore (T5) read by Settings Hub row (T2 — build the row reading a palette-name provider with midnight fallback so T2 doesn't block on T5; document).
- Order matters: T2 before T5 (table exists), T1 anytime, T3/T4 independent.
