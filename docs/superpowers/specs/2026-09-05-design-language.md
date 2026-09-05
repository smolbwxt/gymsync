# GymSync design language, as forged

Distilled 2026-09-05 from the proof rounds v1 to v7 (artifact
https://claude.ai/code/artifact/33a36a70-aff4-4413-98c4-4eb1768fb50f), the P2 restyle,
and the owner's rulings recorded in `docs/superpowers/plans/2026-09-03-field-report-docket.md`.
Future design iterations follow these rules; a proof that breaks one says so and why.

## 1. Surfaces (gs3D)

- Two raised surfaces only: the **static extruded card** (`.gs3DCard(cornerRadius:)`) for things you read,
  and the **sinking tappable** (`.gs3DCardStyle` / `.gs3D(face:lip:...)`) for things you press. A pressed
  control travels down by its lip height and its shadow disappears.
- The face is `raised3DFace`, the lip is `raised3DLip`. **Never** `theme.surface` or `theme.bg` as a face.
- **Furniture stays flat**: inputs, list rows inside a raised box, segmented controls, chips. Extrusion is
  spent on the object, not on every row inside it.
- Not everything is a card. One raised object per idea; strips (`surface`, 14 pt radius) for lines that
  belong to the card above them (coach line, debt strip, pump window).
- Nesting reads as **islands**: a folder is a raised island; the routines inside are raised rows on it, so
  folder boundaries read without borders.
- Radii: cards 24, small cards 16, strips 14, chips 999. Lips 6 to 7 pt on cards, 4 to 5 on tiles.

## 2. Colour

- **Default text everywhere.** Copy is `text`; secondary copy is `muted`; hints are `dim`.
- **Gold has exactly two jobs**: the week-streak number, and "the window is open, act now" (the check-in
  state). Nothing else is gold. On a screen where the gold button is showing, it is the biggest thing.
- **Accent is the user's pick** (sky by default) and is spent on: the one primary action per screen,
  an invitation line, the current item in a pager or turn strip, the talk pill while transmitting.
  A page never has two accent buttons.
- Green means done or present (checked in, recovered, goal met). Red is for errors only.
- Plates are competition colours (55 red, 45 blue `#2F6FD0`, 35 yellow, 25 green, 10 white, 5 grey,
  2.5 light grey) on any surface.
- **No decorative emoji.** SF Symbols for glyphs. Reactions and kudos emoji stay, because they are content.

## 3. Type

- Archivo throughout. Kickers are 10 to 11 pt caps with 0.1 to 0.13 em tracking and sit in `muted`;
  a kicker turns `text` only when it is the current one.
- A widget is named by a **word**, not a label: "Coach", "Stats", "Routines & Programming", "Membership".
  Under the word, one state line written as a sentence. The line goes accent only when it is an invitation.
- Numbers are tabular. The hero number is the largest thing on its page and has one small unit beside it.

## 4. Layout laws

- **One primary per screen.** One button in accent (or gold), everything else the raised face.
- **Same body, different frame** for solo and group. Crew presence adds: chat in the rail, the turn strip,
  the talk pill above the primary button, live video as an option. It never changes the body.
- **Questions above the fold, readouts below.** A question below a scroll gets answered by nobody.
  Questions come as one block with a SKIP in its header.
- **Anything that lives on a timeline is visible on Home, or one tap from the page where it is
  editable.** Sessions, series, block days, campaign deadlines: the training calendar shows them and
  opens the calendar and scheduling page.
- Badges point, they do not shout: a small accent count in the corner of the one widget that has
  something waiting.
- Three doors in a row at most. A door is a small raised tile with a glyph and two words.
- Real estate that the owner has lived in for a month is kept. Repurpose a widget before moving it.

## 5. The one button (Home)

- Reads the state and **names the next physical act**: START WORKOUT · START · PULL A (routine locked and
  loaded) · CHECK-IN OPENS 4:40 (quiet) · CHECK IN (gold) · JOIN THE SESSION.
- **It never starts a workout by itself.** Every state lands on the start screen with the routine
  pre-populated, so you can still do something different.
- When the primary is a crew state, "Start solo workout" remains as the quiet pill under it.

## 6. The talk control

- Neutral raised pill with HOLD TO TALK and a small accent waveform at rest; solid accent with
  TALKING · RELEASE TO STOP while transmitting. Same pill on every surface.
- It has its own home directly above the primary button. Never inside a sound rail, never an emoji.

## 7. Coach's voice

- One line, tappable, opens a seeded thread. First person ("take 185 × 8 today, then we climb").
- Safety notes first, plainly, in every tier, never behind a paywall.
- On Home and on the your-turn page, Coach is reachable in one tap.

## 8. Celebration and milestones

- **PR splash**: the headline first, big, in accent ("New personal record."), a line sweeps under it,
  then the lift and the number land with the ring. No kudos row on the splash.
- **Show, don't tell.** One milestone at a time in the You hero, blended into the hero, not tiled.
- Height ladder (stack of 45s vs a landmark drawn to the stack's scale) and mass vessels (a glass
  animal poured full of plates; fill = pounds lifted / animal pounds by volume). Visible plates are
  symbolic; the honest count goes in the label.
- Renders come from `tools/milestone-render/` (Blender, Cycles, transparent PNG). Frame index =
  round(progress × frames − 1); the app never draws plates itself.

## 9. Copy

- Sentence case for sentences; caps for kickers and buttons.
- A button says exactly what happens and keeps its verb through the flow (LOG SET 3, LOG SET 3 & PASS,
  START SET, CHECK IN, TALK IT THROUGH).
- Errors say what happened and how to fix it. Empty states invite ("Schedule your first lift").
- Weight convention: dumbbell and kettlebell per hand; barbell total including the bar; plate-loaded
  machine "total added" (the loader says "per side"); unilateral per side.

## 10. Settings

- Behind the gear on You. A setting that belongs to a flow also surfaces in that flow: gym equipment and
  starting weights in programming, the heart-rate monitor in the session, calendar sync in scheduling,
  the coaching code in Coach.

## 11. Process

- Screen inventory first (`.superpowers/sdd/*/screen-inventory*.md`), then proofs as interactive HTML at
  the same artifact URL, each publish labelled; the version picker keeps history.
- The owner picks; decisions are written to the docket round by round.
- A proof keeps every element the inventory found or names where it went.
- Then spec, plan, Opus (or lesser) implementers, task reviews, merge. Swift compiles only in CI.
