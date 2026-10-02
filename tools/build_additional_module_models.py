"""Compact armor-integrated modules, authored locally in Blender.

Godot coordinates are metres, Y up, +Z away from the mounting surface. The
small saddle alone extends to Z=-0.008; the functional shell begins at Z=0.
These are fitted armor parts rather than separate display cases.
"""
from math import cos, sin, pi
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
import bmesh
from module_modeling import *


def _chamfer_rect(width, height, cut, offset=(0, 0)):
    x, y = width/2, height/2
    ox, oy = offset
    return [(ox-x+cut, oy-y), (ox+x-cut, oy-y),
            (ox+x, oy-y+cut), (ox+x, oy+y-cut),
            (ox+x-cut, oy+y), (ox-x+cut, oy+y),
            (ox-x, oy+y-cut), (ox-x, oy-y+cut)]


def _hull(name, sections, mat, bevel=.0025):
    """Loft matched XY contours in depth with sloping armor planes."""
    count = len(sections[0][1])
    assert all(len(outline) == count for _, outline in sections)
    vertices = [v((x, y, z)) for z, outline in sections for x, y in outline]
    faces = [tuple(reversed(range(count)))]
    for layer in range(len(sections)-1):
        for i in range(count):
            j = (i+1) % count
            a, b = layer*count, (layer+1)*count
            faces.append((a+i, a+j, b+j, b+i))
    faces.append(tuple((len(sections)-1)*count+i for i in range(count)))
    mesh = bpy.data.meshes.new(name + "_mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    finish(obj, name, mat, bevel)
    modifier = obj.modifiers.get("Machined edge radius")
    if modifier is not None:
        modifier.segments = 3
    return obj


def _bore(obj, x, y, radius):
    """Subtract a real cylindrical aperture before shell edge treatment."""
    cutter = cylinder("temporary_aperture", (x, y, .100), radius,
                      .240, "steel", axis=(0, 0, 1), vertices=16, bevel=0)
    bpy.context.view_layer.objects.active = obj
    modifier = obj.modifiers.new("Through launch aperture", "BOOLEAN")
    modifier.operation = 'DIFFERENCE'
    modifier.solver = 'EXACT'
    modifier.object = cutter
    bpy.ops.object.modifier_move_up(modifier=modifier.name)
    bpy.ops.object.modifier_move_up(modifier=modifier.name)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.data.objects.remove(cutter, do_unlink=True)


def _small_box(name, pos, dims, mat, bevel=.001, rotation=(0, 0, 0)):
    obj = box(name, pos, dims, mat, bevel=bevel, rotation=rotation)
    modifier = obj.modifiers.get("Machined edge radius")
    if modifier is not None:
        modifier.segments = 2
    return obj


def _unbeveled_ring(name, pos, outer, inner, depth, mat, segments=16):
    obj = ring(name, pos, outer, inner, depth, mat,
               axis=(0, 0, 1), segments=segments)
    modifier = obj.modifiers.get("Machined edge radius")
    if modifier is not None:
        obj.modifiers.remove(modifier)
    return obj


def _recessed_fastener(name, x, y, z):
    cylinder(name, (x, y, z), .0025, .002, "steel",
             axis=(0, 0, 1), vertices=6, bevel=0)
    _small_box(name + "_driver", (x, y, z+.0011),
               (.0021, .00055, .0003), "rubber", bevel=0)


def _rocket_saddle():
    """Thin support follows a convex pauldron by sinking at its outer edges."""
    outline = _chamfer_rect(.190, .150, .025)
    vertices = []
    for front in (False, True):
        for x, y in outline:
            curvature = max(abs(x)/.095, abs(y)/.075)**2
            z = .0035 - .0015*curvature if front else -.0015-.0065*curvature
            vertices.append(v((x, y, z)))
    faces = [tuple(reversed(range(8))), tuple(range(8, 16))]
    for i in range(8):
        j = (i+1) % 8
        faces.append((i, j, 8+j, 8+i))
    mesh = bpy.data.meshes.new("curved_saddle_mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("thin_conforming_armor_saddle", mesh)
    bpy.context.scene.collection.objects.link(obj)
    finish(obj, obj.name, "steel", .0007)


def _rocket_ivory():
    """Local warm enamel with coherent paint wear and smoke around six bores."""
    base = material("ivory")
    original_name = base.name
    base.name = "ivory_shared_recipe"
    worn = base.copy()
    worn.name = "ivory"
    size = 256
    rng = random.Random("rocket-ivory-v4")
    albedo, roughness, normals = [], [], []
    patches = [(-.056,.055,.018,.007,.18), (.061,-.044,.016,.009,.15),
               (-.069,-.033,.012,.023,.17), (.011,.061,.030,.008,.09),
               (.040,.046,.008,.005,.11), (-.023,-.053,.019,.006,.15)]
    for y in range(size):
        for x in range(size):
            xx, yy = (x/(size-1)-.5)*.190, (y/(size-1)-.5)*.150
            grain = rng.uniform(-.010,.010)
            shade = .98 + grain + .025*math.sin(x*.047)*math.cos(y*.039)
            for px,py,rx,ry,strength in patches:
                shade -= strength*math.exp(-((xx-px)/rx)**2-((yy-py)/ry)**2)
            smoke = 0.0
            for cy in (-.026,.026):
                for cx in (-.050,0,.050):
                    distance = math.hypot(xx-cx,yy-cy)
                    smoke += .10*math.exp(-((distance-.0184)/.0034)**2)
            shade -= smoke
            edge = max(abs(xx)/.095,abs(yy)/.075)
            broken = math.sin(x*.93+y*.19)+math.cos(y*.77-x*.13)
            chip = edge > .77 and broken > 1.84 and rng.random() > .40
            color = (.225,.230,.216) if chip else (.637*shade,.605*shade,.526*shade)
            albedo.extend((*color,1))
            q = min(.86,.60 + (1-shade)*.45 + grain)
            roughness.extend((q,q,q,1))
            normals.extend((.5+grain*.18,.5+grain*.18,1,1))
    for suffix, pixels, colorspace in (("albedo",albedo,"sRGB"),
                                      ("roughness",roughness,"Non-Color"),
                                      ("normal",normals,"Non-Color")):
        image = bpy.data.images.new("rocket_ivory_"+suffix,width=size,height=size)
        image.colorspace_settings.name = colorspace
        image.pixels.foreach_set(pixels)
        image.filepath_raw = str(SOURCE/("rocket_ivory_"+suffix+".png"))
        image.file_format = 'PNG'
        image.save()
        image.pack()
        for node in worn.node_tree.nodes:
            if node.type == 'TEX_IMAGE' and node.image.name.endswith("_"+suffix):
                node.image = image
    MATERIALS["ivory"] = worn
    return base, original_name, worn


def _rocket_planar_uv():
    # A continuous XY projection gives the six mouths their own smoke rings;
    # the same scars continue around the bevels instead of random UV islands.
    for obj in bpy.context.scene.objects:
        if obj.type != 'MESH' or not any(m.name == "ivory" for m in obj.data.materials):
            continue
        uv = obj.data.uv_layers[0] if obj.data.uv_layers else obj.data.uv_layers.new(name="UVMap")
        uv.name = "UVMap"
        obj.data.uv_layers.active_index = 0
        for loop in obj.data.loops:
            p = obj.matrix_world @ obj.data.vertices[loop.vertex_index].co
            uv.data[loop.index].uv = (p.x/.190+.5,p.z/.150+.5)


def build_rocket_basket():
    """A shallow conforming six-bore insert: 19 x 15 x 5 cm maximum."""
    begin("rocket_basket")
    base, original_name, worn = _rocket_ivory()
    _rocket_saddle()
    shell = _hull("contoured_ceramic_cassette", [
        (.003, _chamfer_rect(.188, .148, .026)),
        (.021, _chamfer_rect(.179, .139, .024, (0, -.001))),
        (.041, _chamfer_rect(.166, .117, .018, (0, -.001)))],
        "ivory", .0018)
    for row, y in enumerate((-.026, .026)):
        for column, x in enumerate((-.050, 0, .050)):
            suffix = "%d_%d" % (row, column)
            _bore(shell, x, y, .0177)
            _unbeveled_ring("recessed_launch_sleeve_" + suffix,
                            (x, y, .026), .0175, .0134, .032, "steel")
            cylinder("recessed_rocket_body_" + suffix,
                     (x, y, .016), .011, .020, "steel",
                     axis=(0, 0, 1), vertices=16, bevel=0)
            cylinder("recessed_ceramic_ogive_" + suffix,
                     (x, y, .030), .011, .020, "ivory",
                     axis=(0, 0, 1), vertices=20, radius_top=.0012, bevel=0)
    _small_box("narrow_ochre_side_inlay", (.076, -.001, .041),
               (.0018, .048, .0010), "paint", bevel=.0003)
    _rocket_planar_uv()
    try:
        export("rocket_basket")
    finally:
        # begin() retains the material cache, so full-script runs must restore
        # the shared recipe before the magnetic brace and reactor are built.
        MATERIALS["ivory"] = base
        worn.name = "ivory_rocket_source"
        base.name = original_name


def build_magnetic_field():
    """An asymmetric forearm induction brace: 14.0 x 18.4 x 5.3 cm."""
    begin("magnetic_field")
    outline = [(-.037, -.092), (.034, -.081), (.067, -.040),
               (.054, .063), (.011, .092), (-.044, .075),
               (-.067, .036), (-.064, -.057)]
    front = [(x*.94, y*.97) for x, y in outline]
    _small_box("flush_forearm_saddle", (0, 0, -.004),
               (.064, .113, .008), "steel", bevel=.0015)
    _hull("fitted_asymmetric_brace", [(.000, outline), (.027, front)],
          "ivory", .003)
    pocket = [(-.045, -.034), (.026, -.038), (.045, -.016),
              (.038, .042), (.011, .061), (-.026, .050),
              (-.048, .022), (-.049, -.017)]
    _hull("recessed_induction_pocket", [(.026, pocket), (.030, pocket)],
          "steel", .0012)
    for index, radius in enumerate((.023, .032, .041)):
        points = []
        for step in range(10):
            angle = -pi*.37 + (pi*1.03)*step/9
            points.append((-.011 + cos(angle)*radius,
                           .003 + sin(angle)*radius, .034))
        pipe("partial_copper_induction_trace_%d" % index,
             points, .00155, "copper")
    upper = [(-.050, .025), (-.043, .064), (-.022, .080),
             (.013, .084), (.038, .065), (.019, .057),
             (-.011, .049), (-.027, .021)]
    upper_tip = [(x*.97, y-.002) for x, y in upper]
    _hull("swept_upper_coil_cover", [(.027, upper), (.044, upper_tip)],
          "ivory", .0025)
    lower = [(-.058, -.054), (-.032, -.083), (.030, -.075),
             (.055, -.042), (.043, -.029), (.008, -.036),
             (-.028, -.041), (-.047, -.037)]
    _hull("swept_lower_coil_cover", [(.026, lower), (.040, lower)],
          "ivory", .0025)
    _small_box("offset_aperture_dark_seat", (.033, -.006, .038),
               (.010, .040, .010), "rubber", bevel=.0015,
               rotation=(0, 0, -.13))
    _small_box("restrained_cyan_aperture", (.033, -.006, .044),
               (.0031, .027, .002), "cyan", bevel=.0006,
               rotation=(0, 0, -.13))
    _small_box("ochre_terminal_inlay", (-.017, .070, .044),
               (.027, .0027, .0014), "paint", bevel=.00045,
               rotation=(0, 0, .25))
    _recessed_fastener("brace_single_retainer", -.032, -.067, .041)
    export("magnetic_field")


def build_auxiliary_reactor():
    """A tapered dorsal cartridge: 16.0 x 26.0 x 6.6 cm."""
    begin("auxiliary_reactor")
    _small_box("flush_dorsal_saddle", (0, 0, -.004),
               (.083, .216, .008), "steel", bevel=.0015)
    base_outline = [(-.050, -.130), (.044, -.130), (.077, -.107),
                    (.080, .077), (.054, .124), (-.043, .130),
                    (-.078, .100), (-.080, -.100)]
    front_outline = [(x*.84, y*.95) for x, y in base_outline]
    _hull("cooled_dorsal_spine", [(.000, base_outline),
                                 (.043, front_outline)], "steel", .0025)
    left = [(-.075, -.107), (-.048, -.127), (-.028, -.119),
            (-.018, -.078), (-.030, .078), (-.048, .125),
            (-.066, .101), (-.078, .052)]
    left_front = [(x+.002, y*.98) for x, y in left]
    right = [(.029, -.122), (.049, -.125), (.073, -.106),
             (.078, .062), (.061, .109), (.043, .120),
             (.019, .079), (.020, -.084)]
    right_front = [(x-.003, y*.98) for x, y in right]
    _hull("swept_left_ceramic_shell", [(.010, left), (.057, left_front)],
          "ivory", .003)
    _hull("swept_right_ceramic_shell", [(.010, right), (.055, right_front)],
          "ivory", .003)
    for index, y in enumerate((-.053, -.002, .049)):
        _small_box("cooling_slot_dark_recess_%d" % index, (0, y, .043),
                   (.053, .0115, .004), "rubber", bevel=.001)
        _small_box("restrained_cyan_cooling_slot_%d" % index,
                   (0, y+.0008, .046), (.038, .0038, .0018),
                   "cyan", bevel=.0005)
        _small_box("cooling_slot_protective_lip_%d" % index,
                   (0, y-.006, .045), (.053, .002, .003),
                   "steel", bevel=.00045)
    for side in (-1, 1):
        for index, y in enumerate((-.068, -.013, .042)):
            _small_box("shallow_cooling_notch_%d_%d" % (side, index),
                       (side*.074, y, .020), (.011, .009, .027),
                       "steel", bevel=.001)
    _small_box("slender_ochre_shell_inlay", (-.057, .024, .058),
               (.0028, .084, .0012), "paint", bevel=.00045,
               rotation=(0, 0, -.073))
    latch = [(-.018, -.119), (.019, -.120), (.025, -.105),
             (.021, -.092), (.012, -.088), (-.016, -.089),
             (-.025, -.102), (-.026, -.112)]
    _hull("flush_lower_cartridge_latch", [(.041, latch), (.052, latch)],
          "steel", .0012)
    _recessed_fastener("dorsal_latch_retainer", 0, -.106, .053)
    export("auxiliary_reactor")


if __name__ == "__main__":
    build_rocket_basket()
    build_magnetic_field()
    build_auxiliary_reactor()
