#!/usr/bin/env python3
# iHearYou | Signature: i729
# Rebuild and validate the exact production C DSP, not research adapters.
from pathlib import Path
import hashlib
import json
import subprocess
import numpy as np

root = Path(__file__).resolve().parents[1]
source = root / 'build/clap-evaluation'
folder = root / 'build/final-evaluation'
folder.mkdir(parents=True, exist_ok=True)
binary = folder / 'dsp-final-probe'
model = root / 'Vendor/DPDFNet/dpdfnet2_48khz_hr.onnx'
vad = root / 'Vendor/Silero/silero_vad.onnx'
dsp = root / 'Sources/AudioDSP/AudioDSP.c'
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
source_sha = sha(dsp)
subprocess.run(['clang', '-O3', '-std=c11', '-I', str(root / 'Sources/AudioDSP/include'), '-I', str(root / 'Vendor/Sherpa/include'),
                str(dsp), str(root / 'scripts/DSPFileProbe.c'), '-L', str(root / 'Vendor/Sherpa/lib'),
                '-lsherpa-onnx-c-api', '-lc++', '-Wl,-rpath,' + str(root / 'Vendor/Sherpa/lib'), '-o', str(binary)], check=True)
baseline_fixture = json.loads((source / 'metrics.json').read_text())
speech = np.fromfile(source / 'speech.f32', dtype=np.float32)
mixture = np.fromfile(source / 'mixture.f32', dtype=np.float32)
noise = mixture - speech
events = baseline_fixture['events']

def ratio(a, b):
    a = a.astype(np.float64); b = b.astype(np.float64)
    return float(10 * np.log10((np.dot(a, a) + 1e-15) / (np.dot(b, b) + 1e-15)))

def sdr(y, x):
    x = x.astype(np.float64); y = y.astype(np.float64)
    projected = np.dot(y, x) / np.dot(x, x) * x
    return ratio(projected, y - projected)

def lag(y, x):
    nfft = 1 << (len(y) + len(x) - 1).bit_length()
    corr = np.fft.irfft(np.fft.rfft(y, nfft) * np.conj(np.fft.rfft(x, nfft)), nfft)
    offsets = np.arange(-4800, 4801)
    return int(offsets[np.argmax(np.abs(corr[offsets % nfft]))])

def process(label, mode, kind, reference=False):
    destination = folder / f'{label}-{kind}.f32'
    command = [str(root / 'build/rnnoise-reference' if reference else binary), str(source / f'{kind}.f32'), str(destination), str(mode)]
    if not reference: command.extend([str(model), str(vad)])
    completed = subprocess.run(command, check=True, text=True, capture_output=True)
    stats = None if reference else json.loads(completed.stdout.strip())
    if stats:
        assert stats['processing_errors'] == stats['input_drops'] == stats['io_error'] == 0
        assert stats['input_samples'] == len(speech)
    unaligned = np.fromfile(destination, dtype=np.float32)
    delay = 960 if reference else 8672
    audio = unaligned[delay:delay + len(speech)]
    assert len(audio) == len(speech) and np.isfinite(audio).all() and np.max(np.abs(audio)) <= .99
    aligned = folder / f'{label}-{kind}-aligned.f32'
    audio.tofile(aligned)
    subprocess.run(['ffmpeg', '-v', 'error', '-f', 'f32le', '-ar', '48000', '-ac', '1', '-i',
                    str(aligned), '-y', str(folder / f'{label}-{kind}-aligned.wav')], check=True)
    return audio, stats

results = {'fixture': baseline_fixture['fixture'], 'events': events, 'input_si_sdr_db': sdr(mixture, speech),
           'sample_rate': 48000, 'production_source_sha256': source_sha, 'model_sha256': sha(model),
           'probe_sha256': sha(binary), 'production_delay_samples': 8672, 'presets': {}}
for label, mode, reference in [('rnnoise-reference', 2, True), ('natural', 1, False), ('balanced', 2, False), ('strong', 3, False)]:
    clean, clean_stats = process(label, mode, 'speech', reference)
    mixed, mixed_stats = process(label, mode, 'mixture', reference)
    residual = mixed - clean
    result = {'clap_effect_reduction_db': ratio(noise, residual),
              'speech_only_si_sdr_db': sdr(clean, speech), 'speech_level_change_db': -ratio(speech, clean),
              'mixture_output_si_sdr_db': sdr(mixed, speech),
              'voiced_event_effect_reduction_db': [ratio(noise[start:start + 19200], residual[start:start + 19200]) for start in events],
              'aligned_speech_lag_samples': lag(clean, speech), 'speech_probe': clean_stats, 'mixture_probe': mixed_stats}
    if label == 'strong':
        only_claps, clap_stats = process(label, mode, 'claps')
        result['clap_only_reduction_db'] = ratio(noise, only_claps)
        result['clap_probe'] = clap_stats
    results['presets'][label] = result
    (folder / 'metrics.json').write_text(json.dumps(results, indent=2))
    print(label, json.dumps(result), flush=True)
bypass, bypass_stats = process('bypass', 0, 'speech')
results['bypass_max_error'] = float(np.max(np.abs(bypass - speech)))
results['bypass_probe'] = bypass_stats
assert results['bypass_max_error'] < 1e-6
assert sha(dsp) == source_sha, 'Production DSP changed during validation; rerun against latest source'
strong = results['presets']['strong']; reference = results['presets']['rnnoise-reference']
assert strong['aligned_speech_lag_samples'] == 0, 'The production 180.67 ms alignment is incorrect'
assert strong['clap_effect_reduction_db'] > reference['clap_effect_reduction_db'] + 3
assert min(strong['voiced_event_effect_reduction_db']) > min(reference['voiced_event_effect_reduction_db']) + 3
assert strong['mixture_output_si_sdr_db'] > reference['mixture_output_si_sdr_db'] + 4
assert strong['speech_only_si_sdr_db'] > 15 and abs(strong['speech_level_change_db']) < 3
results['acceptance_passed'] = True
(folder / 'metrics.json').write_text(json.dumps(results, indent=2))
report = ('Production C DSP validation passed.\n'
          f"Strong clap-effect reduction: {strong['clap_effect_reduction_db']:.2f} dB; "
          f"worst voiced clap: {min(strong['voiced_event_effect_reduction_db']):.2f} dB.\n"
          f"Speech preservation SI-SDR: {strong['speech_only_si_sdr_db']:.2f} dB; "
          f"speech level change: {strong['speech_level_change_db']:.3f} dB.\n"
          f"Mixture SI-SDR: {strong['mixture_output_si_sdr_db']:.2f} dB "
          f"(RNNoise reference: {reference['mixture_output_si_sdr_db']:.2f} dB).\n"
          'Verified 8672-sample / 180.67 ms alignment; bypass exact within 1e-6.\n'
          'Every production probe returned zero processing errors and dropped input samples.\n'
          'Controlled evidence uses one speech excerpt and one real clap excerpt repeated during six voiced windows.\n')
(folder / 'report.txt').write_text(report)
print(report)
