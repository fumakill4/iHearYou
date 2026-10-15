# Krisp features worth implementing in iHearYou

Created by i729. Research date: 16 October 2026.

## Product constraint and outcome

The user requires **no subscription in iHearYou for now**. The proposed implementation paths use local processing and avoid a recurring hosted API dependency. This document distinguishes package evidence, vendor claims, proposals, and measured experiments. It does not announce new app features or a new release.

The highest-value improvements are target-speaker isolation, playback-reference echo cancellation, input clipping protection, and measured device/performance adaptation. The current v1.4.0 release remains the stable baseline; background phone-video voices remain an unresolved issue.

## What was actually inspected

Static inspection used the already-expanded, user-supplied Krisp 3.17.6 ARM64 package. All 26 packed application JS/JSON files were checked/extracted locally from an ASAR inventory containing 185 entries. The ASAR SHA-256 is `f89590cfbc104184fba7bd2d6f292c39191dc4a6a7bfe5460af3ef243fda86a3`. Native symbols and diagnostic strings were inspected with `nm -C` and `strings`; no extracted application code or installer script was executed.

Relevant local evidence is in the ignored `build/reference/krisp-asar-analysis/` directory: `audio-feature-source-contexts.json`, `audio-feature-strings.json`, and `native-audio-feature-symbols.txt`. Extracted JS, binaries and model files are not included in public iHearYou source or app bundles.

| Feature | Direct evidence in this package | What that establishes |
| --- | --- | --- |
| Separate noise and human-voice model paths | `models/audio/models.json` lists `nc-outbound-*` and `hvc-outbound-*` at 32 kHz, narrowband noise models at 8 kHz; Bootstrap contains BVC processing options | Distinct model selections exist; their measured ability is not established by filenames alone |
| Echo reference and microphone processing | Shared AEC identifiers in separate `aecMonitor`/`aecProcessor` graph nodes; `processingDelayMs`; native `AECSDK::AnalyzeReverseStream`, `ProcessStream`, `SetStreamSpec` | Speaker/reference analysis and microphone cancellation are separate operations with delay handling |
| Clipping detection and automatic mic volume | Native `EnableClippingDetection`, source configuration for detection windows/thresholds, and a microphone clipping callback that invokes a volume-controller action in automatic mode | Clipping is detected on input and can trigger volume control, rather than only limiting final output |
| Smooth gain control | Readable `gainControlConfig` with separate attack/release, gain bounds, and a level floor | Gain behavior is bounded and smoothed; copying its numeric defaults would not establish good iHearYou behavior |
| Quality/performance modes | Bootstrap `BestQuality`/`BestPerformance` processing options; model manifest contains distinct model/performance entries | Multiple processing choices exist; manifest numbers are not measured CPU percentages |
| Independent inbound processing and reverberation-related settings | Separate inbound manifest; distinct microphone/speaker graphs; NC graph has an `rdThreshold` parameter | Separate receive-side processing exists; a parameter name alone does not prove a specific dereverberation algorithm |

The native core and `.kef` models are compiled assets, not a complete recoverable development source tree. Architectural findings can inform independently written code. They do not provide a ready-to-copy free voice-isolation engine.

## Comparison with the supplied older Intel package

The user subsequently supplied `Krisp_3.6.8_x64.pkg`, describing it as an older paid version. Static checks verified an Apple-issued Krisp installer signature and trusted notarization, with a signing timestamp of 10 October 2025. SHA-256: `e2e8db82d42d2c76e2f51c1ac9efe735e5e8aa4c0770473d14ee3d96f4a53c2d`. The nested app reports version 3.6.8; its executable and media module are x86_64. No installer script, app or account activation flow was executed, so account entitlement was not independently verified.

Its ASAR has 66 entries; 14 packed JS files and 2 JSON files were extracted locally. The older `.webpack` layout differs from the newer `.vite` layout. Its graph also contains separate AEC monitor/processor stages with delay settings, native `KrispEchoCancellerSDK::AnalyzeReverseStream` / `ProcessStream`, clipping detection, and quality/performance options. These corroborate that the relevant architecture already existed in the older app.

| Model group | 3.6.8 Intel compared with 3.17.6 ARM |
| --- | --- |
| Five noise/reverberation files: `c8.f.m`, `c8.f.s`, `c5.n.s`, `c8.w.m`, `c6.b78b81` | Full-file contents and SHA-256 values are identical |
| Human-voice path `hs.c6.f.m.75df8f.berlin.kef` | Different contents: 29,434,098 bytes versus 14,889,028 bytes |
| Human-voice path `hs.c6.f.s.de56df.bucharest.kef` | Different contents: 15,122,004 bytes versus 7,732,977 bytes |

The human-voice model differences are not confined to a tiny header: no 64 KiB block at the same offset matched in the overlapping ranges. This does **not** establish different training quality or the reason for the size difference; architecture-specific representation or packing remain possibilities. Static inspection cannot establish that a paid account has a superior algorithm, or that the older model sounds better. Identical filenames also cannot substitute for pinned model checksums.

The comparison strengthens the proposal to maintain separate noise and target-speaker stages in iHearYou and to evaluate quality/performance explicitly. It does not supply an ARM-native, freely redistributable replacement engine. Raw manifests, extracted code, binaries and the complete hash comparison remain under ignored `build/reference/krisp-3.6.8-analysis/`.

## Priorities for iHearYou

| Priority | Improvement and user benefit | Local implementation path | Readiness / acceptance requirement |
| --- | --- | --- | --- |
| High | **Target-speaker isolation:** reject another person or phone-video voice while retaining the user | Evaluate a speaker separator plus matching against an optional clean voice reference; start with saved-recording processing before live use | Research required: preserve Indonesian/AirPods speech, reject target-absent speech, handle overlapping and louder interference, establish model redistribution rights, measure CPU and latency |
| High | **Mac playback echo rejection:** reduce notifications, video and meeting audio that speakers leak into the mic | A private playback-reference tap plus an open-source AEC, with capture timestamps, device-clock alignment, own-output exclusion and independent microphone input | Feasible architecture; experimental AEC below has not passed preservation gates, and no live reference capture is integrated |
| High | **Clipping and recording-health protection:** prevent distorted recordings and make problems visible | Count raw-input clipped samples and sustained near-full-scale blocks; show an actionable local warning; use supported hardware input-volume controls only in a visible optional automatic mode | Small/medium scope; test clipping before inference, unsupported controls, reconnection and noise-only scenes |
| Medium | **Speech-aware automatic level:** keep quiet/loud speech more consistent | Bounded gain changes during confident speech with a conservative limiter; freeze upward gain during silence/noise | Do not indiscriminately re-enable AGC on AirPods or boost the noise floor; preserve existing manual gain |
| Medium | **Device/CPU adaptation:** prevent overload and unnecessary Bluetooth quality loss | Use effective signal bandwidth and measured inference/backlog time to select validated profiles, with hysteresis and explicit status | A reported hardware sample rate is insufficient; switching during recording must preserve or explicitly segment the file |
| Later | **Receive-side noise reduction:** clean noisy remote audio for listening | Separate denoiser state and a selected playback capture/render path | Requires routing/permission and video-sync testing; not the same feature as live monitoring of the user's mic |

Diarization only labels who speaks; it does not by itself remove another voice from the audio. Likewise, an AEC can cancel only a sound represented in its reference. A separate phone playing in the room provides no Mac digital playback reference, so target-speaker isolation remains necessary for that case.

## Target-speaker candidates screened

- **Krisp BVC:** the [vendor documentation](https://sdk-docs.krisp.ai/docs/krisp-rtc-bvc-nc) describes background-voice removal without user enrollment and compatibility with most Bluetooth headsets, including AirPods. This demonstrates a relevant product capability, not permission to redistribute its bundled models or an established free implementation path.
- **SpeechBrain separation + ECAPA matching:** the official [WHAMR 16 kHz SepFormer model](https://huggingface.co/speechbrain/sepformer-whamr16k) separates two sources, and the official [ECAPA model](https://huggingface.co/speechbrain/spkrec-ecapa-voxceleb) extracts speaker embeddings; both model cards declare Apache-2.0. Combining separation with reference matching is an **iHearYou research proposal**, not a measured or production-ready result. No benchmark has been run here; evaluate offline first and check complete dependency notices before distribution.
- **WeSep:** the [current upstream README](https://github.com/wenet-e2e/wesep) explicitly describes a research preview; its validated pretrained packages and deployment interfaces are not ready. Legacy deployment claims should not be treated as current support.
- **Vanta:** the author's [repository](https://github.com/Komalpreet2809/Vanta) and [download script](https://github.com/Komalpreet2809/Vanta/blob/main/scripts/download_weights.py) expose a matched separator/encoder pair and local inference. Global utterance normalization, a limited training regime, and unverified complete model/source licensing make it an experimental candidate, not a drop-in live engine.
- **Other apparent shortcuts:** the [VoiceSplit issue discussion](https://github.com/k2-fsa/sherpa-onnx/issues/3674) reports reliability problems during silence/long clips; [solo-audio-core's fetch script](https://github.com/sihekuang/solo-audio-core/blob/main/scripts/fetch-models.sh) relies on another local checkout rather than published model downloads. Neither is a verified ready solution.
- **Restricted candidates:** the upstream [SpeakerBeam license](https://github.com/BUTSpeechFIT/speakerbeam/blob/main/LICENSE.txt) is evaluation-restricted, despite some third-party conversion claims; the [USEF-TSE ONNX card](https://huggingface.co/bitsydarel/usef-tse-onnx) specifies non-commercial use and 8 kHz audio. Do not bundle these as though they were unrestricted production dependencies.

No user voice profile was created, and no private audio was uploaded or sent to any demo service.

## Echo-reference feasibility experiment

[SpeexDSP](https://github.com/xiph/speexdsp) provides a local AEC with a [BSD-style license](https://github.com/xiph/speexdsp/blob/master/COPYING). Its [reference API](https://www.speex.org/docs/manual/speex-manual/node7.html) accepts microphone and playback signals separately. [WebRTC's APM interface](https://webrtc.googlesource.com/src/+/refs/heads/main/modules/audio_processing/include/audio_processing.h) is another candidate for reverse/capture processing and delay control; it has not been benchmarked here.

Built **SpeexDSP 1.2.1 locally in the ignored research directory**, without global installation or app integration. Official source archive: `https://downloads.xiph.org/releases/speex/speexdsp-1.2.1.tar.gz`, SHA-256 `8c777343e4a6399569c72abc38a95b24db56882c83dbdb6c6424a5f4aeb54d3d`.

The original iHearYou harness uses 16 kHz PCM, 10 ms frames and a 500 ms echo filter. It combines the existing locally held public speech fixture and macOS Glass sound with a **synthetic synchronized linear echo path** at 60/83/112/151 ms. There was no physical speaker/microphone recording.

| Measurement | Result |
| --- | ---: |
| Echo reduction after adaptation, echo-only test | 18.78 dB |
| First isolated notification, cold state | 13.77 dB |
| Double-talk input → output SI-SDR | 8.19 → 10.66 dB |
| Double-talk output level change | −0.03 dB |
| Zero-reference waveform identity SNR | 11.15 dB |
| Echo-only CPU real-time factor | 0.004 |
| Candidate acceptance gate | **Failed** |

The pinned `libspeexdsp/mdf.c` includes input DC-notch filtering, so the zero-reference waveform difference is not evidence that speech was simply erased. However, this configuration failed the deliberate preservation/double-talk thresholds and must not be shipped unchanged. A robust idle-reference bypass/tail policy, delay tracking, comparison against a filter-matched reference, additional speech/perceptual evaluation and a WebRTC AEC3 comparison are still needed. Do not claim complete notification removal from these synthetic results.

For live reference capture, [Apple's Core Audio tap sample](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps) requires macOS 14.2+ and system-audio capture permission with `NSAudioCaptureUsageDescription`. The current minimum is macOS 14.0, so this must be an availability-gated optional feature. Capture only the reference required for cancellation, exclude the app's own output, and do not mix or save the reference into microphone recordings.

### Reproduce the experiment

After downloading, checking the hash, and expanding the official archive under `build/reference/`:

```sh
cd build/reference/speexdsp-1.2.1
./configure --disable-shared --enable-static --disable-examples
make -j4
cd ../../..
python3 scripts/evaluate-echo-reference.py
```

The Python environment needs NumPy and FFmpeg. The existing local public speech fixture must be present at `build/clap-evaluation/speech.f32`; its evaluation-only provenance is recorded in `THIRD_PARTY_NOTICES.md`. Generated PCM and metrics stay under ignored `build/echo-research/`. The script writes metrics and exits unsuccessfully while the candidate gate fails; that is the expected research outcome, not a passing app regression test.

## Current delivery status

Completed static comparison, candidate screening, a reproducible negative/positive AEC experiment, and a prioritized integration plan. App behavior, version, installed binaries and the published v1.4.0 artifacts are unchanged. No subscription, trial, billing flow, paid SDK dependency or new system-audio permission was introduced.
