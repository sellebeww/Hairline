# SPIKE opencv_dart (Fase 1)

Tanggal 2026-11-17. Host: macOS 14.8.9 arm64 (bukan Linux), Flutter 3.47.5 / Dart 3.13.4, NDK 28.2.13676358. Semua angka di bawah berasal dari perintah yang dijalankan; yang tidak bisa dijalankan ditandai.

## Ringkasan jawaban

| Pertanyaan | Jawaban | Status bukti |
|---|---|---|
| API ArUco ada di opencv_dart? | YA, di modul contrib `aruco` (paket `dartcv4` 2.2.2, OpenCV 4.13.0) | terbukti: kode sumber dibaca, `flutter analyze` bersih pada spike, library native berhasil dibangun dan masuk APK |
| Bisa jalan sebagai tes di host? | TIDAK di host ini (macOS tanpa Xcode). Linux/CI belum dicoba. Perangkat belum dicoba | terbukti gagal 3 kali, lihat BLOCKERS B1 |
| Ukuran APK | +13,5 MB (arm64-v8a saja, release) | terukur |
| Perilaku runtime (deteksi, sub-pixel, JPEG, ROI) | Tes Dart ditulis, BELUM dijalankan. Referensi independen Python dijalankan | lihat bawah |

## API yang benar (opencv_dart 2.2.2, `import 'package:opencv_dart/opencv_dart.dart' as cv;`)

- Generate: `cv.arucoGenerateImageMarker(cv.PredefinedDictionaryType.DICT_4X4_50, id, sidePixels, borderBits)` mengembalikan `cv.Mat` (CV_8UC1). `borderBits=1`: `sidePixels` sudah termasuk border hitam.
- Detektor: `cv.ArucoDetector.create(cv.ArucoDictionary.predefined(cv.PredefinedDictionaryType.DICT_4X4_50), params)` lalu `final (corners, ids, rejected) = det.detectMarkers(mat)` bertipe `(VecVecPoint2f, VecI32, VecVecPoint2f)`.
- Parameter: `cv.ArucoDetectorParameters.empty()` dengan `cornerRefinementMethod` bertipe `int` (TIDAK ada konstanta bernama `CORNER_REFINE_*` di Dart; pakai angka OpenCV: 0 NONE, 1 SUBPIX, 2 CONTOUR, 3 APRILTAG), juga `cornerRefinementWinSize`, `cornerRefinementMaxIterations`, `cornerRefinementMinAccuracy`.
- JPEG: `cv.imdecode(Uint8List, cv.IMREAD_GRAYSCALE)`, `cv.imencode('.jpg', mat)` mengembalikan `(bool, Uint8List)`.
- ROI: `mat.region(cv.Rect(x, y, w, h))` (tampilan tanpa salin), `.clone().data` memberi `Uint8List`.
- Pembuangan memori: `Mat`, `Vec*`, detektor dan parameter punya `dispose()`; semua dipanggil di spike.
- Urutan sudut dari referensi: tiap penanda 4 titik TL,TR,BR,BL (sesuai D2); urutan penanda dalam daftar BUKAN urut id (terlihat pada referensi: penanda pertama yang dikembalikan adalah id 2), jadi adapter harus memetakan lewat `ids`.

## Konfigurasi wajib

- Modul contrib tidak dibangun default. Tambahkan pada `pubspec.yaml` aplikasi:
  `hooks.user_defines.dartcv4.include_modules: [imgproc, imgcodecs, calib3d, objdetect, aruco]` (D10). Dengan `aruco` saja build Android gagal di tahap link.
- Native OpenCV DIKOMPILASI DARI SUMBER lewat CMake + Ninja pada build pertama (bukan biner prebuilt, bertentangan dengan tabel README paket). Build arm64 Android: sekitar 4 menit untuk build kedua yang sudah menyalin sumber, 5m09 untuk baseline tanpa opencv (kompilasi plugin lain dan Gradle dingin). Perlu cmake dan ninja terpasang. Satu unduhan opsional (KLEIDICV, SSL error) hanya memberi peringatan.
- Pada macOS tanpa Xcode penuh build host gagal (B1).

## Ukuran APK (release, `--target-platform android-arm64`, 5 modul)

| Varian | APK | Catatan |
|---|---|---|
| Baseline app (riverpod, go_router, drift, camera, pdf, printing) | 18.832.741 B (18,8 MB) | `libflutter.so` 11,7 MB, `libapp.so` 4,1 MB, `libsqlite3.so` 1,7 MB |
| + opencv_dart (kode spike di `main`) | 32.318.381 B (32,3 MB) | tambah `libdartcv.so` 13.413.680 B |
| Selisih | +13.485.640 B (+13,5 MB) | hanya arm64-v8a. ABI lain belum diukur; split per-ABI menjaga tiap APK mendekati angka ini |

`libsqlite3.so` hadir tanpa `sqlite3_flutter_libs`, mendukung D6.

## Referensi independen (Python 3.15, opencv-contrib-python-headless 5.0.0, `tools/opencv_spike_ref.py`)

Adegan 800x800 putih, 4 penanda 120 px (id 0..3) pada (100,100),(580,100),(580,580),(100,580). Seed tidak relevan (tanpa acak).
- Tanpa refinement: 4 penanda terdeteksi, galat maks 1,0 px terhadap tepi piksel bulat.
- `CORNER_REFINE_SUBPIX`: 4 penanda, sudut jatuh pada tepi minus 0,44 (mis. 579,558 untuk tepi 580), yaitu pusat-piksel minus 0,5 dengan sisa sekitar 0,06 px (dasar D3).
- Setelah JPEG (13.634 B) lalu dekode abu-abu: 4 penanda tetap, galat maks 0,558 px (tak berubah berarti terhadap tepi bulat).
- ROI 64x48 dari adegan: min intensitas 255 (area putih), ukuran benar.
Ini membuktikan perilaku OpenCV Python, BUKAN bukti bahwa opencv_dart menghasilkan angka yang sama.

## Tes Dart (`tools/opencv_spike/test/opencv_spike_test.dart`)

Status: ditulis, `flutter analyze` bersih, BELUM dijalankan (B1). Mereplika adegan di atas dan menegaskan 4 penanda terdeteksi, galat kuadrat sudut sub-pixel < 1,0 px^2 terhadap (tepi - 0,5), dekode JPEG ke 1 kanal, dan patch ROI Float32 64x48 dengan minimum > 0,95. Jalankan di CI Linux atau setelah Xcode dipasang: `cd tools/opencv_spike && flutter test`.

## Implikasi untuk Fase 5

1. Adapter memakai tepat API di atas; antarmuka ke core hanya `GrayPatch` dan daftar `(id, 4 sudut)` (D2, D4).
2. Pertama di Fase 5: jalankan tes spike di Linux/perangkat; bila galat berbeda dari referensi Python, catat di DECISIONS.
3. Jangan tambah modul OpenCV tanpa catatan; ukuran APK sensitif (+13,5 MB).
4. Alternatif bila ArUco opencv_dart gagal di perangkat: D11 (tidak diimplementasikan).
