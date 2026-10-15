# iHearYou

Created by **i729**. Signature: i729.

A macOS app that reduces microphone noise locally, records WAV files, and sends processed audio to browsers through a virtual microphone. No account, trial, subscription, telemetry, or audio upload service is required. The optional iPhone speaker mode streams processed audio directly over the local network. Physical full-band microphones use DPDFNet2 and Silero VAD. Bluetooth headset microphones use a dedicated 16 kHz DPDFNet2 denoiser with a GTCRN speech-preservation path.

## Getting started

1. Open iHearYou. Click its menu bar icon to open the compact control panel; the gear opens a separate Settings window.
2. Select a physical microphone, enable it, and allow microphone access when macOS asks.
3. Choose **Studio** for the strongest speech gate. All full-band presets use the denoised signal without mixing raw background noise back in; Natural and Balanced retain a quieter floor. The Bluetooth headset profile uses narrowband neural denoising; Natural allows the strongest speech rescue, Balanced limits it, and Studio prioritizes rejection of interference.
4. Select **iHearYou Microphone** as the input in your browser or destination app. Use a physical device for speaker output.
5. Record WAV files in the app, then press **Save recording** to open the recording library. Play **Clean audio** or **Original audio** to compare; playback stops an idle microphone session automatically to avoid feedback. Or open **Record in Browser** for local recording, playback, and download. Original and processed WAV files are saved in `~/Music/iHearYou` as 48 kHz mono, 16-bit PCM.

The app defaults to **English**. In version 1.3.0, choose **English** or **Indonesian** in **Settings → Appearance → Language**. The selection is saved immediately and applies to native controls, messages, the browser recorder, and the iPhone Safari receiver. Both browser pages also let you switch their language directly.

Settings includes **System, Light, and Dark** themes, the floating control, gain, devices, recordings, and setup guidance. The floating control appears by default; drag the dots at the top to move it. Its iH button opens the compact panel, its microphone button enables the session, and its record button saves WAV files. Position, theme, and language persist across launches. The meter and timer reflect the actual session. Shortcuts: Cmd+Shift+M for the microphone, Cmd+R to record/save, Cmd+, for Settings, and Cmd+Q to quit.

Install the microphone driver using the macOS installer available in **Guide**. The installer asks for administrator authentication to copy the driver to `/Library/Audio/Plug-Ins/HAL/iHearYouMic.driver` and reload CoreAudio. Close calls and recordings before installation. An existing driver does not need to be reinstalled when updating the app. Closing the window leaves the app running in the menu bar.

Use headphones for **Live Monitoring** to avoid feedback. You can change microphone and speaker devices during capture; the app stops the old session and starts another with the selected devices. During WAV recording, it saves the current file and continues in a new one. Configuration changes trigger bounded reconnection attempts using the same selected microphone; an active recording is saved and continued in a new file after reconnection. A disconnected microphone stops capture with a message and never silently switches to another input.

## iPhone, Bluetooth, and wired devices

Device selectors show the active inputs and outputs provided by macOS, including iPhone Continuity microphones, Bluetooth, USB, wired earphones, and other audio devices. Labels indicate the connection type. The list refreshes every two seconds and through CoreAudio notifications; **Refresh Devices** is also available. Virtual inputs, aggregate devices, private engine devices, and loopbacks are excluded from microphone and monitoring choices so desktop audio cannot be selected as a physical microphone.

The iPhone microphone uses [Continuity Camera](https://support.apple.com/102546), over USB or wirelessly with Wi-Fi and Bluetooth enabled and the same Apple Account on both devices. Accept the Trust prompt when connecting an iPhone over USB. Pair Bluetooth devices in macOS, or connect wired devices, before selecting them. Bluetooth formats depend on the device profile; the pipeline resamples input to 48 kHz.

To use the **iPhone's built-in speaker**, select a Mac, USB, or Bluetooth microphone, then enable **iPhone Speaker via Safari** in Settings. Connect both devices to the same Wi-Fi network, scan the QR code or copy the link, and tap **Listen** in Safari on the iPhone. Keep the tab open and the screen on. The receiver provides volume, a meter, and a **Disconnect** button. It plays processed iHearYou microphone audio; it does not stream all Mac system audio. The virtual microphone remains available to Mac browsers.

On the tested device, Continuity exposes the iPhone microphone but not its speaker. Unlocking the iPhone pauses Continuity, so Safari speaker mode uses a Mac, USB, or Bluetooth microphone. Selecting a Continuity microphone disables the Safari receiver. Use earphones or low volume to avoid feedback.

The receiver runs only when enabled, uses a local IPv4 address and a new random link for each activation, and accepts one tab at a time. PCM audio streams directly over local HTTP without transport encryption; use a trusted network and treat the link as listening access. Disabling the mode closes connections and invalidates the link. There is no upload endpoint, stored-recording access, or cloud service. Audio buffers are bounded so slow connections cannot accumulate unlimited memory or delay.

## Browsers and privacy

The local recorder runs on `127.0.0.1` with a random port and path for each launch. After browser permission is granted, it selects the iHearYou device automatically. Browser echo cancellation, noise suppression, and AGC are disabled on the local page to avoid processing the model output twice. MediaRecorder produces WebM/Opus, M4A, or Ogg, depending on the browser. Audio stays in the browser until downloaded; the server does not receive audio or provide an upload endpoint.

For MargVoice, select **iHearYou Microphone** in Brave's microphone settings and in the site's input selector when available, then restart the site session. iHearYou does not require credentials or access to project content. Users control activity and uploads on third-party sites.

## Engine and measured limits

Physical microphone input → SPSC ring → streaming resampling to 48 kHz → DPDFNet2 in 480-sample frames → linear-phase 70 Hz rumble filter → speech gate, gain, and limiter → WAV files and separate output rings. Silero VAD classifies input speech before denoising, with pre-roll and a release tail to preserve word boundaries. Built-in microphones also use macOS acoustic echo cancellation with automatic gain disabled when a physical non-Bluetooth system output is available. Bluetooth input and all outputs use AUHAL; monitoring resamples independently to the physical output rate. The headset profile uses 16 kHz DPDFNet2 plus an independently denoised GTCRN safety path when speech would otherwise collapse (bounded most tightly in Studio), with aligned block FIFOs and bandlimited interpolation back to 48 kHz. Neural inference and file I/O run on the processing queue, outside audio render callbacks. Frame counts and backlog are bounded; model errors stop the session with a message.

The streaming pipeline adds 8,672 samples / approximately 180.67 ms of algorithmic delay, with device and buffer latency adding further delay. Bypass and original audio are aligned to the same delay. The activity indicator reflects the speech/activity gate, not an enrolled speaker identity. Levels are RMS dBFS, not the percentage of noise removed.

A controlled speech-and-clap test measured about 14.6 dB of clap-effect reduction, compared with 9.7 dB for the previous RNNoise engine. These measurements do not guarantee that all noise disappears. Other speakers, heavy reverberation, clipping, and noise overlapping speech may remain audible. See [verification details](docs/VERIFICATION.md).

## Recording quality and notification sounds

Studio suppresses non-speech during pauses and reduces background noise from full-band microphone input. Echo cancellation helps reject sounds played through Mac speakers; selecting only physical microphone inputs prevents digital desktop/loopback audio from entering capture. It does not guarantee removal of a notification, bark, or other sound overlapping speech. No speaker enrollment exists: other human voices cannot be distinguished from the user. Bluetooth input uses a separate 16 kHz processing path because the full-band denoiser damaged AirPods speech in testing; its effective bandwidth is approximately 8 kHz even though WAV and virtual output remain 48 kHz. A close microphone and headphones improve isolation.

## Build

Requires an Apple Silicon Mac, macOS 14+, Xcode Command Line Tools (Swift 5.9+), and standard Python 3. An SDK older than macOS 27 can build the same macOS 14+ compatibility paths.

```sh
./scripts/build.sh
swift test
```

The build verifies SHA-256 checksums and downloads the official model/runtime when needed. DPDFNet2 at 48/16 kHz, GTCRN, Silero VAD v5, sherpa-onnx 1.13.8, and ONNX Runtime 1.28.2 are copied into the bundle; installed apps do not depend on workspace paths. **Real app logo.icns** is used directly when present; `icon.png` provides a local build fallback if that file has been removed. The universal arm64/x86_64 driver is built from BlackHole source. Debug records are stripped from the app binary before packaging.

Version 1.4.0 build artifacts in `dist/`:

- `iHearYou.app`: the complete app.
- `iHearYou-1.4.0.pkg`: installs the app in `/Applications` and the driver in `/Library/Audio/Plug-Ins/HAL`; requests administrator access and reloads CoreAudio.
- `iHearYou-1.4.0-macOS-arm64.zip`: the app without driver installation.
- `iHearYouMicrophone.pkg`: the driver only, for an app already installed.
- `iHearYou.png`: the PNG exported from the current app icon.
- `SHA256SUMS.txt`: release artifact checksums.

Download published builds from [GitHub Releases](https://github.com/fumakill4/iHearYou/releases). The app requires Apple Silicon and macOS 14+. The app and libraries use ad-hoc signatures; the installer is not Developer ID signed or notarized. Gatekeeper may require manually allowing the app to open. Close calls and recordings before installing the full package because it reloads CoreAudio.

Dependency sources, versions, licenses, and checksums are recorded in [third-party notices](THIRD_PARTY_NOTICES.md). Local DeepFilterNet/RNNoise experiments are excluded from the current engine build. Recordings, downloaded models/runtimes, logs, build caches, and local data are ignored by Git. The repository includes the model card, licenses, C header, and download scripts with checksums.

## License and uninstall

iHearYou is GPL-3.0-or-later; DPDFNet2 and sherpa-onnx are Apache-2.0; GTCRN, Silero VAD, and ONNX Runtime are MIT; the BlackHole driver is GPLv3. Upstream copyrights are retained. To uninstall the driver, close audio apps, move only `iHearYouMic.driver` to the Trash using Finder, and restart the Mac. Recordings remain in the Music folder until deleted by the user.
