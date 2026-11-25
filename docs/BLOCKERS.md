# BLOCKERS

## B1. Hook native opencv_dart tidak bisa dibangun di host macOS tanpa Xcode (Fase 1)
- Gejala: `flutter test` pada paket yang bergantung `opencv_dart` gagal di "Building native assets" untuk target macOS.
- Percobaan 1: generator default (Xcode): `CMake Error: Xcode 1.5 not supported` / `Could not create named generator Xcode`.
- Percobaan 2: `macos.generator: Ninja`: `ios.toolchain.cmake:668 get_filename_component called with incorrect number of arguments`, lalu `CMAKE_MAKE_PROGRAM is not set`.
- Percobaan 3: `macos.generator: Unix Makefiles`: `CMake Error: Error: generator : Unix Makefiles`.
- Akar masalah: toolchain macOS milik `native_toolchain_cmake` memerlukan `xcodebuild` (hanya ada di Xcode penuh; `xcode-select -p` menunjuk Command Line Tools).
- Opsi: (1) pasang Xcode penuh lalu jalankan spike di host; (2) jalankan di Linux/CI (belum dicoba, Docker daemon tidak aktif di mesin ini); (3) uji di perangkat Android.
- Dampak: tes `tools/opencv_spike` berstatus "ditulis, belum dijalankan" sebagai tes Dart. Perilaku runtime opencv_dart belum terbukti; hanya referensi Python (`tools/opencv_spike_ref.py`) yang dijalankan. Mitigasi keputusan D1: app tidak bergantung opencv_dart sampai Fase 5.

### Pembaruan B1 (Fase 5, 2026-11-17)
- `cd packages/hairline_opencv && flutter test` dicoba lagi: "Building native assets failed" (sama seperti B1; Xcode penuh tetap tidak ada, `xcodebuild` menolak dengan Command Line Tools).
- Dampak Fase 5: tes adapter (`packages/hairline_opencv/test/opencv_adapters_test.dart`: ID dan urutan sudut pada rotasi 0/90/180/270 dan perspektif, id di luar lembar, tanpa penanda, dekode, ROI, dispose idempotent, kebocoran RSS pada 30 putaran 12 MP) berstatus **ditulis, belum dijalankan**. `flutter analyze` paket itu bersih. Toleransi (0,8 px sudut, 150 MB RSS) adalah penalaran, bukan hasil ukur.
- `app/` belum bergantung pada `hairline_opencv` (D34), sehingga APK dari repo ini belum dapat mendeteksi penanda sampai dependensi disambungkan.
- Opsi: (1) pasang Xcode penuh lalu `make opencv-test`; (2) job CI `opencv` (Linux, `continue-on-error`) mungkin sudah cukup, belum dilihat hijau; (3) perangkat Android.

### Pembaruan B1 (Fase 6, 2026-11-25)
- `OpenCvGrayMarkerDetector` (deteksi live dari buffer abu-abu) dan tesnya (`packages/hairline_opencv/test/opencv_adapters_test.dart`, tes baru "the live detector ...") ditulis, `flutter analyze` bersih, BELUM dijalankan: akar masalah sama (build native OpenCV tidak jalan di host tanpa Xcode penuh).
- Dampak Fase 6: tanpa dependensi `hairline_opencv` di `app/`, layar pengambilan nyata tidak dapat mendeteksi penanda (menampilkan "Detektor penanda belum tersedia"). Alur ujung ke ujung terbukti hanya dengan `FakeCameraService` dan penanda tertanam (SINTETIS). Menyambungkan: dependensi di `app/pubspec.yaml`, dua override di `main.dart` (`openCvPorts`, `openCvGrayDetector`), lalu DEVICE_TEST.

### Pembaruan B1 (Fase 9, 2026-11-25)
- Akar masalah tidak berubah: host ini hanya punya Command Line Tools, tidak ada Xcode penuh. `dartcv4` mengompilasi OpenCV dari sumber pada setiap build target (host untuk `flutter test`, Android untuk APK).
- Penyambungan ke aplikasi diselesaikan tanpa menunggu Xcode (DECISIONS D48): `lib/main_device.dart` + `tools/build_device_apk.sh` (`make apk-device`) membangun APK perangkat dengan `hairline_opencv` dan hook `dartcv4`; `app/` yang tercatat di git tetap tanpa dependensi itu sehingga `make verify` dan CI app tetap berjalan. Hasil build arm64 dicatat di PROGRESS.
- DIPERBARUI setelahnya (2026-11-25, D54): ke-13 tes `packages/hairline_opencv/test/opencv_adapters_test.dart` DIJALANKAN dan LULUS pada `opencv_dart` 2.2.2 asli di emulator Android arm64 (API 29) lewat `tools/opencv_device_test.sh`: urutan sudut pada rotasi 0, 90, 180, 270 dan perspektif, id unik dan di luar lembar, tanpa penanda, detektor live dari buffer abu-abu, dekode, ROI, dispose idempoten, dan uji kebocoran RSS 12 MP. Host macOS tanpa Xcode tetap tidak dapat menjalankannya.
- Yang tetap TIDAK terbukti: tes yang sama pada ponsel fisik (emulator memakai CPU Apple, bukan SoC ponsel), job CI `opencv` Linux (belum dilihat hijau), dan deteksi pada stream kamera nyata. Pengganti parsial: detektor ArUco OpenCV Python (5.0.0, perilaku referensi, BUKAN `opencv_dart`) pada rotasi 0, 90, 180, 270, 45 dan 200 derajat menghasilkan urutan sudut yang cocok dengan core (`make audit-numeric`, docs/AUDIT.md).

## B2. Butir yang hanya dapat dibuktikan di perangkat nyata (Fase 9, 2026-11-25)
Semua butir ini ditulis, diuji di host dengan data sintetis atau pengganti, dan diberi status `SELESAI-PERLU-UJI-PERANGKAT`. Alasan setiap butir: agent tidak punya ponsel, kamera, printer, pemindai, atau lembar cetak. Langkah uji ada di docs/DEVICE_TEST.md.
1. Deteksi penanda `opencv_dart` pada foto cetak dan stream kamera nyata: tes adapter sudah lulus di emulator arm64 (D54) tetapi dengan gambar sintetis; ulangi di ponsel fisik (`make opencv-device-test`) lalu dengan foto lembar cetak.
2. Fokus dan eksposur terkunci benar-benar bertahan selama burst, orientasi bingkai CameraX (D41), penyelarasan overlay, kinerja stream, panas: butuh kamera nyata (DEVICE_TEST 2 sampai 6).
3. Kanal Kotlin `LensInfoChannel` dan kecocokan id kamera `camera` dengan `CameraManager`: hanya terkompilasi (DEVICE_TEST 5).
4. Cetak 100 persen dan skala nyata, deteksi foto cetak, bayangan ISP pada profil retak berkontras rendah (5.3a catatan): butuh printer dan ponsel (DEVICE_TEST 10).
5. Validasi pelat (`PERANGKAT`): bias, RMSE, cakupan, `u_dev` nyata dan lebar terkecil yang terukur andal: butuh pelat cetak, pemindai atau lup, ponsel (DEVICE_TEST 11). Tanpa ini setiap hasil tetap `BELUM_DIVALIDASI`.
6. Ambang awal yang belum dituning di perangkat: `QualityThresholds`, stabilitas live (5 frame, selisih antar frame), `maxTrackingOffsetMm` 0,5 mm, ambang validasi 16 garis, 4 lebar, cakupan 0,9.
7. TalkBack, huruf besar sistem, kontras di layar nyata dan di bawah matahari (DEVICE_TEST 10).
8. Perilaku R8 pada APK rilis di perangkat, penandatanganan dengan kunci pemilik (DEVICE_TEST 12).
9. Uji kunjungan nyata dua minggu: konsistensi pose kunjungan ulang, ketahanan lembar tempel, tren pada retak nyata (DEVICE_TEST 14).
