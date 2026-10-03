"""Generate audition sources with the installed official Stable Audio runtime."""
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RUNTIME = Path(r"C:\Users\BOTTEROOOW\Tools\stable-audio-3\optimized\tflite")
PYTHON = RUNTIME / ".venv/Scripts/python.exe"
CLI = RUNTIME / "scripts/sa3_tflite.py"
NEGATIVE = "music, melody, speech, voices, alarms, gunshots, drilling, jackhammer, rhythmic impacts, screeching, harsh buzzing, cinematic boom, clipping, distortion"
CUES = [
    {"id": "ventilation", "seed": 26100331, "seconds": 12,
     "prompt": "Distant quiet ventilation airflow in a spacious empty industrial workshop, soft diffuse air moving through overhead metal ducts, smooth low gentle room tone, constant restrained environmental bed, natural indoor acoustics, no rattling, no music",
     "visible_cause": "Hangar industriel autour de l'atelier, source distante hors champ.",
     "function": "Donner un peu de volume au hangar sans attirer l'attention.",
     "desired": "Souffle doux et lointain.", "forbidden": "Bourdonnement aigu, pulsation, vibration envahissante."},
    {"id": "pressure", "seed": 26100332, "seconds": 4,
     "prompt": "One small pneumatic valve softly releasing a short breath of compressed air from a workshop pipe, distant across a large industrial hangar, delicate airy pssht fading quickly into silence, one quiet brief gesture, realistic clean isolated environmental sound effect, no music",
     "visible_cause": "Circuit pneumatique du hangar, hors champ, indépendant du bras visible.",
     "function": "Faire vivre occasionnellement l'atelier entre les manipulations.",
     "desired": "Bref souffle de pression lointain.", "forbidden": "Explosion, vapeur forte, alarme ou bruit continu."},
    {"id": "metal", "seed": 26100333, "seconds": 4,
     "prompt": "One small steel tool gently set down on a wooden workbench in a distant workshop bay, a soft tiny metallic clink with a short dull tail, spacious quiet indoor industrial hangar acoustics, one delicate isolated contact then silence, clean realistic environmental sound effect, no music",
     "visible_cause": "Établi voisin dans le hangar, hors champ.",
     "function": "Suggérer une activité éloignée par un détail rare.",
     "desired": "Petit contact métallique mat.", "forbidden": "Coups de marteau répétés, chute lourde, son brillant trop long."},
]


def main():
    for directory in ["raw", "candidates", "previews", "reports"]:
        (ROOT / directory).mkdir(parents=True, exist_ok=True)
    spec = {"model": "Stable Audio 3 Small-SFX", "runtime": "official optimized TFLite",
            "steps": 8, "cfg": 1, "negative_prompt": NEGATIVE,
            "integrated_in_game": False, "decision": "pending listening in garage context", "cues": CUES}
    (ROOT / "sound-sheet.json").write_text(json.dumps(spec, indent=2, ensure_ascii=False), encoding="utf-8")
    for cue in CUES:
        path = ROOT / "raw" / (cue["id"] + ".wav")
        if path.exists():
            continue
        print("GENERATING " + cue["id"], flush=True)
        cmd = [str(PYTHON), str(CLI), "--dit", "sm-sfx", "--decoder", "same-s",
               "--seconds", str(cue["seconds"]), "--steps", "8", "--cfg", "1",
               "--seed", str(cue["seed"]), "--threads", "8", "--prompt", cue["prompt"],
               "--negative-prompt", NEGATIVE, "--out", str(path)]
        with (ROOT / "reports" / (cue["id"] + "-generation.log")).open("w", encoding="utf-8") as log:
            result = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT)
        if result.returncode:
            raise SystemExit("FAILED " + cue["id"] + ": inspect generation log")
        print("RAW_READY " + cue["id"], flush=True)


if __name__ == "__main__":
    main()
