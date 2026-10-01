import json
import subprocess
import sys
from design import ROOT,PYTHON,CLI,NEGATIVE,CUES,MODULES

def main():
 for folder in ["raw","candidates","previews","reports"]:
  (ROOT/folder).mkdir(parents=True,exist_ok=True)
 (ROOT/"sound-sheet.json").write_text(json.dumps({"model":"Stable Audio 3 Small-SFX","runtime":"local official optimized TFLite","generation_seconds":4,"steps":8,"cfg":1.0,"negative_prompt":NEGATIVE,"negative_prompt_note":"At CFG 1 the negative branch is not used; exclusions are stated in each positive prompt as well.","rejected_previous_batch":True,"direction":"Complete physical gestures, distinct causal roles; no universal envelope or notification beep.","modules":MODULES,"cues":CUES,"integrated_in_game":False},ensure_ascii=False,indent=2),encoding="utf-8")
 selected=set(sys.argv[1:])
 for cue in CUES:
  if selected and cue["id"] not in selected: continue
  path=ROOT/"raw"/(cue["id"]+".wav")
  if path.exists():
   print("EXISTS "+cue["id"],flush=True);continue
  print("GENERATING "+cue["id"],flush=True)
  cmd=[str(PYTHON),str(CLI),"--dit","sm-sfx","--decoder","same-s","--seconds","4","--steps","8","--cfg","1","--seed",str(cue["seed"]),"--threads","8","--prompt",cue["prompt"],"--negative-prompt",NEGATIVE,"--out",str(path)]
  with (ROOT/"reports"/(cue["id"]+"-generation.log")).open("w",encoding="utf-8") as log:
   run=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT)
  if run.returncode: raise SystemExit("FAILED "+cue["id"])
  print("RAW_READY "+cue["id"],flush=True)

if __name__=="__main__":main()
