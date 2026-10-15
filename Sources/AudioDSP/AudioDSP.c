// iHearYou | Signature: i729
// Copyright (c) 2026 i729. GPL-3.0-or-later.
#include "AudioDSP.h"
#include "sherpa-onnx/c-api/c-api.h"
#include <stdatomic.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

#define CAPACITY 32768u
#define MASK (CAPACITY - 1u)
#define FRAME 480u
#define PREROLL 5760u
#define FIR_TAPS 1025u
#define FIR_HALF 512u
#define DELAY (2400u + PREROLL + FIR_HALF)
typedef struct { float samples[CAPACITY]; _Atomic uint64_t read, write; } Ring;
struct IHProcessor {
    const SherpaOnnxOnlineSpeechDenoiser *model, *headset_guard;
    const SherpaOnnxVoiceActivityDetector *vad, *guard_vad;
    Ring capture, virtual_out, monitor, headset_out, headset_guard_out;
    double step, phase, render_phase[2];
    float frame[FRAME], dry_delay[DELAY], wet_delay[PREROLL];
    float fir[2048], fir_coeff[FIR_HALF + 1], gate_gain;
    uint32_t fir_index;
    uint32_t wet_index, headset_hold, interpolation_index, wet_length;
    float interpolation_history[32], interpolation_coeff[63], protection_gain;
    uint32_t frame_count, delay_index, delay;
    _Atomic int enabled, gate, headset;
    _Atomic float strength, gain, input_db, output_db, voice;
    _Atomic uint64_t drops, underruns, errors;
    uint64_t frames;
};
static uint32_t available(Ring *r) {
    return (uint32_t)(atomic_load_explicit(&r->write, memory_order_acquire) - atomic_load_explicit(&r->read, memory_order_relaxed));
}
static int put(Ring *r, float value) {
    uint64_t w = atomic_load_explicit(&r->write, memory_order_relaxed);
    if (w - atomic_load_explicit(&r->read, memory_order_acquire) == CAPACITY) return 0;
    r->samples[w & MASK] = value;
    atomic_store_explicit(&r->write, w + 1, memory_order_release);
    return 1;
}
static int get(Ring *r, float *value) {
    uint64_t rd = atomic_load_explicit(&r->read, memory_order_relaxed);
    if (rd == atomic_load_explicit(&r->write, memory_order_acquire)) return 0;
    *value = r->samples[rd & MASK];
    atomic_store_explicit(&r->read, rd + 1, memory_order_release);
    return 1;
}
static float db(float energy) { return fmaxf(-90, 10 * log10f(fmaxf(energy / FRAME, 1e-9f))); }
static IHProcessor *create(double rate, const char *model_path, const char *vad_path, const char *guard_path) {
    int headset = guard_path != NULL;
    if (!model_path || !vad_path || !isfinite(rate) || rate < 8000 || rate > 192000) return NULL;
    IHProcessor *p = calloc(1, sizeof(*p));
    if (!p) return NULL;
    SherpaOnnxOnlineSpeechDenoiserConfig config = {0};
    config.model.dpdfnet.model = model_path;
    config.model.dpdfnet.attenuation_limit_db = 100;
    config.model.num_threads = 1; config.model.provider = "cpu";
    p->model = SherpaOnnxCreateOnlineSpeechDenoiser(&config);
    if (!p->model) { free(p); return NULL; }
    if (SherpaOnnxOnlineSpeechDenoiserGetSampleRate(p->model) != (headset ? 16000 : 48000) ||
        SherpaOnnxOnlineSpeechDenoiserGetFrameShiftInSamples(p->model) != (headset ? 160 : FRAME)) {
        SherpaOnnxDestroyOnlineSpeechDenoiser(p->model); free(p); return NULL;
    }
    SherpaOnnxVadModelConfig vad = {0};
    vad.silero_vad.model = vad_path;
    vad.silero_vad.threshold = .35f;
    vad.silero_vad.min_silence_duration = headset ? .064f : .32f;
    vad.silero_vad.min_speech_duration = .032f;
    vad.silero_vad.window_size = 512;
    vad.silero_vad.max_speech_duration = 15;
    vad.sample_rate = 16000; vad.num_threads = 1; vad.provider = "cpu";
    p->vad = SherpaOnnxCreateVoiceActivityDetector(&vad, 20);
    if (!p->vad) { SherpaOnnxDestroyOnlineSpeechDenoiser(p->model); free(p); return NULL; }
    // Symmetric 70 Hz high-pass: suppress low rumble without the phase
    // distortion of a causal biquad across the voice fundamental. Its fixed
    // 512-sample delay is included in the dry/reference alignment.
    double lowpass[FIR_TAPS], sum = 0;
    for (uint32_t i = 0; i < FIR_TAPS; ++i) {
        double n = (double)i - FIR_HALF, fc = 70.0 / 48000.0;
        double sinc = n == 0 ? 2 * fc : sin(2 * 3.141592653589793 * fc * n) / (3.141592653589793 * n);
        double window = .5 - .5 * cos(2 * 3.141592653589793 * i / (FIR_TAPS - 1));
        lowpass[i] = sinc * window; sum += lowpass[i];
    }
    for (uint32_t i = 0; i <= FIR_HALF; ++i)
        p->fir_coeff[i] = (i == FIR_HALF ? 1.f : 0.f) - (float)(lowpass[i] / sum);
    p->wet_length = PREROLL;
    if (headset) {
        SherpaOnnxOnlineSpeechDenoiserConfig safety = {0};
        safety.model.gtcrn.model = guard_path;
        safety.model.num_threads = 1; safety.model.provider = "cpu";
        p->headset_guard = SherpaOnnxCreateOnlineSpeechDenoiser(&safety);
        if (!p->headset_guard || SherpaOnnxOnlineSpeechDenoiserGetSampleRate(p->headset_guard) != 16000 ||
            SherpaOnnxOnlineSpeechDenoiserGetFrameShiftInSamples(p->headset_guard) != 256) {
            ih_destroy(p); return NULL;
        }
        SherpaOnnxVadModelConfig guard_vad = vad;
        guard_vad.silero_vad.min_silence_duration = .064f;
        p->guard_vad = SherpaOnnxCreateVoiceActivityDetector(&guard_vad, 20);
        if (!p->guard_vad) { ih_destroy(p); return NULL; }
        // Both models share 60 ms of alignment: DPDFNet has 640 samples of
        // intrinsic lookahead at 16 kHz; GTCRN has none. FIFOs absorb their
        // different STFT block schedules. Both feed one bandlimited upsampler.
        for (uint32_t i = 0; i < 320; ++i) put(&p->headset_out, 0);
        for (uint32_t i = 0; i < 960; ++i) put(&p->headset_guard_out, 0);
        // Account for the extra 10 ms scheduling and interpolation filter's
        // 31-sample delay within the existing pre-roll budget, keeping original/clean/bypass aligned.
        p->wet_length = PREROLL - FRAME - 31;
        double sum = 0;
        for (int i = 0; i < 63; ++i) {
            int n = i - 31;
            double fc = .15; // 7.2 kHz passband, reject 16 kHz images.
            double sinc = n == 0 ? 2 * fc : sin(2 * 3.141592653589793 * fc * n) / (3.141592653589793 * n);
            double window = .42 - .5 * cos(2 * 3.141592653589793 * i / 62) + .08 * cos(4 * 3.141592653589793 * i / 62);
            p->interpolation_coeff[i] = (float)(sinc * window);
            sum += p->interpolation_coeff[i];
        }
        for (int i = 0; i < 63; ++i) p->interpolation_coeff[i] *= (float)(3 / sum);
        memset(p->fir_coeff, 0, sizeof(p->fir_coeff));
        p->fir_coeff[FIR_HALF] = 1;
    }
    // Pinned DPDFNet2 HR: 480 STFT buffering + 1920 neural lookahead samples.
    // Verified with speech-only cross-correlation and the same offset for mixtures.
    p->delay = DELAY;
    p->step = rate / 48000.;
    atomic_init(&p->enabled, 1); atomic_init(&p->strength, 1); atomic_init(&p->gain, 1);
    atomic_init(&p->headset, headset);
    atomic_init(&p->input_db, -90); atomic_init(&p->output_db, -90);
    return p;
}
IHProcessor *ih_create(double rate, const char *model_path, const char *vad_path) { return create(rate, model_path, vad_path, NULL); }
IHProcessor *ih_create_headset(double rate, const char *model_path, const char *guard_path, const char *vad_path) { return create(rate, model_path, vad_path, guard_path); }
void ih_destroy(IHProcessor *p) { if (p) { SherpaOnnxDestroyVoiceActivityDetector(p->vad); SherpaOnnxDestroyOnlineSpeechDenoiser(p->model); if (p->headset_guard) SherpaOnnxDestroyOnlineSpeechDenoiser(p->headset_guard); if (p->guard_vad) SherpaOnnxDestroyVoiceActivityDetector(p->guard_vad); free(p); } }
uint32_t ih_delay_samples(void) { return DELAY; }
void ih_settings(IHProcessor *p, int enabled, float strength, float gain_db, int gate) {
    atomic_store(&p->enabled, enabled);
    atomic_store(&p->strength, fminf(1, fmaxf(0, strength)));
    atomic_store(&p->gain, powf(10, fminf(12, fmaxf(-12, gain_db)) / 20));
    atomic_store(&p->gate, gate);
}
void ih_capture(IHProcessor *p, const float *mono, uint32_t count) {
    for (uint32_t i = 0; i < count; ++i) {
        float x = isfinite(mono[i]) ? fminf(1, fmaxf(-1, mono[i])) : 0;
        if (!put(&p->capture, x)) atomic_fetch_add(&p->drops, 1);
    }
}
void ih_pad_silence(IHProcessor *p) {
    static const float silence[2048] = {0};
    ih_capture(p, silence, (uint32_t)ceil(FRAME * p->step) + 2);
}
uint32_t ih_queued_input(IHProcessor *p) { return available(&p->capture); }
int ih_next_frame(IHProcessor *p, float *raw, float *clean) {
    Ring *r = &p->capture;
    // Bound latency after a stalled worker. Only the consumer advances read.
    uint32_t pending = available(r);
    if (pending > (uint32_t)(48000 * p->step / 4)) {
        uint32_t discard = pending - (uint32_t)(48000 * p->step / 10);
        atomic_fetch_add_explicit(&r->read, discard, memory_order_release);
        atomic_fetch_add(&p->drops, discard);
        p->phase = 0;
    }
    while (p->frame_count < FRAME) {
        uint32_t consumed = (uint32_t)floor(p->phase + p->step);
        if (available(r) < (consumed > 2 ? consumed : 2)) return 0;
        uint64_t rd = atomic_load_explicit(&r->read, memory_order_relaxed);
        float a = r->samples[rd & MASK], b = r->samples[(rd + 1) & MASK];
        p->frame[p->frame_count++] = a + (b - a) * (float)p->phase;
        p->phase += p->step;
        uint32_t skip = (uint32_t)floor(p->phase);
        atomic_store_explicit(&r->read, rd + skip, memory_order_release);
        p->phase -= skip;
    }
    float filtered[FRAME] = {0}, energy_in = 0, energy_out = 0;
    int enabled = atomic_load(&p->enabled);
    // Detect speech before suppression so a denoiser cannot erase its own gate trigger. Keep 120 ms of
    // look-behind so the detector can open before the delayed first consonant.
    float vad_input[FRAME / 3];
    for (uint32_t i = 0; i < FRAME / 3; ++i)
        vad_input[i] = (p->frame[i*3] + p->frame[i*3+1] + p->frame[i*3+2]) / 3;
    SherpaOnnxVoiceActivityDetectorAcceptWaveform(p->vad, vad_input, FRAME / 3);
    int speaking = SherpaOnnxVoiceActivityDetectorDetected(p->vad);
    if (atomic_load(&p->headset)) {
        // A near-mouth headset may remove the high-frequency cues used by VAD.
        // Preserve low-band speech too; never hard-mute a clear headset word
        // solely because a full-band speech classifier rejects that frame.
        float energy = 0;
        for (uint32_t i = 0; i < FRAME; ++i) energy += p->frame[i] * p->frame[i];
        if (speaking || energy / FRAME > 1e-5f) p->headset_hold = 40;
        else if (p->headset_hold) --p->headset_hold;
        speaking = p->headset_hold > 0;
    }
    while (!SherpaOnnxVoiceActivityDetectorEmpty(p->vad)) SherpaOnnxVoiceActivityDetectorPop(p->vad);
    const SherpaOnnxDenoisedAudio *chunk = SherpaOnnxOnlineSpeechDenoiserRun(p->model, p->frame, FRAME, 48000);
    if (chunk) {
        if (atomic_load(&p->headset)) {
            if (chunk->sample_rate == 16000 && chunk->n >= 0 && chunk->n <= 512) {
                for (int j = 0; j < chunk->n; ++j)
                    if (!put(&p->headset_out, chunk->samples[j])) atomic_fetch_add(&p->errors, 1);
            } else atomic_fetch_add(&p->errors, 1);
        } else {
            if (chunk->n == FRAME && chunk->sample_rate == 48000) memcpy(filtered, chunk->samples, sizeof(filtered));
            else if (chunk->n != 0 || p->frames > 0) atomic_fetch_add(&p->errors, 1);
        }
        SherpaOnnxDestroyDenoisedAudio(chunk);
    } else if (!atomic_load(&p->headset) && p->frames > 0) atomic_fetch_add(&p->errors, 1);
    if (atomic_load(&p->headset)) {
        const SherpaOnnxDenoisedAudio *guard = SherpaOnnxOnlineSpeechDenoiserRun(p->headset_guard, p->frame, FRAME, 48000);
        if (guard) {
            if (guard->sample_rate == 16000 && guard->n >= 0 && guard->n <= 512) {
                for (int j = 0; j < guard->n; ++j)
                    if (!put(&p->headset_guard_out, guard->samples[j])) atomic_fetch_add(&p->errors, 1);
            } else atomic_fetch_add(&p->errors, 1);
            SherpaOnnxDestroyDenoisedAudio(guard);
        }
        float primary[160] = {0}, safety[160] = {0};
        float primary_energy = 0, safety_energy = 0;
        for (uint32_t j = 0; j < 160; ++j) {
            if (!get(&p->headset_out, &primary[j])) atomic_fetch_add(&p->errors, 1);
            if (!get(&p->headset_guard_out, &safety[j])) atomic_fetch_add(&p->errors, 1);
            primary_energy += primary[j] * primary[j];
            safety_energy += safety[j] * safety[j];
        }
        // Rescue speech only when the primary model collapses relative to an
        // independent narrowband model. Never mix raw background audio back.
        SherpaOnnxVoiceActivityDetectorAcceptWaveform(p->guard_vad, safety, 160);
        int detected_speech = SherpaOnnxVoiceActivityDetectorDetected(p->guard_vad);
        while (!SherpaOnnxVoiceActivityDetectorEmpty(p->guard_vad)) SherpaOnnxVoiceActivityDetectorPop(p->guard_vad);
        float protect = detected_speech && safety_energy > 1.6e-5f && primary_energy < safety_energy * .16f ? 1 : 0;
        // Studio prioritizes rejection of transient interference. Limit the
        // rescue contribution so a barking event cannot reopen the whole
        // secondary path; Natural provides the most protection for soft speech.
        protect *= atomic_load(&p->gate) ? .15f : atomic_load(&p->strength) < .9f ? 1.f : .5f;
        for (uint32_t j = 0; j < 160; ++j) {
            p->protection_gain += (protect - p->protection_gain) * (protect ? .02f : .001f);
            float sample = primary[j] + p->protection_gain * (safety[j] - primary[j]);
            p->interpolation_history[p->interpolation_index] = sample;
            for (uint32_t phase = 0; phase < 3; ++phase) {
                float value = 0;
                for (uint32_t tap = phase, k = 0; tap < 63; tap += 3, ++k)
                    value += p->interpolation_coeff[tap] * p->interpolation_history[(p->interpolation_index - k) & 31u];
                filtered[j*3 + phase] = value;
            }
            p->interpolation_index = (p->interpolation_index + 1) & 31u;
        }
    }
    ++p->frames;
    float floor_gain = atomic_load(&p->strength) < .9f ? .05f : atomic_load(&p->gate) ? 0 : .015f;
    float target = speaking ? 1 : floor_gain;
    float gain = atomic_load(&p->gain);
    for (uint32_t i = 0; i < FRAME; ++i) {
        // Keep original/reference and bypass aligned with model + pre-roll.
        float dry = p->dry_delay[p->delay_index];
        p->dry_delay[p->delay_index] = p->frame[i];
        p->delay_index = (p->delay_index + 1) % p->delay;
        raw[i] = dry;
        float wet = p->wet_delay[p->wet_index];
        p->fir[p->fir_index] = filtered[i];
        float shaped = p->fir_coeff[FIR_HALF] * p->fir[(p->fir_index - FIR_HALF) & 2047u];
        for (uint32_t j = 0; j < FIR_HALF; ++j)
            shaped += p->fir_coeff[j] * (p->fir[(p->fir_index - j) & 2047u]
                      + p->fir[(p->fir_index - (FIR_TAPS - 1 - j)) & 2047u]);
        p->fir_index = (p->fir_index + 1) & 2047u;
        p->wet_delay[p->wet_index] = shaped;
        p->wet_index = (p->wet_index + 1) % p->wet_length;
        // 3 ms attack / 40 ms release, no hard frame-boundary switch/click.
        p->gate_gain += (target - p->gate_gain) * (target > p->gate_gain ? .00692f : .00052f);
        float y = (enabled ? wet * p->gate_gain : dry) * gain;
        if (!isfinite(y)) { y = 0; atomic_fetch_add(&p->errors, 1); }
        clean[i] = fminf(.99f, fmaxf(-.99f, y));
        energy_in += p->frame[i] * p->frame[i]; energy_out += clean[i] * clean[i];
    }
    atomic_store(&p->voice, speaking ? 1 : 0);
    atomic_store(&p->input_db, db(energy_in)); atomic_store(&p->output_db, db(energy_out));
    p->frame_count = 0;
    return 1;
}
void ih_publish(IHProcessor *p, const float *clean, int virtual_enabled, int monitor_enabled) {
    for (uint32_t i = 0; i < FRAME; ++i) {
        if (virtual_enabled) put(&p->virtual_out, clean[i]);
        if (monitor_enabled) put(&p->monitor, clean[i]);
    }
}
void ih_render(IHProcessor *p, float *output, uint32_t count, int monitor_lane) {
    Ring *r = monitor_lane ? &p->monitor : &p->virtual_out;
    uint32_t pending = available(r);
    if (pending > 4800) atomic_fetch_add_explicit(&r->read, pending - 1440, memory_order_release);
    int underflow = 0;
    for (uint32_t i = 0; i < count; ++i) if (!get(r, &output[i])) { output[i] = 0; underflow = 1; }
    if (underflow) atomic_fetch_add(&p->underruns, 1);
}
// AUHAL monitoring runs at the physical output rate, independently of the
// 48 kHz virtual mic. Bluetooth profile changes never reinterpret 48 kHz PCM.
void ih_render_rate(IHProcessor *p, float *output, uint32_t count, int lane, double rate) {
    lane = lane ? 1 : 0;
    if (!isfinite(rate) || rate < 8000 || rate > 192000) { memset(output, 0, count * sizeof(float)); return; }
    if (rate == 48000) { ih_render(p, output, count, lane); return; }
    Ring *r = lane ? &p->monitor : &p->virtual_out;
    uint32_t pending = available(r);
    if (pending > 4800) { atomic_fetch_add_explicit(&r->read, pending - 1440, memory_order_release); p->render_phase[lane] = 0; }
    double step = 48000.0 / rate;
    int underflow = 0;
    for (uint32_t i = 0; i < count; ++i) {
        uint32_t consumed = (uint32_t)floor(p->render_phase[lane] + step);
        if (available(r) < (consumed > 2 ? consumed : 2)) { output[i] = 0; underflow = 1; continue; }
        uint64_t rd = atomic_load_explicit(&r->read, memory_order_relaxed);
        float a = r->samples[rd & MASK], b = r->samples[(rd + 1) & MASK];
        output[i] = a + (b - a) * (float)p->render_phase[lane];
        p->render_phase[lane] += step;
        uint32_t skip = (uint32_t)floor(p->render_phase[lane]);
        atomic_store_explicit(&r->read, rd + skip, memory_order_release);
        p->render_phase[lane] -= skip;
    }
    if (underflow) atomic_fetch_add(&p->underruns, 1);
}
IHStats ih_stats(IHProcessor *p) {
    return (IHStats){atomic_load(&p->input_db), atomic_load(&p->output_db), atomic_load(&p->voice), atomic_load(&p->drops), atomic_load(&p->underruns), atomic_load(&p->errors)};
}
