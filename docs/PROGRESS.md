# PROGRESS

Terakhir diperbarui: 2026-11-17, akhir Fase 5.

## Fase

| Fase | Isi | Status |
|---|---|---|
| 1 | Repo, toolchain, spike opencv_dart | SELESAI-TERVERIFIKASI untuk repo/toolchain/`make verify`; spike: API dan build native terbukti, tes runtime Dart BELUM dijalankan (B1) |
| 2 | Geometri lembar, homografi + diagnostik, panduan pose, kualitas, harness sintetis (hairline_core) | SELESAI-TERVERIFIKASI (dart test 153 lulus, cakupan 97,8 persen); perilaku/akurasi: TERVERIFIKASI-SINTETIS |
| 3 | Pengukuran lebar retak sub-pixel (hairline_core): patch/sampler, LM, PSF, punggung retak, profil, orkestrasi frame | SELESAI-TERVERIFIKASI (dart test 287 lulus, cakupan 98,4 persen); akurasi: TERVERIFIKASI-SINTETIS |
| 4 | Anggaran ketidakpastian, agregasi, tren, statistik pelat, studi sintetis, kalibrasi `rho` (hairline_core) | SELESAI-TERVERIFIKASI (dart test 401 lulus, cakupan 98,2 persen, `make verify` bersih); perilaku/cakupan: TERVERIFIKASI-SINTETIS |
| 5 | Port + pipeline frame (core), adapter OpenCV (paket terpisah), isolate, Drift, penyimpanan foto, VisitProcessor, provider | SELESAI-TERVERIFIKASI untuk isolate/pipeline/Drift/kunjungan/provider (core 415 tes, app 50 tes, `make verify` bersih); adapter OpenCV: SELESAI-PERLU-UJI-PERANGKAT (ditulis, analyze bersih, tes BELUM dijalankan, B1); app belum bergantung pada paket adapter (D34) |
| 6 | Belum dimulai | BELUM |
| 7 | Belum dimulai | BELUM |
| 8 | Belum dimulai | BELUM |
| 9 | Belum dimulai | BELUM |

## Butir Wajib

| # | Butir | Status | Kode/test |
|---|---|---|---|
| 1 | Lembar bingkai PDF | BELUM | - |
| 2 | Deteksi penanda + homografi | Bagian homografi/diagnostik: TERVERIFIKASI-SINTETIS. Deteksi penanda (opencv_dart): adapter ditulis di packages/hairline_opencv, tes BELUM dijalankan (B1) | lib/src/homography.dart, test/homography_test.dart; spike: tools/opencv_spike |
| 3 | Panduan pose + burst + gerbang kualitas | Logika pose dan gerbang geometri: TERVERIFIKASI-SINTETIS. Overlay, burst, kamera, gerbang citra: BELUM | lib/src/pose.dart, lib/src/quality.dart, test/pose_test.dart, test/quality_test.dart |
| 4 | Pengukuran lebar retak sub-pixel | Inti (satu frame, agregasi median, anggaran 5.5, `k` Welch-Satterthwaite, batas ukur): TERVERIFIKASI-SINTETIS. Adapter citra dan validasi perangkat: BELUM | lib/src/{patch,lm,psf,ridge,profile_fit,measure,uncertainty,aggregate,student_t}.dart, test/{...,uncertainty,aggregate,student_t}_test.dart, docs/MEASUREMENT_NOTES.md, docs/SYNTHETIC_VALIDATION.md |
| 5 | Penyimpanan Drift | SELESAI-TERVERIFIKASI (skema 5.7, FK, migrasi, atomisitas, pemrosesan ulang tanpa menimpa, foto privat + SHA-256, maks 5) | app/lib/data, app/lib/pipeline, app/test/data, app/test/pipeline |
| 6 | Tren 2 sampai 5 kunjungan | Logika inti (delta, `u_delta`, z, klasifikasi, MDC, peringatan konteks, tanpa regresi): TERVERIFIKASI-SINTETIS. Penyimpanan dan layar: BELUM | lib/src/trend.dart, test/trend_test.dart |
| 7 | Validasi pelat + studi sintetis | Studi sintetis penuh (864 kondisi, kalibrasi `rho`): TERVERIFIKASI-SINTETIS. Alat statistik pelat: SELESAI-TERVERIFIKASI (diuji pada data buatan). Pelat nyata, impor CSV, `PERANGKAT`: BELUM | lib/src/synthetic/, lib/src/studies/, lib/src/validation.dart, test/{synthetic,studies,validation}*, tool/run_synthetic_study.dart, docs/SYNTHETIC_VALIDATION.md |
| 8 | Pustaka inti Dart murni | Sebagian: sheet, linalg, homografi, pose, kualitas, harness, LM, PSF, punggung, model profil, orkestrasi frame SELESAI-TERVERIFIKASI; anggaran 5.5, agregasi, tren, statistik pelat, studi sintetis SELESAI-TERVERIFIKASI | packages/hairline_core (401 tes, cakupan 98,2 persen) |

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

## Hasil Fase 3 (SINTETIS, seed tetap; angka lengkap di docs/MEASUREMENT_NOTES.md)

- Ideal (0,06 mm/px, sigma 1 px, derau 0,002): galat lebar 0,0 sampai 0,6 um untuk 0,3 sampai 2,0 mm. Sub-pixel (kedalaman 0,3, derau 0,02, sigma 1 px): w 0,1 mm bias +12,6 um, `u_frame` 41 um; w 0,05 mm `DI_BAWAH_BATAS_UKUR` pada 5 dari 6 frame; `u_frame` naik monoton saat w/sigma turun (uji).
- Tidak ada lebar presisi palsu pada sub-pixel: cakupan `2 u_frame` >= 97 persen untuk w sempit, setelah menambah suku bentuk kernel eps = 0,10 (D24). Retak lebar kurang tercakup (63 sampai 77 persen) karena `rho = 1,0` belum dikalibrasi; perlu sekitar 4 sampai 7.
- Bias diam-diam tercatat (tanpa peringatan): gamma sRGB tanpa linearisasi -3,9 persen (adapter wajib memanggil `linearizedFromSrgb`), PSF retak 25 persen lebih buram +17,5 um pada 0,3 mm, lengkung 0,2/mm +16 um.
- Waktu satu frame penuh 1702 x 1702 (macOS arm64, Dart VM JIT): 122 sampai 146 ms stabil, 986 ms panggilan dingin pertama. Belum diukur di ponsel.

## Hasil Fase 4 (SINTETIS, seed 20261117; angka lengkap di docs/SYNTHETIC_VALIDATION.md)

- Studi: 864 kondisi x 5 replikasi (4320 kunjungan, 21600 frame) untuk kalibrasi, 1 replikasi hold-out (864). Rantai penuh: pose acak, derau sudut 0,2 px, homografi, gerbang, patch, PSF, `measureFrame`, `aggregateVisit`.
- `rho = 1,0` didukung (tidak perlu inflasi): cakupan fit 100 persen dengan `u_truth` renderer (98,7 persen ketat); cakupan `U` bawaan 100 persen (3080 kunjungan kalibrasi, 616 hold-out), 0 kondisi signifikan di bawah 90 persen. Lima kondisi ketat (lebar 2,0 mm, galat beberapa um sampai 0,15 px) adalah resolusi renderer (S=8 menurunkan galat 2,6 sampai 4,7 kali).
- Jujur: `U` bawaan sekitar 20 kali lebih lebar dari galat (p95 `|galat|/U` = 0,05); positif palsu tren pada rantai penuh 0,2 persen pada tilt 0 (ekspektasi 4,55), `u_delta` 1,9 kali sebaran nyata pada tilt 0 dan ~20 kali pada tilt 10/20 (`u_par` dengan relief 0,3 mm). Konservatif, bukan optimistis; ketepatan butuh validasi `PERANGKAT`. Uji unit tren (20000 replikasi): positif palsu 4,61 persen, deteksi pada MDC 50,4 persen, 2 x MDC 97,7 persen.
- Batas ukur: empiris per setelan 0,1 sampai 0,5 mm; batas 5.5 median 70 sampai 440 um (didominasi `u_dev` bawaan 0,5 mm/px).

## Hasil Fase 5 (SINTETIS; angka lengkap di MEASUREMENT_NOTES)

- JPEG q85/q95 vs mentah: pergeseran lebar 0,5 / 0,2 um pada 0,6 mm, di dalam `U` 128,7 um (satu seed, codec Dart, detektor tersimulasi). MODEL_MISFIT dikecualikan dari median (D36). Patch per penanda, bukan seluruh lembar.

## Konteks untuk sesi berikutnya

- Baca CLAUDE.md, DECISIONS.md (D29 sampai D33), docs/SYNTHETIC_VALIDATION.md (bagian 8: apa yang didukung dan tidak), MEASUREMENT_NOTES.md.
- API Fase 4: `FrameRecord.fromMeasurement(m, rmsPx:, looMm:, tiltDeg:)` -> `FrameInput.accepted/rejected` -> `aggregateVisit(frames, options: UncertaintyOptions(dzMm, uPrintRel, uDevMm))` -> `VisitResult` (`status`, `budget`, `reportableWidthMm`, `storable`, `frameRejections`). Tren: `computeTrend(List<TrendVisit>, uPrintRel:)`. Pelat: `computePlateStats`, `deriveUDev` (hasil dipakai di `UncertaintyOptions.uDevMm`).
- Adapter Fase 5 tetap WAJIB: patch abu-abu +-8 mm di titik ukur dan tepi penanda, `linearizedFromSrgb()`, hitung `rmsPx`/`looMm`/`tiltDeg` dari `estimateSheetHomography` dan `estimateTilt`, jalankan `evaluateFrameGeometry` lebih dulu. Frame `MODEL_MISFIT` BELUM dikecualikan di `aggregateVisit` (FrameRecord belum membawa peringatan): putuskan di Fase 5.
- `u_dev` bawaan 0,5 mm/px dan `dz` 0,3 mm menentukan hampir seluruh `U` dan `MDC`; hanya validasi pelat nyata yang boleh mengecilkannya. Hasil selalu bertanda BELUM_DIVALIDASI tanpa `uDevMm`.
- Studi ulang: `cd packages/hairline_core && dart run tool/run_synthetic_study.dart simulate --reps 8 --workers 4` (resumable, 1 sampai 3 jam, butuh memori; proses terpisah), lalu `renderer-check` dan `analyze`. Mesin ini hanya 8 GB: tutup emulator/IDE saat studi.
- `opencv_dart` TIDAK ada di `app/pubspec.yaml` (D34, B1): sambungkan `packages/hairline_opencv` + override `framePortsFactoryProvider` di main.dart begitu bisa dibangun (Linux/Xcode), jalankan `make opencv-test`. Fase 6: `VisitProcessor.processBurst` menerima `List<Uint8List>` (pertimbangkan jalur file untuk burst besar), `deleteUnreferenced` belum dipanggil saat start. Suite core sekitar 3 sampai 6 menit.
- Jika Gradle gagal dengan NoSuchFileException di cache transforms: `app/android/gradlew --stop` lalu ulangi.
