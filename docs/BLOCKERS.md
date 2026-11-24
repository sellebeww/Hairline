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
