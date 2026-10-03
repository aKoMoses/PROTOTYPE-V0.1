"""Stable Audio originals and audition pack; new candidates are not gameplay assets."""
import hashlib, html, json, subprocess, sys, wave
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parent
RUNTIME = Path(r'C:\Users\BOTTEROOOW\Tools\stable-audio-3\optimized\tflite')
PYTHON = RUNTIME / '.venv/Scripts/python.exe'
CLI = RUNTIME / 'scripts/sa3_tflite.py'
INSPECTOR = Path(r'C:\Users\BOTTEROOOW\.codex\skills\generate-local-sfx\scripts\inspect_sfx.py')
SR = 44100
# Cue, family, French label, maximum gesture length, acoustic cause.
SPECS = [
 ('javelin-charge','javelin','Charge du javelot',1.1,'One steel throwing spear charging with taut electrical energy, a brief rising coarse arc tightening into a crisp dry metal latch'),
 ('javelin-launch','javelin','Lancer du javelot',.55,'One heavy steel throwing spear hurled rapidly past the microphone, a sharp narrow cutting air whoosh and a tiny metallic snap'),
 ('javelin-impact','javelin','Impact et marque',.65,'One steel spear point embedding into thick robot armor, a sharp piercing metallic crack, solid low contact and a short rough electrical spark'),
 ('javelin-mark-end','javelin','Expiration de la marque',.35,'One charged steel pin spring snapping back into its latch, a clearly articulated dry metal click and short rough electrical release'),
 ('fulguro-charge','fulguro_punch','Charge du poing',1.25,'One massive robotic fist building electrical pressure, a compact rising coarse power crackle with strained metal resonance, finishing taut'),
 ('fulguro-impact','fulguro_punch','Coup de poing électrique',.7,'One heavy powered metal fist smashing thick robot armor, immediate deep blunt thump, crunchy steel contact and short violent electrical discharge'),
 ('fulguro-wall','fulguro_punch','Projection contre un mur',.8,'One heavy armored robot body slamming into a concrete wall, deep physical body impact and a brief dry burst of broken concrete rubble'),
 ('pelto-outbound','pelto_smash','Onde aller',.85,'One broad heavy pressure wave scraping outward across coarse stone, a forceful low rushing sweep with dry gritty friction and one compact steel pulse'),
 ('pelto-return','pelto_smash','Onde retour',.85,'One broad pressure wave rushing back rapidly along a gritty stone floor, a narrowing inward suction sweep ending with a dry tight mechanical catch'),
 ('pelto-hit','pelto_smash','Impact de l’onde',.55,'One heavy pressure wave hitting an armored metal body, a wide blunt physical thump with short crunchy steel vibration'),
 ('bio-inject','bio_injector','Injection',.5,'One industrial medical injector firing a pressurized dose into a metal port, a crisp plunger click, short compressed liquid hiss and tiny valve catch'),
 ('bio-boost','bio_injector','Activation du boost',.65,'One pressurized performance booster opening into a heavy metal actuator, a compact forceful air release with a rising textured energy rush'),
 ('bio-end','bio_injector','Fin du boost',.45,'One pressurized booster valve closing, a short descending air release ending in a small dry mechanical latch'),
 ('static-on','static_shield','Activation de la protection',.65,'One compact electrostatic protective shell snapping into place around a metal robot, one rounded dry power snap with a brief granular electrical shimmer'),
 ('static-block','static_shield','Coup absorbé',.4,'One projectile stopped against a charged protective shell, one tight muted impact pop and a short fine electrical crackle, close and restrained'),
 ('static-off','static_shield','Fin de la protection',.4,'One electrostatic protective shell collapsing, short brittle electricity dissipating with one soft dry power-down snap'),
 ('magnetic-place','magnetic_field','Pose du champ',.65,'One heavy magnetic barrier engaging, a firm metal clamp locking and a short deep textured magnetic surge spreading outward'),
 ('magnetic-block','magnetic_field','Projectile absorbé',.4,'One metal projectile caught abruptly by a powerful magnetic barrier, one dry metallic catch followed by a short coarse energy absorption crackle'),
 ('magnetic-end','magnetic_field','Disparition du champ',.5,'One heavy magnetic clamp releasing from steel, a clearly articulated close mechanical unclamp clack and brief descending pressure release'),
 ('eclipse-depart','eclipse','Disparition',.55,'One heavy object abruptly dissolving into dark gritty particles, a tight inward air implosion and a short coarse scattering crackle'),
 ('eclipse-arrival','eclipse','Explosion à l’arrivée',.85,'One heavy armored object explosively rematerializing, immediate dense low physical impact, sharp bursting pressure crack and a short rough shower of falling particles'),
 ('eclipse-shield','eclipse','Bouclier obtenu',.4,'One compact temporary energy shield locking around a heavy object after impact, a restrained firm shell snap and tiny dry electrical shimmer'),
 ('tracker-mark','tracker','Cible repérée',.35,'One precision mechanical targeting latch locking onto a target, two tiny dry metallic clicks ending in a short taut nonmusical steel ping'),
 ('alternator-ready','alternator','Bonus prêt',.35,'One heavy weapon breech engaging an alternate power contact, a close crisp metal switch clack and tiny rough electrical spark'),
 ('inertia-trigger','inertia','Ralentissement appliqué',.4,'One heavy mechanical brake clamping suddenly, a compact dry friction grab and short weighted metal catch'),
 ('reactor-refresh','auxiliary_reactor','Recharge accélérée',.4,'One small auxiliary pressure accumulator releasing a compact pulse into a mechanical port, short dry compressed air puff and precise valve click'),
 ('omnivamp-heal','omnivamp','Soin obtenu',.3,'One pressurized restorative fluid pulse entering a medical port, one clear rounded wet suction pop with a crisp valve catch'),
]

def read(path):
 with wave.open(str(path),'rb') as w:
  assert w.getframerate()==SR and w.getsampwidth()==2
  channels=w.getnchannels()
  x=np.frombuffer(w.readframes(w.getnframes()),dtype='<i2').astype(float).reshape(-1,channels)/32768
 return x if channels==2 else np.repeat(x,2,axis=1)

def write(path,x):
 path.parent.mkdir(parents=True,exist_ok=True)
 assert np.isfinite(x).all() and np.max(np.abs(x))<.995
 with wave.open(str(path),'wb') as w:
  w.setnchannels(2);w.setsampwidth(2);w.setframerate(SR)
  w.writeframes((x*32767).astype('<i2').tobytes())

def extract(raw,maximum,target_db=-19):
 block=round(.005*SR)
 energy=np.mean(raw[:len(raw)//block*block].reshape(-1,block,2)**2,axis=(1,2))
 peak=int(np.argmax(energy));threshold=max(energy[peak]*.025,np.median(energy)*.8)
 first=last=peak;gap=0
 for i in range(peak-1,-1,-1):
  gap=gap+1 if energy[i]<threshold else 0
  if gap>=5:break
  first=i
 gap=0
 for i in range(peak+1,len(energy)):
  gap=gap+1 if energy[i]<threshold else 0
  if gap>=8:break
  last=i
 start=max(0,first*block-round(.006*SR));end=min(len(raw),(last+1)*block+round(.04*SR))
 cap=round(maximum*SR)
 if end-start>cap:
  if peak*block-start>cap*.65:start=max(0,peak*block-round(cap*.4))
  end=min(len(raw),start+cap)
 if end-start<round(.12*SR):end=min(len(raw),start+round(.12*SR))
 x=raw[start:end].copy();x-=np.mean(x,axis=0)
 source_rms=float(np.sqrt(np.mean(x*x)))
 if source_rms<.008:raise ValueError('source too weak; regeneration needed')
 a=min(round(.0015*SR),len(x)//3);r=min(round(.025*SR),len(x)//3)
 x[:a]*=(np.sin(np.linspace(0,np.pi/2,a))**2)[:,None]
 x[-r:]*=(np.cos(np.linspace(0,np.pi/2,r))**2)[:,None]
 gain=min(10**(target_db/20)/np.sqrt(np.mean(x*x)),.77/max(np.max(np.abs(x)),1e-9))
 if gain>10**(10/20):raise ValueError('excessive gain; regeneration needed')
 return x*gain,[round(start/SR,5),round(end/SR,5)],round(20*np.log10(gain),2)

def main():
 for d in ['raw','candidates','previews','reports']:(ROOT/d).mkdir(parents=True,exist_ok=True)
 previous=json.loads((ROOT/'manifest.json').read_text(encoding='utf-8')) if (ROOT/'manifest.json').exists() else {}
 rejected={c['id']:c['reason'] for c in previous.get('failures',[])}
 cues=[]
 for i,(key,family,label,maximum,cause) in enumerate(SPECS):
  prompt=cause+'. Close microphone, dry isolated studio game sound effect. One clearly articulated physical gesture then silence. No music, no voices, no repeating motor, no drill, no notification beeps, no sustained tonal drone.'
  retry=key in rejected or (ROOT/'raw'/f'{key}-v2.wav').exists()
  quiet=key in ['javelin-mark-end','bio-end','static-off','magnetic-end','tracker-mark','alternator-ready','reactor-refresh','omnivamp-heal']
  cues.append(dict(id=key,family=family,label=label,maximum_duration=maximum,target_rms_db=-25 if quiet else -19,prompt=prompt,seed=261002100+i+(1000 if retry else 0),attempt=2 if retry else 1,previous_rejection=rejected.get(key),visible_cause=cause,desired_association=cause,forbidden_association='music, voice, motor, drill, repeated pulse train, notification beep',contact='on the corresponding gameplay action or confirmed hit',heard_in_picture=None,decision='pending listening'))
 (ROOT/'sound-sheet.json').write_text(json.dumps(dict(model='Stable Audio 3 Small-SFX',runtime='official optimized TFLite local',seconds=4,steps=8,cfg=1,cues=cues,integrated_in_game=False),ensure_ascii=False,indent=2),encoding='utf-8')
 records=[];clips={};failures=[]
 for cue in cues:
  key=cue['id'];suffix='-v2' if cue['attempt']==2 else '';raw=ROOT/'raw'/f'{key}{suffix}.wav'
  if not raw.exists():
   print('GENERATING '+key,flush=True)
   with (ROOT/'reports'/f'{key}{suffix}-generation.log').open('w',encoding='utf-8') as log:
    result=subprocess.run([str(PYTHON),str(CLI),'--dit','sm-sfx','--decoder','same-s','--seconds','4','--steps','8','--cfg','1','--seed',str(cue['seed']),'--threads','8','--prompt',cue['prompt'],'--out',str(raw)],stdout=log,stderr=subprocess.STDOUT)
   if result.returncode:raise SystemExit('generation failed '+key)
  try:
   x,interval,gain=extract(read(raw),cue['maximum_duration'],cue['target_rms_db'])
   dest=ROOT/'candidates'/f'{key}.wav';write(dest,x)
   result=subprocess.run([str(PYTHON),str(INSPECTOR),str(dest),'--kind','accent','--strict'],capture_output=True,text=True)
   (ROOT/'reports'/f'{key}-strict.txt').write_text(result.stdout+result.stderr,encoding='utf-8')
   if result.returncode:raise ValueError('strict inspection rejected candidate')
   clips[key]=x
   records.append(dict(**cue,source=str(raw.relative_to(ROOT)),file=f'candidates/{key}.wav',source_sha256=hashlib.sha256(raw.read_bytes()).hexdigest(),source_interval_seconds=interval,gain_db=gain,sha256=hashlib.sha256(dest.read_bytes()).hexdigest(),duration_seconds=len(x)/SR,technical_check='PASS'))
   print('CANDIDATE_READY '+key,flush=True)
  except ValueError as e:
   failures.append(dict(id=key,reason=str(e)));print('REJECT '+key+' '+str(e),flush=True)
 families=list(dict.fromkeys(c['family'] for c in cues))
 for family in families:
  keys=[c['id'] for c in cues if c['family']==family and c['id'] in clips]
  if not keys:continue
  reel=np.zeros((round(sum(len(clips[k])/SR+1.1 for k in keys)*SR),2));offset=round(.3*SR)
  for key in keys:
   x=clips[key];reel[offset:offset+len(x)]+=x;offset+=len(x)+round(1.1*SR)
  write(ROOT/'previews'/f'{family}.wav',reel)
 (ROOT/'manifest.json').write_text(json.dumps(dict(integrated_in_game=False,decision='pending user listening',cues=records,failures=failures),ensure_ascii=False,indent=2),encoding='utf-8')
 body=['<!doctype html><meta charset="utf-8"><title>Sons de combat — Stable Audio</title><style>body{background:#171b20;color:#eee;font:16px system-ui;max-width:900px;margin:40px auto}section{border-top:1px solid #59616b;padding:20px 0}audio{width:100%}h1{color:#efb765}</style><h1>Sons de combat — Stable Audio</h1><p>Candidats à écouter. Aucun nouveau son de ce pack n’est encore intégré au jeu.</p>']
 for family in families:
  body.append('<section><h2>'+html.escape(family.replace('_',' ').title())+'</h2><audio controls src="previews/'+family+'.wav"></audio>')
  for c in records:
   if c['family']==family:body.append('<p>'+html.escape(c['label'])+'</p><audio controls src="'+c['file']+'"></audio>')
  body.append('</section>')
 (ROOT/'index.html').write_text('\n'.join(body),encoding='utf-8')
 print(f'PACK_READY {len(records)}/{len(cues)}; rejected={len(failures)}',flush=True)
 return 1 if failures else 0

if __name__=='__main__':sys.exit(main())
