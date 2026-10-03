"""Authored Javelin and Projector armour inserts; no external assets/providers."""
from pathlib import Path
from math import cos, sin, pi
import json
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import module_modeling as model
from module_modeling import bpy, v, finish, box, cylinder, ring, arc, pipe
from build_fulguro_static_models import contour, loft, saddle, fastener

model.SOURCE = model.DEST / 'source' / 'javelin-projector'


def export(identifier, description):
    model.export(identifier)
    path = model.DEST / (identifier + '.asset.json')
    record = json.loads(path.read_text())
    record['source'] = 'source/javelin-projector/' + identifier + '.blend'
    record['design'] = description
    path.write_text(json.dumps(record, indent=2) + '\n')


def build_javelin():
    """Three exposed induction rails in a tapered upper-arm launch cassette."""
    model.begin('javelin')
    saddle(.096, .169)
    outline = [(-.054,-.105),(.047,-.105),(.073,-.078),(.077,.055),
               (.054,.094),(-.051,.102),(-.077,.068),(-.076,-.074)]
    loft('tapered_trident_carrier',[(.000,outline),
         (.020,[(x*.94,y*.97) for x,y in outline])],'steel',.0018)
    for side in (-1,1):
        cheek=[(side*x,y) for x,y in [(.049,-.081),(.065,-.088),
               (.074,-.067),(.073,.056),(.056,.090),(.046,.077),
               (.052,.048),(.049,-.050)]]
        loft('swept_ceramic_rail_guard_'+str(side),[(.010,cheek),
             (.037,[(x-side*.002,y) for x,y in cheek])],'ivory',.0014)
        box('ochre_guard_inlay_'+str(side),(side*.065,-.012,.038),
            (.0028,.074,.0015),'paint',bevel=.00035)
        fastener('guard_retaining_socket_'+str(side),side*.061,-.066,.038)
    loft('recessed_three_rail_well',[(.020,contour(.096,.136,.014,(0,.003))),
         (.024,contour(.090,.133,.012,(0,.003)))],'rubber',.0008)
    # Separate induction rails, each with real sleeves and a pointed electrode.
    for index,x in enumerate((-.032,0,.032)):
        length=.124 if index==1 else .104
        top=.098 if index==1 else .083
        box('induction_rail_bed_%d'%index,(x,-.006,.026),
            (.022,length,.007),'edge',bevel=.001)
        cylinder('copper_induction_rail_%d'%index,(x,(top-.084)/2,.033),
                 .0045,top+.028,'copper',vertices=16,bevel=.0006)
        ring('electrode_retaining_ferrule_%d'%index,(x,top-.028,.033),
             .008,.0044,.006,'edge',axis=(0,1,0),segments=16)
        for row,y in enumerate((-.046,.035)):
            ring('ceramic_isolator_%d_%d'%(index,row),(x,y,.032),
                 .009,.005,.011,'ivory',axis=(0,1,0),segments=16)
        cylinder('rail_tapered_electrode_%d'%index,(x,top-.016,.033),
                 .007,.024,'edge',vertices=12,radius_top=.002,bevel=.0003)
        cylinder('trident_tip_%d'%index,(x,top,.033),
                 .0028,.012,'cyan',vertices=12,radius_top=.0007,bevel=0)
        box('recessed_cyan_rail_trace_%d'%index,(x+.009,-.004,.031),
            (.0016,.067,.0018),'cyan',bevel=.0002)
        box('lower_rail_terminal_%d'%index,(x,-.068,.032),
            (.019,.014,.016),'steel',bevel=.001)
    # Open induction clearances remain visible below the ceramic bridge.
    bridge=[(-.060,-.096),(.056,-.098),(.066,-.078),(.049,-.063),
            (.020,-.065),(-.035,-.065),(-.064,-.076),(-.068,-.088)]
    loft('keyed_lower_ceramic_bridge',[(.017,bridge),
         (.045,[(x*.93,y+.001) for x,y in bridge])],'ivory',.0015)
    box('bridge_recessed_service_latch',(0,-.083,.0455),
        (.038,.009,.002),'rubber',bevel=.0005)
    box('bridge_ochre_latch',(0,-.083,.047),
        (.025,.003,.0015),'paint',bevel=.0003)
    for side in (-1,1):
        for row in range(3):
            box('lateral_thermal_vent',(side*.074,-.037+row*.013,.019),
                (.009,.004,.012),'rubber',bevel=.0004)
    export('javelin','Compact upper-arm trident launch cassette, three separate '
           'copper induction rails, hollow ceramic isolators, tapered cyan electrodes '
           'and swept armour cheeks.')


def dish(name, center, profile, material):
    """A real concave diaphragm of revolved rings; front-facing open mouth."""
    segments=40
    vertices=[]
    for radius,z in profile:
        for index in range(segments):
            angle=index*2*pi/segments
            vertices.append(v((center[0]+cos(angle)*radius,
                               center[1]+sin(angle)*radius,z)))
    faces=[]
    for layer in range(len(profile)-1):
        for index in range(segments):
            j=(index+1)%segments
            a,b=layer*segments,(layer+1)*segments
            faces.append((a+index,b+index,b+j,a+j))
    mesh=bpy.data.meshes.new(name+'_mesh')
    mesh.from_pydata(vertices,[],faces)
    mesh.update()
    obj=bpy.data.objects.new(name,mesh)
    bpy.context.scene.collection.objects.link(obj)
    finish(obj,name,material,0)
    for face in mesh.polygons:
        face.use_smooth=True
    return obj


def build_projector():
    """Recessed repulsion diaphragm with two ceramic shutters and a metal grille."""
    model.begin('projector')
    saddle(.096,.162)
    outline=[(-.047,-.103),(.045,-.103),(.077,-.067),(.080,.035),
             (.054,.087),(.025,.104),(-.045,.097),(-.081,.043)]
    loft('repulsion_diaphragm_backbone',[(.000,outline),
         (.023,[(x*.92,y*.97) for x,y in outline])],'steel',.0018)
    ring('open_pressure_aperture_rim',(0,.003,.036),.056,.049,.012,
         'edge',segments=40)
    # The depression and its inner rings are geometry, not a painted dark disk.
    dish('concave_repulsion_membrane',(0,.003),
         [(.007,.027),(.017,.026),(.027,.028),(.037,.034),(.045,.041),
          (.049,.045),(.052,.043),(.052,.034),(.046,.030),(.029,.021),
          (.008,.020),(.007,.027)],'steel')
    for index,radius in enumerate((.023,.034,.043)):
        ring('concentric_copper_membrane_trace_%d'%index,(0,.003,.028+index*.006),
             radius,radius-.0015,.0016,'copper',segments=32)
    cylinder('central_pressure_boss',(0,.003,.029),.009,.013,'edge',
             axis=(0,0,1),vertices=24,bevel=.0008)
    ring('small_cyan_pressure_indicator',(0,.003,.036),.008,.0055,.0015,
         'cyan',segments=24)
    # Two asymmetric ceramic shutters distinguish this from Static's sectors.
    upper=[(-.066,.045),(-.051,.081),(-.016,.101),(.024,.096),
           (.059,.070),(.066,.046),(.046,.036),(.030,.062),
           (-.004,.069),(-.033,.059)]
    lower=[(-.066,-.039),(-.048,-.091),(-.019,-.102),(.030,-.098),
           (.059,-.070),(.068,-.039),(.051,-.027),(.032,-.058),
           (-.004,-.067),(-.036,-.052)]
    for name,outline in [('upper',upper),('lower',lower)]:
        loft('swept_ceramic_shutter_'+name,[(.014,outline),
             (.052,[(x*.96,y*.98) for x,y in outline])],'ivory',.0018)
    # Three raised protective struts leave open gaps over the deep membrane.
    for index,x in enumerate((-.023,0,.023)):
        length=.073 if index==1 else .064
        box('arched_diaphragm_guard_%d'%index,(x,.003,.053),
            (.0045,length,.0045),'edge',bevel=.0007)
        for side in (-1,1):
            box('guard_standoff_%d_%d'%(index,side),
                (x,.003+side*length*.48,.045),(.006,.006,.016),
                'steel',bevel=.0007)
    for side in (-1,1):
        box('protected_cyan_side_aperture_'+str(side),(side*.068,.003,.033),
            (.007,.038,.008),'rubber',bevel=.0008)
        box('cyan_side_status_slit_'+str(side),(side*.068,.003,.038),
            (.0022,.026,.0015),'cyan',bevel=.0003)
        fastener('shutter_mount_'+str(side),side*.037,side*.075,.052)
    box('upper_ochre_inlay',(-.010,.087,.053),(.030,.0025,.0015),
        'paint',bevel=.0003,rotation=(0,0,-.12))
    box('lower_service_release',(0,-.085,.053),(.025,.008,.003),
        'rubber',bevel=.0006)
    box('lower_service_release_key',(0,-.085,.055),(.015,.003,.0015),
        'edge',bevel=.0003)
    export('projector','Compact forearm repulsion emitter, true concave metal '
           'diaphragm, concentric copper traces, open protective grille, two '
           'ceramic shutters and restrained cyan side apertures.')


if __name__=='__main__':
    build_javelin()
    build_projector()
