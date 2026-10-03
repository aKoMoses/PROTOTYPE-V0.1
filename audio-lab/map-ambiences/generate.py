"""Run the existing local Stable Audio optimized runtime sequentially."""
import json
import subprocess
import sys
import time
from design import ROOT, CUES, MAPS, PYTHON, CLI, NEGATIVE

def main():
    for folder in ["raw", "candidates", "previews", "reports"]:
        (ROOT / folder).mkdir(parents=True, exist_ok=True)
    sheet = dict(model="Stable Audio 3 Small-SFX", provider="local Stability AI", runtime="official optimized TFLite", steps=8, cfg=1.0, negative_prompt=NEGATIVE, negative_prompt_effect="Not applied by the runtime when cfg=1.0; exclusions also appear in positive prompts.", integrated_in_game=False, semantic_acceptance="pending user audition", maps=MAPS, cues=CUES)
    (ROOT / "sound-sheet.json").write_text(json.dumps(sheet, ensure_ascii=False, indent=2), encoding="utf-8")
    selected = set(sys.argv[1:])
    for index, cue in enumerate(CUES, 1):
        if selected and cue["id"] not in selected:
            continue
        path = ROOT / "raw" / (cue["id"] + ".wav")
        if path.exists():
            print("EXISTS " + cue["id"], flush=True)
            continue
        print(f"GENERATING {index}/{len(CUES)} {cue['id']}", flush=True)
        cmd = [str(PYTHON), str(CLI), "--dit", "sm-sfx", "--decoder", "same-s", "--seconds", str(cue["generation_seconds"]), "--steps", "8", "--cfg", "1", "--seed", str(cue["seed"]), "--threads", "8", "--prompt", cue["prompt"], "--negative-prompt", NEGATIVE, "--out", str(path)]
        start = time.monotonic()
        with (ROOT / "reports" / (cue["id"] + "-generation.log")).open("w", encoding="utf-8") as log:
            result = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT)
        if result.returncode:
            raise SystemExit("FAILED " + cue["id"] + ": inspect generation log")
        print(f"RAW_READY {cue['id']} ({time.monotonic()-start:.1f}s)", flush=True)

if __name__ == "__main__":
    main()
