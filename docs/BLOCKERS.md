# BLOCKERS

## B1. Hook native opencv_dart tidak bisa dibangun di host macOS tanpa Xcode (Fase 1)
- Gejala: `flutter test` pada paket yang bergantung `opencv_dart` gagal di "Building native assets" untuk target macOS.
- Percobaan 1: generator default (Xcode): `CMake Error: Xcode 1.5 not supported` / `Could not create named generator Xcode`.
- Percobaan 2: `macos.generator: Ninja`: `ios.toolchain.cmake:668 get_filename_component called with incorrect number of arguments`, lalu `CMAKE_MAKE_PROGRAM is not set`.
- Percobaan 3: `macos.generator: Unix Makefiles`: `CMake Error: Error: generator : Unix Makefiles`.
- Akar masalah: toolchain macOS milik `native_toolchain_cmake` memerlukan `xcodebuild` (hanya ada di Xcode penuh; `xcode-select -p` menunjuk Command Line Tools).
- Opsi: (1) pasang Xcode penuh lalu jalankan spike di host; (2) jalankan di Linux/CI (belum dicoba, Docker daemon tidak aktif di mesin ini); (3) uji di perangkat Android.
- Dampak: tes `tools/opencv_spike` berstatus "ditulis, belum dijalankan" sebagai tes Dart. Perilaku runtime opencv_dart belum terbukti; hanya referensi Python (`tools/opencv_spike_ref.py`) yang dijalankan. Mitigasi keputusan D1: app tidak bergantung opencv_dart sampai Fase 5.
