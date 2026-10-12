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
