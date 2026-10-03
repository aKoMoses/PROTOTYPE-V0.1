"""Verify approved asset identity, import gain and actual mixer output."""
import hashlib
import json
from pathlib import Path

import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parents[1]


def main():
    preparation = json.loads((ROOT / "reports/preparation.json").read_text(encoding="utf-8"))
    assets = []
    for name in ["ventilation", "pressure", "metal"]:
        source = ROOT / "candidates" / (name + ".wav")
        target = PROJECT / "art/audio/garage-ambience" / source.name
        expected = next(entry["sha256"] for entry in preparation["outputs"] if entry["path"].replace("\\", "/") == "candidates/" + source.name)
        digest = hashlib.sha256(target.read_bytes()).hexdigest()
        assert digest == expected == hashlib.sha256(source.read_bytes()).hexdigest(), name + " differs from approved preview"
        importer = target.with_suffix(".wav.import").read_text(encoding="utf-8")
        assert "edit/normalize=false" in importer and "edit/trim=false" in importer, "import changes approved level or loop"
        assets.append({"cue": name, "path": str(target.relative_to(PROJECT)), "sha256": digest,
                       "decision": "accepted by user with music in the proposed preview",
                       "heard_in_picture": "User approved the offline garage music and ambience proposal; no agent listening claim."})
    recording, rate = sf.read(ROOT / "reports/runtime-ambience.wav", always_2d=True)
    assert len(recording) > rate * 2 and np.isfinite(recording).all(), "missing mixer recording"
    assert float(np.max(np.abs(recording))) > .001, "mixer recording is silent"
    tail_peak = float(np.max(np.abs(recording[-rate // 4:])))
    assert tail_peak == 0, "ambience continues after hiding garage"
    log = (ROOT / "reports/runtime-test.log").read_text(encoding="utf-8")
    assert "FORGE AMBIENCE AUDIO TEST: PASS (0 failures)" in log and "ERROR:" not in log, "runtime test failed"
    installation = (ROOT / "reports/installation-regression.log").read_text(encoding="utf-8")
    assert "FORGE INSTALLATION AUDIO TEST: PASS (0 failures)" in installation, "installation regression failed"
    selection = {"model": "Stable Audio 3 Small-SFX", "accepted_on": "2026-10-03",
                 "integrated_in_game": True, "publication": "local only", "assets": assets,
                 "runtime_verified": {"audio_present": True, "silence_after_hide": True,
                                      "tail_peak": tail_peak, "sample_rate": rate},
                 "android_verified": False}
    (ROOT / "selection.json").write_text(json.dumps(selection, ensure_ascii=False, indent=2), encoding="utf-8")
    print("GARAGE AMBIENCE INTEGRATION: PASS (3 approved assets, unchanged import gain, mixer audio and exit silence)")


if __name__ == "__main__":
    main()
