# Design Request — Next Phases (July 2026)

**Date:** 2026-07-12  
**From:** Engineering  
**To:** Design counterpart

---

## What has shipped since your last canvas update

Since the canvas was committed, three significant phases have landed in production:

1. **Design adoption (Midnight)** — the midnight palette, Archivo typography, and your component system (zero-radius cards, flush-left buttons, 2px dividers, GSTags, GSSectionHeader) have been applied across every existing screen. Every tab — Home, Library, Social, Stats, You, and the full sessions flow — now renders your system tokens verbatim. Design is authoritative; the app iterates toward the canvas via TestFlight.

2. **Phase 3b — chess-clock live session** — the real-time rotation flow is live. Participants take turns in a round-robin on the bar, the app manages whose turn it is, penalties for lateness are tracked (burpees owed), and the session ends with a recap. This built on your Lobby and Live Session canvas sections directly.

3. **Phase 3c — soundboard, voice messages, and the PR moment** — the in-session soundboard dock is live (tappable sound tiles, reaction bar), voice message recording and playback are in chat (hold to record in chat, bubble with waveform and duration), and the PR celebration moment fires in-session and in chat. These consumed your "Comms, soundboard & the PR moment" canvas section.

What follows is every surface that needs **new design work** — none of it is covered by the canvas yet.

---

## System constraints (binding on every surface below)

Your own system rules apply everywhere. For reference: midnight palette (`bg #13161c`, `surface #1e232c`, `text #eef2f7`, `divider white 15%`, `accent #38bdf8`); zero corner radius on all cards and controls; flush-left labels including inside buttons; 2px dividers between major sections; accent used sparingly; Archivo at all type sizes; Lucide-style iconography approximated with SF Symbols.

---

## Feature 1: Push Notification Permission Priming

**What it is.** Before the app can send push notifications (session reminders, turn alerts, friend requests, PR celebrations from crewmates), iOS requires explicit permission. The app needs an interstitial priming screen that runs just before the native iOS prompt — to explain value and improve grant rates.

**Where it lives.** This screen appears as a full-screen modal during onboarding (after the home gym step) and also as a re-entry point from the "Notifications" settings row in the You tab. It is a standalone, navigation-pushed screen — not a sheet.

**User-facing behavior and states.**

- **Default / pre-prompt state.** A single screen explaining what the user gains. Headline is motivational ("Never miss your turn on the bar"), not technical ("Enable push notifications"). Three benefit bullets: a session-start alert when the lobby opens, a "it's your turn" nudge mid-session, and a friend-request ping. Two CTAs at the bottom: primary "Turn on notifications" (triggers the native iOS prompt), ghost "Not now" (skips and dismisses).
- **After the native prompt — granted.** The screen dismisses and the user proceeds. No additional feedback needed; the You tab's Notifications row will reflect the active state.
- **After the native prompt — denied.** The priming screen should have a denied-state variant: a different headline ("Notifications are off"), a short line explaining the user can enable them in iOS Settings, and a single "Open Settings" button that deep-links to iOS Settings for the app. No "Not now" option in this state — there is nothing to defer.
- **Re-entry from You tab (notifications already denied).** Same denied-state as above, but the back button in the nav bar should be visible (user navigated here intentionally, not from a flow).

**Open design questions.**
- What icon or illustration anchors the priming screen? Your existing permission priming frame in the canvas (the mic one) uses an accent-filled square with an icon — does the same pattern apply here with a bell icon?
- Does the benefit list use checklist rows (accent check + label, as in your mic priming frame) or plain body copy?

---

## Feature 2: Notification Preferences Screen

**What it is.** A per-category opt-out screen for push notifications. Every notification category ships on by default; users can silence individual categories without disabling all notifications.

**Where it lives.** Tapping the "Notifications" row in the You tab's Settings section navigates here (full-screen, navigation-pushed).

**Notification categories that need toggle rows.**

| Category | Plain-English label |
|---|---|
| Friend requests | "Friend requests" |
| Session invites | "Session invites" |
| Session reminders (15 min before) | "15-minute reminders" |
| Lobby open | "Lobby is open" |
| Your turn | "It's your turn" |
| Partner PR | "Crew PRs" |
| Lateness chirp | "Late-arrival pings" |
| Session idle | "Idle session nudges" |
| Chat @mentions | "Mentions in chat" |
| Leaderboard passed | "Leaderboard changes" |

**States to cover.**

- **Fully enabled (default).** All rows toggled on. A brief header note: "All on by default — turn off any you don't need."
- **Mixed state.** Some categories off. Nothing special — just the list with mixed toggle states.
- **All off.** Consider whether a banner or footer copy should note "You won't receive any notifications" as a mild caution, without being preachy.
- **System-level denied.** If the user has revoked permissions at the iOS level, this screen cannot honour per-category toggles. It should show a banner at the top: "Notifications are disabled in iOS Settings — per-category preferences are saved but won't apply until you re-enable them." A button "Open Settings" links out.

**Open design questions.**
- Do the toggle rows use a standard iOS `UISwitch`-style control or a custom GS toggle? The canvas uses flush-left buttons throughout; native switches may read as out-of-system. Your call on whether to specify a custom 2-state pill or delegate to the system control.
- Should categories be grouped (social vs. session vs. chat) with GSSectionHeader separators, or is a flat list preferable?

---

## Feature 3: Live Voice PTT — In-Session and Lobby Controls

**What it is.** Phase 3e adds real-time voice to sessions. While a session is active (in lobby, voting, locked, or in progress), a voice room runs via LiveKit. Every participant joins listen-only; holding the push-to-talk button transmits. The user's music ducks while the voice room is active (join-scoped, not per-utterance in v1). There is no open-mic toggle — hold to transmit, release to stop.

**Note on canvas coverage.** Your existing "Comms, Soundboard & PTT" frame already shows the PTT transmitting state (the large round mic button in the bottom dock, the "TRANSMITTING — RELEASE TO STOP" kicker, and the pulsing ring) alongside the soundboard grid and the "Jordan is talking" active-speaker card. That frame covers the active/transmitting states. What is still needed is the full set of states across both surfaces (lobby and live session), including connection states, permission denial, and the voice-unavailable error banner already shown in your "Errors" frame but not yet wired into a complete PTT interaction model.

**Lobby — PTT zone.** The lobby currently has a participant list with check-in states. Voice will be active here too. You need to design:

- **Idle state (connected, mic muted).** A persistent control area — where does PTT live in the lobby? Is it a floating dock at the bottom, inline with the participant list, or a distinct row? The button should clearly read as "hold to activate" without being intrusive.
- **Active-speaker indicator on participant rows.** When another participant is transmitting, their row in the lobby list should show an animated speaking indicator. Your "Jordan is talking" card in the soundboard frame is one treatment; consider whether lobby rows show a subtler inline indicator instead.
- **Voice connecting state.** Between lobby join and room connection, there should be a brief connecting state. A small pill ("Connecting voice…") or a spinner somewhere unobtrusive — not a blocking overlay.
- **Voice unavailable in lobby.** If the token fetch or room join fails, the PTT control should show a degraded state with a "Retry" affordance. The "Voice unavailable" banner in your "Errors" frame is the right precedent; clarify how it surfaces in the lobby context specifically.

**Live session — PTT integration.** The live session view (both the Spotlight and Roster layouts) currently has the soundboard dock. PTT will live in or alongside that area:

- **Resting state (connected, mic muted).** The PTT button at rest — size, position, label, and visual treatment when not being held. Should it be always visible in the bottom dock alongside the soundboard tiles, or accessible via a tab/toggle within the dock?
- **Transmitting state.** Already covered by the canvas (pulsing ring, accent fill, "TRANSMITTING — RELEASE TO STOP" kicker). Confirm the button position within the live session layout if it differs from the soundboard-panel view.
- **Others transmitting.** The "Jordan is talking" card in the soundboard panel treats this as a card at the top of the panel. Does the live session's main view also surface a speaking indicator, or only the soundboard panel does?
- **Voice unavailable in-session.** Same "voice unavailable" banner treatment as lobby, contextualised within the session view. Your "Errors" frame already shows this banner — confirm it applies identically in both contexts.

**Microphone permission priming.** Your existing priming frame ("Talk to your crew mid-set") is already designed with a full-screen centered layout, accent-square mic icon, headline, three benefit bullets (checklist style), "Enable microphone" primary CTA, and "Not now" ghost CTA. This is complete. What is not yet designed:

- **Permission denied state.** If the user taps "Not now" and later tries to use PTT — or if the OS denies the permission — the PTT button in both lobby and live session should show a visually distinct disabled/denied state with an inline affordance to open Settings. Design this button variant.
- **First-time priming trigger.** The priming screen (already designed) fires on first voice join. After "Not now," the PTT button should show a muted/disabled state — design this variant.

**Open design questions.**
- In the live session layouts (Spotlight and Roster), is the PTT button always visible, or does it only appear when the soundboard panel is open?
- Should there be any visual feedback when voice ducking activates (i.e., user's music dips) — a brief music-note icon or just silence?
- The lobby and live session views have quite different layouts. Does PTT use the same control in both, or context-specific placements?

---

## Feature 4: Palette Picker — Appearance Screen (Activation)

**What it is.** The canvas already specifies the Appearance screen with all four palette swatches (Midnight, Arena, Ink, Modernist) and the selection state (accent border on the selected row, check icon). That design is complete. What is needed now is making this screen live — the "Appearance" row in the You tab currently shows "Midnight" as a static label. The picker needs to navigate to the Appearance screen and persist the user's selection so the whole app re-themes.

**This is primarily a design question, not an engineering one.** Specifically:

- The Appearance screen is designed for a navigation-push from the You tab. Confirm the back-button treatment: is it the standard nav bar back chevron (icon-only, flush with the left edge per your system) or a labeled "You" back?
- When a non-Midnight palette is selected and the user navigates back, does the You tab re-render immediately in the new palette, or is there a confirmation step?
- Are there any transition/selection micro-interactions on the swatch rows (beyond the border swap already shown)?

**Where it lives.** You tab → Settings section → "Appearance" row (currently labeled "Midnight" as a static disclosure row).

---

## Feature 5: Home Stat Tiles — Live Data

**What it is.** The Home screen canvas shows three stat tiles in a horizontal row: "Workouts this week," "Lifetime lbs," and "PRs this month." These were deferred from the design adoption phase because the data was not yet wired. They now need to be treated as live, data-driven components.

**Where it lives.** Home tab, below the Today's Routine card.

**States to cover.**

- **Loaded state.** Already shown in the canvas — three tiles with bold numerals and muted kicker labels. No changes needed for the happy path.
- **Loading state.** On first load or after a long offline period, what do the tiles show while data is fetching? Skeleton loaders (rectangular placeholders in neutral300), zero values with a spinner, or invisible until ready?
- **Empty / zero state.** A brand-new user has 0 workouts, 0 lbs, 0 PRs. Do the tiles render zeroes normally, or does the tile layout give way to a different first-session prompt?
- **Error state.** If the stats fetch fails (offline, server error), how do individual tiles degrade? Stale cached values with a muted "·" indicator, or dashes?

**Open design questions.**
- On the Home screen canvas, the "Today's routine" card and "🔥 New personal record" card appear above the stat tiles. If there is no routine scheduled for today and no recent PR, are those cards hidden and the tiles shift up? Does the Home screen have an empty/first-use state of its own?

---

## Feature 6: Gym Setup Screen — Persistent Saving

**What it is.** The onboarding flow currently includes a "Set your home gym" step (already designed in your canvas). However, the gym setup was deferred from the design adoption phase because it was onboarding-only and didn't persist through the Settings path. The "Home Gym" row in the You tab's Settings section needs to navigate to a functional gym-setup screen that lets users change their home gym after onboarding.

**Where it lives.** You tab → Settings section → "Home Gym" row, which navigates to a re-entrant version of the gym setup screen.

**States to cover.**

- **With an existing gym (most users).** The screen opens pre-filled with the user's saved gym name and (if available) the radius/location. There should be a way to clear and search for a new gym.
- **Searching.** Text input triggers a location search (same flow as onboarding). Results appear in a list below.
- **No gym set (fresh or cleared).** The same as the onboarding step — search-forward UI.
- **Location permission denied.** If location access is denied at the OS level, the search still works by text but the geofence check-in during sessions will not function. A small informational note (not a blocker) explaining this.
- **Saved confirmation.** After selecting a gym, the row in You tab should reflect the updated name. Does saving show a toast, a brief in-screen confirmation, or just navigate back?

**Open design questions.**
- Is the re-entrant gym setup screen visually identical to the onboarding step, or does it adopt the Settings chrome (nav bar with back button) rather than the onboarding chrome?

---

## Feature 7: Rest Timer — In-Solo-Workout

**What it is.** After logging a set during a solo workout, a rest timer counts down. The canvas's Live Session view shows a rest timer card (clock icon, countdown) as part of the workout view. This needs to exist in the solo workout context as well.

**Where it lives.** Solo workout screen (the active logging view), appearing after a set is logged.

**States to cover.**

- **Timer active.** Countdown display — duration, visual progress. Where does it sit in the layout? The canvas shows it as a card in the exercise rotation list; in solo mode the layout is simpler (your sets for the current exercise, input controls). Does the rest timer appear as a banner above the log input, a sticky card, or a pill in the nav bar?
- **Timer paused or dismissed.** User taps to dismiss before it expires — what happens? Does the timer disappear, or show a "Timer cancelled" state briefly?
- **Timer elapsed.** When the countdown hits zero, a haptic + brief visual change cues the user to start the next set. What does "zero" look like — accent flash, label change to "Rest complete," or just disappear?
- **No timer (user skips rest).** If the user logs another set before the timer expires, the timer should silently dismiss.

**Open design questions.**
- Is the rest timer duration user-configurable per exercise (shown in the canvas's exercise-detail screen as a setting), or is it a global default accessible from You or from the workout header?
- In the canvas's solo workout view, the rest timer card appears in the rotation; is its placement the same in the implemented solo workout layout?

---

## Already designed — no action needed

The following canvas sections are fully adopted by the app and require no further design work:

- **Buttons & backgrounds** — token definitions and component patterns
- **Home · Library · Social · Stats · You** — all five tab full-screen mockups (happy path)
- **Live Session** — Lobby (Step 1), Spotlight layout (2A), Roster layout (2B), Session Recap
- **Onboarding** — Sign in, Pick your username, Set your home gym, You're in
- **Routines & the exercise library** — routine list, exercise detail (Bench Press), exercise list
- **Solo workout** — active workout with log-set sheet (RPE stepper treatment adopted)
- **Exercise history** — per-exercise ledger view
- **Friends, groups & chat** — friends list, group list, chat view (text, image, reaction, typing indicator, voice note bubbles)
- **Scheduling, lobby & accountability** — schedule form (weekday chips, series rows), proposal cards (Approve/Veto/resolved states), lobby participant rows (check-in states), burpee penalty banner, room-code display
- **Comms, soundboard & the PR moment** — soundboard dock (2×3 grid), PTT transmitting state, "Jordan is talking" active-speaker card, voice note bubbles (incoming unplayed, outgoing played, recording composer), PR celebration full-screen moment
- **Empty, error, permissions & settings** — Empty & Offline state (Social), Errors state (voice unavailable banner, inline error toast, failed-to-load with retry), Permission Priming (microphone / "Talk to your crew"), Theme Picker (Appearance screen with all four palettes), Completed Session Detail (duration with edit, volume/sets/PRs tiles, participant recap)
