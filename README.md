# iHearYou

Dibuat oleh **i729**. Signature: i729.

Aplikasi macOS untuk meredam noise mikrofon secara lokal, merekam WAV, dan mengirim hasil ke browser melalui mikrofon virtual. Tidak ada akun, trial, subscription, telemetry, atau unggahan audio. Implementasi independen memakai model DPDFNet2 resmi; tidak memakai kode, model, atau aset Krisp.

## Penggunaan

1. Buka iHearYou. Klik ikon menu bar untuk panel kontrol ringkas; roda gigi membuka Settings terpisah.
2. Pilih mikrofon fisik, lalu aktifkan mikrofon dan izinkan akses ketika macOS meminta.
3. Pilih **Kuat** untuk seluruh hasil model; **Seimbang** membatasi peredaman sampai 30 dB, **Natural** sampai 20 dB dengan campuran suara asli yang diselaraskan.
4. Pilih **iHearYou Microphone** sebagai input browser atau aplikasi tujuan. Speaker tetap memakai perangkat fisik.
5. Rekam WAV di aplikasi atau buka **Rekam lewat browser** untuk perekam lokal, preview, dan unduhan. WAV asli dan bersih disimpan di `~/Music/iHearYou` (48 kHz mono PCM 16-bit).

Settings menyediakan **System, Light, Dark**, floating control, gain, perangkat, rekaman, dan panduan. Floating control muncul secara default; geser titik di atas untuk memindahkan. Tombol iH membuka panel ringkas, tombol mikrofon mengaktifkan sesi, tombol rekam menyimpan WAV. Posisi dan tema tersimpan. Meter dan timer memakai sesi aktual. Shortcut: Cmd+Shift+M mikrofon, Cmd+R rekam/simpan, Cmd+, Settings, Cmd+Q keluar.

Driver mikrofon dipasang melalui installer macOS di Panduan. Installer meminta autentikasi admin untuk menyalin driver ke `/Library/Audio/Plug-Ins/HAL/iHearYouMic.driver` dan memuat ulang CoreAudio. Tutup rekaman/panggilan sebelum memasang. Jika driver sudah tersedia, tidak perlu memasang ulang saat aplikasi diperbarui. Menutup jendela membiarkan aplikasi berjalan di menu bar.

**Dengar langsung** memakai headphone untuk menghindari feedback; pilih perangkat sebelum memulai. Pilihan perangkat terkunci selama capture. Perubahan perangkat menghentikan sesi dengan pesan.

## Browser dan privasi

Perekam lokal berjalan di `127.0.0.1` dengan port dan path acak per peluncuran. Setelah izin browser, perangkat iHearYou dipilih otomatis. Echo cancellation, noise suppression, dan AGC browser dimatikan di halaman lokal agar hasil model tidak diproses dua kali. MediaRecorder menghasilkan WebM/Opus, M4A, atau Ogg sesuai browser. Audio tetap berada di browser sampai diunduh; server tidak menerima audio atau menyediakan endpoint upload.

Untuk MargVoice, pilih **iHearYou Microphone** di pengaturan mikrofon Brave dan pilihan input situs bila tersedia, lalu mulai ulang sesi situs. iHearYou tidak memerlukan kredensial atau akses isi project. Aktivitas dan upload di situs pihak ketiga tetap dikendalikan pengguna.

## Mesin dan batas hasil

Input AVAudioEngine → ring SPSC → resampling streaming 48 kHz → DPDFNet2 per 480 sampel → campuran sesuai mode, gain, limiter → WAV dan ring output terpisah. Output virtual memakai AUHAL, monitor memakai AVAudioEngine. Neural inference dan file I/O berjalan pada queue pemrosesan, bukan audio render callback. Jumlah frame dan backlog dibatasi; kesalahan model menghentikan sesi dengan pesan.

Model menghasilkan delay 2.400 sampel / 50 ms dalam pipeline streaming; latensi perangkat dan buffer menambah delay. Bypass dan suara asli diselaraskan dengan delay yang sama. Indikator output menunjukkan energi audio, bukan identitas pembicara. Level dB adalah RMS dBFS, bukan persentase noise yang dihapus.

Uji speech+clap terkontrol menunjukkan pengurangan efek tepuk sekitar 14,6 dB, dibanding 9,7 dB mesin RNNoise lama. Ini bukan jaminan seluruh noise hilang atau bukti setara Krisp. Pembicara lain, gema berat, clipping, dan noise yang tumpang tindih dengan suara masih dapat terdengar. Lihat `docs/VERIFICATION.md`.

## Build

Apple Silicon Mac, macOS 14+, Xcode Command Line Tools (Swift 5.9+), Python 3 standar.

```sh
./scripts/build.sh
swift test
```

Build memverifikasi SHA-256 dan mengambil model/runtime resmi jika belum tersedia. Model DPDFNet2, sherpa-onnx 1.13.8 dan ONNX Runtime 1.28.2 disalin ke bundle; tidak bergantung pada path workspace saat dipasang. `icon.png` dikonversi menjadi iconset macOS. Driver universal arm64/x86_64 dibangun dari source BlackHole. Aplikasi dan library ditandatangani ad-hoc untuk penggunaan lokal; distribusi publik memerlukan Developer ID dan notarization.

Source dependency, versi, lisensi, dan checksum dicatat di `THIRD_PARTY_NOTICES.md`. Eksperimen DeepFilterNet/RNNoise di workspace bukan bagian engine build saat ini. Rekaman, model/runtime unduhan, log, cache build, dan data lokal diabaikan Git. Repo menyertakan model card, license, header C, serta script unduhan dengan checksum.

## Lisensi dan uninstall

iHearYou GPL-3.0-or-later; DPDFNet2 dan sherpa-onnx Apache-2.0; ONNX Runtime MIT; driver BlackHole GPLv3. Copyright upstream tetap dipertahankan. Untuk uninstall, tutup aplikasi audio dan pindahkan hanya `iHearYouMic.driver` ke Trash melalui Finder, lalu restart Mac. Rekaman tetap di Musik sampai dihapus pengguna.
