"""Compact armour inserts. Godot metres, Y up; mounting plane Z=0."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from module_modeling import *


def build_pyro_boots():
    begin('pyro_boots')
    shell('Heel saddle', [(-.044,-.074),(.039,-.068),(.053,-.017),(.040,.069),
                         (-.024,.078),(-.051,.042)], -.003, .009, 'steel', .003)
    shell('Moulded ankle fairing', [(-.044,-.052),(.039,-.044),(.047,.002),(.028,.068),
                                 (-.026,.072),(-.046,.025)], .005, .039, 'ivory', .0045, .85)
    ring('Exhaust throat', (.005,-.022,.043), .028, .019, .019, 'steel', segments=24)
    ring('Exhaust lip', (.005,-.022,.052), .024, .019, .004, 'edge', segments=24)
    ring('Recessed pilot lining', (.005,-.022,.039), .0192, .014, .004, 'amber', segments=20)
    cylinder('Exhaust chamber', (.005,-.022,.029), .018, .003, 'rubber', (0,0,1), 20, bevel=0)
    cylinder('Igniter', (.005,-.022,.033), .005, .005, 'copper', (0,0,1), 12, bevel=.0005)
    shell('Narrow heat shroud', [(-.035,.037),(.015,.039),(.020,.058),(-.023,.063),
                               (-.035,.052)], .034, .039, 'paint', .0018)
    for i in range(3):
        box('Fine intake slit', (-.020,.018+i*.006,.040), (.025,.0025,.002),
            'rubber', .0005, rotation=(0,0,.15))
    box('Ready pin', (.027,.033,.035), (.003,.012,.002), 'amber', .0004)
    for x,y in [(-.027,-.059),(.029,.057)]:
        bolt('Flush fastener', (x,y,.015), .0032)
    export('pyro_boots')


def build_bio_injector():
    begin('bio_injector')
    outline = [(-.049,-.091),(.036,-.085),(.045,-.056),(.044,.072),(.028,.092),
               (-.036,.086),(-.050,.063)]
    shell('Contoured mounting shoe', outline, -.002, .009, 'steel', .0025)
    shell('Ceramic pump fairing', [(.015,-.081),(.040,-.075),(.044,.064),(.027,.088),
                                 (.015,.078)], .006, .041, 'ivory', .003, .93)
    for index,x in enumerate([-.032,-.006]):
        cylinder('Fluid cartridge_%d' % index, (x,.009,.021), .0108, .119,
                 'green', vertices=20, bevel=.001)
        for y in [-.057,.072]:
            cylinder('Retaining cap', (x,y,.021), .014, .018, 'steel', vertices=20, bevel=.0015)
        cylinder('Ceramic lid', (x,.083,.021), .010, .008, 'ivory', vertices=20, bevel=.001)
        for y in [-.025,.043]:
            ring('Retention band', (x,y,.021), .0138, .0108, .004, 'steel', (0,1,0), 20)
        for i in range(4):
            box('Dose mark', (x,-.012+i*.014,.032), (.006,.0011,.001), 'ivory', .0002)
    shell('Feed manifold', [(-.046,-.083),(.025,-.083),(.032,-.067),(-.042,-.062)],
          .011, .033, 'steel', .002)
    shell('Service stripe', [(.020,.009),(.035,.012),(.037,.058),(.021,.062)],
          .035, .039, 'paint', .0012)
    box('Control seam', (.028,-.037,.040), (.009,.026,.0015), 'rubber', .0004)
    box('Status pin', (.028,-.033,.042), (.003,.006,.0015), 'green', .0003)
    pipe('Recessed feed hose', [(-.036,-.070,.018),(-.055,-.072,.014),
                               (-.057,-.043,.010),(-.047,-.028,.005)], .0035, 'rubber')
    bolt('Service screw', (.027,-.066,.037), .0028)
    export('bio_injector')


if __name__ == '__main__':
    build_pyro_boots()
    build_bio_injector()
