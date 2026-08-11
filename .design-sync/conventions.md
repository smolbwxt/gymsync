# Onyx (GymSync) — build conventions

Onyx is a **committed-dark** system. Every screen sits on `var(--onyx-bg)` (#0A0B0D); set that
as the page/root background before composing anything — components are tuned for it and look
wrong on white. No provider or wrapper component is needed; the tokens are plain CSS custom
properties shipped in `styles.css`.

## Styling idiom: tokens + `ox-*` classes, never ad-hoc hex

Style your own layout glue with the Onyx tokens, not invented colors:

| Role | Tokens |
|---|---|
| Ground | `--onyx-bg` page · `--onyx-sf` cards · `--onyx-well` inputs · `--onyx-dvs` hairlines |
| Ink | `--onyx-tx` primary · `--onyx-t78` secondary · `--onyx-n700` labels · `--onyx-n500` tertiary |
| Accent | `--onyx-ac` (sky blue = "yours to act on") · `--onyx-onac` ink on accent |
| Semantic | `--onyx-gold` (reserved: check-in, debts, goals) · `--onyx-green` good standing · `--onyx-red` |
| Extrusion | `--onyx-face` button face · `--onyx-lip` the lip below it |
| Lifters | `--onyx-lift-you` `--onyx-lift-marcus` `--onyx-lift-dani` `--onyx-lift-tess` — one color per crew member, used consistently for their AvatarChip AND their plates on WeeksBar |
| Type | `--onyx-font` (system sans; k-labels are 10px/800 tracked uppercase — use `KLabel`) |

**The extrusion rule:** anything tappable sits proud of the surface — use `ExtrudedButton`
(or the `ox-btn` classes) for every control; never a flat text button.

**The color law — colors are meanings, never decoration.** Accent sky = actionable / presence.
Gold = debt, goals, streaks, check-in. Green = square with the crew / week made. Lifter colors =
member identity on avatars ONLY — never on plates, bars, or progress. Iron and the neutral ramp
carry everything else. One accent moment per view; if a screen reads colorful, it's wrong.

## Domain semantics (get these right)

- `WeeksBar` is the hero: one uniform IRON plate per routine the crew completed **together**.
  There is NO clip — bare sleeve is the work remaining (never ghost plates); the slot column
  carries the declared count, and `completed ≥ declared` = "ironclad" (green count and slots).
  The week count sits dead-center above its THIS WEEK label. Who-showed detail lives one tap
  deep, never on the bar.
- `Plate` is the crew's unit of shared effort — always iron, never one member's, never colored
  by identity. Lifter colors belong to avatars only.
- Debts (`CrewCard.members[].owes`) are owed **to the crew**, not to individuals; 0 = green check.
- Chat: `Bubble direction="out"` is accent-with-dark-ink (not Apple blue); tails only on the
  last bubble of a sender's run (`MsgRow endOfRun`); completed sessions appear in-stream as `SysLine`.

## Where the truth lives

Read `styles.css` (imports `tokens/` + component classes) before styling anything; each
component's API is its `<Name>.d.ts` and usage notes are in `<Name>.prompt.md`.

## Idiomatic composition

```tsx
<div style={{ background: "var(--onyx-bg)", padding: 16 }}>
  <BannerRail weeks={7}>
    <PixelBanner color="#6b4fd6" emblem="plate" chevrons={2} />
    <PixelBanner color="#c39a1e" emblem="chalk" />
  </BannerRail>
  <WeeksBar declared={7} sessions={[
    { color: "var(--onyx-lift-marcus)" }, { color: "var(--onyx-lift-dani)" }]} />
  <KLabel tone="gold">5 TO THE COLLARS</KLabel>
  <CrewCard members={[{ initials: "MK", color: "#E8834A" },
    { initials: "YO", color: "#3AB5F5", owes: 20 }]}
    routineName="CHEST DAY A" routineTime="FRI 5:30" />
</div>
```
