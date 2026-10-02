"""Re-record the Forge's training clips with Godot and encode small silent OGVs."""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GODOT = Path(r"C:\RomainOpen\perso\Godot_4.7.2\Godot_v4.7.2-stable_win64_console.exe")


def run(command, log=None):
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = subprocess.SW_HIDE
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                            encoding="utf-8", errors="replace", startupinfo=startup)
    output = result.stdout + result.stderr
    if log:
        log.write_text(output, encoding="utf-8")
    if result.returncode or "SCRIPT ERROR" in output or "\nERROR:" in output:
        raise RuntimeError(output[-4000:])
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=str(GODOT))
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg"))
    parser.add_argument("--only", nargs="*")
    parser.add_argument("--native", action="store_true", help="Keep Godot's native Theora video and remove audio without transcoding.")
    args = parser.parse_args()
    if not args.ffmpeg:
        parser.error("Pass the installed FFmpeg executable with --ffmpeg.")
    catalog = (ROOT / "scripts/forge_training_demo.gd").read_text(encoding="utf-8")
    loadout_catalog = (ROOT / "scripts/loadout_state.gd").read_text(encoding="utf-8")
    choices = re.findall(r'const (?:WEAPONS|OFFENSIVE|DEFENSIVE|MOBILITY|PASSIVES) := \[(.*?)\]', loadout_catalog)
    identifiers = [identifier for group in choices for identifier in re.findall(r'"([a-z_]+)"', group)]
    supported = identifiers.copy()
    if args.only:
        unknown = set(args.only) - set(identifiers)
        if unknown:
            parser.error(f"Unknown equipment: {sorted(unknown)}")
        identifiers = args.only
    cache = ROOT / "captures/forge-demos/raw"
    cache.mkdir(parents=True, exist_ok=True)
    destination = ROOT / "art/forge-demos"
    destination.mkdir(parents=True, exist_ok=True)
    for identifier in identifiers:
        raw = cache / f"{identifier}.ogv"
        output = run([args.godot, "--path", str(ROOT), "--fixed-fps", "30",
                      "--disable-vsync", "--write-movie", str(raw),
                      "--script", "tools/record_forge_training_demo.gd",
                      "--", "--demo", identifier], cache / f"{identifier}.log")
        marker = next((line for line in output.splitlines()
                       if line.startswith("FORGE DEMO RECORDED:")), None)
        if not marker:
            raise RuntimeError(f"Recording did not finish: {identifier}")
        clip = cache / f"{identifier}-encoded.ogv"
        if args.native:
            run([args.ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
                 "-i", str(raw), "-an", "-c:v", "copy", str(clip)])
        else:
            run([args.ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
                 "-ss", "0.1", "-i", str(raw), "-an", "-vf", "scale=640:360",
                 "-c:v", "libtheora", "-q:v", "7", str(clip)])
        run([args.ffmpeg, "-hide_banner", "-loglevel", "error", "-i", str(clip),
             "-f", "null", "-"])
        shutil.copyfile(clip, destination / f"{identifier}.ogv")
        print(marker, "bytes=", clip.stat().st_size, flush=True)
    # Preserve verification data for the other clips after a targeted rebuild.
    manifest = []
    known_clips = dict.fromkeys(supported + re.findall(r'"([a-z_]+)": preload\("res://art/forge-demos/', catalog))
    for clip_id in known_clips:
        clip = destination / f"{clip_id}.ogv"
        log = cache / f"{clip_id}.log"
        if not clip.exists() or not log.exists():
            continue
        marker = next((line for line in log.read_text(encoding="utf-8").splitlines()
                       if line.startswith("FORGE DEMO RECORDED:")), "")
        manifest.append({"id": clip_id, "bytes": clip.stat().st_size,
                         "sha256": hashlib.sha256(clip.read_bytes()).hexdigest(), "combat": marker})
    (cache.parent / "recordings.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
