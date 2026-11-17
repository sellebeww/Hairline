# PROGRESS

Terakhir diperbarui: 2026-11-17, akhir Fase 1.

## Fase

| Fase | Isi | Status |
|---|---|---|
| 1 | Repo, toolchain, spike opencv_dart | SELESAI-TERVERIFIKASI untuk repo/toolchain/`make verify`; spike: API dan build native terbukti, tes runtime Dart BELUM dijalankan (B1) |
| 2 | Belum dimulai | BELUM |
| 3 | Belum dimulai | BELUM |
| 4 | Belum dimulai | BELUM |
| 5 | Belum dimulai | BELUM |
| 6 | Belum dimulai | BELUM |
| 7 | Belum dimulai | BELUM |
| 8 | Belum dimulai | BELUM |
| 9 | Belum dimulai | BELUM |

## Butir Wajib

| # | Butir | Status | Kode/test |
|---|---|---|---|
| 1 | Lembar bingkai PDF | BELUM | - |
| 2 | Deteksi penanda + homografi | BELUM | spike: tools/opencv_spike (ditulis, belum dijalankan) |
| 3 | Panduan pose + burst + gerbang kualitas | BELUM | - |
| 4 | Pengukuran lebar retak sub-pixel | BELUM | - |
| 5 | Penyimpanan Drift | BELUM | - |
| 6 | Tren 2 sampai 5 kunjungan | BELUM | - |
| 7 | Validasi pelat + studi sintetis | BELUM | - |
| 8 | Pustaka inti Dart murni | BELUM | kerangka: packages/hairline_core (tes smoke) |

## Toolchain (dicek 2026-11-17, host macOS 14.8.9 arm64)

- Flutter 3.47.5 stable (Dart 3.13.4), tersedia sebelumnya di `~/development/flutter`, tidak perlu dipasang.
- JDK: OpenJDK 25.0.2 (`/usr/bin/java`). Android SDK 37.0.0 di `~/Library/Android/sdk`: platforms android-34..37.1, build-tools 36.0.0 / 36.1.0 / 37.0.0, NDK 28.2.13676358, cmdline-tools terpasang. `flutter doctor`: Android toolchain OK; Xcode tidak lengkap (hanya Command Line Tools, tanpa CocoaPods).
- `adb devices`: tidak ada perangkat. Python 3.15.2; `opencv-contrib-python-headless` 5.0.0 dipasang di venv sementara (di luar repo).
- cmake 4.4.5 dan ninja 1.13.2 (Homebrew) ada. Docker CLI ada, daemon tidak aktif.

## Konteks untuk sesi berikutnya

- Baca CLAUDE.md, DECISIONS.md (D1 sampai D12), SPIKE_OPENCV.md.
- `opencv_dart` TIDAK ada di `app/pubspec.yaml` (D1, B1). Tambahkan di Fase 5 beserta `hooks.user_defines` (lihat tools/opencv_spike/pubspec.yaml) dan jalankan tes adapter di CI Linux atau perangkat.
- Di mesin ini hanya `hairline_core` dan tes app tanpa opencv yang bisa dijalankan.
- `make verify` bersih (hasil di laporan akhir Fase 1). Core hanya berisi konstanta versi; belum ada logika bisnis.
- ArUco ADA di opencv_dart 2.2.2 (modul aruco + objdetect + calib3d, D10). APK arm64 +13,5 MB. Tes Dart spike belum pernah dijalankan (B1): jalankan di Linux/CI atau perangkat di awal Fase 5.
- Jika Gradle gagal dengan NoSuchFileException di cache transforms: `app/android/gradlew --stop` lalu ulangi.
