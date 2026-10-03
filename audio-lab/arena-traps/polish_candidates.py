"""Extract short physical gestures, EQ gently, and render synchronized previews."""
import json
from pathlib import Path
import hashlib

import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parent
SR = 44100
SHEET = json.loads((ROOT / "sound-sheet.json").read_text(encoding="utf-8"))
# Raw intervals are seconds. Multiple grains are joined only for the loading gesture.
GRAINS = {
    "tile-warning-A": [(0.135, 0.725, 1.0)],
    "tile-warning-B": [(0.0, 0.72, 1.0)],
    "tile-discharge-A": [(0.299, 0.879, 1.0)],
    "tile-discharge-B": [(0.312, 0.892, 1.0)],
    "cannon-warning-A": [(0.085, 0.385, 1.5), (2.015, 2.625, 1.0)],
    "cannon-warning-B": [(0.125, 0.875, 1.0)],
    "cannon-shot-A": [(0.137, 0.357, 1.0)],
    "cannon-shot-B": [(0.238, 0.448, 1.0)],
}


def fades(audio, start_ms=2, end_ms=32):
    audio = audio.copy()
    start = min(len(audio), round(SR * start_ms / 1000))
    end = min(len(audio), round(SR * end_ms / 1000))
    audio[:start] *= np.linspace(0, 1, start)[:, None] ** 0.7
    audio[-end:] *= np.linspace(1, 0, end)[:, None] ** 1.3
    return audio


def eq(audio, lowpass):
    audio = audio - audio.mean(axis=0)
    spectrum = np.fft.rfft(audio, axis=0)
    freq = np.fft.rfftfreq(len(audio), 1 / SR)
    # Broad cosine transitions avoid a hard spectral cutoff and remove sub-bass.
    high = np.clip((freq - 45) / 70, 0, 1)
    high = (1 - np.cos(np.pi * high)) / 2
    low = np.clip((freq - (lowpass - 900)) / 1800, 0, 1)
    low = (1 + np.cos(np.pi * low)) / 2
    return np.fft.irfft(spectrum * (high * low)[:, None], n=len(audio), axis=0)


def metrics(path, audio):
    if not np.isfinite(audio).all():
        raise ValueError("Non-finite audio: " + path.name)
    peak = float(np.max(np.abs(audio)))
    rms = float(np.sqrt(np.mean(audio ** 2)))
    if peak < 0.001 or rms < 0.0001 or peak >= 0.999:
        raise ValueError("Silent or clipped audio: " + path.name)
    return {"file": path.relative_to(ROOT).as_posix(), "sample_rate": SR,
            "channels": 2, "pcm_bits": 16, "duration_seconds": round(len(audio) / SR, 4),
            "peak_dbfs": round(20 * np.log10(peak), 2),
            "rms_dbfs": round(20 * np.log10(rms), 2),
            "finite": True, "clipped_samples": int(np.count_nonzero(np.abs(audio) >= 0.999)),
            "first_last_peak": round(float(np.max(np.abs(audio[[0, -1]]))), 8),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


REPORT = {"status": "technical-check-only-user-choice-pending", "raw": [], "candidates": [], "previews": []}
CANDIDATES = {}
for cue in SHEET["cues"]:
    raw_path = ROOT / "raw" / (cue["id"] + ".wav")
    raw, rate = sf.read(raw_path, always_2d=True, dtype="float64")
    assert rate == SR and raw.shape[1] == 2
    REPORT["raw"].append(metrics(raw_path, raw))
    grains = [fades(raw[round(start * SR):round(end * SR)] * gain, 2, 24)
              for start, end, gain in GRAINS[cue["id"]]]
    if len(grains) == 2:
        audio = np.concatenate([grains[0], np.zeros((round(.065 * SR), 2)), grains[1]])
    else:
        audio = grains[0]
    audio = eq(audio, cue["lowpass_hz"])
    if "cannon-shot" in cue["id"]:
        # Preserve the attack while suppressing the long generated tail before the next bolt.
        t = np.arange(len(audio)) / SR
        audio *= np.exp(-np.maximum(t - .07, 0) * 9)[:, None]
    audio = fades(audio, 2, 34)
    audio *= 10 ** (cue["peak_dbfs"] / 20) / np.max(np.abs(audio))
    assert len(audio) / SR <= cue["max_seconds"] + 1 / SR
    path = ROOT / "candidates" / (cue["id"] + ".wav")
    sf.write(path, audio, SR, subtype="PCM_16")
    saved, rate = sf.read(path, always_2d=True)
    item = metrics(path, saved)
    item.update({"event": cue["event"], "direction": cue["direction"],
                 "grain_intervals": GRAINS[cue["id"]], "semantic_acceptance": "pending-user-listening",
                 "in_game_audition": "not-integrated"})
    REPORT["candidates"].append(item)
    CANDIDATES[cue["id"]] = saved
    print("CANDIDATE", path.name, item["duration_seconds"], item["peak_dbfs"], flush=True)

# Compare acoustic designs at similar total energy without lifting transient peaks.
for family in ("tile-warning", "tile-discharge", "cannon-warning", "cannon-shot"):
    energies = {direction: float(np.sum(CANDIDATES[family + "-" + direction] ** 2))
                for direction in ("A", "B")}
    target = min(energies.values())
    for direction in ("A", "B"):
        key = family + "-" + direction
        gain = float(np.sqrt(target / energies[direction]))
        audio = CANDIDATES[key] * gain
        path = ROOT / "candidates" / (key + ".wav")
        sf.write(path, audio, SR, subtype="PCM_16")
        saved, rate = sf.read(path, always_2d=True)
        item = next(item for item in REPORT["candidates"] if item["file"] == path.relative_to(ROOT).as_posix())
        item.update(metrics(path, saved))
        item["energy_match_gain_db"] = round(20 * np.log10(gain), 2)
        CANDIDATES[key] = saved

for direction in ("A", "B"):
    pulse = CANDIDATES["cannon-shot-" + direction]
    for count in (2, 3):
        length = round((count - 1) * .24 * SR) + len(pulse) + round(.035 * SR)
        audio = np.zeros((length, 2))
        for shot in range(count):
            start = round(shot * .24 * SR)
            audio[start:start+len(pulse)] += pulse * (1 - .035 * shot)
        path = ROOT / "candidates" / f"cannon-salvo-{count}-{direction}.wav"
        sf.write(path, audio, SR, subtype="PCM_16")
        saved, rate = sf.read(path, always_2d=True)
        item = metrics(path, saved)
        item.update({"event": "trap_cannon_salvo", "shot_count": count,
                     "shot_onsets_seconds": [round(shot * .24, 2) for shot in range(count)],
                     "semantic_acceptance": "pending-user-listening", "in_game_audition": "not-integrated"})
        REPORT["candidates"].append(item)
        CANDIDATES[f"cannon-salvo-{count}-{direction}"] = saved

    # A faithful warning/activation pair for each trap; no music or combat mixed in.
    schedule = [(0.0, "tile-warning-" + direction), (1.6, "tile-discharge-" + direction),
                (3.35, "cannon-warning-" + direction), (4.95, "cannon-salvo-3-" + direction)]
    audio = np.zeros((round(6.4 * SR), 2))
    for at, key in schedule:
        source = CANDIDATES[key]
        start = round(at * SR)
        audio[start:start+len(source)] += source
    path = ROOT / "previews" / f"sequence-{direction}.wav"
    sf.write(path, audio, SR, subtype="PCM_16")
    saved, rate = sf.read(path, always_2d=True)
    item = metrics(path, saved)
    item["schedule"] = [{"at": at, "cue": key} for at, key in schedule]
    REPORT["previews"].append(item)

(ROOT / "reports" / "technical-integrity.json").write_text(json.dumps(REPORT, indent=2), encoding="utf-8")
print("REPORT_READY reports/technical-integrity.json", flush=True)
