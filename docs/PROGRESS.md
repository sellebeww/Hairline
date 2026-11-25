# PROGRESS

Terakhir diperbarui: 2026-11-25, akhir Fase 9 (audit independen).

## Fase

| Fase | Isi | Status |
|---|---|---|
| 1 | Repo, toolchain, spike opencv_dart | SELESAI-TERVERIFIKASI untuk repo/toolchain/`make verify`; spike: API dan build native terbukti, tes runtime Dart BELUM dijalankan (B1) |
| 2 | Geometri lembar, homografi + diagnostik, panduan pose, kualitas, harness sintetis (hairline_core) | SELESAI-TERVERIFIKASI (dart test 153 lulus, cakupan 97,8 persen); perilaku/akurasi: TERVERIFIKASI-SINTETIS |
| 3 | Pengukuran lebar retak sub-pixel (hairline_core): patch/sampler, LM, PSF, punggung retak, profil, orkestrasi frame | SELESAI-TERVERIFIKASI (dart test 287 lulus, cakupan 98,4 persen); akurasi: TERVERIFIKASI-SINTETIS |
| 4 | Anggaran ketidakpastian, agregasi, tren, statistik pelat, studi sintetis, kalibrasi `rho` (hairline_core) | SELESAI-TERVERIFIKASI (dart test 401 lulus, cakupan 98,2 persen, `make verify` bersih); perilaku/cakupan: TERVERIFIKASI-SINTETIS |
| 5 | Port + pipeline frame (core), adapter OpenCV (paket terpisah), isolate, Drift, penyimpanan foto, VisitProcessor, provider | SELESAI-TERVERIFIKASI untuk isolate/pipeline/Drift/kunjungan/provider (core 415 tes, app 50 tes, `make verify` bersih); adapter OpenCV: SELESAI-PERLU-UJI-PERANGKAT (ditulis, analyze bersih, tes BELUM dijalankan, B1); app belum bergantung pada paket adapter (D34) |
| 6 | Alur pengambilan: CameraService (lifecycle, burst, kunci), kanal Kotlin lensa, deteksi live di isolate + throttle, overlay, mesin status, gerbang kualitas pra-simpan, simulasi | SELESAI-TERVERIFIKASI untuk mesin status, analisis pose live, throttle/isolate, lifecycle `DeviceCameraService` (driver tiruan), kanal lensa (channel tiruan), overlay (widget test), alur ujung ke ujung dengan `FakeCameraService` (SINTETIS; app 149 tes, `make verify` bersih; APK debug dan rilis terbangun); kamera nyata (`CameraPluginDriver`), kunci fokus, kanal Kotlin di perangkat, detektor live OpenCV: SELESAI-PERLU-UJI-PERANGKAT (docs/DEVICE_TEST.md) |
| 7 | Lembar PDF, pemasangan terpandu, layar (situs, retak, detail, titik ukur, hasil, tren, bantuan, tentang), kunjungan dasar dua tahap, proses ulang, aksesibilitas | SELESAI-TERVERIFIKASI untuk kode dan tes host (core 432 tes, app 192 tes, `make verify` bersih); alur ujung ke ujung dengan kamera tiruan: TERVERIFIKASI-SINTETIS; cetak nyata, kamera, OpenCV di perangkat, TalkBack: SELESAI-PERLU-UJI-PERANGKAT (DEVICE_TEST bagian 10) |
| 8 | Pelat validasi (generator PDF, impor CSV, alat pindai), mode validasi di aplikasi, `u_dev` PERANGKAT, validasi sintetis versi aplikasi, build rilis, README dan DEVICE_TEST final | SELESAI-TERVERIFIKASI untuk kode dan tes host (core 482 tes, app 209 tes, `make verify` bersih, APK dan AAB rilis terbangun, manifest hanya CAMERA); pipeline validasi: TERVERIFIKASI-SINTETIS; pelat cetak, pindaian, akurasi nyata, `u_dev` nyata, APK di perangkat: SELESAI-PERLU-UJI-PERANGKAT (DEVICE_TEST bagian 11 dan 12) |
| 9 | Audit independen (docs/AUDIT.md), perbaikan, finalisasi, tag `v0.1.0-mvp` | SELESAI-TERVERIFIKASI untuk kode dan tes host (core 492 tes, app 215 tes, `make verify` bersih, 65 butir audit PASS dari 54 awal, studi sintetis direproduksi identik); APK rilis dan APK perangkat (OpenCV) terbangun; semua yang butuh ponsel: SELESAI-PERLU-UJI-PERANGKAT (BLOCKERS B2) |

## Butir Wajib

| # | Butir | Status | Kode/test |
|---|---|---|---|
| 1 | Lembar bingkai PDF | SELESAI-TERVERIFIKASI untuk geometri vektor dan id (tes core + PDF; OpenCV Python di host mendeteksi 24 lembar, bukan opencv_dart). Cetak 100 persen nyata dan deteksi foto cetak: SELESAI-PERLU-UJI-PERANGKAT | core: lib/src/{sheet_layout,aruco_bits}.dart, test/sheet_layout_test.dart; app: lib/sheet/*, test/sheet/*; tools/gen_aruco_table.py, tools/verify_sheet_raster.py |
| 2 | Deteksi penanda + homografi | Bagian homografi/diagnostik: TERVERIFIKASI-SINTETIS. Deteksi penanda (opencv_dart): adapter foto dan adapter live (`OpenCvGrayMarkerDetector`) di packages/hairline_opencv, tersambung ke APK perangkat lewat `make apk-device` (D48; APK arm64 terbangun dengan libdartcv.so), tes adapter dan perilaku runtime BELUM dijalankan (B1): SELESAI-PERLU-UJI-PERANGKAT. Urutan sudut diperiksa dengan OpenCV Python pada 6 rotasi (AUDIT N10) | lib/src/homography.dart, test/homography_test.dart; spike: tools/opencv_spike |
| 3 | Panduan pose + burst + gerbang kualitas | Logika pose, gerbang geometri, mesin status alur, analisis live (stabilitas, referensi, hantu), throttle, urutan burst dan siklus hidup (driver tiruan), gerbang kualitas pra-simpan lewat `VisitProcessor`: SELESAI-TERVERIFIKASI / TERVERIFIKASI-SINTETIS. Kamera nyata (fokus/eksposur terkunci benar-benar bertahan, panggilan masuk, rotasi, multi-lensa, panas), overlay terhadap pratinjau nyata, kanal Kotlin, detektor OpenCV live: SELESAI-PERLU-UJI-PERANGKAT | app/lib/capture/*, app/lib/debug/*, app/android/.../LensInfoChannel.kt, app/test/capture/*, docs/DEVICE_TEST.md; core: lib/src/{pose,quality,frame_ports}.dart |
| 4 | Pengukuran lebar retak sub-pixel | Aplikasi (titik ukur, hasil): TERVERIFIKASI-SINTETIS (tes ujung ke ujung `app/test/e2e_mvp_test.dart`, `locate_point_test.dart`, layar hasil/titik); dengan foto nyata: SELESAI-PERLU-UJI-PERANGKAT. Inti (satu frame, agregasi median, anggaran 5.5, `k` Welch-Satterthwaite, batas ukur): TERVERIFIKASI-SINTETIS. Adapter citra dan validasi perangkat: BELUM | lib/src/{patch,lm,psf,ridge,profile_fit,measure,uncertainty,aggregate,student_t}.dart, test/{...,uncertainty,aggregate,student_t}_test.dart, docs/MEASUREMENT_NOTES.md, docs/SYNTHETIC_VALIDATION.md |
| 5 | Penyimpanan Drift | SELESAI-TERVERIFIKASI (skema 5.7, FK, migrasi, atomisitas, pemrosesan ulang tanpa menimpa, foto privat + SHA-256, maks 5) | app/lib/data, app/lib/pipeline, app/test/data, app/test/pipeline |
| 6 | Tren 2 sampai 5 kunjungan | Logika inti (delta, `u_delta`, z, klasifikasi, MDC, peringatan konteks, tanpa regresi): TERVERIFIKASI-SINTETIS. Layar tren, grafik, proses ulang: TERVERIFIKASI-SINTETIS (e2e menandai "kemungkinan bertambah lebar"; tes grafik, layar, string) | lib/src/trend.dart, test/trend_test.dart; app/lib/screens/trend_*.dart, app/test/screens/* |
| 7 | Validasi pelat + studi sintetis | Pipeline (generator pelat PDF vektor, impor CSV ketat, alat pindai `tools/measure_scan.dart`, mode validasi di aplikasi, penyimpanan `validation_runs`, `u_dev` dan label BELUM_DIVALIDASI, label SINTETIS tidak pernah menjadi PERANGKAT): TERVERIFIKASI-SINTETIS. Studi sintetis penuh (864 kondisi, kalibrasi `rho`): TERVERIFIKASI-SINTETIS. Akurasi nyata (pelat cetak, ponsel, pemindai): SELESAI-PERLU-UJI-PERANGKAT | core: lib/src/{plate,scan_measure,validation}.dart, lib/src/synthetic/plate_scene.dart, test/{plate,scan_measure,validation}_test.dart; app: lib/validation/*, lib/screens/validation_*.dart, test/validation/*, test/screens/validation_screens_test.dart; tools/measure_scan.dart; lib/src/studies/, docs/SYNTHETIC_VALIDATION.md |
| 8 | Pustaka inti Dart murni | SELESAI-TERVERIFIKASI (sheet, linalg, homografi, pose, kualitas, harness, LM, PSF, punggung, model profil, orkestrasi frame multi-titik, anggaran 5.5, agregasi, tren, pelat, pindaian, studi sintetis) | packages/hairline_core (482 tes) |

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

## Hasil Fase 6 (apa yang terbukti dan apa tidak)

- Terbukti di host (SINTETIS, tanpa kamera): alur baseline lalu follow-up ujung ke ujung (`app/test/capture/capture_controller_test.dart`, grup "end to end"): deteksi live di isolate, siap setelah 5 frame mantap, burst 6, pemrosesan lewat isolate dan gerbang, kunjungan dasar tersimpan dengan `reference_pose_json`, hantu muncul di follow-up. Kunjungan tak lolos tidak menulis apa pun (tabel visits dan folder foto kosong).
- Tes lifecycle dengan driver tiruan menangkap: pause di tengah burst, pause menunggu bidikan berjalan, dispose ganda, callback stream basi, burst ganda, urutan stream/kunci/bidik/buka kunci. Tes ujung ke ujung menemukan dua bug nyata (provider auto-dispose menutup kamera, ref mati setelah layar ditutup), keduanya diperbaiki (D42).
- Manifest rilis terverifikasi dari APK rilis yang terbangun: hanya `CAMERA` (tanpa `INTERNET`).
- TIDAK terbukti: apa pun tentang kamera nyata (fokus terkunci bertahan, CameraX tidak memutar bingkai analisis, kinerja stream beresolusi maksimum, panas, penyelarasan overlay), kanal Kotlin di perangkat (hanya terkompilasi), deteksi OpenCV live. Nilai ambang stabilitas dan 5 frame adalah nilai awal.

## Hasil Fase 7 (apa yang terbukti dan apa tidak)

- Terbukti di host (SINTETIS): rantai penuh dengan kamera tiruan: buat retak, foto dasar (gerbang geometri), ketuk dan tempelkan titik ke punggung retak (galat < 0,1 mm dari garis benar, arah dalam 3 derajat), simpan dasar, dua kunjungan lanjutan dengan lebar 1,0 dan 1,6 mm (dasar 0,5 mm), tren menandai "kemungkinan bertambah lebar". Lembar: 24 tata letak terbaca benar oleh detektor ArUco OpenCV Python (galat sudut terburuk 0,056 mm), PDF 30 mm persis.
- TIDAK terbukti: cetak nyata di printer, foto lembar cetak oleh `opencv_dart`, kamera, orientasi EXIF foto di layar titik ukur, TalkBack, kinerja pemrosesan dasar dua kali. Aplikasi belum bergantung pada `hairline_opencv` (D34, B1): APK nyata belum bisa mendeteksi penanda sampai disambungkan. Semua hasil berlabel `BELUM_DIVALIDASI`; tidak ada angka akurasi PERANGKAT.
- Tangkapan layar tidak dibuat: lihat docs/screenshots/README.md.

## Hasil Fase 8 (apa yang terbukti dan apa tidak)

- Terbukti di host (SINTETIS): foto pelat sintetis 32 titik dalam satu dekode (`processFramePoints`): garis lebar >= 0,5 mm terukur dalam 0,03 mm dari lebar sebenarnya (0,12 mm/px, sigma 1 px); pindaian sintetis 600 dpi (miring 1,5 derajat, titik asal meleset 0,8 mm) terukur dalam 0,012 mm; run validasi lewat alur pengambilan dengan `FakeCameraService` tersimpan `SINTETIS`, tidak pernah `PERANGKAT`, dan tidak mengubah anggaran; run `PERANGKAT` (dengan kebenaran karakterisasi sintetis) menurunkan `u_dev` kunjungan berikutnya untuk model itu dan menghilangkan BELUM_DIVALIDASI; kebenaran NOMINAL tidak pernah memvalidasi; run terbaru yang gagal mencabut validasi.
- Build rilis (host macOS, Flutter 3.47.5): `flutter build apk --release` 61,6 MB (tiga ABI, tanpa OpenCV karena belum tersambung; unduhan terkompresi menurut `apkanalyzer` 28,0 MB), `appbundle` 61,0 MB; R8 dan penyusutan sumber daya aktif; `aapt dump permissions`: hanya `CAMERA` (dan izin internal app), tanpa `INTERNET`. Ditandatangani kunci debug karena tidak ada `key.properties` (cara pemilik menandatangani: README dan `key.properties.example`).
- TIDAK terbukti: cetak pelat, pindaian nyata, kamera nyata, deteksi OpenCV, akurasi atau `u_dev` nyata, perilaku R8 pada perangkat. Ambang validasi (16 garis, 4 lebar, cakupan 0,9) adalah nilai awal; cakupan pelat dalam-sampel. Tidak ada angka `PERANGKAT`.

## Hasil Fase 9 (apa yang terbukti dan apa tidak)

- Terbukti di host: 313 pemeriksaan numerik independen (numpy/scipy, detektor ArUco OpenCV Python) PASS: homografi, `rms_px`, `loo_mm`, `mm_per_px`, tilt, profil, anggaran 5.5, `u_delta`, `k`. Studi sintetis diulang dengan seed 20261117: 5184 dari 5184 rekaman identik (SINTETIS). `make verify` bersih (core 492, app 215 tes).
- Cacat nyata yang ditemukan dan diperbaiki (11): lihat docs/AUDIT.md bagian 3 dan DECISIONS D48 sampai D53 (APK tanpa detektor, cadangan data aktif, peringatan frame tak tampil, lembar bergeser tak ditandai, klaim galat `k` salah, overlay dua kali skala, id penanda ganda, label dan kata di dokumen, tes CSV, Makefile).
- TIDAK terbukti: semua butir B2 (kamera, OpenCV runtime, cetak, validasi pelat, TalkBack, R8). Tidak ada angka `PERANGKAT`. Cakupan baris tes tidak dihitung ulang.

## Konteks untuk sesi berikutnya

- Baca CLAUDE.md, docs/AUDIT.md, DECISIONS D48 sampai D53, BLOCKERS B1 dan B2, docs/DEVICE_TEST.md (bagian 0 sampai 14). Tag `v0.1.0-mvp` menandai akhir Fase 9.
- Pekerjaan berikutnya hanya dapat dilakukan pemilik di ponsel: `make apk-device`, pasang, jalankan DEVICE_TEST (urutan: 10, 1 sampai 9, 11, 13, 14, 12). Isi hasil dengan label `PERANGKAT`; catat di README hanya angka yang diukur.
- Struktur: core murni `packages/hairline_core`; adapter `packages/hairline_opencv` (tidak jadi dependensi `app/` di git, D48); `app/lib/main_device.dart` hanya dipakai `tools/build_device_apk.sh`; simulasi tanpa kamera `cd app && flutter run -t lib/main_fake.dart`.
- Verifikasi: `make verify` (core, analyze adapter, app), `make audit-docs`, `make audit-numeric PY=<python dengan numpy scipy opencv-contrib-python-headless>`. Studi sintetis: `cd packages/hairline_core && dart run tool/run_synthetic_study.dart simulate --reps 6` lalu `analyze` (sekitar 1 jam pada 8 inti; hapus `build/synthetic_study` dulu agar benar-benar diulang).
- Catatan Gradle: bila NoSuchFileException di cache transforms: `app/android/gradlew --stop` lalu ulangi. Build perangkat pertama mengompilasi OpenCV (sekitar 20 menit); jangan mulai dua build bersamaan (kunci hook `dartcv4`).
- Ambang awal belum dituning di perangkat: `QualityThresholds`, stabilitas live, `maxTrackingOffsetMm` 0,5 mm, ambang validasi pelat (16 garis, 4 lebar, cakupan 0,9). `rho = 1.0` hanya terhadap simulasi; `u_dev` bawaan 0,5 mm/px tetap sampai ada validasi PERANGKAT.
