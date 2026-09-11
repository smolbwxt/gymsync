"""
GymSync milestone -- top rung: a column of 45 lb plates bridging Earth to the moon.

Symbolic scale throughout, deliberately not real: the moon sits 4.5 Earth radii away
(really ~60) and the plates are 0.22 Earth radii across, so the ribbing still reads.

Frame k (0..50) shows the column covering k/50 of the gap between the two surfaces,
always ending on a whole plate. Frame 0 is Earth + moon with no column.

    blender -b -P tools/milestone-render/render_earth_moon.py -- \
        --out tools/milestone-render/out-earth-moon --frames 51 --size 1200x1200 --samples 96

Plate geometry, material, GPU selection, the transparent-pixel cleanup and the proof
downscaler are all imported from render_plates.py rather than duplicated.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
import time

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render_plates as rp   # noqa: E402  (needs the path fix above)


# --------------------------------------------------------------------------------------
# Scene constants -- symbolic, tuned for legibility rather than astronomy
# --------------------------------------------------------------------------------------

EARTH_RADIUS = 1.0
MOON_RADIUS = 0.30
CENTRE_DISTANCE = 4.5 * EARTH_RADIUS      # real is ~60; compressed hard for framing
AXIS_TILT_DEG = 26.0                      # lifts the moon to the upper right of frame

PLATE_DIAMETER = 0.22 * EARTH_RADIUS
COLUMN_PLATES = 60                        # plates in the full column at frame 50

OCEAN_DEEP = "0E2C3A"
OCEAN_SHALLOW = "17506B"
LAND_DARK = "35513C"
LAND_LIGHT = "4E6E4F"
ATMOSPHERE = "7FC4E8"
MOON_LIGHT = "C2C2BA"
MOON_DARK = "8C8C85"

CAM_ELEVATION_DEG = 17.0
CAM_AZIMUTH_DEG = -115.0
CAM_LENS_MM = 60.0
FRAME_MARGIN = 0.05


def axis_direction():
    t = math.radians(AXIS_TILT_DEG)
    return Vector((math.cos(t), 0.0, math.sin(t)))


def moon_centre():
    return axis_direction() * CENTRE_DISTANCE


def column_span():
    """(start point on Earth's surface, unit direction, total gap length)."""
    d = axis_direction()
    start = d * EARTH_RADIUS
    end = moon_centre() - d * MOON_RADIUS
    return start, d, (end - start).length


# --------------------------------------------------------------------------------------
# Shading -- all procedural, no image textures
# --------------------------------------------------------------------------------------

def _hex(h):
    return rp.hex_to_linear_rgba(h)


def make_earth_material():
    mat = bpy.data.materials.new("Earth")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]

    coord = nt.nodes.new("ShaderNodeTexCoord")
    # Object coordinates so the pattern is locked to the sphere, not the camera.
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 2.4
    noise.inputs["Detail"].default_value = 8.0
    noise.inputs["Roughness"].default_value = 0.55
    nt.links.new(coord.outputs["Object"], noise.inputs["Vector"])

    # Landmasses: a hard-ish threshold on the noise gives a coastline instead of a smear.
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "LINEAR"
    stops = [
        (0.00, OCEAN_DEEP),
        (0.44, OCEAN_SHALLOW),
        (0.535, OCEAN_SHALLOW),
        (0.555, LAND_DARK),
        (0.70, LAND_LIGHT),
        (1.00, LAND_DARK),
    ]
    el = ramp.color_ramp.elements
    while len(el) > 1:
        el.remove(el[-1])
    el[0].position, el[0].color = stops[0][0], _hex(stops[0][1])
    for pos, col in stops[1:]:
        e = el.new(pos)
        e.color = _hex(col)
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])

    # Ocean reads smoother than land.
    rough = nt.nodes.new("ShaderNodeValToRGB")
    rough.color_ramp.elements[0].position = 0.49
    rough.color_ramp.elements[0].color = (0.28, 0.28, 0.28, 1.0)
    rough.color_ramp.elements[1].position = 0.52
    rough.color_ramp.elements[1].color = (0.85, 0.85, 0.85, 1.0)
    nt.links.new(noise.outputs["Fac"], rough.inputs["Fac"])
    nt.links.new(rough.outputs["Color"], bsdf.inputs["Roughness"])
    bsdf.inputs["Metallic"].default_value = 0.0
    for k in ("Specular IOR Level", "Specular"):
        if k in bsdf.inputs:
            bsdf.inputs[k].default_value = 0.25
    return mat


def make_atmosphere_material():
    """A thin Fresnel-driven emissive shell. Transparent head-on, glowing at the limb."""
    mat = bpy.data.materials.new("Atmosphere")
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        if n.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(n)
    out = nt.nodes["Material Output"]

    emis = nt.nodes.new("ShaderNodeEmission")
    emis.inputs["Color"].default_value = _hex(ATMOSPHERE)
    emis.inputs["Strength"].default_value = 1.0
    transp = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")

    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.30
    # Layer Weight "Facing" is 0 head-on and 1 at grazing angles, so the ramp keeps the
    # glow to a thin band at the limb: fac 0 -> transparent, fac 1 -> emission.
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.62
    ramp.color_ramp.elements[1].position = 1.0
    nt.links.new(lw.outputs["Facing"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], mix.inputs["Fac"])
    nt.links.new(transp.outputs["BSDF"], mix.inputs[1])
    nt.links.new(emis.outputs["Emission"], mix.inputs[2])
    nt.links.new(mix.outputs["Shader"], out.inputs["Surface"])
    return mat


def make_moon_material():
    mat = bpy.data.materials.new("Moon")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]

    coord = nt.nodes.new("ShaderNodeTexCoord")
    craters = nt.nodes.new("ShaderNodeTexVoronoi")
    craters.inputs["Scale"].default_value = 9.0
    craters.feature = "F1"
    nt.links.new(coord.outputs["Object"], craters.inputs["Vector"])

    grain = nt.nodes.new("ShaderNodeTexNoise")
    grain.inputs["Scale"].default_value = 14.0
    grain.inputs["Detail"].default_value = 6.0
    nt.links.new(coord.outputs["Object"], grain.inputs["Vector"])

    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.15
    ramp.color_ramp.elements[0].color = _hex(MOON_DARK)
    ramp.color_ramp.elements[1].position = 0.75
    ramp.color_ramp.elements[1].color = _hex(MOON_LIGHT)
    nt.links.new(craters.outputs["Distance"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])

    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.35
    nt.links.new(grain.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])

    bsdf.inputs["Roughness"].default_value = 0.9
    bsdf.inputs["Metallic"].default_value = 0.0
    for k in ("Specular IOR Level", "Specular"):
        if k in bsdf.inputs:
            bsdf.inputs[k].default_value = 0.15
    return mat


# --------------------------------------------------------------------------------------
# Bodies and column
# --------------------------------------------------------------------------------------

def add_sphere(name, location, radius, mat, segments=96, rings=48):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings,
                                         radius=radius, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.data.materials.append(mat)
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


def build_bodies():
    earth = add_sphere("Earth", (0.0, 0.0, 0.0), EARTH_RADIUS, make_earth_material())
    atmo = add_sphere("Atmosphere", (0.0, 0.0, 0.0), EARTH_RADIUS * 1.035,
                      make_atmosphere_material(), segments=64, rings=32)
    # The shell must not shadow or bounce light onto the planet it wraps.
    atmo.visible_shadow = False
    atmo.visible_diffuse = False
    atmo.visible_glossy = False
    moon = add_sphere("Moon", tuple(moon_centre()), MOON_RADIUS, make_moon_material())
    return earth, atmo, moon


def build_column():
    """COLUMN_PLATES plates stacked face-to-face from Earth's surface toward the moon."""
    start, direction, gap = column_span()
    thickness = gap / COLUMN_PLATES

    # The shared plate mesh is authored at diameter 1.0, so scaling the object by the
    # target diameter also scales thickness; author the mesh thicker to compensate and
    # everything (rim, hole, chamfer) stays proportional.
    rp.PLATE_THICKNESS = thickness / PLATE_DIAMETER
    mesh = rp.build_plate_mesh("Plate45_EM")
    mesh.materials.append(rp.make_material())

    rot = direction.to_track_quat("Z", "Y").to_euler()
    plates = []
    for i in range(COLUMN_PLATES):
        obj = bpy.data.objects.new(f"plate_{i:02d}", mesh)
        obj.location = start + direction * ((i + 0.5) * thickness)
        obj.rotation_euler = rot
        obj.scale = (PLATE_DIAMETER, PLATE_DIAMETER, PLATE_DIAMETER)
        bpy.context.collection.objects.link(obj)
        plates.append(obj)
    rp.apply_auto_smooth(plates)
    return plates, thickness


def plates_for_frame(k, frames):
    """Column covers k/(frames-1) of the gap, always ending on a whole plate."""
    return int(round(COLUMN_PLATES * k / max(1, frames - 1)))


# --------------------------------------------------------------------------------------
# Lighting -- key from the right so Earth gets a real terminator
# --------------------------------------------------------------------------------------

def _receiver_collection(name, objs):
    coll = bpy.data.collections.new(name)
    for o in objs:
        coll.objects.link(o)
    return coll


def build_lighting(main_objs, moon_objs, scale=1.0, plate_rim=True):
    # Cycles light linking. The moon needs a much more frontal key than the Earth (it is
    # the destination and has to read at 400 px), but one shared light cannot do both:
    # the direction that leaves Earth with a terminator leaves the moon 65% dark. So the
    # moon gets its own lamp and is excluded from the Earth's.
    main_coll = _receiver_collection("lit_main", main_objs)
    moon_coll = _receiver_collection("lit_moon", moon_objs)

    def sun(name, direction, energy, angle_deg, color=(1.0, 1.0, 1.0), receivers=None):
        data = bpy.data.lights.new(name, type="SUN")
        data.energy = energy * scale
        data.angle = math.radians(angle_deg)
        data.color = color
        obj = bpy.data.objects.new(name, data)
        obj.rotation_euler = Vector(direction).to_track_quat("-Z", "Y").to_euler()
        bpy.context.collection.objects.link(obj)
        if receivers is not None:
            try:
                obj.light_linking.receiver_collection = receivers
            except Exception as exc:
                raise SystemExit(
                    f"[earth-moon] light linking unavailable ({exc}); this scene needs it "
                    "to light the moon separately from the Earth.")
        return obj

    # Suns, not area lights: the scene is ~5 units wide and inverse-square falloff would
    # leave the moon end of the column much dimmer than the Earth end.
    # Key from screen-right, solved rather than guessed. The lit hemisphere faces L; the
    # fraction of the visible disc that is lit follows dot(L, view). 0.10 gave a bare
    # crescent on both bodies, 0.62 washed the Earth flat with no terminator at all;
    # 0.30 leaves roughly two thirds lit with the terminator clearly on the left.
    sun("key", (-0.739, 0.572, -0.357), energy=5.2, angle_deg=2.0, receivers=main_coll)
    # Fill from screen-LEFT, not from the camera. A camera-side fill lights the whole
    # visible disc evenly and erases the terminator the key just built; from the left it
    # only lifts the dark limb.
    sun("fill", (0.85, -0.40, -0.25), energy=0.30, angle_deg=40.0,
        color=(0.62, 0.72, 1.0), receivers=main_coll)
    if plate_rim:
        # Faint rim aimed back toward the camera so the column keeps an edge where it
        # crosses Earth's dark limb. Deliberately weak; it must not flatten the terminator.
        sun("plate_rim", (0.30, -0.86, -0.42), energy=0.7, angle_deg=25.0,
            color=(0.78, 0.86, 1.0), receivers=main_coll)

    # Moon-only key. The lit fraction of a sphere's visible disc is (1 + dot(L, view))/2,
    # so dot = 0.715 puts ~86% of the moon in light -- it reads as the destination rather
    # than as a dark smudge -- while the Earth keeps its dot = 0.30 terminator.
    sun("moon_key", (-0.341, 0.843, -0.416), energy=4.6, angle_deg=3.0,
        receivers=moon_coll)
    sun("moon_fill", (0.80, -0.45, -0.30), energy=0.35, angle_deg=45.0,
        color=(0.70, 0.76, 0.95), receivers=moon_coll)

    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.0, 0.0, 0.0, 1.0)
    bg.inputs[1].default_value = 0.0
    bpy.context.scene.world = world


# --------------------------------------------------------------------------------------
# Camera -- fixed, framed on Earth + moon + full column
# --------------------------------------------------------------------------------------

def sample_points():
    pts = []

    def sphere(centre, radius, n=180):
        # Fibonacci sphere -- even coverage without a pole cluster.
        ga = math.pi * (3.0 - math.sqrt(5.0))
        for i in range(n):
            z = 1.0 - 2.0 * i / (n - 1)
            r = math.sqrt(max(0.0, 1.0 - z * z))
            a = ga * i
            pts.append(Vector(centre) + Vector((math.cos(a) * r, math.sin(a) * r, z)) * radius)

    sphere((0.0, 0.0, 0.0), EARTH_RADIUS * 1.035)
    sphere(tuple(moon_centre()), MOON_RADIUS)
    start, direction, gap = column_span()
    for f in (0.0, 0.5, 1.0):
        centre = start + direction * (gap * f)
        for i in range(16):
            a = i * math.tau / 16
            perp1 = direction.cross(Vector((0, 0, 1))).normalized()
            perp2 = direction.cross(perp1).normalized()
            pts.append(centre + (perp1 * math.cos(a) + perp2 * math.sin(a))
                       * (PLATE_DIAMETER * 0.5))
    return pts


def build_camera(scene):
    from bpy_extras.object_utils import world_to_camera_view

    cam_data = bpy.data.cameras.new("Camera")
    cam_data.lens = CAM_LENS_MM
    cam = bpy.data.objects.new("Camera", cam_data)
    bpy.context.collection.objects.link(cam)
    scene.camera = cam

    el = math.radians(CAM_ELEVATION_DEG)
    az = math.radians(CAM_AZIMUTH_DEG)
    back = Vector((math.cos(el) * math.cos(az), math.cos(el) * math.sin(az), math.sin(el)))

    pts = sample_points()
    aim = Vector((0.0, 0.0, 0.0))
    for p in pts:
        aim += p
    aim /= len(pts)
    dist = 14.0
    want = 1.0 - 2.0 * FRAME_MARGIN

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
        # World size of one full frame at the aim plane, for a perspective camera.
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
# Main
# --------------------------------------------------------------------------------------

def parse_args(argv):
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    p = argparse.ArgumentParser(prog="render_earth_moon.py")
    p.add_argument("--out", default="tools/milestone-render/out-earth-moon")
    p.add_argument("--frames", type=int, default=51)
    p.add_argument("--size", default="1200x1200")
    p.add_argument("--samples", type=int, default=96)
    p.add_argument("--only", type=int, nargs="+", default=None,
                   help="render just these frames (quick look)")
    p.add_argument("--proof-frame", type=int, nargs="+", default=None)
    p.add_argument("--proof-width", type=int, default=400)
    p.add_argument("--light-scale", type=float, default=1.0)
    p.add_argument("--no-plate-rim", action="store_true")
    p.add_argument("--save-blend", action="store_true")
    args = p.parse_args(argv)
    w, _, h = args.size.lower().partition("x")
    args.width, args.height = int(w), int(h)
    args.fit_width = args.width
    return args


def main():
    args = parse_args(sys.argv)
    t_start = time.time()
    out_dir = os.path.abspath(args.out)
    os.makedirs(out_dir, exist_ok=True)

    rp.clear_scene()
    scene = bpy.context.scene

    earth, atmo, moon = build_bodies()
    plates, thickness = build_column()
    build_lighting([earth, atmo] + plates, [moon], args.light_scale,
                   plate_rim=not args.no_plate_rim)

    engine, device_type, device_names = rp.setup_render(scene, args, "auto")
    cam, fit = build_camera(scene)

    print(f"[earth-moon] engine={engine} device={device_type} {device_names} "
          f"samples={args.samples} size={args.width}x{args.height}")
    print(f"[earth-moon] column: {COLUMN_PLATES} plates, thickness {thickness:.5f}, "
          f"diameter {PLATE_DIAMETER}, gap {column_span()[2]:.4f}")
    print(f"[earth-moon] camera fit: {fit}")

    if args.save_blend:
        blend = os.path.join(os.path.dirname(out_dir), "earth_moon.blend")
        bpy.ops.wm.save_as_mainfile(filepath=blend)
        print(f"[earth-moon] saved {blend}")

    frame_list = args.only if args.only else list(range(args.frames))
    timings = {}
    for k in frame_list:
        n = plates_for_frame(k, args.frames)
        for i, obj in enumerate(plates):
            obj.hide_render = (i >= n)
        path = os.path.join(out_dir, f"frame_{k:02d}.png")
        scene.render.filepath = path
        t0 = time.time()
        bpy.ops.render.render(write_still=True)
        rp.clean_transparent_rgb(path)
        dt = time.time() - t0
        timings[k] = round(dt, 2)
        print(f"[earth-moon] frame {k:02d}/{args.frames - 1}  {n:2d} plates  {dt:6.2f}s  "
              f"{os.path.getsize(path) / 1024:8.1f} KB", flush=True)

    proofs = []
    for pk in (args.proof_frame or []):
        src = os.path.join(out_dir, f"frame_{pk:02d}.png")
        if not os.path.exists(src):
            print(f"[earth-moon] proof skipped, {src} not rendered")
            continue
        dst = os.path.join(out_dir, f"preview_{pk:02d}_{args.proof_width}.png")
        tw, th = rp.write_downscaled_proof(src, dst, args.proof_width)
        proofs.append(dst)
        print(f"[earth-moon] proof {tw}x{th}  {os.path.getsize(dst) / 1024:.1f} KB  {dst}")

    times = list(timings.values())
    manifest = {
        "generator": "tools/milestone-render/render_earth_moon.py",
        "blender_version": bpy.app.version_string,
        "engine": engine,
        "device_type": device_type,
        "devices": device_names,
        "samples": args.samples,
        "frame_count": len(frame_list),
        "steps": args.frames - 1,
        "step_percent": round(100.0 / max(1, args.frames - 1), 4),
        "frames": frame_list,
        "frame_naming": "frame_XX.png; frame k = column covering k/%d of the gap"
                        % (args.frames - 1),
        "app_usage": "frame index = round(progress * %d); cross-fade between neighbours"
                     % (args.frames - 1),
        "image_size": [args.width, args.height],
        "background": "transparent (RGBA, 8-bit PNG); app paints #0A0B0D behind",
        "scene": {
            "earth_radius": EARTH_RADIUS,
            "moon_radius": MOON_RADIUS,
            "centre_distance_earth_radii": CENTRE_DISTANCE / EARTH_RADIUS,
            "surface_gap": round(column_span()[2], 5),
            "axis_tilt_deg": AXIS_TILT_DEG,
            "column_plates_full": COLUMN_PLATES,
            "plate_diameter": PLATE_DIAMETER,
            "plate_thickness": round(thickness, 6),
            "plate_color_hex": "#" + rp.PLATE_COLOR_HEX,
            "ocean_hex": ["#" + OCEAN_DEEP, "#" + OCEAN_SHALLOW],
            "land_hex": ["#" + LAND_DARK, "#" + LAND_LIGHT],
            "atmosphere_hex": "#" + ATMOSPHERE,
        },
        "camera": {
            "lens_mm": CAM_LENS_MM,
            "elevation_deg": CAM_ELEVATION_DEG,
            "azimuth_deg": CAM_AZIMUTH_DEG,
            "margin": FRAME_MARGIN,
            "fit": fit,
        },
        "proofs": [os.path.basename(p) for p in proofs],
        "timing": {
            "seconds_per_frame": timings,
            "mean_seconds_per_frame": round(sum(times) / len(times), 2) if times else None,
            "total_seconds": round(time.time() - t_start, 2),
        },
    }
    with open(os.path.join(out_dir, "manifest.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2)
    print(f"[earth-moon] done in {manifest['timing']['total_seconds']}s")


if __name__ == "__main__":
    main()
