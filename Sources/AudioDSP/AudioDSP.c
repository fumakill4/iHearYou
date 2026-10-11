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
typedef struct { float samples[CAPACITY]; _Atomic uint64_t read, write; } Ring;
struct IHProcessor {
    const SherpaOnnxOnlineSpeechDenoiser *model;
    Ring capture, virtual_out, monitor;
    double step, phase;
    float frame[FRAME], dry_delay[4800];
    uint32_t frame_count, delay_index, delay;
    _Atomic int enabled, gate;
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
IHProcessor *ih_create(double rate, const char *model_path) {
    if (!model_path || !isfinite(rate) || rate < 8000 || rate > 192000) return NULL;
    IHProcessor *p = calloc(1, sizeof(*p));
    if (!p) return NULL;
    SherpaOnnxOnlineSpeechDenoiserConfig config = {0};
    config.model.dpdfnet.model = model_path;
    config.model.dpdfnet.attenuation_limit_db = 100;
    config.model.num_threads = 1; config.model.provider = "cpu";
    p->model = SherpaOnnxCreateOnlineSpeechDenoiser(&config);
    if (!p->model) { free(p); return NULL; }
    if (SherpaOnnxOnlineSpeechDenoiserGetSampleRate(p->model) != 48000 ||
        SherpaOnnxOnlineSpeechDenoiserGetFrameShiftInSamples(p->model) != FRAME) {
        SherpaOnnxDestroyOnlineSpeechDenoiser(p->model); free(p); return NULL;
    }
    // Pinned DPDFNet2 HR: 480 STFT buffering + 1920 neural lookahead samples.
    // Verified with speech-only cross-correlation and the same offset for mixtures.
    p->delay = 2400;
    p->step = rate / 48000.;
    atomic_init(&p->enabled, 1); atomic_init(&p->strength, 1); atomic_init(&p->gain, 1);
    atomic_init(&p->input_db, -90); atomic_init(&p->output_db, -90);
    return p;
}
void ih_destroy(IHProcessor *p) { if (p) { SherpaOnnxDestroyOnlineSpeechDenoiser(p->model); free(p); } }
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
    const SherpaOnnxDenoisedAudio *chunk = SherpaOnnxOnlineSpeechDenoiserRun(p->model, p->frame, FRAME, 48000);
    if (chunk) {
        if (chunk->n == FRAME && chunk->sample_rate == 48000) memcpy(filtered, chunk->samples, sizeof(filtered));
        else if (chunk->n != 0 || p->frames > 0) atomic_fetch_add(&p->errors, 1);
        SherpaOnnxDestroyDenoisedAudio(chunk);
    } else if (p->frames > 0) atomic_fetch_add(&p->errors, 1);
    ++p->frames;
    // The online backend currently ignores its attenuation-limit config. Apply
    // explicit, delay-aligned limits here: Natural 20 dB, Balanced 30 dB, Strong full.
    float dry_mix = !enabled ? 1 : atomic_load(&p->strength) < .9f ? .1f : atomic_load(&p->gate) ? 0 : .0316227766f;
    float gain = atomic_load(&p->gain);
    for (uint32_t i = 0; i < FRAME; ++i) {
        // Keep original/reference, all presets and bypass at the same 50 ms delay.
        float dry = p->dry_delay[p->delay_index];
        p->dry_delay[p->delay_index] = p->frame[i];
        p->delay_index = (p->delay_index + 1) % p->delay;
        raw[i] = dry;
        float y = (filtered[i] * (1 - dry_mix) + dry * dry_mix) * gain;
        if (!isfinite(y)) { y = 0; atomic_fetch_add(&p->errors, 1); }
        clean[i] = fminf(.99f, fmaxf(-.99f, y));
        energy_in += p->frame[i] * p->frame[i]; energy_out += clean[i] * clean[i];
    }
    atomic_store(&p->voice, energy_out / FRAME > 1e-5f ? 1 : 0);
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
IHStats ih_stats(IHProcessor *p) {
    return (IHStats){atomic_load(&p->input_db), atomic_load(&p->output_db), atomic_load(&p->voice), atomic_load(&p->drops), atomic_load(&p->underruns), atomic_load(&p->errors)};
}
