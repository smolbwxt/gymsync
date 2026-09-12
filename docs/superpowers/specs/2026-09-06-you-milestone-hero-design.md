# The You milestone hero — one display, weekly and lifetime — design

**Status:** SIGNED OFF by the owner on 2026-09-11 (round 12), with one addition — §4b, the interactive
model — whose build path is decision 7 (open). Was: for the owner's review before any You tab code. This is the document the congruence plan's T10.2 and its "does not decide" item 3 name
as the gate for the hero work. **Gate documents:** the milestone catalog
(`docs/superpowers/specs/2026-09-06-milestone-catalog.md` — the thirty rungs, the one currency, the render
notes, the Earth-ring hero), the design language (`docs/superpowers/specs/2026-09-05-design-language.md`), and
the docket rounds 4–9 on the You proofs (`docs/superpowers/plans/2026-09-03-field-report-docket.md`).
Render pipeline: `tools/milestone-render/` on `feat/milestone-render-pipeline` @ 0ab82e8 (not yet on master).

## Why

The owner, across the You proofs: *"keep the big weekly hero; add LIFETIME total; milestone graphics"* (round 3),
*"the render must NOT sit in a sectioned tile — blend into the hero as one display"* (round 6), and *"You: stats
hero great"* (round 5). Today `YouTabView.statsHero` is a live lifetime-volume headline with a plate meter and a
sparkline; the milestone graphics exist only as rendered frame sets and the catalog's paper. This design makes the
hero one display that carries three facts — this week, the lifetime total, and the next milestone the lifetime
total is climbing toward — with the render as the hero's own ground, not a picture in a box.

## 1. Vocabulary

| Word | Meaning |
|---|---|
| **Hero** | The full-width display at the top of You, under the identity header. One object. |
| **Weekly** | Volume moved this device-calendar week (the same week the streak and the goal strip use). |
| **Lifetime** | `profiles.lifetime_volume_lifted`, in the user's unit, with its plate count (lb ÷ 45). |
| **Ladder** | One of the catalog's three: HEIGHT (the stack against a landmark), WEIGHT (vessels poured full), DISTANCE (the line laid along a path). |
| **Rung** | One landmark on a ladder (thirty in all, ten per ladder), with its exact figure and source. |
| **Next rung** | The rung the lifetime total is climbing toward on the ladder where progress is highest — the catalog's rule. |
| **Frame set** | A rendered sequence for one rung at a range of progress values (plates stacked, vessel filled, ring closed). |

## 2. What the hero shows

Three layers, one composition, top to bottom:

1. **The week** — the headline number: volume this week in the user's unit, counting up on appear as today
   (`GSBarLoader`-style count), with the eight-week sparkline kept exactly as shipped. The kicker reads
   `THIS WEEK`. This is the fact the athlete looks at most, so it stays the largest type.
2. **The lifetime band** — one line under the week: `LIFETIME · 1,305,325 lb · 29,007 plates`. Honest-label
   rules from the catalog apply (rounded figures carry `about`; never a false precision).
3. **The next milestone** — the render is the hero's **ground**: it sits behind and beside the numbers as one
   picture, bleeding to the hero's edges, with the numbers set on top in the hero's own type. A single caption
   line on the render: `64% of the way to the Eiffel Tower · 1,083 ft` (progress on the next rung, the rung's
   name, its exact figure). Nothing sits in a sectioned tile; there is no card inside the card.

The hero is tappable as one object and opens the Stats tab's milestone page (existing route), where all three
ladders and every rung are listed; the hero itself never shows more than one rung.

## 3. Which rung, which ladder

The catalog's rule, verbatim: **the next rung is the one with the highest progress across the three ladders.**
Progress on a rung = lifetime total ÷ the rung's figure in the one currency (plates = feet × 8 for HEIGHT;
plates = pounds ÷ 45 for WEIGHT; plates = feet × 8 along the line for DISTANCE — the catalog fixes these).
Ties break toward the ladder the athlete last completed a rung on, then HEIGHT. When a rung is passed, the
hero shows the passed rung at 100 % for one session (the "made it" state, §5) and then advances.

## 4. The frame sets and how they are used

The pipeline renders each rung as a sequence at a fixed camera; the app ships a subset and interpolates:

| Ladder | Render | Frames shipped | Frame from progress |
|---|---|---|---|
| HEIGHT | `render_plates.py` — the stack against the landmark silhouette | 41 frames per rung (0 … 100 % in 2.5 % steps), 600 × 1500 alpha PNG, mid-tone lit | index = round(progress × 40); cross-fade to the neighbour over 350 ms when progress moves |
| WEIGHT | `render_vessel.py` — the glass shell filled with settled plates | 21 frames per rung (0 … 100 % in 5 % steps), the vessel's own camera | index = round(progress × 20); same cross-fade |
| DISTANCE | `render_plates.py` in line mode — the line along the path | 41 frames per rung | as HEIGHT |
| The Earth ring (DISTANCE rung 10, and the poster) | `render_earth_ring.py` — the face-to-face ring, r = 1.40 R, elevation 62° | 5 frames (0, 25, 50, 75, 100) | nearest frame; the ring is a poster, not a meter, per the catalog |

Assets: measured, not assumed. The pipeline's existing outputs are **~212 KB per 600 × 1500 alpha PNG**
(51 frames = 10 MB; the 240 × 1500 variant is 188 KB, the vessel 191 KB, the Earth ring 540 KB at 600 × 600),
not the ~90 KB an earlier draft of this spec claimed. Bundling every rung's frame set is therefore out: thirty
rungs at the steps above come to ~213 MB at 2× alone, and widening the step to 5 % still leaves ~130 MB.
**Recommended delivery (owner decision 6, open):** bundle only what the first open needs — the HEIGHT ladder's
rung 1 set (the first-week state, ~9 MB) and the Earth ring's five poster frames (~2.7 MB) — and serve every
other rung's frame set from a public Supabase storage bucket (`milestone-frames/<ladder>/<rung>/`), fetched on
first need and cached on device (one rung is ~9 MB; the hero only ever shows one). The buckets and the client
download path already exist for exercise media; a rung can be re-rendered without an app release. Fallback while
a set downloads: the bundled rung-1 frame at the current progress, with the caption already correct.
**Alternative (zero network):** ship one full-stack render per HEIGHT/DISTANCE rung and clip it to the progress
height at runtime (a stack *is* its lower portion) — ~30 × 2 × 212 KB ≈ 13 MB at 2× — but the cut loses the top
plate's face and WEIGHT's poured vessel has no clip equivalent; it is the second choice. Either way the frames
stay alpha-clean so the hero's own surface shows through, and the landmark silhouettes are part of the render
(the catalog's render notes), not separate SF or SVG assets — one image, one light, one style.

The render is **the ground, not a tile**: it is placed with `.aspectRatio(.fill)` inside the hero's bounds, the
hero's `surface` shows through its alpha, and a vertical scrim (`bg` → clear, 40 % height) sits under the
numbers so the week's headline stays legible on any frame. No border, no inner radius.

## 4b. The interactive model — owner round 12 (2026-09-11)

The owner: *"as a part of the spec let's remember that I want it to be interactive — in the widget, if a user
uses their finger to interact with it, we could spin the model."* ("Widget" here is the You hero in the app;
WidgetKit home-screen widgets accept no gestures, so this cannot be a home-screen widget.)

**What interactivity forces.** A frame set cannot be spun: a turntable at 36 angles × 41 progress steps × ~212 KB
is ~313 MB per rung. Spinning needs real geometry at runtime. That geometry is cheap for two of the three ladders:

| Ladder | Geometry at runtime | Asset per rung | Spin? |
|---|---|---|---|
| HEIGHT, DISTANCE | plates = one instanced cylinder (procedural, 0 bytes); the landmark = one low-poly mesh exported from the Blender pipeline as USDZ | ~0.3–1.5 MB (the pipeline already builds the geometry from code) | yes |
| WEIGHT (vessel) | the glass shell = one mesh; the poured plates are a rigid-body **simulation**, not real-time — bake the settled plate transforms per fill level (21 levels × ~50 plates × 7 floats ≈ 30 KB per level) and instance the same cylinder | ~1 MB mesh + ~0.6 MB of baked transforms | yes, phase 2 (the bake is new pipeline work) |
| Earth ring (poster) | stays a picture | 5 frames | no (per the catalog: a poster, not a meter) |

**Storage and memory, against the frame path.**

| | Frame sets (§4 as signed) | Interactive model |
|---|---|---|
| Bundle for thirty rungs | ~213 MB at 2× (impossible); ~9 MB per rung if streamed from storage | ~6–30 MB of meshes in total; plates cost nothing |
| Runtime memory while the hero is on screen | one decoded 600 × 1500 frame ≈ 3.6 MB (+ a neighbour during a cross-fade) | a live SceneKit scene — ~2 k instanced plates, one 10–20 k-triangle landmark, an image-based light — ≈ 30–80 MB, released when You leaves the screen |
| At rest | a bundled frame | a **snapshot the scene renders itself** (`SCNRenderer`) once per progress change, so the resting hero costs what a frame costs and the scene runs only while a finger is on it |
| Reduced motion | the nearest static frame | the snapshot, no spin |
| Look | Cycles renders, exactly the catalog's | SceneKit PBR + HDRI; a look-matching pass is required and is the main risk — expect "close", not identical |

Consequence for decision 6: **the interactive path dissolves the asset-budget problem.** With the resting hero
rendered from geometry there are no frame sets to bundle or stream for HEIGHT and DISTANCE; only the vessel keeps
frames until its bake lands.

**Level of effort (the owner's ask).** Build weeks of one Opus stream plus CI rounds:

| Path | Work | Estimate |
|---|---|---|
| A. Frames only (spec as signed, storage-streamed) | bucket + fetch/cache, frame interpolation, four ids | ~1 week |
| B. Interactive from the start for HEIGHT + DISTANCE; vessel as frames | pipeline exports landmark meshes as USDZ (2–3 days); SceneKit scene, spin gesture with inertia, snapshot-at-rest, reduced motion (4–5 days); look-matching against the Cycles renders (3–4 days); ids + proofs (2 days) | ~2.5–3 weeks |
| C. B plus the vessel bake | rigid-body bake export + instanced playback | +1 week, phase 2 |

**Recommendation:** B. About a week and a half more than A, it removes the 213 MB problem outright and builds the
thing the owner asked for rather than a picture of it. A's four catalog ids stay (`you-hero-*` capture the snapshot
at rest); one id is added, `you-hero-spinning` (a frame mid-gesture via a debug seam that sets the camera angle), so
FLOOR +5 instead of +4.

**Decision 7 (owner, open):** A, B, or C.

## 5. States

| State | What the hero shows |
|---|---|
| **Normal** | Week · lifetime band · next rung's frame at current progress · caption `N % of the way to <rung> · <figure>` |
| **First week, no lifetime** | Week (0 counting nothing) · lifetime band `LIFETIME · 0 lb` · the HEIGHT ladder's rung 1 (**You** — your own silhouette at 0 %) with the caption `Your first plate is the first foot.` |
| **Made it** (a rung passed since last open) | The passed rung at 100 %, caption `You made it: <rung> · <figure>`, once; the count-up on the week still runs; next open advances |
| **No milestone in reach** (lifetime beyond the last rung of every ladder — the equator) | The Earth ring at 100 % as a poster, caption `Around the world · 24,901 mi`, and the lifetime band carries a second figure: `× 1.3 around` (the catalog's "beyond the last rung" rule) |
| **Unit switch** (kg) | Every figure in the user's unit; plates stay plates (a 20 kg plate is the metric currency the catalog names); rung figures shown in metric with their sources' metric values |
| **Reduced motion** | No count-up, no cross-fade: the frame nearest current progress, static |

## 6. Where it sits and what moves

- **Identity header** above the hero, unchanged (name, handle, home gym, since; the gear opens Settings).
- **The hero** replaces `statsHero` in place; the widget grid below (STATS · ROUTINES & PROGRAMMING · COACH ·
  SHOP · SETTINGS, with B10's state sentences) is unchanged.
- The STATS widget's own line becomes `See where it's going.` (its number now lives in the hero; no figure
  twice on one screen).
- The streak chip stays the one gold on the page.

## 7. Data

No new tables. Reads: `profiles.lifetime_volume_lifted` (exists, trigger-maintained), this week's volume from
`set_logs` (the same read the Stats week view makes), the catalog's thirty rungs as a static Swift table with
their sources (`MilestoneCatalog.swift`, new, generated from the spec's tables — figures and URLs verbatim), and
`milestone_progress` **state** for the "made it" flag: one new column on `profiles`, `milestone_last_shown text`
(the rung key last shown at 100 %), additive, RLS unchanged.

## 8. Catalog and proof

Ids: `you-hero-normal` (rung mid-progress — the Eiffel Tower at 64 %), `you-hero-first-week`, `you-hero-made-it`,
`you-hero-beyond` (the Earth ring). Four ids, one capture each, FLOOR +4 at integration. Fixtures pin the
lifetime figure and the shown frame; no clock. The existing `app-tab-you` capture (live account) also changes and
is in the proof set. Proof cards before merge.

## 9. Sequencing

1. Merge `feat/milestone-render-pipeline` (the scripts, previews, manifests, `ASSETS.md`) — no app change.
2. Render and bundle the thirty rungs' frame sets at the shipped steps; measure the budget; commit the asset
   catalog.
3. `MilestoneCatalog.swift` from the spec's tables (with a test that every figure and source matches the spec).
4. The hero view, its states, the four catalog ids, the profile column, proof cards, one PR.

Files touched: `YouTabView.swift` (the hero), one new `MilestoneHeroView.swift`, `MilestoneCatalog.swift`, the
asset catalog, one migration, `CatalogHostView`/tests/frame-map for four ids. Nothing overlaps the goal-first or
social-card work.

## 10. What this design does not decide

1. The interactive Earth/moon stack you can spin (owner round 6: "future … parked as flavor") — not built.
2. Whether the hero animates the count-up on every appear or once per session.
3. Whether the Stats tab's milestone page gains the same renders (it lists the rungs today).
4. Lifetime reps/sets/bar-travel are still not computable (`increment_lifetime_volume` carries volume only);
   nothing here needs them — the ladders are volume-derived by design.
5. Asset delivery (§4): superseded by §4b — under path B there are no frame sets for HEIGHT/DISTANCE; under path A
   the storage-fetched sets stand. Falls out of decision 7.

## Owner decisions (2026-09-04 → 2026-09-11) — binding

1. Keep the big weekly hero; add the lifetime total; add milestone graphics.
2. The render blends into the hero as one display; it never sits in a sectioned tile.
3. One currency: plates from pounds; feet from plates; the catalog's thirty rungs with sources.
4. The next rung is the one with the highest progress; the Earth ring is the poster beyond the last rung.
5. Go to write this spec now, in parallel with the programming and social work.
6. **Signed off 2026-09-11 (round 12).**
7. The hero is interactive — a finger rotates, pans and pinches a 3D object (§4b). **Deferred by the owner
   (2026-09-11, round 13): on the to-do list, not prioritized; the current plan stands.** No physics: it is a
   3D image you orbit and zoom, not a simulation. The route when its turn comes: **Blender pre-builds every
   mesh** — the landmark, the plate column as stackable segments of 1 / 10 / 100 / 1,000 plates with the level
   of detail baked into each piece (full plate geometry in the small pieces, a normal-mapped profile in the
   large), and the vessel's settled pile exported in fill layers — and packages them as USDZ with USD Preview
   Surface materials, which RealityKit reads directly. The iOS side then only loads the pieces, stacks them to
   the plate count, and drives a camera: no mesh code in the app. Decide between path A and this route when
   the hero's turn comes, after a half-day check that RealityKit renders and captures on the CI simulator.
