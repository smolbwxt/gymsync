"""
GymSync milestone tile -- 45 lb plate stack renderer (headless Blender / bpy).

Renders frame_00.png .. frame_50.png where frame k shows a stack of exactly k
45-lb plates on an invisible floor, transparent background, fixed camera.
Frame k differs from frame k-1 by exactly one added plate (same seeded jitter),
so the app can cross-fade between neighbouring frames.

Usage (from the repo root):

    blender -b -P tools/milestone-render/render_plates.py -- \
        --out tools/milestone-render/out --frames 51 --size 600x1500 [--samples 96] [--preview]

Everything after the bare `--` is parsed by this script; Blender consumes the rest.
The whole scene is built from code -- no .blend file is required. Pass --save-blend
to also drop tools/milestone-render/plates.blend for hand tweaking.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import random
import sys
import time

import bpy
import bmesh
from mathutils import Vector

# --------------------------------------------------------------------------------------
# Constants -- symbolic proportions, not physical ones. Tuned so a 130x80 pt tile still
# lets you count individual plates.
# --------------------------------------------------------------------------------------

PLATE_DIAMETER = 1.0      # unit
PLATE_RADIUS = PLATE_DIAMETER / 2.0
BASE_THICKNESS = 0.16     # the thickness the profile's depth constants were authored against
PLATE_THICKNESS = 0.16    # ~3x real, deliberately thick so plates read individually
                          # (overridden by --thickness; 50 plates = 50 * this, tall)
HOLE_DIAMETER = 0.11
HOLE_RADIUS = HOLE_DIAMETER / 2.0

PLATE_COLOR_HEX = "2F6FD0"   # competition blue == 45 lb
PLATE_ROUGHNESS = 0.45
PLATE_METALLIC = 0.15        # faint painted-iron feel
# Dielectric specular is dialled well below the 0.5 default. The camera looks down on the
# plate faces at ~65 deg from normal, right in the Fresnel rise, and at the default level a
# broad white sheen washes the top face of the lower frames off the blue entirely.
PLATE_SPECULAR = 0.16

ROT_JITTER_DEG = 3.0         # +/- per plate
POS_JITTER = 0.01            # +/- per plate, horizontal
JITTER_SEED = 20260904       # plate k is always in the same place, in every frame

CAM_ELEVATION_DEG = 25.0
CAM_AZIMUTH_DEG = -122.0     # three-quarter view
CAM_LENS_MM = 85.0
FRAME_MARGIN = 0.04          # 4% top and bottom

REVOLVE_STEPS = 96


# --------------------------------------------------------------------------------------
# Small helpers
# --------------------------------------------------------------------------------------

def srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_to_linear_rgba(hex_str: str):
    hex_str = hex_str.lstrip("#")
    r, g, b = (int(hex_str[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    return (srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b), 1.0)


def parse_args(argv):
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = []
    p = argparse.ArgumentParser(prog="render_plates.py")
    p.add_argument("--out", default="tools/milestone-render/out")
    p.add_argument("--frames", type=int, default=51, help="total frames; frame k shows k plates")
    p.add_argument("--size", default="600x1500", help="WxH in pixels")
    p.add_argument("--samples", type=int, default=96)
    p.add_argument("--preview", action="store_true",
                   help="render only frames 1, 25, 50 at half size into <out>/preview")
    p.add_argument("--engine", default="auto", choices=("auto", "cycles", "eevee"))
    p.add_argument("--save-blend", action="store_true")
    p.add_argument("--seed", type=int, default=JITTER_SEED)
    p.add_argument("--light-scale", type=float, default=1.0,
                   help="multiply all three light energies (exposure tuning)")
    p.add_argument("--width", type=int, default=None,
                   help="render a narrower canvas by cropping horizontally only. The camera is "
                        "still solved at the --size width, so the vertical framing (and every "
                        "frame's height and position) is bit-identical to the wider set.")
    p.add_argument("--proof-frame", type=int, nargs="+", default=None,
                   help="also write downscaled proofs of these frames: preview_<k>_<w>w.png")
    p.add_argument("--proof-width", type=int, default=120)
    p.add_argument("--thickness", type=float, default=PLATE_THICKNESS,
                   help="plate thickness in units (diameter is always 1.0). 50 plates stand "
                        "50x this tall, so this sets the stack aspect: 0.16 -> 1:8, "
                        "0.06 -> 1:3. Rim/hole/chamfer depths scale with it.")
    args = p.parse_args(argv)
    w, _, h = args.size.lower().partition("x")
    # fit_width drives the camera solve; width is what actually gets rendered.
    args.fit_width, args.height = int(w), int(h)
    args.width = args.width if args.width else args.fit_width
    if args.width > args.fit_width:
        p.error("--width may only narrow the canvas (<= the --size width)")
    return args


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.lights,
                 bpy.data.cameras, bpy.data.objects):
        for item in list(coll):
            coll.remove(item)


# --------------------------------------------------------------------------------------
# Geometry -- one plate, built by revolving a 2D (radius, z) profile.
# The profile gives us the raised rim ring, the recessed face, the hub and the bevelled
# centre hole in one shot, and it stays watertight.
# --------------------------------------------------------------------------------------

def plate_profile():
    """Half-section of one plate, revolved around Z to make the solid.

    Radial positions are fixed -- the diameter is always 1.0. Everything that is a *depth*
    (hole bevel, face recess, outer chamfer) scales with thickness, so a thinner plate keeps
    the same proportions rather than turning into a flat washer with a full-depth groove.
    """
    h = PLATE_THICKNESS / 2.0
    s = PLATE_THICKNESS / BASE_THICKNESS   # depth scale
    hr = HOLE_RADIUS
    R = PLATE_RADIUS
    recess = 0.020 * s      # how far the face is sunk below the rim
    chamfer = 0.030 * s     # outer chamfer, kept ~45 deg so the seam stays a clean V
    top = [
        (hr, h - 0.012 * s),        # top of the bevelled hole edge
        (hr + 0.011 * s, h),        # hub top begins
        (0.100, h),                 # hub top ends
        (0.114, h - recess),
        (0.392, h - recess),        # recessed face
        (0.412, h),                 # rim ring begins
        (R - chamfer, h),
        (R, h - chamfer),           # outer chamfer -- the V-groove between two stacked
    ]                               # plates is what makes them countable
    bottom = [(r, -z) for (r, z) in reversed(top)]
    return top + bottom


SMOOTH_ANGLE_DEG = 32.0


def build_plate_mesh(name="Plate45"):
    bm = bmesh.new()
    prof = plate_profile()
    verts = [bm.verts.new((r, 0.0, z)) for (r, z) in prof]
    edges = [bm.edges.new((verts[i], verts[(i + 1) % len(verts)])) for i in range(len(verts))]

    bmesh.ops.spin(
        bm,
        geom=verts + edges,
        cent=(0.0, 0.0, 0.0),
        axis=(0.0, 0.0, 1.0),
        dvec=(0.0, 0.0, 0.0),
        angle=2.0 * math.pi,
        steps=REVOLVE_STEPS,
        use_duplicate=False,
    )
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    # Shading is baked into the MESH (smooth faces + sharp edges), not into a per-object
    # "Smooth by Angle" modifier -- all 50 plates are linked duplicates of this one mesh
    # datablock, so a modifier would only ever smooth plate 0.
    limit = math.cos(math.radians(SMOOTH_ANGLE_DEG))
    for face in bm.faces:
        face.smooth = True
    for edge in bm.edges:
        if len(edge.link_faces) == 2:
            edge.smooth = edge.link_faces[0].normal.dot(edge.link_faces[1].normal) > limit

    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    return mesh


def apply_auto_smooth(objs):
    """Blender 4.1+ honours sharp edges directly, so the mesh-level marking above is
    enough. On older builds sharp edges only split with auto-smooth or an Edge Split
    modifier, so add one per object there."""
    if bpy.app.version >= (4, 1, 0):
        return "mesh sharp edges"
    for obj in objs:
        mod = obj.modifiers.new("EdgeSplit", "EDGE_SPLIT")
        mod.use_edge_angle = True
        mod.use_edge_sharp = True
        mod.split_angle = math.radians(SMOOTH_ANGLE_DEG)
    return "edge split modifier"


def make_material():
    mat = bpy.data.materials.new("PlateBlue45")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = hex_to_linear_rgba(PLATE_COLOR_HEX)
    bsdf.inputs["Roughness"].default_value = PLATE_ROUGHNESS
    bsdf.inputs["Metallic"].default_value = PLATE_METALLIC
    for key, val in (("Specular IOR Level", PLATE_SPECULAR), ("Specular", PLATE_SPECULAR),
                     ("IOR", 1.5)):
        if key in bsdf.inputs:
            try:
                bsdf.inputs[key].default_value = val
            except Exception:
                pass
    return mat


def plate_transform(k: int, seed: int):
    """Deterministic per-plate jitter. Seeded on the plate index (not the frame index),
    so plate k sits in exactly the same spot in every frame it appears in."""
    rng = random.Random(seed + k * 7919)
    rot_z = math.radians(rng.uniform(-ROT_JITTER_DEG, ROT_JITTER_DEG))
    dx = rng.uniform(-POS_JITTER, POS_JITTER)
    dy = rng.uniform(-POS_JITTER, POS_JITTER)
    z = (k + 0.5) * PLATE_THICKNESS
    return dx, dy, z, rot_z


def build_stack(max_plates: int, seed: int, mat):
    mesh = build_plate_mesh()
    mesh.materials.append(mat)
    plates = []
    for k in range(max_plates):
        dx, dy, z, rot_z = plate_transform(k, seed)
        obj = bpy.data.objects.new(f"plate_{k:02d}", mesh)   # linked duplicate, one mesh
        obj.location = (dx, dy, z)
        obj.rotation_euler = (0.0, 0.0, rot_z)
        bpy.context.collection.objects.link(obj)
        plates.append(obj)
    smooth_mode = apply_auto_smooth(plates) if plates else "n/a"
    return plates, smooth_mode


# --------------------------------------------------------------------------------------
# Lighting -- soft three point, neutral white, world strength 0 so alpha stays clean.
# Lights sit far away and are large, which keeps the top of an 8-unit stack from being
# dramatically brighter than the bottom.
# --------------------------------------------------------------------------------------

def _add_area_light(name, location, target, energy, size):
    data = bpy.data.lights.new(name, type="AREA")
    data.energy = energy
    data.size = size
    data.color = (1.0, 1.0, 1.0)
    obj = bpy.data.objects.new(name, data)
    obj.location = location
    direction = Vector(target) - Vector(location)
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.collection.objects.link(obj)
    return obj


def build_lighting(stack_height: float, scale: float = 1.0):
    mid = stack_height * 0.5
    aim = (0.0, 0.0, mid)

    def add_area_light(name, location, target, energy, size):
        return _add_area_light(name, location, target, energy * scale, size)

    # key -- upper left, in front
    # Lights are kept deliberately side-on. A plate's horizontal top face sees all three
    # at once, so raising them blows out the top plate long before the barrel -- which is
    # the surface that has to land on #2F6FD0 -- gets bright enough.
    # Energies solved by sweeping --light-scale and measuring the rendered mid-tone against
    # #2F6FD0: this exposure puts the stack barrel on the target blue while keeping the
    # lone plate in frame_01 (all horizontal top face, so the brightest surface in the set)
    # just under clipping.
    add_area_light("key", (-16.0, -13.0, mid + 6.0), aim, energy=6800.0, size=16.0)
    # fill -- right, weaker, flatter
    add_area_light("fill", (15.0, -9.0, mid + 2.0), aim, energy=1275.0, size=18.0)
    # rim -- behind and above, carves the plate edges out of the background.
    # Kept low: it is the single biggest contributor to a horizontal top face, and the
    # lone plate in frame_01 is all top face.
    add_area_light("rim", (6.0, 15.0, mid + 3.0), aim, energy=3825.0, size=12.0)

    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.0, 0.0, 0.0, 1.0)
    bg.inputs[1].default_value = 0.0        # no ambient -> clean alpha, no colour wash
    bpy.context.scene.world = world


# --------------------------------------------------------------------------------------
# Camera -- fixed for every frame, framed on the FULL stack.
# --------------------------------------------------------------------------------------

def stack_sample_points(max_plates: int, seed: int):
    """Extreme points of the full stack: the outer rim circle at the top and bottom of
    every plate. Used to solve the camera framing numerically."""
    pts = []
    ring = [(PLATE_RADIUS * math.cos(a), PLATE_RADIUS * math.sin(a))
            for a in (i * math.tau / 32 for i in range(32))]
    half = PLATE_THICKNESS / 2.0
    for k in range(max_plates):
        dx, dy, z, _ = plate_transform(k, seed)
        for (x, y) in ring:
            pts.append(Vector((x + dx, y + dy, z - half)))
            pts.append(Vector((x + dx, y + dy, z + half)))
    return pts


def build_camera(max_plates: int, seed: int, scene):
    from bpy_extras.object_utils import world_to_camera_view

    cam_data = bpy.data.cameras.new("Camera")
    cam_data.lens = CAM_LENS_MM
    cam = bpy.data.objects.new("Camera", cam_data)
    bpy.context.collection.objects.link(cam)
    scene.camera = cam

    el = math.radians(CAM_ELEVATION_DEG)
    az = math.radians(CAM_AZIMUTH_DEG)
    back = Vector((math.cos(el) * math.cos(az), math.cos(el) * math.sin(az), math.sin(el)))

    pts = stack_sample_points(max_plates, seed)
    z_lo = min(p.z for p in pts)
    z_hi = max(p.z for p in pts)

    dist = max(30.0, (z_hi - z_lo) * 4.0)
    aim_z = (z_lo + z_hi) * 0.5
    want = 1.0 - 2.0 * FRAME_MARGIN

    def place(d, az_):
        cam.location = Vector((0.0, 0.0, az_)) + back * d
        direction = Vector((0.0, 0.0, az_)) - cam.location
        cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        bpy.context.view_layer.update()

    for _ in range(90):
        place(dist, aim_z)
        ndc = [world_to_camera_view(scene, cam, p) for p in pts]
        ys = [v.y for v in ndc]
        xs = [v.x for v in ndc]
        span_y = max(ys) - min(ys)
        if span_y <= 1e-6:
            break
        # world units spanned by one full frame height at the current distance
        world_per_frame = (z_hi - z_lo) / span_y
        aim_z += (((max(ys) + min(ys)) * 0.5) - 0.5) * world_per_frame * 0.9
        scale = span_y / want
        # if the stack is somehow wide enough to clip horizontally, pull back for that too
        span_x = max(xs) - min(xs)
        scale = max(scale, span_x / want)
        dist *= 1.0 + (scale - 1.0) * 0.8
        if abs(scale - 1.0) < 2e-4 and abs(((max(ys) + min(ys)) * 0.5) - 0.5) < 2e-4:
            break

    place(dist, aim_z)
    ndc = [world_to_camera_view(scene, cam, p) for p in pts]
    fit = {
        "distance": round(dist, 4),
        "aim_z": round(aim_z, 4),
        "ndc_y_min": round(min(v.y for v in ndc), 4),
        "ndc_y_max": round(max(v.y for v in ndc), 4),
        "ndc_x_min": round(min(v.x for v in ndc), 4),
        "ndc_x_max": round(max(v.x for v in ndc), 4),
    }
    return cam, fit


# --------------------------------------------------------------------------------------
# Render settings
# --------------------------------------------------------------------------------------

def setup_gpu():
    """Returns (device_type, [device names]) -- OPTIX first, then CUDA, then CPU."""
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
    except KeyError:
        return "NONE", []
    chosen, names = "NONE", []
    for want in ("OPTIX", "CUDA", "HIP", "ONEAPI"):
        try:
            prefs.compute_device_type = want
        except Exception:
            continue
        for refresh in ("refresh_devices", "get_devices"):
            fn = getattr(prefs, refresh, None)
            if fn:
                try:
                    fn()
                    break
                except Exception:
                    pass
        devs = [d for d in prefs.devices if d.type == want]
        if devs:
            for d in prefs.devices:
                d.use = (d.type == want)
            chosen, names = want, [d.name for d in devs]
            break
    return chosen, names


def setup_render(scene, args, engine_pref):
    # Solve at the reference width; main() narrows resolution_x afterwards.
    scene.render.resolution_x = args.fit_width
    scene.render.resolution_y = args.height
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.render.image_settings.compression = 25
    # Standard, not AgX/Filmic -- we want #2F6FD0 to survive to the PNG.
    try:
        scene.view_settings.view_transform = "Standard"
        scene.view_settings.look = "None"
    except Exception:
        pass

    device_type, device_names = "NONE", []
    engine = None
    if engine_pref in ("auto", "cycles"):
        try:
            scene.render.engine = "CYCLES"
            device_type, device_names = setup_gpu()
            scene.cycles.device = "GPU" if device_type != "NONE" else "CPU"
            scene.cycles.samples = args.samples
            scene.cycles.use_adaptive_sampling = True
            scene.cycles.adaptive_threshold = 0.01
            scene.cycles.use_denoising = True
            for dn in ("OPTIX", "OPENIMAGEDENOISE"):
                try:
                    scene.cycles.denoiser = dn
                    break
                except Exception:
                    continue
            scene.cycles.max_bounces = 6
            scene.cycles.transparent_max_bounces = 4
            scene.cycles.caustics_reflective = False
            scene.cycles.caustics_refractive = False
            engine = "CYCLES"
        except Exception as exc:
            print(f"[plates] Cycles setup failed ({exc}); falling back to EEVEE")
            engine = None
    if engine is None:
        for name in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
            try:
                scene.render.engine = name
                engine = name
                break
            except Exception:
                continue
        try:
            scene.eevee.taa_render_samples = max(64, args.samples)
            scene.eevee.use_raytracing = True
        except Exception:
            pass
    return engine, device_type, device_names


def clean_transparent_rgb(path):
    """Zero the colour channels of fully transparent pixels.

    Cycles writes non-premultiplied RGBA, so the RGB channels still carry sampled light
    everywhere alpha is 0. It is invisible composited as-is, but it roughly doubles PNG
    size (an empty frame_00 lands at 178 KB instead of 4 KB) and can bleed a colour halo
    once the tile scales the image with alpha-unaware filtering. Blender bundles numpy,
    so this needs no dependency beyond Blender itself.

    Returns True if the file was rewritten.
    """
    import numpy as np

    img = bpy.data.images.load(path)
    try:
        for cs in ("Raw", "Non-Color"):
            try:
                img.colorspace_settings.name = cs   # identity transform, so it round-trips
                break
            except Exception:
                continue
        px = np.empty(len(img.pixels), dtype=np.float32)
        img.pixels.foreach_get(px)
        px = px.reshape(-1, 4)
        mask = px[:, 3] <= 0.0
        if not mask.any():
            return False
        px[mask, :3] = 0.0
        img.pixels.foreach_set(px.reshape(-1))
        img.filepath_raw = path
        img.file_format = "PNG"
        img.save()
        return True
    finally:
        bpy.data.images.remove(img)


def write_downscaled_proof(src_path, dst_path, target_width):
    """Box-downscale one rendered frame for a design proof.

    Done properly rather than with a naive resize: the RGB under fully transparent pixels
    is zero (see clean_transparent_rgb), so averaging straight-alpha RGB across a silhouette
    edge would drag the edge toward black and ring the stack with a dark halo. So the
    average is taken on premultiplied values, in linear light, then un-premultiplied.
    Exact area-average for any ratio: pixels are repeated `up` times then box-averaged by
    `down`, where up/down is w:target reduced by their gcd (240->120 is 1:2, 300->120 is
    2:5). No resampling filter, no fractional coverage, no halo.
    """
    import math as _math

    import numpy as np

    img = bpy.data.images.load(src_path)
    try:
        for cs in ("Raw", "Non-Color"):
            try:
                img.colorspace_settings.name = cs
                break
            except Exception:
                continue
        w, h = img.size
        g = _math.gcd(w, target_width)
        up, down = target_width // g, w // g
        if (h * up) % down:
            raise SystemExit(f"[plates] proof width {target_width} does not divide "
                             f"{w}x{h} to whole pixels")
        tw, th = target_width, h * up // down

        px = np.empty(len(img.pixels), dtype=np.float32)
        img.pixels.foreach_get(px)
        px = px.reshape(h, w, 4)

        srgb = px[..., :3]
        lin = np.where(srgb <= 0.04045, srgb / 12.92, ((srgb + 0.055) / 1.055) ** 2.4)
        a = px[..., 3:4]

        pm = lin * a
        if up != 1:
            pm = np.repeat(np.repeat(pm, up, axis=0), up, axis=1)
            a = np.repeat(np.repeat(a, up, axis=0), up, axis=1)
        pm = pm.reshape(th, down, tw, down, 3).mean(axis=(1, 3))
        aa = a.reshape(th, down, tw, down, 1).mean(axis=(1, 3))
        out_lin = np.where(aa > 1e-6, pm / np.maximum(aa, 1e-6), 0.0)
        out_srgb = np.where(out_lin <= 0.0031308,
                            out_lin * 12.92,
                            1.055 * np.maximum(out_lin, 0.0) ** (1 / 2.4) - 0.055)
        out = np.concatenate([np.clip(out_srgb, 0.0, 1.0), aa], axis=2)
    finally:
        bpy.data.images.remove(img)

    dst = bpy.data.images.new("proof", width=tw, height=th, alpha=True)
    try:
        for cs in ("Raw", "Non-Color"):
            try:
                dst.colorspace_settings.name = cs
                break
            except Exception:
                continue
        dst.alpha_mode = "STRAIGHT"
        dst.pixels.foreach_set(out.reshape(-1).astype(np.float32))
        dst.filepath_raw = dst_path
        dst.file_format = "PNG"
        dst.save()
    finally:
        bpy.data.images.remove(dst)
    return tw, th


# --------------------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------------------

def main():
    global PLATE_THICKNESS
    args = parse_args(sys.argv)
    PLATE_THICKNESS = args.thickness
    t_start = time.time()

    max_plates = args.frames - 1
    out_dir = os.path.abspath(args.out)
    if args.preview:
        out_dir = os.path.join(out_dir, "preview")
    os.makedirs(out_dir, exist_ok=True)

    clear_scene()
    scene = bpy.context.scene

    mat = make_material()
    plates, smooth_mode = build_stack(max_plates, args.seed, mat)
    stack_height = max_plates * PLATE_THICKNESS
    build_lighting(stack_height, args.light_scale)

    if args.preview:
        args.width = max(2, args.width // 2)
        args.fit_width = max(2, args.fit_width // 2)
        args.height = max(2, args.height // 2)

    engine, device_type, device_names = setup_render(scene, args, args.engine)
    cam, fit = build_camera(max_plates, args.seed, scene)

    # Narrow the canvas *after* the camera is solved. The camera keeps its solved distance,
    # aim and rotation, and sensor_fit stays AUTO -- which keys off the larger dimension,
    # still the 1500 px height -- so the vertical FOV is untouched and this is a pure
    # horizontal crop about the frame centre. Frame k keeps the exact height and position
    # it has in the full-width set.
    if args.width != args.fit_width:
        if args.width > args.height or args.fit_width > args.height:
            raise SystemExit("[plates] narrowing assumes height is the larger dimension "
                             "(sensor_fit AUTO); refusing to render a landscape canvas.")
        scene.render.resolution_x = args.width
        print(f"[plates] narrowed canvas {args.fit_width} -> {args.width} px "
              f"(horizontal crop only; vertical framing unchanged)")

    print(f"[plates] engine={engine} device={device_type} {device_names} "
          f"samples={args.samples} size={args.width}x{args.height} smooth={smooth_mode}")
    print(f"[plates] camera fit: {fit}")

    if args.save_blend:
        blend_path = os.path.join(os.path.dirname(os.path.abspath(args.out)), "plates.blend")
        bpy.ops.wm.save_as_mainfile(filepath=blend_path)
        print(f"[plates] saved {blend_path}")

    frame_list = [1, 25, 50] if args.preview else list(range(args.frames))
    frame_list = [k for k in frame_list if 0 <= k <= max_plates]

    timings = {}
    for k in frame_list:
        for i, obj in enumerate(plates):
            obj.hide_render = (i >= k)
        path = os.path.join(out_dir, f"frame_{k:02d}.png")
        scene.render.filepath = path
        t0 = time.time()
        bpy.ops.render.render(write_still=True)
        clean_transparent_rgb(path)
        dt = time.time() - t0
        timings[k] = round(dt, 2)
        size_kb = os.path.getsize(path) / 1024.0 if os.path.exists(path) else -1
        print(f"[plates] frame {k:02d}/{max_plates}  {dt:6.2f}s  {size_kb:8.1f} KB  {path}",
              flush=True)

    proofs = []
    if args.proof_frame is not None:
        for pk in args.proof_frame:
            src = os.path.join(out_dir, f"frame_{pk:02d}.png")
            if not os.path.exists(src):
                print(f"[plates] proof skipped, {src} was not rendered")
                continue
            dst = os.path.join(out_dir, f"preview_{pk:02d}_{args.proof_width}w.png")
            tw, th = write_downscaled_proof(src, dst, args.proof_width)
            proofs.append(dst)
            print(f"[plates] proof {tw}x{th}  {os.path.getsize(dst) / 1024:.1f} KB  {dst}")

    times = list(timings.values())
    manifest = {
        "generator": "tools/milestone-render/render_plates.py",
        "blender_version": bpy.app.version_string,
        "engine": engine,
        "device_type": device_type,
        "devices": device_names,
        "samples": args.samples,
        "preview": args.preview,
        "frame_count": len(frame_list),
        "steps": max_plates,
        "step_percent": round(100.0 / max(1, max_plates), 4),
        "frames": frame_list,
        "frame_naming": "frame_XX.png, where XX = number of plates shown (0..%d)" % max_plates,
        "app_usage": "frame index = round(progress * %d); cross-fade between neighbours" % max_plates,
        "image_size": [args.width, args.height],
        "camera_fit_width": args.fit_width,
        "narrowed": args.width != args.fit_width,
        "proofs": [os.path.basename(p) for p in proofs],
        "background": "transparent (RGBA, 8-bit PNG)",
        "plate": {
            "diameter": PLATE_DIAMETER,
            "thickness": PLATE_THICKNESS,
            "hole_diameter": HOLE_DIAMETER,
            "color_hex": "#" + PLATE_COLOR_HEX,
            "roughness": PLATE_ROUGHNESS,
            "metallic": PLATE_METALLIC,
            "rot_jitter_deg": ROT_JITTER_DEG,
            "pos_jitter": POS_JITTER,
            "seed": args.seed,
        },
        "camera": {
            "lens_mm": CAM_LENS_MM,
            "elevation_deg": CAM_ELEVATION_DEG,
            "azimuth_deg": CAM_AZIMUTH_DEG,
            "margin": FRAME_MARGIN,
            "fit": fit,
        },
        "timing": {
            "seconds_per_frame": timings,
            "mean_seconds_per_frame": round(sum(times) / len(times), 2) if times else None,
            "total_seconds": round(time.time() - t_start, 2),
        },
    }
    manifest_path = os.path.join(out_dir, "manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2)
    print(f"[plates] wrote {manifest_path}")
    print(f"[plates] done in {manifest['timing']['total_seconds']}s")


if __name__ == "__main__":
    main()
