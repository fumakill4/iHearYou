#!/usr/bin/env python3
# iHearYou | Signature: i729
# Local-only fixtures; ESC-50 CC-BY-NC clips are not packaged with the app.
from pathlib import Path
import hashlib, json, subprocess
import numpy as np
root = Path(__file__).resolve().parents[1]
folder = root / 'build/noise-regression'
folder.mkdir(parents=True, exist_ok=True)
model = root / 'Vendor/DPDFNet/dpdfnet2_48khz_hr.onnx'
vad = root / 'Vendor/Silero/silero_vad.onnx'
binary = folder / 'studio-probe'
subprocess.run(['clang', '-O3', '-std=c11', '-I', str(root/'Sources/AudioDSP/include'), '-I', str(root/'Vendor/Sherpa/include'), str(root/'Sources/AudioDSP/AudioDSP.c'), str(root/'scripts/DSPFileProbe.c'), '-L', str(root/'Vendor/Sherpa/lib'), '-lsherpa-onnx-c-api', '-lc++', '-Wl,-rpath,'+str(root/'Vendor/Sherpa/lib'), '-o', str(binary)], check=True)
speech = np.fromfile(root/'build/clap-evaluation/speech.f32', dtype=np.float32)
speech = np.pad(speech, (24000, 48000))
n = len(speech); t = np.arange(n)/48000
rng = np.random.default_rng(729)
def decode(path):
    return np.frombuffer(subprocess.check_output(['ffmpeg', '-v', 'error', '-i', str(path), '-f', 'f32le', '-ac', '1', '-ar', '48000', '-']), dtype=np.float32).copy()
def fit(x): return np.resize(x, n)
def rms(x): return float(np.sqrt(np.mean(x.astype(float)**2)))
def reduction(a,b): return float(20*np.log10((rms(a)+1e-12)/(rms(b)+1e-12)))
def sdr(y,x):
    x=x.astype(float);y=y.astype(float);target=x*np.dot(x,y)/np.dot(x,x)
    return reduction(target,y-target)
def run(label,x,baseline=False):
    src=folder/(label+'.f32');dest=folder/(label+'-output.f32');x.astype(np.float32).tofile(src)
    probe=folder/'baseline-probe' if baseline else binary
    cmd=[str(probe),str(src),str(dest),'3',str(model)]
    if not baseline:cmd.append(str(vad))
    completed=subprocess.run(cmd, check=True,capture_output=True,text=True)
    stats=json.loads(completed.stdout)
    delay=2400 if baseline else 8672
    output=np.fromfile(dest,dtype=np.float32)[delay:delay+n]
    assert len(output)==n and np.isfinite(output).all() and np.max(np.abs(output))<=.99
    assert stats['processing_errors']==stats['input_drops']==stats['io_error']==0
    return output,stats
noises={
    'fan-hum': .6*np.sin(2*np.pi*50*t)+.35*np.sin(2*np.pi*100*t)+.2*np.sin(2*np.pi*150*t)+.3*rng.normal(size=n),
    'dog':fit(decode(folder/'dog.wav')),
    'vacuum':fit(decode(folder/'vacuum_cleaner.wav')),
    'notification':fit(np.pad(decode('/System/Library/Sounds/Glass.aiff'),(24000,48000))),
}
report={'sample_rate':48000,'studio_delay_samples':8672,'speech_samples':n,'sources':{'speech':'Existing controlled Freesound #33711 speech fixture (CC BY-NC 3.0)','dog':'ESC-50 1-100032-A-0.wav (CC-BY-NC, local evaluation only)','vacuum':'ESC-50 1-100210-A-36.wav (CC-BY-NC, local evaluation only)','notification':'macOS Glass.aiff (local evaluation only)','fan-hum':'Seeded synthetic 50/100/150 Hz hum + broadband noise; not a physical fan recording'},'source_sha256':hashlib.sha256((root/'Sources/AudioDSP/AudioDSP.c').read_bytes()).hexdigest(),'results':{}}
new_clean,stats=run('studio-speech',speech)
old_clean,_=run('baseline-speech',speech,True)
report['speech']={'studio_si_sdr_db':sdr(new_clean,speech),'baseline_si_sdr_db':sdr(old_clean,speech),'studio_level_change_db':-reduction(speech,new_clean),'stats':stats}
print('speech',json.dumps(report['speech']),flush=True)
for name,noise in noises.items():
    noise=noise/rms(noise)*rms(speech)*.5
    mixture=speech+noise
    assert np.max(np.abs(mixture))<1
    result={}
    for baseline in [True,False]:
        label='baseline' if baseline else 'studio'
        alone,_=run(label+'-'+name+'-only',noise,baseline)
        mixed,stats=run(label+'-'+name+'-mixed',mixture,baseline)
        reference=old_clean if baseline else new_clean
        result[label]={'noise_only_reduction_db':reduction(noise,alone),'mixed_si_sdr_db':sdr(mixed,speech),'noise_effect_reduction_db':reduction(noise,mixed-reference),'rtf':stats['cpu_seconds']/stats['audio_seconds']}
    report['results'][name]=result
    (folder/'metrics.json').write_text(json.dumps(report,indent=2))
    print(name,json.dumps(result),flush=True)
report['speech_acceptance_passed']=report['speech']['studio_si_sdr_db']>15 and abs(report['speech']['studio_level_change_db'])<3
report['noise_acceptance_passed']=all(r['studio']['noise_only_reduction_db']>=r['baseline']['noise_only_reduction_db'] for r in report['results'].values())
(folder/'metrics.json').write_text(json.dumps(report,indent=2))
assert report['speech_acceptance_passed'], 'Speech is damaged; do not ship'
assert report['noise_acceptance_passed'], 'Noise-only regression; do not ship'
