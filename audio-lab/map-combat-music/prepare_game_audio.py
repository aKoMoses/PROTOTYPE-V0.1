"""Preserve selected performances and bake a short tail-to-head loop blend."""
from pathlib import Path
import wave
import hashlib
import json
import numpy as np

ROOT = Path(__file__).resolve().parent
GAME = ROOT.parent.parent
CHOICES = {'heliostat':('4A','4C','4A'),'tideglass':('5B','5C','5A'),'clockwork':('6A','6A','6B')}
COMBAT_REPORT = {t['id']:t for t in json.loads((ROOT/'verification.json').read_text())['tracks']}

def load(path):
    with wave.open(str(path),'rb') as w:
        sr=w.getframerate()
        assert w.getnchannels()==2 and w.getsampwidth()==2
        x=np.frombuffer(w.readframes(w.getnframes()),dtype='<i2').astype(float).reshape(-1,2)/32768
    return sr,x

def main():
    dest=GAME/'art/audio/maps'
    dest.mkdir(parents=True,exist_ok=True)
    records=[]
    for arena,(selection,combat,alternate) in CHOICES.items():
        for kind,key in [('selection',selection),('combat',combat),('combat_alternate',alternate)]:
            source=(ROOT.parent/'map-music-previews' if kind=='selection' else ROOT)/'raw'/(key+'.wav')
            sr,x=load(source)
            start=round(COMBAT_REPORT[key]['trimmed_initial_silence_seconds']*sr) if kind!='selection' else 0
            x=x[start:start+30*sr].copy()
            assert len(x)==30*sr
            x-=x.mean(axis=0)
            ramp=round(.004*sr)
            x[:ramp]*=np.linspace(0,1,ramp)[:,None]
            overlap=round(.12*sr)
            weight=np.linspace(0,1,overlap)[:,None]
            x[-overlap:]=x[-overlap:]*(1-weight)+x[:overlap]*weight
            target=.14 if kind!='selection' else .09
            x*=min(target/np.sqrt(np.mean(x*x)),.92/np.max(np.abs(x)))
            output=dest/(arena+'_'+kind+'.wav')
            with wave.open(str(output),'wb') as w:
                w.setnchannels(2);w.setsampwidth(2);w.setframerate(sr)
                w.writeframes((x*32767).astype('<i2').tobytes())
            seam=float(np.max(np.abs(x[-1]-x[overlap])))
            assert seam < .06,(output,seam)
            records.append({'arena':arena,'kind':kind,'choice':key,'source':str(source.relative_to(GAME)),
                            'path':str(output.relative_to(GAME)), 'duration_seconds':30,
                            'loop_begin_seconds':.12,'loop_seam_max_delta':round(seam,6),
                            'sha256':hashlib.sha256(output.read_bytes()).hexdigest()})
            print('READY '+output.name)
    manifest={'approved_by_user':True,'integrated_in_game':True,'tracks':records,
              'combat_alternate_choices':{'heliostat':'4A','tideglass':'5A','clockwork':'6B'},
              'alternate_selection':'assistant selected at user request',
              'combat_schedule':'primary 0-30s, alternate 30-60s, primary 60-90s; repeat, live unpaused round time'}
    (ROOT/'selection.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    selection=json.loads((ROOT.parent/'map-music-previews/selection.json').read_text())
    selection['integrated_in_game']=True
    selection['combat_tracks']={'heliostat':'4C','tideglass':'5C','clockwork':'6A'}
    (ROOT.parent/'map-music-previews/selection.json').write_text(json.dumps(selection,ensure_ascii=False,indent=2),encoding='utf-8')

if __name__=='__main__':
    main()
