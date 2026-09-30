"""Encode actual rendered PNG frames as GIFs and an aligned comparison."""
from pathlib import Path
import json
import sys

from PIL import Image, ImageDraw
import numpy as np


def gif_sequence(folder: Path) -> Path:
    frames = sorted(folder.glob("motion_*.png"))
    if not frames:
        raise SystemExit(f"No rendered frames: {folder}")
    encoded = []
    for frame in frames:
        with Image.open(frame) as image:
            encoded.append(image.convert("RGB").quantize(colors=256, method=Image.Quantize.FASTOCTREE))
    # GIF stores centiseconds. 30/30/40 ms repeats exactly 30 fps.
    duration = [30 if index % 3 != 2 else 40 for index in range(len(encoded))]
    output = folder.parent / f"{folder.name}.gif"
    encoded[0].save(output, save_all=True, append_images=encoded[1:], duration=duration, loop=0, optimize=False)
    print(json.dumps({"path": str(output), "frames": len(encoded), "duration_ms": sum(duration), "bytes": output.stat().st_size}))
    return output


def aligned_comparison(before: Path, after: Path) -> Path:
    before_frames = sorted(before.glob("motion_*.png"))
    after_frames = sorted(after.glob("motion_*.png"))
    if len(before_frames) != len(after_frames):
        raise SystemExit("Before/after frame counts differ; cannot create aligned comparison")
    encoded = []
    for before_path, after_path in zip(before_frames, after_frames):
        with Image.open(before_path) as left, Image.open(after_path) as right:
            width, height = left.size
            output_frame = Image.new("RGB", (width * 2, height + 30), (20, 23, 28))
            output_frame.paste(left.convert("RGB"), (0, 30))
            output_frame.paste(right.convert("RGB"), (width, 30))
            draw = ImageDraw.Draw(output_frame)
            draw.text((14, 9), "AVANT", fill="white")
            draw.text((width + 14, 9), "APRES", fill="white")
            encoded.append(output_frame.quantize(colors=256, method=Image.Quantize.FASTOCTREE))
    duration = [30 if index % 3 != 2 else 40 for index in range(len(encoded))]
    output = after.parent / f"comparison_{after.name.removeprefix('after_')}.gif"
    encoded[0].save(output, save_all=True, append_images=encoded[1:], duration=duration, loop=0, optimize=False)
    print(json.dumps({"path": str(output), "frames": len(encoded), "duration_ms": sum(duration), "bytes": output.stat().st_size}))
    return output


def temporal_metrics(folder: Path) -> dict:
    """Measure a fixed ground ROI outside the character's orbit on rendered frames."""
    paths = sorted(folder.glob("motion_*.png"))
    deltas = []
    previous = None
    for path in paths:
        with Image.open(path) as image:
            # Rightmost third of the frame; excludes the player's entire orbit.
            roi = np.asarray(image.convert("L"), dtype=np.float32)[150:510, 640:940]
        if previous is not None:
            delta = np.abs(roi - previous)
            deltas.append({"mean_change": float(delta.mean()), "p95_change": float(np.percentile(delta, 95)), "pixels_over_12": float(np.mean(delta > 12.0))})
        previous = roi
    summary = {
        "folder": folder.name,
        "roi_pixels_xy": [640, 150, 940, 510],
        "frame_pairs": len(deltas),
        "ground_mean_frame_change_8bit": float(np.mean([item["mean_change"] for item in deltas])),
        "ground_max_frame_change_8bit": float(np.max([item["mean_change"] for item in deltas])),
        "ground_p95_frame_mean_change_8bit": float(np.percentile([item["mean_change"] for item in deltas], 95)),
        "ground_p95_fraction_pixels_changing_over_12": float(np.percentile([item["pixels_over_12"] for item in deltas], 95)),
        "interpretation": "Rendered temporal variation in a static ground ROI; smaller values indicate smoother motion, not correctness of game visibility.",
    }
    (folder / "temporal_metrics.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary))
    return summary


def compact_comparison(before: Path, after: Path) -> Path:
    """15 fps shareable preview with one palette for the full six-second clip."""
    before_frames = sorted(before.glob("motion_*.png"))[::2]
    after_frames = sorted(after.glob("motion_*.png"))[::2]
    if len(before_frames) != len(after_frames):
        raise SystemExit("Before/after frame counts differ")
    frames = []
    for before_path, after_path in zip(before_frames, after_frames):
        with Image.open(before_path) as left, Image.open(after_path) as right:
            half_width = 360
            half_height = round(left.height * half_width / left.width)
            frame = Image.new("RGB", (half_width * 2, half_height + 20), (20, 23, 28))
            frame.paste(left.convert("RGB").resize((half_width, half_height), Image.Resampling.LANCZOS), (0, 20))
            frame.paste(right.convert("RGB").resize((half_width, half_height), Image.Resampling.LANCZOS), (half_width, 20))
            draw = ImageDraw.Draw(frame)
            draw.text((9, 4), "AVANT", fill="white")
            draw.text((half_width + 9, 4), "APRES", fill="white")
            frames.append(frame)
    sample_indices = np.linspace(0, len(frames) - 1, 12, dtype=int)
    palette_sheet = Image.new("RGB", (frames[0].width, frames[0].height * len(sample_indices)))
    for index, frame_index in enumerate(sample_indices):
        palette_sheet.paste(frames[frame_index], (0, index * frames[0].height))
    palette = palette_sheet.quantize(colors=128, method=Image.Quantize.MEDIANCUT)
    encoded = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
    duration = [60 if index % 3 == 0 else 70 for index in range(len(encoded))]
    output = after.parent / f"comparison_{after.name.removeprefix('after_')}_compact.gif"
    encoded[0].save(output, save_all=True, append_images=encoded[1:], duration=duration, loop=0, optimize=False, disposal=1)
    frames[0].save(output.with_suffix(".png"))
    print(json.dumps({"path": str(output), "frames": len(encoded), "duration_ms": sum(duration), "fps": 15, "dimensions": list(frames[0].size), "palette": "128_colors_fixed_for_all_frames", "bytes": output.stat().st_size}))
    return output


if __name__ == "__main__":
    arguments = sys.argv[1:]
    if arguments and arguments[0] == "--compact":
        compact_comparison(*(Path(value).resolve() for value in arguments[1:]))
        raise SystemExit(0)
    paths = [Path(value).resolve() for value in arguments]
    for path in paths:
        gif_sequence(path)
        if path.name.endswith("_overview"):
            temporal_metrics(path)
    if len(paths) == 2:
        aligned_comparison(*paths)
