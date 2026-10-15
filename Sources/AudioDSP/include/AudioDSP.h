// iHearYou | Signature: i729
// Original integration code. DPDFNet, sherpa-onnx and BlackHole retain their own credits.
#ifndef IHEARYOU_DSP_H
#define IHEARYOU_DSP_H
#include <stdint.h>
typedef struct IHProcessor IHProcessor;
typedef struct {
    float input_db, output_db, voice_probability;
    uint64_t input_drops, output_underruns, processing_errors;
} IHStats;
IHProcessor *ih_create(double input_rate, const char *model_path, const char *vad_path);
// Bluetooth: DPDFNet2 16 kHz with a GTCRN speech safety model; output stays 48 kHz.
IHProcessor *ih_create_headset(double input_rate, const char *model_path, const char *guard_path, const char *vad_path);
uint32_t ih_delay_samples(void);
// After capture stops, pad one 10 ms input block to drain delayed recording tails.
void ih_pad_silence(IHProcessor *p);
void ih_destroy(IHProcessor *p);
void ih_settings(IHProcessor *p, int enabled, float strength, float gain_db, int gate);
void ih_capture(IHProcessor *p, const float *mono, uint32_t count);
// Call on one processing queue. Returns exactly one 480-sample / 10 ms frame.
int ih_next_frame(IHProcessor *p, float *raw, float *clean);
// Each lane has exactly one writer (processing queue) and one render reader.
void ih_publish(IHProcessor *p, const float *clean, int virtual_enabled, int monitor_enabled);
void ih_render(IHProcessor *p, float *output, uint32_t count, int monitor_lane);
void ih_render_rate(IHProcessor *p, float *output, uint32_t count, int monitor_lane, double output_rate);
IHStats ih_stats(IHProcessor *p);
uint32_t ih_queued_input(IHProcessor *p);
#endif
