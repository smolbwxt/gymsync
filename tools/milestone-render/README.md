# Milestone renders

Headless Blender pipeline for the milestone artwork: a growing stack of 45 lb plates, and the
top-rung scene of a plate column bridging Earth to the moon. Everything renders to transparent
8-bit RGBA PNGs; the app paints its own background (`#0A0B0D`) behind them.

Built entirely from code — no `.blend` file is needed:

| Script | Renders |
|---|---|
| `render_plates.py` | The plate stack (hero column and tile variants) |
| `render_earth_moon.py` | Earth + moon + plate column (imports geometry/material/helpers from `render_plates.py`) |
| `render_vessel.py` | An animal-shaped glass vessel poured full of plates (rigid-body sim) |
| `render_earth_ring.py` | A ring of plates stacked face to face around Earth's equator (imports from `render_plates.py`, `render_earth_moon.py`, `render_vessel.py`) |

## Blender

The portable build, installed without elevation:

```
G:/Tools/blender-5.2.1-windows-x64/blender.exe        # Blender 5.2.1 LTS
```

There is **no** `C:\Program Files\Blender Foundation`. `run.sh` uses the path above by default;
override with `BLENDER=/path/to/blender.exe`. Renders use Cycles on OPTIX (RTX 5070), falling
back to CUDA/HIP/oneAPI/CPU, and EEVEE Next if Cycles cannot be set up. The engine and device
actually used are recorded in each `manifest.json` rather than assumed.

---

## The three sets

### 1. Plate stack — hero column, 2% steps

51 frames, frame `k` = `k` plates, plate thickness 0.16 (50 plates = 8.0 units tall, a 1:8 column).
Two widths that **share identical vertical framing**, so the app can swap between them freely and
every frame sits at exactly the same height and position; only the horizontal crop differs.

```bash
# 600x1500 -> tools/milestone-render/out/
G:/Tools/blender-5.2.1-windows-x64/blender.exe -b -P tools/milestone-render/render_plates.py -- \
  --out tools/milestone-render/out --frames 51 --size 600x1500 --samples 96

# 240x1500 -> tools/milestone-render/out-240/   (narrow, for the You hero)
G:/Tools/blender-5.2.1-windows-x64/blender.exe -b -P tools/milestone-render/render_plates.py -- \
  --out tools/milestone-render/out-240 --frames 51 --size 600x1500 --width 240 \
  --samples 96 --proof-frame 15 --proof-width 120
```

`--width` narrows the canvas **without touching the camera**: the camera is solved at the `--size`
width and only `resolution_x` changes afterwards, so it is a pure horizontal crop about the frame
centre. It refuses to widen, and refuses to produce a landscape canvas (which would hand Blender's
`sensor_fit = AUTO` to the width and silently rescale everything vertically).

### 2. Plate stack — tile, 2.5% steps (canonical tile set)

41 frames, frame `k` = `k` plates, plate thickness 0.08 (40 plates = 3.2 units, about 1:3 so the
full stack fits beside a ~180 pt landmark). 340×900 gives 4% margins top and bottom and ~10% at
the sides.

```bash
# 340x900 -> tools/milestone-render/out-tile/
G:/Tools/blender-5.2.1-windows-x64/blender.exe -b -P tools/milestone-render/render_plates.py -- \
  --out tools/milestone-render/out-tile --frames 41 --size 340x900 --thickness 0.08 \
  --samples 96 --proof-frame 15 40 --proof-width 170
```

`--thickness` scales the rim, hole bevel and outer chamfer *depths* with it, so a thinner plate
keeps its proportions rather than degrading into a washer with a full-depth groove. Radial
positions never scale — the plate diameter is always 1.0.

### 3. Earth to moon — top rung, 2% steps

51 frames, frame `k` = the column covering `k/50` of the surface-to-surface gap, always ending on a
whole plate. Frame 0 is Earth and moon with no column.

```bash
# 1200x1200 -> tools/milestone-render/out-earth-moon/
G:/Tools/blender-5.2.1-windows-x64/blender.exe -b -P tools/milestone-render/render_earth_moon.py -- \
  --out tools/milestone-render/out-earth-moon --frames 51 --size 1200x1200 \
  --samples 96 --proof-frame 15 50 --proof-width 400
```

Symbolic scale, deliberately not real: Earth radius 1.0, moon radius 0.30 at 4.5 Earth radii
(really ~60), plates 0.22 Earth radii across, 60 plates spanning the gap at frame 50. All shading
is procedural — no downloaded textures.

Each set takes well under a minute on the GPU (~0.4–0.7 s/frame), which is why the frame PNGs are
**not** committed; see `.gitignore`. Manifests and design proofs are committed.

### 4. Earth ring — plates stacked face to face around the equator

`--fills` values (not a frame count), like `render_vessel.py`: plates are stacked FACE TO
FACE — a roll of coins bent into a circle, each plate's axis tangent to the ring so its flat
face presses the next plate's face — and the ring advances by each plate's *thickness*, not
its diameter. The covered arc always starts at the terminator (the day/night line on the
stylised Earth, reused from `render_earth_moon.py`) and grows eastward; the uncovered arc
renders nothing (`hide_render`, no ghost plates); fill 1.0 closes the ring exactly.

```bash
# 1200x1200 -> tools/milestone-render/out-earth-ring/
G:/Tools/blender-5.2.1-windows-x64/blender.exe -b -P tools/milestone-render/render_earth_ring.py -- \
  --out tools/milestone-render/out-earth-ring --ring-diameter 0.13 --ring-radius 1.40 \
  --elevation 62 --fills 0.25 0.5 0.75 1.0 --size 1200x1200 --samples 96
```

Symbolic scale: Earth radius 1.0, ring radius 1.40 (pass 3 — floats clear of the surface as
a distinct halo; passes 1–2 used 1.06, hugging it). Plate **diameter** is the dial
(`--ring-diameter`, default 0.13 Earth radii — an earlier pass at 0.35 read as a hose, not
plates); plate **count** is derived from it and the ring radius via the real 45's
thickness/diameter ratio (thickness = 0.09 × diameter; `N = round(2π·ring_radius /
thickness)`, ≈752 at the defaults). Honestly closing a real equatorial ring at a real 45's
1.5 in thickness takes ~1.05 **billion** plates face to face (see `manifest.json`'s
`honest_math` block) — the symbolic count rendered is sized so the per-plate chamfer seam
(what sells "stack" rather than "tube") stays legible at 1200 px.

Camera **elevation** is steep — `--elevation`, default 62° above the equatorial plane, a
near-polar view where the ring reads as a halo/ellipse around the disk. This isn't just a
framing choice: a shallower 3/4 view (tried first, ~13°) let the ring's far side project
inside Earth's own silhouette, and that self-occlusion made fill 0.50 and 0.75 render
**pixel-identical** — confirmed the hard way, by image-diffing the renders. Going near-polar
(pass 2, 68°) fixed that, but left the ring radius at 1.06: `1.06 × sin(68°) ≈ 0.98`, just
*under* Earth's own radius, so the ring still grazed the limb and the uncovered arc visually
merged with the atmosphere's Fresnel rim instead of reading as a gap. Pass 3 lifts the ring
to `--ring-radius 1.40` so `ring_radius × sin(elevation) > earth_radius` holds with real
margin — the whole ring floats visibly clear of the planet at every fill level, reading as an
orbiting halo rather than a rim traced along the edge. That inequality is only an
orthographic approximation, though: `verify_ring_clears_limb()` checks it against the actual
finite-distance perspective camera (a ray–sphere test per ring point) and hard-fails if any
point is occluded — the brief's proposed 1.24 failed that real check (binary-searched the
true threshold to ≈1.34), which is why the shipped default carries margin above the formula's
number rather than sitting on it. `verify_distinct_renders()` still hashes every rendered
frame and hard-fails on any collision. `--azimuth` defaults to the terminator dawn line's own
angle and no longer needs to dodge occlusion the way it did at a shallow elevation.

Making the whole ring visible at once (pass 2) exposed a lighting issue: Earth's
single-direction key sun (correct for giving Earth a terminator) necessarily leaves roughly
half the ring's circumference unlit, dragging the whole-ring median color toward black. Fixed
the same way `render_vessel.py` fixed the identical problem for plates buried in shadow — a
small self-emission on the plate material at its own colour (`--emission`, default 0.48) —
rather than adding more directional lights, which only relocates the dark gap to between them.

Earth/atmosphere are reused, not reimplemented — imported from `render_earth_moon.py`; the
plate mesh comes from `render_plates.py` (its material is not reused as-is — see emission,
above); the preview compositing helper is imported from `render_vessel.py`.

---

## How the app picks a frame

Every manifest carries `steps` (the number of increments) and `frame_count`:

```
index = round(progress * manifest.steps)     // progress in 0…1 within the current rung
```

- 2% sets (`out/`, `out-240/`, `out-earth-moon/`): `steps = 50`, so `index = round(progress * 50)`.
- 2.5% set (`out-tile/`): `steps = 40`, so `index = round(progress * 40)`.

Show `frame_<index>.png`, zero-padded to two digits. When `progress` changes, **cross-fade between
the two neighbouring frames** rather than snapping. This is safe by construction: per-plate jitter
is seeded on the *plate index*, not the frame index, so plate `k` sits identically in every frame
it appears in and the camera never moves. Measured on the hero set, adding one plate changes only
the top ~4 plate-heights of the image (the new plate, its cast shadow, and the top face it now
covers); everything below is pixel-stable.

`frame_00` is a fully transparent image of the same size for the plate sets, so the app can
cross-fade in from empty.

---

## Flags (everything after the bare `--`)

`render_plates.py`:

| Flag | Default | Meaning |
|---|---|---|
| `--out DIR` | `tools/milestone-render/out` | Output directory (`--preview` adds `/preview`) |
| `--frames N` | `51` | Total frames; the tallest stack is `N-1` plates |
| `--size WxH` | `600x1500` | Render size in px; also the width the camera is solved at |
| `--width N` | = `--size` width | Narrow the canvas by horizontal crop only |
| `--thickness F` | `0.16` | Plate thickness; sets the stack aspect (50 × this, tall) |
| `--samples N` | `96` | Cycles samples (denoised) |
| `--preview` | off | Only frames 1, 25, 50 at half size |
| `--proof-frame K [K…]` | – | Also write `preview_<k>_<w>w.png` downscaled proofs |
| `--proof-width N` | `120` | Proof width; must divide the canvas to whole pixels |
| `--light-scale F` | `1.0` | Multiply all light energies (exposure tuning) |
| `--engine` | `auto` | `auto` \| `cycles` \| `eevee` |
| `--save-blend` | off | Also write `plates.blend` for hand tweaking |
| `--seed N` | `20260904` | Jitter seed |

`render_earth_moon.py` shares `--out`, `--frames`, `--size`, `--samples`, `--proof-frame`,
`--proof-width`, `--light-scale`, `--save-blend`, and adds `--only K [K…]` (render just these
frames) and `--no-plate-rim`.

`render_earth_ring.py`:

| Flag | Default | Meaning |
|---|---|---|
| `--out DIR` | `tools/milestone-render/out-earth-ring` | Output directory |
| `--ring-diameter F` | `0.13` | Plate face diameter, Earth radii. Plate count is DERIVED from this and `--ring-radius` (honest count is ~1.05 billion) |
| `--ring-radius F` | `1.40` | Ring radius, Earth radii — how far the ring floats off the surface. Must satisfy `ring_radius * sin(elevation) > 1.0`; checked against the real camera by `verify_ring_clears_limb()`, not just this formula |
| `--fills F [F…]` | `0.25 0.5 0.75 1.0` | Fraction of the ring filled, each written as `ring_<pct>.png` |
| `--size WxH` | `1200x1200` | Render size in px |
| `--samples N` | `96` | Cycles samples (denoised) |
| `--elevation F` | `62.0` | Camera elevation above the equatorial plane, deg — must satisfy the `--ring-radius` inequality above or the ring merges with the limb and some fills may render identically |
| `--azimuth F` | dawn line's own angle | Camera azimuth, deg |
| `--preview-width N` | `600` | Downscaled preview width |
| `--preview-bg HEX` | `0A0B0D` | Composite previews over this colour (app's real ground) |
| `--light-scale F` | `1.0` | Multiply all three (Earth) light energies (exposure tuning) |
| `--emission F` | `0.48` | Plate self-emission strength at #2F6FD0 (keeps the ring's far side from reading black) |
| `--save-blend` | off | Also write `earth_ring.blend` for hand tweaking |

---

## Notes on the output

- **Colour.** The plate blue is `#2F6FD0`, converted sRGB→linear before it reaches the shader, and
  the view transform is forced to **Standard** (not Blender's default AgX) so it survives to the
  PNG. Light energies were solved by sweeping `--light-scale` and measuring the rendered mid-tone:
  the stack barrel lands within ~3% per channel of `#2F6FD0`. Horizontal top faces read lighter and
  less saturated — correct for an up-facing surface — and are held just below clipping.
- **Transparent pixels are cleaned.** Cycles writes non-premultiplied RGBA, so the colour channels
  carry sampled light even where alpha is 0. After each render the script zeroes RGB under fully
  transparent pixels: it roughly halves the set (an empty `frame_00` is 15 KB instead of 178 KB)
  and prevents a colour halo if the image is scaled with alpha-unaware filtering.
- **Proof downscales are premultiplied.** Because of the above, a naive resize would drag silhouette
  edges toward black. The proof writer averages premultiplied values in linear light and
  un-premultiplies, using an exact integer up/down ratio — hence the "must divide to whole pixels"
  constraint on `--proof-width`.
- Nothing here touches `GymSyncApp/`.
