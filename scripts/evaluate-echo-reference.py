#!/usr/bin/env python3
# iHearYou | Signature: i729
# Offline research harness; no private recordings or live audio capture.
from pathlib import Path
import hashlib, json, subprocess
import numpy as np
root=Path(__file__).resolve().parents[1]
folder=root/'build/echo-research';folder.mkdir(parents=True,exist_ok=True)
source=root/'build/reference/speexdsp-1.2.1'
subprocess.run(['clang','-O3','-I',str(source/'include'),str(root/'scripts/AECReferenceProbe.c'),str(source/'libspeexdsp/.libs/libspeexdsp.a'),'-lm','-o',str(folder/'probe')],check=True)
rate=16000; n=rate*30
speech48=np.fromfile(root/'build/clap-evaluation/speech.f32',np.float32)
def convert(x):
    return np.frombuffer(subprocess.check_output(['ffmpeg','-v','error','-f','f32le','-ar','48000','-ac','1','-i','pipe:0','-ar','16000','-f','f32le','-'],input=x.astype(np.float32).tobytes()),np.float32).copy()
speech=np.resize(convert(speech48),n);speech*=.08/max(np.sqrt(np.mean(speech**2)),1e-9)
notice=np.frombuffer(subprocess.check_output(['ffmpeg','-v','error','-i','/System/Library/Sounds/Glass.aiff','-ar','16000','-ac','1','-f','f32le','-']),np.float32).copy()
notice*=.2/max(np.max(np.abs(notice)),1e-9)
far=np.roll(speech,rate*3)*.7
far[rate*22:rate*22+len(notice)]+=notice
near=np.zeros(n,np.float32);near[rate*12:rate*26]=speech[:rate*14]
def echo(reference):
    y=np.zeros(n,np.float32)
    # Known synthetic linear room path, not a physical-room measurement.
    for ms,gain in [(60,.50),(83,.17),(112,-.08),(151,.035)]:
        delay=round(ms*rate/1000);y[delay:]+=reference[:-delay]*gain
    return y
def pcm(x):return np.clip(np.rint(x*32768),-32768,32767).astype(np.int16)
def run(name,reference,microphone):
    a=folder/(name+'-reference.pcm');b=folder/(name+'-mic.pcm');c=folder/(name+'-out.pcm')
    assert np.max(np.abs(microphone))<1
    pcm(reference).tofile(a);pcm(microphone).tofile(b)
    result=subprocess.run([str(folder/'probe'),str(a),str(b),str(c)],check=True,capture_output=True,text=True)
    stats=json.loads(result.stdout);y=np.fromfile(c,np.int16).astype(np.float32)/32768
    assert len(y)==n and np.isfinite(y).all()
    return y,stats
def db(a,b):return float(20*np.log10((np.linalg.norm(a.astype(float))+1e-12)/(np.linalg.norm(b.astype(float))+1e-12)))
def sdr(y,x):
    x=x.astype(float);y=y.astype(float);target=x*np.dot(x,y)/np.dot(x,x)
    return db(target,y-target)
e=echo(far);warm=slice(rate*5,rate*28)
y,stats=run('echo-only',far,e)
report={'engine':'SpeexDSP 1.2.1','source_archive_sha256':hashlib.sha256((root/'build/reference/speexdsp-1.2.1.tar.gz').read_bytes()).hexdigest(),'sample_rate':rate,'frame_ms':10,'filter_ms':500,'fixture':'Locally held public speech fixture plus macOS Glass; known synthetic linear echo path at 60/83/112/151 ms. No physical recording.','warm_echo_reduction_db':db(e[warm],y[warm]),'rtf':stats['cpu_seconds']/30}
y,_=run('double-talk',far,near+e);active=slice(rate*14,rate*26)
report['double_talk_si_sdr_db']=sdr(y[active],near[active]);report['double_talk_input_si_sdr_db']=sdr((near+e)[active],near[active]);report['double_talk_level_change_db']=-db(near[active],y[active])
y,_=run('no-reference',np.zeros(n,np.float32),speech)
quantized=pcm(speech).astype(np.float32)/32768
report['no_reference_identity_snr_db']=db(quantized,y-quantized)
cold=np.zeros(n,np.float32);cold[rate:rate+len(notice)]=notice
echo_cold=echo(cold);y,_=run('cold-notification',cold,echo_cold)
report['cold_notification_echo_reduction_db']=db(echo_cold,y)
report['candidate_gate_passed']=report['warm_echo_reduction_db']>15 and report['double_talk_si_sdr_db']>15 and report['no_reference_identity_snr_db']>35
report['limitations']=['Synthetic synchronized linear echo only; no hardware/room/Bluetooth clock coverage.','No live Core Audio playback reference is integrated in iHearYou.','An unrelated phone playing nearby provides no digital reference to this AEC.','A first notification without prior adaptation may leak.']
(folder/'metrics.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))

if not report['candidate_gate_passed']:
    raise SystemExit("Research acceptance gate failed; this AEC configuration must not ship unchanged.")
