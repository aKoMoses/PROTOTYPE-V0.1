import hashlib
import json
import subprocess
import numpy as np
from design import ROOT,INSPECT_PYTHON,INSPECTOR
from prepare import read,rms

def inspect(paths,kind,name):
 run=subprocess.run([str(INSPECT_PYTHON),str(INSPECTOR),*[str(p) for p in paths],"--kind",kind,"--strict","--json"],capture_output=True,text=True)
 (ROOT/"reports"/name).write_text(run.stdout,encoding="utf-8")
 if run.returncode:raise SystemExit("REJECT "+name+": "+run.stderr)

def main():
 m=json.loads((ROOT/"manifest.json").read_text(encoding="utf-8"))
 inspect([ROOT/c["file"] for c in m["cues"] if c["kind"]=="accent"],"accent","strict-accents.json")
 inspect([ROOT/c["file"] for c in m["cues"] if c["kind"]=="loop"],"ambience","strict-loops.json")
 previews=[ROOT/p["file"] for module in m["previews"].values() for p in module.values()]
 inspect(previews,"accent","strict-previews.json")
 checks=[]
 for cue in m["cues"]:
  path=ROOT/cue["file"];x=read(path)
  assert hashlib.sha256(path.read_bytes()).hexdigest()==cue["sha256"]
  assert hashlib.sha256((ROOT/cue["source"]).read_bytes()).hexdigest()==cue["source_sha256"]
  assert np.isfinite(x).all() and np.max(np.abs(x))<.80 and rms(x)>.006
  assert cue["source_rms_dbfs"]>-42 and cue["gain_db"]<=10
  if cue["kind"]=="loop":
   delta=float(np.max(np.abs(x[0]-x[-1])));typical=float(np.percentile(np.max(np.abs(np.diff(x,axis=0)),axis=1),99))
   assert delta<max(.003,typical*1.5)
  else:
   delta=None
   assert 0<=cue["main_peak_offset"]<cue["duration_seconds"]
   assert np.max(np.abs(x[0]))<.0001 and np.max(np.abs(x[-1]))<.0001
  checks.append({"id":cue["id"],"status":"pass","source_rms_dbfs":cue["source_rms_dbfs"],"gain_db":cue["gain_db"],"duration":cue["duration_seconds"],"loop_seam_difference":delta})
 for path in previews:assert rms(read(path))>.009
 report={"status":"pass","candidate_count":8,"preview_count":4,"generator":"Stable Audio","checks":checks,"user_validation":"pending","in_game_validation":"not performed; not integrated"}
 (ROOT/"reports/integrity.json").write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
 print("PASS 8 sources/candidates + 4 previews; no weak-source boosts, clipping or invalid loop seam")

if __name__=="__main__":main()
