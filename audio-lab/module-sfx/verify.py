"""Inspect candidates, the propulsion loop and audition sequences appropriately."""
import hashlib
import json
import subprocess
import numpy as np
from cues import ROOT, SR, CUES, INSPECTION_PYTHON, INSPECTOR
from prepare import read, rms

def inspect(paths,kind,filename):
    result=subprocess.run([str(INSPECTION_PYTHON),str(INSPECTOR),*[str(p) for p in paths],"--kind",kind,"--strict","--json"],capture_output=True,text=True)
    (ROOT/"reports"/filename).write_text(result.stdout,encoding="utf-8")
    if result.returncode:
        print(result.stderr)
        raise SystemExit("REJECT: "+filename)
    return json.loads(result.stdout)

def main():
    manifest=json.loads((ROOT/"manifest.json").read_text(encoding="utf-8"))
    accents=[ROOT/cue["file"] for cue in manifest["cues"] if cue["kind"]!="loop"]
    loops=[ROOT/cue["file"] for cue in manifest["cues"] if cue["kind"]=="loop"]
    previews=[ROOT/value["file"] for module in manifest["previews"].values() for value in module.values()]
    inspect(accents,"accent","strict-accents.json")
    inspect(loops,"ambience","strict-loops.json")
    inspect(previews,"accent","strict-previews.json")
    checks=[]
    for cue in manifest["cues"]:
        path=ROOT/cue["file"]
        assert hashlib.sha256(path.read_bytes()).hexdigest()==cue["sha256"]
        assert hashlib.sha256((ROOT/cue["source"]).read_bytes()).hexdigest()==cue["source_sha256"]
        x=read(path)
        assert np.isfinite(x).all() and np.max(np.abs(x))<.8
        assert rms(x)>.003,(cue["id"],"too quiet")
        assert len(x)==round(cue["duration_seconds"]*SR)
        power=np.mean(x*x,axis=1)
        activity=np.flatnonzero(power>float(np.max(power))*.01)
        onset=float(activity[0]/SR)
        assert onset<.13,(cue["id"],onset)
        if cue["kind"]=="loop":
            boundary=float(np.max(np.abs(x[0]-x[-1])))
            steps=np.max(np.abs(np.diff(x,axis=0)),axis=1)
            typical=float(np.percentile(steps,99))
            assert boundary<max(.003,typical*1.5),(cue["id"],boundary,typical)
        else:
            boundary=None
            assert cue["main_energy_peak_offset"]<cue["duration_seconds"]
            assert np.max(np.abs(x[0]))<.0001 and np.max(np.abs(x[-1]))<.0001
        checks.append({"id":cue["id"],"status":"pass","onset_seconds":round(onset,5),"rms_dbfs":round(20*np.log10(rms(x)),2),"loop_boundary_difference":boundary})
    for path in previews:
        assert rms(read(path))>.006,(path,"quiet preview")
    report={"status":"pass","candidate_count":len(checks),"preview_count":len(previews),"format":"WAV PCM16 stereo 44100 Hz","technical_checks":checks,"listening_validation":"pending user audition","integrated_in_game":False}
    (ROOT/"reports/integrity.json").write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
    print("PASS 22 candidate WAVs + 10 previews; hashes, audible onset, headroom and loop seam verified")

if __name__=="__main__":
    main()
