"""Independent resource checks and approximate rhythmic periodicity, not listening approval."""
from pathlib import Path
import json
import wave
import hashlib
import urllib.request
import numpy as np

ROOT = Path(__file__).resolve().parent

def inspect(item):
    path = ROOT/item['file']
    with wave.open(str(path),'rb') as w:
        sr, nc, width, n = w.getframerate(),w.getnchannels(),w.getsampwidth(),w.getnframes()
        assert nc==2 and width==2 and n==30*sr, item['id']
        x = np.frombuffer(w.readframes(n),dtype='<i2').reshape(-1,2).astype(float)/32768
    peak = float(np.max(np.abs(x)))
    assert .01 < peak < .95
    first_second = float(np.sqrt(np.mean(x[:sr]**2)))
    assert first_second > .006
    samples = x.mean(1)[::4]
    freq = sr/4
    hop, window = 128,512
    frames = np.lib.stride_tricks.sliding_window_view(samples,window)[::hop]
    spectrum = np.abs(np.fft.rfft(frames*np.hanning(window)))
    onset = np.maximum(np.diff(np.log1p(spectrum*32768),axis=0),0).mean(1)
    flux = onset-onset.mean()
    fft = np.fft.rfft(flux,n=2*len(flux))
    corr = np.fft.irfft(fft*fft.conj())[:len(flux)]
    candidates = []
    for lag in range(round(60*freq/hop/210),round(60*freq/hop/60)):
        if corr[lag] > corr[lag-1] and corr[lag] > corr[lag+1]:
            candidates.append({'bpm_periodicity':round(60*freq/hop/lag,1),
                               'correlation':round(float(corr[lag]/corr[0]),3)})
    candidates.sort(key=lambda z:z['correlation'],reverse=True)
    target = item['target_bpm']
    nearby = [c for c in candidates if abs(c['bpm_periodicity']/target-1)<.12]
    early = onset[:round(2*freq/hop)]
    onset_threshold = float(onset.mean()+.6*onset.std())
    early_peaks = sum(early[i]>early[i-1] and early[i]>early[i+1] and early[i]>onset_threshold for i in range(1,len(early)-1))
    return {'id':item['id'],'duration_seconds':n/sr,'channels':nc,
            'first_second_rms_dbfs':round(20*np.log10(first_second),2),
            'peak_dbfs':round(20*np.log10(peak),2),
            'target_bpm':target,'rhythmic_periodicity_near_target':nearby[0] if nearby else None,
            'strongest_periodicities':candidates[:4],
            'transient_peaks_first_two_seconds':int(early_peaks),
            'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}

def main():
    manifest = json.loads((ROOT/'manifest.json').read_text(encoding='utf-8'))
    reports=[]
    for item in manifest['tracks']:
        if not (ROOT/item['file']).exists():
            continue
        result=inspect(item)
        reports.append(result)
        print(item['id']+' target '+str(item['target_bpm'])+' periodicity '+str(result['rhythmic_periodicity_near_target'])+' early transients '+str(result['transient_peaks_first_two_seconds']))
    assert len({r['sha256'] for r in reports})==len(reports)
    page=urllib.request.urlopen('http://127.0.0.1:8767/preview.html').read().decode('utf-8')
    for item in manifest['tracks']:
        if not (ROOT/item['file']).exists():
            continue
        assert 'src="'+item['file']+'"' in page
        request=urllib.request.Request('http://127.0.0.1:8767/'+item['file'],method='HEAD')
        assert urllib.request.urlopen(request).status==200
    report={'note':'Periodicity from onset autocorrelation is approximate: half/double time and subdivisions may coexist. This is not a listening judgment or a certified musical tempo.',
            'files_checked':len(reports),'tracks':reports}
    (ROOT/'rhythm-checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print('VERIFIED '+str(len(reports))+'/9')

if __name__=='__main__':
    main()
