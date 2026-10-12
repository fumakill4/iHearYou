# iHearYou

Created by **i729**. Signature: i729.

A macOS app that reduces microphone noise locally, records WAV files, and sends processed audio to browsers through a virtual microphone. No account, trial, subscription, telemetry, or audio upload service is required. The optional iPhone speaker mode streams processed audio directly over the local network. The engine uses the official DPDFNet2 model.

## Getting started

1. Open iHearYou. Click its menu bar icon to open the compact control panel; the gear opens a separate Settings window.
2. Select a physical microphone, enable it, and allow microphone access when macOS asks.
3. Choose **Strong** for the full model output. **Balanced** caps attenuation at 30 dB; **Natural** caps it at 20 dB by mixing in the aligned original audio.
4. Select **iHearYou Microphone** as the input in your browser or destination app. Use a physical device for speaker output.
5. Record WAV files in the app, or open **Record in Browser** for local recording, playback, and download. Original and processed WAV files are saved in `~/Music/iHearYou` as 48 kHz mono, 16-bit PCM.

The app defaults to **English**. In version 1.3.0, choose **English** or **Indonesian** in **Settings → Appearance → Language**. The selection is saved immediately and applies to native controls, messages, the browser recorder, and the iPhone Safari receiver. Both browser pages also let you switch their language directly.

Settings includes **System, Light, and Dark** themes, the floating control, gain, devices, recordings, and setup guidance. The floating control appears by default; drag the dots at the top to move it. Its iH button opens the compact panel, its microphone button enables the session, and its record button saves WAV files. Position, theme, and language persist across launches. The meter and timer reflect the actual session. Shortcuts: Cmd+Shift+M for the microphone, Cmd+R to record/save, Cmd+, for Settings, and Cmd+Q to quit.

Install the microphone driver using the macOS installer available in **Guide**. The installer asks for administrator authentication to copy the driver to `/Library/Audio/Plug-Ins/HAL/iHearYouMic.driver` and reload CoreAudio. Close calls and recordings before installation. An existing driver does not need to be reinstalled when updating the app. Closing the window leaves the app running in the menu bar.

Use headphones for **Live Monitoring** to avoid feedback. You can change microphone and speaker devices during capture; the app stops the old session and starts another with the selected devices. During WAV recording, it saves the current file and continues in a new one. Disconnecting an active device stops the session with a message; capture does not silently switch to a different microphone.

## iPhone, Bluetooth, and wired devices

Device selectors show the active inputs and outputs provided by macOS, including iPhone Continuity microphones, Bluetooth, USB, wired earphones, and other audio devices. Labels indicate the connection type. The list refreshes every two seconds and through CoreAudio notifications; **Refresh Devices** is also available. Hidden/private engine devices and the iHearYou loopback are excluded from input and monitoring choices.

The iPhone microphone uses [Continuity Camera](https://support.apple.com/102546), over USB or wirelessly with Wi-Fi and Bluetooth enabled and the same Apple Account on both devices. Accept the Trust prompt when connecting an iPhone over USB. Pair Bluetooth devices in macOS, or connect wired devices, before selecting them. Bluetooth formats depend on the device profile; the pipeline resamples input to 48 kHz.

To use the **iPhone's built-in speaker**, select a Mac, USB, or Bluetooth microphone, then enable **iPhone Speaker via Safari** in Settings. Connect both devices to the same Wi-Fi network, scan the QR code or copy the link, and tap **Listen** in Safari on the iPhone. Keep the tab open and the screen on. The receiver provides volume, a meter, and a **Disconnect** button. It plays processed iHearYou microphone audio; it does not stream all Mac system audio. The virtual microphone remains available to Mac browsers.

On the tested device, Continuity exposes the iPhone microphone but not its speaker. Unlocking the iPhone pauses Continuity, so Safari speaker mode uses a Mac, USB, or Bluetooth microphone. Selecting a Continuity microphone disables the Safari receiver. Use earphones or low volume to avoid feedback.

The receiver runs only when enabled, uses a local IPv4 address and a new random link for each activation, and accepts one tab at a time. PCM audio streams directly over local HTTP without transport encryption; use a trusted network and treat the link as listening access. Disabling the mode closes connections and invalidates the link. There is no upload endpoint, stored-recording access, or cloud service. Audio buffers are bounded so slow connections cannot accumulate unlimited memory or delay.

## Browsers and privacy

The local recorder runs on `127.0.0.1` with a random port and path for each launch. After browser permission is granted, it selects the iHearYou device automatically. Browser echo cancellation, noise suppression, and AGC are disabled on the local page to avoid processing the model output twice. MediaRecorder produces WebM/Opus, M4A, or Ogg, depending on the browser. Audio stays in the browser until downloaded; the server does not receive audio or provide an upload endpoint.

For MargVoice, select **iHearYou Microphone** in Brave's microphone settings and in the site's input selector when available, then restart the site session. iHearYou does not require credentials or access to project content. Users control activity and uploads on third-party sites.

## Engine and measured limits

AVAudioEngine input → SPSC ring → streaming resampling to 48 kHz → DPDFNet2 in 480-sample frames → preset mix, gain, and limiter → WAV files and separate output rings. Virtual output uses AUHAL; monitoring uses AVAudioEngine. Neural inference and file I/O run on the processing queue, outside audio render callbacks. Frame counts and backlog are bounded; model errors stop the session with a message.

The streaming pipeline adds 2,400 samples / 50 ms of algorithmic delay, with device and buffer latency adding further delay. Bypass and original audio are aligned to the same delay. The output indicator measures audio energy, not speaker identity. Levels are RMS dBFS, not the percentage of noise removed.

A controlled speech-and-clap test measured about 14.6 dB of clap-effect reduction, compared with 9.7 dB for the previous RNNoise engine. These measurements do not guarantee that all noise disappears. Other speakers, heavy reverberation, clipping, and noise overlapping speech may remain audible. See [verification details](docs/VERIFICATION.md).

## Build

Requires an Apple Silicon Mac, macOS 14+, Xcode Command Line Tools (Swift 5.9+), and standard Python 3.

```sh
./scripts/build.sh
swift test
```

The build verifies SHA-256 checksums and downloads the official model/runtime when needed. DPDFNet2, sherpa-onnx 1.13.8, and ONNX Runtime 1.28.2 are copied into the bundle; installed apps do not depend on workspace paths. **Real app logo.icns** is used directly as the app icon. The universal arm64/x86_64 driver is built from BlackHole source. Debug records are stripped from the app binary before packaging.

Version 1.3.0 build artifacts in `dist/`:

- `iHearYou.app`: the complete app.
- `iHearYou-1.3.0.pkg`: installs the app in `/Applications` and the driver in `/Library/Audio/Plug-Ins/HAL`; requests administrator access and reloads CoreAudio.
- `iHearYou-1.3.0-macOS-arm64.zip`: the app without driver installation.
- `iHearYouMicrophone.pkg`: the driver only, for an app already installed.
- `SHA256SUMS.txt`: release artifact checksums.

Download published builds from [GitHub Releases](https://github.com/fumakill4/iHearYou/releases). The app requires Apple Silicon and macOS 14+. The app and libraries use ad-hoc signatures; the installer is not Developer ID signed or notarized. Gatekeeper may require manually allowing the app to open. Close calls and recordings before installing the full package because it reloads CoreAudio.

Dependency sources, versions, licenses, and checksums are recorded in [third-party notices](THIRD_PARTY_NOTICES.md). Local DeepFilterNet/RNNoise experiments are excluded from the current engine build. Recordings, downloaded models/runtimes, logs, build caches, and local data are ignored by Git. The repository includes the model card, licenses, C header, and download scripts with checksums.

## License and uninstall

iHearYou is GPL-3.0-or-later; DPDFNet2 and sherpa-onnx are Apache-2.0; ONNX Runtime is MIT; the BlackHole driver is GPLv3. Upstream copyrights are retained. To uninstall the driver, close audio apps, move only `iHearYouMic.driver` to the Trash using Finder, and restart the Mac. Recordings remain in the Music folder until deleted by the user.
