// iHearYou | Signature: i729
// Copyright (c) 2026 i729. GPL-3.0-or-later.
// Offline research only; not linked into the application.
#include <speex/speex_echo.h>
#include <stdio.h>
#include <stdint.h>
#include <time.h>
int main(int argc, char **argv) {
    if (argc != 4) return 2;
    FILE *reference = fopen(argv[1], "rb"), *microphone = fopen(argv[2], "rb"), *output = fopen(argv[3], "wb");
    if (!reference || !microphone || !output) return 3;
    const int frame = 160;
    int rate = 16000;
    SpeexEchoState *state = speex_echo_state_init(frame, 8000);
    if (!state || speex_echo_ctl(state, SPEEX_ECHO_SET_SAMPLING_RATE, &rate)) return 4;
    int16_t ref[160], mic[160], clean[160];
    size_t frames = 0;
    clock_t start = clock();
    while (fread(ref, sizeof(int16_t), frame, reference) == frame && fread(mic, sizeof(int16_t), frame, microphone) == frame) {
        speex_echo_cancellation(state, mic, ref, clean);
        if (fwrite(clean, sizeof(int16_t), frame, output) != frame) return 5;
        ++frames;
    }
    int error = ferror(reference) || ferror(microphone) || ferror(output);
    printf("{\"frames\":%zu,\"cpu_seconds\":%.8f,\"io_error\":%d}\n", frames, (double)(clock()-start)/CLOCKS_PER_SEC, error);
    speex_echo_state_destroy(state);
    fclose(reference); fclose(microphone);
    if (fclose(output)) error = 1;
    return error ? 5 : 0;
}
