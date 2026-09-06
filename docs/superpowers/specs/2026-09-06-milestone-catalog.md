# Milestone catalog — lifetime weight moved

**Date:** 2026-09-06
**Status:** spec, ready for build
**Scope:** three ladders of ten rungs (HEIGHT · WEIGHT · DISTANCE), one hero rendering brief, one selection rule.

---

## 0. What this is

Lifetime volume load (total pounds moved) is one enormous number that means nothing on its own.
This catalog turns it into thirty things a person can picture, in three families:

| Ladder | The question it answers | Idiom | Render |
|---|---|---|---|
| **HEIGHT** | How tall is the stack? | A column of 45 lb plates standing next to a landmark | `render_plates.py` (exists) |
| **WEIGHT** | What could you fill? | A glass vessel shaped like the thing, poured full of plates | `render_vessel.py` (exists) |
| **DISTANCE** | How far does the line reach? | The same column tipped over and laid along a path | `render_line.py` (**new**) |

### Inherited decisions (not re-litigated here)

- A plate is **45 lb**, **17.7 in / 450 mm** across, **1.5 in** thick.
- Renders are headless Blender → transparent 8-bit RGBA PNG; the app paints **`#0A0B0D`** behind.
- **One milestone shows at a time** in the You hero.
- **Show, don't tell.** Plates on screen are symbolic; the honest count lives in the label.

### The plate-thickness constant is a project decision, not a standard — pin it in one place

450 mm diameter is a real standard (IWF/IPF competition dimension, matched by every major
manufacturer — [Titan 45 lb bumper, 450 mm / 17.75 in](https://titan.fitness/products/45-lb-single-economy-bumper-plate)).
**1.5 in thickness is not.** Real 45s vary: [Titan's cast-iron 45 is 34 mm / 1.3 in](https://titan.fitness/products/45-lb-single-cast-iron-olympic-plate),
its bumper 45 is 74 mm / 2.9 in. 1.5 in sits inside the cast-iron range and is a reasonable
house convention — but **every number in this document scales inversely with it.** At 1.34 in the
owner's stack is 4,057 ft, not 3,626 ft; at 2.0 in it is 2,719 ft. Define `PLATE_THICKNESS_IN = 1.5`
in exactly one constant, derive everything from it, and never re-type a derived figure.

**After the face-to-face correction, plate *diameter* enters no arithmetic anywhere in this
catalog.** It sets only how a plate looks. Height and distance both consume thickness.

### Honest-label rules

1. The label always carries the **true** plate count and pounds. The symbolic count on screen is never quoted.
2. Never round a percentage up across an integer boundary. 99.6% is "99%".
3. Below 1%, print two significant figures — "0.0028%". Never "0%", never "<1%".
4. Show the denominator: "29,007 of 99,108 plates", not "29% there".

### Worked example — the owner, today

```
1,305,325 lb  ÷ 45 lb        = 29,007 plates
29,007 plates × 1.5 in       = 43,511 in = 3,626 ft   (standing or laid flat — same number)
```

| Ladder | Live rung | Progress |
|---|---|---|
| HEIGHT | Mount Fuji (12,388 ft) | **29.3%** — passed Burj Khalifa |
| WEIGHT | Saturn V (6,200,000 lb) | **21.1%** — passed a 747-8 at max take-off |
| DISTANCE | A mile (5,280 ft) | **68.7%** |

---

## 1. HEIGHT ladder — the stack against a landmark

> **Conversion, once.**
> `plates = height_ft × 12 ÷ 1.5 = height_ft × 8`  ·  `pounds = plates × 45 = height_ft × 360`
> **One foot of stack = 8 plates = 360 lb.**

| # | Thing | Real height (source) | Plates | Pounds | How to draw it |
|---|---|---|---|---|---|
| 1 | **You** | your profile height (6 ft 0 in worked) | 48 | 2,160 | Your own silhouette at the column's left, scaled from the profile — the only rung that is a mirror |
| 2 | **A giraffe** | 5.5 m / 18 ft ([Smithsonian, Movement of Life](https://movementoflife.si.edu/species/giraffe/)) | 144 | 6,480 | Giraffe in profile, head above the full column; the column reaches its shoulder at ~60% |
| 3 | **Statue of Liberty** | 305 ft 1 in / 92.99 m, ground to torch ([NPS](https://www.nps.gov/stli/learn/historyculture/statue-statistics.htm)) | 2,441 | 109,845 | Full statue *with* pedestal — the 305 ft figure includes it; a heel-to-crown drawing against a 305 ft label is a lie |
| 4 | **Eiffel Tower** | 330 m / 1,083 ft incl. antennas ([SETE](https://www.toureiffel.paris/en/the-monument/key-figures)) | 8,661 | 389,745 | Lattice silhouette; the blue column reads *through* the open ironwork — best contrast on the ladder |
| 5 | **Burj Khalifa** | 828 m / 2,716.5 ft ([official unveiling, 2010](https://www.prnewswire.com/news-releases/burj-khalifa-is-unveiled-to-the-world-and-its-official-height-is-828-metres-80657972.html)) | 21,732 | 977,940 | Setback spire silhouette; column beside it, both tapering to the same vanishing point |
| 6 | **Mount Fuji** | 3,776 m / 12,388 ft, Kengamine summit ([GSI Japan, via Britannica](https://www.britannica.com/place/Mount-Fuji)) | 99,108 | 4,459,860 | Fuji's one-stroke cone with the column planted at the tree line — the silhouette everyone knows |
| 7 | **Everest** | 8,848.86 m / 29,031.7 ft ([Nepal–China joint survey, 8 Dec 2020](https://kathmandupost.com/national/2020/12/08/it-s-official-mount-everest-is-8-848-86-metres-tall)) | 232,254 | 10,451,430 | Everest + Lhotse ridge line, not a generic peak; column rises from the Khumbu |
| 8 | **The Kármán line** | 100 km / 328,084 ft ([FAI](https://www.fai.org/page/icare-boundary)) | 2,624,672 | 118,110,240 | **Draw the sky, not an object** — a vertical gradient from horizon blue to black with the column crossing where it goes black |
| 9 | **ISS orbit** | ~250 mi / 400 km ([NASA](https://www.nasa.gov/international-space-station/)) | 10,560,000 | 475,200,000 | **Draw the orbit, not the station** — Earth's limb at the bottom, a dotted orbital track, the ISS as a deliberately oversized marker on it |
| 10 | **The Moon** | 238,855 mi / 384,400 km mean ([NASA](https://spaceplace.nasa.gov/moon-distance/en/)) | 10,089,235,200 | 454,015,584,000 | `render_earth_moon.py` as built — Earth r=1, moon r=0.30 at 4.5 Earth radii, column bridging the gap |

### Replacements and rejections

**All ten of the owner's rungs survive. Two need their *drawing* replaced, not their subject:**

- **Rung 8, Kármán line — replaced the object with the sky.** There is nothing at 100 km to
  silhouette. Every attempt to draw "the edge of space" as a thing produces a made-up thing.
  Draw the atmosphere instead: the column punching from blue into black *is* the milestone.
- **Rung 9, ISS — replaced the station with its orbit.** The ISS is 357 ft across. At a framing
  where a 1,320,000 ft column fits, the station is 0.027% of the frame height — sub-pixel. Drawing
  it at a readable size is a 4,000× scale lie sitting next to an honest column. The orbital track
  is honest and reads instantly.
- **Rung 1, "a person" → "you".** A fixed 6-ft figure is wrong for every user but one, and this is
  the most-viewed rung in the app. Drive the silhouette height from the profile.

**Gaps examined and deliberately left alone:**

- **Rung 2 → 3 is a 17× jump** (144 → 2,441 plates), the widest at the bottom. Left as is: it is
  103,365 lb of progress, roughly two to three weeks of ordinary training. A filler rung there
  would be crossed and forgotten inside a fortnight and would cost a slot the top of the ladder
  needs more.
- **Rung 9 → 10 is a 955× jump.** Nothing can fix this; the Moon is 955 ISS altitudes away.
  Handled in §5 instead: **the Moon is a ceremonial capstone the hero never auto-selects.** It is
  a poster, and the render already exists.

### Render notes for the whole ladder

- **One render set serves all ten rungs.** The plate column is symbolic (50 plates, 2% steps) and
  identical at every rung; the rung is expressed entirely by the silhouette beside it and the label.
  Do not build ten column renders.
- **Frame 50's column top must land exactly on the landmark's top.** Frame *k*'s top is then
  *k*/50 of the landmark height, and the progress reads without a single word of copy.
- Landmarks are flat SVG silhouettes drawn by the app over `#0A0B0D`, not Blender geometry — the
  column PNG has a transparent background precisely so this composites.
- **Never attempt a literal plate count above ~50.** At rung 6 the true column is 0.45 m wide and
  1,105 m tall — a 1:2,400 thread, invisible. The symbolic 50 is the whole point.

---

## 2. WEIGHT ladder — vessels poured full

> **Conversion, once.**
> `plates = pounds ÷ 45`  ·  fill fraction = `lifetime_lb ÷ vessel_lb`, clamped to [0, 1].
> The vessel fill is **continuous** (a count of visible plates, not a frame index) — see
> `render_vessel.py`, `fill_is_continuous: true`. Any step size renders.

Body-weight rungs are dynamic. Worked at a 180 lb body weight; **sort the ladder by actual mass at
runtime** rather than hardcoding the order — at 260 lb, rung 5 (26,000 lb) overtakes the T. rex.

| # | Vessel | Real mass (source) | Plates | Pounds | How it renders |
|---|---|---|---|---|---|
| 1 | **You** | 1× body weight (180 lb worked) | 4 | 180 | Glass human figure scaled from the profile; four plates in the feet — deliberately, comically few |
| 2 | **A grand piano** | 990 lb / 480 kg ([Steinway Model D Spirio\|r](https://www.steinway.com/spirio/spirio-r-institutions)) | 22 | 990 | Glass grand, lid closed; plates settle into the curved case and the leg columns fill last |
| 3 | **10× you** | 1,800 lb | 40 | 1,800 | Same human vessel, ten faint ghost outlines behind it; the front one fills |
| 4 | **A car** | 4,354 lb, average new US vehicle MY2024 ([EPA Automotive Trends](https://www.epa.gov/automotive-trends/highlights-automotive-trends-report)) † | 97 | 4,354 | Glass hatchback in 3/4 view; plates fill the cabin to the window line at 100% |
| 5 | **100× you — about a T. rex** | 18,000 lb (SUE, ~9 tons, [Field Museum](https://www.fieldmuseum.org/blog/sue-t-rex)) | 400 | 18,000 | Glass *T. rex* in SUE's mounted pose; tail and skull fill last — the reveal is that a hundred of you *is* a dinosaur |
| 6 | **A loaded semi** | 80,000 lb, US federal interstate gross limit ([FHWA](https://ops.fhwa.dot.gov/freight/sw/overview/index.htm)) | 1,778 | 80,000 | Glass tractor-trailer, side elevation; trailer fills first, cab last |
| 7 | **A blue whale** | up to 330,000 lb, 110 ft ([NOAA Fisheries](https://www.fisheries.noaa.gov/species/blue-whale)) | 7,333 | 330,000 | **Already built** — `render_vessel.py` with `assets/whale.glb`, 754 settled plates at full fill |
| 8 | **A 747-8 at max take-off** | 987,000 lb ([Boeing 747-8 ACAP](https://www.boeing.com/content/dam/boeing/v2/airports/acaps/747-8_Rev_D.pdf)) ‡ | 21,933 | 987,000 | Glass 747 in planform from slightly above; wings fill outward from the root, hump last |
| 9 | **Saturn V, fully fuelled** | 6,200,000 lb / 2.8 M kg ([NASA](https://www.nasa.gov/learning-resources/for-kids-and-students/what-was-the-saturn-v-grades-5-8/)) | 137,778 | 6,200,000 | Glass rocket standing vertical, 363 ft; the three stages fill bottom-up like a real propellant load |
| 10 | **The Eiffel Tower** | 10,100 tonnes = 22,266,688 lb ([SETE](https://www.toureiffel.paris/en/the-monument/key-figures)) | 494,815 | 22,266,688 | Glass tower; plates pour through the lattice and pile in the four feet, then climb — the callback to HEIGHT rung 4 |

† **Medium confidence.** The 4,354 lb MY2024 figure was read from a secondary summary of the EPA
2025 Automotive Trends Report; the EPA highlights page does not state it in text (it lives in
Figure ES-4). Read [420r26001.pdf](https://www.epa.gov/system/files/documents/2026-02/420r26001.pdf)
directly before shipping. Related EPA figures seen: 4,372 lb (MY2023), 4,441 lb (MY2025 preliminary).

‡ **Medium confidence.** Boeing's own ACAP PDF exceeded the fetch size limit; 987,000 lb MTOW was
confirmed only from secondary sources citing it. Verify against the PDF's weight table before ship.

### Replacements and rejections

- **Merged "100× body weight" with the T. rex (rung 5).** 100× a 120–260 lb body is 12,000–26,000 lb,
  which lands squarely on the elephant (13,000 lb) and SUE (18,000 lb) no matter what. Two adjacent
  rungs three points apart is a worse ladder than one rung with a two-part label. The merge also
  produces the best line in the catalog.
- **Cut the African elephant** (~13,000 lb) — subsumed by rung 5.
- **Cut the school bus** (~30,000 lb GVWR) — sits between rungs 5 and 6 with nothing to add, and
  "GVWR" is a rating, not a mass, so the honest number is squishy.
- **Cut the Space Shuttle orbiter** (~240,000 lb) — within 1.4× of the blue whale, and the whale
  vessel is already built and is the better render.
- **Cut the Statue of Liberty as a *mass* rung.** The popular "450,000 lb" is not an NPS figure.
  [NPS](https://www.nps.gov/stli/learn/historyculture/statue-statistics.htm) gives 176,000 lb of
  copper + 440,000 lb of framework = 616,000 lb for the statue, and 54,000,000 lb for the concrete
  foundation. Two defensible numbers 88× apart is a labelling trap. Liberty stays on HEIGHT only.
- **Added the Eiffel Tower at rung 10.** Without it the ladder tops out at Saturn V, which the
  owner is already 21% through after 1.3 M lb — the ceiling would arrive in about four years.
  Eiffel adds a 3.6× headroom step and gives the ladder a ~17-year top end.

### Symbolic plate count — the rule

The whale bake solved to **754 settled plates** at a plate diameter of 0.278 against a body length
of 6.0 units (4.6%). Do not carry that ratio across shapes: a boxy vessel at the same ratio would
swallow ~2,500 plates and read as gravel; a thin one would read as a handful.

**Target 700–900 survivors for every vessel and bisect on plate diameter in the bake to hit it.**
Granularity then reads identically at every rung, bake cost stays bounded, and the solved diameter
and final count go in the manifest, as the whale's already do.

### Fix before build

`out-vessel/manifest.json` has the blue whale at **300,000 lb**. NOAA says **up to 330,000 lb**.
Update the constant and re-bake, or the rung's honest label is wrong by 10%.

---

## 3. DISTANCE ladder — the line laid along a path

> **Conversion, once — face to face, not edge to edge.**
> Plates lie flat along the path, each advancing the line by its **thickness**:
> `plates = distance_ft × 12 ÷ 1.5 = distance_ft × 8`  ·  `pounds = plates × 45 = distance_ft × 360`
> **This is the same conversion as HEIGHT.** It is one column: standing, or tipped over.

*Rejected alternative: bar travel (reps × ~0.5 m ROM). It is tangible and it is a genuinely
different measurement — but it is a second currency the app would have to explain, it needs a rep
count the lifetime-pounds figure does not carry, and it makes DISTANCE incomparable with the other
two ladders. One currency: plates.*

| # | Thing | Real distance (source) | Plates | Pounds | How to draw it |
|---|---|---|---|---|---|
| 1 | **An Olympic pool** | 50 m / 164.0 ft ([World Aquatics facilities rules](https://www.worldaquatics.com/rules/facilities)) | 1,312 | 59,040 | Line of plates along lane 4, seen from the blocks; water surface reflects the blue |
| 2 | **A football field** | 360 ft / 120 yd, end line to end line ([NFL Rule 1](https://operations.nfl.com/rules-officiating/2026-nfl-rulebook)) | 2,880 | 129,600 | Low sideline camera; the line advances goal line to goal line, yard numbers for scale |
| 3 | **One lap of a track** | 400 m / 1,312.3 ft ([World Athletics C2.1](https://worldathletics.org/disciplines/road-running/marathon)) | 10,499 | 472,455 | Overhead oval, lane 1; the arc closes on itself — the first rung that visibly *comes back round* |
| 4 | **A mile** | 5,280 ft | 42,240 | 1,900,800 | Straight road to a vanishing point, the line running down the centre; a mile marker at the end |
| 5 | **Everest laid flat** | 29,031.7 ft ([2020 joint survey](https://kathmandupost.com/national/2020/12/08/it-s-official-mount-everest-is-8-848-86-metres-tall)) | 232,254 | 10,451,430 | The mountain tipped 90° onto the horizon with the line running its length — the pun *is* the render |
| 6 | **A marathon** | 42.195 km / 138,435 ft ([World Athletics](https://worldathletics.org/disciplines/road-running/marathon)) | 1,107,480 | 49,836,600 | The line as a race route through a stylised city, start banner to finish tape |
| 7 | **The Grand Canyon** | 277 river mi / 1,462,560 ft ([NPS](https://www.nps.gov/grca/planyourvisit/upload/life_geology.pdf)) | 11,700,480 | 526,521,600 | The line follows the Colorado's meanders on the canyon floor, seen from the rim |
| 8 | **The Appalachian Trail** | 2,197.9 mi ([Appalachian Trail Conservancy, 2026 official mileage](https://appalachiantrail.org/news-stories/2026-official-mileage/)) | 92,839,296 | 4,177,768,320 | The line threading a ridge profile from Springer to Katahdin; state boundaries as tick marks |
| 9 | **The Great Wall of China** | 21,196.18 km / 13,170.7 mi ([NCHA survey, 5 Jun 2012](https://www.chinadiscovery.com/great-wall/facts/how-long-is-the-great-wall-of-china.html)) § | 556,330,184 | 25,034,858,280 | The line running the wall's crenellations over hills — plates as the merlons |
| 10 | **Earth's equator** | 24,901 mi / 40,075 km ([NASA](https://science.nasa.gov/earth/facts/)) | 1,051,818,240 | 47,331,820,800 | **The hero — see §4** |

§ **Medium confidence on the source, high on the number.** 21,196.18 km is the People's Republic
of China National Cultural Heritage Administration's 2012 figure (all branches, all dynasties;
the Ming wall alone is 8,851.8 km). I could not reach an NCHA English primary page — the citation
above is a secondary reporting it. Label the rung "the Great Wall, all dynasties" so the 13,171 mi
figure is not mistaken for the Ming wall.

### Replacements and rejections

- **Cut the ISS altitude.** Under the thickness metric it is numerically identical to HEIGHT rung 9
  (10,560,000 plates). The same number cannot honestly be two different milestones.
- **Cut the length of Manhattan** (13.4 mi) — within 2× of the marathon, and parochial.
- **Cut Mars at closest approach.** The distance changes every opposition (~34.6–62 M mi); it is a
  moving number, and a milestone denominator must not move.
- **Cut the Sun (1 AU) and the heliopause.** 1 AU is 3.93 × 10¹² plates — 3,733× the equator. At
  the owner's rate that is a fill of 7 × 10⁻⁹. Not a milestone; a joke about milestones. On the
  bench with numbers in Appendix A if the app ever wants an Easter egg.
- **Added the Olympic pool, the track lap and a mile** at the bottom. The correction to
  face-to-face made the whole ladder ~12× more expensive: a football field went from 2,880 lb to
  **129,600 lb**. Without these three, a user's first DISTANCE milestone would be months away.
- **Added the Grand Canyon, the AT and the Great Wall** in the middle. They turn a 950× dead zone
  between the marathon and the equator into four even steps.

**Resulting gap profile — 2.2×, 3.6×, 4.0×, 5.5×, 4.8×, 10.6×, 7.9×, 6.0×, 1.9×.** This is the
best-spaced of the three ladders, and the final 1.9× is deliberate: *you have walked the Great
Wall; the equator is only twice as far.*

### Render notes for the whole ladder

- **New script, `render_line.py`** — reuse `render_plates.py`'s plate geometry, material, GPU
  setup, alpha cleanup and downscaler exactly as `render_earth_moon.py` and `render_vessel.py` do.
  Do not re-implement the plate.
- 50 symbolic plates laid face-to-face along a per-rung spline; frame *k* covers *k*/50 of the path
  and always ends on a whole plate — the existing manifest convention, unchanged.
- Camera low and near the line's start so the plates recede to a vanishing point; the covered arc
  is lit, the remaining path is a dim dotted guide.
- Per-plate jitter seeded on the **plate index**, not the frame index — so plate *k* sits
  identically in every frame it appears in and cross-fades stay pixel-stable below the growth edge.
  This is the rule that already makes the stack set safe to cross-fade; keep it.

---

## 4. The Earth-circumference hero — a ring of plates around the world

### The honest math

```
Equatorial circumference   24,901 mi          (NASA)
                        = 131,477,280 ft
                        = 1,577,727,360 in
÷ 1.5 in per plate       = 1,051,818,240 plates   ≈ 1.05 billion
× 45 lb                  = 47,331,820,800 lb      ≈ 47.3 billion lb
```

**The owner today: 29,007 plates = 3,626 ft = 0.687 mi = 0.00276% of the equator.**

> **Correction to the brief.** The brief's "~89.1 million plates ≈ 4.0 billion lb, owner at 0.03%"
> was the *edge-to-edge* calculation (÷ 1.475 ft per plate). Face-to-face is **11.8× more plates**
> and the owner's coverage is **0.0028%, not 0.03%** — an order of magnitude smaller. The owner's
> own corrected figures (1.05 billion plates, 47.3 billion lb) are confirmed exact.

That 0.00276% is **0.0099° of arc — 35.7 arcseconds.** On a 1200 px render of an Earth filling the
frame, the completed arc is roughly **0.1 px.** This governs everything below.

### Geometry

Follow the `render_earth_moon.py` conventions so the two space scenes read as one family:

| Parameter | Value | Note |
|---|---|---|
| Earth radius | `1.0` | matches `EARTH_RADIUS` |
| Ring plate diameter | `0.22` Earth radii | matches `PLATE_DIAMETER`; deliberately oversized so ribbing reads |
| Symbolic plates in a full ring | **200** | 1.8° of arc each; ring circumference 2π ÷ 200 = 0.0314 units of thickness, giving a 1:7 plate — within a whisker of the existing 1:6.25 proportion |
| Frames | 51 (0…50) | **exactly 4 plates per frame** — no rounding drift, matches the 2% convention |
| Ring radius | `1.11` Earth radii | each plate stands on its rim on the surface, so its centre sits one plate-radius (0.11) above it |
| Ring plane | the equator, on the stylised Earth's axis tilt | reuse `AXIS_TILT_DEG = 26.0` |
| Arc origin | the **terminator** (day/night boundary) | growth is **eastward**, into the light |

It is a **bent stack — a roll of coins around the equator**, not plates standing on their rims.
Each plate's flat face presses against the next, exactly as in HEIGHT and DISTANCE; the ring is the
same column bent into a circle. Plate faces are radial to the ring's path, so the viewer sees the
ribbed *edge* of the roll from outside and the stacked faces where the arc curves away.

### Camera

- 3/4 view: elevation **+22°** above the equatorial plane, so the ring reads as an ellipse rather
  than collapsing to a line; azimuth chosen so the **terminator sits near frame centre** and the
  growing arc runs toward the lit limb.
- Lens **60 mm** (matches `CAM_LENS_MM`), frame margin 0.05.
**The gap is the near-side path, not the far side.** A ring of radius 1.11 around a sphere of
radius 1 projects to an ellipse with semi-minor axis 1.11·sin(elevation). That stays inside the
disc of radius 1 — i.e. the far half of the ring is hidden behind the globe — for **any elevation
below 64.3°**. Above 64.3° the far arc does clear the pole, but by then the camera is looking
almost straight down the axis: the ring reads as a flat circle, the terminator no longer runs
vertically, and the 3/4 "reaching around the world" read is gone. There is no camera that gives
you both. Do not try to frame around this.

Instead: the **completed arc** is solid, lit plates on the near hemisphere, and the **gap** is the
rest of the near-side path drawn as a dim dotted guide running from the arc's leading edge to the
limb and reappearing on the other side. The far half being hidden is correct and sells the sphere.
At the owner's fill the arc is a 35.7-arcsecond sliver at the terminator and the dotted guide is
effectively the whole visible ring — which is exactly the honest picture.

### Light

- **Key** from the sun direction — it defines the terminator, which is the arc's origin. Non-negotiable.
- **Rim** from behind and slightly left, to separate Earth's limb from the transparent background.
- A small **fill on the ring only**, so plate ribbing on the night side still reads as plates and
  the arc does not vanish where it starts.
- Transparent RGBA output over `#0A0B0D`; view transform forced to **Standard**, not AgX; plate
  blue `#2F6FD0` converted sRGB → linear before the shader — same as every other set.

### How the label reads

At the owner's 0.00276%:

> **3,626 ft of plates around the Earth**
> 29,007 of 1,051,818,240 plates · 1,305,325 lb of 47,331,820,800
> **0.0028% of the equator**

That is honest, and it is unusable as a progress hero. Frame 0 is what renders — an empty ring —
because 0.0028% is 0.14% of a single 2% step. The user sees a bare Earth and a number with three
leading zeros.

### Recommendation — what the hero shows instead

**The Earth ring is a poster, not a progress bar.** Ship it as the DISTANCE ladder's ceremonial
top card: reachable from the full catalog, used as the section header art, never auto-selected by
the hero. Same treatment as HEIGHT rung 10, the Moon.

For the owner today the You hero should show **DISTANCE rung 4 — a mile, 68.7%**: a line of plates
down a straight road, two-thirds of the way to the marker. Non-silly, nearly complete, and it will
fire a celebration within weeks. The equator becomes a live rung only after the Great Wall
completes, at 25 billion lb.

The general form of "what to show instead" is §5.

---

## 5. Which ladder when

**One milestone at a time.** The hero picks one rung, from one ladder, and the user can override.

### Default

**HEIGHT.** It is the only ladder whose first rung — your own height, 48 plates, 2,160 lb — lands
inside a single session, and rung 1 is a mirror of the user. A new account sees itself.

### The rule, evaluated at every session close

1. For each ladder, find the **lowest incomplete rung** and its progress *p*.
2. **Celebration override.** If any rung completed since the hero was last seen, show that rung at
   100% for the next three app opens, whichever ladder it belongs to. A completion is the only
   thing allowed to interrupt.
3. Discard any ladder whose *p* < **0.02**. Below one full frame step there is literally nothing
   rendered — frame 0 is empty — and the label reads as zero. (Exception: a brand-new account with
   no completed rung anywhere shows HEIGHT rung 1 at 0% with "48 plates to go".)
4. **Never auto-select a ceremonial capstone:** HEIGHT rung 10 (the Moon) or DISTANCE rung 10 (the
   Earth ring). If a ladder's only remaining rung is its capstone, that ladder is out of the
   rotation until the user reaches it for real.
5. Of what survives, show the ladder with the **highest** *p* — the one nearest a completion. Ties
   go to the ladder not shown last time.

**The owner today:** DISTANCE 68.7% > HEIGHT 29.3% > WEIGHT 21.1% → the hero shows **a mile**.
When the mile completes, the celebration fires, then HEIGHT/Fuji takes over at 29.3%.

### Why "highest *p*" and not a fixed schedule

Highest-*p* makes the hero drift toward whatever is about to pay off, so completions arrive in a
steady rhythm instead of clustering. It also self-corrects for any user's mix: a heavy low-rep
lifter climbs WEIGHT fastest, a high-volume lifter climbs HEIGHT and DISTANCE fastest, and neither
needs a special case.

### How a user flips

- **Horizontal swipe** on the hero cycles HEIGHT → WEIGHT → DISTANCE. Three page dots under the
  hero show which is up. This is the only gesture; it is discoverable and it does not need copy.
- **Long-press** opens the full catalog: three columns of ten. Completed rungs solid with their
  date, the current rung with its live percentage and denominator, future rungs dimmed with their
  plate and pound cost showing. This is where the Moon and the Earth ring live, viewable any time.
- A manual choice **pins for the session** and persists until the next completion. A completion
  always wins — that is rule 2, and it is the one interruption users forgive.

### What changed because of the face-to-face correction

The correction made DISTANCE **11.8× more expensive** (1.475 ft per plate → 0.125 ft per plate).
Under edge-to-edge the owner's 29,007 plates reached 8.10 mi — past Everest-laid-flat and a third
of the way to a marathon. Face-to-face, the same plates reach 0.687 mi: 68.7% of one mile. A
football field went from 244 plates / 10,980 lb to **2,880 plates / 129,600 lb**. Consequences
carried into this spec:

- DISTANCE lost its three cheapest rungs' worth of headroom and gained three new bottom rungs
  (pool, track lap, mile) so a new user's first DISTANCE milestone stays inside the first month.
- DISTANCE is no longer the "easy" ladder. It now sits between HEIGHT (cheapest bottom, 2,160 lb)
  and WEIGHT (cheapest top, 22.3 M lb) — which is what makes the highest-*p* rule produce a
  genuine rotation rather than always naming the same ladder.
- The Earth ring moved from "silly for a while" to "silly for any human", which is why §4 demotes
  it to a poster outright rather than gating it behind a threshold.

---

## Appendix A — bench rungs (sourced, not shipped)

| Ladder | Thing | Figure | Plates | Pounds |
|---|---|---|---|---|
| HEIGHT | Red Bull Stratos jump altitude | 127,852 ft | 1,022,816 | 46,026,720 |
| HEIGHT | Geostationary orbit | 22,236 mi | 939,248,640 | 42,266,188,800 |
| WEIGHT | African bush elephant (bull) | ~13,000 lb | 289 | 13,000 |
| WEIGHT | School bus (Type C GVWR) | ~30,000 lb | 667 | 30,000 |
| WEIGHT | Space Shuttle orbiter | ~240,000 lb | 5,333 | 240,000 |
| WEIGHT | Statue of Liberty (statue only, NPS) | 616,000 lb | 13,689 | 616,000 |
| WEIGHT | Statue of Liberty (incl. concrete foundation, NPS) | 54,616,000 lb | 1,213,689 | 54,616,000 |
| DISTANCE | Length of Manhattan | 13.4 mi | 566,016 | 25,470,720 |
| DISTANCE | Mars at closest approach | ~34.6 M mi | 1.46 × 10¹² | 6.58 × 10¹³ |
| DISTANCE | Earth to the Sun (1 AU) | 92,955,807 mi | 3.93 × 10¹² | 1.77 × 10¹⁴ |
| DISTANCE | Voyager 1 at the heliopause | ~122 AU | 4.79 × 10¹⁴ | 2.16 × 10¹⁶ |

## Appendix B — build checklist

- [ ] Define `PLATE_THICKNESS_IN = 1.5` in one place; derive all thirty rungs from it.
- [ ] Correct `render_vessel.py`'s blue whale from 300,000 lb to **330,000 lb** and re-bake.
- [ ] Verify the EPA MY2024 average vehicle weight (4,354 lb) against 420r26001.pdf, Figure ES-4.
- [ ] Verify the 747-8 MTOW (987,000 lb) against Boeing's ACAP weight table.
- [ ] Write `render_line.py`, importing plate geometry/material/GPU/alpha/downscaler from `render_plates.py`.
- [ ] Nine new SVG landmark silhouettes for HEIGHT, each scaled so frame 50's column top meets the landmark top.
- [ ] Nine new glass vessels for WEIGHT; bisect plate diameter per vessel to 700–900 survivors.
- [ ] `render_earth_ring.py` — 200 symbolic plates, 51 frames, 4 plates/frame, arc from the terminator eastward.
- [ ] Hero selection rule (§5) with the 2% floor and the capstone exclusion.
