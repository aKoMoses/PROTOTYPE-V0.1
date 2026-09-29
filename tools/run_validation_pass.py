"""Run the repository's Godot regressions without modifying player saves."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument("--godot", required=True)
parser.add_argument("--project", default=str(Path(__file__).resolve().parents[1]))
parser.add_argument("--output", default="docs/pass_validation_results.json")
args = parser.parse_args()
project = Path(args.project).resolve()
log_dir = project / ".godot/pass-logs/final"
log_dir.mkdir(parents=True, exist_ok=True)
results = []
for test in sorted((project / "tools").glob("test_*.gd")):
	# Native GUI hit-testing is not performed by the headless display server.
    graphics = test.name == "test_gui_input_routing.gd"
    environment = os.environ.copy()
    user_dir = project / ".godot/pass-user-suite" / test.stem
    user_dir.mkdir(parents=True, exist_ok=True)
    environment["APPDATA"] = str(user_dir)
    started = time.monotonic()
    try:
        command = [args.godot, "--path", str(project), "--script", "res://tools/" + test.name]
        command += ["--resolution", "1280x720"] if graphics else ["--headless"]
        run = subprocess.run(
            command,
            capture_output=True, text=True, encoding="utf-8", errors="replace",
            timeout=180, env=environment,
        )
        output = run.stdout + run.stderr
        exit_code = run.returncode
    except subprocess.TimeoutExpired as error:
        output = "TIMEOUT\n" + str(error.stdout or "") + str(error.stderr or "")
        exit_code = -1
    log_path = log_dir / (test.stem + ".log")
    log_path.write_text(output, encoding="utf-8")
    script_error = "SCRIPT ERROR:" in output
    failed_assertion = bool(re.search(r"(?m)^[^\n]*(?:TEST|RELIABILITY|LIFECYCLE|SAFETY)[^\n]*:\s*FAIL\b", output))
    result = {
        "test": test.name, "exit_code": exit_code,
        "display": "Windows/Vulkan" if graphics else "headless",
        "passed": exit_code == 0 and not script_error and not failed_assertion,
        "script_error": script_error, "seconds": round(time.monotonic() - started, 2),
        "log": str(log_path.relative_to(project)).replace("\\", "/"),
        "certificate_store_warning": "Failed to read the root certificate store" in output,
        "shutdown_resource_warning": "resources still in use at exit" in output or "ObjectDB instances were leaked" in output,
        "summary": [line for line in output.splitlines() if "PASS" in line or "checks" in line or "TEST:" in line][-8:],
    }
    results.append(result)
    print(f"{'PASS' if result['passed'] else 'FAIL'} {test.name} ({result['seconds']} s)", flush=True)
report = {
    "engine_executable": args.godot, "project": str(project),
    "tests": len(results), "passed": sum(r["passed"] for r in results),
    "failed": [r["test"] for r in results if not r["passed"]], "results": results,
}
(project / args.output).write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
raise SystemExit(0 if report["passed"] == report["tests"] else 1)
