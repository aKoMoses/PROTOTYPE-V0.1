"""Authored, reproducible module modelling helpers. Blender 4.5, no providers.

Public helpers use Godot metres, Y up and +Z toward the viewer/robot front.
The runtime GLBs contain only joined material batches, with embedded PBR maps.
"""
from pathlib import Path
import json
import math
import random
import hashlib
import bpy
from mathutils import Vector, Matrix, Euler

DEST = Path(__file__).resolve().parent.parent / 'art' / 'modules'
SOURCE = DEST / 'source'
PREVIEW = DEST / 'previews'
ROOT = None
MATERIALS = {}
IDENTIFIER = ''
AXIS = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))


def v(pos):
    return Vector((pos[0], -pos[2], pos[1]))


def rotation_basis(rotation):
    return (AXIS @ Euler(rotation, 'XYZ').to_matrix() @ AXIS.inverted()).to_4x4()


def material(key):
    if key in MATERIALS:
        return MATERIALS[key]
    palette = {
        'steel': ((.115, .145, .155), .78, .48),
        'paint': ((.54, .31, .105), .32, .58),
        'ivory': ((.66, .635, .555), .12, .57),
        'edge': ((.245, .265, .255), .82, .43),
        'rubber': ((.022, .031, .032), .06, .78),
        'copper': ((.39, .18, .077), .78, .39),
        'jade': ((.043, .16, .105), .24, .33),
        'green': ((.19, .56, .26), .13, .32),
        'cyan': ((.036, .44, .51), .12, .30),
        'amber': ((.88, .30, .045), .10, .33),
        'red': ((.36, .072, .042), .36, .55),
    }
    color, metal, rough = palette[key]
    mat = bpy.data.materials.new(key)
    mat.use_nodes = True
    mat.diffuse_color = (*color, 1)
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Metallic'].default_value = metal
    bsdf.inputs['Roughness'].default_value = rough
    if key in ('cyan', 'green', 'amber'):
        bsdf.inputs['Emission Color'].default_value = (*color, 1)
        bsdf.inputs['Emission Strength'].default_value = .22 if key == 'amber' else .15
    else:
        # Portable surface detail. Export texture nodes, never shader-only noise.
        size = 256
        rng = random.Random('module-v2-' + key)
        albedo, roughness, normal = [], [], []
        for y in range(size):
            for x in range(size):
                grain = rng.uniform(-.025, .025)
                cloud = math.sin(x * .045 + math.sin(y * .035)) * math.sin(y * .027 + 1.7)
                brushed = math.sin(x * 1.75 + y * .13) * .010
                stain = max(0, math.sin(x * .072 + y * .021) * math.cos(y * .063)) ** 5
                scratch = ((x * 17 + y * 3) % 787 < 2 and (y % 31) < 13)
                shade = .94 + cloud * .055 + grain + brushed - stain * .075
                fleck = .065 if scratch and key != 'rubber' else 0
                albedo.extend((*(max(0, min(1, c * shade + fleck)) for c in color), 1))
                q = max(.12, min(.95, rough + cloud * .05 + stain * .09 + grain))
                roughness.extend((q, q, q, 1))
                normal.extend((.5 + grain * .14, .5 + brushed * .17, 1, 1))
        for suffix, pixels, color_space, socket in [
                ('albedo', albedo, 'sRGB', 'Base Color'),
                ('roughness', roughness, 'Non-Color', 'Roughness'),
                ('normal', normal, 'Non-Color', None)]:
            image = bpy.data.images.new('module_' + key + '_' + suffix, width=size, height=size)
            image.colorspace_settings.name = color_space
            image.pixels.foreach_set(pixels)
            image.filepath_raw = str(SOURCE / ('module_' + key + '_' + suffix + '.png'))
            image.file_format = 'PNG'
            image.save()
            image.pack()
            tex = mat.node_tree.nodes.new('ShaderNodeTexImage')
            tex.image = image
            if socket:
                mat.node_tree.links.new(tex.outputs['Color'], bsdf.inputs[socket])
            else:
                n = mat.node_tree.nodes.new('ShaderNodeNormalMap')
                n.inputs['Strength'].default_value = .30
                mat.node_tree.links.new(tex.outputs['Color'], n.inputs['Color'])
                mat.node_tree.links.new(n.outputs['Normal'], bsdf.inputs['Normal'])
    MATERIALS[key] = mat
    return mat


def begin(identifier):
    global ROOT, IDENTIFIER
    DEST.mkdir(parents=True, exist_ok=True)
    SOURCE.mkdir(exist_ok=True)
    PREVIEW.mkdir(exist_ok=True)
    (SOURCE / '.gdignore').write_text('')
    (PREVIEW / '.gdignore').write_text('')
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    IDENTIFIER = identifier
    ROOT = bpy.data.objects.new('Module_' + identifier, None)
    bpy.context.scene.collection.objects.link(ROOT)
    return ROOT


def finish(obj, name, mat, bevel=0):
    obj.name = name
    obj.parent = ROOT
    obj.data.materials.append(material(mat))
    if bevel > 0:
        mod = obj.modifiers.new('Machined edge radius', 'BEVEL')
        mod.width = bevel
        mod.segments = 2
        mod.affect = 'EDGES'
        mod.material = -1
    if obj.type == 'MESH':
        normal = obj.modifiers.new('Weighted surface normals', 'WEIGHTED_NORMAL')
        normal.keep_sharp = True
        normal.weight = 40
    return obj


def box(name, pos, dims, mat, bevel=.008, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1)
    obj = bpy.context.object
    obj.scale = (dims[0], dims[2], dims[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    finish(obj, name, mat, min(bevel, min(dims) * .22))
    obj.matrix_world = Matrix.Translation(v(pos)) @ rotation_basis(rotation)
    return obj


def shell(name, outline, back_z, front_z, mat, bevel=.004, front_scale=.92):
    """Tapered polygonal armour with a recessed mounting plane at Godot Z=0."""
    count = len(outline)
    verts = [v((x, y, back_z)) for x, y in outline]
    verts += [v((x * front_scale, y * front_scale, front_z)) for x, y in outline]
    faces = [tuple(reversed(range(count))), tuple(range(count, count * 2))]
    for i in range(count):
        j = (i + 1) % count
        faces.append((i, j, j + count, i + count))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return finish(obj, name, mat, bevel)


def arc(name, pos, outer, inner, depth, mat, start, end, segments=20):
    """Closed annular sector, oriented on the outward Godot +Z face."""
    verts, faces = [], []
    width = segments + 1
    for z in (-depth / 2, depth / 2):
        for radius in (outer, inner):
            for i in range(width):
                a = start + (end - start) * i / segments
                verts.append(v((pos[0] + math.cos(a)*radius,
                                pos[1] + math.sin(a)*radius, pos[2] + z)))
    for i in range(segments):
        j = i + 1
        faces.extend(((i, j, width+j, width+i),
                      (2*width+i, 3*width+i, 3*width+j, 2*width+j),
                      (i, 2*width+i, 2*width+j, j),
                      (width+i, width+j, 3*width+j, 3*width+i)))
    faces.extend(((0, width, 3*width, 2*width),
                  (segments, 2*width+segments, 3*width+segments, width+segments)))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return finish(obj, name, mat, min(.0008, depth * .12))


def cylinder(name, pos, radius, depth, mat, axis=(0, 1, 0), vertices=24, radius_top=None, bevel=.003):
    if radius_top is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius, radius2=radius_top, depth=depth)
    obj = bpy.context.object
    finish(obj, name, mat, min(bevel, radius * .15, depth * .18))
    obj.location = v(pos)
    obj.rotation_mode = 'QUATERNION'
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(v(axis).normalized())
    for face in obj.data.polygons:
        face.use_smooth = len(face.vertices) == 4
    return obj


def ring(name, pos, outer, inner, depth, mat, axis=(0, 0, 1), segments=32):
    # Closed machined annulus with an actual bore. No black disk faking a hole.
    verts, faces = [], []
    for z in (-depth / 2, depth / 2):
        for radius in (outer, inner):
            for i in range(segments):
                a = math.tau * i / segments
                verts.append((math.cos(a) * radius, math.sin(a) * radius, z))
    for i in range(segments):
        j = (i + 1) % segments
        faces.extend(((i, j, segments + j, segments + i),
                      (2*segments+i, 3*segments+i, 3*segments+j, 2*segments+j),
                      (i, 2*segments+i, 2*segments+j, j),
                      (segments+i, segments+j, 3*segments+j, 3*segments+i)))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    finish(obj, name, mat, min(.0017, depth * .1))
    obj.location = v(pos)
    obj.rotation_mode = 'QUATERNION'
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(v(axis).normalized())
    for index, poly in enumerate(mesh.polygons):
        poly.use_smooth = index % 4 in (2, 3)
    return obj


def pipe(name, points, radius, mat):
    curve = bpy.data.curves.new(name, 'CURVE')
    curve.dimensions = '3D'
    curve.resolution_u = 6
    curve.bevel_depth = radius
    curve.bevel_resolution = 1
    spline = curve.splines.new('BEZIER')
    spline.bezier_points.add(len(points)-1)
    for point, pos in zip(spline.bezier_points, points):
        point.co = v(pos)
        point.handle_left_type = 'AUTO'
        point.handle_right_type = 'AUTO'
    obj = bpy.data.objects.new(name, curve)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = ROOT
    obj.data.materials.append(material(mat))
    return obj


def text(name, body, pos, size, mat, rotation=(0, 0, 0)):
    curve = bpy.data.curves.new(name, 'FONT')
    curve.body = body
    curve.align_x = 'CENTER'
    curve.align_y = 'CENTER'
    curve.size = size
    curve.extrude = .00012
    curve.resolution_u = 2
    obj = bpy.data.objects.new(name, curve)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = ROOT
    obj.data.materials.append(material(mat))
    # Text's default local XY face becomes Godot XY, outward +Z.
    obj.matrix_world = Matrix.Translation(v(pos)) @ rotation_basis(rotation) @ AXIS.to_4x4()
    return obj


def bolt(name, pos, radius=.008, axis=(0, 0, 1)):
    obj = cylinder(name, pos, radius, .007, 'edge', axis=axis, vertices=6, bevel=.0009)
    p = Vector(pos) + Vector(axis).normalized() * .004
    cylinder(name + '_Socket', p, radius * .43, .0012, 'rubber', axis=axis, vertices=6, bevel=0)
    return obj


def _render(identifier):
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.film_transparent = False
    scene.world.color = (.075, .075, .075)
    scene.world.use_nodes = True
    scene.world.node_tree.nodes.get('Background').inputs['Color'].default_value = (.055, .067, .075, 1)
    scene.world.node_tree.nodes.get('Background').inputs['Strength'].default_value = .50
    scene.view_settings.view_transform = 'AgX'
    corners = [o.matrix_world @ Vector(c) for o in ROOT.children if o.type == 'MESH' for c in o.bound_box]
    lo = Vector(tuple(min(p[i] for p in corners) for i in range(3)))
    hi = Vector(tuple(max(p[i] for p in corners) for i in range(3)))
    center = (lo + hi) * .5
    radius = max(hi - lo)
    cam_data = bpy.data.cameras.new('Preview lens')
    cam = bpy.data.objects.new('Preview lens', cam_data)
    scene.collection.objects.link(cam)
    cam.location = center + v((radius * 1.3, radius * .70, radius * 2.9))
    cam.rotation_euler = (center - cam.location).to_track_quat('-Z', 'Y').to_euler()
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = radius * 1.65
    scene.camera = cam
    for name, pos, energy, color, size in [
        ('Soft key', (-1.1, 1.7, 1.9), 95, (1, .86, .68), 1.0),
        ('Cool fill', (1.4, .5, 1.0), 65, (.67, .82, 1), 1.0),
        ('Edge strip', (.6, 1.4, -1.2), 105, (1, .70, .39), .70)]:
        data = bpy.data.lights.new(name, 'AREA')
        data.energy = energy
        data.color = color
        data.shape = 'DISK'
        data.size = size
        light = bpy.data.objects.new(name, data)
        scene.collection.objects.link(light)
        light.location = center + v(pos)
        light.rotation_euler = (center - light.location).to_track_quat('-Z', 'Y').to_euler()
    scene.render.filepath = str(PREVIEW / (identifier + '.png'))
    bpy.ops.render.render(write_still=True)


def export(identifier):
    # Keep the editable individual-part source before creating material batches.
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / (identifier + '.blend')))
    authored = [obj for obj in ROOT.children if obj.type in ('MESH', 'CURVE', 'FONT')]
    bpy.ops.object.select_all(action='DESELECT')
    for obj in authored:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = authored[0]
    bpy.ops.object.convert(target='MESH')
    bpy.ops.object.join()
    joined = bpy.context.object
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.separate(type='MATERIAL')
    bpy.ops.object.mode_set(mode='OBJECT')
    batches = [obj for obj in ROOT.children if obj.type == 'MESH']
    for obj in batches:
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        key = obj.data.materials[0].name.split('.')[0]
        obj.name = key
        if not obj.data.uv_layers:
            bpy.ops.object.mode_set(mode='EDIT')
            bpy.ops.mesh.select_all(action='SELECT')
            bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=.006)
            bpy.ops.object.mode_set(mode='OBJECT')
        obj.data.calc_loop_triangles()
        obj.select_set(False)
    bpy.ops.object.select_all(action='DESELECT')
    ROOT.select_set(True)
    for obj in batches:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = batches[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    path = DEST / (identifier + '.glb')
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True,
                              export_apply=True, export_yup=True, export_texcoords=True,
                              export_normals=True, export_materials='EXPORT',
                              export_cameras=False, export_lights=False)
    corners = [obj.matrix_world @ Vector(c) for obj in batches for c in obj.bound_box]
    low = tuple(min(p[i] for p in corners) for i in range(3))
    high = tuple(max(p[i] for p in corners) for i in range(3))
    metrics = {'asset': identifier, 'triangles': sum(len(o.data.loop_triangles) for o in batches),
               'material_batches': len(batches), 'bytes': path.stat().st_size,
               'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
               'blender_bounds_min': low, 'blender_bounds_max': high,
               'origin': 'Locally authored Blender geometry and PBR textures, no external assets.',
               'source': 'source/' + identifier + '.blend'}
    (DEST / (identifier + '.asset.json')).write_text(json.dumps(metrics, indent=2) + '\n')
    print('MODULE ASSET ' + json.dumps(metrics), flush=True)
    _render(identifier)
