"""
GymSync milestone -- a ring of 45 lb plates reaching around the Earth's equator.

The plates are stacked FACE TO FACE, like a roll of coins bent into a circle: each
plate's axis points TANGENT to the ring (along the direction of travel), so its flat
face presses against the next plate's face. The ring advances by each plate's
THICKNESS, not its diameter -- N plates of thickness t close the ring exactly when
N * t == the ring's circumference (2 * pi * RING_RADIUS). Plate DIAMETER is the primary
dial (`--ring-diameter`, default 0.13 Earth radii -- pass 1 used 0.35 and it read as a
hose, not plates); N is DERIVED from it via the real 45's thickness/diameter ratio.

The filled fraction of the ring is the progress bar. The covered arc always starts at
the terminator (the day/night line) on the lit side of the stylised Earth and grows
EASTWARD (increasing angle, the same sense as Earth's own prograde rotation) around
the globe; the uncovered arc renders nothing at all -- no ghost plates -- so the gap
itself reads as "not there yet". At fill 1.0 the ring closes.

Camera elevation is steep (`--elevation`, default 62 deg above the equatorial plane) --
pass 1 used a 3/4 view (13 deg) where the ring's far side projected inside the planet's
silhouette, making fill 0.50 and 0.75 render pixel-identical. Pass 2 fixed that by going
near-polar (68 deg) but left RING_RADIUS at 1.06 -- just proud of the surface -- which
(1.06 * sin(68) = 0.983, just UNDER 1) still grazed the limb: the uncovered arc merged
with the atmosphere's own Fresnel rim highlight instead of reading as a gap. Pass 3 lifts
the ring clear instead: `--ring-radius` (default 1.40 Earth radii) with `--elevation`
lowered to 62 so `RING_RADIUS * sin(elevation) > EARTH_RADIUS` for every point on the
ring, not just the ones near the limb -- so the WHOLE ring floats visibly clear of
Earth's silhouette, reading as a halo orbiting the planet rather than a rim traced along
its edge. The brief's proposed 1.24 (1.24 * sin(62) = 1.095 > 1) is that inequality's
ORTHOGRAPHIC approximation -- verify_ring_clears_limb() checks the claim against the
REAL, finite-distance perspective camera instead of trusting the approximation, and at
1.24 it failed (the antipodal ring point stayed occluded); a binary search against the
actual camera found the true threshold near 1.34, so the default carries ~5% margin over
that empirical number, not the formula's number. See the render report's pass 3 section
for the search. verify_ring_clears_limb() hard-fails if any ring point is occluded, so a
future `--ring-radius`/`--elevation` combination that regresses this cannot ship
silently; verify_distinct_renders() still hashes every rendered fill and hard-fails on
any collision (belt and suspenders -- clearing the limb makes fill collisions
structurally impossible too, since occlusion was pass 2's collision cause).

    blender -b -P tools/milestone-render/render_earth_ring.py -- \
        --out tools/milestone-render/out-earth-ring --ring-diameter 0.13 \
        --ring-radius 1.40 --elevation 62 --fills 0.25 0.5 0.75 1.0 \
        --size 1200x1200 --samples 96

Symbolic scale, deliberately not real: Earth radius 1.0 (matching render_earth_moon.py),
ring radius 1.40 (pass 3 -- floats clear of the surface rather than hugging it; pass 1/2
used 1.06). A real 45 lb plate is 17.7 in across and ~1.5 in thick (thickness/diameter
~= 0.085, rounded to 0.09 here); honestly closing a real equatorial ring at that
thickness takes on the order of 1.05 BILLION plates (see the manifest's "honest_math"
block) -- the ~752 rendered at the default diameter and ring radius are symbolic, sized
so the chamfered seam between each one (what sells "stack" rather than "tube") is still
legible at 1200 px.

Earth's material, atmosphere shell and the plate mesh/material are all reused, not
reimplemented: Earth + atmosphere come from render_earth_moon.py's
make_earth_material()/make_atmosphere_material()/add_sphere(), and the plate itself is
render_plates.py's revolved 45-lb profile (rim, centre hole, outer chamfer) recoloured
to the same #2F6FD0. This script does not modify any of those three files -- it only
imports them.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import sys
import time

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render_plates as rp        # noqa: E402  (needs the path fix above)
import render_earth_moon as rem   # noqa: E402  (Earth/atmosphere material + add_sphere)
import render_vessel as rv        # noqa: E402  (composite_preview_on_bg)


# --------------------------------------------------------------------------------------
# Scene constants -- symbolic, tuned for legibility rather than astronomy
# --------------------------------------------------------------------------------------

EARTH_RADIUS = rem.EARTH_RADIUS        # 1.0
# Pass 3's brief proposed 1.24 (from the orthographic approximation ring_radius *
# sin(elevation) > earth_radius: 1.24 * sin(62) = 1.095 > 1) but verify_ring_clears_limb
# -- checking the REAL perspective camera, not that infinite-distance approximation --
# failed at 1.24 through 1.33 (binary search against the actual solved camera: the
# antipodal ring point stayed occluded up to radius 1.33, first cleared at 1.34). The
# finite camera distance (~4.4-4.7 units here) makes Earth's projected silhouette
# larger than the orthographic model assumes, so the whole-ring-clears threshold sits
# noticeably higher in practice. 1.40 gives roughly 5% margin over the empirical 1.34
# threshold rather than sitting right on it.
DEFAULT_RING_RADIUS = 1.40 * EARTH_RADIUS   # pass 3: floats clear of the limb (was 1.06)
# Mutable, like rp.PLATE_THICKNESS elsewhere in this pipeline: main() overwrites this
# from --ring-radius before any geometry is built, so every function below that reads
# RING_RADIUS (ring_dimensions, build_ring, ring_sample_points, measure_plate_color,
# verify_ring_clears_limb) picks up the CLI value without threading it through as an
# extra parameter everywhere.
RING_RADIUS = DEFAULT_RING_RADIUS

# A real 45: 17.7 in across, ~1.5 in thick -> thickness/diameter ~= 0.085, rounded to
# 0.09. This is the ratio a face-to-face stack advances by relative to how wide each
# disc reads, so it is what has to stay true to "45-lb plate" even though the plate
# COUNT (derived, ~666 at the pass-3 defaults) is wildly symbolic (honest count is
# ~1.05 billion; see honest_math). Pass 2: at 0.09 with ~570 plates the per-plate
# chamfer seam is still visible at 1200 px (confirmed via a cropped close-up), so the
# rise to 0.12 mentioned as a fallback was not needed -- left as a documented option.
THICKNESS_OVER_DIAMETER = 0.09

OCEAN_DEEP = rem.OCEAN_DEEP
OCEAN_SHALLOW = rem.OCEAN_SHALLOW
LAND_DARK = rem.LAND_DARK
LAND_LIGHT = rem.LAND_LIGHT
ATMOSPHERE = rem.ATMOSPHERE

# Key + fill directions copied from render_earth_moon.py's solved build_lighting (same
# numbers, not a new solve) -- reusing them is what guarantees the ring's fill-start
# angle (computed from these same directions, see terminator_theta_dawn()) actually
# lines up with the terminator the render shows on Earth's surface. "rim" is
# render_earth_moon.py's plate_rim sun, reused here for the same job: catching the
# plates' edges against space.
KEY_DIR = (-0.739, 0.572, -0.357)
KEY_ENERGY = 5.2
KEY_ANGLE_DEG = 2.0
FILL_DIR = (0.85, -0.40, -0.25)
FILL_ENERGY = 0.30
FILL_ANGLE_DEG = 40.0
FILL_COLOR = (0.62, 0.72, 1.0)
RIM_DIR = (0.30, -0.86, -0.42)
RIM_ENERGY = 0.7
RIM_ANGLE_DEG = 25.0
RIM_COLOR = (0.78, 0.86, 1.0)

# Elevation defaults to 62 deg (pass 3; see module docstring for why) -- both are now
# CLI args (--elevation, --azimuth) rather than fixed constants; DEFAULT_* are just the
# argparse defaults so the reasoning has one home.
DEFAULT_CAM_ELEVATION_DEG = 62.0
DEFAULT_CAM_AZIMUTH_DEG = 0.0
CAM_LENS_MM = 55.0
FRAME_MARGIN = 0.07

# Honest math, printed and written to the manifest verbatim (see module docstring).
HONEST_MATH = {
    "earth_equatorial_circumference_mi": 24901,
    "earth_equatorial_circumference_ft": 131_477_280,
    "earth_equatorial_circumference_in": 1_577_727_360,
    "plate_thickness_in": 1.5,
    "plates_face_to_face_to_close_ring": 1_051_818_240,
    "total_weight_lb": 47_331_820_800,
    "note": "visible plates are symbolic",
}


# --------------------------------------------------------------------------------------
# Terminator -- where the covered arc starts
# --------------------------------------------------------------------------------------

def terminator_theta_dawn():
    """Ring-plane angle (radians, atan2(y,x) convention) where the KEY sun's terminator
    crosses from night into day as theta increases (the dawn line, "eastward" being the
    direction of increasing theta -- Earth's own prograde sense viewed from +Z/North).

    A SUN light's `direction` is where its rays TRAVEL (see build_lighting: rotation is
    solved via `direction.to_track_quat("-Z", "Y")`, i.e. local -Z, the direction the
    light shines, points along `direction`). A point with outward normal N is lit when
    the incoming ray direction opposes N: dot(N, direction) < 0.

    For a ring-plane point at angle theta, N = (cos theta, sin theta, 0), so
    dot(N, direction) = Lx*cos(theta) + Ly*sin(theta) = |L_xy| * cos(theta - phi),
    phi = atan2(Ly, Lx). That crosses zero at theta = phi +/- pi/2; going from + to -
    (night to day) as theta increases happens at theta = phi + pi/2 (checked
    numerically against a toy direction=(-1,0,0) case: the point at theta=270 deg is the
    dawn line and theta=271 deg is lit, theta=269 deg is not).
    """
    lx, ly = KEY_DIR[0], KEY_DIR[1]
    phi = math.atan2(ly, lx)
    return (phi + math.pi / 2.0) % math.tau


# --------------------------------------------------------------------------------------
# Ring plate material -- rp.make_material() plus a self-emission floor
# --------------------------------------------------------------------------------------

def make_ring_plate_material(emission=0.48):
    """Same base material as every other plate in this pipeline, plus a small
    self-emission at the plate's own colour.

    A near-polar camera (pass 2) makes the WHOLE ring visible at once, and Earth's
    single-direction key sun -- correct for giving Earth a terminator -- necessarily
    leaves roughly half the ring's circumference facing away from every light. Measured
    on the first pass 2 render: the lit side landed close to #2F6FD0, but the far side
    measured close to black, dragging the whole-ring median to #1B427F (32% off target
    on blue). render_vessel.py hit the identical problem (plates buried deep in the
    vessel, no direct light reaches them) and fixed it with exactly this: a modest
    Emission at the plate's own base colour, applied here rather than more directional
    lights because more suns just relocates the dark gap to between them (see
    build_lighting's ring rig) instead of removing it.
    """
    mat = rp.make_material()
    mat.name = "PlateBlue45_Ring"
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    base_color = rp.hex_to_linear_rgba(rp.PLATE_COLOR_HEX)
    for k in ("Emission Color", "Emission"):
        if k in bsdf.inputs:
            try:
                bsdf.inputs[k].default_value = base_color
                break
            except Exception:
                continue
    if "Emission Strength" in bsdf.inputs:
        bsdf.inputs["Emission Strength"].default_value = emission
    return mat


# --------------------------------------------------------------------------------------
# Ring geometry -- N plates, face to face, axis tangent to the ring
# --------------------------------------------------------------------------------------

def ring_dimensions(diameter):
    """(n_plates, thickness) for a ring of plates with the given face diameter.

    Diameter is the dial (--ring-diameter): thickness = ratio * diameter (the real 45's
    proportion), and N = round(circumference / thickness) is DERIVED, not chosen -- the
    plate count that happens to close a RING_RADIUS-circumference ring at that
    thickness. Thickness is then recomputed from the rounded N so the ring closes
    EXACTLY (N * thickness == circumference to floating-point precision), which differs
    from the target by a negligible sub-percent amount for N in the hundreds.
    """
    thickness_target = THICKNESS_OVER_DIAMETER * diameter
    n_plates = max(1, round(math.tau * RING_RADIUS / thickness_target))
    thickness = math.tau * RING_RADIUS / n_plates
    return n_plates, thickness


def build_ring(diameter, theta0, emission=0.35):
    """Plates stacked face-to-face around the ring at the given face diameter, starting
    at angle theta0 (the dawn line) and advancing eastward (increasing theta) by
    exactly `thickness` each, so the last plate sits flush against the first and the
    ring closes with no seam gap. Plate count is derived (see ring_dimensions)."""
    n_plates, thickness = ring_dimensions(diameter)
    dtheta = math.tau / n_plates

    # The shared mesh is authored at diameter 1.0; scale the local thickness so that
    # after the object is uniformly scaled by `diameter`, world thickness comes out
    # right -- the same trick render_earth_moon.py's build_column() uses.
    rp.PLATE_THICKNESS = thickness / diameter
    mesh = rp.build_plate_mesh("Plate45_Ring")
    mesh.materials.append(make_ring_plate_material(emission))

    plates = []
    thetas = []
    for i in range(n_plates):
        theta = theta0 + i * dtheta
        radial = Vector((math.cos(theta), math.sin(theta), 0.0))
        tangent = Vector((-math.sin(theta), math.cos(theta), 0.0))  # eastward
        obj = bpy.data.objects.new(f"ring_plate_{i:04d}", mesh)
        obj.location = radial * RING_RADIUS
        # The mesh is a solid of revolution about local Z (see rp.build_plate_mesh),
        # so it has no directional feature around that axis -- only where local Z
        # points (here: tangent) matters, never occurring here since tangent lies in
        # the XY plane and never coincides with the visible profile's roll axis.
        obj.rotation_euler = tangent.to_track_quat("Z", "Y").to_euler()
        obj.scale = (diameter, diameter, diameter)
        bpy.context.collection.objects.link(obj)
        plates.append(obj)
        thetas.append(theta)
    rp.apply_auto_smooth(plates)
    return plates, thetas, n_plates, thickness


# --------------------------------------------------------------------------------------
# Bodies (Earth + atmosphere) -- reused materials from render_earth_moon.py
# --------------------------------------------------------------------------------------

def build_earth():
    earth = rem.add_sphere("Earth", (0.0, 0.0, 0.0), EARTH_RADIUS, rem.make_earth_material())
    atmo = rem.add_sphere("Atmosphere", (0.0, 0.0, 0.0), EARTH_RADIUS * 1.035,
                          rem.make_atmosphere_material(), segments=64, rings=32)
    atmo.visible_shadow = False
    atmo.visible_diffuse = False
    atmo.visible_glossy = False
    return earth, atmo


# --------------------------------------------------------------------------------------
# Lighting -- key + fill (Earth's terminator) plus a rim for the plates' edges
# --------------------------------------------------------------------------------------

def build_lighting(scale=1.0):
    def sun(name, direction, energy, angle_deg, color=(1.0, 1.0, 1.0)):
        data = bpy.data.lights.new(name, type="SUN")
        data.energy = energy * scale
        data.angle = math.radians(angle_deg)
        data.color = color
        obj = bpy.data.objects.new(name, data)
        obj.rotation_euler = Vector(direction).to_track_quat("-Z", "Y").to_euler()
        bpy.context.collection.objects.link(obj)
        return obj

    sun("key", KEY_DIR, KEY_ENERGY, KEY_ANGLE_DEG)
    sun("fill", FILL_DIR, FILL_ENERGY, FILL_ANGLE_DEG, FILL_COLOR)
    sun("rim", RIM_DIR, RIM_ENERGY, RIM_ANGLE_DEG, RIM_COLOR)

    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.0, 0.0, 0.0, 1.0)
    bg.inputs[1].default_value = 0.0
    bpy.context.scene.world = world


# --------------------------------------------------------------------------------------
# Camera -- fixed 3/4 view, solved once against the FULL ring regardless of fill
# --------------------------------------------------------------------------------------

def fibonacci_sphere_points(centre, radius, n=180):
    pts = []
    ga = math.pi * (3.0 - math.sqrt(5.0))
    for i in range(n):
        z = 1.0 - 2.0 * i / (n - 1)
        r = math.sqrt(max(0.0, 1.0 - z * z))
        a = ga * i
        pts.append(Vector(centre) + Vector((math.cos(a) * r, math.sin(a) * r, z)) * radius)
    return pts


def ring_sample_points(n_plates, diameter, theta0, k=8):
    """Extremal rim points of every plate's cross-section circle (spanned by the
    radial and Z directions, since tangent/radial/Z are mutually orthogonal), used to
    numerically solve the camera framing against the FULL ring."""
    pts = []
    dtheta = math.tau / n_plates
    z_axis = Vector((0.0, 0.0, 1.0))
    for i in range(n_plates):
        theta = theta0 + i * dtheta
        radial = Vector((math.cos(theta), math.sin(theta), 0.0))
        centre = radial * RING_RADIUS
        for kk in range(k):
            a = kk * math.tau / k
            offset = (radial * math.cos(a) + z_axis * math.sin(a)) * (diameter * 0.5)
            pts.append(centre + offset)
    return pts


def build_camera(scene, n_plates, diameter, theta0, cam_azimuth_deg, cam_elevation_deg):
    from bpy_extras.object_utils import world_to_camera_view

    cam_data = bpy.data.cameras.new("Camera")
    cam_data.lens = CAM_LENS_MM
    cam = bpy.data.objects.new("Camera", cam_data)
    bpy.context.collection.objects.link(cam)
    scene.camera = cam

    pts = (fibonacci_sphere_points((0.0, 0.0, 0.0), EARTH_RADIUS * 1.035, n=180)
           + ring_sample_points(n_plates, diameter, theta0))

    el, az = math.radians(cam_elevation_deg), math.radians(cam_azimuth_deg)
    back = Vector((math.cos(el) * math.cos(az), math.cos(el) * math.sin(az), math.sin(el)))
    aim = Vector((0.0, 0.0, 0.0))
    dist, want = 12.0, 1.0 - 2.0 * FRAME_MARGIN

    def place(d, a):
        cam.location = a + back * d
        cam.rotation_euler = (a - cam.location).to_track_quat("-Z", "Y").to_euler()
        bpy.context.view_layer.update()

    for _ in range(120):
        place(dist, aim)
        ndc = [world_to_camera_view(scene, cam, p) for p in pts]
        xs = [v.x for v in ndc]
        ys = [v.y for v in ndc]
        span = max(max(xs) - min(xs), max(ys) - min(ys))
        if span <= 1e-6:
            break
        frame_world = 2.0 * dist * math.tan(cam_data.angle_y * 0.5)
        mw = cam.matrix_world.to_3x3()
        right, up = mw.col[0].normalized(), mw.col[1].normalized()
        cx = (max(xs) + min(xs)) * 0.5
        cy = (max(ys) + min(ys)) * 0.5
        aim = aim + right * ((cx - 0.5) * frame_world) + up * ((cy - 0.5) * frame_world)
        dist *= 1.0 + (span / want - 1.0) * 0.8
        if abs(span / want - 1.0) < 2e-4 and abs(cx - 0.5) < 2e-4 and abs(cy - 0.5) < 2e-4:
            break

    place(dist, aim)
    ndc = [world_to_camera_view(scene, cam, p) for p in pts]
    fit = {
        "distance": round(dist, 4),
        "aim": [round(v, 4) for v in aim],
        "ndc_x": [round(min(v.x for v in ndc), 4), round(max(v.x for v in ndc), 4)],
        "ndc_y": [round(min(v.y for v in ndc), 4), round(max(v.y for v in ndc), 4)],
    }
    return cam, fit


# --------------------------------------------------------------------------------------
# Median plate colour -- sample the ACTUAL rendered pixels of unoccluded plates
# --------------------------------------------------------------------------------------

def _ray_sphere_nearest_t(origin, direction, centre, radius):
    oc = origin - centre
    b = oc.dot(direction)
    c = oc.dot(oc) - radius * radius
    disc = b * b - c
    if disc < 0.0:
        return None
    sq = math.sqrt(disc)
    for t in (-b - sq, -b + sq):
        if t > 1e-6:
            return t
    return None


def verify_ring_clears_limb(cam, thetas):
    """Geometric check, not eyeballed: every point on the FULL ring (all N plate
    positions, regardless of current fill -- occlusion is a fact about the camera and
    the ring, not about which plates happen to be hidden by --fills) must be
    unoccluded by Earth's sphere from the camera's position. This is the pass-3 fix's
    actual claim (RING_RADIUS * sin(elevation) > EARTH_RADIUS clears the whole ring,
    not just the near side) verified against the real camera transform rather than
    trusted from the orthographic approximation the inequality comes from.

    Hard-fails with a specific offending angle so a future --ring-radius/--elevation
    combination that regresses this cannot ship silently. Same ray-sphere test
    measure_plate_color uses for the (now expected to never trigger) per-sample check.
    """
    cam_loc = cam.matrix_world.translation
    worst = None
    for theta in thetas:
        pos = Vector((math.cos(theta), math.sin(theta), 0.0)) * RING_RADIUS
        to_point = pos - cam_loc
        dist = to_point.length
        direction = to_point / dist
        t_hit = _ray_sphere_nearest_t(cam_loc, direction, Vector((0.0, 0.0, 0.0)), EARTH_RADIUS)
        if t_hit is not None and t_hit < dist - 1e-4:
            margin = dist - t_hit
            if worst is None or margin > worst[1]:
                worst = (theta, margin)
    if worst is not None:
        raise SystemExit(
            f"[earth-ring] FAILED limb-clearance check -- ring point at theta="
            f"{math.degrees(worst[0]):.2f} deg is occluded by Earth's silhouette "
            f"(hidden by {worst[1]:.4f} world units). Raise --ring-radius or lower "
            f"--elevation; see the pass 3 discussion in the module docstring and the "
            f"render report."
        )
    print(f"[earth-ring] limb-clearance check passed: all {len(thetas)} ring points "
          f"clear Earth's silhouette from the camera")


def measure_plate_color(image_path, cam, scene, thetas, n_show):
    """Median rendered colour of the visible (front-facing, Earth-unoccluded) plates in
    one already-rendered frame. Projects each shown plate's centre into the image (the
    same world_to_camera_view helper the camera solve uses), rejects points behind the
    camera, outside frame or occluded by the Earth sphere (simple ray-sphere test
    against radius EARTH_RADIUS), then reads the corresponding pixel straight out of
    the saved PNG (colourspace forced to Raw so no further transform is applied -- the
    stored bytes ARE the sRGB-encoded colour, directly comparable to PLATE_COLOR_HEX).
    """
    from bpy_extras.object_utils import world_to_camera_view
    import numpy as np

    img = bpy.data.images.load(image_path)
    try:
        for cs in ("Raw", "Non-Color"):
            try:
                img.colorspace_settings.name = cs
                break
            except Exception:
                continue
        w, h = img.size
        px = np.empty(len(img.pixels), dtype=np.float32)
        img.pixels.foreach_get(px)
        px = px.reshape(h, w, 4)
    finally:
        bpy.data.images.remove(img)

    cam_loc = cam.matrix_world.translation
    samples = []
    for theta in thetas[:n_show]:
        pos = Vector((math.cos(theta), math.sin(theta), 0.0)) * RING_RADIUS
        ndc = world_to_camera_view(scene, cam, pos)
        if ndc.z <= 0.0 or not (0.02 < ndc.x < 0.98 and 0.02 < ndc.y < 0.98):
            continue
        to_point = pos - cam_loc
        dist = to_point.length
        direction = to_point / dist
        t_hit = _ray_sphere_nearest_t(cam_loc, direction, Vector((0.0, 0.0, 0.0)), EARTH_RADIUS)
        if t_hit is not None and t_hit < dist - 1e-4:
            continue   # occluded by Earth
        col = int(round(ndc.x * (w - 1)))
        row = int(round(ndc.y * (h - 1)))
        r, g, b, a = px[row, col]
        if a < 0.9:
            continue   # anti-aliased edge pixel, skip
        samples.append((r, g, b))

    if not samples:
        return None
    arr = np.array(samples)
    median = np.median(arr, axis=0)
    hexval = "".join(f"{int(round(c * 255)):02X}" for c in median)
    target = rp.PLATE_COLOR_HEX
    target_rgb = [int(target[i:i + 2], 16) for i in (0, 2, 4)]
    measured_rgb = [int(round(c * 255)) for c in median]
    pct_diff = [round(100.0 * abs(m - t) / 255.0, 2) for m, t in zip(measured_rgb, target_rgb)]
    return {
        "hex": "#" + hexval,
        "target_hex": "#" + target,
        "rgb_255": measured_rgb,
        "pct_diff_per_channel": pct_diff,
        "sample_count": len(samples),
    }


# --------------------------------------------------------------------------------------
# Verification -- every requested fill must render a genuinely different image
# --------------------------------------------------------------------------------------

def verify_distinct_renders(renders):
    """Hashes each rendered (post clean_transparent_rgb) PNG's file bytes and hard-fails
    if any two fills collide. Pass 1 (a shallower 3/4 camera) shipped a render where
    fill 0.50 and 0.75 were provably pixel-identical; this makes that class of bug
    impossible to ship silently again. Returns {tag: md5-hex}, printed regardless of
    outcome so a pass/fail is visible either way.
    """
    hashes = {}
    for (fill, tag, n_show, path) in renders:
        with open(path, "rb") as fh:
            hashes[tag] = hashlib.md5(fh.read()).hexdigest()
    print("[earth-ring] render hashes: " + json.dumps(hashes))

    seen = {}
    collisions = []
    for tag, h in hashes.items():
        if h in seen:
            collisions.append((seen[h], tag))
        else:
            seen[h] = tag
    if collisions:
        raise SystemExit(
            "[earth-ring] FAILED distinctness check -- identical renders: "
            + ", ".join(f"{a} == {b}" for a, b in collisions)
            + ". Every requested --fills value must render a visibly different image; "
              "see the camera elevation/azimuth discussion in the module docstring."
        )
    print(f"[earth-ring] distinctness check passed: all {len(hashes)} fills render "
          f"different images")
    return hashes


# --------------------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------------------

def parse_args(argv):
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    p = argparse.ArgumentParser(prog="render_earth_ring.py")
    p.add_argument("--out", default="tools/milestone-render/out-earth-ring")
    p.add_argument("--ring-diameter", type=float, default=0.13,
                   help="plate face diameter, in Earth radii. Plate count is DERIVED "
                        "from this and --ring-radius (thickness = 0.09 x diameter; "
                        "N = round(2*pi*ring_radius / thickness)), not chosen directly "
                        "-- see ring_dimensions().")
    p.add_argument("--ring-radius", type=float, default=DEFAULT_RING_RADIUS,
                   help="ring radius, in Earth radii -- how far the ring floats off "
                        "the surface. Must satisfy ring_radius * sin(elevation) > "
                        "EARTH_RADIUS (1.0) for the whole ring to clear Earth's "
                        "silhouette; verify_ring_clears_limb() checks this against the "
                        "real camera and hard-fails otherwise.")
    p.add_argument("--fills", type=float, nargs="+", default=[0.25, 0.5, 0.75, 1.0])
    p.add_argument("--size", default="1200x1200")
    p.add_argument("--samples", type=int, default=96)
    p.add_argument("--elevation", type=float, default=DEFAULT_CAM_ELEVATION_DEG,
                   help="camera elevation above the equatorial plane, degrees. Must "
                        "satisfy ring_radius * sin(elevation) > EARTH_RADIUS for the "
                        "ring to clear Earth's silhouette (see --ring-radius); if not, "
                        "the ring visually merges with the limb and some fill levels "
                        "may render identically -- see the module docstring.")
    p.add_argument("--azimuth", type=float, default=None,
                   help="camera azimuth, degrees (world XY convention used throughout "
                        "this pipeline). Defaults to the terminator dawn line's own "
                        "angle, which just fixes where the fill-start seam sits on "
                        "screen -- azimuth no longer needs to dodge Earth's self-"
                        "occlusion the way it did at a shallow elevation.")
    p.add_argument("--preview-width", type=int, default=600)
    p.add_argument("--preview-bg", default="0A0B0D",
                   help="composite the preview PNGs over this hex colour (the app's "
                        "real ground); full renders stay transparent")
    p.add_argument("--light-scale", type=float, default=1.0)
    p.add_argument("--emission", type=float, default=0.48,
                   help="plate self-emission strength at #2F6FD0 -- keeps the far side "
                        "of the ring (necessarily unlit by Earth's single-direction key "
                        "sun once the whole ring is visible at once) from reading black. "
                        "Same technique as render_vessel.py's make_vessel_plate_material.")
    p.add_argument("--save-blend", action="store_true")
    args = p.parse_args(argv)
    w, _, h = args.size.lower().partition("x")
    args.width, args.height = int(w), int(h)
    args.fit_width = args.width
    return args


def main():
    global RING_RADIUS
    args = parse_args(sys.argv)
    RING_RADIUS = args.ring_radius * EARTH_RADIUS
    t_start = time.time()
    out_dir = os.path.abspath(args.out)
    os.makedirs(out_dir, exist_ok=True)

    clearance = RING_RADIUS * math.sin(math.radians(args.elevation))
    print(f"[earth-ring] limb clearance: ring_radius({RING_RADIUS}) * "
          f"sin(elevation {args.elevation} deg) = {clearance:.4f} "
          f"({'clears' if clearance > EARTH_RADIUS else 'DOES NOT CLEAR'} "
          f"Earth radius {EARTH_RADIUS})")

    rp.clear_scene()
    scene = bpy.context.scene

    theta0 = terminator_theta_dawn()
    earth, atmo = build_earth()
    plates, thetas, n_plates, thickness = build_ring(args.ring_diameter, theta0, args.emission)
    build_lighting(args.light_scale)

    cam_azimuth_deg = (math.degrees(theta0) if args.azimuth is None else args.azimuth)
    cam_elevation_deg = args.elevation
    engine, device_type, device_names = rp.setup_render(scene, args, "auto")
    cam, fit = build_camera(scene, n_plates, args.ring_diameter, theta0,
                            cam_azimuth_deg, cam_elevation_deg)

    print(f"[earth-ring] engine={engine} device={device_type} {device_names} "
          f"samples={args.samples} size={args.width}x{args.height}")
    print(f"[earth-ring] {n_plates} plates (derived from --ring-diameter "
          f"{args.ring_diameter}), thickness {thickness:.5f}, ring radius {RING_RADIUS}")
    print(f"[earth-ring] dawn line theta={math.degrees(theta0):.2f} deg, "
          f"camera azimuth={cam_azimuth_deg:.2f} deg, elevation={cam_elevation_deg} deg")
    print(f"[earth-ring] camera fit: {fit}")
    print(f"[earth-ring] camera location: {tuple(round(v, 4) for v in cam.matrix_world.translation)}")

    verify_ring_clears_limb(cam, thetas)

    if args.save_blend:
        blend = os.path.join(os.path.dirname(out_dir), "earth_ring.blend")
        bpy.ops.wm.save_as_mainfile(filepath=blend)
        print(f"[earth-ring] saved {blend}")

    timings, shown, previews, renders = {}, {}, [], []
    for fill in args.fills:
        n_show = int(round(fill * n_plates))
        for i, obj in enumerate(plates):
            obj.hide_render = (i >= n_show)
        tag = f"{int(round(fill * 100)):02d}"
        path = os.path.join(out_dir, f"ring_{tag}.png")
        scene.render.filepath = path
        t0 = time.time()
        bpy.ops.render.render(write_still=True)
        rp.clean_transparent_rgb(path)
        dt = time.time() - t0
        timings[tag], shown[tag] = round(dt, 2), n_show

        prev = os.path.join(out_dir, f"preview_{tag}_{args.preview_width}.png")
        rp.write_downscaled_proof(path, prev, args.preview_width)
        rv.composite_preview_on_bg(prev, args.preview_bg)
        previews.append(prev)
        renders.append((fill, tag, n_show, path))
        print(f"[earth-ring] fill {fill:.2f}  {n_show:4d}/{n_plates} plates  {dt:6.2f}s  "
              f"{os.path.getsize(path) / 1024:8.1f} KB  -> {prev}", flush=True)

    render_hashes = verify_distinct_renders(renders)

    # Measure median plate colour on the frame with the most visible (front-facing,
    # unoccluded) plates -- the largest requested fill gives the most robust sample.
    best_fill, best_tag, best_n, best_path = max(renders, key=lambda r: r[2])
    measured = measure_plate_color(best_path, cam, scene, thetas, best_n)
    if measured:
        print(f"[earth-ring] measured plate colour {measured['hex']} vs target "
              f"{measured['target_hex']}  (n={measured['sample_count']}, frame={best_tag}, "
              f"pct diff/channel={measured['pct_diff_per_channel']})")
    else:
        print(f"[earth-ring] measured plate colour: no unoccluded samples found on frame {best_tag}")

    print("[earth-ring] honest math: " + json.dumps(HONEST_MATH))

    times = list(timings.values())
    manifest = {
        "generator": "tools/milestone-render/render_earth_ring.py",
        "blender_version": bpy.app.version_string,
        "engine": engine,
        "device_type": device_type,
        "devices": device_names,
        "samples": args.samples,
        "image_size": [args.width, args.height],
        "background": "transparent (RGBA, 8-bit PNG); app paints #0A0B0D behind",
        "geometry": "plates stacked FACE TO FACE (axis tangent to the ring); ring "
                    "advances by each plate's thickness, not its diameter",
        "fill_mapping": "covered arc starts at the terminator (dawn line) on the lit "
                        "side and grows eastward; uncovered arc renders nothing "
                        "(hide_render, no ghost plates); fill 1.0 closes the ring",
        "ring": {
            "earth_radius": EARTH_RADIUS,
            "ring_radius": RING_RADIUS,
            "ring_diameter_arg": args.ring_diameter,
            "n_plates": n_plates,
            "thickness_over_diameter_ratio": THICKNESS_OVER_DIAMETER,
            "plate_thickness": round(thickness, 6),
            "plate_diameter": round(args.ring_diameter, 6),
            "plate_color_hex": "#" + rp.PLATE_COLOR_HEX,
            "dawn_theta_deg": round(math.degrees(theta0), 4),
        },
        "limb_clearance": {
            "ring_radius": RING_RADIUS,
            "elevation_deg": args.elevation,
            "ring_radius_times_sin_elevation": round(clearance, 4),
            "earth_radius": EARTH_RADIUS,
            "clears": clearance > EARTH_RADIUS,
            "note": "ring_radius * sin(elevation) must exceed earth_radius for the "
                    "WHOLE ring to clear Earth's silhouette (verify_ring_clears_limb "
                    "checks this against the real camera transform, not just this "
                    "orthographic-approximation inequality)",
        },
        "earth": {
            "ocean_hex": ["#" + OCEAN_DEEP, "#" + OCEAN_SHALLOW],
            "land_hex": ["#" + LAND_DARK, "#" + LAND_LIGHT],
            "atmosphere_hex": "#" + ATMOSPHERE,
        },
        "camera": {
            "lens_mm": CAM_LENS_MM,
            "elevation_deg": cam_elevation_deg,
            "azimuth_deg": round(cam_azimuth_deg, 4),
            "margin": FRAME_MARGIN,
            "fit": fit,
        },
        "distinctness_check": {
            "render_hashes_md5": render_hashes,
            "all_distinct": len(set(render_hashes.values())) == len(render_hashes),
        },
        "history": "Pass 1: shallow 3/4 camera (13 deg elevation), ring radius 1.06 -- "
                   "far side of the ring projected inside Earth's silhouette, making "
                   "fill 0.50 and 0.75 render pixel-identical. Pass 2: near-polar "
                   "camera (68 deg) made the whole ring visible, but ring_radius(1.06) "
                   "* sin(68 deg) = 0.983 still fell just short of clearing Earth's "
                   "radius (1.0), so the uncovered arc visually merged with the "
                   "atmosphere's Fresnel rim highlight instead of reading as a gap; "
                   "also surfaced uneven ring lighting, fixed with plate self-emission "
                   "(see ring.plate_color_hex / measured_plate_color). Pass 3: lowered "
                   "elevation to 62 deg and lifted the ring; the brief's orthographic-"
                   "approximation estimate (ring_radius 1.24) failed a real-camera "
                   "check, so ring_radius was raised to 1.40 (empirical threshold ~1.34, "
                   "found by binary search against the actual perspective camera) so "
                   "ring_radius * sin(elevation) > earth_radius holds with margin (see "
                   "limb_clearance above) -- verify_ring_clears_limb() checks this "
                   "geometrically every run and verify_distinct_renders() still checks "
                   "fill distinctness (see distinctness_check above); both pass.",
        "measured_plate_color": measured,
        "honest_math": HONEST_MATH,
        "renders": [{"fill": f, "tag": t, "plates_shown": n,
                     "seconds": timings[t]} for (f, t, n, _p) in renders],
        "previews": [os.path.basename(p) for p in previews],
        "preview_background": "#" + args.preview_bg.lstrip("#").upper(),
        "timing": {
            "seconds_per_frame": timings,
            "mean_seconds_per_frame": round(sum(times) / len(times), 2) if times else None,
            "total_seconds": round(time.time() - t_start, 2),
        },
    }
    with open(os.path.join(out_dir, "manifest.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2)
    print(f"[earth-ring] done in {manifest['timing']['total_seconds']}s")


if __name__ == "__main__":
    main()
