"""Generate one Stable Audio candidate per requested cue; preserve raw bytes."""
import json
import subprocess
import sys
from cues import ROOT, PYTHON, CLI, CUES, MODULES, NEGATIVE

def main():
    for name in ["raw","candidates","previews","reports"]:
        (ROOT/name).mkdir(parents=True,exist_ok=True)
    spec={"model":"Stable Audio 3 Small-SFX","provider":"local Stability AI","runtime":"official optimized TFLite","generation_seconds":4,"steps":8,"cfg":1.0,"negative_prompt":NEGATIVE,"integrated_in_game":False,"selection":"pending user audition","modules":MODULES,"cues":CUES}
    (ROOT/"sound-sheet.json").write_text(json.dumps(spec,ensure_ascii=False,indent=2),encoding="utf-8")
    requested=set(sys.argv[1:])
    for cue in CUES:
        if requested and cue["id"] not in requested:
            continue
        path=ROOT/"raw"/(cue["id"]+".wav")
        if path.exists():
            print("EXISTS "+cue["id"],flush=True)
            continue
        print("GENERATING "+cue["id"],flush=True)
        cmd=[str(PYTHON),str(CLI),"--dit","sm-sfx","--decoder","same-s","--seconds","4","--steps","8","--cfg","1","--seed",str(cue["seed"]),"--threads","8","--prompt",cue["prompt"],"--negative-prompt",NEGATIVE,"--out",str(path)]
        with (ROOT/"reports"/(cue["id"]+"-generation.log")).open("w",encoding="utf-8") as log:
            run=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT)
        if run.returncode:
            raise SystemExit("FAILED "+cue["id"]+": inspect generation log")
        print("RAW_READY "+cue["id"],flush=True)

if __name__=="__main__":
    main()
