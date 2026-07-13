# Gym Sync — Designer Note #3 (2026-07-13)

Quick status + three small asks. Since your sign-offs: all six rulings are implemented and shipped.
Push notifications are now fully built and live (priming screen in onboarding, per-category
preferences under You → Notifications, and the delivery pipeline end to end).

## A. Bless or redraw — two screens shipped from assumptions

1. **Push permission priming.** You designed the microphone priming frame; a bell variant didn't
   exist, so we shipped your mic frame's exact pattern (accent icon square, flush-left headline
   "Never miss your turn on the bar", three benefit bullets, CTA stack) with a bell-badge icon.
   Bless as-is, or draw the push variant and we'll match it.

2. **Notification preferences screen.** Built entirely from your written spec (10 toggle rows
   with your exact labels, "All on by default —" header note, system-denied banner with Open
   Settings). No proof exists for it, which means our proof-vs-app comparison pipeline can't
   check it. When convenient, add it to the canvas so it's covered.

## B. One flow decision — denied-state re-entry

Your spec described a dedicated priming re-entry screen (denied variant with back button) reached
from the You tab. We shipped a simpler route: You → Notifications goes straight to the
Preferences screen, which shows the denied banner + Open Settings when notifications are off at
the OS level. The dedicated re-entry variant exists in code but is unreachable.
**Choose:** (a) bless the Preferences-with-banner route (we delete the unused variant), or
(b) keep your original flow (we wire the dedicated screen in). Either is fine — we just don't
want dead code without a decision on record.

## C. Queue confirmation

1. **PTT states are next-priority** — live voice push-to-talk is the phase after the current one.
   From your earlier canvas: the transmitting state ("Jordan is talking") exists; still needed
   are idle/connecting/unavailable states in both lobby and live session, and the
   denied-mic-permission button variant.
2. Please confirm the three addendum screens (series editor, activity feed, trend chart) are
   saved into the main canvas file — we're about to pull it and build all three.
3. From the first brief, we count as still open: home stat tile loading/empty/error states,
   the You-tab gym-setup chrome, and rest timers (partially covered by the solo in-progress
   frame's SET TIMER / REST AFTER tiles — confirm whether that's the full intent). Correct us
   if you consider any of these already delivered.

One small future ask to keep on your list, no urgency: the late-arrival "Roast" push action is
specced to open the soundboard "aimed at" the late lifter — the aimed/targeted soundboard moment
has no design yet.
