// iHearYou | Signature: i729
// Offline verification uses the identical processing API as the live app.
#include "AudioDSP.h"
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <inttypes.h>
int main(int argc, char **argv) {
    if (argc < 6) return 2;
    FILE *in = fopen(argv[1], "rb"), *out = fopen(argv[2], "wb");
    if (!in || !out) return 3;
    IHProcessor *p = argc > 7 && atoi(argv[6]) ? ih_create_headset(48000, argv[4], argv[7], argv[5]) : ih_create(48000, argv[4], argv[5]);
    if (!p) return 4;
    int mode = atoi(argv[3]);
    if (mode < 0 || mode > 3) { ih_destroy(p); fclose(in); fclose(out); return 2; }
    ih_settings(p, mode != 0, mode == 1 ? .65f : 1, 0, mode == 3);
    float block[480], raw[480], clean[480];
    size_t count; uint64_t input_samples = 0, frames = 0, flushed_frames = 0; clock_t start = clock();
    while ((count = fread(block, sizeof(float), 480, in))) {
        input_samples += count;
        ih_capture(p, block, (uint32_t)count);
        while (ih_next_frame(p, raw, clean)) { fwrite(clean, sizeof(float), 480, out); ++frames; }
    }
    // Flush model lookahead without losing the last spoken syllable in the fixture.
    for (int i = 0; i < 22; i++) {
        for (int j = 0; j < 480; j++) block[j] = 0;
        ih_capture(p, block, 480);
        while (ih_next_frame(p, raw, clean)) { fwrite(clean, sizeof(float), 480, out); ++flushed_frames; }
    }
    IHStats stats = ih_stats(p);
    int io_error = ferror(in) || ferror(out);
    printf("{\"input_samples\":%" PRIu64 ",\"processed_frames\":%" PRIu64 ",\"flush_frames\":%" PRIu64
           ",\"audio_seconds\":%.8f,\"cpu_seconds\":%.8f,\"processing_errors\":%" PRIu64
           ",\"input_drops\":%" PRIu64 ",\"io_error\":%d}\n", input_samples, frames, flushed_frames,
           input_samples / 48000.0, (double)(clock() - start) / CLOCKS_PER_SEC,
           stats.processing_errors, stats.input_drops, io_error);
    ih_destroy(p); fclose(in); fclose(out);
    return stats.processing_errors || stats.input_drops || io_error ? 5 : 0;
}
