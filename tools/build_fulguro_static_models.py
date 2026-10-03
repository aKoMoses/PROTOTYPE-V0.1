"""Two compact armour inserts, using the existing locally authored PBR recipe.

Run with Blender --background --python tools/build_fulguro_static_models.py.
Coordinates are reference metres, Y up, +Z outward from the armour surface.
The editable parts and textures live in their own source directory.
"""
from pathlib import Path
from math import sin, cos, pi
import json
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bmesh
import module_modeling as model
from module_modeling import bpy, v, box, cylinder, ring, arc, pipe, material, finish

model.SOURCE = model.DEST / 'source' / 'fulguro-static'


def contour(width, height, cut, center=(0, 0)):
    x, y = width / 2, height / 2
    ox, oy = center
    return [(ox-x+cut, oy-y), (ox+x-cut, oy-y), (ox+x, oy-y+cut),
            (ox+x, oy+y-cut), (ox+x-cut, oy+y), (ox-x+cut, oy+y),
            (ox-x, oy+y-cut), (ox-x, oy-y+cut)]


def loft(name, sections, mat, bevel=.0012):
    count = len(sections[0][1])
    vertices = [v((x, y, z)) for z, outline in sections for x, y in outline]
    faces = [tuple(reversed(range(count)))]
    for level in range(len(sections)-1):
        for i in range(count):
            j = (i+1) % count
            a, b = level*count, (level+1)*count
            faces.append((a+i, a+j, b+j, b+i))
    faces.append(tuple((len(sections)-1)*count+i for i in range(count)))
    mesh = bpy.data.meshes.new(name + '_mesh')
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return finish(obj, name, mat, bevel)


def fastener(name, x, y, z):
    cylinder(name, (x, y, z), .0032, .0024, 'edge',
             axis=(0, 0, 1), vertices=6, bevel=.00035)
    cylinder(name + '_recess', (x, y, z+.0013), .00145, .00035,
             'rubber', axis=(0, 0, 1), vertices=6, bevel=0)


def saddle(width, height):
    outline = contour(width, height, .013)
    # Recess the corners into convex armour; the working shell starts at Z=0.
    back = [(x, y) for x, y in outline]
    loft('recessed_conforming_saddle', [(-.006, back), (.001, back)],
         'steel', .0007)
    for y in (-height*.32, height*.32):
        box('rubber_mounting_gasket', (0, y, -.001),
            (width*.78, .009, .004), 'rubber', bevel=.0006)


def export(identifier, description):
    model.export(identifier)
    path = model.DEST / (identifier + '.asset.json')
    record = json.loads(path.read_text())
    record['source'] = 'source/fulguro-static/' + identifier + '.blend'
    record['design'] = description
    path.write_text(json.dumps(record, indent=2) + '\n')


def build_fulguro():
    """Forearm punch accelerator: segmented impact crown and hydraulic rails."""
    model.begin('fulguro_punch')
    saddle(.105, .171)
    outline = [(-.045,-.106), (.045,-.106), (.069,-.076), (.072,.063),
               (.053,.102), (-.048,.109), (-.073,.075), (-.070,-.072)]
    loft('tapered_accelerator_backbone', [(.000, outline),
         (.020, [(x*.91, y*.98) for x,y in outline])], 'steel', .002)
    # The two ceramic cheeks leave a real open channel for the metal workings.
    for side in (-1, 1):
        cheek = [(side*x,y) for x,y in [(.033,-.094),(.051,-.095),
                 (.065,-.071),(.064,.068),(.049,.093),(.035,.085),
                 (.028,.058),(.030,-.067)]]
        loft('ceramic_side_guard_' + str(side), [(.014, cheek),
             (.040, [(x-side*.003,y) for x,y in cheek])], 'ivory', .0018)
        box('ochre_inlaid_rail_' + str(side), (side*.053,-.010,.041),
            (.0032,.097,.0018), 'paint', bevel=.0004)
        # Nested sleeve, polished rod and end collars, with air around the rod.
        cylinder('hydraulic_barrel_' + str(side), (side*.027,-.057,.029),
                 .006,.052,'steel',vertices=16,bevel=.0008)
        cylinder('exposed_piston_rod_' + str(side), (side*.027,-.010,.029),
                 .0036,.045,'edge',vertices=12,bevel=.0003)
        for y in (-.030,.015):
            cylinder('piston_retaining_collar', (side*.027,y,.029),
                     .007,.006,'copper',vertices=16,bevel=.0005)
        fastener('cheek_retainer_' + str(side),side*.049,-.078,.041)
        pipe('protected_pressure_line_' + str(side),
             [(side*.035,-.079,.020),(side*.041,-.048,.019),
              (side*.040,.012,.020),(side*.035,.036,.027)],.0018,'rubber')
    loft('recessed_thermal_well', [(.019,contour(.044,.095,.008,(0,-.013))),
         (.024,contour(.040,.091,.006,(0,-.013)))], 'rubber', .0006)
    for index in range(7):
        y = -.049+index*.011
        box('machined_heat_fin_%02d'%index,(0,y,.032),
            (.033,.0032,.017),'copper',bevel=.00045)
        box('restrained_amber_heat_gap_%02d'%index,(0,y+.004,.025),
            (.023,.0017,.0013),'amber',bevel=.0002)
    crown = [(-.049,.029),(.049,.029),(.063,.057),(.047,.103),
             (.020,.110),(-.020,.110),(-.054,.098),(-.063,.055)]
    loft('floating_impact_crown', [(.025,crown),
         (.048,[(x*.92,y-.002) for x,y in crown])], 'ivory', .0018)
    # Three impact shoes, separated by dark seams rather than painted lines.
    for index,x in enumerate((-.032,0,.032)):
        outline = contour(.027,.032,.005,(x,.077))
        loft('impact_shoe_%d'%index,[(.047,outline),
             (.053,[(xx,yy-.002) for xx,yy in outline])],'edge',.0008)
        box('impact_shoe_ochre_mark_%d'%index,(x,.066,.054),
            (.012,.002,.001),'paint',bevel=.0002)
    loft('lower_quick_release_cover',[(.020,contour(.074,.027,.007,(0,-.090))),
         (.036,contour(.066,.021,.005,(0,-.090)))],'ivory',.001)
    box('release_tab_recess',(0,-.091,.037),(.025,.006,.002),
        'rubber',bevel=.0005)
    box('release_tab',(0,-.091,.0385),(.016,.0025,.0015),
        'edge',bevel=.0003)
    fastener('upper_crown_retainer',0,.039,.049)
    export('fulguro_punch','Compact right forearm accelerator, real piston clearances, '
           'three impact shoes, copper heat fins and restrained amber apertures.')


def build_static():
    """A compact three-sector stasis emitter, rather than another coil brace."""
    model.begin('static_shield')
    saddle(.092,.144)
    outline = [(-.050,-.093),(.037,-.093),(.069,-.062),(.075,.008),
               (.048,.080),(-.005,.099),(-.053,.074),(-.075,.011)]
    loft('shield_emitter_armour_seat',[(.000,outline),
         (.018,[(x*.93,y*.96) for x,y in outline])],'steel',.002)
    ring('recessed_emitter_socket',(0,.004,.022),.049,.034,.014,'rubber',segments=36)
    ring('machined_emitter_inner_lip',(0,.004,.029),.037,.028,.012,'edge',segments=36)
    cylinder('opaque_stasis_core',(0,.004,.029),.028,.009,'steel',
             axis=(0,0,1),vertices=36,bevel=.0008)
    # Concentric emitter traces remain tucked into the protective annulus.
    for index in range(3):
        angle = pi/2 + index*2*pi/3
        arc('cyan_stasis_segment_%d'%index,(0,.004,.035),.026,.023,.002,
            'cyan',angle-.83,angle+.83,segments=14)
        arc('copper_sector_busbar_%d'%index,(0,.004,.027),.046,.043,.003,
            'copper',angle-.73,angle+.73,segments=14)
        # The ceramic shrouds are distinct lobes; the gaps expose the busbars.
        points=[]
        for step in range(6):
            a=angle-.73+1.46*step/5
            points.append((cos(a)*.066,.004+sin(a)*.078))
        for step in range(5,-1,-1):
            a=angle-.73+1.46*step/5
            points.append((cos(a)*.049,.004+sin(a)*.049))
        loft('ceramic_sector_shroud_%d'%index,[(.018,points),
             (.043,[(x*.95,.004+(y-.004)*.98) for x,y in points])],
             'ivory',.0014)
        x,y=cos(angle)*.057,.004+sin(angle)*.063
        fastener('sector_shroud_lock_%d'%index,x,y,.044)
        # An edge visible through each of the three interruptions in the shell.
        end=angle+.86
        box('recessed_sector_contact_%d'%index,
            (cos(end)*.046,.004+sin(end)*.046,.032),
            (.006,.012,.004),'copper',bevel=.0005,rotation=(0,0,end-pi/2))
    # Small central ceramic iris with a cyan slit, no transparent shader layer.
    iris=[(-.007,-.010),(.012,-.006),(.010,.010),(-.004,.017),(-.015,.008),(-.014,-.004)]
    loft('central_stasis_iris',[(.034,iris),(.040,[(x*.83,y*.83) for x,y in iris])],
         'ivory',.0007)
    box('iris_recess',(-.001,.003,.041),(.004,.015,.0018),'rubber',bevel=.0004)
    box('iris_status_slit',(-.001,.003,.042),(.0015,.011,.001),'cyan',bevel=.0002)
    lower=[(-.038,-.088),(.034,-.088),(.045,-.072),(.035,-.057),
           (.018,-.054),(-.018,-.056),(-.047,-.070),(-.046,-.077)]
    loft('lower_service_latch',[(.016,lower),(.033,[(x*.93,y) for x,y in lower])],
         'ivory',.0012)
    box('service_latch_dark_seam',(0,-.073,.034),(.024,.006,.002),'rubber',bevel=.0004)
    box('service_latch_ochre_key',(0,-.073,.0355),(.013,.0028,.0015),'paint',bevel=.0003)
    for side in (-1,1):
        for index in range(3):
            box('ventilation_notch',(side*.063,-.034+index*.009,.019),
                (.015,.003,.008),'rubber',bevel=.0004)
    export('static_shield','Compact left forearm stasis emitter with three ceramic '
           'sectors, recessed copper busbars, machined aperture and opaque cyan iris.')


if __name__ == '__main__':
    build_fulguro()
    build_static()
