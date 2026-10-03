"""Check the real Effects-bus recording for silence or digital clipping."""
import array, json, math, wave
from pathlib import Path
ROOT = Path(__file__).resolve().parent
log = (ROOT / 'reports/combat-mixer.log').read_text(encoding='utf-8-sig')
assert 'COMBAT COMPLETION SFX: PASS' in log
if 'falling back to the dummy driver' in log:
    report = dict(status='unavailable', reason='WASAPI output device could not be opened; dummy recording is not audio acceptance',
                  gameplay_cues_verified=27)
    (ROOT / 'reports/combat-mixer.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print('MIXER: UNAVAILABLE - no WASAPI output device; gameplay checks passed')
    raise SystemExit(2)
assert 'SCRIPT ERROR' not in log and 'ERROR:' not in log
with wave.open(str(ROOT / 'reports/combat-completion-recorded.wav'), 'rb') as wav:
    assert wav.getsampwidth() == 2
    values = array.array('h', wav.readframes(wav.getnframes()))
    peak = max(abs(value) for value in values) / 32768
    rms = math.sqrt(sum(value * value for value in values) / len(values)) / 32768
    clipped = sum(abs(value) >= 32767 for value in values)
    report = dict(status='passed', duration_seconds=wav.getnframes()/wav.getframerate(), peak=peak,
                  rms=rms, clipped_samples=clipped, channels=wav.getnchannels(),
                  sample_rate=wav.getframerate())
assert rms > 0.001 and clipped == 0, report
(ROOT / 'reports/combat-mixer.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print('REAL MIXER: PASS', json.dumps(report))
