"""Encode the Godot camera cycle using a shared palette to avoid lighting flicker."""
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[1] / "captures/forge-camera-motion"
paths = sorted((root / "frames").glob("frame-*.png"))
if len(paths) != 360:
    raise SystemExit("Run capture_forge_camera_motion.gd to render the 360-frame cycle first.")
frames = []
for path in paths:
    with Image.open(path) as source:
        frames.append(source.convert("RGB").resize((960, 540), Image.Resampling.LANCZOS))
reference = Image.new("RGB", (960, 540 * 4))
for row, index in enumerate([0, 90, 180, 270]):
    reference.paste(frames[index], (0, 540 * row))
palette = reference.quantize(colors=256, method=Image.Quantize.MEDIANCUT)
encoded = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
output = root / "garage-camera.gif"
encoded[0].save(output, save_all=True, append_images=encoded[1:], duration=50, loop=0, optimize=True, disposal=1)
with Image.open(output) as result:
    count = result.n_frames
    duration = sum((result.seek(index), result.info.get("duration", 0))[1] for index in range(count))
print(f"FORGE CAMERA PREVIEW: {count} GPU frames, {duration / 1000:.2f}s, {output.stat().st_size} bytes")
