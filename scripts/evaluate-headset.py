#!/usr/bin/env python3
# iHearYou | Signature: i729
# Local regression fixtures are never bundled or uploaded.
from pathlib import Path
import hashlib, json, subprocess
import numpy as np
root = Path(__file__).resolve().parents[1]
folder = root / 'build/noise-regression'
binary = folder / 'headset-probe'
subprocess.run(['clang', '-O3', '-std=c11', '-I', str(root/'Sources/AudioDSP/include'), '-I', str(root/'Vendor/Sherpa/include'), str(root/'Sources/AudioDSP/AudioDSP.c'), str(root/'scripts/DSPFileProbe.c'), '-L', str(root/'Vendor/Sherpa/lib'), '-lsherpa-onnx-c-api', '-lc++', '-Wl,-rpath,'+str(root/'Vendor/Sherpa/lib'), '-o', str(binary)], check=True)
model = root / 'Vendor/DPDFNet/dpdfnet2.onnx'
safety = root / 'Vendor/GTCRN/gtcrn_simple.onnx'
vad = root / 'Vendor/Silero/silero_vad.onnx'
def decode(path):
    return np.frombuffer(subprocess.check_output(['ffmpeg','-v','error','-i',str(path),'-f','f32le','-ac','1','-ar','48000','-']), np.float32).copy()
def bandlimit(x):
    low = subprocess.check_output(['ffmpeg','-v','error','-f','f32le','-ar','48000','-ac','1','-i','pipe:0','-ar','16000','-f','f32le','pipe:1'], input=x.astype(np.float32).tobytes())
    output = np.frombuffer(subprocess.check_output(['ffmpeg','-v','error','-f','f32le','-ar','16000','-ac','1','-i','pipe:0','-ar','48000','-f','f32le','pipe:1'], input=low), np.float32)
    return np.pad(output, (0, max(0, len(x)-len(output))))[:len(x)]
def rms(x): return float(np.sqrt(np.mean(x.astype(float)**2)))
def reduction(a,b): return float(20*np.log10((rms(a)+1e-12)/(rms(b)+1e-12)))
def sdr(y,x):
    x=x.astype(float); y=y.astype(float); target=x*np.dot(x,y)/np.dot(x,x)
    return reduction(target,y-target)
def run(label,x):
    source=folder/('headset-'+label+'.f32'); dest=folder/('headset-'+label+'-out.f32')
    x.astype(np.float32).tofile(source)
    result=subprocess.run([str(binary),str(source),str(dest),'3',str(model),str(vad),'1',str(safety)],check=True,capture_output=True,text=True)
    stats=json.loads(result.stdout)
    y=np.fromfile(dest,np.float32)[8672:8672+len(x)]
    assert len(y)==len(x) and np.isfinite(y).all()
    assert stats['processing_errors']==stats['input_drops']==stats['io_error']==0
    return y, stats
speech=np.pad(np.fromfile(root/'build/clap-evaluation/speech.f32',np.float32),(24000,48000))
n=len(speech);t=np.arange(n)/48000; rng=np.random.default_rng(729)
y, stats=run('speech',speech)
reference=bandlimit(speech)
report={'source_sha256':hashlib.sha256((root/'Sources/AudioDSP/AudioDSP.c').read_bytes()).hexdigest(),'model_sha256':hashlib.sha256(model.read_bytes()).hexdigest(),'bandwidth_note':'The headset DPDFNet2/GTCRN pair runs at 16 kHz, limited to roughly 8 kHz bandwidth; speech metrics use a bandwidth-matched reference.','speech_si_sdr_db':sdr(y,reference),'speech_level_change_db':-reduction(reference,y),'rtf':stats['cpu_seconds']/stats['audio_seconds'],'noise':{}}
print(json.dumps(report),flush=True)
noises={'fan':.6*np.sin(2*np.pi*50*t)+.35*np.sin(2*np.pi*100*t)+.2*np.sin(2*np.pi*150*t)+.3*rng.normal(size=n),'dog':np.resize(decode(folder/'dog.wav'),n),'vacuum':np.resize(decode(folder/'vacuum_cleaner.wav'),n)}
for name,noise in noises.items():
    noise=noise/rms(noise)*rms(speech)*.5
    alone,_=run(name+'-only',noise)
    mixed,stat=run(name+'-mixed',speech+noise)
    report['noise'][name]={'noise_only_reduction_db':reduction(bandlimit(noise),alone),'overlapping_noise_effect_reduction_db':reduction(bandlimit(noise),mixed-y),'mixture_si_sdr_db':sdr(mixed,reference),'rtf':stat['cpu_seconds']/stat['audio_seconds']}
    print(name,json.dumps(report['noise'][name]),flush=True)
report['passed']=report['speech_si_sdr_db']>18 and abs(report['speech_level_change_db'])<3 and all(v['noise_only_reduction_db']>12 and v['overlapping_noise_effect_reduction_db']>10 for v in report['noise'].values())
(folder/'headset-metrics.json').write_text(json.dumps(report,indent=2))
assert report['passed'], 'Headset denoiser regression: do not ship'
