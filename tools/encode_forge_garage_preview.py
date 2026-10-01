"""Encode the real Godot Movie Maker frames as a compact animated preview."""

from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
FRAME_DIR = ROOT / "captures" / "forge-garage" / "motion"
OUTPUT = FRAME_DIR.parent / "garage-motion.gif"
paths = sorted(FRAME_DIR.glob("garage[0-9]*.png"))
if len(paths) < 120:
    raise SystemExit("Record the complete service cycle with Godot Movie Maker first.")

frames = []
for path in paths:
    with Image.open(path) as source:
        frames.append(source.convert("RGB").resize((960, 540), Image.Resampling.LANCZOS))

# Share a palette across the sequence so static lighting does not flicker.
reference = Image.new("RGB", (960, 540 * 3))
for row, index in enumerate([0, len(frames) // 2, len(frames) - 1]):
    reference.paste(frames[index], (0, row * 540))
palette = reference.quantize(colors=256, method=Image.Quantize.MEDIANCUT)
encoded = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
durations = [80 if index % 3 else 90 for index in range(len(encoded))]
encoded[0].save(
    OUTPUT,
    save_all=True,
    append_images=encoded[1:],
    duration=durations,
    loop=0,
    optimize=True,
    disposal=1,
)
with Image.open(OUTPUT) as result:
    count = result.n_frames
    duration = 0
    for frame in range(count):
        result.seek(frame)
        duration += result.info.get("duration", 0)
print(f"FORGE MOTION: {count} real frames, {duration / 1000:.2f}s, {OUTPUT.stat().st_size} bytes")
