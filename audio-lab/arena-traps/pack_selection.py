"""Preserve the user's selected candidates exactly and make a combined audition."""
import hashlib
import json
from pathlib import Path
import shutil

import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parent
SR = 44100
SELECTION = {
    "trap_tile_warning": "B",
    "trap_tile_discharge": "A",
    "trap_cannon_warning": "B",
    "trap_cannon_salvo": "A",
}
SOURCES = {
    "trap-tile-warning.wav": "tile-warning-B.wav",
    "trap-tile-discharge.wav": "tile-discharge-A.wav",
    "trap-cannon-warning.wav": "cannon-warning-B.wav",
    "trap-cannon-shot.wav": "cannon-shot-A.wav",
    "trap-cannon-salvo-2.wav": "cannon-salvo-2-A.wav",
    "trap-cannon-salvo-3.wav": "cannon-salvo-3-A.wav",
}
report = json.loads((ROOT / "reports/technical-integrity.json").read_text(encoding="utf-8"))
expected = {item["file"]: item["sha256"] for item in report["candidates"]}
strict = json.loads((ROOT / "reports/strict-candidates.json").read_text(encoding="utf-8"))
assert all(item["quality"] == "ok" for item in strict)
(ROOT / "selected").mkdir(exist_ok=True)
manifest = {"reservation": "c6c7d972-717e-417c-892c-542f5ae0859c",
            "status": "user-selected-awaiting-gameplay-integration", "selection": SELECTION,
            "files": [], "warning_seconds": 1.6, "cannon_shot_interval_seconds": .24,
            "in_game_audition": "pending", "published": False}
audio_by_file = {}
for destination, source in SOURCES.items():
    raw_path = ROOT / "candidates" / source
    source_hash = hashlib.sha256(raw_path.read_bytes()).hexdigest()
    assert source_hash == expected["candidates/" + source], "Candidate changed since its inspection"
    target = ROOT / "selected" / destination
    shutil.copyfile(raw_path, target)
    assert hashlib.sha256(target.read_bytes()).hexdigest() == source_hash
    audio, rate = sf.read(target, always_2d=True)
    assert rate == SR and audio.shape[1] == 2 and np.isfinite(audio).all()
    audio_by_file[destination] = audio
    manifest["files"].append({"path": "selected/" + destination, "source": "candidates/" + source,
                              "sha256": source_hash, "duration_seconds": round(len(audio) / SR, 4),
                              "sample_rate": SR, "channels": 2, "bit_identical_to_inspected_candidate": True})
    print("SELECTED", destination, "<", source, flush=True)
timeline = [(0.0, "trap-tile-warning.wav"), (1.6, "trap-tile-discharge.wav"),
            (3.35, "trap-cannon-warning.wav"), (4.95, "trap-cannon-salvo-3.wav")]
preview = np.zeros((round(6.4 * SR), 2))
for at, filename in timeline:
    source = audio_by_file[filename]
    start = round(at * SR)
    preview[start:start + len(source)] += source
assert np.isfinite(preview).all() and np.max(np.abs(preview)) < .999
preview_path = ROOT / "previews/sequence-selected.wav"
sf.write(preview_path, preview, SR, subtype="PCM_16")
manifest["preview"] = {"path": "previews/sequence-selected.wav",
                       "sha256": hashlib.sha256(preview_path.read_bytes()).hexdigest(),
                       "schedule": [{"at": at, "file": filename} for at, filename in timeline]}
(ROOT / "selection.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
print("SELECTION_READY selection.json", flush=True)
