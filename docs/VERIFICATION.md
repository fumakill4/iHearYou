# Verification — 11 October 2026

Created by **i729**. Signature: i729.

## Current engine checks

- `swift test`: 8 tests, 0 failures, using production DPDFNet2 DSP. Covers silence, finite/peak bounds, exact 2,400-sample bypass alignment, 16/44.1/48/96 kHz conversion, capture overflow, independent output lanes, and changing presets/bypass while running.
- Stationary-noise test: 29.75 dB reduction in Balanced, consistent with its explicit 30 dB cap. A noise-only synthetic test does not measure speech quality.
- Controlled fixture: speech plus six real clap excerpts, all claps overlapping voiced windows, unclipped. Algorithmic delay calibrated from speech only and applied identically to speech/mixture. DPDFNet2 achieved 14.64 dB global clap-effect reduction versus RNNoise 9.66 dB; worst voiced event 10.05 versus 4.04 dB. Clean speech level change -0.063 dB and SI-SDR 39.33 dB; mixture SI-SDR 23.11 dB. DPDFNet8 added little improvement at substantially higher processing cost. DeepFilterNet3 performed worse on overlapping claps and was rejected.
- Online model evaluation: real-time factor approximately 0.33; frame p99 approximately 8.5 ms. The production wrapper adds one 480-sample streaming buffer to model history, for 50 ms algorithmic delay.
- Model and runtime checksums are verified before packaging. Weights run locally on CPU; no service call performs inference.

## Host checks and limits

The previous installed version demonstrated physical microphone capture, paired 48 kHz mono WAV recording/playback and virtual CoreAudio routing. Its driver remains installed independently of application engine updates. These historical checks are not a claim that the new final build has passed every host test. Final build/UI/browser evidence is appended below after verification.

The app is tested on Apple Silicon macOS. Driver builds for arm64 and x86_64; app runtime is arm64. Ad-hoc signing is for local use and is not Developer ID notarization. Rebuilding or changing bundle identity may require macOS microphone permission again.

Noise reduction does not guarantee silence from every clap, isolate an enrolled speaker, repair clipping or eliminate heavy reverberation. Controlled fixture measurements describe the tested inputs and conditions. No paid MargVoice task or project recording is submitted during testing. Headphone monitoring needs physical headphones; its independent output lane is covered by tests.

## Final build and interaction evidence

- Production build and an independent clean source archive both successfully built app, icon, and universal driver. The clean archive downloaded its own official model/runtime and verified checksums. App and nested libraries pass strict local code-signature verification.
- Installed process loads sherpa-onnx and ONNX Runtime from its own Frameworks folder, not the workspace vendor directory.
- Compact controls, gear-to-settings, Light/Dark/System selection and persistence were exercised. Automatic duplicate SwiftUI Settings scene was removed. Closing Settings keeps the floating panel. First-click floating logo opens compact controls after the panel was made key-capable and accepts first mouse events.
- Floating control visibly shows current microphone state, timer and output meter. Its initial position is clamped to the screen and drag handle uses native window dragging. Screen changes and all Spaces configurations were not exhaustively exercised.
- Virtual microphone receiver: 139,200 samples at 48 kHz during three seconds, nonzero signal, ROUTING PROBE PASS. RMS -82.86 dBFS / peak 0.00219 reflect quiet ambient input during the probe, not a clap attenuation comparison.
- Brave local browser recorder received iHearYou Microphone (Virtual); its meter reached -34 dBFS. Record, stop and download completed. Exported WebM decoded as Opus, 48 kHz stereo, 8.4 seconds with nonzero audio. Native WAV is mono; browser channel count depends on its device/codec support. No browser recording was submitted to MargVoice or uploaded to GitHub.
- Source upload is limited to application, DSP, tests, required driver source, license/model cards, header and build scripts, icon and documentation. Runtime/model files are obtained through pinned checksum downloads. Recordings, fixtures, logs, credentials, local preferences and original image provenance metadata are excluded. Git author is i729 using a noreply address.
- Local installed bundle retains its pre-existing macOS identity for upgrade compatibility; distributed source uses the i729 identifier. A rebuilt ad-hoc binary may still ask the user to allow microphone access again.

- Final installed build is active in Strong mode with live output energy observed. Public GitHub repository visibility and remote main commit were confirmed after source/privacy review. Local working tree is clean.

## 1.2.0 — devices, iPhone receiver, and release packaging (12 October)

- Release build passed with live input/output selection, connection labels, automatic refresh, device-disconnect stop/save behavior, and filtering of hidden/private engine devices. The same public bundle uses the i729 identifier.
- Physical iPhone Continuity appeared with wired and wireless transport labels. A local 48 kHz mono capture delivered 345,600 samples with nonzero original signal (peak 0.07959, RMS -47.04 dBFS). A later input disconnect stopped the session with a visible error rather than silently continuing with another microphone.
- Changing the output selection from built-in speakers to DisplayPort during native recording restarted the session and continued recording in a new file, with a visible split notice. The two checked WAVs contained 312,000 and 253,920 mono samples at 48 kHz. Built-in output was restored; physical monitoring remained off to avoid feedback.
- The LAN Safari receiver ran in Safari Mac for more than 40 seconds. Wrong routes return 404, POST returns 405, a second receiver returns 409. Final-build stream check received 144,000 finite mono PCM samples; those were silent during the quiet-input probe, so this check establishes transport/format only.
- The user then tested Safari on a physical iPhone and explicitly confirmed that speaking into the Mac microphone produced audible sound on the iPhone. Safari receiver and same-phone Continuity microphone are separate modes; the app prevents enabling the receiver with a selected Continuity input and disables it when that input is chosen.
- Receiver is opt-in and off on normal launch. A new capability URL is generated at each activation; one receiver is accepted, audio buffering is bounded, stale/backpressured connections close, and turning off closes the listener. IPv4 LAN HTTP transport is unencrypted. There are no upload or stored-recording endpoints. iPhone Safari must remain visible with the screen on.
- `Real app logo.icns` is copied directly and is byte-identical in the app and expanded installer. The full PKG contains `/Applications/iHearYou.app` and the HAL driver at their documented paths. Expanded app/driver pass strict local code-signature checks; artifact SHA-256 checks passed. Own binary debug records were stripped, and the expanded payload contained none of the personal name/path markers checked.
- Bluetooth and additional wired headsets are supported when exposed as alive macOS audio devices, but no physical Bluetooth peripheral was connected for this verification. Apple Silicon/macOS 14+ is the supported app target. Release app signing is ad-hoc; the installer is not Developer ID signed or notarized.


## 1.3.0 — languages and recording workflow

- Release build and all eight DSP tests pass; the inference model and DSP behavior are unchanged.
- English/Indonesian UI switching updates native Settings, floating controls, menus, device transport labels, dates, and an existing saved-recording notice. The Indonesian preference persisted after quit/relaunch.
- Native Record audio is enabled with an available microphone even before capture starts. It started capture and recording, changed to Save recording with a Stop-square icon, saved a valid approximately 44-second mono 48 kHz WAV pair, and returned to Record audio. The library displayed that pair and all 16 earlier pairs; clean-recording playback changed its button to Stop and back.
- The library refreshes on entry, reports directory failures, shows the saved count, and provides a Stop microphone action before playback.
- Localization checks pass for both locales, message retranslation, unknown system-error preservation, and 1,000 concurrent accesses. Web script checks pass for both pages, injected app language, unavailable storage, and changing language while preserving recording/listening state. Native OS error details may follow the macOS language.
- Full PKG app/driver pass strict local signature checks. The public payload uses the i729 identity, contains English and Indonesian permission descriptions and the supplied ICNS, and excludes the personal name/path/token markers checked. All artifact SHA-256 checks pass. Ad-hoc signing is not Developer ID notarization.


## 1.4.0 — 15 October 2026: Bluetooth capture and speech preservation

### Implemented and exercised

- Two host crash reports from this date faulted in MainActor executor checking; one entered through the AppModel timer. Foundation/CoreAudio callbacks now hop to MainActor instead of using `assumeIsolated`.
- Physical AirPods Pro 2 reproduced AVAudioEngine tap/format mismatch and unsupported-format failures. Input-only AUHAL capture successfully started the same physical AirPods microphone; the user confirmed application stability and a clear Original recording.
- The initial full-band denoiser damaged that headset's Clean recording. The final Bluetooth profile preserves the headset's voice signal/EQ and uses a quiet-background activity gate. It does not apply another full-band DPDFNet pass to Bluetooth audio. The user-supplied local recording was reprocessed without overwriting its existing original/clean files.
- Late audio callbacks retain a DSPContext owner. Queue generation/identity checks prevent an obsolete timer or device notification from processing a new session's recording.
- Hardware configuration changes reconnect the same selected microphone with bounded attempts; active recordings are saved and continued in a new file. Newly detected Bluetooth devices receive a short settling period. A disconnected microphone does not silently select another input.
- Physical monitoring now uses AUHAL at its device rate, resampled independently of the fixed 48 kHz virtual output. CoreAudio buffer sizes and callback capacities are bounded.
- Built-in capture enables native acoustic echo processing when the system output is a physical non-Bluetooth device, with native AGC disabled. Physical-only microphone selection excludes desktop loopback sources. A built-in microphone session and live switch to AirPods were observed in the final installed build.
- Save opens the recording library; playback stops an idle microphone session automatically. WAV finalization drains processing delay so the final word is retained.

### Automated evidence

- `swift test`: 14 tests passed, covering silence, exact delayed bypass, clipping/invalid samples, capture overflow, hardware input rates 8/16/24/32/44.1/48/96/192 kHz, independent output lanes, Bluetooth monitoring-rate conversion, delayed callback ownership, recoverable Objective-C audio exceptions, headset low-band voice preservation, and recording-tail draining.
- `scripts/evaluate-studio.py`: acceptance passed against the exact production C source hash. It uses the existing Freesound #33711 speech excerpt, an ESC-50 bark, an ESC-50 vacuum, local macOS Glass alert audio, and synthesized fan/hum. No evaluation audio is shipped.
- In noise-only full-band fixtures, Studio's activity gate closed to digital silence. This is gating during non-speech, not a claim of extraordinary measured acoustic attenuation.
- Clean full-band speech SI-SDR: 38.43 dB; level change -0.064 dB.
- Overlapping-noise effect reduction: fan-hum 15.02 dB, dog 17.25 dB, vacuum 12.86 dB, notification 20.38 dB.
- Overlapping-noise results remain broadly comparable with 1.3.0; the significant additional rejection is during pauses. They do not prove complete isolation in a real room.
- Local headset regression: 353/353 strong input frames retained within 6 dB; level change -0.000037 dB. This tests preservation of that supplied recording, not headset suppression of every noise.
- Release app/installer produced and strict nested code-signature verification passed. The app was copied into `/Applications`; the original installed 1.3.0 app remains backed up locally. The existing HAL driver was not replaced or restarted during this update.

### Limits

The full-band algorithmic delay is 8,672 samples (180.67 ms) including fixed model alignment, speech pre-roll, and the linear-phase rumble filter; headset/bypass timelines use the same alignment. Device and buffer latency add to that delay. There is no enrolled-speaker identity model: overlapping human voices cannot be reliably attributed to the owner. Speaker echo, barks, and fan noise overlapping speech may remain. Headset gating preserves audible speech and therefore may also pass a sufficiently loud unwanted headset input. Physical fan/dog rejection in the user's room and audible quality of every new live capture require real-condition listening; fixture results alone do not establish those outcomes.

Krisp package inspection is documented separately in `KRISP_PACKAGE_INSPECTION.md`; extracted proprietary files remain under ignored local build artifacts and are not shipped.

### Bluetooth denoising revision after user feedback

The user confirmed that the interim Bluetooth pass-through/activity-gate profile produced clear, unbroken Clean recordings, but still captured phone-video voices, dogs, and nearby sounds. That profile was insufficient for noise rejection.

The revised headset path uses DPDFNet2 **16 kHz**, with GTCRN as an independent denoised safety path for speech rejected by the primary model. Both models use the existing pinned sherpa-onnx runtime. Their different block sizes and intrinsic delays are aligned in separate FIFOs before interpolation to 48 kHz. A 63-tap bandlimited interpolator and a shorter pre-roll retain the documented 8,672-sample recording alignment. No raw signal is mixed into enabled suppression. Natural permits the greatest speech rescue, Balanced limits it, and Studio caps it most tightly so transient interference cannot reopen the secondary path at full level. A second local VAD evaluates that safety path; neither detector identifies the owner of a voice.

Standalone GTCRN was rejected for the shipped Studio path after the controlled dog mixture achieved only about 2.25 dB of interference-effect reduction. Full-band DPDFNet2 and DPDFNet8 were also unsuitable for the original AirPods example. Narrowband DPDFNet2 preserved the two latest local headset examples much better. The oldest example remains a difficult case for aggressive processing; Natural is the speech-preserving option when Studio attenuates soft speech.

The headset evaluation uses the same locally held public speech, ESC-50 dog/vacuum clips and seeded synthetic fan fixture described above. It compares noise-only and speech-plus-noise streams against an independently processed speech-only stream, with a fixed 8,672-sample compensation for every signal. It uses a bandwidth-matched reference because 16 kHz models retain approximately 8 kHz of bandwidth, even though output WAVs remain 48 kHz. These are controlled fixture results, not a promise of equivalent physical-room performance or complete noise removal. Reproduce with `scripts/evaluate-headset.py` once the local fixtures are present.

Other human voices, including speech from a phone, are still speech to these models. No speaker enrollment or target-speaker separation is implemented; this remains an explicit product gap.

Final revision validation: 15 automated tests passed, including headset denoising, block scheduling, bypass alignment, monitoring rates, and recording-tail draining. Exact-source headset regression passed (AudioDSP SHA-256 `3c6b41546d62882634d3ea72c4ca7bc4c6343a11c64330762d411a4770740df8`). Studio overlapping-interference effect reduction: synthetic fan **15.60 dB**, dog **16.39 dB**, vacuum **12.79 dB**. Speech-only SI-SDR against the bandwidth-matched reference was **21.93 dB**, with **-0.22 dB** level change. Model, processing and input-drop counters were zero throughout. CPU real-time factors were 0.35–0.46 in this local run; device/render latency is additional.

The two latest local headset examples retained bandwidth-matched SI-SDR values of approximately 28.13/29.51 dB and level changes of −0.13/−0.12 dB. Of 220/422 input frames above −40 dBFS, 2/5 were reduced by more than 6 dB; those recordings are not clean laboratory references, so these numbers are preservation diagnostics rather than perceptual scores or proof of noise removal. Original recordings were preserved and were not uploaded.
