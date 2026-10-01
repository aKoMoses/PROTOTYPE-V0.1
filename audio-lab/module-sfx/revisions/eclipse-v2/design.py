"""One Eclipse arrival cue: violent rematerialization, not a teleport chime."""
from pathlib import Path
ROOT=Path(__file__).resolve().parent
SR=44100
RUNTIME=Path(r"C:\Users\BOTTEROOOW\Tools\stable-audio-3\optimized\tflite")
PYTHON=RUNTIME/".venv/Scripts/python.exe"
CLI=RUNTIME/"scripts/sa3_tflite.py"
INSPECT_PYTHON=Path(r"C:\Users\BOTTEROOOW\.codex\runtimes\stable-audio-3\.venv\Scripts\python.exe")
INSPECTOR=Path(r"C:\Users\BOTTEROOOW\.codex\skills\generate-local-sfx\scripts\inspect_sfx.py")
NEGATIVE="music, voices, notification beep, sonar ping, sine wave, cartoon bloop, drill, clipping"
MODULES={"eclipse":{"name":"Éclipse","meaning":"Le robot se reforme brutalement à l'arrivée et libère une explosion au contact. Un seul son d'arrivée, court, dense et rugueux.","scenario":[("eclipse-arrival",.50,1)]}}
CUES=[{"id":"eclipse-arrival","module":"eclipse","label":"Explosion à l'arrivée","meaning":"La matière se reforme dans une détonation courte : impact grave et éclatement de particules, sans signal de téléportation.","maximum_duration":.85,"rms_db":-20,"kind":"accent","seed":26100601,"prompt":"One sudden explosive rematerialization of a heavy object at close range. Immediate dense low impact thump and a sharp dry bursting pressure crack, followed by a short coarse shower of crackling particles scattering outward and fading into silence. Strong violent physical arrival, compact explosion with weight and rough granular texture. One clearly articulated detonation, no preparatory rise, no long rumble, no metal ricochet, no notification beep, no pitched tone, no laser chirp, no voices or music. Clean isolated sound effect."}]
# Retain the first detonation and falling fragments, rather than selecting
# the louder individual fragment at 0.20 s as if it were the whole impact.
CUES[0]["source_interval"]=(0,.82)
