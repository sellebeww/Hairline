# BACKLOG

Ide di luar scope Wajib. Satu baris per ide, tidak dikerjakan.

- Hapus ketergantungan `dart pub outdated` manual: pertimbangkan Dependabot untuk pub (2026-11-17).
- Evaluasi `opencv_dart` 2.3.x (tersedia, lebih baru dari 2.2.2) sebelum Fase 5 (2026-11-17).
- Layar debug dengan penghitung deteksi (fps nyata, `FrameThrottle.admitted/droppedBusy`, waktu deteksi) untuk mengisi DEVICE_TEST bagian 6 tanpa log sementara (2026-11-25).
- Memisahkan resolusi stream analisis dari resolusi foto diam bila `ResolutionPreset.max` terlalu berat (butuh CameraX langsung lewat platform channel; mengubah keputusan terkunci "paket camera") (2026-11-25).
- Pemilihan lensa fisik pada ponsel multi-lensa (saat ini lensa belakang pertama dari `availableCameras()`) (2026-11-25).
- Jalur berkas untuk burst bila foto 12 MP dalam memori (6 x sekitar 5 MB) menjadi masalah di ponsel murah (2026-11-25).
- Proses ulang foto dasar sekali saja (hemat satu putaran pemrosesan di kunjungan dasar, D43) (2026-11-25).
- Tampilan lup (zoom otomatis) pada segmen 4 mm di layar titik ukur (2026-11-25).
