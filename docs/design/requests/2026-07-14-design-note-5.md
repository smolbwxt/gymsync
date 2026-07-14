# Gym Sync — Designer Note #5: voice is NOT a queue (correction) + curation surfaces

## 1. URGENT CORRECTION — live voice model (affects anything voice you're drawing now)

If any in-flight work treats voice as a **queue** (one speaker at a time, take-turns,
raise-hand, "next up"), please stop and redraw from this model:

**Live voice is a mixed room, Discord-style.** Every open mic in the session is heard by
everyone simultaneously — people talk over each other naturally. There is no queue, no
floor-holding, no speaking order. The server mixes all open mics.

What each person controls is only **their own mic**, via one dock button with two gestures
(product decision from today):

- **Tap** → mic toggles OPEN and *stays* open, hands-free (they're holding a barbell).
  Tap again → muted.
- **Hold** → classic walkie-talkie: open while held, muted on release.

### Dock states (your four existing frames mostly survive)
| State | Your frame | Change needed |
|---|---|---|
| Muted (idle) | "Hold to talk" | Copy must invite both gestures. Our interim: **"Tap to talk · hold to talk live"** — bless or improve. |
| Open via TAP (new state) | — | Reuses your Transmitting styling (accent fill, animated bars) with copy **"Mic open · tap to mute"**. Needs your blessing or a redraw. |
| Open via HOLD | "Release to stop" | Unchanged. |
| Connecting / Mic denied / Unavailable | your frames | Unchanged. |

Speaking rings on participant rows (accent ring + bars on whoever is audible) are unchanged
— they now just light up on multiple people at once.

## 2. Content curation surfaces (new frames requested — next phase after voice)

Per note #4's conventions: **separate file** (e.g. `sections/2026-07-curation.dc.html`,
under ~200 KB) and **plain HTML frames** (no ios-frame.jsx) so our pipeline can render them.

1. **Soundboard favorites ribbon** (in-session dock area): the user's 4 favorite sounds as
   tappable tiles (today's fixed airhorn/let's-go/ding/boo becomes personal), plus an
   expand affordance.
2. **Sound library sheet**: full catalog opened from the ribbon's expand — pick favorites
   (which 4, and their order) + tap-to-send any sound directly. Catalog entries carry an
   icon + display name.
3. **Library tab "Featured" section**: curated public routines (seasonal packs like
   "12 Days of Liftmas") shown above/beside the user's own routines — browse + one-tap
   "add to my routines". Publishing is curator-only; regular users only consume.

## 3. Housekeeping
- Note #4's conventions (split files, plain HTML) stand — this note assumes them.
- The voice correction (§1) outranks anything drawn under the queue assumption; the
  curation frames (§2) are next-phase, no rush relative to §1.
