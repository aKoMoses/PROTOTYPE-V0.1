"""Approved shoulder-eye Traqueur. Rebuild with Blender 4.5 --background --python.

Godot metres, Y up, +Z toward the eye. Origin is the underside of the oval
shoulder foot. Editable parts and packed textures remain in source/tracker-eye.
"""
from pathlib import Path
from math import pi, sin, cos, tau
import json
import math
import random
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy
import bmesh
import module_modeling as model
from module_modeling import v, box, pipe


def mesh_part(name, points, faces, mat, bevel=0, smooth=True):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([v(p) for p in points], [], faces)
    mesh.update()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    model.finish(obj, name, mat, bevel)
    if smooth:
        for polygon in mesh.polygons:
            polygon.use_smooth = True
    # Cylinders already own UVs. Give authored surfaces their own UVs BEFORE
    # joining batches, so Blender cannot fill their missing layer with (0, 0).
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=1.15,island_margin=.01)
    bpy.ops.object.mode_set(mode='OBJECT')
    return obj


def turned(name, pos, radius, depth, mat, axis=(0, 1, 0), vertices=24, bevel=.0015):
    obj = model.cylinder(name, pos, radius, depth, mat, axis, vertices, bevel=bevel)
    for modifier in obj.modifiers:
        if modifier.type == 'BEVEL':
            modifier.segments = 1
    return obj


def collar(name, pos, outer, inner, depth, mat, axis=(0, 0, 1), segments=28):
    obj = model.ring(name, pos, outer, inner, depth, mat, axis, segments)
    for modifier in obj.modifiers:
        if modifier.type == 'BEVEL':
            modifier.segments = 1
    return obj


def painted_material(key, color, roughness, metallic, worn=False):
    """Embedded maps with broad paint wear; no renderer-specific noise nodes."""
    mat = bpy.data.materials.new(key)
    mat.use_nodes = True
    mat.diffuse_color = (*color, 1)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    shader = nodes.get('Principled BSDF')
    shader.inputs['Metallic'].default_value = metallic
    shader.inputs['Roughness'].default_value = roughness
    size = 256
    rng = random.Random('tracker-eye-' + key)
    islands = [(rng.random()*size, rng.random()*size, rng.uniform(5, 17)) for _ in range(23)]
    pixels, rough = [], []
    for y in range(size):
        for x in range(size):
            grain = rng.uniform(-.012, .012)
            cloud = sin(x*.039 + sin(y*.024)) * cos(y*.051)
            chip = worn and any(((x-a)/r)**2 + ((y-b)/(r*.65))**2 < .60 + .16*sin(x*.9+y*.7) for a,b,r in islands)
            shade = .93 + cloud*.075 + grain
            c = (.25, .245, .205) if chip else tuple(max(0, min(1, k*shade)) for k in color)
            pixels.extend((*c, 1))
            q = min(.95, roughness + .07*cloud + (.08 if chip else 0))
            rough.extend((q, q, q, 1))
    for suffix, data, space, socket in [('albedo', pixels, 'sRGB', 'Base Color'), ('roughness', rough, 'Non-Color', 'Roughness')]:
        image = bpy.data.images.new(key+'_'+suffix, width=size, height=size)
        image.colorspace_settings.name = space
        image.pixels.foreach_set(data)
        image.filepath_raw = str(model.SOURCE/(key+'_'+suffix+'.png'))
        image.file_format = 'PNG'
        image.save()
        image.pack()
        texture = nodes.new('ShaderNodeTexImage')
        texture.image = image
        links.new(texture.outputs['Color'], shader.inputs[socket])
    model.MATERIALS[key] = mat


def solid_material(key, color, roughness=.25, metallic=.1, emission=0):
    mat = bpy.data.materials.new(key)
    mat.use_nodes = True
    mat.diffuse_color = (*color, 1)
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*color, 1)
    shader.inputs['Metallic'].default_value = metallic
    shader.inputs['Roughness'].default_value = roughness
    shader.inputs['Emission Color'].default_value = (*color, 1)
    shader.inputs['Emission Strength'].default_value = emission
    model.MATERIALS[key] = mat


def spherical_uv(obj, center, vertical_axis=False):
    # Continuous paint over the curved shell, with the wrap seam on its rear.
    uv = obj.data.uv_layers.active.data
    for polygon in obj.data.polygons:
        coords = []
        for index in polygon.loop_indices:
            point = obj.data.vertices[obj.data.loops[index].vertex_index].co
            x,y,z = point.x,point.z-center,-point.y
            length = math.sqrt(x*x+y*y+z*z)
            u = math.atan2(z if vertical_axis else y,x)/tau+.5
            theta = math.acos(max(-1,min(1,(y if vertical_axis else z)/max(length,.00001))))
            coords.append([u,theta/(1.66 if vertical_axis else pi)])
        if max(p[0] for p in coords)-min(p[0] for p in coords) > .5:
            for p in coords:
                if p[0] < .5:
                    p[0] += 1
        for index,coord in zip(polygon.loop_indices,coords):
            uv[index].uv = coord


def spherical_housing(center, radius):
    # An actual open front aperture, with a closed rounded back.
    sectors, rows = 28, 14
    points, faces = [], []
    start = .57
    for j in range(rows):
        theta = start + (pi-start-.08)*j/(rows-1)
        for i in range(sectors):
            phi = tau*i/sectors
            points.append((radius*sin(theta)*cos(phi), center+radius*sin(theta)*sin(phi), radius*cos(theta)))
    for j in range(rows-1):
        for i in range(sectors):
            a = j*sectors+i
            b = j*sectors+(i+1)%sectors
            faces.append((a,b,b+sectors,a+sectors))
    points.append((0,center,-radius))
    for i in range(sectors):
        faces.append(((rows-1)*sectors+i,(rows-1)*sectors+(i+1)%sectors,len(points)-1))
    obj = mesh_part('Ivory spherical eye shell with open aperture', points, faces, 'tracker_ivory')
    spherical_uv(obj,center)


def helmet(center, radius):
    # Front rim arches above the lens; sides descend to the swivel, like the mockup.
    sectors, rows = 28, 8
    points, faces = [], []
    for layer in range(2):
        r = radius - layer*.006
        points.append((0,center+r,0))
        pole = len(points)-1
        for j in range(1, rows+1):
            for i in range(sectors):
                phi = tau*i/sectors
                limit = 1.63 - .46*max(0,sin(phi))**3
                theta = limit*j/rows
                brim = .008*max(0,sin(phi))**6*(j/rows)**5
                points.append((r*sin(theta)*cos(phi),center+r*cos(theta),r*sin(theta)*sin(phi)+brim))
        for i in range(sectors):
            faces.append((pole,pole+1+i,pole+1+(i+1)%sectors))
        for j in range(rows-1):
            for i in range(sectors):
                a = pole+1+j*sectors+i
                b = pole+1+j*sectors+(i+1)%sectors
                faces.append((a,b,b+sectors,a+sectors))
    offset = 1+rows*sectors
    for i in range(sectors):
        a = 1+(rows-1)*sectors+i
        b = 1+(rows-1)*sectors+(i+1)%sectors
        faces.append((a,b,b+offset,a+offset))
    obj = mesh_part('Ochre curved helmet and sculpted eyelid',points,faces,'tracker_ochre')
    spherical_uv(obj,center,True)


def convex_iris(center):
    # The turquoise iris is a curved annulus surrounding a dark convex pupil.
    points, faces = [], []
    segments = 32
    for r,z in [(.048,.099),(.043,.109),(.032,.115),(.022,.117)]:
        for i in range(segments):
            a = tau*i/segments
            points.append((r*cos(a),center+r*sin(a),z))
    for j in range(3):
        for i in range(segments):
            a = j*segments+i
            b = j*segments+(i+1)%segments
            faces.append((a,b,b+segments,a+segments))
    iris = mesh_part('Cyan curved iris with real central opening',points,faces,'tracker_iris')
    for polygon in iris.data.polygons:
        for index in polygon.loop_indices:
            point = iris.data.vertices[iris.data.loops[index].vertex_index].co
            iris.data.uv_layers.active.data[index].uv = (.5+point.x/.10,.5+(point.z-center)/.10)
    points = [(0,center,.121)]
    for j in range(1,4):
        r = .022*j/3
        z = .121-.004*(j/3)**2
        for i in range(segments):
            a = tau*i/segments
            points.append((r*cos(a),center+r*sin(a),z))
    faces = [(0,1+i,1+(i+1)%segments) for i in range(segments)]
    for j in range(2):
        for i in range(segments):
            a = 1+j*segments+i
            b = 1+j*segments+(i+1)%segments
            faces.append((a,b,b+segments,a+segments))
    mesh_part('Dark convex central pupil',points,faces,'tracker_pupil')
    # A deliberately authored glint reads at gameplay size, like the reference.
    turned('Small upper left lens glint',(-.011,center+.015,.121),.005,.0015,'tracker_glint',axis=(0,0,1),vertices=16,bevel=.0001)


def iris_texture():
    size, pixels = 256, []
    for y in range(size):
        for x in range(size):
            dx, dy = (x/(size-1)-.5)*.10, (y/(size-1)-.5)*.10
            r = math.hypot(dx,dy)
            edge = min(1,max(0,(.048-r)/.012))
            ray = .94+.06*sin(math.atan2(dy,dx)*37 + r*450)
            pixels.extend((.012*edge, (.13+.48*edge)*ray, (.17+.46*edge)*ray, 1))
    image = bpy.data.images.new('tracker_iris_radial_albedo',width=size,height=size)
    image.colorspace_settings.name = 'sRGB'
    image.pixels.foreach_set(pixels)
    image.filepath_raw = str(model.SOURCE/'tracker_iris_radial_albedo.png')
    image.file_format = 'PNG'
    image.save()
    image.pack()
    mat = model.MATERIALS['tracker_iris']
    texture = mat.node_tree.nodes.new('ShaderNodeTexImage')
    texture.image = image
    mat.node_tree.links.new(texture.outputs['Color'],mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])


def fork(center):
    # Extruded curved side cradle, joined to the stalk and lateral trunnion.
    outline = [(-.025,.042),(-.050,.039),(-.082,.067),(-.115,.124),(-.124,center-.012),
               (-.120,center+.022),(-.100,center+.030),(-.095,center-.012),(-.093,.125),(-.067,.089),(-.026,.077)]
    points = [(x,y,z) for z in (-.015,.015) for x,y in outline]
    n = len(outline)
    faces = [tuple(reversed(range(n))),tuple(range(n,2*n))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    mesh_part('Rounded ivory side cradle',points,faces,'tracker_ivory',.005,False)
    turned('Side pitch axle',(-.109,center,0),.032,.035,'edge',axis=(1,0,0))
    turned('Ivory swivel bearing',(-.132,center,0),.036,.011,'tracker_ivory',axis=(1,0,0))
    turned('Ochre circular trunnion cap',(-.140,center,0),.023,.010,'tracker_ochre',axis=(1,0,0),vertices=24)
    turned('Copper trunnion center',(-.147,center,0),.014,.006,'copper',axis=(1,0,0),vertices=20)


def build_tracker():
    previous_source = model.SOURCE
    previous_materials = model.MATERIALS.copy()
    model.SOURCE = model.DEST/'source'/'tracker-eye'
    model.SOURCE.mkdir(parents=True,exist_ok=True)
    model.begin('tracker')
    painted_material('tracker_ivory',(.74,.70,.60),.71,.05,True)
    painted_material('tracker_ochre',(.77,.46,.18),.68,.08,True)
    solid_material('tracker_iris',(.009,.27,.34),.23,.15,.18)
    iris_texture()
    solid_material('tracker_pupil',(.006,.026,.029),.12,.32)
    solid_material('tracker_glint',(.65,.93,.94),.22,0,.45)
    center, radius = .205, .112
    # Oval foot really seats on top of the shoulder, rather than a rear backplate.
    foot = turned('Oval shoulder foot',(0,.008,0),.044,.016,'tracker_ochre',vertices=28,bevel=.002)
    foot.scale.y = .74  # Blender Y is Godot depth.
    turned('Rubber mounting gasket',(0,.002,0),.040,.004,'rubber',vertices=24,bevel=.0004).scale.y = .74
    turned('Stalk yaw collar',(0,.024,0),.027,.023,'edge',vertices=24)
    box('Rounded adjustable stalk',(0,.049,0),(.063,.053,.058),'tracker_ochre',bevel=.009)
    turned('Stalk side pivot',(0,.050,.032),.018,.009,'edge',axis=(0,0,1),vertices=20)
    turned('Stalk pivot cap',(0,.050,.039),.012,.006,'tracker_ivory',axis=(0,0,1),vertices=20)
    fork(center)
    spherical_housing(center,radius)
    helmet(center,radius+.005)
    collar('Recessed dark circular optical bezel',(0,center,.096),.061,.047,.017,'edge',segments=32)
    collar('Ivory inner lens lip',(0,center,.108),.050,.046,.006,'tracker_ivory',segments=32)
    convex_iris(center)
    pipe('One thick protected loop cable',[(-.112,center-.034,-.016),(-.122,.115,-.044),(-.081,.078,-.046),(-.044,.051,-.017)],.007,'rubber')
    turned('Cable inlet ferrule',(-.045,.051,-.017),.010,.018,'copper',axis=(1,0,0),vertices=16)
    model.ROOT.scale = (1.10,1.10,1.10)
    # Single chamfers on small parts keep the complete kit below 30k triangles.
    model.export('tracker')
    record_path = model.DEST/'tracker.asset.json'
    record = json.loads(record_path.read_text(encoding='utf-8'))
    record.update(source='source/tracker-eye/tracker.blend',
                  design='Approved shoulder-mounted spherical eye: ochre helmet brow, ivory shell, recessed cyan annular iris, dark convex pupil and glint, lateral swivel cradle, short adjustable stalk, oval foot and one thick cable.',
                  reference='captures/module-identity-concepts/traqueur-sur-vrai-robot-v1.png',
                  mounting_origin='Underside of oval foot, local Y up, eye faces +Z.')
    record_path.write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    model.SOURCE = previous_source
    model.MATERIALS.clear()
    model.MATERIALS.update(previous_materials)


if __name__ == '__main__':
    build_tracker()
