import hashlib,json,subprocess
import numpy as np
from design import ROOT,INSPECT_PYTHON,INSPECTOR
from prepare import read,rms

def main():
 m=json.loads((ROOT/"manifest.json").read_text(encoding="utf-8"))
 assert len(m["cues"])==1 and list(m["modules"])==["eclipse"]
 paths=[ROOT/c["file"] for c in m["cues"]]
 paths.extend(ROOT/p["file"] for p in m["previews"]["eclipse"].values())
 run=subprocess.run([str(INSPECT_PYTHON),str(INSPECTOR),*[str(p) for p in paths],"--kind","accent","--strict","--json"],capture_output=True,text=True)
 (ROOT/"reports/strict.json").write_text(run.stdout,encoding="utf-8")
 if run.returncode:raise SystemExit("REJECT "+run.stderr)
 for cue in m["cues"]:
  x=read(ROOT/cue["file"])
  assert hashlib.sha256((ROOT/cue["file"]).read_bytes()).hexdigest()==cue["sha256"]
  assert hashlib.sha256((ROOT/cue["source"]).read_bytes()).hexdigest()==cue["source_sha256"]
  assert np.isfinite(x).all() and np.max(np.abs(x))<.8 and rms(x)>.006
  assert cue["source_rms_dbfs"]>-42 and cue["gain_db"]<=10
  assert np.max(np.abs(x[0]))<.0001 and np.max(np.abs(x[-1]))<.0001
 report={"status":"pass","candidate_count":1,"generator":"Stable Audio 3 Small-SFX","user_validation":"pending","integrated_in_game":False,"checks":["Strict inspection","RIFF stereo 44.1 kHz","Source and candidate SHA256","Source energy and gain limits","No clipping; edge fades"]}
 (ROOT/"reports/integrity.json").write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
 print("PASS one Eclipse arrival proposal; technical checks only")

if __name__=="__main__":main()
