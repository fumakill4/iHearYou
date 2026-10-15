# Krisp 3.17.6 package inspection — 15 October 2026

Created by i729. Signature: i729.

The user supplied a local ARM64 installer as an engineering reference for iHearYou. Inspection is static and local. No Krisp install/uninstall script was executed and no extracted proprietary payload was added to iHearYou.

## Observed evidence

- `pkgutil --check-signature`: trusted Developer ID Installer signature and Apple notarization; timestamp 1 October 2026.
- The product archive contains nested installers in component `Scripts` directories. Expanding those reveals the app and HAL audio driver.
- The application uses Electron. Its ASAR inventory contains 185 entries; 26 packed application JavaScript/JSON resource files were extracted locally for examination. Application bundles are minified/obfuscated and are not the original development source tree.
- `kr-audio-dm.node` and `kr-media-sp.node` are native compiled modules. Imported CoreAudio functions include device I/O callbacks, device start/stop, property reads/writes, and property listeners.
- Native diagnostic labels explicitly mention deferring newly detected Bluetooth devices and handling a deferred default device. This establishes the existence of a Bluetooth settling mechanism, not its exact implementation or timing.
- The shipped audio manifest lists separate input/output model choices, including 8 kHz narrowband outbound processing, 32 kHz outbound processing, and 16 kHz inbound processing. Device sample-rate ranges and internal model work rates are separate fields.
- A separate `libaec-sdk.dylib` exists. The JavaScript configuration includes separate echo-cancellation, noise-reduction, and recording processors. Their names do not prove their measured quality or internal algorithm.
- Native labels include resampler state, frame cache sizes, processing delay, dropped frame counts, and mismatched frame-buffer lengths.

## Applied independently in iHearYou

- Input-only AUHAL capture for Bluetooth avoids AVAudioEngine's stale tap/output graph format during headset profile negotiation.
- A short settling period for newly detected Bluetooth devices and bounded reconnection attempts allow format negotiation to stabilize.
- Monitoring uses AUHAL at the selected physical output's rate; its resampling and virtual microphone lane are independent.
- Bluetooth headset audio uses a separate 16 kHz denoiser with an independently denoised speech-safety path rather than the full-band denoiser/EQ. This specifically addresses the user's clear Original / damaged Clean recording.
- Full-band microphone noise reduction, acoustic echo handling, recording, and speech/activity gating remain separate stages with explicit latency alignment.

These are original implementations informed by observed behavior and by iHearYou's own failing tests. No claim is made that extracting a PKG recovers the complete Krisp C/C++ source or that iHearYou reproduces Krisp's trained models.

## Local artifacts

Extracted installers, ASAR inventory, application JavaScript, native modules, and model manifests remain under ignored `build/reference/`. Do not include them in public source or release bundles. The original supplied installer remains unchanged.

## Skill installation

The upstream [morluto catalog](https://github.com/morluto/awesome-reverse-engineering) has no SKILL.md. A global Codex adapter named `awesome-reverse-engineering` was created with the upstream README, CC0 license, and revision provenance. The adapter was validated; it does not automatically install every tool linked by the catalog.
