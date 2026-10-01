"""Generate original Stable Audio 3 Small-SFX sources; never touch gameplay."""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RUNTIME = Path(r"C:\Users\BOTTEROOOW\Tools\stable-audio-3\optimized\tflite")
PYTHON = RUNTIME / ".venv/Scripts/python.exe"
CLI = RUNTIME / "scripts/sa3_tflite.py"
NEGATIVE = "music, melody, speech, voices, narration, automatic gunfire, machine gun, drill, jackhammer, continuous motor, long ambience, repeated attacks, clipping, low fidelity"
SOURCES = [
    ("mekatana-windup", 26100101, "A robotic electric katana energizing for one quick strike, a short taut steel resonance rising into a tiny dry electrical snap, close microphone, dry isolated studio game sound effect, one brief gesture then silence, no music"),
    ("mekatana-slash-1", 26100102, "One fast light katana blade swing cutting the air, tight sharp metallic swish with a tiny electrical crackle, close dry isolated game sound effect, single very short attack then silence, realistic air movement, no music"),
    ("mekatana-slash-2", 26100103, "One forceful broad katana blade swing cutting the air, weighty rushing air and tense steel edge with a brief electrical crackle, close dry isolated game sound effect, one short sweeping attack then silence, no music"),
    ("mekatana-slash-3", 26100104, "One heavy overhead electric katana finishing swing, powerful deep blade whoosh with a sharp electric release and restrained metallic resonance, close dry isolated game sound effect, one decisive short attack then silence, no music"),
    ("mekatana-impact-1", 26100105, "One light energized steel sword strike against robot armor, sharp dry metal contact with a tiny electrical spark and short steel ring, close isolated studio game sound effect, single impact then silence, no music"),
    ("mekatana-impact-2", 26100106, "One solid electric katana strike into heavy steel robot armor, crunchy metal impact and brief crackling discharge, close dry isolated studio game sound effect, single short hit then silence, no music"),
    ("mekatana-impact-3", 26100107, "One powerful electric katana finishing strike into thick robot armor, deep physical metallic slam, tearing steel crunch and a short fierce electrical discharge, close dry isolated game sound effect, one punchy impact then silence, no music"),
    ("longshot-shot", 26100108, "One precision futuristic rifle shot, an extremely sharp dry ballistic crack over a compact low punch with a subtle metal breech clack and brief air release, close isolated studio game sound effect, single shot then silence, no laser whine, no music"),
    ("longshot-enhanced", 26100109, "One powerful overcharged precision rifle shot, sharp explosive ballistic crack, heavy compact chest punch and a short electrical discharge followed by a dry metal breech clack, close isolated studio game sound effect, single shot then silence, no long laser whine, no music"),
    ("longshot-ready", 26100110, "One small futuristic rifle chamber locking an enhanced round into place, two close crisp metallic clicks ending in a tiny taut electrical ping, dry isolated studio game sound effect, one short readiness cue then silence, no music"),
]

def main():
    (ROOT / "raw/stable").mkdir(parents=True, exist_ok=True)
    (ROOT / "reports").mkdir(exist_ok=True)
    spec = {"provider": "local Stability AI", "model": "Stable Audio 3 Small-SFX", "runtime": "official optimized TFLite", "duration": 4, "steps": 8, "cfg": 1.0, "negative_prompt": NEGATIVE, "sources": [{"id": key, "seed": seed, "prompt": prompt} for key, seed, prompt in SOURCES]}
    (ROOT / "stable-requests.json").write_text(json.dumps(spec, indent=2), encoding="utf-8")
    requested = set(sys.argv[1:])
    for key, seed, prompt in SOURCES:
        if requested and key not in requested:
            continue
        dest = ROOT / "raw/stable" / (key + ".wav")
        if dest.exists():
            print("EXISTS " + key, flush=True)
            continue
        print("GENERATING " + key, flush=True)
        cmd = [str(PYTHON), str(CLI), "--dit", "sm-sfx", "--decoder", "same-s", "--seconds", "4", "--steps", "8", "--cfg", "1", "--seed", str(seed), "--threads", "8", "--prompt", prompt, "--negative-prompt", NEGATIVE, "--out", str(dest)]
        with (ROOT / "reports" / (key + "-generation.log")).open("w", encoding="utf-8") as log:
            result = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT)
        if result.returncode:
            raise SystemExit("FAILED " + key + ": inspect generation log")
        print("RAW_READY " + key, flush=True)

if __name__ == "__main__":
    main()
