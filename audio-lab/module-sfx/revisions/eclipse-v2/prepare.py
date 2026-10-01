"""Retain natural Stable Audio gestures, not normalized scraps of quiet noise."""
import hashlib
import json
import wave
import numpy as np
from design import ROOT,SR,CUES,MODULES

def read(path):
 with wave.open(str(path),"rb") as w:
  assert w.getframerate()==SR and w.getsampwidth()==2 and w.getnchannels()==2
  return np.frombuffer(w.readframes(w.getnframes()),dtype="<i2").astype(float).reshape(-1,2)/32768

def rms(x):return float(np.sqrt(np.mean(x*x)))

def write(path,x):
 path.parent.mkdir(parents=True,exist_ok=True)
 assert np.isfinite(x).all() and np.max(np.abs(x))<.995
 with wave.open(str(path),"wb") as w:
  w.setnchannels(2);w.setsampwidth(2);w.setframerate(SR)
  w.writeframes((x*32767).astype("<i2").tobytes())

def fades(x,a=.0015,r=.025):
 x=x.copy();na=min(round(a*SR),len(x)//3);nr=min(round(r*SR),len(x)//3)
 x[:na]*=(np.sin(np.linspace(0,np.pi/2,na))**2)[:,None]
 x[-nr:]*=(np.cos(np.linspace(0,np.pi/2,nr))**2)[:,None]
 return x

def clean(x):
 x=x-np.mean(x,axis=0)
 f=np.fft.rfftfreq(len(x),1/SR)
 h=1/(1+(35/np.maximum(f,.001))**6)/(1+(f/14500)**8)
 return np.fft.irfft(np.fft.rfft(x,axis=0)*h[:,None],n=len(x),axis=0)

def natural_grain(raw,cue):
 if "source_interval" in cue:
  start,end=[round(t*SR) for t in cue["source_interval"]]
  region=raw[start:end]
  block=round(.005*SR)
  p=np.mean(region[:len(region)//block*block].reshape(-1,block,2)**2,axis=(1,2))
  return region,start,end,start+int(np.argmax(p))*block
 block=round(.005*SR)
 e=np.mean(raw[:len(raw)//block*block].reshape(-1,block,2)**2,axis=(1,2))
 peak=int(np.argmax(e));threshold=max(float(e[peak])*.025,float(np.median(e))*.8)
 first=peak;last=peak;gap=0
 for i in range(peak-1,-1,-1):
  gap=gap+1 if e[i]<threshold else 0
  if gap>=5:break
  first=i
 gap=0
 for i in range(peak+1,len(e)):
  gap=gap+1 if e[i]<threshold else 0
  if gap>=8:break
  last=i
 start=max(0,first*block-round(.006*SR))
 end=min(len(raw),(last+1)*block+round(.05*SR))
 maximum=round(cue["maximum_duration"]*SR)
 # If a generation is a sustained texture, choose a bounded gesture with
 # its main attack inside it; record the actual interval for review.
 if end-start>maximum:
  main=peak*block
  if main-start>maximum*.65:start=max(0,main-round(maximum*.40))
  end=min(len(raw),start+maximum)
 if end-start<round(.10*SR):end=min(len(raw),start+round(.12*SR))
 return raw[start:end],start,end,peak*block

def extract(cue):
 path=ROOT/"raw"/(cue["id"]+".wav");raw=read(path)
 if cue["kind"]=="loop":
  n=round(cue["maximum_duration"]*SR);cross=round(.055*SR)
  # Cumulative sums avoid the long dense convolution used in the old batch.
  p=np.mean(raw*raw,axis=1);c=np.concatenate(([0],np.cumsum(p)))
  scores=(c[n+cross:]-c[:-(n+cross)])/(n+cross)
  start=int(np.argmax(scores));end=start+n+cross
  x=clean(raw[start:end]);w=np.linspace(0,1,cross)[:,None]
  x=np.concatenate((x[cross:n],x[n:n+cross]*(1-w)+x[:cross]*w))
  offset=None
 else:
  x,start,end,main=natural_grain(raw,cue);x=fades(clean(x));offset=round((main-start)/SR,5)
 source_rms=rms(x)
 # Reject quiet scraps rather than boosting them into a generic hiss.
 if source_rms<.008:raise ValueError("SOURCE TOO WEAK: "+cue["id"]+f" RMS {source_rms:.5f}; regenerate")
 gain=min(10**(cue["rms_db"]/20)/source_rms,.77/max(float(np.max(np.abs(x))),1e-9))
 if gain>10**(10/20):raise ValueError("EXCESS GAIN: "+cue["id"])
 x*=gain
 dest=ROOT/"candidates"/(cue["id"]+".wav");write(dest,x)
 return x,{"id":cue["id"],"module":cue["module"],"label":cue["label"],"meaning":cue["meaning"],"kind":cue["kind"],"file":str(dest.relative_to(ROOT)),"sha256":hashlib.sha256(dest.read_bytes()).hexdigest(),"source":str(path.relative_to(ROOT)),"source_sha256":hashlib.sha256(path.read_bytes()).hexdigest(),"source_interval_seconds":[round(start/SR,5),round(end/SR,5)],"duration_seconds":len(x)/SR,"main_peak_offset":offset,"source_rms_dbfs":round(20*np.log10(source_rms),2),"gain_db":round(20*np.log10(gain),2),"output_rms_dbfs":round(20*np.log10(rms(x)),2),"envelope":"natural source envelope; only short edge fades; no universal rising ramp","decision":"pending user listening"}

def reel(clips,events,duration):
 x=np.zeros((round(duration*SR),2))
 for e in events:
  clip=clips[e["id"]]*e.get("gain",1);start=round(e["time"]*SR)
  x[start:start+len(clip)]+=clip
 gain=min(1,.79/max(float(np.max(np.abs(x))),1e-9))
 return fades(x*gain,.002,.03),gain

def main():
 clips={};records=[]
 for cue in CUES:
  if not (ROOT/"raw"/(cue["id"]+".wav")).exists():print("WAITING "+cue["id"]);continue
  clips[cue["id"]],record=extract(cue);records.append(record)
 if len(records)!=len(CUES):print("PARTIAL");return
 previews={}
 for module,info in MODULES.items():
  clock=.45;isolated=[]
  for cue in CUES:
   if cue["module"]==module:
    isolated.append({"id":cue["id"],"time":round(clock,4),"gain":1})
    clock+=len(clips[cue["id"]])/SR+.85
  scenario=[{"id":key,"time":time,"gain":gain} for key,time,gain in info["scenario"]]
  end=max(e["time"]+len(clips[e["id"]])/SR for e in scenario)+.80
  previews[module]={}
  for kind,events,duration in [("isolated",isolated,clock+.10),("scenario",scenario,end)]:
   x,gain=reel(clips,events,duration);dest=ROOT/"previews"/(module+"-"+kind+".wav");write(dest,x)
   previews[module][kind]={"file":str(dest.relative_to(ROOT)),"events":events,"duration_seconds":len(x)/SR,"headroom_gain":gain,"sha256":hashlib.sha256(dest.read_bytes()).hexdigest()}
 manifest={"revision":2,"model":"Stable Audio 3 Small-SFX","module_count":1,"candidate_count":1,"integrated_in_game":False,"selection":"pending user listening","modules":MODULES,"cues":records,"previews":previews,"review_boundary":"Proposals with technical checks; no self-hearing or live-game acceptance claimed."}
 (ROOT/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")
 print("READY 1 new effect, 2 listening reels; natural gestures and source signal gate")

if __name__=="__main__":main()
