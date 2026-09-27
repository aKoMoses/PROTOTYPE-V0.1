"""Set a unique Android version code and GitHub prerelease tag for a CI run."""

import re
import sys
from pathlib import Path


def main() -> None:
    if len(sys.argv) != 2 or not sys.argv[1].isdigit():
        raise SystemExit("usage: prepare_android_ci.py GITHUB_RUN_NUMBER")
    run_number = int(sys.argv[1])
    version_code = 10000 + run_number
    if version_code > 2100000000:
        raise SystemExit("Android version code exceeds the supported range")

    preset = Path("export_presets.cfg")
    text = preset.read_text(encoding="utf-8")
    match = re.search(r'^version/name="([0-9]+\.[0-9]+\.[0-9]+)"$', text, re.M)
    if not match:
        raise SystemExit("Expected a numeric X.Y.Z version/name in export_presets.cfg")
    base_version = match.group(1)
    text, code_count = re.subn(r'^version/code=\d+$', f'version/code={version_code}', text, count=1, flags=re.M)
    text, name_count = re.subn(r'^version/name="[^"]+"$', f'version/name="{base_version}.{run_number}"', text, count=1, flags=re.M)
    if code_count != 1 or name_count != 1:
        raise SystemExit("Android version fields missing from export_presets.cfg")
    preset.write_text(text, encoding="utf-8")
    print(f"RELEASE_TAG=v{base_version}-build.{run_number}")


if __name__ == "__main__":
    main()
