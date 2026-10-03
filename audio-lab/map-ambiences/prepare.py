"""Prepare audition material without modifying the game or approving sound semantics."""
import hashlib
import json
import math
import subprocess
import wave
from pathlib import Path
import numpy as np
from design import ROOT, SR, CUES, MAPS, INSPECTION_PYTHON, INSPECTOR

def read(path):
    with wave.open(str(path), "rb") as handle:
        assert handle.getframerate() == SR and handle.getnchannels() == 2 and handle.getsampwidth() == 2, str(path)
        samples = np.frombuffer(handle.readframes(handle.getnframes()), dtype="<i2").reshape(-1, 2).astype(np.float64) / 32768
    assert np.isfinite(samples).all() and len(samples) > SR / 4
    return samples

def write(path, samples):
    assert np.isfinite(samples).all() and np.max(np.abs(samples)) < .98
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(2)
        handle.setsampwidth(2)
        handle.setframerate(SR)
        handle.writeframes(np.rint(samples * 32767).astype("<i2").tobytes())

def level(samples, target, ceiling=.62):
    rms = float(np.sqrt(np.mean(samples * samples)))
    assert rms > .00001, "Silent source"
    gain = min(10 ** (target / 20) / rms, ceiling / max(np.max(np.abs(samples)), .00001))
    return samples * gain, float(gain)

def fades(samples, start=.04, end=.12):
    samples = samples.copy()
    a = min(round(start * SR), len(samples) // 2)
    b = min(round(end * SR), len(samples) // 2)
    samples[:a] *= np.linspace(0, 1, a)[:, None]
    samples[-b:] *= np.linspace(1, 0, b)[:, None]
    return samples

def prepare_cue(cue):
    raw = read(ROOT / "raw" / (cue["id"] + ".wav"))
    clipped = float(np.mean(np.abs(raw) >= .999))
    raw_rms = float(np.sqrt(np.mean(raw * raw)))
    assert clipped <= .001 and raw_rms < .5, f"Reject clipped or over-dense raw source: {cue['id']}"
    samples = raw - np.mean(raw, axis=0)
    n = round(cue["duration"] * SR)
    if cue["kind"] == "ambience":
        source_start = round(.7 * SR)
        samples = samples[source_start:source_start+n].copy()
        assert len(samples) == n
        crossfade = round(1.25 * SR)
        alpha = np.linspace(0, 1, crossfade)[:, None]
        join = samples[-crossfade:] * (1-alpha) + samples[:crossfade] * alpha
        samples = np.concatenate([samples[crossfade:-crossfade], join])
        processing = dict(source_start_seconds=.7, source_end_seconds=.7+cue["duration"], loop_crossfade_seconds=1.25, loop_seam_jump=float(np.max(np.abs(samples[0]-samples[-1]))))
    else:
        grain_n = n - round(.16 * SR)
        # Find the most energetic contiguous grain; no pitch or speed manipulation.
        frame = round(.01 * SR)
        energy = np.mean(samples[:len(samples)//frame*frame].reshape(-1, frame, 2) ** 2, axis=(1,2))
        frames = max(1, grain_n // frame)
        sums = np.convolve(energy, np.ones(frames), mode="valid")
        source_start = int(np.argmax(sums)) * frame
        grain = fades(samples[source_start:source_start+grain_n], .035, min(.2, cue["duration"]*.2))
        samples = np.zeros((n, 2))
        samples[round(.02*SR):round(.02*SR)+len(grain)] = grain
        processing = dict(source_start_seconds=source_start/SR, source_end_seconds=(source_start+grain_n)/SR, leading_silence_seconds=.02, trailing_silence_seconds=.14)
    samples, gain = level(samples, cue["rms_db"])
    path = ROOT / "candidates" / (cue["id"] + ".wav")
    write(path, samples)
    return samples, dict(id=cue["id"], arena=cue["arena"], label=cue["label"], kind=cue["kind"], path=path.relative_to(ROOT).as_posix(), generation_seconds=cue["generation_seconds"], duration_seconds=round(len(samples)/SR, 4), seed=cue["seed"], raw_sha256=hashlib.sha256((ROOT/"raw"/(cue["id"]+".wav")).read_bytes()).hexdigest(), sha256=hashlib.sha256(path.read_bytes()).hexdigest(), raw_clipped_ratio=clipped, raw_rms=raw_rms, gain=gain, processing=processing, semantic_decision="pending", heard_in_picture=None)

def tiled(samples, n):
    return np.tile(samples, (math.ceil(n/len(samples)), 1))[:n]

def inspect(paths, kind, name):
    cmd = [str(INSPECTION_PYTHON), str(INSPECTOR), *[str(p) for p in paths], "--kind", kind, "--strict", "--json"]
    run = subprocess.run(cmd, capture_output=True, text=True)
    if run.stderr:
        (ROOT/"reports"/(name+"-stderr.log")).write_text(run.stderr, encoding="utf-8")
    (ROOT/"reports"/(name+".json")).write_text(run.stdout, encoding="utf-8")
    if run.returncode:
        raise SystemExit(f"Strict inspection failed: {name}; inspect the saved report")
    return json.loads(run.stdout)

def main():
    prepared, records = {}, []
    for cue in CUES:
        samples, info = prepare_cue(cue)
        prepared[cue["id"]] = samples
        records.append(info)
    checks = []
    for kind in ["ambience", "accent"]:
        checks += inspect([ROOT/r["path"] for r in records if r["kind"] == kind], kind, "strict-"+kind)
    for record in records:
        check = next(c for c in checks if Path(c["path"]).name == record["id"]+".wav")
        record["technical_quality"] = check["quality"]
    previews = []
    duration = 45
    n = SR*duration
    for identifier, arena in MAPS.items():
        bed = np.zeros((n, 2))
        for source in arena["beds"]:
            bed += tiled(prepared[source], n)
        bed, _ = level(bed, -32)
        mix = bed.copy()
        events = []
        for source, when, gain in sorted(arena["events"], key=lambda event: event[1]):
            a = round(when*SR)
            source_audio = prepared[source]
            b = min(n, a+len(source_audio))
            mix[a:b] += source_audio[:b-a]*gain
            events.append(dict(id=source, label=next(r["label"] for r in records if r["id"]==source), at_seconds=when, gain=gain))
        mix, mix_gain = level(mix, -29)
        bed_path = ROOT/"previews"/(identifier+"-fond.wav")
        path = ROOT/"previews"/(identifier+"-ambiance.wav")
        write(bed_path, fades(bed, 1.2, 1.8))
        write(path, fades(mix, 1.2, 1.8))
        previews.append(dict(id=identifier, title=arena["title"], number=arena["number"], direction=arena["direction"], color=arena["color"], path=path.relative_to(ROOT).as_posix(), bed_path=bed_path.relative_to(ROOT).as_posix(), duration_seconds=duration, events=events, mix_gain=mix_gain))
    preview_checks = inspect([ROOT/p[key] for p in previews for key in ["path", "bed_path"]], "ambience", "strict-previews")
    manifest = dict(model="Stable Audio 3 Small-SFX", local_only=True, integrated_in_game=False, semantic_acceptance="pending user audition", preview_note="Les événements des extraits sont une mise en scène sonore illustrative. Ils ne sont pas synchronisés à une capture du jeu.", cues=records, maps=previews)
    (ROOT/"manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    review = ["# Écoute et validation sémantique", "", "Généré avec Stable Audio 3 Small-SFX. Aucune écoute humaine ni acceptation artistique n'est présumée. Aucun son intégré au jeu.", "", "Les scènes sonores sont illustratives ; les horaires des événements sont dans manifest.json. Une écoute avec les mécanismes visibles reste nécessaire avant intégration.", ""]
    for record in records:
        review += ["## "+record["id"], "", "- Cause visible : "+record["label"], "- Fonction : rendre le lieu ou le mouvement identifiable sans couvrir les indices de combat.", "- Association souhaitée : "+MAPS[record["arena"]]["direction"], "- Associations interdites : voix, musique, armes, alarme, perceuse ou marteau-piqueur ; tic-tac aigu continu.", "- Contact : à déterminer sur les mécanismes réels ; aperçu illustratif seulement.", "- Source : raw/"+record["id"]+".wav, intervalle "+str(record["processing"]["source_start_seconds"])+" à "+str(record["processing"]["source_end_seconds"])+" s.", "- Entendu en image : non vérifié.", "- Décision : en attente d'écoute.", ""]
    (ROOT/"semantic-review.md").write_text("\n".join(review), encoding="utf-8")
    (ROOT/"reports"/"verification.json").write_text(json.dumps(dict(candidate_count=len(records), preview_count=len(preview_checks), technical_ok=all(r["quality"]=="ok" for r in checks+preview_checks), semantic_verified=False, integrated_in_game=False), indent=2), encoding="utf-8")
    print(f"PACK_READY {len(records)}/{len(CUES)}; 3 map mixes + 3 bed previews; semantic audition pending", flush=True)

if __name__ == "__main__":
    main()
