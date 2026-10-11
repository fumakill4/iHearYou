# iHearYou

Dibuat oleh **i729**. Signature: i729.

Aplikasi macOS untuk meredam noise mikrofon secara lokal, merekam WAV, dan mengirim hasil ke browser melalui mikrofon virtual. Tidak ada akun, trial, subscription, telemetry, atau layanan unggahan audio. Mode speaker iPhone opsional mengirim hasil langsung melalui jaringan lokal. Implementasi independen memakai model DPDFNet2 resmi; tidak memakai kode, model, atau aset Krisp.

## Penggunaan

1. Buka iHearYou. Klik ikon menu bar untuk panel kontrol ringkas; roda gigi membuka Settings terpisah.
2. Pilih mikrofon fisik, lalu aktifkan mikrofon dan izinkan akses ketika macOS meminta.
3. Pilih **Kuat** untuk seluruh hasil model; **Seimbang** membatasi peredaman sampai 30 dB, **Natural** sampai 20 dB dengan campuran suara asli yang diselaraskan.
4. Pilih **iHearYou Microphone** sebagai input browser atau aplikasi tujuan. Speaker tetap memakai perangkat fisik.
5. Rekam WAV di aplikasi atau buka **Rekam lewat browser** untuk perekam lokal, preview, dan unduhan. WAV asli dan bersih disimpan di `~/Music/iHearYou` (48 kHz mono PCM 16-bit).

Settings menyediakan **System, Light, Dark**, floating control, gain, perangkat, rekaman, dan panduan. Floating control muncul secara default; geser titik di atas untuk memindahkan. Tombol iH membuka panel ringkas, tombol mikrofon mengaktifkan sesi, tombol rekam menyimpan WAV. Posisi dan tema tersimpan. Meter dan timer memakai sesi aktual. Shortcut: Cmd+Shift+M mikrofon, Cmd+R rekam/simpan, Cmd+, Settings, Cmd+Q keluar.

Driver mikrofon dipasang melalui installer macOS di Panduan. Installer meminta autentikasi admin untuk menyalin driver ke `/Library/Audio/Plug-Ins/HAL/iHearYouMic.driver` dan memuat ulang CoreAudio. Tutup rekaman/panggilan sebelum memasang. Jika driver sudah tersedia, tidak perlu memasang ulang saat aplikasi diperbarui. Menutup jendela membiarkan aplikasi berjalan di menu bar.

**Dengar langsung** memakai headphone untuk menghindari feedback. Mikrofon dan speaker dapat diganti saat capture; aplikasi menghentikan sesi lama lalu memulai dengan perangkat pilihan. Jika sedang merekam WAV, file lama disimpan dan rekaman berlanjut di file baru. Perangkat yang terputus menghentikan sesi dengan pesan; aplikasi tidak diam-diam meneruskan capture dari mikrofon lain.

## iPhone, Bluetooth, dan kabel

Picker menampilkan input/output hidup yang diberikan macOS, termasuk mikrofon iPhone Continuity, Bluetooth, USB, earphone kabel, dan perangkat audio lain. Label menunjukkan jenis koneksi. Daftar diperbarui setiap dua detik dan lewat notifikasi CoreAudio; tombol **Muat ulang perangkat** tersedia. Perangkat internal/tersembunyi dan loopback iHearYou tidak dijadikan sumber input atau monitor.

Mikrofon iPhone memakai [Continuity Camera](https://support.apple.com/102546), lewat USB atau nirkabel dengan Wi-Fi dan Bluetooth aktif serta Apple Account yang sama. Izinkan Trust jika iPhone tersambung melalui USB. Pasangkan perangkat Bluetooth di macOS atau sambungkan kabel sebelum memilihnya. Format Bluetooth bergantung pada profil perangkat; pipeline meresampling input ke 48 kHz.

Untuk **speaker bawaan iPhone**, pilih mikrofon Mac/USB/Bluetooth lalu aktifkan **Speaker iPhone via Safari** di Settings. Sambungkan kedua perangkat ke Wi-Fi yang sama, pindai QR atau salin tautan, dan ketuk **Dengarkan** di Safari iPhone. Biarkan layar dan tab terbuka. Penerima memiliki volume, meter, dan tombol Putuskan. Ini memutar hasil mikrofon iHearYou, bukan seluruh audio sistem Mac. Mikrofon virtual untuk browser Mac tetap tersedia.

Continuity mengekspos mikrofon iPhone, bukan speaker pada perangkat yang diuji. Membuka kunci iPhone menjeda Continuity, sehingga mode Safari memakai mikrofon Mac/USB/Bluetooth. Memilih mikrofon Continuity mematikan penerima Safari. Gunakan earphone atau volume rendah untuk menghindari feedback.

Penerima hanya aktif setelah dinyalakan, memakai alamat IPv4 jaringan lokal dan tautan acak baru setiap aktivasi, serta menerima satu tab sekaligus. Audio PCM dikirim langsung melalui HTTP lokal tanpa enkripsi transport; gunakan jaringan yang dipercaya dan perlakukan tautan sebagai akses mendengarkan. Mematikan mode menutup koneksi dan membatalkan tautan. Tidak ada endpoint upload, akses rekaman tersimpan, atau layanan cloud. Penyangga audio dibatasi agar koneksi lambat tidak menumpuk memori atau delay tanpa batas.

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

Build memverifikasi SHA-256 dan mengambil model/runtime resmi jika belum tersedia. Model DPDFNet2, sherpa-onnx 1.13.8 dan ONNX Runtime 1.28.2 disalin ke bundle; tidak bergantung pada path workspace saat dipasang. **Real app logo.icns** dipakai langsung untuk ikon aplikasi. Driver universal arm64/x86_64 dibangun dari source BlackHole. Debug record dibuang dari binary aplikasi sebelum packaging.

Hasil di `dist/`:

- `iHearYou.app`: aplikasi lengkap.
- `iHearYou-1.2.0.pkg`: installer aplikasi ke `/Applications` dan driver ke `/Library/Audio/Plug-Ins/HAL`; meminta admin dan memuat ulang CoreAudio.
- `iHearYou-1.2.0-macOS-arm64.zip`: aplikasi tanpa pemasangan driver.
- `iHearYouMicrophone.pkg`: driver saja, untuk aplikasi yang sudah terpasang.
- `SHA256SUMS.txt`: checksum artefak Releases.

Unduh melalui [GitHub Releases](https://github.com/fumakill4/iHearYou/releases). Aplikasi memerlukan Apple Silicon dan macOS 14+. App/library memakai signature ad-hoc; installer belum ditandatangani Developer ID atau dinotarize. Gatekeeper dapat meminta pengguna mengizinkan pembukaan secara manual. Tutup panggilan/rekaman sebelum memasang installer lengkap karena CoreAudio dimuat ulang.

Source dependency, versi, lisensi, dan checksum dicatat di `THIRD_PARTY_NOTICES.md`. Eksperimen DeepFilterNet/RNNoise di workspace bukan bagian engine build saat ini. Rekaman, model/runtime unduhan, log, cache build, dan data lokal diabaikan Git. Repo menyertakan model card, license, header C, serta script unduhan dengan checksum.

## Lisensi dan uninstall

iHearYou GPL-3.0-or-later; DPDFNet2 dan sherpa-onnx Apache-2.0; ONNX Runtime MIT; driver BlackHole GPLv3. Copyright upstream tetap dipertahankan. Untuk uninstall, tutup aplikasi audio dan pindahkan hanya `iHearYouMic.driver` ke Trash melalui Finder, lalu restart Mac. Rekaman tetap di Musik sampai dihapus pengguna.
