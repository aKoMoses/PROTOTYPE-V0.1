"""Nine local Stable Audio music auditions, outside gameplay assets."""
from pathlib import Path
import subprocess
import json
import wave
import hashlib
import html
import numpy as np

ROOT = Path(__file__).resolve().parent
RUNTIME = Path(r'C:\Users\BOTTEROOOW\Tools\stable-audio-3\optimized\tflite')
PYTHON = RUNTIME / '.venv/Scripts/python.exe'
CLI = RUNTIME / 'scripts/sa3_tflite.py'
COMMON = ('Original instrumental acoustic background score for a tactical robot duel. '
          'Restrained quiet opening, short musical phrases with rests, gentle tension building halfway, '
          'thin arrangement that leaves room for combat sounds, warm natural recorded instruments. '
          'No singing, no voices, no electronic synthesizers, no environmental sound effects. ')
NEGATIVE = 'vocals, singing, speech, synthesizer, EDM, electronic drums, dense orchestration, cymbal crashes, sound effects, ticking clocks, water, pumps, mechanical noises, distorted audio'
TRACKS = [
    ('4A', 'Héliostat', 'La ligne d’ombre', 'Chaleur et vigilance', 261003401,
     'Dry low oud plucked melody, sustained viola, soft frame drum. Sparse offbeat 92 BPM pulse. Hot dry sunlight, moving sheltering shadows. Begin with solo oud, add a gentle drum pulse, viola creates a suspended unresolved tension, retreat to sparse oud.'),
    ('4B', 'Héliostat', 'Midi de cuivre', 'Puissance solaire', 261003402,
     'Soft low French horns, cellos, felt piano, very occasional muffled timpani. Slow heavy 72 BPM. Spacious matte chamber orchestral score, vast solar installation, immense heat pressing down. Begin a quiet low piano note, add sustained cello harmony, a brief restrained horn opening, gently recede.'),
    ('4C', 'Héliostat', 'Deux pas dans la poussière', 'Duel mobile', 261003403,
     'Acoustic baritone guitar, pizzicato upright bass, very soft brushed snare, occasional guitar harmonics. Dry intimate acoustic desert duel score. Light syncopated 112 BPM sway. Start solo guitar, add bass, alternate two short nimble motifs with gaps, restrained movement and feints, no dramatic crescendo.'),
    ('5A', 'Serre engloutie', 'Racines sous verre', 'Beauté fragile', 261003501,
     'Low harp, bass clarinet, muted chamber strings. Gentle flowing 6/8 at 78 BPM. Soft suspended resonances, lush submerged botanical greenhouse, fragile beautiful islands. Sparse harp opening, incomplete bass clarinet melody enters, strings gradually turn harmony quietly uneasy, finish delicately.'),
    ('5B', 'Serre engloutie', 'Sous les feuilles', 'Embuscade feutrée', 261003502,
     'Upright bass, felt acoustic piano, low clarinet, very delicate brushed drums. Intimate dark acoustic chamber jazz at 96 BPM, slightly behind the beat, stealthy stalking rather than lounge music. Start bass alone and sparse piano chords, short cautious clarinet replies, then withdraw into spaces. Hidden opponent among wet greenhouse gardens.'),
    ('5C', 'Serre engloutie', 'Les passages verts', 'Circulation et poursuite', 261003503,
     'Low wooden marimba, muted nylon guitar, pizzicato cello, soft hand drums. Rounded acoustic timbres, nimble interlocking patterns at 108 BPM. Begin a three-note marimba cell, guitar answers with an offset phrase, cello adds a brief push before returning to the opening. Crossing routes between green islands, light tactical pursuit.'),
    ('6A', 'Cœur d’horloge', 'La treizième valse', 'Élégance inquiétante', 261003601,
     'Acoustic string quartet, bassoon, felt piano. Restrained eerie chamber waltz in 3/4 at 108 BPM. Precise soft pizzicato, short bowed phrases, subtly displaced accents. Start bassoon and plucked strings, introduce a poised little melody, fragment it, leave the underlying dance pulse. Elegant dangerous duel around a giant pendulum.'),
    ('6B', 'Cœur d’horloge', 'L’échappement', 'Précision nerveuse', 261003602,
     'Viola and cello ostinato, muted prepared acoustic piano, soft low drum. Dry articulated chamber music in 7/8 grouped 2+2+3 at 98 BPM. Start a spare repeated figure, gradually add displaced accents and change register, use clear musical rests, return to the sparse figure. Precise nervous anticipation in a vast brass clock mechanism.'),
    ('6C', 'Cœur d’horloge', 'Le poids des heures', 'Grandeur et menace', 261003603,
     'Real pipe organ using quiet soft stops, low cellos, muted French horns, very rare soft bass drum. Solemn restrained chamber score at 64 BPM, deep resonance but controlled bass. Begin almost solo quiet organ, cellos create slow motion, horns mark one brief modest summit, recede. An ancient massive steel and brass clock, each duel commitment matters.'),
]

def read_wav(path):
    with wave.open(str(path), 'rb') as w:
        sr, channels, width, n = w.getframerate(), w.getnchannels(), w.getsampwidth(), w.getnframes()
        if width != 2:
            raise ValueError('Expected PCM16')
        x = np.frombuffer(w.readframes(n), dtype='<i2').astype(np.float64).reshape(-1, channels) / 32768
    return sr, x

def prepare(source, dest):
    sr, x = read_wav(source)
    assert x.shape == (sr * 30, 2), (source, x.shape)
    x -= x.mean(axis=0)
    a, r = round(.4 * sr), round(1.0 * sr)
    x[:a] *= (np.sin(np.linspace(0, np.pi / 2, a)) ** 2)[:, None]
    x[-r:] *= (np.cos(np.linspace(0, np.pi / 2, r)) ** 2)[:, None]
    raw_rms = float(np.sqrt(np.mean(x*x)))
    assert raw_rms > .0001, 'Silent generation'
    gain = min(.09 / raw_rms, .88 / float(np.max(np.abs(x))))
    x *= gain
    with wave.open(str(dest), 'wb') as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(sr)
        w.writeframes((x * 32767).astype('<i2').tobytes())
    return {'duration_seconds': 30, 'sample_rate': sr, 'channels': 2,
            'rms_dbfs': round(20*np.log10(np.sqrt(np.mean(x*x))), 2),
            'peak_dbfs': round(20*np.log10(np.max(np.abs(x))), 2),
            'sha256': hashlib.sha256(dest.read_bytes()).hexdigest()}

def main():
    for folder in ['raw', 'logs', 'previews']:
        (ROOT / folder).mkdir(parents=True, exist_ok=True)
    items = [{'id': key, 'map': arena, 'title': title, 'direction': direction,
              'seed': seed, 'prompt': COMMON + detail,
              'file': 'previews/' + key + '.wav'}
             for key, arena, title, direction, seed, detail in TRACKS]
    manifest = {'provider': 'local Stability AI', 'model': 'Stable Audio 3 Small-Music',
                'duration_seconds': 30, 'steps': 8, 'cfg': 1.0, 'threads': 4,
                'negative_prompt': NEGATIVE, 'integrated_in_game': False, 'tracks': items}
    (ROOT / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    reports = []
    for item in items:
        raw = ROOT / 'raw' / (item['id'] + '.wav')
        if not raw.exists():
            print('GENERATING ' + item['id'], flush=True)
            cmd = [str(PYTHON), str(CLI), '--dit', 'sm-music', '--decoder', 'same-s',
                   '--seconds', '30', '--steps', '8', '--cfg', '1', '--seed', str(item['seed']),
                   '--threads', '4', '--prompt', item['prompt'], '--out', str(raw)]
            with (ROOT / 'logs' / (item['id'] + '.log')).open('w', encoding='utf-8') as log:
                result = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT)
            if result.returncode:
                raise RuntimeError('Generation failed: ' + item['id'])
        report = {'id': item['id'], **prepare(raw, ROOT / item['file'])}
        reports.append(report)
        (ROOT / 'verification.json').write_text(json.dumps({'technical_checks_only': True, 'tracks': reports}, indent=2), encoding='utf-8')
        print('READY ' + item['id'] + ' 30s', flush=True)
    assert len({x['sha256'] for x in reports}) == 9
    body = ''
    for arena in ['Héliostat', 'Serre engloutie', 'Cœur d’horloge']:
        body += '<section><h2>' + html.escape(arena) + '</h2><div class="cards">'
        for item in items:
            if item['map'] != arena:
                continue
            body += ('<article><span class="tag">' + item['id'] + ' · 30 s</span><h3>'
                     + html.escape(item['title']) + '</h3><p>' + html.escape(item['direction'])
                     + '</p><audio controls preload="none" src="' + item['file'] + '"></audio></article>')
        body += '</div></section>'
    page = '''<!doctype html><html lang="fr"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Prototype 0 — neuf directions musicales</title><style>
    *{box-sizing:border-box}body{margin:0;background:#141719;color:#f1e9da;font:16px system-ui,sans-serif}main{max-width:1120px;padding:32px 24px;margin:auto}h1{font-size:32px;margin:10px 0}header p{color:#b3b5af;max-width:780px;line-height:1.6}.cards{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}section{margin:32px 0}h2{font-size:23px;border-left:3px solid #c8a167;padding-left:12px}section:nth-of-type(2) h2{border-color:#69b9a2}section:nth-of-type(3) h2{border-color:#aea1ce}article{background:#202628;border:1px solid #3a4141;border-radius:12px;padding:20px}h3{font-size:19px;margin:12px 0}.tag{color:#d3b98b;font-size:13px;font-weight:700}article p{color:#b6bcb7;font-size:14px}audio{width:100%;margin-top:14px}footer{color:#9ba49e;font-size:13px}@media(max-width:800px){.cards{grid-template-columns:1fr}main{padding:20px}}
    </style><main><header><p>PROTOTYPE 0 · ÉCOUTE COMPARATIVE</p><h1>Neuf directions musicales</h1><p>Trois propositions par carte, chacune sur 30 secondes. Écoute les A, B et C, puis indique un choix par carte : par exemple 4A / 5B / 6C. Maquettes originales générées avec Stable Audio, sans intégration au jeu.</p></header>''' + body + '''<footer>Volume rapproché entre les extraits. Durée, stéréo et absence de saturation vérifiées techniquement. Instruments, rythme et caractère restent à juger à l’écoute.</footer></main><script>document.querySelectorAll('audio').forEach(a=>a.addEventListener('play',()=>document.querySelectorAll('audio').forEach(b=>{if(b!==a)b.pause()})));</script></html>'''
    (ROOT / 'preview.html').write_text(page, encoding='utf-8')
    print('PACK_READY 9/9', flush=True)

if __name__ == '__main__':
    main()
