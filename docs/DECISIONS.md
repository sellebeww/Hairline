# DECISIONS

Format: tanggal, masalah, keputusan, alasan. Semua tanggal 2026-11-17 (Fase 1).

## D1. Host pengembangan bukan Linux, dan tes opencv_dart tidak bisa jalan di host ini
- Masalah: CLAUDE.md menyebut host Linux, tetapi lingkungan ini macOS arm64 tanpa Xcode penuh (hanya Command Line Tools). Hook native `dartcv4` mengompilasi OpenCV dari sumber lewat CMake dan memakai toolchain iOS/macOS yang memanggil `xcodebuild`. Tiga generator dicoba (default Xcode, Ninja, Unix Makefiles) dan semuanya gagal (lihat BLOCKERS B1). Efek samping: selama `opencv_dart` ada di dependensi `app/`, `flutter test` apa pun gagal di mesin ini.
- Keputusan: `opencv_dart` TIDAK dideklarasikan di `app/pubspec.yaml` sampai Fase 5. Spike hidup di `tools/opencv_spike/` (paket terpisah). Tes adapter OpenCV di Fase 5 dijalankan di CI Linux (generator Unix Makefiles, belum terbukti) atau di perangkat. Seluruh tes `hairline_core` tidak menyentuh OpenCV sehingga tetap jalan di host mana pun.
- Alasan: `make verify` harus bersih di mesin ini, dan DoD melarang dependensi tak terpakai.

## D2. Urutan sudut penanda
- Keputusan: korespondensi sudut selalu urutan OpenCV pada bingkai penanda itu sendiri (TL, TR, BR, BL), persis seperti 5.1. Detektor ArUco mengembalikan sudut dalam urutan ini berapa pun rotasi lembar atau ponsel, karena orientasi dikodekan oleh bit penanda. Core tidak memutar atau mengurutkan ulang sudut. Penanda dengan id di luar `4s..4s+3` diabaikan, lembar campuran ditolak.
- Alasan: menghindari ambiguitas rotasi 90 derajat; terbukti pada spike referensi Python (sudut keluar dalam urutan TL,TR,BR,BL untuk penanda tegak).

## D3. Konvensi koordinat piksel
- Masalah: apakah sudut `(x,y)` berarti tepi piksel atau pusat piksel.
- Keputusan: pusat piksel `k` ada di koordinat `k` (konvensi OpenCV). Tepi kiri piksel 100 berada di 99,5. Core memakai konvensi yang sama untuk `GrayPatch`, `H`, dan interpolasi.
- Alasan: terukur pada spike (docs/SPIKE_OPENCV.md): sudut deteksi sub-pixel jatuh pada tepi minus 0,5 dengan selisih sekitar 0,06 px.

## D4. Representasi GrayPatch
- Keputusan: `GrayPatch(originX:int, originY:int, width:int, height:int, data:Float32List)`, baris demi baris, nilai ternormalisasi 0..1 (`byte/255`), piksel `(i,j)` berpusat pada citra `(originX+i, originY+j)`. Adapter menjamin patch mencakup margin interpolasi bikubik (>= 2 px) di sekitar ROI. Core tidak mengenal Mat atau JPEG.
- Alasan: `Float32List` sesuai CLAUDE.md 5.3; skala 0..1 membuat konstanta derau dan jenuh tak bergantung kedalaman bit.

## D5. Format JSON homografi
- Keputusan: `{"v":1,"dir":"sheet_to_image","h":[h11,h12,h13,h21,h22,h23,h31,h32,h33],"image":{"w":int,"h":int}}`, urut baris, `h33 = 1`, double penuh, satuan sheet mm. `H_inv` selalu dihitung ulang, tidak disimpan. Field `v` untuk migrasi.
- Alasan: cocok dengan kolom `frames.homography_json` (5.7), aman untuk pemrosesan ulang oleh `algorithm_version` baru.

## D6. sqlite3_flutter_libs tidak dipakai
- Masalah: CLAUDE.md meminta `sqlite3_flutter_libs`, tetapi versi terbaru `0.6.0+eol` ditandai end-of-life oleh pembuatnya (sqlite3 3.x membundel SQLite lewat build hook).
- Keputusan: tidak ditambahkan. `drift ^2.35.4` dengan `sqlite3 3.5.2` (transitif). Pembuktian akses DB nyata di Fase 2; bila ternyata butuh paket lain, catat di sini.
- Alasan: paket EOL tidak boleh jadi dasar baru.

## D7. custom_lint dan riverpod_lint dilewati
- Keputusan: hanya lint resmi (`flutter_lints`). `riverpod_lint` + `custom_lint` tidak dapat di-resolve bersama `riverpod_annotation ^4` (version solving gagal di `analyzer`/`macros`).
- Alasan: bukan bagian daftar wajib; `riverpod_generator` sendiri sudah berfungsi.

## D8. Dependensi yang dideklarasikan tetapi belum dipakai di Fase 1
- Keputusan: `drift`, `camera`, `pdf`, `printing`, `drift_dev` tetap dideklarasikan, karena langkah 3 meminta versi diverifikasi bersama (satu `pub get` bersih, build APK sukses). Tidak ada paket lain di luar daftar; `path_provider`, `path`, `cupertino_icons`, `sqlite3_flutter_libs`, `custom_lint`, `riverpod_lint` dibuang. Ini penyimpangan sadar dari DoD "tanpa dependensi tak terpakai", dibatasi ke daftar CLAUDE.md.
- Versi terpasang (dari pub.dev, 2026-11-17): flutter_riverpod 3.5.0, riverpod_annotation 4.0.8, riverpod_generator 4.0.10, go_router 18.1.4, drift 2.35.4, drift_dev 2.35.3, camera 0.12.2, pdf 3.13.1, printing 5.15.1, build_runner 2.17.1, flutter_lints 6.0.0, opencv_dart 2.2.2 (OpenCV 4.13.0, hanya di spike).

## D9. Perintah verifikasi
- Keputusan: `dart test --coverage=coverage` (bentuk tanpa nilai di CLAUDE.md tidak valid di Dart 3.13), `dart pub get` dan `flutter pub get` ditambahkan di Makefile agar bersih dari nol. `make verify` = `core-test` lalu `app-test`.

## D10. Modul OpenCV yang dikompilasi
- Keputusan: `include_modules: [imgproc, imgcodecs, calib3d, objdetect, aruco]` (menggantikan default, `core` selalu ada). `aruco` saja gagal link (`-lopencv_aruco`, `-lopencv_calib3d`, `-lopencv_objdetect` tidak ditemukan) karena di OpenCV 4.13 ArUco ada di objdetect yang membutuhkan calib3d. Terbukti dengan build APK arm64 sukses. Tambah modul hanya dengan catatan di sini.

## D11. Alternatif bila ArUco opencv_dart bermasalah (tidak diimplementasikan)
- API ArUco TERSEDIA di opencv_dart 2.2.2 (modul `aruco`), jadi alternatif tidak dipakai. Cadangan bila di Fase 5 gagal di perangkat: (a) jembatan Kotlin ke OpenCV Android (`org.opencv:opencv` dari Maven): biaya tinggi (kode platform channel, serialisasi gambar), risiko duplikasi dua stack OpenCV; (b) detektor ArUco Dart murni sendiri: biaya sangat tinggi dan risiko akurasi sub-pixel. Keduanya tidak dikerjakan.

## D12. Git dan identitas
- Keputusan: branch `main`, author dari konfigurasi git lokal (Vassel Goleyu). Tanpa atribusi agent.

## D13. build_runner tanpa --delete-conflicting-outputs
- build_runner 2.17 menghapus flag itu ("removed and ignored", hanya peringatan). Makefile dan CI memakai `dart run build_runner build` tanpa flag. Penanganan hasil generasi: lihat D14.

## D14. Berkas hasil generasi
- Keputusan: `*.g.dart` tidak di-commit (ditambahkan ke `.gitignore`); `make verify` dan CI selalu menjalankan build_runner sebelum analyze. Alasan: mencegah drift antara sumber dan hasil generasi.

## D15. Fase 2: konvensi geometri dan masukan (2026-11-17)
- Konvensi piksel: piksel (i,j) berpusat pada (i,j) (sesuai D4); pusat citra `((w-1)/2, (h-1)/2)`. Renderer sintetis memakai konvensi yang sama.
- Deteksi: id penanda di luar empat id lembar diabaikan (tidak dihitung); id ganda, sudut bukan 4, atau koordinat tak hingga memunculkan `InvalidDetectionException`; < 3 penanda valid memunculkan `TooFewMarkersException`.
- Degenerate (`DegenerateConfigurationException`): titik segaris (rasio nilai eigen kovarians < 1e-6, yaitu sebaran melintang < 0,1 persen sebaran sepanjang garis), titik berimpit, rank DLT kurang, kedalaman tak konsisten, titik di garis tak hingga, dan penugasan tercermin (`det H < 0`, mis. urutan sudut terbalik). Alasan penambahan cermin: tanpa itu urutan sudut salah diterima diam-diam.
- `rms_px` = akar rata-rata kuadrat jarak Euklides reproyeksi semua titik. `loo_mm` = RMS jarak Euklides 16 sudut (4 putaran x 4 sudut) dalam mm di lembar. Skala lokal: `mm_per_px` = rata-rata geometrik dua nilai singular Jacobian `H_inv` (`sqrt|det J|`), anisotropi = rasio nilai singular terbesar/terkecil; Jacobian beda-pusat langkah 0,5 px, di titik ukur (default pusat jendela).
- `f_px` dari metadata = `focal_mm / sensor_sisi_panjang_mm * sisi_terpanjang_px` (independen potret/lanskap); metadata tak valid jatuh ke `0,75 x sisi_terpanjang`. `tilt_is_approx` selalu `true` (intrinsik tak pernah dikalibrasi).

## D16. Fase 2: panduan pose dan gerbang kualitas
- Instruksi dinyatakan sebagai tindakan pada ponsel: lembar tampak di kanan referensi -> `MOVE_RIGHT`; lembar lebih besar (ponsel terlalu dekat) -> `FARTHER`; lembar berputar searah jarum jam -> `ROTATE_CW`. Hanya sumbu translasi dominan yang dilaporkan sekali waktu. Urutan prioritas: `HOLD_FLAT`, skala, rotasi, translasi. Nilai tepat pada ambang masih "siap".
- "Selisih tilt" = `|tilt_sekarang - tilt_referensi|` (skalar), sesuai 5.2 secara harfiah. Akibatnya arah kemiringan tidak dibedakan.
- Tilt 20 sampai 30 derajat: ditolak (`TILT_TOO_HIGH`); > 30: `TILT_HARD_REJECT`. Keduanya menolak frame; bedanya hanya pesan UI. Dua faktor tambahan: `mm_per_px` 0,10 sampai 0,20 diterima dengan peringatan, 3 penanda diterima dengan peringatan.
- `QualityThresholds` juga memuat ambang berbasis citra (`maxSigmaPx`, `maxBlurAnisotropy`, `maxSaturatedFraction`) untuk dipakai fase berikutnya; evaluasi geometri tidak memakainya.

## D17. Fase 2: sensitivitas tilt terhadap `f_px` (SINTETIS, terukur, seed tetap)
- Tanpa derau, rata-rata atas 12 azimut, roll 15 derajat, tilt benar -> estimasi pada `f x0,8` / `f x1,2` (galat maks): 0 -> 0,00 / 0,00; 10 -> 8,03 / 11,95 (1,97); 20 -> 16,23 / 23,59 (3,77); 30 -> 24,79 / 34,72 (5,21) derajat.
- Kesimpulan: galat `f_px` 20 persen menggeser tilt sekitar 0,2 x tilt (f terlalu kecil menaksir rendah, terlalu besar menaksir tinggi). Dengan `f_px` tepat dan derau sudut 0,2 px, galat tilt hanya 0,012 sampai 0,019 derajat RMS: galat `f_px` mendominasi. Akibat untuk gerbang: frame 20 derajat sebenarnya dapat terbaca 16 sampai 24 derajat, jadi ambang tilt 20/30 derajat tidak tegas sampai `f_px` divalidasi (butuh pelat/ponsel nyata). `u_par` (5.5) memakai tilt ini, sehingga ketidakpastiannya ikut meleset.

## D18. Fase 2: harness sintetis dan alat ukur
- Harness ada di `package:hairline_core/synthetic.dart` (tidak diekspor oleh `hairline_core.dart`). Renderer: sampel sub-piksel SxS, PSF Gaussian pada resolusi sub-piksel (tepi direplikasi), integrasi kotak per piksel, gradien iluminasi perkalian, derau Gaussian, klip, kuantisasi 8 bit. Penanda dirender sebagai persegi padat (pola bit tidak diperlukan untuk uji tepi dan PSF). Retak = himpunan titik berjarak <= w/2 dari garis tengah (busur lingkaran bila melengkung), sehingga lebar tepat di sepanjang retak.
- Validasi renderer: integral kegelapan tegak lurus retak sama dengan `kedalaman x lebar` untuk PSF apa pun; galat kuadratur tiap tepi <= 0,5/S px, jadi batas uji `1/S` px (S=8, dan S=4 bila PSF aktif).
- Dependensi dev `coverage ^1.16.0` ditambahkan hanya untuk mengukur cakupan (`dart run coverage:format_coverage`); tidak masuk kode produksi.
- Tata letak lembar untuk Fase 3 yang dipilih di sini: batang skala berpusat y = 90 mm (di bawah tepi bawah penanda pada y = 75 mm). Rentang pembacaan penggaris yang diterima 80 sampai 120 mm (di luar itu `PrintScaleException`: biasanya salah satuan atau salah ukur).
- Pembangkit kamera acak: `f` 0,7..0,9 sisi panjang, 0,09..0,15 mm/px di pusat, tilt 0..25 derajat, roll +-20, offset pusat lembar +-10 mm. Rentang ini dipilih agar seluruh bingkai 150 mm selalu berada di dalam citra 4000x3000 (diuji pada 200 kamera).
