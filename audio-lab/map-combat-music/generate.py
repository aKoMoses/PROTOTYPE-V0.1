"""Generate fast action-duel music auditions; no game integration."""
from pathlib import Path
import subprocess
import wave
import json
import hashlib
import html
import shutil
import sys
import numpy as np

ROOT = Path(__file__).resolve().parent
RUNTIME = Path(r'C:\Users\BOTTEROOOW\Tools\stable-audio-3\optimized\tflite')
PYTHON = RUNTIME / '.venv/Scripts/python.exe'
CLI = RUNTIME / 'scripts/sa3_tflite.py'
COMMON = (' Explosive fast action fighting game instrumental. Immediate full rhythmic attack from the first beat, '
          'relentless rapid sixteenth-note figures, driving rhythm throughout, strong precise dry percussion. '
          'A thirty-second frantic duel, energetic and urgent from start to finish. '
          'Natural acoustic instruments, compact arrangement with space between accents for combat effects. '
          'No vocals, no synthesizers, no sound effects, no slow introduction, no gradual build, no ambient pads, '
          'no halftime groove, no cinematic trailer rise. ')
TRACKS = [
    ('4A', 'Héliostat', 'Course dans la lumière', 'Oud rapide et tambours tendus', 172, 261003441,
     '172 BPM. Fast aggressive oud picking, sharp spiccato viola and cello, powerful frame drums and dry snare accents. Driving acoustic desert battle music. Short minor oud hooks alternate with rapid bowed string bursts. Full racing rhythm from beat one, tense sun-baked duel.'),
    ('4B', 'Héliostat', 'Cuivre en surchauffe', 'Cordes d’action et accents de cuivre', 176, 261003442,
     '176 BPM. Very fast staccato low strings, punchy acoustic drum kit with fast kick and snare, clipped muted brass accents, racing oud countermelody. Intense tightly articulated orchestral battle groove. Start already in the busiest action phrase, urgent rhythmic pressure without sustained brass chords.'),
    ('4C', 'Héliostat', 'Lames de soleil', 'Guitare sèche et poursuite percussive', 180, 261003443,
     '180 BPM. Furious acoustic baritone guitar picking, rapid oud riffs, percussive upright bass, hard dry snare and hand drum rolls. Fast aggressive acoustic chase music with syncopated attack. Short repeating riffs, rapid musical call and response, full drums immediately, continuous forward drive.'),
    ('5A', 'Serre engloutie', 'Chasse entre les îlots', 'Marimba rapide et contretemps', 170, 261003551,
     '170 BPM. Racing low marimba ostinato, sharp pizzicato cello, fast bass clarinet figures, hard tightly played acoustic drums. Propulsive dark organic battle music. Dense rapid mallet movement over a clear fast snare pulse, quick syncopated changes, immediate energy, dangerous pursuit through a greenhouse.'),
    ('5B', 'Serre engloutie', 'Sous les feuilles : poursuite', 'Jazz de combat et batterie nerveuse', 174, 261003552,
     '174 BPM. Hard-driving acoustic jazz battle music, frantic dry breakbeat drums, very fast upright bass riff, biting acoustic piano stabs, low clarinet playing short nervous minor hooks. Straight fast time, no laid-back swing, no lounge feel. Already at full chase intensity on the opening beat, urgent ambush and counterattack.'),
    ('5C', 'Serre engloutie', 'Traversée sous pression', 'Cordes rapides et tambours organiques', 178, 261003553,
     '178 BPM. Fierce rapid spiccato strings and muted nylon guitar picking, forceful low hand drums, dry snare subdivisions, brief low woodwind attacks. Fast organic action score, nervous insistent repeated figures and abrupt accented turns. Strong driving beat from the very beginning, sustained combat intensity.'),
    ('6A', 'Cœur d’horloge', 'La treizième heure : assaut', 'Valse précipitée et cordes tranchantes', 180, 261003661,
     '180 BPM. Frantic aggressive chamber battle waltz in fast triple meter. Racing spiccato string quartet, incisive bassoon repeated notes, hard acoustic snare and low drum accents, sharp piano stabs. Fast dance transformed into an urgent duel. Short minor motif chased between strings and bassoon, complete rhythm starts immediately.'),
    ('6B', 'Cœur d’horloge', 'Échappement sous tension', 'Piano martelé et précision rythmique', 172, 261003662,
     '172 BPM. Rapid percussive acoustic piano ostinato, fiercely articulated viola and cello, dry racing acoustic drum kit and short muted horn stabs. Tight relentless sixteenth-note motion, tense precise accents, abrupt short phrase changes. Aggressive clockwork battle groove without actual clock or mechanism sounds, immediate fast action.'),
    ('6C', 'Cœur d’horloge', 'Engrenage de combat', 'Course orchestrale et accents lourds', 166, 261003663,
     '166 BPM. Racing low string ostinato, fast staccato violins, punchy acoustic kick and snare with brief timpani strokes, sharply clipped brass. Powerful urgent battle music with a clearly fast beat, very short rhythmic motifs. Begin with full moving percussion and strings, no majestic slow organ, no long held notes.'),
]

def read(path):
    with wave.open(str(path), 'rb') as w:
        sr, nc, sw = w.getframerate(), w.getnchannels(), w.getsampwidth()
        assert sw == 2 and nc == 2
        x = np.frombuffer(w.readframes(w.getnframes()), dtype='<i2').astype(np.float64).reshape(-1, nc)/32768
    return sr, x

def prepare(raw, dest):
    sr, x = read(raw)
    assert len(x) >= 30 * sr
    # Remove only initial silence: preserve the first musical attack and the performance's tempo.
    block = max(1, round(.01*sr))
    env = np.sqrt(np.mean(x[:len(x)//block*block].reshape(-1, block, 2)**2, axis=(1,2)))
    threshold = max(.0015, float(np.max(env))*.05)
    attacks = np.flatnonzero(env > threshold)
    assert len(attacks), 'Silent generation'
    start = max(0, int(attacks[0])*block-round(.004*sr))
    assert start <= 2*sr, 'Musical opening delayed more than two seconds'
    assert len(x)-start >= 30*sr
    x = x[start:start+30*sr].copy()
    x -= np.mean(x, axis=0)
    attack, release = round(.004*sr), round(.14*sr)
    x[:attack] *= np.linspace(0,1,attack)[:,None]
    x[-release:] *= np.linspace(1,0,release)[:,None]
    rms = float(np.sqrt(np.mean(x*x)))
    assert rms > .002
    x *= min(.14/rms, .92/float(np.max(np.abs(x))))
    with wave.open(str(dest), 'wb') as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(sr)
        w.writeframes((x*32767).astype('<i2').tobytes())
    opening = float(np.sqrt(np.mean(x[:sr]**2)))
    assert opening > .006, 'Opening too quiet'
    return {'duration_seconds': 30, 'sample_rate': sr, 'channels': 2,
            'trimmed_initial_silence_seconds': round(start/sr,4),
            'first_second_rms_dbfs': round(20*np.log10(opening),2),
            'rms_dbfs': round(20*np.log10(np.sqrt(np.mean(x*x))),2),
            'peak_dbfs': round(20*np.log10(np.max(np.abs(x))),2),
            'tempo_modified': False,
            'sha256': hashlib.sha256(dest.read_bytes()).hexdigest()}

def player_page(items, reports):
    available = {r['id'] for r in reports}
    body = ''
    menu_ids = ['4A', '5B', '6A']
    for arena, menu_id in zip(['Héliostat','Serre engloutie','Cœur d’horloge'], menu_ids):
        body += '<section><h2>'+html.escape(arena)+'</h2><details><summary>Thème de sélection validé · '+menu_id+'</summary><audio controls preload="none" src="references/'+menu_id+'.wav"></audio></details><div class="cards">'
        for t in items:
            if t['map'] != arena:
                continue
            body += '<article><span class="tag">COMBAT '+t['id']+' · '+str(t['target_bpm'])+' BPM visés</span><h3>'+html.escape(t['title'])+'</h3><p>'+html.escape(t['direction'])+'</p>'
            if t['id'] in available:
                body += '<audio controls preload="none" src="'+t['file']+'"></audio>'
            else:
                body += '<p class="pending">En préparation</p>'
            body += '</article>'
        body += '</div></section>'
    page = '''<!doctype html><html lang="fr"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Prototype 0 — musiques de combat</title><style>*{box-sizing:border-box}body{margin:0;background:#141719;color:#f1e9da;font:16px system-ui,sans-serif}main{max-width:1150px;padding:30px 24px;margin:auto}h1{font-size:32px;margin:10px 0}header p{color:#b3b5af;max-width:850px;line-height:1.6}.cards{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}section{margin:32px 0}h2{font-size:23px;border-left:3px solid #d7a354;padding-left:12px}section:nth-of-type(2) h2{border-color:#69b9a2}section:nth-of-type(3) h2{border-color:#aea1ce}article{background:#202628;border:1px solid #3a4141;border-radius:12px;padding:20px}h3{font-size:19px;margin:12px 0}.tag{color:#dfac69;font-size:12px;font-weight:700}article p{color:#b6bcb7;font-size:14px}audio{width:100%;margin-top:14px}details{margin-bottom:18px;padding:12px;background:#1b2123;border-radius:8px;color:#b4c1bb}details audio{max-width:420px;display:block}summary{cursor:pointer}footer,.pending{color:#9ba49e;font-size:13px}a{color:#80d1c0}@media(max-width:800px){.cards{grid-template-columns:1fr}main{padding:20px}}</style><main><header><p>PROTOTYPE 0 · ÉCOUTE COMPARATIVE</p><h1>Musiques de combat · 30 secondes</h1><p>Trois nouveaux choix par carte. Rythme rapide et entrée immédiate demandés à la génération. Les BPM affichés sont les objectifs de composition ; l’intensité et le rythme effectifs sont à juger à l’écoute.</p><p>Pour comparer, écoute les A, B et C puis indique par exemple : combat 4B / 5A / 6C. Les thèmes de sélection validés restent accessibles sous chaque carte.</p></header>'''+body+'''<footer>Stable Audio 3 Medium · maquettes originales, sans intégration au jeu. Durée, attaque, stéréo et absence de saturation vérifiées techniquement. Aucun changement de vitesse après génération.</footer></main><script>document.querySelectorAll('audio').forEach(a=>a.addEventListener('play',()=>document.querySelectorAll('audio').forEach(b=>{if(b!==a)b.pause()})));</script></html>'''
    (ROOT/'preview.html').write_text(page, encoding='utf-8')

def main():
    for folder in ['raw','previews','logs','references']:
        (ROOT/folder).mkdir(parents=True,exist_ok=True)
    for key in ['4A','5B','6A']:
        shutil.copyfile(ROOT.parent/'map-music-previews'/'previews'/(key+'.wav'),ROOT/'references'/(key+'.wav'))
    items = [{'id':key,'map':arena,'title':title,'direction':direction,'target_bpm':bpm,
              'seed':seed,'prompt':detail+COMMON,'file':'previews/'+key+'.wav'}
             for key,arena,title,direction,bpm,seed,detail in TRACKS]
    manifest = {'provider':'local Stability AI','model':'Stable Audio 3 Medium',
                'raw_duration_seconds':32,'preview_duration_seconds':30,
                'steps':8,'cfg':1.0,'threads':8,'integrated_in_game':False,
                'approved_selection_themes':{'heliostat':'4A','tideglass':'5B','clockwork':'6A'},'tracks':items}
    (ROOT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    reports = []
    player_page(items,reports)
    requested = set(sys.argv[1:])
    for item in items:
        if requested and item['id'] not in requested:
            continue
        raw = ROOT/'raw'/(item['id']+'.wav')
        if not raw.exists():
            print('GENERATING '+item['id'],flush=True)
            cmd = [str(PYTHON),str(CLI),'--dit','medium','--decoder','same-l','--seconds','32',
                   '--steps','8','--cfg','1','--seed',str(item['seed']),'--threads','8',
                   '--prompt',item['prompt'],'--out',str(raw)]
            with (ROOT/'logs'/(item['id']+'.log')).open('w',encoding='utf-8') as log:
                result = subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT)
            if result.returncode:
                raise RuntimeError('Generation failed: '+item['id'])
        report = {'id':item['id'],**prepare(raw,ROOT/item['file'])}
        reports.append(report)
        (ROOT/'verification.json').write_text(json.dumps({'technical_checks_only':True,'tracks':reports},indent=2),encoding='utf-8')
        player_page(items,reports)
        print('READY '+item['id']+' 30s',flush=True)
    if not requested:
        assert len(reports)==9 and len({r['sha256'] for r in reports})==9
        print('PACK_READY 9/9',flush=True)

if __name__ == '__main__':
    main()
