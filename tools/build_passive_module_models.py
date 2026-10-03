"""Five authored passive inserts, sharing the established garage PBR surfaces.

Blender --background --python tools/build_passive_module_models.py [-- id ...]
Each editable source keeps its individual mechanical parts; runtime batches
are joined by material. Local metres, Y up, outward mounting normal +Z.
"""
from pathlib import Path
from math import pi, sin, cos
import json
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import module_modeling as model
from module_modeling import box, cylinder as model_cylinder, ring as model_ring, arc, pipe
from build_fulguro_static_models import contour, loft, saddle, fastener

model.SOURCE = model.DEST / 'source' / 'passives'


def cylinder(*args, **kwargs):
    obj = model_cylinder(*args, **kwargs)
    # One chamfer on small turned parts; retain smooth radial shading.
    for modifier in obj.modifiers:
        if modifier.type == 'BEVEL':
            modifier.segments = 1
    return obj


def ring(*args, **kwargs):
    obj = model_ring(*args, **kwargs)
    for modifier in obj.modifiers:
        if modifier.type == 'BEVEL':
            modifier.segments = 1
    return obj


def export(identifier, description):
    for obj in model.bpy.context.scene.objects:
        for modifier in obj.modifiers:
            if modifier.type == 'BEVEL' and modifier.width <= .0006:
                modifier.segments = 1
    model.export(identifier)
    path = model.DEST / (identifier + '.asset.json')
    record = json.loads(path.read_text())
    record['source'] = 'source/passives/' + identifier + '.blend'
    record['design'] = description
    path.write_text(json.dumps(record, indent=2) + '\n')


def base(width=.142, height=.204):
    saddle(width*.78, height*.80)
    outline = contour(width, height, .014)
    loft('machined_passive_backplate', [(0, outline), (.015, [(x*.97,y*.98) for x,y in outline])], 'steel', .0014)
    box('isolated_inner_tray', (0,0,.016), (width*.79,height*.79,.006), 'rubber', bevel=.001)
    for side in (-1,1):
        for end in (-1,1):
            fastener('captive_backplate_fastener', side*(width/2-.014), end*(height/2-.021), .023)


def build_baroud():
    """Emergency reserve: protected red cell, charge bars, latched cutoff."""
    model.begin('baroud')
    base(.147,.208)
    core = contour(.076,.144,.015)
    loft('emergency_reserve_cartridge', [(.019,core),(.044,[(x*.94,y*.94) for x,y in core])], 'red', .002)
    box('reserve_label_inset',(0,.033,.045),(.047,.039,.002),'rubber',bevel=.0006)
    for index in range(3):
        box('reserve_charge_window',(0,.020+index*.011,.0465),(.036,.005,.0018),'amber',bevel=.0004)
    for side in (-1,1):
        cheek = [(side*x,y) for x,y in [(.041,-.083),(.063,-.086),(.071,-.056),(.068,.068),(.053,.087),(.037,.076),(.041,.048)]]
        loft('ceramic_crash_rail', [(.015,cheek),(.041,[(x-side*.003,y) for x,y in cheek])], 'ivory', .0014)
        box('rail_ochre_mark',(side*.054,.011,.042),(.008,.055,.002),'paint',bevel=.0005)
        pipe('reserve_terminal_bus',[(side*.024,-.066,.031),(side*.047,-.063,.028),(side*.048,-.091,.026),(side*.029,-.092,.026)],.0022,'copper')
        box('retaining_latch',(side*.027,-.068,.046),(.016,.015,.011),'edge',bevel=.001)
    box('protected_cutoff_bezel',(0,-.030,.047),(.036,.031,.006),'steel',bevel=.0013)
    box('recessed_cutoff_lever',(0,-.030,.051),(.023,.006,.005),'ivory',bevel=.0008,rotation=(0,0,-.22))
    for y in (-.075,.075):
        box('steel_cartridge_retaining_band',(0,y,.037),(.080,.008,.021),'edge',bevel=.001)
    for index in range(4):
        box('reserve_cooling_groove',(0,-.007-index*.010,.0445),(.020,.003,.001),'rubber',bevel=.0002)
    export('baroud','Rear upper-arm emergency reserve cartridge with red ceramic housing, three amber charge windows, protective ivory rails, captive latches, copper terminal buses and a recessed cutoff lever.')


def build_omnivamp():
    """Recovery circuit with two pressure reservoirs and a return manifold."""
    model.begin('omnivamp')
    base(.152,.207)
    for side in (-1,1):
        x = side*.027
        cylinder('recovery_pressure_reservoir',(x,.003,.030),.017,.111,'jade',vertices=20,bevel=.0014)
        for y in (-.055,.061):
            cylinder('reservoir_clamped_cap',(x,y,.030),.019,.014,'edge',vertices=16,bevel=.0009)
        ring('reservoir_neck_seal',(x,.068,.030),.012,.006,.006,'copper',axis=(0,1,0),segments=16)
        box('reservoir_level_channel',(x,.002,.0475),(.006,.067,.002),'rubber',bevel=.0004)
        box('recovered_charge_indicator',(x,.011,.049),(.0028,.039,.001),'green',bevel=.0002)
        rail = [(side*a,b) for a,b in [(.048,-.080),(.065,-.069),(.069,.064),(.052,.083),(.044,.076),(.050,.051)]]
        loft('reservoir_ceramic_guard',[ (.014,rail),(.039,[(a-side*.002,b) for a,b in rail])],'ivory',.0013)
        pipe('copper_recovery_return',[(x,.071,.030),(x,.084,.032),(side*.009,.084,.033),(side*.009,-.069,.033),(x,-.070,.030)],.0021,'copper')
        box('reservoir_guard_strap',(x,-.032,.045),(.037,.007,.010),'edge',bevel=.0008)
    box('lower_recovery_manifold',(0,-.079,.033),(.070,.023,.023),'steel',bevel=.0015)
    cylinder('flow_regulator_spindle',(0,-.079,.046),.006,.008,'copper',axis=(0,0,1),vertices=12,bevel=.0004)
    ring('regulator_handwheel',(0,-.079,.053),.013,.007,.004,'edge',segments=16)
    box('regulator_handwheel_crossbar',(0,-.079,.053),(.021,.004,.004),'edge',bevel=.0005)
    box('circuit_status_bezel',(0,.052,.031),(.018,.026,.013),'steel',bevel=.001)
    box('circuit_status_window',(0,.052,.038),(.005,.014,.0015),'green',bevel=.0004)
    export('omnivamp','Paired jade recovery reservoirs with level channels, copper return circuit, ceramic crash guards, retaining straps and a real bored flow-regulator handwheel.')


def optic(name, center, radius):
    x,y,z = center
    cylinder(name+'_recess',(x,y,z),radius,.020,'rubber',axis=(0,0,1),vertices=24,bevel=.0005)
    ring(name+'_machined_bezel',(x,y,z+.009),radius*1.13,radius*.76,.014,'edge',segments=24)
    ring(name+'_copper_seal',(x,y,z+.014),radius*.81,radius*.69,.003,'copper',segments=20)
    cylinder(name+'_opaque_optical_coating',(x,y,z+.011),radius*.67,.003,'cyan',axis=(0,0,1),vertices=24,bevel=.0003)
    for index in range(6):
        a = index*pi/3
        blade = [(x+radius*r*cos(a+angle),y+radius*r*sin(a+angle)) for r,angle in [(.77,0),(.77,.42),(.53,.56),(.54,.18)]]
        loft(name+'_iris_blade',[ (z+.013,blade),(z+.014,blade)],'steel',.0002)


def build_legacy_tracker():
    """Asymmetric dual-aperture acquisition head with an exposed heat sink."""
    model.begin('tracker')
    base(.145,.203)
    body = contour(.108,.123,.021,(0,.014))
    loft('optical_acquisition_housing',[ (.019,body),(.036,[(x*.95,y) for x,y in body])],'paint',.0016)
    optic('primary_tracker_optic',(-.013,.024,.044),.030)
    optic('offset_rangefinder',(.038,-.050,.029),.012)
    crown = [(-.056,.067),(-.046,.091),(.038,.091),(.060,.064),(.041,.055),(.024,.074),(-.037,.074)]
    loft('ceramic_optical_brow',[ (.031,crown),(.061,[(x,y-.003) for x,y in crown])],'ivory',.0014)
    cheek = [(-.061,-.076),(-.044,-.085),(-.033,-.073),(-.037,-.023),(-.053,-.012),(-.063,-.031)]
    loft('asymmetric_sensor_guard',[ (.016,cheek),(.049,cheek)],'ivory',.0013)
    for index in range(5):
        box('optics_copper_heat_sink',(.048,-.015+index*.013,.030),(.021,.003,.014),'copper',bevel=.0005)
    pipe('rangefinder_link',[ (.036,-.064,.026),(.008,-.078,.025),(-.018,-.063,.026),(-.013,-.009,.026)],.002,'rubber')
    box('acquisition_status_bezel',(-.010,-.067,.026),(.025,.012,.008),'steel',bevel=.0008)
    box('acquisition_status',(-.010,-.067,.0305),(.013,.003,.001),'cyan',bevel=.0003)
    export('tracker','Asymmetric dual-aperture tracker with recessed opaque cyan optics, individual iris blades, bored machined bezels, a ceramic brow, copper heat sink and protected rangefinder cable.')


def build_tracker():
    # The approved eye supersedes the original rear-arm insert. Batch rebuilds
    # must use the same current authoring source as an individual tracker build.
    from build_tracker_eye_model import build_tracker as build_eye
    build_eye()


def build_alternator():
    """Commutator with two charge sectors and exposed radial copper contacts."""
    model.begin('alternator')
    base(.159,.204)
    cylinder('commutator_motor_tray',(0,.013,.026),.063,.021,'steel',axis=(0,0,1),vertices=24,bevel=.001)
    ring('commutator_outer_race',(0,.013,.038),.062,.048,.012,'edge',segments=24)
    cylinder('rotor_hub',(0,.013,.044),.018,.016,'rubber',axis=(0,0,1),vertices=16,bevel=.0008)
    cylinder('keyed_rotor_spindle',(0,.013,.054),.009,.009,'edge',axis=(0,0,1),vertices=8,bevel=.0006)
    for index in range(8):
        a = index*pi/4
        contact = [(r*cos(a+angle),.013+r*sin(a+angle)) for r,angle in [(.024,-.08),(.043,-.08),(.043,.08),(.024,.08)]]
        loft('radial_copper_commutator_contact',[ (.039,contact),(.044,contact)],'copper',.0004)
    arc('weapon_charge_sector',(0,.013,.046),.050,.046,.002,'cyan',.15,pi-.15,segments=16)
    arc('module_charge_sector',(0,.013,.046),.050,.046,.002,'amber',pi+.15,2*pi-.15,segments=16)
    for side in (-1,1):
        rail = [(side*x,y) for x,y in [(.061,-.077),(.076,-.060),(.076,.064),(.062,.084),(.048,.073),(.060,.049),(.062,-.035),(.048,-.062)]]
        loft('ceramic_commutator_yoke',[ (.017,rail),(.048,[(x-side*.002,y) for x,y in rail])],'ivory',.0014)
        box('brush_terminal',(side*.036,-.056,.031),(.021,.020,.014),'edge',bevel=.001)
        pipe('brush_feed',[(side*.051,-.040,.035),(side*.053,-.062,.035),(side*.029,-.076,.032)],.002,'copper')
    box('relay_bridge',(0,-.076,.032),(.043,.021,.026),'paint',bevel=.0014)
    box('relay_divider',(0,-.076,.046),(.004,.020,.002),'rubber',bevel=.0003)
    for side,mat in [(-1,'cyan'),(1,'amber')]:
        box('relay_state_contact',(side*.011,-.076,.046),(.010,.004,.002),mat,bevel=.0003)
    export('alternator','Two-channel rotary commutator with eight separated copper contacts, cyan and amber charge sectors, a keyed spindle, ceramic yokes, carbon brush terminals and a bottom changeover relay.')


def build_inertia():
    """Nested tilted gimbals, solid flywheel and paired damping struts."""
    model.begin('inertia')
    base(.157,.208)
    center = (0,.018,.037)
    ring('outer_gyro_gimbal',center,.057,.051,.010,'edge',segments=24)
    ring('tilted_copper_gimbal',center,.047,.041,.008,'copper',axis=(.46,.34,.82),segments=24)
    ring('inner_flywheel_race',center,.035,.026,.010,'steel',axis=(-.38,.42,.82),segments=24)
    cylinder('solid_inertial_flywheel',center,.025,.014,'paint',axis=(-.38,.42,.82),vertices=24,bevel=.001)
    cylinder('central_rotor_bearing',(0,.018,.049),.007,.011,'edge',axis=(0,0,1),vertices=16,bevel=.0006)
    for side in (-1,1):
        fork = [(side*x,y) for x,y in [(.047,-.087),(.068,-.077),(.074,-.049),(.071,.070),(.056,.088),(.042,.076),(.058,.053),(.058,-.044)]]
        loft('ceramic_gyro_support_fork',[ (.015,fork),(.044,[(x-side*.0015,y) for x,y in fork])],'ivory',.0014)
        cylinder('gimbal_trunnion',(side*.056,.018,.037),.008,.021,'edge',axis=(1,0,0),vertices=16,bevel=.0008)
        cylinder('damper_cylinder',(side*.026,-.071,.031),.007,.028,'steel',vertices=16,bevel=.0007)
        cylinder('damper_piston',(side*.026,-.049,.031),.003,.028,'edge',vertices=12,bevel=.0003)
        ring('damper_copper_seal',(side*.026,-.057,.031),.008,.004,.004,'copper',axis=(0,1,0),segments=16)
        box('damper_pivot_block',(side*.026,-.036,.031),(.014,.012,.014),'edge',bevel=.0008)
    box('gyro_control_bridge',(0,-.088,.027),(.050,.014,.016),'steel',bevel=.001)
    box('gyro_lock_state',(0,-.088,.036),(.016,.004,.002),'cyan',bevel=.0003)
    export('inertia','Mechanical inertia stabilizer with three real bored gimbals in different planes, a solid ochre flywheel, lateral trunnions, ceramic support forks, paired damping struts and a lock-state indicator.')


if __name__ == '__main__':
    builders = {'baroud':build_baroud,'omnivamp':build_omnivamp,'tracker':build_tracker,'alternator':build_alternator,'inertia':build_inertia}
    requested = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else list(builders)
    for identifier in requested:
        builders[identifier]()
