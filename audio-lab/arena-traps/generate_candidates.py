"""Produce isolated raw candidates with the installed local Stable Audio runtime."""
import json
from pathlib import Path
import subprocess
import sys
import wave

ROOT = Path(__file__).resolve().parent
RUNTIME = Path(r"C:\Users\BOTTEROOOW\Tools\stable-audio-3\optimized\tflite")
PYTHON = RUNTIME / ".venv/Scripts/python.exe"
CLI = RUNTIME / "scripts/sa3_tflite.py"

sheet = json.loads((ROOT / "sound-sheet.json").read_text(encoding="utf-8"))
for folder in ("raw", "candidates", "previews", "reports"):
    (ROOT / folder).mkdir(exist_ok=True)

requested = set(sys.argv[1:])
for cue in sheet["cues"]:
    if requested and cue["id"] not in requested:
        continue
    destination = ROOT / "raw" / (cue["id"] + ".wav")
    if destination.exists():
        print("EXISTS " + destination.name, flush=True)
        continue
    command = [str(PYTHON), str(CLI), "--dit", "sm-sfx", "--decoder", "same-s",
               "--seconds", str(sheet["generation_seconds"]), "--steps", str(sheet["steps"]),
               "--cfg", str(sheet["cfg"]), "--seed", str(cue["seed"]),
               "--threads", "8", "--prompt", cue["prompt"],
               "--negative-prompt", sheet["negative_prompt"], "--out", str(destination)]
    print("GENERATING " + cue["id"], flush=True)
    with (ROOT / "reports" / (cue["id"] + "-generation.log")).open("w", encoding="utf-8") as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        raise SystemExit("FAILED " + cue["id"] + ": see its generation log")
    with wave.open(str(destination), "rb") as audio:
        print(f"RAW_READY {destination.name} {audio.getnframes()/audio.getframerate():.2f}s "
              f"{audio.getframerate()}Hz {audio.getnchannels()}ch", flush=True)
