# iHearYou acknowledgments

Created by **i729**. Signature: i729.

Original iHearYou application and integration copyright (c) 2026 i729, GPL-3.0-or-later.

## Shipped engine

**DPDFNet2_48khz_hr** — CEVA IP and contributors, Apache-2.0. Official model card: https://huggingface.co/Ceva-IP/DPDFNet ; source: https://github.com/ceva-ip/DPDFNet . Model card and license retained under `Vendor/DPDFNet`. Official model download: https://github.com/k2-fsa/sherpa-onnx/releases/download/speech-enhancement-models/dpdfnet2_48khz_hr.onnx . SHA-256: `0b399f8a58dc4d70d8cd97541f5c39869406145193b957d00a03b66070944928`.

**Silero VAD v5** — Silero Team, MIT. Source: https://github.com/snakers4/silero-vad/tree/v5.1 . Model provided by the official sherpa-onnx model release: https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad_v5.onnx . SHA-256: `6b99cbfd39246b6706f98ec13c7c50c6b299181f2474fa05cbc8046acc274396`. MIT license retained in `Vendor/Silero/LICENSE` and the app bundle. Detection runs locally; there is no enrollment or speaker identity model.

**sherpa-onnx 1.13.8** — k2-fsa and contributors, Apache-2.0: https://github.com/k2-fsa/sherpa-onnx/tree/v1.13.8 . Official macOS arm64 shared no-TTS runtime archive SHA-256: `f3e0cbd86cc3f38dad30c97921b40e9a8bcc6f2c943777eb76ad77176993e417`. Unmodified C API library SHA-256: `ae729669633008692c670d4e4c942db7ea5bdc38abc2f479516062d48849e9d1`. Header from tag v1.13.8 and license retained under `Vendor/Sherpa`.

**ONNX Runtime 1.28.2**, Microsoft and contributors, MIT: https://github.com/microsoft/onnxruntime . Included in the above official runtime archive; unmodified library SHA-256: `3567d114f7299d559993e536d605a6f46d7bc9d2542004accc80ee9bf5457f0b`. License retained in `Vendor/Sherpa/ONNXRuntime-LICENSE` and bundled with app. Local ad-hoc signing changes binary checksums after packaging.

**BlackHole 0.7.1** — copyright (c) 2019-2026 Existential Audio Inc., GPLv3: https://github.com/ExistentialAudio/BlackHole . Pinned commit `561d934c77a1fa64987e01ccabe890fed30e181f`. Compiled from source as iHearYou Microphone with independent name/UID; original source headers and license remain in `Vendor/BlackHole`. No official binary or branding assets are included. Not endorsed by Existential Audio.

Apple macOS frameworks are system libraries. Retain source, build scripts and notices with distribution. Upstream Sherpa and ONNX Runtime source URLs above provide source corresponding to the official downloaded runtime.

## Offline experiments only

DeepFilterNet commit `d375b2d8309e0935d165700c91da9de862a99c31` (Hendrik Schroeter and contributors, MIT/Apache-2.0), and RNNoise commit `70f1d256acd4b34a572f999a05c87bf00b67730d` (Jean-Marc Valin, Amazon, Mozilla, Xiph.Org Foundation, Mark Borgerding and contributors, BSD-style) remain local evaluation references, excluded from the shipped app and source upload. Their original notices remain in their local vendor folders.

Evaluation audio is excluded from app/repo. Speech `clean_freesound_33711.wav` from DeepFilterNet assets is CC BY-NC 3.0, Freesound #33711. Solo Clap by OwlStorm / Ashe Kirk, https://freesound.org/people/OwlStorm/sounds/151219/ , is CC0 1.0. Fixture files are used only for controlled local regression tests.

Additional 1.4.0 regression fixtures: ESC-50 dog `1-100032-A-0.wav` and vacuum `1-100210-A-36.wav` (CC BY-NC, local evaluation only; source https://github.com/karolpiczak/ESC-50), synthesized fan/hum, and local macOS Glass alert audio. No evaluation audio or user recordings are shipped.

**DPDFNet2 16 kHz** — CEVA IP and contributors, Apache-2.0, with the same license as the full-band model above. Official model: https://github.com/k2-fsa/sherpa-onnx/releases/download/speech-enhancement-models/dpdfnet2.onnx . SHA-256: `ce35d6025fc71df0ef10d1540e1b7916837bbfe5f6896deb744508d2cad487a9`.

**GTCRN** — Copyright (c) 2024 Rong Xiaobin, MIT. Source: https://github.com/Xiaobin-Rong/gtcrn . Official sherpa-onnx model: https://github.com/k2-fsa/sherpa-onnx/releases/download/speech-enhancement-models/gtcrn_simple.onnx . SHA-256: `e77603ac0c23dac3227dd2d7135b3a585cbee2679048aecfa886657d3ae1b534`. MIT license is retained in `Vendor/GTCRN/LICENSE` and the app bundle. Used locally as a second denoiser for Bluetooth speech preservation; it does not identify a speaker.
