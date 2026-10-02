"""Preserve the user's B/B choice and copy its verified audio unchanged."""
import hashlib
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent
TIMESTAMP = "2026-10-01T22:25:13+02:00"

def main():
    manifest_path = ROOT / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    selection = {
        "selected_at": TIMESTAMP,
        "confirmed_by": "user",
        "weapons": {"mekatana": "B-stable", "longshot": "B-stable"},
        "future_sfx_generator": "Stable Audio",
        "current_selected_model": "Stable Audio 3 Small-SFX",
        "integrated_in_game": False,
        "files": [],
    }
    selected = ROOT / "selected"
    selected.mkdir(exist_ok=True)
    for cue in manifest["cues"]:
        source = ROOT / cue["files"]["B"]["path"]
        source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
        assert source_hash == cue["files"]["B"]["sha256"], source
        dest = selected / (cue["id"] + ".wav")
        shutil.copyfile(source, dest)
        assert hashlib.sha256(dest.read_bytes()).hexdigest() == source_hash
        selection["files"].append({"id": cue["id"], "path": str(dest.relative_to(ROOT)), "source": str(source.relative_to(ROOT)), "sha256": source_hash})
    for weapon in ["mekatana", "longshot"]:
        source = ROOT / "previews" / (weapon + "-B.wav")
        dest = selected / (weapon + "-preview.wav")
        shutil.copyfile(source, dest)
        assert source.read_bytes() == dest.read_bytes()
    (ROOT / "selection.json").write_text(json.dumps(selection, indent=2), encoding="utf-8")
    manifest["selection"] = "B selected for Mekatana and Longshot by user"
    manifest["selection_file"] = "selection.json"
    manifest["future_sfx_generator"] = "Stable Audio"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    report_path = ROOT / "reports/package-verification.json"
    report = json.loads(report_path.read_text(encoding="utf-8"))
    report["semantic_acceptance"] = "B selected for both weapons by user after audition; live game synchronization remains unverified"
    report["selected_files_verified"] = 12
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("PASS B/B choice saved; 10 chosen effects and 2 previews copied bit-for-bit")

if __name__ == "__main__":
    main()
