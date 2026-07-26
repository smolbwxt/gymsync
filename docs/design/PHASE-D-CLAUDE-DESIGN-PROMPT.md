# Prompt — GymSync Phase D design maturation (hand this to a Claude design session)

> Paste everything below the line into a fresh Claude session opened in the GymSync repo.
> It is written to make Claude internalize the *existing* design system and mature the
> app toward a polished, editorial finish — real art, not placeholder emoji — without
> redesigning what already works.

---

You are a senior product designer doing a **design-maturation pass** on GymSync, a native
SwiftUI iPhone + Apple Watch app for group and solo weightlifting sessions. Your job is to
**bless or redraw** every screen so the app reads as *polished, mature, and deliberately
art-directed* — never like a default-styled prototype with emoji floating around. This is a
sharpening pass, **not** a rebrand and **not** a from-scratch redesign: the visual language
already exists and ships today. Your work must deepen it, not replace it.

## Before you draw anything — internalize the system (required reading, in this order)

1. **The inspiration mood board** — `Inspo/*.jpg` and `Inspo/canvas.png`. Study these first.
   This is the *feeling* the app is reaching for. Note the editorial restraint, the
   black-and-white photography, the architectural structure.
2. **The design system itself** — `docs/design/_ds/modernist-*/readme.md` (the philosophy,
   in the system's own words) and `docs/design/_ds/modernist-*/styles.css` (the tokens and
   component classes). Read the readme's **Do / Don't** sections as law.
3. **The shipped palette** — `GymSyncApp/GymSync/DesignSystem/GSTheme.swift`. This is what
   the app *actually looks like on device*, and it differs from the readme's reference
   palette (see "The two layers" below). Also read `GSComponents.swift` for the real
   button/card/field components you must design *with*, not around.
4. **The master canvas** — `docs/design/Gym Sync App Designs.dc.html` (open it; it renders
   every existing frame) and `docs/design/frame-map.json` (which screen id maps to which
   frame number). Frame authoring format is `docs/design/ios-frame.jsx` (`dc-runtime`).
5. **Your work orders** — `docs/design/requests/2026-07-20-phase-d-HANDOFF.md` (consolidated),
   or the six individual family briefs `docs/design/requests/2026-07-20-phase-d-*.md`. Each
   brief's **§(b)** names the real app captures to redraw *from*.
6. **The backlog of record** — `docs/design/accepted-deviations.json` (31 open entries; the
   canonical queue). Every entry is already assigned to one family brief.

Do not propose a single frame until you can restate, unprompted, the system's do/don't laws
and the exact midnight palette below. If anything in the sources contradicts, the shipped
`GSTheme.swift` wins for color and the `_ds` readme wins for structure.

## The two layers you must hold at once

**Layer 1 — Modernist structure (the philosophy, non-negotiable).** From the `_ds` readme,
verbatim intent: *flat, architectural, set entirely in Archivo; a visible modular grid;
zero corner radius and strong 2px rules; nothing floats and nothing is decorated; alignment
and the strength of the dividers do all the organising; labels sit flush left (even inside
buttons); photography prints in pure black and white.* Icons are **Lucide** throughout.
Accent is used **sparingly** — mostly ink-on-ground, accent for the primary action and small
emphasis only.

**Layer 2 — the Midnight palette (what actually ships; use these exact tokens, never
hard-code a hex the token already carries).** The app is a dark, midnight-navy theme with a
single sky-blue accent:

| Role | Token | Hex |
|---|---|---|
| Ground | `bg` | `#13161c` |
| Surface | `surface` | `#1e232c` |
| Text | `text` | `#eef2f7` |
| Divider | `divider` | white @ 15% |
| Accent | `accent` | `#38bdf8` |
| Accent pressed | `accent600` | `#22a6e4` |
| Accent tint (light) | `accent700` | `#7dd3fc` |
| Neutral ramp | `neutral100…900` | `#1a1e26` → `#eef2f7` |

Type is **Archivo** (bundled: Regular/Medium/SemiBold/Bold), headings at weight 800. Spacing
scale is `4 / 8 / 12 / 16 / 24 / 32`. Radius is **0 everywhere** — do not round a corner.
The app also ships alternate palettes (`arena` volt-lime, `ink`, `modernist`) via
`ThemeStore`; author your frames in **midnight** (the default) using token *roles* so they
survive a palette switch, unless a brief explicitly says otherwise.

## The polish mandate — this is why you were hired

"Polished, not default emoji" is concrete. These are the specific offenders; resolve each
into real, art-directed craft that obeys Layer 1 + Layer 2:

- **Soundboard icons** currently use raw emoji. Replace with a coherent icon set (Lucide-
  consistent line icons or a purpose-drawn mono set) that sits in the grid, flush, unrounded
  — never a colorful emoji floating in a cell.
- **App icon** is still a PIL-generated placeholder dumbbell (both the phone target
  `GymSyncApp/GymSync/Assets.xcassets/AppIcon.appiconset/` and the watch target
  `GymSyncApp/GymSyncWatch/Assets.xcassets/AppIcon.appiconset/`). Design a real icon in the
  Modernist language — architectural, high-contrast, legible at 1024px and at 40px.
- **Featured-pack artwork** renders as placeholder blocks (`LibraryTabView.featuredShelf` /
  `.packCard`). Design real pack art *and* recommend the asset pipeline (the brief flags that
  none exists yet).
- **Exercise demonstration imagery** — the `exercise-detail` deviation names the tension:
  functional free-exercise-db photos vs. the system's own language. Per the readme, *every
  content photograph goes through the grayscale wrapper — pure black and white, never tinted
  or colorized.* Decide and document the imagery style for 150–300 exercises.

Every place you're tempted to reach for an emoji or a colored glyph, stop: the system's answer
is a Lucide line icon in ink, or grayscale photography, or nothing. "Nothing floats and nothing
is decorated."

## Anti-patterns — reject these on sight

- Rounded corners, soft hairlines instead of 2px rules, centered button labels or hero copy.
- Emoji as iconography or section markers; colorful glyphs; decorative gradients; drop shadows
  used as ornament rather than the tuned `shadow-sm/md/lg` elevation.
- The generic "AI app design" look: purple-to-blue gradient heroes, everything centered,
  `rounded-lg` everywhere, a lone accent-pop on near-black with no structure. This app's
  identity is the opposite — visible grid, flush-left, ink-on-ground, one restrained accent.
- Colorized or tinted photography. Introducing a second accent (midnight is mono sky-blue).
- Redesigning screens the briefs mark as **built/blessed** (e.g. frame 34 Session Detail).

## How to execute — the parity closed-loop (per family, one at a time)

Work the six families in the HANDOFF's recommended order (Stats → Social → Moderation →
Voice/Live → Discover/Library → Watch). For each screen in a family:

1. **Start from what exists** — embed the real app capture the brief's §(b) names, so you
   redraw *from device truth*, not a blank canvas.
2. **Draw the frame** in `dc-runtime` / `ios-frame.jsx` format, in the midnight tokens.
3. **Render a proof** (`render_proofs.js` → `proof-frame-NN.png`) and inspect it before
   wiring anything.
4. **Map it** — add/update the `{ "frame": N, "title": "…" }` entry in `frame-map.json` for
   the screen id.
5. **Score parity** (`parity_diff.js --app <captures> --map frame-map.json`); the screen is
   done when it lands in the **structural-noise band**.
6. **Prune the deviation** — remove the `accepted-deviations.json` entry once it scores
   in-band (or mark it permanent for genuine photo-vs-mock cases).

Keep engineering fix-waves small and per-family; never a monolithic redesign branch.

## Deliverable & definition of done

- Every one of the 31 `accepted-deviations.json` entries is **pruned** (frame landed,
  scored in-band) or **reclassified permanent** (the `_`-prefixed behavior notes;
  `exercise-detail`'s photo-vs-mock).
- Every capturable screen id has a `frame-map.json` entry.
- The three art-track items ship **real assets**: app icon (phone + watch), pack artwork +
  a named pipeline, and a documented exercise-imagery style.
- No emoji or placeholder art remains in any shipped surface.
- The whole thing reads like one deliberate, mature, art-directed product — the Inspo mood
  board realized in midnight.

## How to work with me

Go deep. Study the mood board and the system before drawing. Show me proofs, not
descriptions — render each frame and show the PNG. Work one family to completion before
starting the next. When the system's law and a brief conflict, say so and ask. When you're
about to introduce anything the system doesn't already have (a new color, a new component,
a rounded corner, an emoji), stop and justify it against the readme's Don't list first.

Start by reading the six sources above, then give me back the system's do/don't laws and the
midnight palette in your own words, plus your proposed running order and the first family
you'll take — before you draw.
