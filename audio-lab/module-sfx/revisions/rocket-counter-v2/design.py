"""Focused revision after the user rejected the generic first module batch."""
from pathlib import Path
ROOT=Path(__file__).resolve().parent
SR=44100
RUNTIME=Path(r"C:\Users\BOTTEROOOW\Tools\stable-audio-3\optimized\tflite")
PYTHON=RUNTIME/".venv/Scripts/python.exe"
CLI=RUNTIME/"scripts/sa3_tflite.py"
INSPECT_PYTHON=Path(r"C:\Users\BOTTEROOOW\.codex\runtimes\stable-audio-3\.venv\Scripts\python.exe")
INSPECTOR=Path(r"C:\Users\BOTTEROOOW\.codex\skills\generate-local-sfx\scripts\inspect_sfx.py")
NEGATIVE="music, voice, digital beep, sonar ping, sine wave, videogame power up, cartoon bloop, laser chirp, alarm, squeaky metal, drill, jackhammer, clipping"
MODULES={
 "rocket_basket":{"name":"Panier roquettes","meaning":"Des roquettes physiques : on ouvre le rack, elles s'arrachent du lanceur, puis frappent ou sont détruites en vol.","scenario":[("rocket-arm",.50,1),("rocket-launch",1.00,1),("rocket-flight",1.22,.70),("rocket-impact",2.50,1),("rocket-destroyed",3.90,1)]},
 "counter":{"name":"Counter","meaning":"Le coup est stoppé. Son énergie est aspirée dans le robot, puis violemment rendue au prochain impact.","scenario":[("counter-guard",.50,1),("counter-parry",1.10,1),("counter-capture",1.17,.80),("counter-release",2.85,1)]},
}
# Preserve the meaning and full natural gesture first. Final game timing is a
# later integration concern; neither cosmetic beeps nor a universal rising ramp.
ROWS=[
 ("rocket-arm","rocket_basket","Ouverture / armement","Le rack s'ouvre et verrouille les roquettes : poids, glissière, clac final.",.52,-22,"accent","Close-up Foley of one heavy steel ammunition rack being cocked. A solid mechanical clack, a brief rough sliding metal track, then a firm final locking thunk. Dense dry low metal weight, realistic tool mechanism, clearly articulated complete action. One action followed by silence. No electrical or tonal sounds."),
 ("rocket-launch","rocket_basket","Départ des roquettes","Une poussée brûlante arrache la salve au lanceur, sans tir de fusil.",.66,-20,"accent","A cluster of small missiles firing from a launcher in one burst. Abrupt punchy rocket ignition, ripping hot gas exhaust rushing outward, short layered fiery whooshes overlapping. Strong physical jet thrust, airy coarse roar, no gunshot crack. One short missile launch burst with a natural quick decay into silence."),
 ("rocket-flight","rocket_basket","Propulsion en vol","La poussée continue des moteurs suit les roquettes ; elle reste sous les impacts.",1.25,-29,"loop","A small rocket motor burning steadily in flight. Close textured rushing combustion gases with gritty fluttering turbulent air and a restrained coarse fiery roar. Continuous non musical exhaust sound, no startup, no ignition bang, no explosions, no metallic rattling, no electronic tone. Natural soft irregular texture."),
 ("rocket-impact","rocket_basket","Impact explosif","La roquette atteint sa cible : détonation courte, pression et débris.",.88,-19,"accent","One compact missile detonating against a thick steel plate. Forceful sharp explosion with a chesty low punch, harsh bursting fragments and brief gritty metallic debris. Physical explosive impact, tight dry recording, full initial detonation followed by a short falling debris tail and silence. No long bass drone."),
 ("rocket-destroyed","rocket_basket","Roquette détruite en vol","La carcasse éclate avant la cible : petit éclatement fragile, distinct de l'impact.",.54,-23,"accent","One small flying rocket breaking apart when shot. Short hollow casing crunch and brittle metal crack, followed by a little sputtering fuel puff and light scattered fragment ticks. Fragile airy destruction with much less explosive weight than a missile impact. One complete brief burst and silence. No sonar or electronic tones."),
 ("counter-guard","counter","Mise en garde","Le robot se ferme au coup : une tension physique brève, pas un signal d'interface.",.25,-25,"accent","One heavy protective metal brace snapping firmly into position. Tight muted steel clack with a brief taut air squeeze, dry short solid defensive mechanism. Compact physical lock with weight but without ringing, chirping or electronic sounds. One immediate movement and silence."),
 ("counter-parry","counter","Attaque arrêtée","Le choc est net : on doit sentir que le coup adverse vient d'être bloqué.",.36,-20,"accent","One violent strike stopped dead against a thick steel guard. Hard sharp metal-on-metal crack with a solid lower body and a very brief crushed air burst. Tactile decisive defensive collision, no ricochet whistle, no melodic ring. Single dry close-up impact with a short natural decay and silence."),
 ("counter-capture","counter","Énergie capturée / surcharge","Après la parade, l'énergie rentre dans le robot : aspiration et crépitement contenu.",.58,-25,"accent","One short burst of high voltage arcing being sucked inward and extinguished. A coarse irregular electrical crackle gathering rapidly into a compressed gritty fizz, ending abruptly in a dry muted snap. Textured electricity and inward air suction, an energy capture gesture rather than a UI notification. No pitched hum, no chirp, no ping, no melody. One burst then silence."),
 ("counter-release","counter","Énergie renvoyée à l'impact","L'énergie stockée ressort au contact : décharge plus brutale que l'absorption.",.72,-20,"accent","One forceful high voltage discharge erupting at a steel impact. A hard immediate electrical snap layered with a dense physical metal crack and a compact crackling blast tearing outward. Strong aggressive stored energy release, short rough non tonal electrical tail, then silence. No laser beam, no UI beep, no long buzz."),
]
CUES=[dict(id=r[0],module=r[1],label=r[2],meaning=r[3],maximum_duration=r[4],rms_db=r[5],kind=r[6],prompt=r[7],seed=26100300+i) for i,r in enumerate(ROWS,1)]
# These sources contain several separated gestures. Retain a meaningful group
# instead of letting the loudest isolated spike determine the whole accent.
SOURCE_INTERVALS={"rocket-arm":(.20,.70),"counter-capture":(.60,.99),"rocket-destroyed":(0,.35)}
for cue in CUES:
 if cue["id"] in SOURCE_INTERVALS:cue["source_interval"]=SOURCE_INTERVALS[cue["id"]]
