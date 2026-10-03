"""Four authored armour inserts, using the garage's established PBR recipe.

Run with Blender --background --python tools/build_four_active_module_models.py.
Editable components and textures are isolated from all previous model sources.
"""
from pathlib import Path
from math import sin, cos, pi
import json
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import module_modeling as model
from module_modeling import bpy, v, finish, box, cylinder, ring, arc, pipe
from build_fulguro_static_models import contour, loft, saddle, fastener

model.SOURCE = model.DEST / 'source' / 'four-active'


def export(identifier, description):
    model.export(identifier)
    path = model.DEST / (identifier + '.asset.json')
    record = json.loads(path.read_text())
    record['source'] = 'source/four-active/' + identifier + '.blend'
    record['design'] = description
    path.write_text(json.dumps(record, indent=2) + '\n')


def winding(name, center, radius, height, turns, tube=.0017, handedness=1):
    """Closed copper helix with explicit cross sections and bounded triangles."""
    from mathutils import Vector
    segments = int(turns * 16)
    sides = 6
    vertices, faces = [], []
    for index in range(segments + 1):
        theta = handedness * index * turns * 2 * pi / segments
        radial = Vector((cos(theta), 0, sin(theta)))
        tangent = Vector((-radius*sin(theta), height/(handedness*turns*2*pi), radius*cos(theta))).normalized()
        second = tangent.cross(radial).normalized()
        point = Vector(center) + Vector((radius*cos(theta), -height/2 + height*index/segments, radius*sin(theta)))
        for side in range(sides):
            angle = side * 2*pi/sides
            vertices.append(v(point + tube*(radial*cos(angle) + second*sin(angle))))
    for index in range(segments):
        for side in range(sides):
            a = index*sides + side
            b = index*sides + (side+1) % sides
            faces.append((a,b,b+sides,a+sides))
    faces.extend((tuple(reversed(range(sides))), tuple(segments*sides+i for i in range(sides))))
    mesh = bpy.data.meshes.new(name + '_mesh')
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    finish(obj, name, 'copper')
    for face in mesh.polygons:
        face.use_smooth = len(face.vertices) == 4
    return obj


def build_pelto():
    """Ground-wave driver: segmented impact shoe and a exposed double ram."""
    model.begin('pelto_smash')
    saddle(.112, .162)
    outline = [(-.050,-.100),(.050,-.100),(.085,-.060),(.081,.066),
               (.050,.106),(-.050,.106),(-.081,.067),(-.085,-.060)]
    loft('seismic_driver_backbone',[(.000,outline),(.021,[(x*.96,y*.96) for x,y in outline])],'steel',.002)
    box('recessed_pressure_chamber',(0,-.023,.024),(.082,.110,.006),'rubber',bevel=.001)
    for side in (-1,1):
        cheek = [(side*x,y) for x,y in [(.048,-.076),(.069,-.079),(.080,-.054),
                 (.076,.054),(.058,.069),(.044,.056),(.049,.027),(.046,-.046)]]
        loft('ceramic_ram_guard_'+str(side),[(.012,cheek),(.044,[(x-side*.003,y) for x,y in cheek])],'ivory',.0018)
        box('ochre_ram_guard_inlay_'+str(side),(side*.065,-.011,.045),(.003,.057,.002),'paint',bevel=.0004)
        cylinder('pressure_ram_body_'+str(side),(side*.025,-.052,.032),.009,.046,'edge',vertices=16,bevel=.0008)
        cylinder('polished_seismic_ram_'+str(side),(side*.025,.014,.032),.0048,.086,'edge',vertices=16,bevel=.0004)
        for y in (-.028,.052):
            ring('ram_copper_seal_'+str(side),(side*.025,y,.032),.011,.0048,.006,'copper',axis=(0,1,0),segments=20)
        pipe('hydraulic_return_line_'+str(side),[(side*.032,-.081,.026),(side*.045,-.071,.028),
             (side*.045,.036,.028),(side*.032,.048,.033)],.002,'rubber')
        fastener('shoe_attachment_'+str(side),side*.060,.077,.051)
        for row in range(4):
            box('open_heat_sink_slot_'+str(side),(side*.076,-.050+row*.012,.030),(.012,.004,.007),'rubber',bevel=.0005)
    # A broad lower shoe and three individually chamfered contact teeth.
    shoe = contour(.148,.047,.013,(0,.079))
    loft('floating_impact_shoe',[(.027,shoe),(.047,[(x*.93,y) for x,y in shoe])],'paint',.0016)
    for index,x in enumerate((-.043,0,.043)):
        tooth = contour(.038,.041,.006,(x,.083))
        loft('ceramic_contact_tooth_%d'%index,[(.047,tooth),(.056,[(x2,y*.97) for x2,y in tooth])],'ivory',.001)
        box('contact_tooth_groove_%d'%index,(x,.083,.057),(.021,.0024,.001),'rubber',bevel=.0003)
    box('central_sensor_bezel',(0,-.069,.036),(.021,.024,.008),'steel',bevel=.0012)
    box('recessed_amber_sensor',(0,-.069,.0405),(.006,.014,.0015),'amber',bevel=.0005)
    for row in range(4):
        box('pressure_manifold_fin',(0,-.027+row*.009,.037),(.030,.0032,.014),'copper',bevel=.0006)
    export('pelto_smash','Compact right forearm seismic driver with a segmented impact shoe, paired exposed hydraulic rams, hollow copper seals, cooling fins and protected return lines.')


def build_counter():
    """Interceptor capacitor protected by three overlapping angular vanes."""
    model.begin('counter')
    saddle(.102,.159)
    outline = [(-.047,-.104),(.037,-.104),(.077,-.064),(.078,.058),
               (.035,.103),(-.050,.087),(-.079,.033),(-.076,-.053)]
    loft('interceptor_wedge_backbone',[(.000,outline),(.025,[(x*.92,y*.98) for x,y in outline])],'steel',.0018)
    box('recessed_counter_capacitor',(0,-.005,.025),(.058,.112,.010),'rubber',bevel=.0012)
    cylinder('central_surcharge_cell',(0,-.005,.033),.013,.112,'copper',vertices=20,bevel=.0006)
    for y in (-.044,.034):
        ring('ceramic_capacitor_isolator',(0,y,.033),.017,.012,.012,'ivory',axis=(0,1,0),segments=20)
    # Each vane has its own lip, open separation and an undercut copper contact.
    for index,y in enumerate((-.066,-.008,.050)):
        outline = [(-.066,y-.007),(-.036,y-.026),(.012,y-.029),(.065,y-.007),
                   (.068,y+.019),(.012,y+.004),(-.031,y+.005),(-.067,y+.021)]
        front = .047 + index*.002
        loft('angled_ceramic_interceptor_vane_%d'%index,[(.030,outline),(front,[(x*.97,y2) for x,y2 in outline])],'ivory',.0014)
        pipe('vane_copper_pickup_%d'%index,[(-.054,y-.010,front+.001),(-.030,y-.022,front+.001),
             (.012,y-.024,front+.001),(.054,y-.007,front+.001)],.0013,'copper')
        fastener('vane_retainer_%d'%index,-.048,y+.009,front+.001)
    for side in (-1,1):
        box('surcharge_status_aperture_'+str(side),(side*.068,-.003,.029),(.008,.028,.008),'rubber',bevel=.0007)
        box('cyan_surcharge_indicator_'+str(side),(side*.068,-.003,.034),(.0022,.020,.0012),'cyan',bevel=.0003)
    lower = contour(.054,.017,.004,(.006,-.092))
    loft('counter_service_latch',[(.022,lower),(.035,lower)],'edge',.0008)
    box('ochre_latch_key',(.006,-.092,.036),(.031,.003,.002),'paint',bevel=.0004)
    for index in range(4):
        box('interceptor_edge_vent',(.074,-.045+index*.011,.019),(.008,.003,.007),'rubber',bevel=.0004)
    export('counter','Compact angular forearm interception capacitor with three separated ceramic vanes, copper pickup traces, central surcharge cell and recessed cyan indicators.')


def build_permutation():
    """Two linked phase inductors: a paired exchange mechanism on the torso."""
    model.begin('permutation')
    saddle(.079,.141)
    outline = contour(.105,.177,.018)
    loft('paired_phase_exchange_backbone',[(.000,outline),(.017,[(x*.95,y*.98) for x,y in outline])],'steel',.0015)
    for side in (-1,1):
        x = side*.027
        box('phase_channel_recess_'+str(side),(x,0,.019),(.036,.124,.006),'rubber',bevel=.001)
        cylinder('phase_inductor_core_'+str(side),(x,0,.027),.007,.112,'edge',vertices=16,bevel=.0005)
        winding('counterwound_copper_inductor_'+str(side),(x,0,.027),.011,.079,4.5,tube=.0018,handedness=side)
        for y in (-.059,.059):
            ring('hollow_ceramic_phase_seat',(x,y,.027),.016,.009,.013,'ivory',axis=(0,1,0),segments=20)
            cylinder('phase_seat_end_contact',(x,y*1.08,.027),.007,.005,'edge',vertices=16,bevel=.0005)
        box('phase_status_slit_'+str(side),(x,-.013*side,.040),(.0025,.020,.0015),'cyan',bevel=.0003)
        cheek = [(side*x2,y) for x2,y in [(.044,-.073),(.052,-.054),(.052,.055),
                 (.043,.073),(.036,.060),(.039,.035),(.038,-.045)]]
        loft('swept_ceramic_phase_guard_'+str(side),[(.012,cheek),(.038,[(x2-side*.0015,y) for x2,y in cheek])],'ivory',.0013)
        fastener('phase_guard_fastener_'+str(side),side*.043,-.061,.038)
    # Two diagonally opposed exchange busbars connect the real coil endpoints.
    pipe('upper_phase_exchange_bus',[(-.027,.063,.027),(-.016,.080,.028),(.012,.080,.028),(.027,.063,.027)],.0022,'copper')
    pipe('lower_phase_exchange_bus',[(.027,-.063,.027),(.016,-.080,.028),(-.012,-.080,.028),(-.027,-.063,.027)],.0022,'copper')
    box('central_exchange_bridge',(0,0,.029),(.017,.023,.022),'ivory',bevel=.0012)
    for side in (-1,1):
        box('bridge_port_seam',(side*.006,side*.004,.041),(.0032,.014,.001),'rubber',bevel=.0003)
        box('bridge_port_status',(side*.006,side*.004,.042),(.0013,.009,.001),'cyan',bevel=.0002)
    box('ochre_upper_phase_key',(0,.082,.035),(.025,.005,.004),'paint',bevel=.0007)
    export('permutation','Compact torso phase exchanger with two true copper helices, hollow ceramic seats, paired status ports, swept guards and connected exchange busbars.')


def build_eclipse():
    """Occlusion iris: dark segmented lens under a swept ceramic crescent."""
    model.begin('eclipse')
    saddle(.078,.142)
    outline = [(-.031,-.089),(.029,-.089),(.051,-.054),(.052,.052),
               (.025,.088),(-.032,.084),(-.053,.043),(-.052,-.046)]
    loft('occlusion_iris_backbone',[(.000,outline),(.019,[(x*.93,y*.98) for x,y in outline])],'steel',.0015)
    center = (0,.006)
    ring('dark_iris_machined_rim',(*center,.029),.044,.036,.009,'edge',segments=32)
    cylinder('opaque_occlusion_lens',(*center,.025),.035,.012,'rubber',axis=(0,0,1),vertices=32,bevel=.0012)
    # Eight separated iris blades are opaque geometry over the deep lens.
    blade = [(.004,.003),(.014,.026),(.028,.031),(.031,.016),(.019,.004)]
    for index in range(8):
        angle = index*2*pi/8
        outline = [(x*cos(angle)-y*sin(angle),.006+x*sin(angle)+y*cos(angle)) for x,y in blade]
        loft('radial_occlusion_blade_%d'%index,[(.031,outline),(.033,outline)],'steel',.0004)
    cylinder('iris_dark_center',(*center,.0335),.0075,.003,'rubber',axis=(0,0,1),vertices=20,bevel=.0003)
    arc('thin_amber_half_light',(*center,.035),.039,.037,.002,'amber',-.65*pi,.35*pi,segments=28)
    arc('copper_occluder_pickup',(*center,.036),.043,.041,.002,'copper',.40*pi,1.20*pi,segments=20)
    # A swept crescent partly shrouds the upper lens; an open lower fork balances it.
    crescent = [(-.046,.029),(-.039,.063),(-.017,.086),(.020,.080),(.045,.052),
                (.047,.017),(.035,.028),(.025,.051),(-.001,.061),(-.025,.051),(-.034,.026)]
    loft('swept_ceramic_eclipse_crescent',[(.014,crescent),(.042,[(x*.96,y*.98) for x,y in crescent])],'ivory',.0014)
    lower = [(-.046,-.032),(-.034,-.076),(-.017,-.088),(.029,-.081),(.047,-.044),
             (.035,-.032),(.024,-.055),(.003,-.062),(-.021,-.050),(-.032,-.026)]
    loft('open_ceramic_lower_fork',[(.013,lower),(.037,[(x*.97,y) for x,y in lower])],'ivory',.0013)
    for side in (-1,1):
        fastener('occlusion_guard_socket_'+str(side),side*.028,side*.061,.042 if side>0 else .037)
        for row in range(3):
            box('phase_dissipation_vent',(side*.046,-.023+row*.010,.021),(.011,.003,.006),'rubber',bevel=.0004)
    box('lower_occlusion_service_key',(.007,-.075,.038),(.022,.004,.002),'paint',bevel=.0004)
    box('crescent_ochre_inlay',(.001,.074,.043),(.024,.003,.0015),'paint',bevel=.0003,rotation=(0,0,-.18))
    export('eclipse','Compact torso occlusion emitter with an opaque lens, eight modelled iris blades, restrained half-ring amber light, swept ceramic crescent and open lower fork.')


if __name__ == '__main__':
    selected = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    for identifier, build in [('pelto_smash',build_pelto),('counter',build_counter),
                              ('permutation',build_permutation),('eclipse',build_eclipse)]:
        if not selected or identifier in selected:
            build()
