"""Build the first forge workshop and a keyed, rigid industrial arm in Blender.

All geometry and surface textures are authored here; no external asset provider.
Run with Blender --background --factory-startup --python tools/build_forge_garage.py.
Coordinates in helpers use Godot's Y-up frame. Source .blend and runtime GLBs
are written only under art/forge-garage, leaving the combat assets untouched.
"""
from pathlib import Path
import math
import random
import sys
import bpy
import numpy as np
from mathutils import Vector

DEST = Path(__file__).resolve().parent.parent / "art" / "forge-garage"
DEST.mkdir(parents=True, exist_ok=True)
(DEST / "source").mkdir(exist_ok=True)
bpy.context.preferences.filepaths.save_version = 0
random.seed(1701)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.render.fps = 30
scene.frame_start = 0
scene.frame_end = 300


def v(pos):
    return Vector((pos[0], -pos[2], pos[1]))


def empty(name, pos=(0, 0, 0), parent=None):
    obj = bpy.data.objects.new(name, None)
    scene.collection.objects.link(obj)
    obj.parent = parent
    obj.location = v(pos)
    return obj


def surface(name, rgb, metal=0.0, rough=0.7, worn=False, emission=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Roughness"].default_value = rough
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*rgb, 1)
        bsdf.inputs["Emission Strength"].default_value = emission
    if worn:
        # Exportable albedo; procedural shader nodes would disappear in glTF.
        size = 256
        img = bpy.data.images.new(name + "_albedo", width=size, height=size)
        local_rng = random.Random(name)
        pixels = []
        for y in range(size):
            for x in range(size):
                broad = math.sin(x * .058 + math.sin(y * .043) * 2) * math.sin(y * .035 + 1.2)
                stain = max(0, math.sin(x * .103 + y * .018) * math.sin(y * .073))
                grain = local_rng.uniform(-.045, .045)
                shade = .83 + broad * .10 + grain - stain * .14
                scratch = (x * 13 + y * 7) % 251 < 2 and local_rng.random() > .68
                col = [min(1, max(0, c * shade + (.16 if scratch else 0))) for c in rgb]
                pixels.extend((*col, 1.0))
        img.pixels.foreach_set(pixels)
        img.filepath_raw = str(DEST / (name + "_albedo.png"))
        img.file_format = "PNG"
        img.save()
        img.pack()
        tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = img
        mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


steel = surface("worn_steel", (.23, .26, .27), .78, .57, True)
edge = surface("exposed_metal", (.42, .43, .39), .83, .36)
dark = surface("oiled_metal", (.065, .078, .080), .64, .47, True)
rust = surface("rusted_iron", (.30, .15, .071), .35, .85, True)
yellow = surface("workshop_ochre", (.81, .44, .065), .48, .64, True)
red = surface("toolbox_red", (.37, .058, .032), .39, .66, True)
concrete = surface("workshop_concrete", (.17, .16, .14), .04, .91, True)
wood = surface("scarred_workbench", (.24, .12, .041), .03, .85, True)
rubber = surface("rubber_hoses", (.027, .032, .029), .03, .88)
cloth = surface("canvas_banner", (.36, .068, .039), 0, .97, True)
olive = surface("equipment_cases", (.19, .20, .105), .26, .8, True)
warm_glass = surface("sunlit_window", (.98, .65, .30), .05, .57, emission=1.3)
lamp_glass = surface("lamp_diffuser", (1.0, .63, .20), .05, .3, emission=3.0)
cyan = surface("service_indicator", (.02, .65, .75), .3, .3, emission=2.0)

garage = empty("Workshop")
arm = empty("ServiceArm", (2.35, .28, -.10))
WORKSHOP_ONLY = "--workshop-only" in sys.argv


def finish(obj, name, material, parent, bevel=0):
    obj.name = name
    obj.parent = parent
    obj.data.materials.append(material)
    if bevel:
        obj.data.materials.append(edge)
        mod = obj.modifiers.new("MachinedEdges", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        # Leave paint on the background edges; bright bare-metal bevels on
        # every wall and floor piece make a distant workshop look like CAD.
        mod.material = 1 if parent != garage else -1
    return obj


def box(name, pos, dims, mat, parent=garage, bevel=.018):
    bpy.ops.mesh.primitive_cube_add(size=1)
    obj = bpy.context.object
    obj.scale = (dims[0], dims[2], dims[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj = finish(obj, name, mat, parent, min(bevel, min(dims) * .20))
    obj.location = v(pos)
    return obj


def cylinder(name, pos, radius, height, mat, parent=garage, horizontal=False, vertices=32):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=height)
    obj = finish(bpy.context.object, name, mat, parent, .008)
    obj.location = v(pos)
    if horizontal:
        obj.rotation_euler.x = math.pi / 2
    for face in obj.data.polygons:
        face.use_smooth = len(face.vertices) == 4
    return obj


def pipe(name, points, radius, mat, parent=garage):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 2
    spline = curve.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for point, pos in zip(spline.points, points):
        point.co = (*v(pos), 1)
    obj = bpy.data.objects.new(name, curve)
    scene.collection.objects.link(obj)
    obj.parent = parent
    obj.data.materials.append(mat)
    return obj


def annulus(name, inner, outer, y, depth, mat, start=0, end=math.tau, parent=garage, sections=64):
    verts = []
    for h in (y - depth, y):
        for r in (inner, outer):
            for i in range(sections + 1):
                angle = start + (end - start) * i / sections
                verts.append(v((math.cos(angle) * r, h, math.sin(angle) * r)))
    n = sections + 1
    faces = []
    for i in range(sections):
        faces.extend(((i, i + 1, n + i + 1, n + i),
                      (2*n + i, 3*n + i, 3*n + i + 1, 2*n + i + 1),
                      (i, 2*n + i, 2*n + i + 1, i + 1),
                      (n + i, n + i + 1, 3*n + i + 1, 3*n + i)))
    faces.extend(((0, n, 3*n, 2*n), (n-1, 2*n-1, 4*n-1, 3*n-1)))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    obj.parent = parent
    mesh.materials.append(mat)
    return obj


def label(name, text, pos, size, mat, parent=garage):
    curve = bpy.data.curves.new(name, "FONT")
    curve.body = text
    curve.size = size
    curve.extrude = .001
    obj = bpy.data.objects.new(name, curve)
    scene.collection.objects.link(obj)
    obj.parent = parent
    obj.location = v(pos)
    obj.rotation_euler.x = math.pi / 2  # Front faces the garage camera.
    curve.materials.append(mat)
    return obj


def workshop_floor():
    # One exported floor map adds grounded contact wear without a stack of
    # transparent decals or screen-space ambient occlusion on phone.
    size = 1024
    xs = np.linspace(-9.5, 9.5, size, dtype=np.float32)[None, :]
    zs = np.linspace(-8, 8, size, dtype=np.float32)[:, None]
    rng = np.random.default_rng(1701)
    mottling = np.sin(xs*2.4 + np.sin(zs*1.7))*np.cos(zs*2.1)*.025
    mottling += np.sin(xs*9.1-zs*7.4)*np.cos(zs*5.2+xs*3.1)*.012
    shade = .30 + mottling + rng.normal(0, .014, (size,size))
    for x,z,sx,sz,weight in [(-3.9,-1.9,2.1,.8,.10),(-4.35,3.2,.95,.55,.09),
                           (5.0,-2.4,1.8,1.1,.10),(4.8,3.3,1.0,.65,.07),
                           (2.35,0,.65,.55,.10),(-6.5,-3.7,.5,.35,.09)]:
        shade -= np.exp(-((xs-x)/sx)**2-((zs-z)/sz)**2)*weight
    radial = np.sqrt(xs*xs+zs*zs)
    shade -= np.exp(-((radial-1.90)/.23)**2)*.052
    for x,z in [(-.4,2.5),(.25,3.3),(-.18,3.9),(-3.1,.7),(-3.5,1.1)]:
        shade -= np.exp(-((xs-x)/.10)**2-((zs-z)/.22)**2)*.045
    rgba = np.ones((size,size,4), dtype=np.float32)
    for channel,factor in enumerate((1.02,1.01,.96)):
        rgba[:,:,channel] = np.clip(shade*factor,.06,.5)
    img = bpy.data.images.new("workshop_floor_albedo", width=size, height=size)
    img.pixels.foreach_set(rgba.ravel())
    img.pack()
    mat = surface("workshop_floor", (1,1,1), 0, .97)
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = img
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    slab = box("ConcreteSlab", (0,-.14,0), (19,.25,16), mat, bevel=0)
    uv = slab.data.uv_layers.active
    for face in slab.data.polygons:
        for loop in face.loop_indices:
            point = slab.data.vertices[slab.data.loops[loop].vertex_index].co
            uv.data[loop].uv = ((point.x+9.5)/19, (-point.y+8)/16)


print("FORGE BUILD: workshop shell", flush=True)
workshop_floor()
for x in range(-8, 9, 2):
    box("FloorExpansionJoint", (x, -.012, 0), (.022, .012, 15), dark, bevel=0)
for z in range(-6, 7, 2):
    box("FloorExpansionJoint", (0, -.012, z), (18, .012, .022), dark, bevel=0)
box("BackWall", (0, 3.7, -5.6), (18, 7.4, .24), concrete)
box("LeftWall", (-7.5, 3.6, -1.0), (.22, 7.2, 9), dark)
for x in range(-8, 9):
    box("CorrugatedSheet", (x, 1.15, -5.43), (.94, 2.2, .055), steel)
    for rib in (-.35, -.12, .12, .35):
        box("SheetRib", (x + rib, 1.15, -5.36), (.024, 2.2, .05), steel, bevel=0)
    box("WallSkirting", (x, .17, -5.30), (.96, .20, .08), dark)
    box("WallPaintBand", (x, 2.37, -5.455), (.94, .23, .025), yellow, bevel=0)
for x in (-7.65, -4.8, -1.9, 7.35):
    box("ConcretePanelJoint", (x, 5.1, -5.455), (.022, 4.15, .012), dark, bevel=0)
for y in (3.0, 5.5, 7.0):
    box("ConcreteHorizontalJoint", (-3.4, y, -5.455), (10.6, .018, .012), dark, bevel=0)
for x in (-6.3, -3.5, .6, 5.4, 7.6):
    box("ColumnWeb", (x, 3.75, -4.98), (.13, 7.5, .35), dark)
    for dz in (-.19, .19):
        box("ColumnFlange", (x, 3.75, -4.98 + dz), (.37, 7.5, .045), rust)
    box("ColumnFoot", (x, .1, -4.98), (.6, .15, .6), steel)
for y in (3.7, 6.7):
    box("CrossBeam", (0, y, -4.95), (18, .28, .37), dark)
box("CatwalkDeck", (-2.3, 4.10, -4.45), (10.1, .12, 1.1), dark)
for i in range(67):
    box("CatwalkGrating", (-7.25 + i * .15, 4.18, -4.45), (.035, .035, 1.02), edge, bevel=0)
for z in (-4.95, -4.44, -3.93):
    box("CatwalkLongitudinal", (-2.3, 4.20, z), (10.1, .025, .035), steel, bevel=0)
for x in (-6.8, -5.3, -3.8, -2.3, -.8, .7, 2.2):
    box("CatwalkUpright", (x, 4.66, -3.88), (.065, 1.05, .065), steel)
    box("RailFoot", (x, 4.22, -3.88), (.18, .045, .16), edge)
    box("CatwalkBrace", (x, 3.90, -4.47), (.095, .28, 1.10), dark)
for y in (4.3, 5.12):
    box("CatwalkRail", (-2.3, y, -3.88), (10.1, .065, .065), yellow)
box("CatwalkToeBoard", (-2.3, 4.26, -3.9), (10.1, .15, .035), steel)
# Access ladder stays beside the bench, away from all equipment pick volumes.
for x in (-6.9, -6.3):
    pipe("LadderRail", [(x,.10,-3.70),(x,4.22,-3.70),(x,4.78,-4.04)], .042, yellow)
    for y in (.6, 2.2, 3.9):
        box("LadderBracket", (x,y,-4.20), (.12,.07,.95), steel)
for i in range(13):
    pipe("LadderRung", [(-6.90,.28+i*.30,-3.70),(-6.30,.28+i*.30,-3.70)], .025, edge)

# Window panels are deliberately separate from a bevelled structural grid.
for i in range(5):
    for j in range(3):
        box("WarmWindowPane", (1.65 + i * .98, 3.10 + j * .90, -5.34), (.91, .83, .025), warm_glass, bevel=0)
for x in (1.13, 2.16, 3.14, 4.12, 5.10, 6.1):
    box("WindowMullion", (x, 4.0, -5.25), (.065, 2.82, .1), dark)
for y in (2.62, 3.55, 4.45, 5.37):
    box("WindowCrossbar", (3.6, y, -5.25), (5.05, .065, .1), dark)
for x in (1.04, 6.18):
    box("WindowRecessSide", (x, 4.0, -5.30), (.18, 3.03, .38), steel)
for y in (2.50, 5.49):
    box("WindowRecessRail", (3.61, y, -5.29), (5.30, .17, .38), steel)
box("WindowSill", (3.61, 2.46, -5.04), (5.46, .10, .67), concrete)
for x in (1.60, 3.57, 5.57):
    box("WindowLatch", (x, 3.59, -5.16), (.15,.045,.08), edge)
pipe("WallConduit", [(-6.4, 3.5, -5), (-5.8, 3.5, -5), (-5.8, 2.9, -5), (-4.4, 2.9, -5)], .038, edge)
label("BayNumber", "BAY 01", (-5.9, 5.85, -5.24), .58, yellow)
for x in (-6.6, -.70):
    pipe("UpperWallPipe", [(x,7.20,-5.16),(x,6.65,-5.16),(x+.26,6.40,-5.16),(x+.26,5.47,-5.16),(x+.53,5.22,-5.16),(x+1.05,5.22,-5.16)], .070, steel)
    for y in (5.8,6.8):
        box("PipeClamp", (x,y,-5.22), (.20,.09,.15), edge)
pipe("CableTrunk", [(-6.9,6.8,-5.21),(-3.7,6.8,-5.21),(-3.7,5.63,-5.21),(-2.75,5.63,-5.21)], .034, dark)
box("ElectricalCabinet", (-.38, 2.95, -5.09), (.66,1.13,.37), steel, bevel=.045)
box("ElectricalDoor", (-.38, 2.95, -4.875), (.57,1.02,.07), dark)
box("ElectricalHandle", (-.15, 2.9, -4.816), (.032,.23,.06), edge)
label("ElectricalWarning", "24 V", (-.60, 3.19, -4.826), .15, yellow)
pipe("CabinetSupply", [(-.38,3.52,-5.09),(-.38,3.80,-5.09),(-1.0,3.80,-5.09),(-1.0,6.7,-5.09)], .032, dark)
# Recessed exhaust grille, large enough to read in the desktop establishing view.
cylinder("VentSurround", (-1.95,6.05,-5.24), .62,.18, steel, horizontal=True, vertices=24)
cylinder("VentDarkWell", (-1.95,6.05,-5.115), .53,.025, dark, horizontal=True, vertices=24)
for offset in (-.36,-.18,0,.18,.36):
    length = 2 * math.sqrt(.49**2-offset**2)
    box("VentGrille", (-1.95,6.05+offset,-5.085), (length,.035,.025), edge, bevel=0)
for offset in (-.24,.24):
    box("VentVertical", (-1.95+offset,6.05,-5.06), (.035,.87,.025), steel, bevel=0)

print("FORGE BUILD: workbench and workshop props", flush=True)
box("WorkbenchTop", (-3.9, 1.08, -1.95), (3.7, .23, 1.25), wood, bevel=.025)
for z in (-2.24,-1.94,-1.64):
    box("WorkbenchPlankSeam", (-3.9, 1.199, z), (3.58,.004,.009), dark, bevel=0)
box("WorkbenchFrontLip", (-3.9, 1.0, -1.34), (3.8, .14, .10), steel)
for x in (-5.52, -2.3):
    for z in (-2.35, -1.55):
        box("WorkbenchLeg", (x, .5, z), (.12, 1.0, .12), dark)
        box("WorkbenchFoot", (x, .06, z), (.25, .08, .24), steel)
box("WorkbenchLowerShelf", (-3.9,.25,-1.95), (3.43,.06,1.02), dark)
box("BenchPartsBin", (-3.08,.43,-1.87), (.76,.30,.66), olive, bevel=.04)
box("DrawerCabinet", (-4.45, .51, -1.95), (1.45, .96, .87), red)
for i in range(5):
    box("DrawerFront", (-4.45, .16 + .17 * i, -1.50), (1.36, .145, .03), red)
    box("DrawerGap", (-4.45, .15 + .17 * i, -1.479), (1.29, .015, .01), dark)
    box("DrawerHandle", (-4.45, .18 + .17 * i, -1.45), (.54, .025, .05), edge)
box("ToolPegboard", (-3.92, 2.25, -2.74), (3.65, 1.85, .13), yellow)
for x in range(16):
    for y in range(7):
        cylinder("PegboardHole", (-5.56 + x * .215, 1.48 + y * .25, -2.662), .017, .006, dark, horizontal=True, vertices=8)
for x, length in ((-5.35,.61),(-5.03,.49),(-4.74,.38)):
    box("SpannerShaft", (x,2.29-length*.42,-2.56), (.06,length,.055), edge)
    box("SpannerShoulder", (x,2.40,-2.56), (.18,.10,.055), steel)
    for dx in (-.073,.073):
        jaw=box("SpannerJaw", (x+dx,2.47,-2.56), (.055,.15,.055), edge)
        jaw.rotation_euler.y = math.radians(-12 if dx < 0 else 12)
    box("ToolHook", (x,2.39,-2.48), (.045,.022,.12), dark)
box("HammerHead", (-4.25,2.43,-2.55), (.37,.13,.12), steel)
box("HammerHandle", (-4.25,2.13,-2.55), (.078,.56,.07), wood)
box("HammerGrip", (-4.25,1.92,-2.55), (.09,.19,.09), rubber)
for dx in (-.07,.07):
    grip=box("PliersGrip", (-3.83+dx,2.08,-2.53), (.075,.34,.07), red)
    grip.rotation_euler.y = math.radians(18 if dx < 0 else -18)
    box("PliersJaw", (-3.83+dx*.5,2.40,-2.53), (.065,.23,.055), edge)
cylinder("PliersJoint", (-3.83,2.26,-2.48), .065,.045, steel, horizontal=True, vertices=12)
for x,y,length in ((-3.42,2.10,.49),(-3.16,2.16,.38)):
    box("DriverShaft", (x,y+.16,-2.54), (.025,length*.52,.025), edge)
    box("DriverHandle", (x,y-length*.2,-2.54), (.095,length*.46,.08), yellow)
box("DrillBattery", (-2.69,1.91,-2.50), (.26,.11,.15), dark)
box("DrillGrip", (-2.68,2.06,-2.5), (.12,.28,.12), rubber)
box("DrillHousing", (-2.72,2.27,-2.50), (.39,.18,.17), red, bevel=.04)
pipe("DrillChuck", [(-2.52,2.27,-2.50),(-2.37,2.27,-2.50)], .06, steel)
pipe("DrillBit", [(-2.37,2.27,-2.50),(-2.23,2.27,-2.50)], .016, edge)
box("BenchLampStrip", (-3.9, 3.29, -2.58), (3.7, .045, .08), lamp_glass)
box("BenchLampHousing", (-3.9, 3.32, -2.6), (3.85, .08, .15), dark)
box("BenchRepairMat", (-3.74,1.207,-1.93), (.92,.018,.55), rubber, bevel=.01)
box("OpenPartsTray", (-4.70,1.24,-1.68), (.50,.06,.34), steel)
for i in range(4):
    cylinder("TrayBolt", (-4.85+i*.095,1.286,-1.68), .024,.04, edge, vertices=6)
box("LooseDriverHandle", (-3.7,1.235,-1.71), (.23,.055,.055), red)
pipe("LooseDriverShaft", [(-3.82,1.235,-1.71),(-4.08,1.235,-1.71)], .012, edge)
box("BenchOilTin", (-5.24,1.38,-2.18), (.20,.34,.16), olive)
pipe("OilTinSpout", [(-5.24,1.54,-2.18),(-5.24,1.67,-2.18),(-5.09,1.70,-2.18)], .02, edge)
cylinder("BenchViceBase", (-2.65, 1.23, -1.56), .18, .12, dark)
box("BenchViceJaw", (-2.65, 1.36, -1.55), (.4, .2, .22), steel)
box("BenchViceSlot", (-2.65, 1.47, -1.55), (.042, .012, .22), dark)
pipe("ViceScrew", [(-2.65,1.33,-1.43),(-2.65,1.33,-1.18)], .028, edge)
pipe("ViceHandle", [(-2.65,1.22,-1.18),(-2.65,1.45,-1.18)], .017, steel)
cylinder("RepairMotor", (-2.65,1.58,-1.55), .12,.31, steel, horizontal=True, vertices=16)
cylinder("RepairMotorShaft", (-2.65,1.58,-1.32), .041,.16, edge, horizontal=True, vertices=12)
for y in (1.55,1.61):
    box("RepairMotorFin", (-2.65,y,-1.56), (.31,.018,.23), dark)
pipe("PendantCable", [(-3.65, 6.4, -1.4), (-3.65, 3.9, -1.4)], .018, rubber)
bpy.ops.mesh.primitive_cone_add(vertices=48, radius1=.53, radius2=.17, depth=.37)
pendant = finish(bpy.context.object, "PendantShade", dark, garage)
pendant.location = v((-3.65, 3.72, -1.4))
cylinder("PendantDiffuser", (-3.65, 3.53, -1.4), .48, .014, lamp_glass)
cylinder("PendantCap", (-3.65, 3.96, -1.4), .16, .17, steel)

# Equipment cases, straps, a weathered banner and foreground clutter.
for x, y, z, w, h, d in [(4.0,.38,-2.0,1.4,.75,.8), (4.2,1.02,-2.2,1.18,.54,.76),
                         (5.6,.42,-1.9,1.55,.8,1.0), (5.55,1.25,-2.1,1.25,.8,.86),
                         (4.8,.32,-3.8,1.7,.65,1.0), (6.5,.45,-3.4,1.2,.9,1.0)]:
    box("EquipmentCase", (x,y,z), (w,h,d), olive, bevel=.065)
    box("CaseLidSeam", (x,y+h*.30,z+d*.5+.018), (w*.92,.018,.018), dark, bevel=0)
    box("CaseLid", (x,y+h*.46,z), (w*1.025,.075,d*1.025), olive, bevel=.025)
    for dx in (-w * .34, w * .34):
        box("CaseStrap", (x+dx,y,z+d*.5+.012), (.05,h,.03), dark)
        box("CaseStrapTop", (x+dx,y+h*.5+.012,z), (.05,.03,d), dark)
        box("CaseLatch", (x+dx,y+h*.15,z+d*.5+.04), (.10,.15,.06), edge)
    box("CaseHandle", (x,y+h*.10,z+d*.5+.04), (.25,.055,.07), dark)
    for dx in (-w*.43,w*.43):
        box("CaseCorner", (x+dx,y-h*.37,z+d*.5+.018), (.14,.16,.035), steel)
    box("CaseLabelPlate", (x,y-h*.14,z+d*.5+.025), (.32,.14,.013), dark, bevel=0)
    label("CaseStencil", "P / 01", (x-.14,y-h*.14-.04,z+d*.5+.036), .075, edge)
for i in range(8):
    box("BannerFold", (5.7+i*.055, 2.02, -1.31+math.sin(i)*.025), (.07,1.48,.016), cloth, bevel=0)
pipe("HydraulicSupply", [(2.9,.08,.7), (3.5,.05,1.3), (3.2,.04,2.1), (1.9,.04,2.7), (1.0,.04,2.35)], .028, rubber)
pipe("BenchPowerCable", [(-3.7,.2,-1.4), (-3.3,.07,-.8), (-3.5,.035,.8), (-2.3,.035,1.9)], .025, rubber)
box("ForegroundToolcart", (-4.35,.61,3.2), (1.54,.83,.72), red, bevel=.045)
box("ToolcartTray", (-4.35,1.045,3.2), (1.72,.07,.87), dark)
for z in (2.78,3.62):
    box("ToolcartTrayLip", (-4.35,1.11,z), (1.72,.10,.035), steel)
for x in (-5.18,-3.52):
    box("ToolcartSideLip", (x,1.11,3.2), (.035,.10,.86), steel)
for i in range(4):
    box("CartDrawer", (-4.35,.38+i*.175,3.577), (1.42,.155,.035), red)
    box("CartDrawerGap", (-4.35,.29+i*.175,3.60), (1.40,.018,.014), dark, bevel=0)
    box("CartDrawerHandle", (-4.35,.38+i*.175,3.62), (.79,.032,.062), edge)
for x in (-4.94,-3.76):
    for z in (2.96,3.44):
        wheel=cylinder("CartWheel", (x,.15,z), .13,.09, rubber, horizontal=True, vertices=12)
        box("CasterFork", (x,.25,z), (.16,.18,.08), steel)
pipe("CartPushHandle", [(-3.49,.78,2.95),(-3.37,.78,2.95),(-3.37,.78,3.47),(-3.49,.78,3.47)], .026, edge)
cylinder("ForegroundCan", (-3.9,1.22,3.23), .09,.30, steel, vertices=16)
box("CartLooseTool", (-4.65,1.105,3.32), (.37,.07,.09), steel)
box("CartToolGrip", (-4.43,1.105,3.32), (.19,.08,.095), red)
# Open crate with inset contents and a tilted lid instead of a featureless block.
box("OpenCaseBase", (4.8,.13,3.3), (1.70,.20,1.0), dark, bevel=.035)
for x in (4.0,5.6):
    box("OpenCaseSide", (x,.43,3.3), (.10,.65,1.0), olive)
for z in (2.85,3.75):
    box("OpenCaseWall", (4.8,.43,z), (1.70,.65,.10), olive)
box("OpenCaseInterior", (4.8,.25,3.3), (1.46,.12,.78), rubber)
box("SpareHousing", (4.65,.40,3.35), (.64,.28,.42), steel, bevel=.055)
cylinder("SpareHousingPort", (4.65,.57,3.35), .105,.055, edge, vertices=16)
lid=box("OpenCaseLid", (4.8,.94,2.86), (1.72,.10,1.0), olive, bevel=.025)
lid.rotation_euler.x = math.radians(-55)
for x in (4.35,5.25):
    box("OpenCaseLatch", (x,.57,3.82), (.12,.15,.04), edge)
box("OpenCaseHandle", (4.8,.43,3.83), (.35,.06,.09), dark)

# Restrained floor markings define the work area without adding clutter.
for x in (-6.0,6.9):
    box("FloorBayStripe", (x,-.001,.2), (.085,.006,8.7), yellow, bevel=0)
for z in (-3.9,4.5):
    box("FloorBayStripe", (.45,-.001,z), (12.85,.006,.085), yellow, bevel=0)
box("DrainRecess", (0,-.004,5.2), (11.8,.014,.36), dark, bevel=0)
for i in range(79):
    box("DrainGrille", (-5.8+i*.148,.006,5.2), (.027,.012,.33), steel, bevel=0)
for x in (-5.98,5.98):
    box("DrainFrame", (x,.003,5.2), (.035,.018,.42), edge, bevel=0)

print("FORGE BUILD: grated service turntable", flush=True)
cylinder("TurntableFoundation", (0,.08,0), 2.08,.16,dark, vertices=96)
cylinder("TurntableDeck", (0,.20,0), 1.98,.22,steel, vertices=96)
annulus("OuterMachinedRim",1.9,2.07,.32,.12,dark)
annulus("InnerMachinedRing",1.58,1.63,.322,.008,edge)
annulus("OuterMachinedRing",1.86,1.90,.322,.008,edge)
for i in range(28):
    a = math.tau*i/28
    annulus("SafetyStripe",1.93,2.05,.324,.008,yellow if i%2==0 else dark,
            a,a+math.tau/28*.82, sections=3)
for i in range(-15,16):
    x=i*.094
    length=math.sqrt(max(0,1.51**2-x*x))*2
    box("DeckGrate",(x,.323,0),(.045,.014,length),dark,bevel=0)
for i in range(-5,6):
    z=i*.27
    length=math.sqrt(max(0,1.5**2-z*z))*2
    box("GrateCrossbar",(0,.338,z),(length,.014,.025),edge,bevel=0)
for i in range(24):
    a=math.tau*i/24
    cylinder("RimBolt",(math.cos(a)*1.76,.339,math.sin(a)*1.76),.038,.024,edge,vertices=6)
box("ControlPedestal",(2.35,.44,-.10),(.90,.31,.76),dark)
box("PedestalPanel",(2.35,.63,.31),(.60,.24,.04),steel)
box("PedestalStatus",(2.35,.63,.341),(.28,.036,.012),cyan)

print("FORGE BUILD: articulated arm and authored service cycle", flush=True)
cylinder("ArmMount",(0,.12,0),.39,.24,steel,parent=arm)
base=empty("BaseYaw",(0,.22,0),arm)
cylinder("RotaryBase",(0,.08,0),.29,.18,yellow,parent=base)
box("MotorCabinet",(.16,.31,-.06),(.48,.54,.46),yellow,parent=base,bevel=.055)
shoulder=empty("Shoulder",(0,.58,0),base)
cylinder("ShoulderBearing",(0,0,0),.25,.53,dark,parent=shoulder,horizontal=True)
cylinder("ShoulderCap",(0,0,.29),.21,.035,steel,parent=shoulder,horizontal=True)
cylinder("ShoulderHub",(0,0,.319),.12,.025,yellow,parent=shoulder,horizontal=True)
box("UpperArmHousing",(0,.64,0),(.36,1.12,.37),yellow,parent=shoulder,bevel=.05)
box("UpperArmInset",(0,.63,.205),(.21,.80,.055),dark,parent=shoulder)
for offset in (-.09,.09):
    box("UpperArmBrace",(offset,.64,.24),(.025,.78,.035),steel,parent=shoulder)
pipe("UpperSupplyHose",[(.24,.08,-.20),(.27,.48,-.21),(.24,1.1,-.21),(.04,1.25,-.18)],.025,rubber,parent=shoulder)
elbow=empty("Elbow",(0,1.30,0),shoulder)
cylinder("ElbowBearing",(0,0,0),.23,.50,dark,parent=elbow,horizontal=True)
cylinder("ElbowCap",(0,0,.275),.19,.038,yellow,parent=elbow,horizontal=True)
cylinder("ElbowHub",(0,0,.305),.08,.025,edge,parent=elbow,horizontal=True)
box("ForearmHousing",(0,.53,0),(.29,.95,.29),yellow,parent=elbow,bevel=.045)
box("ForearmGuard",(0,.53,.18),(.18,.66,.045),steel,parent=elbow)
pipe("ForearmCable",[(.18,.02,-.15),(.21,.45,-.17),(.17,.88,-.16),(.05,1.05,-.13)],.021,rubber,parent=elbow)
for node,length in ((shoulder,1.05),(elbow,.82)):
    # Rigid actuator rods move with their segment in this initial mechanism.
    box("ActuatorBody",(-.22,length*.52,-.01),(.068,length*.53,.08),dark,parent=node)
    box("ActuatorRod",(-.22,length*.84,-.01),(.028,length*.28,.028),edge,parent=node)
wrist=empty("Wrist",(0,1.10,0),elbow)
cylinder("WristBearing",(0,0,0),.14,.34,dark,parent=wrist,horizontal=True)
box("ToolBody",(0,.11,0),(.16,.23,.20),steel,parent=wrist)
box("ToolIndicator",(0,.13,.112),(.065,.10,.018),cyan,parent=wrist)
for dx in (-.075,.075):
    box("ToolFinger",(dx,.25,0),(.043,.21,.055),dark,parent=wrist)
    box("ToolFingertip",(dx*.6,.35,0),(.08,.038,.055),edge,parent=wrist)
tip=empty("ToolContact",(0,.36,0),wrist)

# All joints share one named NLA track; glTF exports a single coherent clip.
samples=[(0,-32,125,-3,-8),(1.3,-32,125,-3,-8),(2.8,12,90,-12,0),
         (3.9,24,99,-33,0),(4.5,24.5,98.5,-33,0),
         (5.1,24,99,-32,0),(5.7,23.8,99.2,-33,0),
         (6.8,12,90,-12,0),(8.4,-32,125,-3,-8),(10,-32,125,-3,-8)]
for sample in samples:
    sec,s,e,w,b=sample
    for node,angle,axis in ((shoulder,-s,1),(elbow,-e,1),(wrist,-w,1),(base,b,2)):
        node.rotation_euler[axis]=math.radians(angle)
        node.keyframe_insert(data_path="rotation_euler",frame=round(sec*30),index=axis)
for node in (base,shoulder,elbow,wrist):
    action=node.animation_data.action
    action.name=node.name+"_service_cycle"
    track=node.animation_data.nla_tracks.new()
    track.name="service_cycle"
    track.strips.new("service_cycle",0,action)
    node.animation_data.action=None
scene.frame_set(0)


def descendants(root):
    return [root,*root.children_recursive]


def prepare_meshes(root,merge=False):
    # Bevels and generated UVs are applied before export, never engine-dependent.
    for obj in list(descendants(root)):
        if obj.type not in {"MESH","CURVE","FONT"}:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active=obj
        if obj.type != "MESH":
            bpy.ops.object.convert(target="MESH")
        for mod in list(obj.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)
        if not obj.data.uv_layers:
            bpy.ops.object.mode_set(mode="EDIT")
            bpy.ops.mesh.select_all(action="SELECT")
            bpy.ops.uv.smart_project(angle_limit=1.15,island_margin=.008)
            bpy.ops.object.mode_set(mode="OBJECT")
    if merge:
        meshes=[obj for obj in descendants(root) if obj.type=="MESH"]
        bpy.ops.object.select_all(action="DESELECT")
        for obj in meshes:
            obj.select_set(True)
        bpy.context.view_layer.objects.active=meshes[0]
        bpy.ops.object.join()
        meshes[0].name="WorkshopStaticMesh"


prepare_meshes(garage,merge=True)
prepare_meshes(arm)
scene.frame_set(0)
bpy.ops.wm.save_as_mainfile(filepath=str(DEST/"source"/"forge_garage.blend"))
exports = [(garage,"workshop.glb",False)]
if not WORKSHOP_ONLY:
    exports.append((arm,"service_arm.glb",True))
for root,filename,animated in exports:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in descendants(root):
        obj.select_set(True)
    bpy.context.view_layer.objects.active=root
    bpy.ops.export_scene.gltf(filepath=str(DEST/filename),export_format="GLB",
        use_selection=True,export_animations=animated,export_animation_mode="NLA_TRACKS",
        export_merge_animation="NLA_TRACK",export_frame_range=True,export_force_sampling=True,
        export_bake_animation=True,export_optimize_animation_size=True)
    print("FORGE BUILD: exported",filename,(DEST/filename).stat().st_size,flush=True)
print("FORGE BUILD: complete",flush=True)
