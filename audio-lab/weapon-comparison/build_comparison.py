"""Original hand-built SFX, trimmed Stable sources and matched audition reels.

Uses seeded noise, inharmonic resonators and envelopes, not an audio model for A.
All candidates remain outside the game's audio paths. Human audition is pending.
"""
import hashlib
import json
import wave
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parent
SR = 44100
RNG = np.random.default_rng(261001)
SPEC = {
    "mekatana-windup": (.12, -25),
    "mekatana-slash-1": (.18, -22),
    "mekatana-slash-2": (.23, -20),
    "mekatana-slash-3": (.32, -17.5),
    "mekatana-impact-1": (.22, -22),
    "mekatana-impact-2": (.28, -20),
    "mekatana-impact-3": (.42, -17.5),
    "longshot-shot": (.65, -18),
    "longshot-enhanced": (.85, -16),
    "longshot-ready": (.22, -27),
}

def write(path, audio):
    path.parent.mkdir(parents=True, exist_ok=True)
    audio = np.asarray(audio)
    if audio.ndim == 1:
        audio = np.column_stack((audio, audio))
    assert np.isfinite(audio).all()
    assert np.max(np.abs(audio)) < .995, str(path)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((audio.clip(-.999, .999) * 32767).astype("<i2").tobytes())

def read(path):
    with wave.open(str(path), "rb") as w:
        assert w.getsampwidth() == 2
        rate, channels = w.getframerate(), w.getnchannels()
        x = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(float).reshape(-1, channels) / 32768
    if channels == 1:
        x = np.repeat(x, 2, axis=1)
    if rate != SR:
        n = round(len(x) * SR / rate)
        x = np.column_stack([np.interp(np.arange(n) * rate / SR, np.arange(len(x)), x[:, ch]) for ch in range(2)])
    return x

def band(x, low=55, high=11000):
    f = np.fft.rfftfreq(len(x), 1/SR)
    h = (1 / (1 + (low / np.maximum(f, .01)) ** 6)) * (1 / (1 + (f / high) ** 8))
    spec = np.fft.rfft(x, axis=0)
    return np.fft.irfft(spec * (h if x.ndim == 1 else h[:, None]), n=len(x), axis=0)

def fade(x, attack=.002, release=.02):
    x = x.copy()
    a, r = min(int(attack*SR), len(x)//3), min(int(release*SR), len(x)//3)
    shape = (slice(None),) if x.ndim == 1 else (slice(None), None)
    if a:
        x[:a] *= np.sin(np.linspace(0, np.pi/2, a)) ** 2 if x.ndim == 1 else (np.sin(np.linspace(0, np.pi/2, a)) ** 2)[:, None]
    if r:
        x[-r:] *= np.cos(np.linspace(0, np.pi/2, r)) ** 2 if x.ndim == 1 else (np.cos(np.linspace(0, np.pi/2, r)) ** 2)[:, None]
    return x

def timeline(duration):
    return np.arange(round(duration * SR)) / SR

def noise(t, low, high):
    return band(RNG.normal(0, 1, len(t)), low, high)

def metal(t, root, decay, amount=1):
    y = np.zeros(len(t))
    # Inharmonic partials give a struck steel body, not a musical chord.
    for ratio, amp in [(1, 1), (1.483, .57), (2.173, .32), (3.619, .19), (5.213, .10)]:
        y += amp * np.sin(2*np.pi*root*ratio*t + .13*ratio) * np.exp(-t / (decay / np.sqrt(ratio)))
    return amount * y

def stereo(x, texture=.07):
    side = band(RNG.normal(0, .04, len(x)), 1100, 8500) * np.abs(x) * texture
    return np.column_stack((x + side, x - side))

def handbuilt():
    result = {}
    t = timeline(.12)
    env = np.sin(np.pi * np.minimum(t/.115, 1)) ** .8
    charge = .17*noise(t, 550, 7200)*env + .17*metal(t, 1230, .08)*np.minimum(t/.04, 1)
    result["mekatana-windup"] = stereo(fade(charge, .007, .012))
    for rank, duration in enumerate([.18, .23, .32]):
        t = timeline(duration)
        # Air blade gesture plus an irregular arc; no continuous electric buzz.
        envelope = np.exp(-((t - (.042 + rank*.012))/(.035 + rank*.01)) ** 2)
        air = noise(t, 360-rank*80, 6800-rank*700) * envelope * .65
        edge = noise(t, 3400, 12500) * np.exp(-((t-.065-rank*.015)/.014)**2) * .16
        arc = np.zeros(len(t))
        for offset, amp in [(.048, .12), (.076, .09), (.099+rank*.01, .06)]:
            arc += noise(t, 2300, 13000)*np.exp(-np.abs(t-offset)/.0025)*amp
        body = metal(t, 590-rank*95, .045+rank*.012, .055)*np.minimum(t/.014,1)
        result[f"mekatana-slash-{rank+1}"] = stereo(fade(air+edge+arc+body))
        t = timeline([.22,.28,.42][rank])
        contact = noise(t, 420, 11500)*np.exp(-t/(.010+rank*.005))*.60
        armor = metal(t, 730-rank*125, .06+rank*.025, .24)
        punch = np.sin(2*np.pi*(120*t + 25*.021*(1-np.exp(-t/.021))))*np.exp(-t/(.032+rank*.014))*.17
        spark = noise(t, 3500, 14500)*np.exp(-t/.017)*.19
        result[f"mekatana-impact-{rank+1}"] = stereo(fade(contact+armor+punch+spark, .0006, .028))
    for enhanced, key in [(False,"longshot-shot"),(True,"longshot-enhanced")]:
        t = timeline(SPEC[key][0])
        # A physical report: initial crack, low body, short chassis resonance.
        crack = noise(t, 1000, 14500)*np.exp(-t/(.008 if not enhanced else .012))*.75
        pressure = noise(t, 75, 1900)*np.exp(-t/(.033 if not enhanced else .049))*.43
        bass = np.sin(2*np.pi*(68*t + 84*.017*(1-np.exp(-t/.017)))) * np.exp(-t/(.055 if not enhanced else .078)) * .36
        chassis = metal(t, 460 if not enhanced else 365, .065, .10)
        mechanical = np.zeros(len(t))
        for when, freq, gain in [(.09, 1380, .14),(.138, 890, .08)]:
            tt=np.maximum(t-when,0)
            mechanical += (t>=when)*(metal(tt, freq, .014, gain)+noise(t,1800,7000)*np.exp(-tt/.006)*(t>=when)*gain)
        air = noise(t, 800, 6800)*np.exp(-t/.12)*.05
        extra = noise(t, 2500, 14000)*np.exp(-t/.026)*.18 if enhanced else 0
        result[key] = stereo(fade(crack+pressure+bass+chassis+mechanical+air+extra,.00035,.03))
    t=timeline(.22)
    latch=np.zeros(len(t))
    for when, freq, amp in [(0,1700,.16),(.056,2600,.11)]:
        tt=np.maximum(t-when,0)
        latch += (t>=when)*metal(tt,freq,.012,amp)
    result["longshot-ready"] = stereo(fade(latch,.0006,.02))
    return result

def extract(path, duration, key):
    x=read(path)
    mono=np.mean(x,axis=1)
    window=round(.015*SR)
    energy=np.convolve(mono**2,np.ones(window)/window,mode="same")
    peak=int(np.argmax(energy))
    threshold=float(energy[peak])*.06
    start=peak
    # Find the onset of the main audible grain, preserving the attack.
    # Short game accents must actually include the strongest transient.
    # A long noisy lead-in must not consume the whole retained interval.
    lower=max(0,peak-round(min(.06,duration*.22)*SR))
    while start>lower and energy[start]>threshold:
        start-=1
    start=max(0,start-round(.004*SR))
    n=round(duration*SR)
    y=x[start:start+n]
    if len(y)<n:
        y=np.pad(y,((0,n-len(y)),(0,0)))
    return fade(band(y), .0015 if "impact" in key or "shot" in key else .003, .025), {"source":str(path.relative_to(ROOT)), "start_seconds":round(start/SR,5),"end_seconds":round(min(start+n,len(x))/SR,5),"main_energy_peak_offset":round((peak-start)/SR,5),"raw_peak":round(float(np.max(np.abs(x))),6)}

def rms(x):
    return float(np.sqrt(np.mean(x*x)))

def match_pair(a,b,target_db):
    target=10**(target_db/20)
    ap,bp=max(float(np.max(np.abs(a))),1e-9),max(float(np.max(np.abs(b))),1e-9)
    ar,br=max(rms(a),1e-9),max(rms(b),1e-9)
    # Same duration and RMS for each corresponding cue, with peak headroom.
    level=min(target, ar*.79/ap, br*.79/bp)
    return a*(level/ar),b*(level/br),20*np.log10(level)

def mix(candidates,weapon):
    duration=8.5 if weapon=="mekatana" else 6.4
    out=np.zeros((round(duration*SR),2))
    events=[]
    def add(key,when,gain=1):
        clip=candidates[key]*gain
        start=round(when*SR)
        out[start:start+len(clip)] += clip
        events.append({"cue":key,"time":round(when,3),"gain":gain})
    if weapon=="mekatana":
        # First combo misses; second combo connects. Deliberate gaps aid audition.
        for hits,base in [(False,.55),(True,4.65)]:
            for rank,offset in enumerate([0,.85,1.8],start=1):
                prep=[.12,.14,.18][rank-1]
                add("mekatana-windup",base+offset,[.85,1,1.15][rank-1])
                add(f"mekatana-slash-{rank}",base+offset+prep)
                if hits:
                    add(f"mekatana-impact-{rank}",base+offset+prep+.035)
    else:
        for i in range(5):
            add("longshot-enhanced" if i==4 else "longshot-shot",.6+i*1.05)
        add("longshot-ready",4.35)
    return out,events

def main():
    for folder in ["raw/local","candidates/A-codex","candidates/B-stable","previews","reports"]:
        (ROOT/folder).mkdir(parents=True,exist_ok=True)
    originals=handbuilt()
    pairs={"A":{},"B":{}}
    manifest={"sample_rate":SR,"channels":2,"bit_depth":16,"selection":"pending human audition","integrated_in_game":False,"A":{"method":"Original seeded procedural sound design: filtered air/noise, physical attack envelopes, inharmonic steel resonators, pressure impulse and irregular spark transients.","seed":261001},"B":{"model":"Stable Audio 3 Small-SFX","provider":"local Stability AI optimized TFLite","requests":"stable-requests.json"},"cues":[],"previews":{}}
    for key,(duration,target) in SPEC.items():
        raw=fade(band(originals[key]))
        raw*=.76/max(float(np.max(np.abs(raw))),1e-9)
        write(ROOT/"raw/local"/(key+".wav"),raw)
        stable_path=ROOT/"raw/stable"/(key+".wav")
        if not stable_path.exists():
            print("WAITING "+key,flush=True)
            continue
        stable,interval=extract(stable_path,duration,key)
        if rms(stable)<.0001:
            raise ValueError("Near-silent Stable grain: "+key)
        a,b,db=match_pair(raw,stable,target)
        pairs["A"][key]=a
        pairs["B"][key]=b
        record={"id":key,"duration":duration,"matched_rms_dbfs":round(db,2),"stable_extraction":interval,"files":{}}
        for label,folder,clip in [("A","A-codex",a),("B","B-stable",b)]:
            dest=ROOT/"candidates"/folder/(key+".wav")
            write(dest,clip)
            record["files"][label]={"path":str(dest.relative_to(ROOT)),"sha256":hashlib.sha256(dest.read_bytes()).hexdigest()}
        manifest["cues"].append(record)
    if len(pairs["A"])!=len(SPEC):
        print("PARTIAL candidates; rerun after generation completes",flush=True)
        return
    for weapon in ["mekatana","longshot"]:
        a,events=mix(pairs["A"],weapon)
        b,_=mix(pairs["B"],weapon)
        common=min(1,.79/max(float(np.max(np.abs(a))),float(np.max(np.abs(b)))))
        for label,clip in [("A",a),("B",b)]:
            dest=ROOT/"previews"/(weapon+"-"+label+".wav")
            write(dest,clip*common)
        manifest["previews"][weapon]={"events":events,"common_headroom_gain":round(common,5)}
    (ROOT/"manifest.json").write_text(json.dumps(manifest,indent=2),encoding="utf-8")
    print("READY 20 candidate WAVs and 4 matched audition reels",flush=True)

if __name__=="__main__":
    main()
