#!/usr/bin/env python3
# iHearYou | Signature: i729
# Requires numpy and the local, licensed offline clap fixture (not uploaded).
from pathlib import Path
import json
import subprocess
import numpy as np

root = Path(__file__).resolve().parents[1]
source = root / 'build/clap-evaluation'
folder = root / 'build/final-evaluation'
folder.mkdir(parents=True, exist_ok=True)
baseline = json.loads((source / 'metrics.json').read_text())
model = root / 'Vendor/DPDFNet/dpdfnet2_48khz_hr.onnx'
outputs = {}
timings = {}
for kind in ['speech', 'mixture']:
    destination = folder / (kind + '.f32')
    result = subprocess.run([str(root / 'build/dsp-file-probe'), str(source / (kind + '.f32')),
        str(destination), '3', str(model)], check=True, capture_output=True, text=True)
    timings[kind] = json.loads(result.stdout)
    samples = np.fromfile(source / (kind + '.f32'), dtype=np.float32)
    audio = np.fromfile(destination, dtype=np.float32)[2400:2400 + len(samples)]
    assert len(audio) == len(samples) and np.isfinite(audio).all()
    outputs[kind] = audio.astype(np.float64)
    audio.astype(np.float32).tofile(folder / (kind + '-aligned.f32'))

speech = np.fromfile(source / 'speech.f32', dtype=np.float32).astype(np.float64)
mixture = np.fromfile(source / 'mixture.f32', dtype=np.float32).astype(np.float64)
noise = mixture - speech
residual = outputs['mixture'] - outputs['speech']
def db(a, b): return float(10 * np.log10((np.dot(a, a) + 1e-15) / (np.dot(b, b) + 1e-15)))
def sdr(y, x):
    projection = np.dot(y, x) / np.dot(x, x) * x
    return db(projection, y - projection)
metrics = {
    'engine': 'production AudioDSP.c / DPDFNet2_48khz_hr / Strong',
    'delay_samples': 2400,
    'clap_effect_reduction_db': db(noise, residual),
    'voiced_event_effect_reduction_db': [db(noise[i:i+19200], residual[i:i+19200]) for i in baseline['events']],
    'speech_level_change_db': -db(speech, outputs['speech']),
    'speech_only_si_sdr_db': sdr(outputs['speech'], speech),
    'mixture_output_si_sdr_db': sdr(outputs['mixture'], speech),
    'probe': timings,
}
reference = baseline['models']['rnnoise-reference']
assert metrics['clap_effect_reduction_db'] > reference['clap_effect_reduction_db'] + 3
assert min(metrics['voiced_event_effect_reduction_db']) > min(reference['voiced_event_effect_reduction_db']) + 3
assert metrics['speech_only_si_sdr_db'] > 15 and abs(metrics['speech_level_change_db']) < 3
(folder / 'metrics.json').write_text(json.dumps(metrics, indent=2))
print(json.dumps(metrics, indent=2))
