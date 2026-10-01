"""Extract Stable Audio grains, prepare one loop and assemble audition files."""
import hashlib
import json
import wave
import numpy as np
from cues import ROOT, SR, CUES, MODULES

def read(path):
    with wave.open(str(path),"rb") as w:
        assert w.getframerate()==SR and w.getsampwidth()==2 and w.getnchannels()==2
        return np.frombuffer(w.readframes(w.getnframes()),dtype="<i2").astype(float).reshape(-1,2)/32768

def write(path,x):
    path.parent.mkdir(parents=True,exist_ok=True)
    assert np.isfinite(x).all() and np.max(np.abs(x))<.995
    with wave.open(str(path),"wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x*32767).astype("<i2").tobytes())

def rms(x):
    return float(np.sqrt(np.mean(x*x)))

def filter_audio(x):
    x=x-np.mean(x,axis=0)
    f=np.fft.rfftfreq(len(x),1/SR)
    h=1/(1+(45/np.maximum(f,.01))**6)/(1+(f/12000)**8)
    return np.fft.irfft(np.fft.rfft(x,axis=0)*h[:,None],n=len(x),axis=0)

def fades(x,attack=.002,release=.025):
    x=x.copy()
    a,r=min(round(attack*SR),len(x)//3),min(round(release*SR),len(x)//3)
    if a:
        x[:a]*=(np.sin(np.linspace(0,np.pi/2,a))**2)[:,None]
    if r:
        x[-r:]*=(np.cos(np.linspace(0,np.pi/2,r))**2)[:,None]
    return x

def extract(cue):
    source=ROOT/"raw"/(cue["id"]+".wav")
    raw=read(source)
    mono=np.mean(raw,axis=1)
    n=round(cue["duration"]*SR)
    window=round(.012*SR)
    power=np.convolve(mono*mono,np.ones(window)/window,mode="same")
    main=int(np.argmax(power))
    if cue["kind"]=="loop":
        cross=round(.055*SR)
        # Strongest sustained region, excluding the very beginning/end.
        scores=np.convolve(mono*mono,np.ones(n+cross)/(n+cross),mode="valid")
        start=int(np.argmax(scores))
        segment=filter_audio(raw[start:start+n+cross])
        w=np.linspace(0,1,cross)[:,None]
        x=np.concatenate((segment[cross:n],segment[n:n+cross]*(1-w)+segment[:cross]*w))
        main_offset=None
        seam=float(np.max(np.abs(x[0]-x[-1])))
    else:
        rising=cue["id"] in ["rocket-arm","projector-charge","counter-overload","eclipse-aim"]
        max_lead=cue["duration"]*.75 if rising else min(.065,cue["duration"]*.25)
        lower=max(0,main-round(max_lead*SR))
        start=main
        while start>lower and power[start]>float(power[main])*.06:
            start-=1
        start=max(0,start-round(.003*SR))
        x=raw[start:start+n]
        if len(x)<n:
            x=np.pad(x,((0,n-len(x)),(0,0)))
        x=filter_audio(x)
        if rising:
            x*=np.linspace(.20,1,len(x))[:,None]
        x=fades(x,.003 if rising else .0013,.025)
        main_offset=round((main-start)/SR,5)
        seam=None
    if rms(x)<.00015:
        raise ValueError("Near-silent source grain: "+cue["id"])
    peak=float(np.max(np.abs(x)))
    gain=min(10**(cue["rms_db"]/20)/rms(x), .72/max(peak,1e-9))
    x*=gain
    dest=ROOT/"candidates"/(cue["id"]+".wav")
    write(dest,x)
    return x,{
        "id":cue["id"],"module":cue["module"],"label":cue["label"],"kind":cue["kind"],"source":str(source.relative_to(ROOT)),"source_sha256":hashlib.sha256(source.read_bytes()).hexdigest(),
        "file":str(dest.relative_to(ROOT)),"sha256":hashlib.sha256(dest.read_bytes()).hexdigest(),"duration_seconds":len(x)/SR,"raw_crop_start_seconds":round(start/SR,5),"main_energy_peak_offset":main_offset,"loop_seam_delta_before_gain":seam,"rms_dbfs":round(20*np.log10(rms(x)),2),"gain_db":round(20*np.log10(gain),2),
        "visible_cause":cue["label"],"desired_association":MODULES[cue["module"]]["direction"],"forbidden_association":"speech, music, drill, jackhammer, siren, repeated unrelated impacts","heard_in_picture":"not claimed; awaiting user audition and later in-game synchronization","decision":"pending user audition"
    }

def reel(clips,events,duration):
    out=np.zeros((round(duration*SR),2))
    for event in events:
        clip=clips[event["id"]]*event.get("gain",1)
        offset=round(event["time"]*SR)
        out[offset:offset+len(clip)]+=clip
    gain=min(1,.79/max(float(np.max(np.abs(out))),1e-9))
    return fades(out*gain,.003,.03),gain

def main():
    clips={}; records=[]
    for cue in CUES:
        if not (ROOT/"raw"/(cue["id"]+".wav")).exists():
            print("WAITING "+cue["id"],flush=True)
            continue
        clips[cue["id"]],record=extract(cue)
        records.append(record)
    if len(clips)!=len(CUES):
        print("PARTIAL: "+str(len(clips))+"/"+str(len(CUES)),flush=True)
        return
    previews={}
    for module,definition in MODULES.items():
        isolated=[]; clock=.50
        for cue in CUES:
            if cue["module"]==module:
                isolated.append({"id":cue["id"],"label":cue["label"],"time":round(clock,4),"gain":1})
                clock+=cue["duration"]+.70
        scenario=[{"id":key,"time":when,"gain":gain} for key,when,gain in definition["scenario"]]
        end=max(e["time"]+len(clips[e["id"]])/SR for e in scenario)+.75
        previews[module]={}
        for kind,events,duration in [("isolated",isolated,clock+.10),("scenario",scenario,end)]:
            x,gain=reel(clips,events,duration)
            dest=ROOT/"previews"/(module+"-"+kind+".wav")
            write(dest,x)
            previews[module][kind]={"file":str(dest.relative_to(ROOT)),"events":events,"duration_seconds":len(x)/SR,"headroom_gain":gain,"sha256":hashlib.sha256(dest.read_bytes()).hexdigest()}
    manifest={"model":"Stable Audio 3 Small-SFX","provider":"local Stability AI","requests":"sound-sheet.json","sample_rate":SR,"channels":2,"bit_depth":16,"candidate_count":len(records),"preview_count":10,"integrated_in_game":False,"selection":"pending user audition","cues":records,"previews":previews,"timing_reference":{"rocket_basket_preparation":.30,"counter_preparation":.08,"counter_guard_duration":.8,"projector_cast":.18,"projector_push":.42,"permutation_preparation":.18,"permutation_travel":"0.12 to approximately 0.31 seconds depending on distance","eclipse_travel":.25},"preview_note":"Isolated reels intentionally space effects for listening. Scenario reels illustrate timing, not a live gameplay recording."}
    (ROOT/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")
    print("READY 22 Stable Audio candidates and 10 audition reels",flush=True)

if __name__=="__main__":
    main()
