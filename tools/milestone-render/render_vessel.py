"""
GymSync MASS milestones -- an animal-shaped glass vessel poured full of 45 lb plates.

The filled volume is the progress bar: fill = lifted_lb / animal_lb. First animal is the
blue whale (300,000 lb). The level is continuous -- it is a count of visible plates, not a
frame index -- so the app is NOT constrained to any particular number of steps.

    blender -b -P tools/milestone-render/render_vessel.py -- \
        --out tools/milestone-render/out-vessel --fills 0.30 0.65 1.00 \
        --size 1200x800 --samples 96 --preview-width 600

The shell is a real CC0 whale mesh (see ASSETS.md), not a procedural body. A welded, voxel
-remeshed copy of it is used as the point-inside test for surviving plates and as the
carrier for the faint interior haze, so the fill can never drift outside the silhouette.

Pass 3 replaced the lattice fill with a rigid-body POUR: plates spawn in a loose staggered
grid (some deliberately above the shell, as a "reservoir" that rains in), fall under gravity
through a passive mesh collider shaped like the shell, and settle -- including into the fin,
fluke and head cavities a fixed horizontal lattice could never reach because they are too
thin for a whole flat layer to fit. Spawn every candidate cell (plus a reservoir pouring in
from above), settle once, then drop whatever ends up outside the strict inside-test or above
the shell: the survivors of that one bake are used for every fill level (lowest by settled
height first -- the liquid rule).

Pass 3 also replaced the pass-2 glass, which read as chrome: a broad neutral emission layer
covered most of the face-on surface (visible against the black background), with a real BSDF
only at the grazing edges -- exactly backwards, and exactly what makes a smooth body look like
a polished chrome mirror under a few bright lights. The fix mixes Glass and Transparent BSDFs
by the *same* sense a Fresnel effect actually has: grazing catches Glass (the highlight/edge),
face-on is nearly invisible Transparent -- plus a Subdivision Surface so the 444-tri silhouette
reads as a smooth body, not a facet fan, and two lights (soft key, narrow rim) instead of four.

Plate geometry and material, GPU setup, alpha cleanup and the downscaler come from
render_plates.py.
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
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render_plates as rp   # noqa: E402


# --------------------------------------------------------------------------------------
# Constants
# --------------------------------------------------------------------------------------

ASSET = "assets/whale.glb"
BODY_LENGTH = 6.0

ANIMAL_NAME = "Blue whale"
ANIMAL_LB = 300000

PLATE_THICK_RATIO = 0.085  # a real 45 is 17.7in across x 1.5in thick -> ratio ~0.085
ROT_JITTER_DEG = 8.0       # initial tilt jitter (x/y); yaw is fully random -- the plate
                           # profile is a solid of revolution, so yaw never reads visually
SEED = 20260905

SHELL_TINT = "F2FAFF"      # near-clear; a real tint muddied the plates to navy
HAZE_COLOR = "9FC4DA"

CAM_ELEVATION_DEG = 16.0
CAM_AZIMUTH_DEG = -96.0
CAM_LENS_MM = 70.0
FRAME_MARGIN = 0.05

TEST_SHRINK = 0.965        # inside-test proxy is shrunk so plates stay clear of the glass
SHELL_SUBSURF_LEVELS = 2   # shared by the render shell and the inside-test proxy -- they
                           # must match, or the proxy's silhouette drifts from what's drawn

# -- Rigid-body pour --------------------------------------------------------------------
POUR_OVERFILL = 1.3        # scales the pour reservoir (the extra top layer that rains in);
                           # every interior candidate cell is always spawned regardless
PACK_LOOSE = 1.18          # spawn-grid spacing, x plate diameter -- loose, not touching
POUR_HEADROOM_FRAC = 0.12  # fraction of body height spawned as a reservoir above the shell
RESERVOIR_FRAC = 0.15      # fraction of the overfill budget drawn from that reservoir
JITTER_XY_FRAC = 0.12      # per-plate spawn jitter, x plate diameter

SIM_SUBSTEPS = 10
SIM_SOLVER_ITERATIONS = 20

SHELL_FRICTION = 0.5
SHELL_COLLISION_MARGIN = 0.006
COLLIDER_VOXEL = 0.05      # only used for the leaky-mesh fallback collider

PLATE_MASS = 1.0
PLATE_FRICTION = 0.6
PLATE_RESTITUTION = 0.05
PLATE_LIN_DAMPING = 0.3
PLATE_ANG_DAMPING = 0.5
PLATE_COLLISION_MARGIN = 0.0015   # small relative to plate thickness -- default 0.04
                                  # would be most of a plate's height and float the stack

# -- Pass 4 shading (cosmetic only -- nothing above this line affects the pour) ----------
EDGE_GLOW_COLOR = "DFE7EC"      # shell rim self-glow AND plate rim tint share this hue
EDGE_GLOW_STRENGTH = 0.15       # shell rim emission strength, spec range 0.15-0.4
PLATE_RIM_LIFT = 0.28           # 0=no rim brighten, 1=fully white at the rim (lightening
                                 # toward white is itself a desaturation -- keep this modest
                                 # or the rim swamps the face-median measurement)
PLATE_HOLE_RADIUS = 0.13        # local units (diameter=1.0); a hair past rp.HOLE_RADIUS
                                # (0.11), so the decal clears the modelled hub geometry
PLATE_HOLE_DARKEN = 0.85        # 0=no bore decal, 1=fully black at centre
BEVEL_WIDTH_RATIO = 0.08        # x plate thickness, per spec
BEVEL_SEGMENTS = 2
HAZE_EMISSION_STRENGTH = 0.025  # independent of --haze (scatter density); Volume Emission
                                # has no density input of its own to tie it to


# --------------------------------------------------------------------------------------
# Shell: import, weld, orient, scale
# --------------------------------------------------------------------------------------

def _bbox_world(obj):
    """From vertices, not obj.bound_box: bound_box is cached and goes stale after a bmesh
    write, which silently returned pre-weld dimensions and made the long-axis test pick
    the wrong axis (the whale then imported 15 units wide and 6 long)."""
    mw = obj.matrix_world
    cs = [mw @ v.co for v in obj.data.vertices]
    lo = Vector((min(c.x for c in cs), min(c.y for c in cs), min(c.z for c in cs)))
    hi = Vector((max(c.x for c in cs), max(c.y for c in cs), max(c.z for c in cs)))
    return lo, hi


def load_shell(path, target_length=BODY_LENGTH):
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.context.scene.objects
           if o not in before and o.type == "MESH"]
    if not new:
        raise SystemExit(f"[vessel] no mesh found in {path}")

    # Bake every world transform straight into mesh data instead of using
    # bpy.ops.object.transform_apply, which is a silent no-op in this headless context --
    # it left the whale unrotated and 15 units wide. matrix_world already folds in the
    # glTF empties' Y-up -> Z-up conversion, so no parent_clear is needed either.
    seen = set()
    for o in new:
        if o.data.name in seen:
            continue
        seen.add(o.data.name)
        o.data.transform(o.matrix_world)
        o.matrix_world = Matrix.Identity(4)

    bpy.ops.object.select_all(action="DESELECT")
    for o in new:
        o.select_set(True)
    bpy.context.view_layer.objects.active = new[0]
    if len(new) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = "WhaleShell"
    for o in list(bpy.context.scene.objects):
        if o.type == "EMPTY":
            bpy.data.objects.remove(o, do_unlink=True)

    # glTF splits vertices per face for flat shading, which leaves the mesh technically
    # full of open edges (922 of 1127 here). Welding closes it before anything else.
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    open_edges = sum(1 for e in bm.edges if len(e.link_faces) != 2)
    for f in bm.faces:
        f.smooth = True
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()

    # Longest bbox axis becomes X, then scale to target length and centre on the origin.
    lo, hi = _bbox_world(obj)
    dims = hi - lo
    long_axis = max(range(3), key=lambda i: dims[i])
    if long_axis == 1:
        obj.data.transform(Matrix.Rotation(math.radians(-90.0), 4, "Z"))
    elif long_axis == 2:
        obj.data.transform(Matrix.Rotation(math.radians(90.0), 4, "Y"))

    lo, hi = _bbox_world(obj)
    if (hi.x - lo.x) < max(hi.y - lo.y, hi.z - lo.z):
        raise SystemExit("[vessel] shell's long axis is not X after reorientation")
    obj.data.transform(Matrix.Scale(target_length / (hi.x - lo.x), 4))

    lo, hi = _bbox_world(obj)
    obj.data.transform(Matrix.Translation(-(lo + hi) * 0.5))
    obj.data.update()
    return obj, open_edges


def voxel_remesh_copy(shell, name, voxel=0.05):
    """Watertight copy via voxel remesh. Guarantees a closed manifold whatever the source
    topology, independent of the shrunk inside-test proxy below."""
    obj = shell.copy()
    obj.data = shell.data.copy()
    obj.name = name
    bpy.context.collection.objects.link(obj)

    mod = obj.modifiers.new("Remesh", "REMESH")
    mod.mode = "VOXEL"
    mod.voxel_size = voxel
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj


def make_test_proxy(shell, voxel=0.05, subsurf_levels=SHELL_SUBSURF_LEVELS):
    """Watertight, slightly shrunk copy used ONLY for the strict inside test (both the
    lattice-diameter solve and the post-settle survivor filter) and the interior haze.

    Built from a SUBDIVIDED copy of the shell, matching the Catmull-Clark smoothing
    add_shell_shading adds to the render shell: without this, a plate could clear the
    sharp-cornered unsubdivided proxy while the smoothed glass silhouette -- which pulls
    inward at thin features like the dorsal fin -- had already moved past it, poking a
    "surviving" plate's rim straight through the rendered glass. The shrink on top of that
    keeps surviving plates clear of the glass.
    """
    sub = shell.copy()
    sub.data = shell.data.copy()
    sub.name = "WhaleSubdivided"
    bpy.context.collection.objects.link(sub)
    mod = sub.modifiers.new("Subdivision", "SUBSURF")
    mod.subdivision_type = "CATMULL_CLARK"
    mod.levels = subsurf_levels
    bpy.context.view_layer.objects.active = sub
    bpy.ops.object.select_all(action="DESELECT")
    sub.select_set(True)
    bpy.ops.object.modifier_apply(modifier=mod.name)

    proxy = voxel_remesh_copy(sub, "WhaleInterior", voxel)
    sub_data = sub.data
    bpy.data.objects.remove(sub, do_unlink=True)
    bpy.data.meshes.remove(sub_data)

    proxy.data.transform(Matrix.Scale(TEST_SHRINK, 4))
    proxy.data.update()
    return proxy


def make_collider(shell, open_edges, voxel=COLLIDER_VOXEL):
    """PASSIVE rigid-body collision shell. Prefers the light welded shell mesh (444 tris)
    -- it's already watertight here (0 open edges) so plates can't tunnel through a seam --
    and only falls back to an (unshrunk) voxel remesh if welding left the mesh open."""
    if open_edges == 0:
        obj = shell.copy()
        obj.data = shell.data.copy()
        obj.name = "WhaleCollider"
        bpy.context.collection.objects.link(obj)
        method = f"welded shell mesh, {len(obj.data.polygons)} tris"
    else:
        obj = voxel_remesh_copy(shell, "WhaleCollider", voxel)
        method = f"voxel remesh (unshrunk), {len(obj.data.polygons)} tris"

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)   # consistent outward normals
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    obj.hide_render = True
    return obj, method


def make_inside_test(proxy):
    """Signed-distance test against a closed mesh. closest_point_on_mesh works in the
    object's local space, and every transform has been applied, so local == world."""
    def inside(p):
        ok, loc, nor, _ = proxy.closest_point_on_mesh(p)
        return bool(ok) and (p - loc).dot(nor) < 0.0
    return inside


def add_shell_shading(shell, levels=SHELL_SUBSURF_LEVELS):
    """Kills the faceted 444-tri silhouette without touching the collider, which stays
    coarse and cheap on purpose. `levels` must match make_test_proxy's subsurf_levels --
    the strict inside test is built to track exactly this smoothed silhouette."""
    for f in shell.data.polygons:
        f.use_smooth = True
    mod = shell.modifiers.new("Subdivision", "SUBSURF")
    mod.subdivision_type = "CATMULL_CLARK"
    mod.levels = levels
    mod.render_levels = levels
    return mod


# --------------------------------------------------------------------------------------
# Materials
# --------------------------------------------------------------------------------------

def make_shell_material():
    """Real glass, not chrome -- and, as of pass 4, actually visible on the app's near-
    black ground rather than reading as pure black.

    Pass 2 mixed a Principled BSDF with a flat neutral Emission by Facing, but had the
    Facing sense backwards: Facing is *high* facing the camera and *low* at grazing edges,
    so the ramp (thresholds 0.55/0.97, both high) routed the whole face-on body -- most of
    what's on screen -- to the flat emissive rim colour, and only the true silhouette edge
    to the (already faint) BSDF. A flat, directionless emissive colour covering a smooth
    convex body under a few bright lights is exactly what a chrome sphere looks like. Pass 3
    fixed the polarity: grazing (low Facing) -> Glass, face-on (high Facing) -> Transparent.

    Pass 4 problem: composited on the app's real #0A0B0D (not the tool viewer's white),
    that fix reads as almost pure black. It's optically correct -- transparent glass with a
    black world behind it, refracting/reflecting more black, has nothing to show -- but a
    correct render of "nothing" is still nothing. A glass BSDF cannot glow on its own; it
    needs either a light positioned just right to catch a specular highlight (unreliable
    across a whole silhouette) or genuine self-emission. So pass 4 ADDS a grazing-angle
    self-glow: the same Facing signal drives a small Emission (EDGE_GLOW_COLOR, strength
    EDGE_GLOW_STRENGTH) that's ADDED on top of the Glass/Transparent mix, not blended into
    it -- so it never displaces the transmission, it just guarantees the silhouette has
    *something* to show regardless of whether any actual light lines up with the camera.
    """
    mat = bpy.data.materials.new("WhaleShell")
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)

    out = nt.nodes.new("ShaderNodeOutputMaterial")
    glass = nt.nodes.new("ShaderNodeBsdfGlass")
    glass.inputs["Color"].default_value = rp.hex_to_linear_rgba(SHELL_TINT)
    glass.inputs["Roughness"].default_value = 0.05
    glass.inputs["IOR"].default_value = 1.05

    transp = nt.nodes.new("ShaderNodeBsdfTransparent")
    transp.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)

    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.42
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.40
    ramp.color_ramp.elements[1].position = 0.82
    mix = nt.nodes.new("ShaderNodeMixShader")

    nt.links.new(lw.outputs["Facing"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], mix.inputs["Fac"])
    nt.links.new(glass.outputs["BSDF"], mix.inputs[1])     # Fac=0, grazing -> Glass
    nt.links.new(transp.outputs["BSDF"], mix.inputs[2])    # Fac=1, face-on -> Transparent

    # Grazing-angle self-glow, ADDED (not blended) on top of the mix above. Reuses `lw`'s
    # Fresnel output directly (already 0 face-on / 1 grazing -- no ramp needed, a softer
    # falloff than the hard-ish glass/transparent ramp reads better as a glow than an edge).
    glow = nt.nodes.new("ShaderNodeEmission")
    glow.inputs["Color"].default_value = rp.hex_to_linear_rgba(EDGE_GLOW_COLOR)
    glow.inputs["Strength"].default_value = EDGE_GLOW_STRENGTH
    glow_mix = nt.nodes.new("ShaderNodeMixShader")   # Fac=0 -> no glow, Fac=1 -> glow only
    black = nt.nodes.new("ShaderNodeBsdfTransparent")
    black.inputs["Color"].default_value = (0.0, 0.0, 0.0, 1.0)   # emits nothing itself
    nt.links.new(lw.outputs["Fresnel"], glow_mix.inputs["Fac"])
    nt.links.new(black.outputs["BSDF"], glow_mix.inputs[1])
    nt.links.new(glow.outputs["Emission"], glow_mix.inputs[2])

    add = nt.nodes.new("ShaderNodeAddShader")
    nt.links.new(mix.outputs["Shader"], add.inputs[0])
    nt.links.new(glow_mix.outputs["Shader"], add.inputs[1])
    nt.links.new(add.outputs["Shader"], out.inputs["Surface"])
    return mat


def make_vessel_plate_material(emission=0.45):
    """The shared plate material plus a floor of self-lit colour, a Fresnel rim lift, and
    a dark bore decal.

    Measured on the first mesh render, the median plate pixel came out #0C1D3E against a
    #2F6FD0 target: plates buried under other plates and behind glass receive almost no
    light, and only the top layer read as blue. Turning the lamps up instead would blow
    that top layer out. A small emission at the plate's own colour lifts the interior to
    the right blue and leaves the lit surfaces alone.

    Pass 4 adds two things the owner asked for directly: a Fresnel-driven rim lift (the
    same Facing/Fresnel trick as the shell -- grazing angles, i.e. a plate's silhouette
    edge as the camera sees it, read lighter than the face) so individual plates separate
    from the pile instead of reading as one navy mass even before the geometric bevel
    (applied later, post-settle, in apply_plate_bevel) has a chance to catch a highlight;
    and a dark bore decal (a real 45 has a 2in centre hole) via a radial distance test in
    the plate's own OBJECT-space coordinates -- unaffected by each plate's arbitrary
    settled rotation/scale, since Object texture coordinates are local by definition.

    Scene-local on purpose -- render_plates.py's material is untouched, so the committed
    stack and Earth-moon sets keep their solved, measured exposure.
    """
    mat = rp.make_material()
    mat.name = "PlateBlue45_Vessel"
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

    # -- Rim lift: grazing (Fresnel) edges read lighter than the face -------------------
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.35
    rim_color = tuple(min(1.0, c + (1.0 - c) * PLATE_RIM_LIFT) for c in base_color[:3])
    rim_mix = nt.nodes.new("ShaderNodeMixRGB")
    rim_mix.inputs["Color1"].default_value = base_color
    rim_mix.inputs["Color2"].default_value = (*rim_color, 1.0)
    nt.links.new(lw.outputs["Fresnel"], rim_mix.inputs["Factor"])

    # -- Bore decal: dark disc at the plate's own centre --------------------------------
    texco = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(texco.outputs["Object"], sep.inputs["Vector"])
    combine = nt.nodes.new("ShaderNodeCombineXYZ")   # drop Z -- radial distance in-plane
    nt.links.new(sep.outputs["X"], combine.inputs["X"])
    nt.links.new(sep.outputs["Y"], combine.inputs["Y"])
    radius = nt.nodes.new("ShaderNodeVectorMath")
    radius.operation = "LENGTH"
    nt.links.new(combine.outputs["Vector"], radius.inputs[0])
    hole_ramp = nt.nodes.new("ShaderNodeValToRGB")
    hole_ramp.color_ramp.elements[0].position = PLATE_HOLE_RADIUS * 0.7
    hole_ramp.color_ramp.elements[0].color = (0.0, 0.0, 0.0, 1.0)
    hole_ramp.color_ramp.elements[1].position = PLATE_HOLE_RADIUS
    hole_ramp.color_ramp.elements[1].color = (1.0, 1.0, 1.0, 1.0)
    nt.links.new(radius.outputs["Value"], hole_ramp.inputs["Fac"])

    dark = tuple(c * (1.0 - PLATE_HOLE_DARKEN) for c in base_color[:3])
    hole_mix = nt.nodes.new("ShaderNodeMixRGB")
    hole_mix.inputs["Color1"].default_value = (*dark, 1.0)   # Fac=0 (inside the bore)
    nt.links.new(hole_ramp.outputs["Color"], hole_mix.inputs["Factor"])
    nt.links.new(rim_mix.outputs["Color"], hole_mix.inputs["Color2"])   # Fac=1 (outside)
    nt.links.new(hole_mix.outputs["Color"], bsdf.inputs["Base Color"])

    if "Emission Strength" in bsdf.inputs:
        hole_strength = nt.nodes.new("ShaderNodeMath")
        hole_strength.operation = "MULTIPLY"
        hole_strength.inputs[1].default_value = emission
        nt.links.new(hole_ramp.outputs["Color"], hole_strength.inputs[0])
        nt.links.new(hole_strength.outputs["Value"], bsdf.inputs["Emission Strength"])

    return mat


def make_haze_material(density):
    """Transparent surface, faint volume scatter PLUS a low-strength volume emission.
    Gives the *empty* part of the vessel a body, so it reads as empty glass rather than as
    nothing -- scatter alone needs a light to actually pass through and hit it (unreliable
    for a mostly-empty interior with two small suns outside), so pass 4 adds a small
    self-lit emission floor, guaranteeing the haze shows regardless of whether any ray
    happens to reach it. This Blender version has no standalone Volume Emission node (only
    Scatter/Absorption/Principled) -- Principled Volume folds both into one node."""
    mat = bpy.data.materials.new("WhaleHaze")
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        if n.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(n)
    out = nt.nodes["Material Output"]
    transp = nt.nodes.new("ShaderNodeBsdfTransparent")
    nt.links.new(transp.outputs["BSDF"], out.inputs["Surface"])

    vol = nt.nodes.new("ShaderNodeVolumePrincipled")
    vol.inputs["Color"].default_value = rp.hex_to_linear_rgba(HAZE_COLOR)
    vol.inputs["Density"].default_value = density
    vol.inputs["Emission Color"].default_value = rp.hex_to_linear_rgba(HAZE_COLOR)
    vol.inputs["Emission Strength"].default_value = HAZE_EMISSION_STRENGTH
    nt.links.new(vol.outputs["Volume"], out.inputs["Volume"])
    return mat


# --------------------------------------------------------------------------------------
# Lattice geometry helpers (used only to SIZE the plate, and as the loose spawn grid)
# --------------------------------------------------------------------------------------

def lattice_positions(diameter, lo, hi, spacing_mult=1.0, z_top_extra=0.0):
    """Hex-packed candidate centres. `spacing_mult` > 1 loosens the grid (used for the
    physics spawn); `z_top_extra` extends candidate layers above the shell (the pour
    reservoir). Defaults reproduce the tight lattice used to size the plate diameter."""
    d = diameter * spacing_mult
    t = diameter * PLATE_THICK_RATIO
    zt = t * max(spacing_mult, 1.0)
    dy = d * math.sqrt(3.0) * 0.5
    out = []
    layer = 0
    z = lo.z + t * 0.5
    z_hi = hi.z + z_top_extra
    while z <= z_hi:
        ox = (d * 0.5) if (layer % 2) else 0.0
        oy = (dy / 3.0) if (layer % 2) else 0.0
        row, y = 0, lo.y - dy
        while y <= hi.y + dy:
            rx = (d * 0.5) if (row % 2) else 0.0
            x = lo.x - d
            while x <= hi.x + d:
                out.append((x + rx + ox, y + oy, z))
                x += d
            y += dy
            row += 1
        z += zt
        layer += 1
    return out, t


def plate_fits(inside, cx, cy, cz, pr, ph):
    if not inside(Vector((cx, cy, cz))):
        return False
    for k in range(8):
        a = k * math.tau / 8
        rx, ry = pr * math.cos(a), pr * math.sin(a)
        for dz in (-ph, ph):
            if not inside(Vector((cx + rx, cy + ry, cz + dz))):
                return False
    return True


def count_plates(inside, diameter, lo, hi):
    positions, t = lattice_positions(diameter, lo, hi)
    pr, ph = diameter * 0.5, t * 0.5
    return sum(1 for (x, y, z) in positions if plate_fits(inside, x, y, z, pr, ph))


def solve_diameter(inside, target, lo, hi, d_lo=0.10, d_hi=0.90, iters=14):
    """Bisect for the plate diameter that lands a TIGHT static lattice near `target`. Used
    only to size the plate -- pass 3's actual fill count comes from settling, not this
    lattice -- but it's still the right way to size it: the count depends on the mesh's
    interior volume, which is not something to eyeball."""
    best, best_err, best_n = d_hi, None, 0
    for _ in range(iters):
        mid = 0.5 * (d_lo + d_hi)
        n = count_plates(inside, mid, lo, hi)
        err = abs(n - target)
        if best_err is None or err < best_err:
            best, best_err, best_n = mid, err, n
        if n > target:
            d_lo = mid
        else:
            d_hi = mid
        if err == 0:
            break
    return best, best_n


# --------------------------------------------------------------------------------------
# Rigid-body pour
# --------------------------------------------------------------------------------------

def build_pour(spawn_inside, diameter, lo, hi, mat, target_plates,
               overfill=POUR_OVERFILL, pack_loose=PACK_LOOSE):
    """Spawns cylinders in a loose staggered grid over the whole interior, plus a
    reservoir above the shell that pours in.

    Every candidate cell in the loose grid that's plausibly inside the shell is spawned --
    NOT subsampled down toward `target_plates`: the strict rim-aware survivor filter after
    settling (see freeze_and_filter) is what actually decides the full-fill count, and it
    is considerably stricter than this lax, unshrunk spawn test (it has to be -- see
    make_test_proxy). Capping spawn count to ~target*overfill before that filter ran was
    silently throwing away genuine candidate cells and starving the fin/fluke bases of
    plates that would otherwise have cleared the strict test. `overfill` now only scales
    the pour reservoir (the extra layer spawned above the shell, raining in from the top).
    """
    headroom = (hi.z - lo.z) * POUR_HEADROOM_FRAC
    loose_positions, _t = lattice_positions(diameter, lo, hi,
                                             spacing_mult=pack_loose, z_top_extra=headroom)

    body, reservoir = [], []
    for (x, y, z) in loose_positions:
        if z > hi.z:
            reservoir.append((x, y, z))
        elif spawn_inside(Vector((x, y, z))):
            body.append((x, y, z))

    rng = random.Random(SEED)
    reservoir_budget = min(len(reservoir),
                            max(1, round(RESERVOIR_FRAC * overfill * len(body))))
    reservoir_pick = (list(reservoir) if len(reservoir) <= reservoir_budget
                      else rng.sample(reservoir, reservoir_budget))
    spawn_positions = body + reservoir_pick
    spawn_positions.sort(key=lambda p: -p[2])   # higher z first, so it reads as a pour

    rp.PLATE_THICKNESS = PLATE_THICK_RATIO
    mesh = rp.build_plate_mesh("Plate45_Vessel")
    mesh.materials.append(mat)

    jitter_xy = diameter * JITTER_XY_FRAC
    plates = []
    for idx, (x, y, z) in enumerate(spawn_positions):
        prng = random.Random(SEED + idx * 7919)
        obj = bpy.data.objects.new(f"pour_{idx:04d}", mesh)
        obj.location = (x + prng.uniform(-jitter_xy, jitter_xy),
                         y + prng.uniform(-jitter_xy, jitter_xy), z)
        obj.rotation_euler = (
            math.radians(prng.uniform(-ROT_JITTER_DEG, ROT_JITTER_DEG)),
            math.radians(prng.uniform(-ROT_JITTER_DEG, ROT_JITTER_DEG)),
            math.radians(prng.uniform(-180.0, 180.0)),
        )
        obj.scale = (diameter, diameter, diameter)
        bpy.context.collection.objects.link(obj)
        plates.append(obj)
    rp.apply_auto_smooth(plates)
    return plates, len(body), len(reservoir_pick)


def setup_physics(collider, plates):
    bpy.ops.object.select_all(action="DESELECT")
    collider.select_set(True)
    bpy.context.view_layer.objects.active = collider
    bpy.ops.rigidbody.object_add(type="PASSIVE")
    rb = collider.rigid_body
    rb.collision_shape = "MESH"
    rb.friction = SHELL_FRICTION
    rb.use_margin = True
    rb.collision_margin = SHELL_COLLISION_MARGIN

    bpy.ops.object.select_all(action="DESELECT")
    for o in plates:
        o.select_set(True)
    bpy.context.view_layer.objects.active = plates[0]
    bpy.ops.rigidbody.objects_add(type="ACTIVE")
    for o in plates:
        rb = o.rigid_body
        rb.collision_shape = "CYLINDER"
        rb.mass = PLATE_MASS
        rb.friction = PLATE_FRICTION
        rb.restitution = PLATE_RESTITUTION
        rb.linear_damping = PLATE_LIN_DAMPING
        rb.angular_damping = PLATE_ANG_DAMPING
        rb.use_margin = True
        rb.collision_margin = PLATE_COLLISION_MARGIN

    rbw = bpy.context.scene.rigidbody_world
    rbw.substeps_per_frame = SIM_SUBSTEPS
    rbw.solver_iterations = SIM_SOLVER_ITERATIONS


def run_sim(scene, n_frames):
    scene.frame_start = 1
    scene.frame_end = n_frames
    for f in range(1, n_frames + 1):
        scene.frame_set(f)


def plate_clears_glass(inside, matrix_world, half_thick, k=8):
    """Rotation-aware rim test: samples the plate's actual outer rim (top and bottom) in
    its own local frame, transformed by its settled matrix_world -- not just the centre.
    A tilted plate resting against a thin wall (the dorsal fin's base, at these small
    diameters) can have its centre clear the strict test while its edge still pokes
    through the glass; that showed up as a visible leak until this was added, echoing the
    pass-2 tail leak this whole pass exists to fix."""
    pts = [Vector((0.0, 0.0, 0.0))]
    for i in range(k):
        a = i * math.tau / k
        rx, ry = rp.PLATE_RADIUS * math.cos(a), rp.PLATE_RADIUS * math.sin(a)
        for dz in (-half_thick, half_thick):
            pts.append(Vector((rx, ry, dz)))
    return all(inside(matrix_world @ p) for p in pts)


def freeze_and_filter(plates, inside, hi):
    """Reads each plate's EVALUATED world matrix at the settled frame (the depsgraph
    copy, not the base object -- the base transform is not guaranteed live-updated by the
    rigid body simulation in background mode), freezes it onto the plain object, then
    drops the physics. A plate survives only if it sits at/under the shell's own top AND
    its whole rim (not just its centre) clears the strict inside test -- any failure means
    it escaped the pour."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    frozen = {o.name: o.evaluated_get(depsgraph).matrix_world.copy() for o in plates}

    bpy.ops.object.select_all(action="DESELECT")
    for o in plates:
        o.select_set(True)
    bpy.context.view_layer.objects.active = plates[0]
    bpy.ops.rigidbody.objects_remove()

    half_thick = PLATE_THICK_RATIO * 0.5
    survivors, escaped = [], 0
    for o in plates:
        o.matrix_world = frozen[o.name]
        center = o.matrix_world.translation
        if center.z <= hi.z and plate_clears_glass(inside, o.matrix_world, half_thick):
            survivors.append(o)
        else:
            escaped += 1
            bpy.data.objects.remove(o, do_unlink=True)

    survivors.sort(key=lambda o: (round(o.matrix_world.translation.z, 6),
                                   o.matrix_world.translation.x,
                                   o.matrix_world.translation.y))
    return survivors, escaped


def apply_plate_bevel(plates, width_ratio=BEVEL_WIDTH_RATIO, segments=BEVEL_SEGMENTS,
                      angle_deg=None):
    """Bevels the shared plate mesh -- purely cosmetic, run AFTER freeze_and_filter, so it
    cannot touch the pour: every survivor's matrix_world is already frozen and physics is
    already removed by this point. All survivors are linked duplicates of one mesh
    datablock, so this bevels that ONE mesh once rather than 754 individual objects.

    `bpy.ops.object.modifier_apply` auto-single-users a multi-user mesh onto the ACTIVE
    object only, leaving every other user pointing at the old, unbevelled data -- so this
    explicitly reassigns the new (bevelled, now single-user) mesh to every plate afterward
    rather than relying on the apply to propagate it."""
    if not plates:
        return None
    angle_deg = rp.SMOOTH_ANGLE_DEG if angle_deg is None else angle_deg
    old_mesh = plates[0].data
    tmp = bpy.data.objects.new("__bevel_tmp", old_mesh)
    bpy.context.collection.objects.link(tmp)
    tmp.data = tmp.data.copy()   # modifier_apply refuses multi-user data outright in this
                                 # Blender version (no silent auto-single-user) -- make an
                                 # explicit single-user copy for `tmp` only
    mod = tmp.modifiers.new("Bevel", "BEVEL")
    mod.width = PLATE_THICK_RATIO * width_ratio
    mod.segments = segments
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(angle_deg)
    bpy.context.view_layer.objects.active = tmp
    bpy.ops.object.select_all(action="DESELECT")
    tmp.select_set(True)
    bpy.ops.object.modifier_apply(modifier=mod.name)

    new_mesh = tmp.data
    for o in plates:
        o.data = new_mesh
    bpy.data.objects.remove(tmp, do_unlink=True)
    if old_mesh.users == 0:
        bpy.data.meshes.remove(old_mesh)
    return new_mesh


def apply_fill_level(plates, fill):
    """Fill by settled height, lowest first -- what poured first sits lowest, the liquid
    rule. `plates` is pre-sorted bottom-up by freeze_and_filter."""
    n_show = int(round(fill * len(plates)))
    for i, obj in enumerate(plates):
        obj.hide_render = i >= n_show
    return n_show


# --------------------------------------------------------------------------------------
# Lighting and camera
# --------------------------------------------------------------------------------------

def build_lighting(scale=1.0):
    """One soft key, one narrow rim -- pass 2's four broad lights (up to 45 deg across)
    painted reflections across the whole body, which is most of what read as chrome.

    Pass 4: raised key (2.0 -> 4.5) since the shell's Transparent lobe (most of its visible
    area, see make_shell_material) barely reflects a sun at all -- it was the plates, not
    the glass, that were starved by a dim key. Raised and narrowed rim (2.5 -> 7.0 energy,
    2.5 -> 1.2 deg) and repositioned it to come from behind and above (matching pass 2's
    validated `rim_back` direction) so it raxes across the top of the back and the fluke
    outline specifically, as a specular accent on top of the shell's own Fresnel self-glow
    (which is view-angle driven and doesn't depend on any light lining up right)."""
    def sun(name, direction, energy, angle_deg, color=(1.0, 1.0, 1.0)):
        data = bpy.data.lights.new(name, type="SUN")
        data.energy = energy * scale
        data.angle = math.radians(angle_deg)
        data.color = color
        obj = bpy.data.objects.new(name, data)
        obj.rotation_euler = Vector(direction).to_track_quat("-Z", "Y").to_euler()
        bpy.context.collection.objects.link(obj)
        return obj

    sun("key", (0.40, 0.62, -0.66), energy=2.0, angle_deg=18.0)
    sun("rim", (0.05, -0.80, -0.42), energy=3.5, angle_deg=1.2, color=(0.90, 0.95, 1.0))

    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.0, 0.0, 0.0, 1.0)
    bg.inputs[1].default_value = 0.0
    bpy.context.scene.world = world


def build_camera(scene, shell):
    from bpy_extras.object_utils import world_to_camera_view

    cam_data = bpy.data.cameras.new("Camera")
    cam_data.lens = CAM_LENS_MM
    cam = bpy.data.objects.new("Camera", cam_data)
    bpy.context.collection.objects.link(cam)
    scene.camera = cam

    el, az = math.radians(CAM_ELEVATION_DEG), math.radians(CAM_AZIMUTH_DEG)
    back = Vector((math.cos(el) * math.cos(az), math.cos(el) * math.sin(az), math.sin(el)))
    pts = [shell.matrix_world @ v.co for v in shell.data.vertices]
    aim = sum(pts, Vector((0.0, 0.0, 0.0))) / len(pts)
    dist, want = 14.0, 1.0 - 2.0 * FRAME_MARGIN

    def place(d, a):
        cam.location = a + back * d
        cam.rotation_euler = (a - cam.location).to_track_quat("-Z", "Y").to_euler()
        bpy.context.view_layer.update()

    for _ in range(120):
        place(dist, aim)
        ndc = [world_to_camera_view(scene, cam, p) for p in pts]
        xs, ys = [v.x for v in ndc], [v.y for v in ndc]
        span = max(max(xs) - min(xs), max(ys) - min(ys))
        if span <= 1e-6:
            break
        fw = 2.0 * dist * math.tan(cam_data.angle_x * 0.5)
        fh = 2.0 * dist * math.tan(cam_data.angle_y * 0.5)
        mw = cam.matrix_world.to_3x3()
        right, up = mw.col[0].normalized(), mw.col[1].normalized()
        cx, cy = (max(xs) + min(xs)) * 0.5, (max(ys) + min(ys)) * 0.5
        aim = aim + right * ((cx - 0.5) * fw) + up * ((cy - 0.5) * fh)
        dist *= 1.0 + (span / want - 1.0) * 0.8
        if abs(span / want - 1.0) < 2e-4 and abs(cx - 0.5) < 2e-4 and abs(cy - 0.5) < 2e-4:
            break

    place(dist, aim)
    ndc = [world_to_camera_view(scene, cam, p) for p in pts]
    return cam, {
        "distance": round(dist, 4),
        "ndc_x": [round(min(v.x for v in ndc), 4), round(max(v.x for v in ndc), 4)],
        "ndc_y": [round(min(v.y for v in ndc), 4), round(max(v.y for v in ndc), 4)],
    }


def composite_preview_on_bg(path, bg_hex):
    """Overwrites a downscaled preview PNG with itself alpha-composited over `bg_hex`.

    The tool used to review these renders shows transparency as white, which is exactly
    backwards for judging "does the glass read against the app's near-black ground" --
    that's how the pass-3 glass fix looked fine in review and then read as invisible black
    once actually composited on #0A0B0D. Every future preview is composited for real here,
    so review always happens on the true ground. Full (non-preview) renders are untouched
    and stay transparent, per spec, for the app to composite itself."""
    import numpy as np

    img = bpy.data.images.load(path)
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

        srgb, a = px[..., :3], px[..., 3:4]
        lin = np.where(srgb <= 0.04045, srgb / 12.92, ((srgb + 0.055) / 1.055) ** 2.4)
        bg_lin = np.array(rp.hex_to_linear_rgba(bg_hex)[:3], dtype=np.float32)
        out_lin = lin * a + bg_lin * (1.0 - a)
        out_srgb = np.where(out_lin <= 0.0031308, out_lin * 12.92,
                            1.055 * np.maximum(out_lin, 0.0) ** (1 / 2.4) - 0.055)
        out = np.concatenate([np.clip(out_srgb, 0.0, 1.0), np.ones_like(a)], axis=2)

        img.pixels.foreach_set(out.reshape(-1).astype(np.float32))
        img.filepath_raw = path
        img.file_format = "PNG"
        img.save()
    finally:
        bpy.data.images.remove(img)


# --------------------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------------------

def parse_args(argv):
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    p = argparse.ArgumentParser(prog="render_vessel.py")
    p.add_argument("--out", default="tools/milestone-render/out-vessel")
    p.add_argument("--asset", default=None)
    p.add_argument("--fills", type=float, nargs="+", default=[0.30, 0.65, 1.00])
    p.add_argument("--size", default="1200x800")
    p.add_argument("--samples", type=int, default=96)
    p.add_argument("--preview-width", type=int, default=600)
    p.add_argument("--preview-bg", default="0A0B0D",
                   help="composite the 600px previews over this hex colour (the app's "
                        "real ground) so review happens on it, not on transparency; full "
                        "renders stay transparent")
    p.add_argument("--target-plates", type=int, default=1000)
    p.add_argument("--diameter", type=float, default=None)
    p.add_argument("--haze", type=float, default=0.03)
    p.add_argument("--emission", type=float, default=0.30)
    p.add_argument("--light-scale", type=float, default=1.0)
    p.add_argument("--sim-frames", type=int, default=260)
    p.add_argument("--overfill", type=float, default=POUR_OVERFILL)
    p.add_argument("--save-blend", action="store_true")
    args = p.parse_args(argv)
    w, _, h = args.size.lower().partition("x")
    args.width, args.height = int(w), int(h)
    args.fit_width = args.width
    if args.asset is None:
        args.asset = os.path.join(os.path.dirname(os.path.abspath(__file__)), ASSET)
    return args


def main():
    args = parse_args(sys.argv)
    t_start = time.time()
    out_dir = os.path.abspath(args.out)
    os.makedirs(out_dir, exist_ok=True)
    if not os.path.exists(args.asset):
        raise SystemExit(f"[vessel] missing asset {args.asset} (see ASSETS.md)")

    rp.clear_scene()
    scene = bpy.context.scene

    shell, open_edges = load_shell(args.asset)
    lo, hi = _bbox_world(shell)
    print(f"[vessel] shell '{os.path.basename(args.asset)}' {len(shell.data.polygons)} tris, "
          f"open edges after weld {open_edges}, "
          f"dims {tuple(round(v, 3) for v in (hi - lo))}")

    proxy = make_test_proxy(shell)
    proxy.data.materials.clear()
    proxy.data.materials.append(make_haze_material(args.haze))
    proxy.visible_shadow = False
    inside = make_inside_test(proxy)

    collider, collider_method = make_collider(shell, open_edges)
    spawn_inside = make_inside_test(collider)
    print(f"[vessel] collider: {collider_method}")

    # Render-only shading goes on `shell` AFTER the proxy/collider copies above, so neither
    # of them inherits the Subdivision modifier added here.
    shell.data.materials.clear()
    shell.data.materials.append(make_shell_material())
    add_shell_shading(shell)

    if args.diameter:
        diameter = args.diameter
        n_lattice = count_plates(inside, diameter, lo, hi)
    else:
        diameter, n_lattice = solve_diameter(inside, args.target_plates, lo, hi)
    thickness = diameter * PLATE_THICK_RATIO
    print(f"[vessel] plate diameter {diameter:.4f} thickness {thickness:.4f} -> "
          f"tight-lattice estimate {n_lattice} (target {args.target_plates})")

    t0 = time.time()
    plates, n_body_candidates, n_reservoir = build_pour(
        spawn_inside, diameter, lo, hi, make_vessel_plate_material(args.emission),
        args.target_plates, overfill=args.overfill)
    spawn_n = len(plates)
    t_spawn = time.time() - t0
    print(f"[vessel] spawned {spawn_n} plates ({n_body_candidates} interior candidates, "
          f"{n_reservoir} from the pour reservoir)  {t_spawn:.2f}s")

    setup_physics(collider, plates)

    t0 = time.time()
    run_sim(scene, args.sim_frames)
    t_sim = time.time() - t0

    survivors, escaped = freeze_and_filter(plates, inside, hi)
    n_full = len(survivors)
    print(f"[vessel] settled after {args.sim_frames} frames in {t_sim:.2f}s -- "
          f"{n_full} survivors, {escaped} escaped")

    # Cosmetic only, run after the physics/filter above: cannot change the pour, since
    # every survivor's transform is already frozen and its rigid body already removed.
    apply_plate_bevel(survivors)

    build_lighting(args.light_scale)

    engine, device_type, device_names = rp.setup_render(scene, args, "auto")
    scene.cycles.max_bounces = 16
    scene.cycles.transmission_bounces = 12
    scene.cycles.transparent_max_bounces = 12
    scene.cycles.volume_bounces = 2
    cam, fit = build_camera(scene, shell)
    print(f"[vessel] engine={engine} device={device_type} {device_names} "
          f"samples={args.samples} size={args.width}x{args.height}")
    print(f"[vessel] camera fit: {fit}")

    if args.save_blend:
        bpy.ops.wm.save_as_mainfile(
            filepath=os.path.join(os.path.dirname(out_dir), "vessel.blend"))

    timings, shown, previews = {}, {}, []
    for fill in args.fills:
        n = apply_fill_level(survivors, fill)
        tag = f"{int(round(fill * 100)):02d}"
        path = os.path.join(out_dir, f"fill_{tag}.png")
        scene.render.filepath = path
        t0 = time.time()
        bpy.ops.render.render(write_still=True)
        rp.clean_transparent_rgb(path)
        dt = time.time() - t0
        timings[tag], shown[tag] = round(dt, 2), n
        prev = os.path.join(out_dir, f"preview_{tag}_{args.preview_width}.png")
        rp.write_downscaled_proof(path, prev, args.preview_width)
        composite_preview_on_bg(prev, args.preview_bg)   # full render (`path`) stays
                                                          # transparent; only the preview
                                                          # is composited, for review
        previews.append(prev)
        print(f"[vessel] fill {fill:.2f}  {n:4d} plates  {dt:6.2f}s  "
              f"{os.path.getsize(path) / 1024:8.1f} KB  -> {prev}", flush=True)

    times = list(timings.values())
    manifest = {
        "generator": "tools/milestone-render/render_vessel.py",
        "blender_version": bpy.app.version_string,
        "engine": engine,
        "device_type": device_type,
        "devices": device_names,
        "samples": args.samples,
        "image_size": [args.width, args.height],
        "background": "transparent (RGBA, 8-bit PNG); app paints #0A0B0D behind",
        "animal": {"name": ANIMAL_NAME, "pounds": ANIMAL_LB},
        "shell_asset": {"path": ASSET, "see": "tools/milestone-render/ASSETS.md",
                        "tris": len(shell.data.polygons),
                        "length_units": BODY_LENGTH},
        "fill_is_continuous": True,
        "fill_mapping": "fill = lifted_lb / %d, clamped to [0,1]; continuous -- any step "
                        "size renders, not tied to a frame count" % ANIMAL_LB,
        "method": "rigid-body settle; fill = lowest f*N plates by height",
        "plate": {
            "diameter": round(diameter, 5),
            "thickness": round(thickness, 5),
            "color_hex": "#" + rp.PLATE_COLOR_HEX,
            "count_at_full_fill": n_full,
            "rot_jitter_deg": ROT_JITTER_DEG,
            "seed": SEED,
        },
        "pour": {
            "collider": collider_method,
            "target_plates": args.target_plates,
            "overfill_factor": args.overfill,
            "spawned": spawn_n,
            "survivors": n_full,
            "escaped": escaped,
            "sim_frames": args.sim_frames,
            "substeps_per_frame": SIM_SUBSTEPS,
            "solver_iterations": SIM_SOLVER_ITERATIONS,
        },
        "renders": [{"fill": f, "tag": f"{int(round(f * 100)):02d}",
                     "plates_shown": shown[f"{int(round(f * 100)):02d}"],
                     "seconds": timings[f"{int(round(f * 100)):02d}"]}
                    for f in args.fills],
        "camera": {"lens_mm": CAM_LENS_MM, "elevation_deg": CAM_ELEVATION_DEG,
                   "azimuth_deg": CAM_AZIMUTH_DEG, "fit": fit},
        "previews": [os.path.basename(p) for p in previews],
        "preview_background": "#" + args.preview_bg.lstrip("#").upper(),
        "timing": {"spawn_seconds": round(t_spawn, 2),
                   "sim_seconds": round(t_sim, 2),
                   "mean_render_seconds_per_frame":
                   round(sum(times) / len(times), 2) if times else None,
                   "total_seconds": round(time.time() - t_start, 2)},
    }
    with open(os.path.join(out_dir, "manifest.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2)
    print(f"[vessel] done in {manifest['timing']['total_seconds']}s")


if __name__ == "__main__":
    main()
