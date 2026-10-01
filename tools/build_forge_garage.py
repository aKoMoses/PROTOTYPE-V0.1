"""Build the first forge workshop and a keyed, rigid industrial arm in Blender.

All geometry and surface textures are authored here; no external asset provider.
Run with Blender --background --factory-startup --python tools/build_forge_garage.py.
Coordinates in helpers use Godot's Y-up frame. Source .blend and runtime GLBs
are written only under art/forge-garage, leaving the combat assets untouched.
"""
from pathlib import Path
import math
import random
import bpy
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


print("FORGE BUILD: workshop shell", flush=True)
box("ConcreteSlab", (0, -.14, 0), (19, .25, 16), concrete)
for x in range(-8, 9, 2):
    box("FloorExpansionJoint", (x, -.012, 0), (.022, .012, 15), dark, bevel=0)
for z in range(-6, 7, 2):
    box("FloorExpansionJoint", (0, -.012, z), (18, .012, .022), dark, bevel=0)
box("BackWall", (0, 3.7, -5.6), (18, 7.4, .24), rust)
box("LeftWall", (-7.5, 3.6, -1.0), (.22, 7.2, 9), dark)
for x in range(-8, 9):
    box("CorrugatedSheet", (x, 2.0, -5.43), (.87, 3.6, .055), steel)
    for rib in (-.35, -.12, .12, .35):
        box("SheetRib", (x + rib, 2.0, -5.36), (.024, 3.6, .05), rust, bevel=.004)
for x in (-6.3, -3.5, .6, 5.4, 7.6):
    box("ColumnWeb", (x, 3.75, -4.98), (.13, 7.5, .35), dark)
    for dz in (-.19, .19):
        box("ColumnFlange", (x, 3.75, -4.98 + dz), (.37, 7.5, .045), rust)
    box("ColumnFoot", (x, .1, -4.98), (.6, .15, .6), steel)
for y in (3.7, 6.7):
    box("CrossBeam", (0, y, -4.95), (18, .28, .37), dark)
box("CatwalkDeck", (-2.3, 4.10, -4.45), (10.1, .15, 1.1), steel)
for x in (-6.8, -5.3, -3.8, -2.3, -.8, .7, 2.2):
    box("CatwalkUpright", (x, 4.63, -3.88), (.045, 1.05, .045), rust)
for y in (4.3, 5.12):
    box("CatwalkRail", (-2.3, y, -3.88), (10.1, .045, .045), rust)

# Window panels are deliberately separate from a bevelled structural grid.
for i in range(5):
    for j in range(3):
        box("WarmWindowPane", (1.65 + i * .98, 3.10 + j * .90, -5.34), (.91, .83, .025), warm_glass, bevel=0)
for x in (1.13, 2.16, 3.14, 4.12, 5.10, 6.1):
    box("WindowMullion", (x, 4.0, -5.25), (.065, 2.82, .1), dark)
for y in (2.62, 3.55, 4.45, 5.37):
    box("WindowCrossbar", (3.6, y, -5.25), (5.05, .065, .1), dark)
pipe("WallConduit", [(-6.4, 3.5, -5), (-5.8, 3.5, -5), (-5.8, 2.9, -5), (-4.4, 2.9, -5)], .038, edge)
label("BayNumber", "BAY 01", (-5.9, 5.85, -5.24), .40, yellow)

print("FORGE BUILD: workbench and workshop props", flush=True)
box("WorkbenchTop", (-3.9, 1.08, -1.95), (3.7, .18, 1.15), wood)
box("WorkbenchFrontLip", (-3.9, 1.0, -1.34), (3.8, .14, .10), steel)
for x in (-5.52, -2.3):
    for z in (-2.35, -1.55):
        box("WorkbenchLeg", (x, .5, z), (.09, 1.0, .09), dark)
box("DrawerCabinet", (-4.45, .51, -1.95), (1.45, .96, .87), red)
for i in range(5):
    box("DrawerFront", (-4.45, .16 + .17 * i, -1.50), (1.36, .145, .03), red)
    box("DrawerGap", (-4.45, .15 + .17 * i, -1.479), (1.29, .015, .01), dark)
    box("DrawerHandle", (-4.45, .18 + .17 * i, -1.45), (.54, .025, .05), edge)
box("ToolPegboard", (-3.92, 2.25, -2.74), (3.65, 1.85, .13), yellow)
for x in range(16):
    for y in range(7):
        cylinder("PegboardHole", (-5.56 + x * .215, 1.48 + y * .25, -2.662), .017, .006, dark, horizontal=True, vertices=8)
for i in range(11):
    x = -5.34 + i * .27
    length = .37 + (i % 4) * .08
    box("HangingSpanner", (x, 2.34 - length * .30, -2.60), (.035, length, .036), edge)
    box("SpannerJaw", (x - .038, 2.38, -2.60), (.036, .10, .035), edge)
    box("SpannerJaw", (x + .038, 2.38, -2.60), (.036, .10, .035), edge)
    box("ToolHook", (x, 2.53, -2.56), (.055, .026, .10), dark)
box("BenchLampStrip", (-3.9, 3.29, -2.58), (3.7, .045, .08), lamp_glass)
box("BenchLampHousing", (-3.9, 3.32, -2.6), (3.85, .08, .15), dark)
for i in range(6):
    box("ToolOnBench", (-5.2 + i * .25, 1.20, -1.90 + (i % 2) * .14), (.08, .07, .28), steel)
cylinder("BenchViceBase", (-2.65, 1.23, -1.56), .18, .12, dark)
box("BenchViceJaw", (-2.65, 1.36, -1.55), (.4, .2, .22), steel)
box("BenchViceSlot", (-2.65, 1.47, -1.55), (.042, .012, .22), dark)
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
    for dx in (-w * .34, w * .34):
        box("CaseStrap", (x+dx,y,z+d*.5+.012), (.05,h,.03), dark)
        box("CaseStrapTop", (x+dx,y+h*.5+.012,z), (.05,.03,d), dark)
        box("CaseLatch", (x+dx,y+h*.15,z+d*.5+.04), (.10,.15,.06), edge)
    box("CaseHandle", (x,y+h*.10,z+d*.5+.04), (.25,.055,.07), dark)
for i in range(8):
    box("BannerFold", (5.7+i*.055, 2.02, -1.31+math.sin(i)*.025), (.07,1.48,.016), cloth, bevel=0)
pipe("HydraulicSupply", [(2.9,.08,.7), (3.5,.05,1.3), (3.2,.04,2.1), (1.9,.04,2.7), (1.0,.04,2.35)], .028, rubber)
pipe("BenchPowerCable", [(-3.7,.2,-1.4), (-3.3,.07,-.8), (-3.5,.035,.8), (-2.3,.035,1.9)], .025, rubber)
box("ForegroundToolcart", (-4.35,.41,3.2), (1.7,.8,.8), red)
box("ToolcartTray", (-4.35,.84,3.2), (1.8,.065,.9), dark)
cylinder("ForegroundCan", (-3.9,1.02,3.23), .09,.30, steel)
box("ForegroundLid", (4.8,.45,3.3), (1.7,.85,1.0), dark)

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
for root,filename,animated in ((garage,"workshop.glb",False),(arm,"service_arm.glb",True)):
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
