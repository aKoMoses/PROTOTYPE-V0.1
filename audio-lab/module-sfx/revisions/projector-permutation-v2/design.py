"""Pressure versus displacement: two distinct module sound vocabularies."""
from pathlib import Path
ROOT=Path(__file__).resolve().parent
SR=44100
RUNTIME=Path(r"C:\Users\BOTTEROOOW\Tools\stable-audio-3\optimized\tflite")
PYTHON=RUNTIME/".venv/Scripts/python.exe"
CLI=RUNTIME/"scripts/sa3_tflite.py"
INSPECT_PYTHON=Path(r"C:\Users\BOTTEROOOW\.codex\runtimes\stable-audio-3\.venv\Scripts\python.exe")
INSPECTOR=Path(r"C:\Users\BOTTEROOOW\.codex\skills\generate-local-sfx\scripts\inspect_sfx.py")
NEGATIVE="music, voices, notification beep, sonar ping, sine wave, cartoon bloop, drill, clipping"
MODULES={
 "projector":{"name":"Projector","meaning":"L'air se comprime autour du robot, puis une onde de pression chasse les adversaires. Le déclenchement de survie est immédiat et plus sec.","scenario":[("projector-charge",.45,1),("projector-wave",.95,1),("projector-push",1.05,.85),("projector-passive",2.70,1)]},
 "permutation":{"name":"Permutation","meaning":"Une ombre électrique se détache du robot et rejoint sa cible. Deux positions s'échangent ; le bouclier se referme sur le robot.","scenario":[("permutation-send",.45,1),("permutation-flight",.65,.75),("permutation-swap",1.70,1),("permutation-shield",1.88,.85)]},
}
ROWS=[
 ("projector-charge","projector","Compression avant l'onde","Une aspiration resserre la pression avant la répulsion ; pas de montée de synthé.",.45,-25,"accent","Close sound of air sucked rapidly into a compact pressure chamber. A short dry inward rush becoming tight and dense, a rough compressed air texture ending in a tiny muffled restraint. One brief intake with a clear natural stop. Physical air pressure, no motor, no pitched sound, no electronic beep, no music, clean isolated sound effect."),
 ("projector-wave","projector","Départ de l'onde","Un coup de pression large et grave marque le départ de l'onde circulaire.",.40,-20,"accent","One sudden pneumatic pressure wave exploding outward from a small chamber. A forceful low dry air thump, broad compressed gas punch with a hollow chesty body and a very short rough decay. Physical concussion without fire, metal debris or a gunshot crack. One isolated pressure release then silence, no pitched tone, no electronic chirp."),
 ("projector-push","projector","Souffle de répulsion","L'air balaye l'espace et pousse les corps loin du robot.",.58,-24,"accent","One broad forceful rush of displaced air sweeping outward close to the microphone. Dense windy shove, soft low pressure body and a coarse airy rushing tail fading quickly to silence. A brief physical gust pushing heavy objects, no explosion, no metal crash, no voices, no tonal wind whistle. Clean isolated short sound effect."),
 ("projector-passive","projector","Expulsion de secours · faibles PV","Une expulsion instantanée et sèche : le robot se sauve sans préparation.",.55,-21,"accent","One emergency pneumatic safety vent abruptly blasting open. A hard low air slap immediately followed by a short torn compressed air hiss, urgent physical pressure expulsion, fast aggressive onset and short falling tail. No alarm, no siren, no notification ping, no electronic tone, no voice, no melodic rise. One isolated release then silence."),
 ("permutation-send","permutation","Envoi de l'ombre","L'ombre se détache : une déchirure électrique fine et rapide.",.35,-24,"accent","One thin sheet of static electricity tearing away and shooting forward. A brief crisp irregular electrical rip and a narrow airy flick, delicate charged crackling dust, immediate clean launch gesture ending quickly. No heavy impact, no laser chirp, no sonar ping, no pitched buzz, no voice. Dry isolated electrical movement sound effect."),
 ("permutation-flight","permutation","Trajet de l'ombre","Une traînée électrique légère accompagne l'ombre jusqu'à sa cible.",1.10,-29,"loop","A faint moving cloud of charged dust flowing through the air. Soft irregular tiny static crackles carried by a narrow airy whisper, delicate fine electric particle texture, restrained continuous flowing motion. No motor, no repeated mechanical pulses, no high pitched whine, no electronic beep, no explosions, no voice or music."),
 ("permutation-swap","permutation","Échange des positions","Deux claquements spatiaux liés par un souffle bref font sentir le déplacement croisé.",.55,-21,"accent","One sudden spatial exchange sound, a tight air implosion snapping inward followed immediately by a crisp dry outward air pop with scattered static crackles. A compact double sided displacement gesture with a brief hollow sucking gap and decisive arrival. No explosion, no pitched laser, no sci fi beep, no music, one short complete gesture then silence."),
 ("permutation-shield","permutation","Bouclier obtenu","Une membrane énergétique se tend puis se ferme : protection légère et ferme.",.45,-25,"accent","One taut protective membrane snapping into place. A brief soft elastic air flap tightening into a rounded muted firm pop, with a delicate grain of static on the edge. Light flexible protective enclosure forming, one compact gesture and silence. No metal impact, no magic chime, no beep, no pitched hum, no voice, clean isolated sound effect."),
]
CUES=[dict(id=r[0],module=r[1],label=r[2],meaning=r[3],maximum_duration=r[4],rms_db=r[5],kind=r[6],prompt=r[7],seed=26100400+i) for i,r in enumerate(ROWS,1)]
for cue in CUES:
 if cue["id"]=="permutation-flight":
  cue["seed"]=26100506
  cue["prompt"]="A flowing cloud of electrically charged particles moving through the air close to the microphone. Clearly audible fine irregular static crackles mixed with a coarse narrow air stream, steady non tonal electric friction and flowing motion. Dense delicate charged dust texture, continuous without gaps. No motor, no mechanical pulses, no pitched whine, no beep, no explosions, no voices or music."
# Keep the sustained intake and the complete paired displacement. The loudest
# single spike in these sources does not represent the complete intended action.
SOURCE_INTERVALS={"projector-charge":(2.68,3.05),"permutation-swap":(2.53,3.03),"permutation-shield":(.95,1.20)}
for cue in CUES:
 if cue["id"] in SOURCE_INTERVALS:cue["source_interval"]=SOURCE_INTERVALS[cue["id"]]
