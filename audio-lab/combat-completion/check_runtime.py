"""Run relevant Godot regressions; a PASS beside a script error is a failure."""
import json, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]
GODOT = r'C:\RomainOpen\perso\Godot_4.7.2\Godot_v4.7.2-stable_win64_console.exe'
TESTS = ['test_combat_completion_sfx', 'test_training_audio', 'test_module_sfx',
         'test_offensive_modules', 'test_fulguro_punch', 'test_pelto_smash',
         'test_defensive_modules', 'test_eclipse_training', 'test_new_passive_combat',
         'test_network_combat']

if __name__ == '__main__':
    import sys
    previous = ROOT / 'reports' / 'runtime-checks.json'
    reports = json.loads(previous.read_text(encoding='utf-8')) if previous.exists() else []
    for name in sys.argv[1:] or TESTS:
        result = subprocess.run([GODOT, '--headless', '--path', str(REPO),
                                 '--script', f'res://tools/{name}.gd'],
                                capture_output=True, text=True, timeout=75)
        output = result.stdout + result.stderr
        (ROOT / 'reports' / f'{name}.log').write_text(output, encoding='utf-8')
        meaningful = '\n'.join(line for line in output.splitlines()
                               if not ('resources still in use at exit' in line))
        passed = result.returncode == 0 and 'PASS' in output and not any(
            error in meaningful for error in ['SCRIPT ERROR', 'Parse Error', 'Compilation failed', 'ERROR:'])
        reports = [row for row in reports if row['test'] != name]
        reports.append(dict(test=name, passed=passed, exit_code=result.returncode))
        print(name, 'PASS' if passed else 'FAIL', flush=True)
        if not passed:
            print(output[-4500:], flush=True)
    (ROOT / 'reports' / 'runtime-checks.json').write_text(json.dumps(reports, indent=2), encoding='utf-8')
    raise SystemExit(0 if all(row['passed'] for row in reports) else 1)
