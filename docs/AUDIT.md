# AUDIT (Fase 9)

Auditor independen, 2026-11-25. Tidak mempercayai klaim di PROGRESS.md: setiap butir di bawah dibuktikan ulang dengan perintah yang dijalankan di sesi ini. Semua angka akurasi di dokumen ini berlabel `SINTETIS` (simulasi) atau berasal dari perbandingan matematis dengan rumus; tidak ada angka `PERANGKAT` karena tidak ada ponsel, kamera, atau pelat cetak.

Status butir: `PASS` (bukti ada dan dijalankan), `FAIL` (cacat atau tanpa tes), `PERANGKAT` (hanya dapat dibuktikan di ponsel nyata, tercatat di BLOCKERS B2). Kolom "Awal" adalah keadaan sebelum perbaikan Fase 9, "Akhir" sesudahnya.

## 1. Tahap A: bukti dasar

Semua dijalankan di sesi ini, host macOS 14 arm64, Flutter 3.47.5, Dart 3.13.4, setelah `flutter clean` dan penghapusan `.dart_tool`, `coverage`, dan cache studi.

| Langkah | Perintah | Hasil nyata |
|---|---|---|
| A1 | `make verify` (awal, sebelum perubahan Fase 9) | bersih: core 482 tes lulus, app 209 tes lulus, `dart analyze --fatal-infos` dan `flutter analyze` (app, `hairline_opencv`) tanpa temuan |
| A2 | Studi sintetis diulang dari nol: `dart run tool/run_synthetic_study.dart simulate --reps 6`, `renderer-check`, `analyze` (seed 20261117, algoritma `p3-1`, 864 kondisi x 6 replikasi = 5184 kunjungan) | **5184 dari 5184 rekaman kunjungan identik** sampai bit terakhir dengan simpanan lama (JSONL); tabel `renderer-check` identik; `SYNTHETIC_VALIDATION_CONDITIONS.csv` identik; `SYNTHETIC_VALIDATION.md` hanya berbeda pada versi core di header (0.3.0 menjadi 0.5.0, konstanta `hairlineCoreVersion`) dan satu kata yang diganti pada audit (H1). `rho = 1.0` tetap. Label SINTETIS |
| A3 | `make verify` (akhir, sesudah perbaikan) | bersih, EXIT=0: core **492** tes lulus (482 + 10 baru), app **215** tes lulus (209 + 6 baru), analyzer tanpa temuan. Cakupan baris tidak dihitung ulang di Fase 9 (angka 98 persen Fase 4 tidak diverifikasi ulang) |
| A4 | `make audit-numeric` | 313 PASS, 0 FAIL (bagian 2.3) |
| A5 | `python3 tools/audit/doc_checks.py` | OK: tanpa em dash, tanpa kata terlarang, angka berlabel |
| A6 | `flutter build apk --release` (app tanpa detektor, build host) | berhasil, 61,6 MB (tiga ABI); `aapt dump permissions`: hanya `CAMERA` (dan izin internal `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` milik aplikasi); tanpa `INTERNET`; `allowBackup=false`; tanpa `libdartcv.so` |
| A7 | `tools/build_device_apk.sh --target-platform android-arm64` (APK perangkat dengan OpenCV) | berhasil, 35,8 MB arm64; memuat `lib/arm64-v8a/libdartcv.so` 13,4 MB dan `libapp.so`; izin hanya `CAMERA`; `allowBackup=false`; `pubspec.yaml` dan `pubspec.lock` dipulihkan (`git status` bersih untuk keduanya). Percobaan pertama gagal karena dua kesalahan impor di `main.dart` dan `main_device.dart` (Dart 3 `Override` dan provider); percobaan kedua gagal karena kunci hook `dartcv4` dipegang proses sisa percobaan pertama; ketiga berhasil memakai pustaka native yang sudah dikompilasi. Perilaku runtime di perangkat tidak dijalankan: PERANGKAT |

| A8 | `tools/opencv_device_test.sh emulator-5554` (emulator Android arm64, API 29, `opencv_dart` 2.2.2 asli) | **13 dari 13 tes adapter lulus**: urutan sudut pada rotasi 0, 90, 180, 270 dan perspektif, id unik dan di luar lembar, tanpa penanda, detektor live, dekode, ROI, dispose, kebocoran RSS 12 MP. Emulator, bukan ponsel fisik: PERANGKAT untuk ponsel dan kamera nyata |

Kegagalan Tahap A yang ditemukan dan diperbaiki: dua impor (di atas), satu tes manifest yang salah menghitung kata INTERNET di komentar XML (diperbaiki dengan membuang komentar sebelum memeriksa).

## 2. Tahap B dan C: butir audit

### 2.1 Keterlacakan: butir Wajib 1 sampai 8 dan aturan 5.1 sampai 5.8

| ID | Butir | Awal | Akhir | Bukti (kode : test) |
|---|---|---|---|---|
| T1 | Wajib 1: lembar bingkai PDF, panduan, verifikasi skala | PASS | PASS | `packages/hairline_core/lib/src/sheet_layout.dart:91`, `sheet.dart:125`; `test/sheet_layout_test.dart`, `test/sheet_test.dart:33,76`; `app/test/sheet/sheet_pdf_test.dart:17`. Cetak 100 persen nyata: PERANGKAT (B2.4) |
| T2 | Wajib 2: deteksi penanda dan homografi | PASS (homografi) | PASS | `homography.dart:304`; `test/homography_test.dart`; 313 pemeriksaan independen (2.3). Detektor `opencv_dart`: PERANGKAT (B2.1) |
| T3 | Wajib 3: panduan pose, burst, gerbang kualitas | PASS (logika) | PASS | `pose.dart:224`, `quality.dart:5`; `test/pose_test.dart:146`, `test/quality_test.dart:16`; `app/test/capture/*`. Kamera nyata: PERANGKAT (B2.2) |
| T4 | Wajib 4: lebar retak satu titik, profil sub-pixel, ketidakpastian | PASS | PASS | `profile_fit.dart:381`, `measure.dart`, `uncertainty.dart:154`; `test/profile_fit_test.dart:74`, `test/measure_test.dart`, `test/uncertainty_test.dart:35` |
| T5 | Wajib 5: Drift, kunjungan, frame, pengukuran | PASS | PASS | `app/lib/data/tables.dart:7`, `repository.dart:193`; `app/test/data/database_test.dart`, `app/test/pipeline/visit_processor_test.dart` |
| T6 | Wajib 6: tren 2 sampai 5 kunjungan | PASS | PASS | `trend.dart:103`; `test/trend_test.dart:19`; `app/test/screens/trend_chart_test.dart`, `screens_test.dart` |
| T7 | Wajib 7: pelat, mode validasi, laporan tersimpan, studi sintetis | PASS | PASS | `plate.dart:189`, `validation.dart`, `studies/synthetic_study.dart:24`; `test/plate_test.dart`, `test/validation_test.dart`; `app/test/validation/plate_validation_test.dart`. Akurasi nyata: PERANGKAT (B2.5) |
| T8 | Wajib 8: inti Dart murni dengan tes | PASS | PASS | `packages/hairline_core/pubspec.yaml` tanpa dependensi runtime; tanpa impor Flutter atau OpenCV; jumlah tes dan cakupan di bagian 1 |
| R51 | 5.1 geometri lembar, id, skala cetak, `u_print_rel` | PASS | PASS | `sheet.dart:125`; `test/sheet_test.dart:33,76`; `test/sheet_layout_test.dart` |
| R52 | 5.2 homografi, loo, `mm_per_px`, tilt, pose, instruksi, ambang | PASS | PASS | `homography.dart`, `pose.dart`; `test/homography_test.dart:262`, `test/pose_test.dart:146`; ambang `pose.dart:138` = 3 persen, 0,9 sampai 1,1, 5 derajat, 8 derajat |
| R53 | 5.3 profil, 40 profil, segmen 4 mm, langkah, LM dua lintasan, PSF 8 profil, gerbang kontras | PASS | PASS | `patch.dart:90` (`test/patch_test.dart:93`), `profile_fit.dart:381` (`test/profile_fit_test.dart:74` memeriksa 40, 4, 3), `psf.dart:168`, `ridge.dart:20` (radius 1,5 mm) |
| R54 | 5.4 `QualityThresholds`, gerbang frame dan kunjungan, alasan penolakan spesifik | PASS | PASS | `quality.dart:5`; `test/quality_test.dart:16` (nilai = spesifikasi), `test/measure_test.dart` (blur, anisotropi, jenuh, kontras) |
| R55 | 5.5 anggaran, `u_stat` max, `u_par`, `u_geo`, `u_print`, `u_dev`, W-S, `k`, batas bawah | PASS | PASS | `uncertainty.dart:154`, `student_t.dart:30`; `test/uncertainty_test.dart`, `test/student_t_test.dart`; dihitung ulang independen (2.3) |
| R56 | 5.6 delta, `u_delta`, z, klasifikasi, MDC, peringatan konteks, tanpa regresi | PASS | PASS | `trend.dart:103`; `test/trend_test.dart`; dihitung ulang independen (2.3) |
| R57 | 5.7 skema Drift tepat, UTC, tanpa `alerts` dan `reports`, maks 5 frame | PASS | PASS | `tables.dart` (7 tabel); `repository.dart:110,319` menolak non-UTC; `app/test/data/database_test.dart:127` |
| R58 | 5.8 data lokal, tanpa jaringan di rilis, impor CSV ketat | PASS | PASS | `app/test/android_manifest_test.dart` (baru), `plate.dart:189`, `test/plate_test.dart` |

### 2.2 Lingkup (scope lock)

| ID | Butir | Awal | Akhir | Bukti |
|---|---|---|---|---|
| S1 | Dependensi hanya yang dicatat di DECISIONS | PASS | PASS | `app/pubspec.yaml`: riverpod, go_router, drift, camera, pdf, printing (CLAUDE.md 4); `path`, `path_provider`, `crypto` (D35); `hairline_core` tanpa dependensi runtime; `opencv_dart` hanya di `packages/hairline_opencv` (D34, D48) |
| S2 | Tabel: tanpa `alerts`, `reports`; satu titik per retak | PASS | PASS | `tables.dart:5` (komentar), 7 kelas tabel; titik tunggal ditegakkan di `repository.dart` |
| S3 | Layar hanya yang diperlukan Wajib | PASS | PASS | `router.dart:29-42`: situs, retak, pengambilan, titik, hasil, tren, validasi, bantuan, tentang |
| S4 | Fitur terlarang tidak ada (laporan PDF kunjungan, notifikasi, peta, ML, kalibrasi papan catur, AR, panjang/area, keparahan) | PASS | PASS | grep `alert\|notifica\|geofenc\|firebase\|appwrite\|tflite\|arcore\|checkerboard\|severity` di `app/lib` dan `packages/*/lib`: satu-satunya kecocokan adalah teks pernyataan jujur |
| S5 | Izin dan INTERNET | PASS | PASS | lihat G1 dan G2 |

### 2.3 Kebenaran numerik (dihitung ulang tanpa membaca kode core)

Skrip: `tools/audit/independent_check.py` (numpy 2.5.5, scipy 1.18.1, OpenCV Python 5.0.0 untuk detektor ArUco nyata), benih 20261125, keluaran core dari `packages/hairline_core/tool/audit_dump.dart`. Jalankan ulang: `make audit-numeric PY=<python dengan numpy scipy cv2>`. Awal: 299 PASS, 2 FAIL (301 pemeriksaan, keduanya `k` pada dof non-bulat kecil); akhir: **313 PASS, 0 FAIL** (pemeriksaan `k` kini dua per dof: tidak di bawah kebenaran, dan selisih di dalam batas terdokumentasi).

| ID | Butir | Awal | Akhir | Bukti |
|---|---|---|---|---|
| N1 | Homografi (DLT ternormalisasi + LM) | PASS | PASS | 12 kasus (6 sintetis: tilt 0 sampai 30, rotasi dalam bidang 0 sampai 270, 3 dan 4 penanda, derau 0,1 sampai 0,5 px, `print_scale` 0,98 sampai 1,01; 6 dengan detektor ArUco nyata): selisih H pada grid lembar antara core dan LM independen paling besar 5,0e-7 px (toleransi 1e-4) |
| N2 | `rms_px` dan `loo_mm` | PASS | PASS | selisih `rms_px` paling besar 1,3e-13 px; `loo_mm` 1,3e-7 mm (toleransi 1e-5); `loo_mm` null pada 3 penanda |
| N3 | `mm_per_px` dan anisotropi (Jacobian numerik core vs analitik independen) | PASS | PASS | 36 pasangan (3 titik uji x 12 kasus): selisih relatif paling besar 4,9e-9 (`mm_per_px`) dan 1,2e-8 (anisotropi); toleransi 2e-4 |
| N4 | Tilt dari dekomposisi homografi | PASS | PASS | cocok dengan dekomposisi independen dalam 1e-7 derajat dan dengan tilt benar kamera sintetis dalam 0,029 derajat pada f benar (toleransi 1 derajat) |
| N5 | Profil model dan lebar | PASS | PASS | 4 retak analitik (w 0,3 sampai 1,0 mm, sigma 0,8 sampai 1,5 px, tilt 0 sampai 15): galat core vs kebenaran paling besar 1,4 um (w 0,3 mm); penyesuaian scipy independen pada profil spline: paling besar 0,2 um; core vs independen paling besar 1,2 um; pusat retak 0,001 um. Label SINTETIS |
| N6 | Anggaran 5.5 (14 nilai x 6 kasus) | PASS | PASS | semua komponen (`u_stat`, `u_sigma_w`, `u_pos`, `u_par`, `u_geo`, `u_print`, `u_dev`, `u_rand`, `u_sys`, `u_c`, dof W-S, lantai, lebar) sama sampai 7,5e-16 relatif |
| N7 | `u_delta`, z, MDC, klasifikasi (5 kasus) | PASS | PASS | selisih 0; kelas sama |
| N8 | Faktor `k` (14 dof terhadap `scipy.stats.t.ppf`) | FAIL | PASS | Awal: komentar `student_t.dart` mengklaim galat < 0,001, padahal interpolasi 1/dof melebihi kebenaran sampai 0,059 (dof 2 sampai 3; 7,10 vs 6,02 pada dof 1,5). Tidak pernah di bawah kebenaran (konservatif). Akhir: dokumentasi dikoreksi (D50), tes penjaga `student_t_test.dart` "against scipy" dan pemeriksaan independen dengan batas terdokumentasi |
| N9 | Konsistensi satuan (px, mm, derajat, radian) | FAIL | PASS | Semua pemanggilan sin/cos/tan/atan/acos di core dan app memakai radian dari variabel `...Deg * pi / 180` (grep `\b(sin\|cos\|tan\|atan2?\|acos)\(`). Cacat ditemukan: segmen 4 mm di overlay dikalikan `print_scale` dua kali (H sudah milimeter fisik). Diperbaiki, tes `screens_test.dart` "overlay geometry" diubah (D52) |
| N10 | Urutan sudut penanda pada empat rotasi | PASS | PASS | Penanda ArUco nyata (OpenCV Python 5.0.0 `DICT_4X4_50`, SUBPIX) dirender pada lembar 8 sampai 11 dan diproyeksikan pada rotasi dalam bidang 0, 90, 180, 270, 45, 200 derajat (tilt 0 sampai 20): 4 penanda terdeteksi di tiap kasus, H core vs H kamera benar paling besar 0,063 px, `rms_px` paling besar 0,24, `loo_mm` paling besar 0,037. Perilaku referensi OpenCV Python; urutan yang sama terbukti pada `opencv_dart` asli di emulator arm64 (A8, D54) |
| N11 | Tidak ada angka akurasi tanpa label SINTETIS/PERANGKAT di dokumen | PASS | PASS | `python3 tools/audit/doc_checks.py`: semua angka mirip akurasi berlabel (README memakai label Inggris, lihat H5) |

### 2.4 Pelanggaran asumsi: menolak atau menaikkan ketidakpastian

| ID | Skenario | Awal | Akhir | Perilaku dan bukti |
|---|---|---|---|---|
| V1 | Lembar tidak sebidang (penanda menyimpang) | PASS | PASS | Penanda digeser 10 px (1,2 mm): frame ditolak `LOO_TOO_HIGH` atau `RMS_TOO_HIGH`, tidak ada pengukuran (tes baru `frame_pipeline_test.dart` "assumption violations seen by the geometry gate"); penyimpangan kecil di bawah gerbang masuk `u_geo`. Ambang `loo_mm` 0,3 mm belum dituning (B2.6) |
| V2 | Lembar bergeser antar kunjungan | FAIL | PASS | Awal: `trackingOffsetMm` dicatat tetapi tidak dipakai; retak 0,9 mm dari titik tersimpan diukur tanpa peringatan. Akhir: peringatan `TRACKING_OFFSET` (> 0,5 mm), tampil di layar hasil dengan catatan seri terputus; lebih dari 1,5 mm: retak tidak ditemukan, ditolak (D49; tes `measure_test.dart` "sheet slipped", `screens_test.dart`). Pergeseran sepanjang retak tidak dapat dideteksi: batas yang diakui |
| V3 | Skala cetak salah | PASS | PASS | Pembacaan penggaris di luar 80 sampai 120 mm ditolak (`PrintScaleException`, `sheet_test.dart:76`). Pembacaan salah dalam rentang tidak dapat dideteksi (kesalahan masukan): galat relatif yang sama muncul di semua kunjungan sehingga dibatalkan oleh tren, tetapi tidak pada lebar mutlak. Batas yang diakui |
| V4 | Penanda sebagian tertutup | FAIL | PASS | Kurang dari 3 penanda: ditolak `TOO_FEW_MARKERS` (`frame_pipeline_test.dart`). Satu sudut salah 12 px dengan 3 penanda: ditolak `RMS_TOO_HIGH` (tes baru). Awal: adapter OpenCV membuang diam-diam id ganda dan mempercayai yang pertama; akhir: diteruskan ke core yang menolak `InvalidDetectionException` (D52, `homography_test.dart:103`) |
| V5 | Pencahayaan gradien | PASS | PASS | `measure_test.dart` "illumination gradient up to 50 percent": galat dalam 3 um + 3 `u_frame` (SINTETIS); 100 persen klip dan ditolak; bayangan sepihak ditandai `MODEL_MISFIT` dan frame diturunkan ke `TIDAK_TERUKUR` (`frame_pipeline_test.dart`, D36). Peringatan kini terlihat di layar hasil (H6) |
| V6 | Blur gerak | PASS | PASS | Blur anisotropik sigma 1 x 2,5 px ditolak oleh gerbang rasio 1,6 (`measure_test.dart` "anisotropic blur"); blur > 2,5 px ditolak |
| V7 | Tilt besar | PASS | PASS | > 20 derajat ditolak, > 30 ditolak keras (`quality_test.dart`, `frame_pipeline_test.dart` "a hard tilt"); `u_par = dz tan(tilt) / sqrt(3)` masuk anggaran |
| V8 | Jarak terlalu jauh | PASS | PASS | 0,36 mm/px terhadap batas 0,20 ditolak `RESOLUTION_TOO_COARSE` (tes baru); antara 0,10 dan 0,20 diterima dengan peringatan; lantai pelaporan `max(0,5 mm/px, 2 u_c)` |

### 2.5 Kejujuran UI dan dokumen

| ID | Butir | Awal | Akhir | Bukti |
|---|---|---|---|---|
| H1 | Tidak ada kata yang menyiratkan keselamatan bangunan | FAIL | PASS | Awal: dua dokumen teknis memakai kata keselamatan secara statistik (4 tempat). Akhir: diganti (D52); `tools/audit/doc_checks.py` dan `app/test/l10n/strings_test.dart` menjaga `app/lib`, README, docs |
| H2 | "Tidak ada perubahan terdeteksi" tidak dipakai sebagai "tidak berubah" | PASS | PASS | `strings.dart:300` menyatakan bukan bukti; `honestyNoChange` di hasil, tren, bantuan (`widgets/common.dart:49`); `strings_test.dart` memeriksa frasa |
| H3 | `BELUM_DIVALIDASI` tampil bila belum ada validasi PERANGKAT | PASS | PASS | `result_page.dart:38` (default tampil bila bendera hilang); run SINTETIS dan kebenaran NOMINAL tidak pernah memvalidasi (`plate_validation_test.dart`, `validation_screens_test.dart`) |
| H4 | Klaim pesaing dan literatur hanya yang terverifikasi | PASS | PASS | README: "reported, not verified", tanpa perbandingan produk; tidak ada klaim yang diverifikasi ke sumber primer sehingga tidak ada yang dikutip |
| H5 | Pernyataan jujur di README, layar hasil, bantuan; label asal angka sesuai kontrak | FAIL | PASS | Awal: README memakai label `SYNTHETIC` dan `DEVICE` padahal kontrak menyebut `SINTETIS` dan `PERANGKAT`. Akhir: diganti. `HonestyCard` ada di `result_page.dart`, `trend_page.dart`, `help_page.dart` |
| H6 | Peringatan pengukuran per frame sampai ke pengguna | FAIL | PASS | Awal: `MODEL_MISFIT`, `PARAMETER_AT_BOUND`, `WIDTH_BEYOND_VALIDATED`, `FEW_PSF_EDGES` hanya di JSON. Akhir: `frame_warnings` di agregat, tampil per jumlah foto (D49; `screens_test.dart`, `strings_test.dart`) |

### 2.6 Android

| ID | Butir | Awal | Akhir | Bukti |
|---|---|---|---|---|
| G1 | Izin hanya CAMERA | PASS | PASS | `AndroidManifest.xml` utama; `app/test/android_manifest_test.dart`; APK rilis: bagian 1 |
| G2 | Tanpa INTERNET di rilis | PASS | PASS | INTERNET hanya di manifest debug dan profile; APK rilis: bagian 1 |
| G3 | Foto di penyimpanan privat dan tidak ikut cadangan | FAIL | PASS | `getApplicationSupportDirectory` (`main.dart`). Awal: `allowBackup` tidak dinyatakan (bawaan true: basis data dan foto ke Cadangan Google). Akhir: `allowBackup="false"` dan `data_extraction_rules.xml` (D51, tes manifest) |
| G4 | Pembuangan kamera dan `Mat` | PASS | PASS | `ResourceScope` untuk semua `Mat` (`opencv_*.dart`), `device_camera_service_test.dart` ("dispose releases once"), `resource_scope_test.dart`; kebocoran terukur di perangkat: PERANGKAT (B2.2) |
| G5 | Kerja berat di isolate | PASS | PASS | `frame_processor.dart:114`, `point_locator.dart:25`, `detection_worker.dart:99`; analisis pose live ringan di isolate UI (D40) |
| G6 | Pause/resume | PASS | PASS | `capture_controller.dart:330`; tes lifecycle dengan driver tiruan (`capture_controller_test.dart`, `device_camera_service_test.dart`); perilaku nyata: PERANGKAT |
| G7 | Memori citra 12 MP | PASS | PASS | Hanya patch kecil dari foto (`frame_pipeline_test.dart` "memory: no whole-frame patches"); `Mat` abu-abu 12 MB per foto dalam isolate; pengukuran RSS: PERANGKAT (B2.2) |
| G8 | Tanpa log sensitif | PASS | PASS | grep `print(`, `debugPrint`, `developer.log`, `Log.`, `println` di `app/lib`, `packages/*/lib`, Kotlin: nol kecocokan |
| G9 | Penyambungan OpenCV ke APK | FAIL | PASS | Awal: `app/` tidak bergantung pada `hairline_opencv`; APK tidak dapat mendeteksi penanda (TODO di `main.dart`). Akhir: `main_device.dart` + `tools/build_device_apk.sh` (D48), build arm64 pada bagian 1. Perilaku di kamera nyata: PERANGKAT (B2.1) |

### 2.7 Data

| ID | Butir | Awal | Akhir | Bukti |
|---|---|---|---|---|
| D1 | Migrasi Drift | PASS | PASS | `database.dart`: skema 1 (belum ada rilis sebelumnya), `onUpgrade` gagal keras, basis data lebih baru ditolak, FK aktif; `database_test.dart` grup migration |
| D2 | Integritas kunjungan atomik | PASS | PASS | `repository.dart:193` satu transaksi; `visit_processor_test.dart` "a failing transaction removes the files" |
| D3 | Pemrosesan ulang tidak menimpa | PASS | PASS | `visit_processor_test.dart` "reprocessing a stored visit adds rows under the new version, keeps every old row" |
| D4 | Penghapusan frame, maks 5 | PASS | PASS | "only 5 frames are kept"; `frame_storage_test.dart`; `sweepOrphanFrames` saat start |
| D5 | Impor CSV berbahaya ditolak | FAIL | PASS | Perilaku sudah benar (regex angka ketat), tetapi NaN, Infinity, heksadesimal, dan rumus lembar kerja tanpa tes. Ditambah 5 tes penjaga di `plate_test.dart` |

### 2.8 Aksesibilitas, UX, proses

| ID | Butir | Awal | Akhir | Bukti |
|---|---|---|---|---|
| U1 | Kontras WCAG AA | PASS | PASS | `app/test/theme_test.dart` (semua pasangan status >= 4,5:1) |
| U2 | Font besar | PASS | PASS | `screens_test.dart:407` semua layar pada skala teks 2 tanpa overflow, dengan semantik |
| U3 | State kosong dan galat | PASS | PASS | `strings.dart:114,128` (situs, retak kosong); galat spesifik Indonesia (alasan penolakan, CSV, izin kamera) |
| U4 | Bahasa Indonesia konsisten, tanpa string di widget | PASS | PASS | `strings_test.dart` memindai literal di luar katalog |
| U5 | `make verify` sesuai kontrak CLAUDE.md aturan 5 | FAIL | PASS | `Makefile`: `build_runner` tanpa `--delete-conflicting-outputs`; diperbaiki, plus target `audit-docs`, `audit-numeric`, `apk-device` |

## 3. Ringkasan

| | PASS | FAIL |
|---|---|---|
| Awal (sebelum Fase 9) | 54 | 11 |
| Akhir | 65 | 0 |

Total 65 butir. Sebelas FAIL awal: N8 (klaim galat `k`), N9 (segmen overlay dikalikan skala cetak dua kali), V2 (lembar bergeser tanpa peringatan), V4 (id penanda ganda dipercaya diam-diam), H1 (kata keselamatan di dokumen teknis), H5 (label README tidak sesuai kontrak), H6 (peringatan frame tak tampil), G3 (cadangan data Android aktif), G9 (APK tanpa detektor), D5 (impor CSV tanpa tes untuk masukan berbahaya), U5 (`make verify` menyimpang dari kontrak). Semua diperbaiki dengan tes penjaga (D48 sampai D53).

"PASS" pada butir yang menyebut PERANGKAT berarti bagian yang dapat dibuktikan di host sudah dibuktikan; bagian yang butuh ponsel nyata TIDAK dinyatakan lulus dan tercatat di BLOCKERS B2 (sembilan kelompok): detektor `opencv_dart` dan tes adapter, kunci fokus dan eksposur, orientasi CameraX dan overlay, kanal Kotlin, cetak nyata, validasi pelat `PERANGKAT` (satu-satunya sumber akurasi nyata), ambang yang belum dituning, TalkBack, R8 dan penandatanganan, uji kunjungan dua minggu.

## 4. Batas audit ini

- Risiko ISP: penajaman unsharp pada penanda dan retak membiaskan lebar rendah sampai -20 um (retak 0,3 mm, SINTETIS) dan baru ditandai `MODEL_MISFIT` bila kuat; tercatat sebagai KNOWN LIMIT dengan tes (MEASUREMENT_NOTES bagian 8). Tidak mengubah hitungan PASS/FAIL di atas karena bukan cacat implementasi.

- Semua pemeriksaan dijalankan di host macOS arm64 tanpa ponsel. Tidak ada angka `PERANGKAT`. Butir B2 di BLOCKERS.md adalah daftar yang hanya dapat dijawab di perangkat nyata.
- Pembanding independen memakai asumsi model yang sama (profil Gaussian terkonvolusi kotak, titik di tengah piksel, tanpa JPEG nyata). Ia membuktikan implementasi core mengikuti spesifikasi dan bebas dari kesalahan aljabar atau satuan, bukan bahwa spesifikasi cocok dengan kamera nyata.
- Pemeriksaan numerik urutan sudut memakai OpenCV Python 5.0.0; `opencv_dart` 2.2.2 (OpenCV 4.13) dijalankan hanya lewat tes adapter di emulator arm64 (A8), belum di ponsel fisik.
