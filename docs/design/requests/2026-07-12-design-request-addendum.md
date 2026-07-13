# Gym Sync — Design Request Addendum (2026-07-12, follow-up to "next phases" brief)

Since the last brief, the app shipped a full design-parity pass: all five tabs, onboarding
(including the home-gym map screen and the "You're set" welcome), the solo workout recap, and a
custom bottom dock now follow your canvas. We can also now render your canvas directly for
pixel-level comparison, so future parity gaps will be caught faster.

Two kinds of asks below: decisions we need you to bless (or overrule — your call is final), and
three screens that exist in the app but have no proof yet.

---

## A. Decisions needing your sign-off

1. **Minimum tap size vs. drawn size.** Apple requires ~44pt touch targets. Small controls in
   your proofs (the username suggestion chips, the Approve/Veto vote buttons, ~24–26px tall as
   drawn) now render visibly taller (44pt) in the app. Options: bless the taller rendering, or
   redraw those controls so the visual box stays small while padding provides the touch area
   (we can do invisible-padding — say the word).

2. **Number formatting convention.** Your proofs mix comma-grouped ("48,120", "7,240") and the
   app currently uses compact notation ("48.1k", "7.2k") in stat tiles and the recap hero.
   Pick one convention (or a rule, e.g., compact in small tiles / comma-grouped in heroes) and
   we'll apply it everywhere.

3. **"Today's routine" card tap behavior.** Tapping it currently starts that routine immediately
   (with a brief picker flash). Alternative: open the routine picker paused, with today's routine
   preselected. Which did you intend?

4. **Recap "top set" semantics.** Should a FAILED attempt at the heaviest weight of the session
   count as the "top set" in the by-exercise breakdown, or only completed sets? (Penalty sets
   are already excluded.)

5. **Geofence circle tint.** Your home-gym map draws the radius circle at ~12% accent fill; the
   app ships 20%. Confirm 12% and we'll match it.

6. **Chat input: mic vs. context-sensitive send.** Your chat proofs show the idle input row with
   only the text field + arrow button, and the recording state shows an arrow-style control with
   an X — which reads as ONE context-sensitive button (tap = send, hold = record). The app
   currently ships a separate mic icon that swaps in when the field is empty. Confirm which you
   intend: (a) single arrow button, tap-to-send / hold-to-record; or (b) the mic/send swap as
   shipped. If (a), specify the discoverability treatment for hold-to-record.

## B. Screens that exist in the app but have no proof — please design

1. **Recurring series editor.** Editing a repeating session series: weekly day pattern with a
   per-day routine, an until-date (max 26 weeks), and Teams-style edit/cancel scope choices
   ("this occurrence" vs "this and following"). Today it's a functional but undesigned form.

2. **Activity feed.** A reverse-chronological list of completed sessions (own history), reached
   from Stats. Each entry: date, session type (solo/group), volume, sets, PR count.

3. **Per-exercise trend chart.** From Stats → an exercise: a time-series of top-set weight over
   months. Today a placeholder chart; needs your treatment for axes/points/accent usage
   consistent with the weekly-volume bars.

## C. For reference — already requested, still open

The seven features from the previous brief (push-notification priming + preferences, live voice
PTT states, palette-picker activation, home stat tile states, You-tab gym setup chrome, rest
timers) remain the priority queue. This addendum's items slot after them unless you disagree.
