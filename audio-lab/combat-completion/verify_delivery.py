"""Check audition sources and preserve a current integration receipt."""
import hashlib, html, json, sys, wave
from pathlib import Path
ROOT=Path(__file__).resolve().parent
REPO=ROOT.parents[1]
pack=json.loads((ROOT/'manifest.json').read_text(encoding='utf-8'))
is_integrated=bool(pack.get('integrated_in_game')) or '--integrated' in sys.argv
assert len(pack['cues'])==27 and not pack['failures']
for cue in pack['cues']:
 path=ROOT/cue['file']
 assert hashlib.sha256(path.read_bytes()).hexdigest()==cue['sha256']
 assert hashlib.sha256((ROOT/cue['source']).read_bytes()).hexdigest()==cue['source_sha256']
 assert cue['technical_check']=='PASS'
 with wave.open(str(path),'rb') as wav:
  assert wav.getframerate()==44100 and wav.getnchannels()==2
  assert wav.getnframes()>0 and wav.getnframes()/44100<=cue['maximum_duration']+.001
 if is_integrated:
  dest=REPO/'art/audio/combat-sfx'/path.name
  assert dest.read_bytes()==path.read_bytes()
runtime=[]
if is_integrated:
 from check_runtime import TESTS
 for test in TESTS:
  output=(ROOT/'reports'/f'{test}.log').read_text(encoding='utf-8')
  meaningful='\n'.join(line for line in output.splitlines() if 'resources still in use at exit' not in line)
  assert 'PASS' in output and not any(error in meaningful for error in ['SCRIPT ERROR','Parse Error','Compilation failed','ERROR:']),test
  runtime.append(dict(test=test,passed=True))
 (ROOT/'reports/runtime-checks.json').write_text(json.dumps(runtime,indent=2),encoding='utf-8')
 pack['integrated_in_game']=True
 pack['decision']='integration requested by user'
 pack['human_listening_confirmed']=False
 for cue in pack['cues']:
  cue['decision']='integration requested by user'
  cue['integrated_file']='art/audio/combat-sfx/'+Path(cue['file']).name
 (ROOT/'manifest.json').write_text(json.dumps(pack,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
selected_path=REPO/'audio-lab/weapon-comparison/selection.json'
selected=json.loads(selected_path.read_text(encoding='utf-8'))
integrated=[]
for asset in selected['files']:
 if asset['id'].endswith('-preview'):continue
 source=REPO/'audio-lab/weapon-comparison'/asset['path'].replace('\\','/')
 dest=REPO/'art/audio/weapon-sfx'/source.name
 assert hashlib.sha256(dest.read_bytes()).hexdigest()==asset['sha256']
 assert dest.read_bytes()==source.read_bytes()
 integrated.append(str(dest.relative_to(REPO)))
assert len(integrated)==10
receipt=dict(rocket_fix='TrainingAudioListener follows the controlled robot; camera framing unchanged',recorded_mixer='reports/training-rockets-recorded.wav',weapons=integrated,checks=runtime,combat_completion=dict(count=27,integrated_in_game=is_integrated,decision=pack['decision']),publication='local only')
probe=ROOT/'reports/combat-mixer.json'
if probe.exists():receipt['current_mixer_probe']=json.loads(probe.read_text(encoding='utf-8'))
(ROOT/'delivery.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf-8')
selected['integrated_in_game']=True
selected['integration_receipt']='audio-lab/combat-completion/delivery.json'
selected_path.write_text(json.dumps(selected,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
names={'javelin':'Javelin','fulguro_punch':'Fulguro Punch','pelto_smash':'Pelto Smash','bio_injector':'Bio Injector','static_shield':'Static Shield','magnetic_field':'Magnetic Field','eclipse':'Éclipse','tracker':'Tracker','alternator':'Alternator','inertia':'Inertia','auxiliary_reactor':'Réacteur auxiliaire','omnivamp':'Omnivamp'}
status='Les 27 sons sont intégrés au jeu local. Leurs déclenchements ont été vérifiés dans le terrain jouable.' if is_integrated else 'Les candidats passent les contrôles techniques ; leur intégration reste à valider.'
parts=['<!doctype html><html lang="fr"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Sons de combat — Stable Audio</title><style>body{background:#171b20;color:#eee;font:16px system-ui;max-width:900px;margin:32px auto;padding:0 20px}section{border-top:1px solid #59616b;padding:20px 0}audio{width:100%}h1{color:#efb765}p{line-height:1.5}details{margin-top:18px}summary{cursor:pointer;color:#efb765}nav a{color:#9cdae1;display:inline-block;margin:6px 12px 6px 0}</style><h1>Sons de combat — Stable Audio</h1><p>27 nouveaux sons dans 12 familles. Écoute la séquence de chaque module, ou ouvre les sons individuels. '+status+'</p><nav>']
for family,name in names.items():parts.append('<a href="#'+family+'">'+html.escape(name)+'</a>')
parts.append('</nav>')
for family,name in names.items():
 parts.append('<section id="'+family+'"><h2>'+html.escape(name)+'</h2><p>Séquence du module</p><audio controls preload="none" src="previews/'+family+'.wav"></audio><details><summary>Écouter les sons individuellement</summary>')
 for c in pack['cues']:
  if c['family']==family:parts.append('<p>'+html.escape(c['label'])+'</p><audio controls preload="none" src="'+c['file']+'"></audio>')
 parts.append('</details></section>')
parts.append('</html>')
(ROOT/'index.html').write_text('\n'.join(parts),encoding='utf-8')
print('DELIVERY VERIFIED: 10 selected weapon WAVs, 27 Stable Audio cues '+('integrated and runtime checked' if is_integrated else 'ready'))
