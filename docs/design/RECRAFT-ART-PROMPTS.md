# GymSync — Recraft art prompt sheet

Generating the Phase D **art track** (app icon, soundboard icons, pack artwork, exercise
imagery) in Recraft, in the app's real visual language. Read the two-track model first — it
determines every prompt below.

## The two art tracks (confirmed from `Inspo/`)

- **Track 1 — Ink illustration (Recraft's main job here).** Monochrome ink on light ground:
  either *fine vintage engraving* (classical physique, cross-hatch, navy — `Inspo/1840c5fd…jpg`
  "Act Like Men") or *loose single-weight line-art* (`Inspo/2c5e2239…jpg` "Old School
  Bodybuilding"). Subject: classical/Greco-Roman statuary and physiques. Aspirational,
  timeless, understated. This replaces every placeholder emoji/block.
- **Track 2 — Midnight UI + duotone photography.** Near-black ground, heavy Archivo sans,
  grayscale athlete photography with dark vignettes, one sky-blue accent. This is the
  shipped `_ds`/midnight chrome — Recraft only contributes the *photographic treatment*
  (grayscale/duotone), not the layout.

**Palette (use Recraft's color controls, never let it invent colors):**
midnight ground `#13161c` · surface `#1e232c` · ink/near-white `#eef2f7` · accent sky-blue
`#38bdf8`. Illustration ink where on light ground: deep navy `#16233d` or black on cream
`#f3f2f2`.

---

## STEP 1 — Build the custom Style first (do this once; everything inherits it)

In Recraft: **Styles → Create new style → upload reference images.** Create **two** styles.

**Style A — "GymSync Engraving"** (the workhorse). Upload the ink-illustration references
only — the classical-physique engraving + the line-art poses chart + any other statue/etching
JPGs in `Inspo/` (skip the app-screenshot and photo refs; mixing them muddies the style).
This style powers app-icon motif, pack art, exercise imagery, and soundboard icons.

**Style B — "GymSync Midnight Duotone"** (optional, track 2). Upload the dark app-screenshot
ref (`Inspo/18af21e…jpg`) — the grayscale athlete-in-vignette treatment. Use only if you need
photographic hero/pack imagery rather than illustration.

Once created, **select the style** on every generation below instead of re-describing it —
that's what keeps 300 exercise images looking like one set.

---

## STEP 2 — Per-asset prompts

For each, the format is: **[Recraft mode] · [style] · prompt · [settings]**. Paste the prompt
text; set mode/style/colors/background in the UI as noted.

### A. App icon (highest priority)

App icons must read at 40px, so keep the mark **bold and singular** — an engraving *flavor*,
not engraving *detail* (fine cross-hatch disappears at small size).

**Mode:** Vector (SVG) · **Style:** GymSync Engraving · **Background:** solid `#13161c`
**Colors:** `#eef2f7` line + `#38bdf8` single accent on `#13161c`

> Prompt (primary — barbell mark):
> *A single bold barbell viewed head-on, rendered as a clean high-contrast engraving-style
> emblem: thick even line weight, flat, geometric, perfectly centered, generous margin,
> pure symbol with no text. Near-white lines on a deep midnight-navy field, one thin
> sky-blue accent stripe. Architectural, timeless, legible at small sizes. No gradient, no
> bevel, no 3D, no drop shadow, no photorealism, no emoji.*

> Prompt (alternative — classical bust):
> *A Greco-Roman marble athlete's head in strict profile, rendered as a bold minimal
> engraving emblem with even line weight, flat and centered, pure symbol, no text.
> Near-white on deep midnight-navy, one restrained sky-blue accent. Classical, austere,
> legible at 40px. No gradient, no bevel, no 3D, no shadow, no emoji.*

Generate 6–8, pick the one that survives shrinking to 40px. Then re-export at 1024×1024 for
the phone target and a simplified variant for the **watch** target (round-friendly, even
bolder — the watch mask is a circle).

### B. Soundboard icons (kill the emoji)

A cohesive **set** in one pass so they match. Simplify the engraving into Lucide-weight line
icons — the app already uses Lucide, so these must sit beside them without clashing.

**Mode:** Vector (SVG) · **Style:** GymSync Engraving · **Background:** transparent
**Colors:** single ink color (`#eef2f7` for on-midnight use)

> Prompt:
> *A set of minimalist single-weight line icons in one consistent style: [drumroll, clapping
> hands, air horn, whistle, bell, flexed arm, dumbbell, stopwatch]. Even 2px stroke, flat,
> geometric, no fill, no color, centered in a square with even padding, transparent
> background. Cohesive icon family, no text, no emoji, no gradient, no shadow.*

Swap the bracketed list for the actual soundboard actions. Export each as SVG; recolor in-app
via the token, so they follow palette switches.

### C. Featured-pack artwork

One illustration per pack, themed to the pack (strength, hypertrophy, conditioning, etc.),
in the engraving language so the shelf reads as a curated set.

**Mode:** Raster (or Vector for flatter looks) · **Style:** GymSync Engraving
**Background:** `#1e232c` (surface) or transparent · **Colors:** navy/near-white ink + sparing `#38bdf8`

> Prompt (template — swap the subject per pack):
> *[A classical strongman lifting a stone / an atlas figure bearing a globe / a discus
> thrower] rendered as a fine vintage engraving with cross-hatched shading, monochrome deep
> navy ink, aspirational and timeless, composed for a wide card with the figure offset left.
> Muted, restrained, one small sky-blue accent detail. No text, no color wash, no modern
> gym equipment, no gradient, no photorealism.*

Keep the framing/lighting consistent across packs (all offset-left, same ink weight) so the
shelf is a family, not a grab bag.

### D. Exercise demonstration imagery (highest volume — 150–300)

This is where the custom Style earns its keep: one **prompt template** + the pinned Style =
a consistent library. Decide line-art (cleaner, scales to any size, tiny SVGs) over engraving
(richer but heavier) — line-art is the better call for hundreds of small cells.

**Mode:** Vector (SVG) · **Style:** GymSync Engraving · **Background:** transparent
**Colors:** single ink color

> Prompt (template — swap the exercise):
> *A single figure performing a [barbell back squat], shown mid-repetition from a 3/4 view,
> as a clean confident single-weight line drawing — anatomical but minimal, no shading, even
> stroke, centered with even margin, transparent background. Consistent proportions and line
> weight for a matched instructional set. No text, no color, no background scenery, no
> gradient, no emoji.*

Lock ONE view angle and figure proportion in the first few generations, then reuse verbatim
for every exercise so the set is uniform.

---

## STEP 3 — In-app placement note (don't skip)

The inspiration illustrations are **dark ink on light**, but the app is **midnight (dark)**.
So for in-app use, generate line-art on a **transparent background in a single ink color**,
then recolor it via the design token (`#eef2f7` near-white on midnight; or the accent for
emphasis). That way one asset works on any palette (midnight/arena/ink/modernist) without
regenerating. Keep the original dark-on-cream versions for marketing/App Store/poster
contexts where the classic engraving-on-paper look is wanted.

## How we iterate

I can't run Recraft or see its output — this is a generate → paste-back → refine loop. Run a
prompt, drop the results here, and tell me what's off (too detailed, wrong weight, reads
poorly at size, accent overused). I'll tune the exact wording, the Style reference set, or the
color controls. Start with the **app icon** (A) — it's the highest-visibility placeholder and
the fastest to judge.
