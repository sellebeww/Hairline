# PROGRESS

Terakhir diperbarui: 2026-11-17, akhir Fase 2.

## Fase

| Fase | Isi | Status |
|---|---|---|
| 1 | Repo, toolchain, spike opencv_dart | SELESAI-TERVERIFIKASI untuk repo/toolchain/`make verify`; spike: API dan build native terbukti, tes runtime Dart BELUM dijalankan (B1) |
| 2 | Geometri lembar, homografi + diagnostik, panduan pose, kualitas, harness sintetis (hairline_core) | SELESAI-TERVERIFIKASI (dart test 153 lulus, cakupan 97,8 persen); perilaku/akurasi: TERVERIFIKASI-SINTETIS |
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
| 2 | Deteksi penanda + homografi | Bagian homografi/diagnostik: TERVERIFIKASI-SINTETIS. Deteksi penanda (opencv_dart): BELUM (spike ditulis, belum dijalankan) | lib/src/homography.dart, test/homography_test.dart; spike: tools/opencv_spike |
| 3 | Panduan pose + burst + gerbang kualitas | Logika pose dan gerbang geometri: TERVERIFIKASI-SINTETIS. Overlay, burst, kamera, gerbang citra: BELUM | lib/src/pose.dart, lib/src/quality.dart, test/pose_test.dart, test/quality_test.dart |
| 4 | Pengukuran lebar retak sub-pixel | BELUM | - |
| 5 | Penyimpanan Drift | BELUM | - |
| 6 | Tren 2 sampai 5 kunjungan | BELUM | - |
| 7 | Validasi pelat + studi sintetis | Fondasi harness sintetis tervalidasi (SELESAI-TERVERIFIKASI); studi dan pelat: BELUM | lib/src/synthetic/, test/synthetic/ |
| 8 | Pustaka inti Dart murni | Sebagian: sheet, linalg, homografi, pose, kualitas, harness SELESAI-TERVERIFIKASI; model profil/anggaran/tren BELUM | packages/hairline_core (153 tes, cakupan 97,8 persen) |

## Toolchain (dicek 2026-11-17, host macOS 14.8.9 arm64)

- Flutter 3.47.5 stable (Dart 3.13.4), tersedia sebelumnya di `~/development/flutter`, tidak perlu dipasang.
- JDK: OpenJDK 25.0.2 (`/usr/bin/java`). Android SDK 37.0.0 di `~/Library/Android/sdk`: platforms android-34..37.1, build-tools 36.0.0 / 36.1.0 / 37.0.0, NDK 28.2.13676358, cmdline-tools terpasang. `flutter doctor`: Android toolchain OK; Xcode tidak lengkap (hanya Command Line Tools, tanpa CocoaPods).
- `adb devices`: tidak ada perangkat. Python 3.15.2; `opencv-contrib-python-headless` 5.0.0 dipasang di venv sementara (di luar repo).
- cmake 4.4.5 dan ninja 1.13.2 (Homebrew) ada. Docker CLI ada, daemon tidak aktif.

## Pemetaan aturan Fase 2 ke test (packages/hairline_core/test)

| Aturan | Test (file: grup / nama) |
|---|---|
| 5.1 id penanda 4s+0..3, TL/TR/BR/BL, sheet 0..11 | sheet_test: marker ids and corners / sheet s has ids...; sheet ids outside 0..11... |
| 5.1 pusat (+-60,+-60), sudut OpenCV +-15 | sheet_test: centres are at...; corners are in OpenCV order... |
| 5.1 semua dimensi x print_scale | sheet_test: print scale multiplies every coordinate; window bounds scale... |
| 5.1 jendela 70, zona ukur 50, celah 10, sisi dalam 45 | sheet_test: window is 70 mm square...; inner marker edge is 45 mm... |
| 5.1 batang skala 100 mm | sheet_test: scale bar is 100 mm long... |
| 5.1 print_scale = L/100, u_print_rel = (0,5/sqrt3)/L | sheet_test: print scale from ruler (4 test, termasuk penolakan rentang) |
| 5.2 >= 3 penanda, < 3 ditolak | homography_test: input validation / fewer than 3 markers...; markers of another sheet are ignored... |
| 5.2 DLT+LM, H dan H_inv, galat < 1e-6 px | homography_test: noiseless recovery (8 seed acak, 3 penanda, H_inv, print scale) |
| 5.2 derau 0,2 px sesuai ekspektasi statistik | homography_test: noise statistics (galat posisi pusat dan sudut jendela, bias nol, rms_px sigma*sqrt(2(2n-8)/2n)) |
| 5.2 3 vs 4 penanda | homography_test: 3 markers are less accurate than 4...; noiseless 3 markers... |
| 5.2 degenerate / kolinear / cermin / kedalaman | homography_test: input validation (collinear x4, coincident, mirrored, reversed corners, inconsistent depth) |
| 5.2 loo_mm (hanya 4 penanda), membesar bila satu penanda bergeser | homography_test: leave-one-marker-out (3 test); noiseless recovery (looMm null/kecil) |
| 5.2 mm_per_px dan anisotropi (Jacobian) | homography_test: local scale (5.2) (fronto-parallel, tilt 10/20/30 analitik, titik luar pusat) |
| 5.2 f_px dari metadata/default, tilt_is_approx | pose_test: intrinsics (5.2) (4 test); tilt (5.2) with exact f |
| 5.2 tilt 0/10/20/30 dipulihkan; f_px meleset 20 persen | pose_test: tilt (5.2) with exact f; tilt with f_px off by 20 percent (envelope + arah + akibat ke gerbang) |
| 5.2 deviasi pose dan instruksi, ambang di dalam/di luar | pose_test: pose instructions (5.2) (arah 4, ambang translasi, skala, rotasi, wrap, tilt, prioritas, ambang kustom/standar) |
| 5.4 QualityThresholds dan gerbang geometri frame/kunjungan | quality_test (13 test) |
| Harness: renderer valid (lebar efektif = nominal) | synthetic/synthetic_test: renderer validation: effective crack width equals nominal (12 tanpa PSF, 3 dengan PSF, kuantisasi+derau, melengkung) |
| Harness: lembar, kamera, detektor, derau | synthetic_test: renderer validation: sheet; SyntheticCamera; gaussian / detector noise |

Hasil Fase 2 (SINTETIS, seed tetap, lihat DECISIONS D17 dan D18): derau sudut 0,2 px pada 0,08 mm/px memberi galat posisi 0,0076 mm di pusat jendela (1,34x estimasi 4-dof) dan 0,0084 mm di sudut jendela dengan 4 penanda; 3 penanda 2,6x lebih buruk di pusat. `loo_mm` 0,06 mm dengan derau saja; satu penanda digeser 5 px (0,4 mm) memberi 0,28 mm (dekat ambang 0,3). Galat `f_px` 20 persen menggeser tilt sekitar 0,2 x tilt.

## Konteks untuk sesi berikutnya

- Baca CLAUDE.md, DECISIONS.md (D1 sampai D12), SPIKE_OPENCV.md.
- `opencv_dart` TIDAK ada di `app/pubspec.yaml` (D1, B1). Tambahkan di Fase 5 beserta `hooks.user_defines` (lihat tools/opencv_spike/pubspec.yaml) dan jalankan tes adapter di CI Linux atau perangkat.
- Di mesin ini hanya `hairline_core` dan tes app tanpa opencv yang bisa dijalankan.
- Fase 2 selesai: API inti di `lib/hairline_core.dart` (sheet, homography, pose, quality, linalg_small, point) dan harness `package:hairline_core/synthetic.dart` (SyntheticCamera, SyntheticDetector, renderGray, crackScene, sheetScene, effectiveWidthMm). Konvensi D15 sampai D18 (piksel berpusat di integer, instruksi = tindakan pada ponsel, tilt skalar). Fase 3 (PDF lembar) memakai konstanta `sheet.dart`; Fase 4 (profil) memakai renderer untuk retak berlebar tepat.
- `make verify` bersih (hasil di laporan akhir Fase 1). Core hanya berisi konstanta versi; belum ada logika bisnis.
- ArUco ADA di opencv_dart 2.2.2 (modul aruco + objdetect + calib3d, D10). APK arm64 +13,5 MB. Tes Dart spike belum pernah dijalankan (B1): jalankan di Linux/CI atau perangkat di awal Fase 5.
- Jika Gradle gagal dengan NoSuchFileException di cache transforms: `app/android/gradlew --stop` lalu ulangi.
