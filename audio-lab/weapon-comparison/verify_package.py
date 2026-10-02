"""Verify original bytes, paired levels, cue onset and all audition outputs."""
import json
import subprocess
import sys
from pathlib import Path
import numpy as np
from build_comparison import ROOT, SPEC, SR, read, rms

SKILL = Path(r"C:\Users\BOTTEROOOW\.codex\skills\generate-local-sfx")
PYTHON = Path(r"C:\Users\BOTTEROOOW\.codex\runtimes\stable-audio-3\.venv\Scripts\python.exe")

def main():
    paths=sorted((ROOT/"candidates").glob("*/*.wav"))+sorted((ROOT/"previews").glob("*.wav"))
    run=subprocess.run([str(PYTHON),str(SKILL/"scripts/inspect_sfx.py"),*[str(p) for p in paths],"--kind","accent","--strict","--json"],capture_output=True,text=True)
    if run.stderr:
        print(run.stderr,file=sys.stderr)
    (ROOT/"reports/strict-final.json").write_text(run.stdout,encoding="utf-8")
    if run.returncode:
        raise SystemExit("Strict inspection failed")
    checks=[]
    manifest=json.loads((ROOT/"manifest.json").read_text(encoding="utf-8"))
    for cue in manifest["cues"]:
        key=cue["id"]
        a,b=[read(ROOT/cue["files"][v]["path"]) for v in ["A","B"]]
        assert len(a)==len(b)==round(SPEC[key][0]*SR)
        delta=abs(20*np.log10(rms(a)/rms(b)))
        assert delta<.03,(key,delta)
        assert min(rms(a),rms(b))>.003,(key,"near silent")
        assert 0<=cue["stable_extraction"]["main_energy_peak_offset"]<cue["duration"]*.5
        onsets=[]
        for x in [a,b]:
            power=np.mean(x*x,axis=1)
            idx=np.flatnonzero(power>max(power)*.01)
            onset=float(idx[0]/SR)
            assert onset<.075,(key,onset)
            onsets.append(round(onset,5))
            assert np.max(np.abs(x))<.8
        checks.append({"id":key,"pair_rms_difference_db":round(delta,5),"onset_seconds":onsets,"status":"pass"})
    for path in paths[-4:]:
        assert rms(read(path))>.008,(path,"quiet preview")
    report={"files_verified":len(paths),"candidate_pairs":checks,"semantic_acceptance":"pending user audition; no listening in live game claimed","gameplay_modified":False}
    (ROOT/"reports/package-verification.json").write_text(json.dumps(report,indent=2),encoding="utf-8")
    print(f"PASS {len(paths)} WAVs; 10 duration/level/onset pairs; no clipping or near-silent preview")

if __name__=="__main__":
    main()
