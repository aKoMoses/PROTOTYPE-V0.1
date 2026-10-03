"""Polish generated sources and render a conservative offline garage audition."""
import hashlib
import json
import math
from pathlib import Path

import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parent
SR = 44100


def read(path):
    audio, rate = sf.read(path, dtype="float32", always_2d=True)
    if rate != SR or audio.shape[1] != 2 or not np.isfinite(audio).all():
        raise ValueError("Unexpected audio format: " + str(path))
    return audio


def fade(audio, seconds):
    audio = audio.copy()
    count = min(int(seconds * SR), len(audio) // 2)
    ramp = np.linspace(0, 1, count, dtype=np.float32)[:, None]
    audio[:count] *= ramp
    audio[-count:] *= ramp[::-1]
    return audio


def soften(audio, low, high):
    frequencies = np.fft.rfftfreq(len(audio), 1 / SR)
    response = 1 / np.sqrt(1 + (low / np.maximum(frequencies, 1)) ** 4)
    response *= 1 / np.sqrt(1 + (frequencies / high) ** 6)
    return np.fft.irfft(np.fft.rfft(audio, axis=0) * response[:, None], n=len(audio), axis=0).astype(np.float32)


def level(audio, db):
    rms = float(np.sqrt(np.mean(audio ** 2)))
    if rms < 1e-6:
        raise ValueError("Empty source")
    return audio * (10 ** (db / 20) / rms)


def grain(audio, seconds):
    length = int(seconds * SR)
    energy = np.mean(audio ** 2, axis=1)
    integral = np.concatenate(([0], np.cumsum(energy, dtype=np.float64)))
    best = int(np.argmax(integral[length:] - integral[:-length]))
    return audio[best:best + length], best / SR


def write(path, audio):
    if not np.isfinite(audio).all() or float(np.max(np.abs(audio))) >= .99:
        raise ValueError("Nonfinite or clipping output: " + str(path))
    sf.write(path, audio, SR, subtype="PCM_16")
    decoded = read(path)
    return {"path": str(path.relative_to(ROOT)), "seconds": len(decoded) / SR,
            "rms_dbfs": round(20 * math.log10(float(np.sqrt(np.mean(decoded ** 2))) + 1e-12), 2),
            "peak_dbfs": round(20 * math.log10(float(np.max(np.abs(decoded))) + 1e-12), 2),
            "clipped_samples": int(np.count_nonzero(np.abs(decoded) >= .999)),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def main():
    spec = json.loads((ROOT / "sound-sheet.json").read_text(encoding="utf-8"))
    report = {"integrated_in_game": False, "semantic_listening": "pending user audition",
              "music_gain_db": -14, "music_unchanged": True, "outputs": [], "grains": {}}
    bed = soften(read(ROOT / "raw/ventilation.wav"), 90, 2800)
    # Crossfade the generated tail into its head; retain a loop without abrupt seams.
    overlap = int(.8 * SR)
    ramp = np.linspace(0, 1, overlap)[:, None]
    bed = np.concatenate((bed[overlap:-overlap], bed[-overlap:] * (1 - ramp) + bed[:overlap] * ramp))
    bed = level(bed, -49)
    sources = {"ventilation": bed}
    report["outputs"].append(write(ROOT / "candidates/ventilation.wav", bed))
    for cue, seconds, db in [("pressure", 1.3, -42), ("metal", .65, -43)]:
        audio, start = grain(read(ROOT / "raw" / (cue + ".wav")), seconds)
        audio = level(fade(soften(audio, 160, 4200), .07), db)
        sources[cue] = audio
        report["grains"][cue] = {"source_start": start, "duration": seconds}
        report["outputs"].append(write(ROOT / "candidates" / (cue + ".wav"), audio))
    duration = 36
    total = duration * SR
    ambience = np.zeros((total, 2), dtype=np.float32)
    start = 6 * SR
    tiled = np.tile(bed, (int(np.ceil((total - start) / len(bed))), 1))[:total - start]
    ambience[start:] = fade(tiled, 1.5)
    cues = [(11, "pressure"), (21, "metal"), (31, "pressure")]
    for time, cue in cues:
        audio = sources[cue]
        begin = int(time * SR)
        ambience[begin:begin + len(audio)] += audio
    music = read(ROOT.parents[1] / "art/audio/garage_atelier.wav")
    music_loop = music[8 * SR:]
    if not len(music_loop):
        raise ValueError("Garage music is too short")
    music = np.tile(music_loop, (int(np.ceil(total / len(music_loop))), 1))[:total]
    music *= 10 ** (-14 / 20)
    mix = fade(music + ambience, .25)
    report["outputs"].append(write(ROOT / "previews/garage-musique-et-ambiance.wav", mix))
    # Separate boosted audition helps identify details; never use this gain in game.
    report["outputs"].append(write(ROOT / "previews/ambiance-seule-amplifiee.wav", ambience * 10 ** (14 / 20)))
    report["cue_schedule_seconds"] = cues
    report["first_six_seconds"] = "music only; same gain as the remainder"
    report["music_rms_dbfs"] = round(20 * math.log10(float(np.sqrt(np.mean(music ** 2)))), 2)
    report["ambience_rms_dbfs"] = round(20 * math.log10(float(np.sqrt(np.mean(ambience ** 2)))), 2)
    (ROOT / "reports/preparation.json").write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps({"previews": len(report["outputs"]), "music_rms_dbfs": report["music_rms_dbfs"],
                      "ambience_rms_dbfs": report["ambience_rms_dbfs"], "semantic_listening": report["semantic_listening"]}))


if __name__ == "__main__":
    main()
