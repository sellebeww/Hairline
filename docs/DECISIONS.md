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

## D19. Fase 3: konvensi pengukuran (2026-11-17)
- Pengambilan sampel memakai `H` (lembar ke citra), bukan `H_inv`: untuk mengambil intensitas pada posisi metrik harus dipetakan mm ke piksel. `H_inv` hanya dibutuhkan untuk skala (`localMmPerPx` memakai Jacobian `H`, hasilnya sama dengan `LocalScale.mmPerPx`). Permintaan fase menyebut `H_inv`; ini penyimpangan sadar.
- Sampler Catmull-Rom: bila dukungan 4x4 tidak seluruhnya di dalam patch hasilnya NaN (tanpa klem atau ekstrapolasi); profil yang keluar patch menjadi `null`, lalu ditolak dengan alasan `PATCH_TOO_SMALL`. Patch minimal kira-kira +-8 mm di sekitar titik ukur; untuk PSF patch harus mencakup tepi luar penanda (praktis seluruh bingkai 150 mm).
- Arah retak dalam derajat dari sumbu x lembar (y ke bawah), normal `n = (-sin a, cos a)`, sama dengan `crackScene`.
- Parameter model `[B, m, D, c, w]`; batas `D in [0, baseline]` (retak tidak bisa lebih gelap dari nol), `w in [0, 3 mm]`, `c in +-1,5 mm`. Lebar > 3 mm di luar rancangan (rentang profil +-3 mm): ditandai `PARAMETER_AT_BOUND`.

## D20. Fase 3: sigma PSF adalah kernel semu, dan isotropik di ruang piksel
- Sigma dari tepi penanda mencakup apertur piksel (varians 1/12 px^2) sehingga untuk PSF Gaussian sigma_g nilainya sekitar `sqrt(sigma_g^2 + 1/12)`. Itu benar untuk model retak karena retak melihat kernel yang sama; uji PSF membandingkan dengan nilai itu, bukan dengan sigma_g.
- Blur citra isotropik di ruang piksel, bukan di ruang lembar. Di bawah tilt, sigma dalam mm berbeda menurut arah (hingga 1/cos tilt). Karena itu tiap tepi diubah ke piksel dengan mm/px searah normal tepi; median dan rasio anisotropi dihitung dalam piksel, dan sigma untuk retak = `sigma_px x mm/px sepanjang normal retak` (`PsfEstimate.sigmaMmAlong`). Median sigma dalam mm (definisi 5.3a) tetap dilaporkan (`sigmaMm`). Tanpa ini tilt 25 derajat memberi rasio anisotropi palsu.
- `u_sigma_edge` = simpangan baku sampel sigma antar tepi (px), sesuai 5.3a. Ini mengukur ketelitian, bukan keakuratan (lihat D24).
- Batas yang diketahui: dengan dua keluarga tepi (normal sumbu x dan y lembar), blur gerak pada 45 derajat terhadap tepi tidak terdeteksi (rasio ~1). Diuji dan dicatat. Sigma yang membesar tetap tertangkap oleh gerbang `maxSigmaPx`.

## D21. Fase 3: gerbang kontras
- 5.3 menyebut `D / sigma_noise >= 3`. Untuk retak lebih sempit dari sigma, `D` dan `w` kolinear (hanya luas `D*w` teridentifikasi), jadi `D` sendiri menyesatkan (menempel pada batas atas dengan nilai besar). Gerbang memakai kedalaman lembah model, `D (2 Phi(w/2sigma) - 1)`, yang sama dengan `D` untuk retak lebar dan yang benar-benar dibatasi data untuk retak sempit.
- `sigma_noise = max(median RMS residu per profil, derau piksel patch)`. Residu per profil lebih kecil dari derau piksel karena interpolasi menghaluskan; derau patch (MAD dari `I - rata-rata 4 tetangga`, anggapan iid) memberi lantai. Anggapan iid dapat meremehkan derau nyata yang berkorelasi (dicatat).

## D22. Fase 3: dua lintasan, penjajaran dan kovarians
- Lintasan 2 menjajarkan profil pada kurva kuadrat robust yang dilewatkan pada pusat `c_j` per profil (default `alignWithSmoothedCenters`), bukan pada tiap `c_j` mentah. `c_j` mentah mengikuti derau per profil. Mode harfiah 5.3 tersedia lewat konfigurasi. Bukti SINTETIS (MEASUREMENT_NOTES 4.6): pada SNR rendah (derau 0,04, kedalaman 0,3) dan w 0,15 mm, sd galat 13,3 um (mentah) versus 7,0 um (kurva), rms 18,0 versus 13,1 um, dan mode mentah memunculkan `MODEL_MISFIT`; pada SNR tinggi keduanya identik (resolusi 0,1 um). Klaim awal bahwa mode mentah membiaskan lebar menjadi lebih sempit TIDAK terbukti; yang terbukti hanya varians lebih besar.
- Kovarians `rho * s2 (J^T J)^-1`, `rho = 1,0` TIDAK dikalibrasi (ditandai di hasil). Sapuan sintetis menunjukkan perlu `rho` sekitar 5 untuk retak lebar (galat sebenarnya sekitar 2,3 kali `u_fit`); kalibrasi resmi tetap di studi cakupan (butir 7).

## D23. Fase 3: pencarian punggung retak
- Komponen nn Hessian dihitung pada profil melintang yang dirata-ratakan sepanjang retak (kernel memanjang), dengan pencarian skala-ruang (turunan kedua Gaussian, skala `sigma_px` sampai 1 mm), karena retak 2 mm tidak punya puncak tengah pada satu skala kecil. Kandidat harus punya sinyal/derau >= 5 dan puncak lokal sejati (respons dievaluasi 1 mm di luar radius sehingga punggung di luar 1,5 mm tampak sebagai lereng, bukan puncak palsu di tepi). Arah diperbarui dengan garis OLS melalui 4 pusat bagian (2 lintasan).

## D24. Fase 3: ketidakpastian bentuk kernel (temuan sapuan)
- Temuan SINTETIS: untuk retak sempit (w kurang dari sekitar 3 sigma) lebar dipengaruhi bentuk kernel, bukan hanya sigma: kernel nyata (Gaussian dikonvolusi apertur kotak) bukan Gaussian, sehingga ada bias sistematis positif (+9,8 sampai +39 um pada w 0,05 sampai 0,1 mm, sigma 0,6 sampai 2 px) yang tidak tertangkap `u_fit` (derau) maupun `u_sigma_edge` (ketelitian antar tepi, sekitar 1 persen). Tanpa tambahan, cakupan `2 u_frame` pada w = 0,05 mm hanya 33 persen (sigma 0,6 px) dan 76 persen (sigma 1 px).
- Keputusan: `u_sigma_w` dihitung dengan `u_sigma = sqrt(u_sigma_edge^2 + (eps sigma)^2)`, `eps = 0,10` (`defaultKernelShapeRelUncertainty`), dapat diubah. Dari tiga nilai yang dicoba (0; 0,05; 0,10) hanya 0,10 mencapai cakupan >= 90 persen pada kasus terburuk (w 0,05 mm: 97 persen pada kedua sigma; dengan 0,05: 60 dan 90 persen). Nilai ini TIDAK divalidasi di perangkat; kemungkinan ponsel nyata lebih buruk (penajaman ISP, JPEG, tepi versus retak diproses beda). Retak lebar tidak diperbaiki oleh `eps`: kekurangan cakupannya (63 sampai 77 persen) berasal dari `rho` (D22).
- Pengaruh pada anggaran 5.5: `u_sigma_w` di 5.5 = komponen ini.

## D25. Fase 3: status per frame dan lantai
- `measureFrame` mengembalikan `MeasureAccepted` (dengan status `TERUKUR`, `DI_BAWAH_BATAS_UKUR`, `TIDAK_TERUKUR`) atau `MeasureRejected` (alasan: patch terlalu kecil, tepi PSF tak tersedia, blur terlalu besar, blur anisotropik, jenuh, retak tak ditemukan, masukan tak valid). Penolakan berarti frame tak bisa diukur; `TIDAK_TERUKUR` berarti diukur tetapi gerbang kontras atau kesehatan fit gagal.
- Lantai frame = `max(0,5 mm/px, 2 u_frame)` dengan `u_frame = sqrt(u_fit^2 + u_sigma_w^2)`; lantai kunjungan penuh (5.5) memakai `u_c` lengkap di fase agregasi. Di bawah lantai: `reportableWidthMm == null`.
- Gerbang kualitas citra dari 5.4 (sigma, anisotropi, jenuh) dipakai di `measureFrame` memakai `QualityThresholds`. Piksel jenuh = di atas 0,995 atau di bawah 0,005 di dalam kotak +-5 mm.
- `MODEL_MISFIT` bila `misfitRel` (bagian sistematis residu akhir, `sqrt(max(0, rms^2 - derau^2/N))`, dibagi kedalaman lembah) melebihi 1 persen. Ambang pertama (rasio residu/derau > 2,5) dibuang karena memberi alarm palsu pada citra sangat bersih (rasio sampai 3,2 pada derau 0,002 untuk model yang benar). Empiris (SINTETIS): model benar paling banyak 0,25 persen; tepi kasar 0,08 mm: 1,6; bayangan 0,9x: 3,4; noda amplitudo 0,1: 1,2 persen.

## D26. Fase 3: linearisasi sRGB dan peringatan lebar
- Model lebar linear terhadap cahaya; nilai JPEG berenkode gamma membiaskan lebar sub-piksel (SINTETIS: -3,9 persen pada 0,5 mm, -13 persen pada 0,2 mm). Ditambahkan `GrayPatch.linearizedFromSrgb()` dan `srgbToLinear`; adapter Fase 5 wajib memanggilnya. Dengan linearisasi galat kembali +1,7 / +3,8 / +10,7 um (0,5 / 0,2 / 0,1 mm). Apakah kurva nada ponsel mendekati sRGB hanya bisa dicek di perangkat. Ini satu-satunya penambahan API di luar enam berkas yang diminta selain `special.dart`, `stats.dart`, `rejection.dart`, dan harness (`patch_scene.dart`, `violations.dart`).
- `WIDTH_BEYOND_VALIDATED` bila lebar > 1,05 x 2,0 mm: sapuan menunjukkan galat 68 +- 56 um pada 2,6 mm dengan `u_frame` 0,2 um.

## D27. Fase 3: artefak renderer pada retak sejajar sumbu piksel
- Retak tepat sejajar sumbu (0 atau 90 derajat) memberi bias +10,3 um pada S=4 dan -4,6 um pada S=8 di harness, sedangkan 20 derajat memberi +0,3 um. Penyebabnya kuantisasi sub-sampel renderer (aritmetika eksak: 8,5 px pada S=4, 8,25 px pada S=8, benar 8,333 px), bukan algoritma. Dugaan awal "kunci fase piksel" dan prediksi +2,5 um pada S=8 keliru dan dikoreksi oleh pengukuran. Kasus pelanggaran asumsi (bayangan, noda, retak kedua) dirotasi 20 derajat (`rotatedAboutOrigin`) agar artefak ini tidak tercampur.

## D28. Fase 3: dependensi
- Tidak ada dependensi baru. LM, fungsi CDF normal (deret positif, ~1e-16), statistik, dan interpolasi ditulis sendiri.

## D29. Fase 4: anggaran ketidakpastian (2026-11-17)
- Pembangun `UncertaintyBudget.fromFrames` mengikuti 5.5 harfiah. Penafsiran yang dipilih: (a) `rms_mm` = `loo_mm` bila ada, selain itu `rms_px x mm_per_px`; `u_pos = |dw/ds| max(rms_mm, 0,05)`; `u_geo = w sqrt(rms_mm^2 + loo_mm^2)/120` dengan `loo_mm = 0` bila tidak ada. Dengan 4 penanda `loo_mm` jadi terhitung dua kali di `u_geo` (faktor sqrt 2): konservatif, sengaja dibiarkan harfiah. (b) Suku geometri (tilt, `rms_mm`, `loo_mm`, `dw/ds`, `mm_per_px`) memakai median antar frame, `u_sigma_w` rata-rata. (c) `dw/ds` yang tak diketahui di semua frame: `u_pos = 0` dan `dw_ds_unknown = true` di anggaran (informasi hilang dinyatakan, bukan disembunyikan). (d) Derajat kebebasan Welch-Satterthwaite hanya dari `u_stat` (n-1), komponen lain tak hingga, sesuai 5.5; `k` dari tabel t dengan interpolasi linear dalam 1/dof (galat < 0,001 untuk dof <= 30, < 0,003 sampai dof 100, selalu ke sisi konservatif); tabel dof 1..30 dihitung (integrasi numerik) dan dicocokkan dengan NIST/SEMATECH e-Handbook 1.3.6.7.2 (3 desimal).
- `rho` disimpan terpisah di `FrameRecord` (`uFitRawMm` dan `rho`) agar kalibrasi bisa memutar ulang frame tersimpan dengan `rho` lain tanpa mengukur ulang; replay eksak karena `rho` hanya mengalikan `u_fit` dengan `sqrt(rho)`.
- Batas pelaporan: `floor = max(0,5 mm/px, 2 u_c)` dengan `u_c` penuh (termasuk `u_dev` bawaan 0,5 mm/px), sehingga tanpa validasi perangkat batas ukur praktis sekitar 1 mm/px.

## D30. Fase 4: gerbang kunjungan dan penanganan TIDAK_TERUKUR
- Kunjungan ditolak (`DITOLAK`, tidak disimpan) bila < 3 frame diterima; hanya 5 frame diterima pertama dipakai. Frame diterima = lolos gerbang geometri dan `measureFrame` mengembalikan hasil (status apa pun). Alasan penolakan dikembalikan terstruktur per frame (`FrameRejection` dan `RejectReason` kode).
- Frame TIDAK_TERUKUR dikeluarkan dari median. Bila yang tersisa < 3 atau bukan mayoritas ketat dari frame diterima, kunjungan `TIDAK_TERUKUR` (tanpa angka): membuang frame sulit dari retak samar tidak boleh menyisakan angka yakin. Frame yang di bawah batas ukur pada tingkat frame tetap ikut median; lantai kunjungan yang memutuskan.

## D31. Fase 4: tren
- Dasar = kunjungan pertama pada daftar; "sebelumnya" = kunjungan tepat sebelumnya (bila tak bernomor, perbandingan itu `TIDAK_TERUKUR`, tanpa melompat ke yang terakhir bernomor). `u_delta` hanya memakai `u_rand` kedua kunjungan dan `(delta u_print_rel)^2`; `u_print` dan `u_dev` bukan masukan (sistematis bersama, saling meniadakan). Tanpa regresi atau ekstrapolasi: tiap perbandingan hanya bergantung pada dua kunjungannya (diuji). Peringatan konteks (model ponsel, versi algoritma, lembar) tidak mengubah angka.
- Pengukuran (SINTETIS, 20000 replikasi, seed tetap, test/trend_test.dart): positif palsu pada k=2 sebesar 4,61 persen (ekspektasi normal 4,55); perubahan sebesar MDC terdeteksi 50,4 persen, 2 x MDC 97,7 persen (ekspektasi 50 dan 97,7).

## D32. Fase 4: statistik pelat
- `PlateMeasurement` menyimpan `u_truth`, `u_c`, `k`; galat = terukur - kebenaran; cakupan = fraksi `|galat| <= k sqrt(u_c^2 + u_truth^2)` atas garis yang dilaporkan. Garis tanpa angka (di bawah batas ukur) dihitung "tidak dilaporkan".
- Batas bawah empiris: lebar terkecil yang diuji sehingga ia dan semua lebar lebih besar "andal": >= 90 persen garis dilaporkan, cakupan >= 90 persen, dan median `U` gabungan < lebarnya (angka yang ketidakpastiannya melebihi dirinya tidak informatif). Tidak memilih lebar sempit yang kebetulan lolos bila lebar tengah gagal.
- `u_dev` = RMS bias per lebar pada lebar uji dalam faktor 2 (0,5 sampai 2 kali) dari lebar yang diukur; null (tetap memakai bawaan tak tervalidasi) bila tak ada lebar sebanding.

## D33. Fase 4: studi sintetis, kalibrasi `rho`, dan angka yang dihasilkan (2026-11-17)
- Berkas: `lib/src/studies/{synthetic_study,study_analysis}.dart` (diekspor lewat `synthetic.dart`) dan `tool/{run_synthetic_study,study_report}.dart` di `packages/hairline_core` (folder `tool/` yang sudah dipakai `measurement_sweep.dart`, bukan `tools/` di akar yang berisi spike OpenCV). Keluaran: `docs/SYNTHETIC_VALIDATION.md` dan `docs/SYNTHETIC_VALIDATION_CONDITIONS.csv` (864 baris). Frame mentah di `packages/hairline_core/build/synthetic_study/` (tidak di-commit).
- Desain: grid penuh 864 kondisi; derau {1; 3; 6} ditafsirkan sebagai sd dalam tingkat abu-abu 8 bit; kedalaman retak 0,4 dari latar 0,8; lima replikasi untuk kalibrasi (4320 kunjungan, 21600 frame), satu replikasi hold-out lengkap (864 kunjungan). Replikasi ke-6 sampai ke-8 sempat berjalan tetapi dihentikan (mesin 8 GB berebut memori dengan emulator/IDE sehingga laju turun dari ~100 ke ~16 kunjungan per menit); replikasi tak lengkap tidak dipakai. Per kondisi hanya 5 sampai 6 kunjungan, jadi cakupan per kondisi kasar (dinilai dengan interval Wilson).
- Penyederhanaan yang disengaja: satu burst berbagi pose dan render bebas-derau (getaran tangan tidak disimulasikan; dilakukan demi waktu: render per frame 2 sampai 8 detik); PSF dari patch penanda terpisah dengan homografi sebenarnya; tilt dari `f_px` bawaan.
- Optimasi renderer (`_blur` di `synthetic/render.dart`): jalur interior tanpa `clamp`; urutan penjumlahan sama sehingga hasil identik (checksum patch sama, 805 ms vs 2755 ms). Studi memakai proses terpisah, bukan isolate: isolate satu grup berbagi heap dan GC stop-the-world sehingga 8 isolate 8 kali lebih lambat dari satu.
- Cakupan dihitung tiga tingkat (fit = `k sqrt(u_stat^2 + u_sigma_w^2)`, acak, bawaan) dan dengan `u_truth` renderer = `0,1021 px x mm/px` (batas kuadratur 0,5/S px per tepi, seragam, dua tepi); varian ketat `u_truth = 0` tetap dilaporkan. Alasan: pada lebar 2,0 mm galat sebenarnya 1 sampai 23 um (sampai 0,15 px) sedangkan `u_fit` sekitar 1 um; percobaan `renderer-check` (derau acak sama, S 4 vs 8) menurunkan RMS galat dari 7,6 ke 1,6 um dan dari 13,4 ke 5,2 um, jadi sisa galat itu resolusi simulator.
- Hasil kalibrasi: **`rho = 1,0` didukung** (cakupan fit 100 persen dengan `u_truth`; 98,7 persen ketat, 5 dari 668 kondisi ketat di bawah 90 persen, semuanya lebar 2,0 mm dengan galat beberapa um). Mengejar cakupan ketat di semua kondisi butuh `rho = 64` (`u_fit` 8 kali) dan tidak dipilih. Ini mengoreksi D22 (perkiraan `rho` sekitar 5 dari sapuan Fase 3 yang memakai `u_frame` tanpa `u_repeat` dan faktor t, dan galat eksak). `ProfileFitConfig.rhoCalibrated` sekarang `true` (hanya terhadap simulasi; bukan validasi perangkat); angka hasil ukur tidak berubah sehingga `measurementAlgorithmVersion` tetap `p3-1`.
- Temuan jujur: `U` bawaan terlalu lebar (persentil ke-95 `|galat|/U` = 0,05) dan positif palsu tren pada rantai penuh 0,2 persen pada tilt 0 dan 0 persen pada tilt 10/20 (ekspektasi 4,55); `u_delta` tilt 0 sekitar 1,9 kali sebaran nyata, tilt > 0 sekitar 20 kali (karena `u_par` dengan relief 0,3 mm yang tidak ada). Konservatif, tidak optimistis; ketepatan menunggu validasi perangkat.
- Frame `MODEL_MISFIT` belum dikecualikan di `aggregateVisit` (butuh keputusan adapter Fase 5; `FrameRecord` belum membawa peringatan).

## D34. Fase 5: adapter OpenCV di paket terpisah, belum dihubungkan ke `app/` (2026-11-17)
- Masalah: perintah fase menyebut adapter di `app/`, tetapi selama `opencv_dart` ada di dependensi `app/`, setiap `flutter test` di `app/` gagal di mesin ini (D1, BLOCKERS B1; dicoba lagi di Fase 5 pada `packages/hairline_opencv`: "Building native assets failed").
- Keputusan: adapter (`OpenCvFrameImageSource`, `OpenCvDecodedImage`, `OpenCvMarkerDetector`, `openCvPorts`) hidup di `packages/hairline_opencv` (tanpa logika pengukuran). `app/` hanya bergantung pada port di core dan menerima pabrik adapter lewat `framePortsFactoryProvider` (secara bawaan melempar `UnimplementedError`, jadi aplikasi yang lupa menyambungkannya gagal keras). Menghubungkan adalah dua baris: dependensi `hairline_opencv` di `app/pubspec.yaml` dan satu override di `main.dart` (ada TODO). `make verify` menjalankan `flutter analyze` pada paket adapter (terbukti bersih) tetapi TIDAK menjalankan tesnya (`make opencv-test`, job CI `opencv` pada Linux, `continue-on-error`, belum terbukti).
- Konsekuensi jujur: aplikasi yang dibangun dari repo ini belum dapat mengukur di perangkat sampai dependensi itu disambungkan dan dibangun di host yang bisa (Linux/Xcode). Seluruh jalur lain (isolate, pipeline, Drift, kunjungan) berjalan dalam tes memakai port sintetis dengan kode yang sama.

## D35. Fase 5: dependensi baru
- `app`: `path`, `path_provider` (direktori privat), `crypto` (SHA-256). Sudah transitif sebelumnya; kini dideklarasikan karena dipakai langsung. `sqlite3` tetap transitif lewat drift (`NativeDatabase`); terbukti berjalan di host (tes Drift lulus), jadi D6 berlaku.
- `hairline_core` (dev saja): `image ^4.8.0` untuk menyandikan/mendekode JPEG nyata di tes ujung-ke-ujung. Inti produksi tetap tanpa dependensi.
- `hairline_opencv`: `opencv_dart ^2.2.2` dengan modul sama seperti D10.

## D36. Fase 5: port, pipeline frame di inti, dan keputusan MODEL_MISFIT
- Port di core: `DecodedImage` (dimensi, `extractPatch` nilai 0..1 bergamma, `dispose`), `FrameImageSource.decode`, `MarkerDetector.detect(DecodedImage)`. Gambar yang didekode tetap native (Mat) dan hidup sampai `processFrame` memanggil `dispose` di `finally`; detektor menerima `DecodedImage`, bukan byte, agar Mat tidak disalin ke Dart.
- Orkestrasi satu frame ada di core (`processFrame`, `frame_pipeline.dart`), bukan di app, supaya dapat diuji tanpa native dan agar app tidak memuat logika pengukuran: deteksi, homografi, tilt, gerbang geometri, patch, `linearizedFromSrgb` (D26), `measureFrame`. App hanya menjalankannya di isolate dan menyimpan hasil.
- Patch: satu patch per penanda (setengah sisi 15 mm x skala cetak + 14 px) dan satu patch retak (+-8 mm), tidak pernah satu patch seluruh lembar. `estimatePsfFromPatches` (baru, `psf.dart`) menaksir PSF dari patch per penanda; `estimatePsf` lama memanggilnya (hasil sama). Terukur pada tes: empat patch ~4 sampai 5 persen luas foto per patch, total di bawah 25 persen (nilai terukur di foto uji 1600 x 1500).
- MODEL_MISFIT (pertanyaan terbuka dari Fase 4): frame yang terukur tetapi bertanda `MODEL_MISFIT` diperlakukan sebagai `TIDAK_TERUKUR` (`FrameRecord.withStatus`), jadi keluar dari median dan ikut aturan mayoritas D30, dan ditandai `demoted_for_misfit` di `quality_json`. Alasan: peringatan itu berarti `u_fit` tidak dapat dipercaya; angka yang tampak yakin dari frame demikian lebih buruk daripada kehilangan satu frame. Terbukti SINTETIS (bayangan satu sisi 0,9x) di `frame_pipeline_test`.
- Penolakan baru di `FrameRejection`: `homographyFailed`, `imageUnreadable`; tiap penolakan geometri kini membawa pesan Indonesia spesifik (`message`).
- Efek JPEG (SINTETIS, bukan ponsel): lihat MEASUREMENT_NOTES bagian "Fase 5".

## D37. Fase 5: isolate dan pembatalan
- `FrameProcessor` menjalankan `processFrame` di isolate sekali pakai per frame (`Isolate.spawn`, foto dikirim dengan `TransferableTypedData`, hasil adalah objek core biasa). Pabrik adapter dibuat DI DALAM isolate (handle native tidak melintas isolate).
- Pembatalan kooperatif: pemanggil langsung menerima `FrameCancelledException`, worker di-`kill(beforeNextEvent)`. Dipilih bukan `immediate` karena kill langsung dapat memotong kode Dart dan melompati `finally` (kebocoran Mat); `beforeNextEvent` menunggu pipeline sinkron selesai sehingga `dispose` sudah jalan. Harganya: worker berjalan sampai satu frame selesai (<= sekitar 1 detik di ponsel, belum diukur), hasilnya dibuang. Terbukti di tes (`open`/`close` seimbang setelah cancel, setelah error, setelah worker mati).
- Satu frame satu isolate, berurutan: foto 12 MP dan salinan terdekodenya besar; paralel ditolak. Biaya spawn per frame tidak diukur di ponsel.

## D38. Fase 5: penyimpanan
- Skema 5.7 persis (tujuh tabel, tanpa `alerts` dan `reports`); kunci asing semuanya RESTRICT dan `PRAGMA foreign_keys = ON` per koneksi; indeks: `cracks(site_id)`, `crack_points(crack_id)`, `visits(crack_id, ts_utc)`, `frames(visit_id)`, `measurements(visit_id, algorithm_version)`, `validation_runs(device_model, ts_utc)`. Satu titik per retak ditegakkan repository (bukan UNIQUE: skema siap banyak titik). `sheet_id` 0..11 dan `print_scale` 0,8..1,2 punya CHECK.
- Waktu: kolom `DateTime` bawaan drift (detik epoch); repository menolak waktu non-UTC dan hasil bacaan diubah `toUtc()`. Resolusi detik cukup untuk kunjungan.
- Migrasi: versi 1 (belum ada rilis sebelumnya). `onUpgrade` melempar bila dipanggil (belum ada langkah); basis data dari versi yang lebih baru ditolak di `beforeOpen`. Setiap langkah di masa depan wajib datang dengan tes migrasi. Snapshot skema `drift_dev schema dump` BELUM dibuat.
- `measurements`: `width_mm`, `u_*`, `k` hanya terisi bila status `TERUKUR`; `DI_BAWAH_BATAS_UKUR` dan `TIDAK_TERUKUR` menyimpan `NULL` dan anggaran lengkap hanya di `components_json`, agar angka yang tak boleh ditampilkan tak pernah tersimpan di kolom angka. Baris per frame: `u_rand` = `u_frame`, `u_sys`/`u_expanded`/`k` NULL (anggaran hanya pada tingkat kunjungan).
- `u_dev` tetap bawaan tak tervalidasi (`BELUM_DIVALIDASI`) sampai Fase 7; `VisitProcessor` tidak membaca `validation_runs`.
- Frame: hanya yang diterima (maks 5) ditulis, nama acak 128 bit + `.jpg`, tulis ke `.tmp` lalu rename, SHA-256 disimpan dan diverifikasi sebelum pemrosesan ulang. Foto yang tak diterima tidak pernah ditulis. Bila transaksi gagal, file yang sudah ditulis dihapus lagi (upaya terbaik; sisa disapu `deleteUnreferenced`, belum dipanggil saat start: menunggu Fase 6).
- Pemrosesan ulang: `VisitProcessor.reprocess` menambah baris (agregat + per frame) dengan `algorithm_version` baru; versi yang sama dua kali ditolak; baris lama tidak pernah diubah (diuji sebagai persamaan nilai). Tabel `frames` tidak diubah; geometri versi baru ada di `components_json` baris baru.
- Penghapusan frame yang dirujuk pengukuran ditolak oleh repository dan oleh kunci asing.

## D39. Fase 6: arsitektur alur pengambilan dan penguncian kamera (2026-11-25)
- Lapisan: `reduceCapture` (fungsi murni, `capture_flow.dart`) memutuskan semua fase (menunggu penanda, menyesuaikan, siap, burst, memproses, hasil, galat); `CaptureController` (Riverpod, `capture_controller.dart`) hanya memberi peristiwa dan menjalankan I/O; `CameraService` adalah antarmuka dengan dua implementasi: `DeviceCameraService` (urutan, siklus hidup, balapan) di atas `CameraDriver` (lapisan tipis atas `CameraController`), dan `FakeCameraService`. Pemisahan driver dibuat agar logika yang paling rawan (urutan stream/kunci/bidik, jeda, pause di tengah burst, dispose ganda) dapat diuji dengan driver tiruan; `CameraPluginDriver` sendiri butuh kamera nyata dan berstatus ditulis, belum dijalankan.
- Aturan siklus hidup di `DeviceCameraService`: operasi siklus hidup (initialize, pause, resume, dispose) berjalan satu per satu sesuai urutan panggil; `pause` dan `dispose` menaikkan penghitung generasi seketika sehingga burst yang sedang jalan gagal sebagai `interrupted` pada pemeriksaan berikutnya dan tidak menyentuh kamera yang sudah dilepas; `pause` menunggu bidikan yang sedang berjalan (maks 5 detik) sebelum menutup kamera; stream selalu dihentikan sebelum bidikan pertama dan dilanjutkan sesudah terakhir; callback stream dari generasi lama diabaikan; satu burst pada satu waktu (`busy`).
- Kunci saat bidik, bukan saat stabil: fokus dan eksposur dikunci tepat setelah tombol ditekan (sesudah "siap" yang stabil), lalu jeda penyesuaian 300 ms, burst, lalu dibuka lagi (`auto`). Mengunci lebih awal membuat kunci basi begitu ponsel bergeser. Perangkat yang menolak kunci (galat dari plugin) tetap memotret; hasil diberi bendera `fokus_tidak_terkunci` / `eksposur_tidak_terkunci` di `camera_info_json.flags`, ditampilkan sebagai peringatan, dan frame tetap melewati gerbang kualitas yang ada (blur `sigma_px`, anisotropi). Tidak ada gerbang baru.
- Batas pengetahuan: backend CameraX tidak melempar galat bila kunci diabaikan perangkat, dan plugin mengisi `value.focusMode` apa pun hasilnya. "Terkunci" di kode berarti "diminta tanpa galat". Bukti bahwa fokus benar-benar bertahan hanya dari DEVICE_TEST bagian 2.
- Resolusi: `ResolutionPreset.max` (still tertinggi, keputusan terkunci). Plugin `camera` mengikat pratinjau, foto, dan stream analisis ke satu preset, jadi stream live ikut beresolusi maksimum (bidang Y sekitar 12 MP per frame lewat platform channel). Mitigasi: throttle memutuskan SEBELUM menyalin (frame yang dibuang tidak didesimasi), plugin sendiri membuang frame lama, dan desimasi ke sisi panjang <= 800 px. Risiko kinerja dan panas belum terukur (DEVICE_TEST bagian 6); opsi cadangan `veryHigh` mengorbankan resolusi foto sehingga butuh keputusan setelah uji perangkat.
- Foto dari `takePicture` dibaca sebagai bytes lalu berkas cache plugin dihapus (salinan kedua di luar penyimpanan privat). Burst N = 6 (`FlowConfig.burstCount`), jeda minimal 200 ms, disimpan sebagai `List<Uint8List>` (sekitar 30 MB pada 12 MP, diterima karena `VisitProcessor.processBurst` berurutan; jalur berkas ditunda).
- Izin: lewat `camera` (kode galat `CameraAccessDenied`, `CameraAccessDeniedWithoutPrompt`, `CameraAccessRestricted` dipetakan ke pesan Indonesia spesifik). Tidak menambah `permission_handler`. Manifest utama menyatakan hanya `CAMERA` dan menghapus (`tools:node="remove"`) `RECORD_AUDIO`, `WRITE/READ_EXTERNAL_STORAGE` (dari plugin kamera) dan `ACCESS_NETWORK_STATE` (dari media3); `INTERNET` hanya di manifest debug/profile.

## D40. Fase 6: deteksi live, throttling, dan port detektor abu-abu
- Port baru di core `GrayMarkerDetector.detectGray(gray, w, h)` + `GrayDetectorFactory` (`frame_ports.dart`); implementasi OpenCV `OpenCvGrayMarkerDetector` di `packages/hairline_opencv` memakai fungsi deteksi yang sama dengan jalur foto (sub-pixel sudut aktif) dan membuat serta melepas `Mat` dalam satu `ResourceScope` per panggilan. Tes adapter ditulis, BELUM dijalankan (B1). `app/` tetap tidak bergantung pada `hairline_opencv` (D34): `grayDetectorFactoryProvider` secara bawaan melempar dan layar pengambilan menampilkan "Detektor penanda belum tersedia" (tes), sama seperti `framePortsFactoryProvider`.
- `DetectionWorker`: satu isolate berumur panjang yang membuat detektor di dalamnya (handle native tidak melintas isolate), satu frame dalam penerbangan, TANPA antrean. `FrameThrottle` (interval minimal 85 ms, sekitar 11,8 fps maksimum; detektor lambat menurunkannya sendiri) memutuskan sebelum frame dibuat (`offer(produce)`: frame yang dibuang tidak pernah didesimasi). `dispose` memakai `kill(beforeNextEvent)` seperti D37 agar `Mat` frame yang sedang berjalan sempat dilepas. Kegagalan satu frame dilaporkan sebagai galat stream tanpa mematikan isolate.
- Analisis pose (homografi 3 sampai 4 penanda dengan leave-one-out, tilt, deviasi) berjalan di isolate UI: biaya jauh di bawah satu milidetik per frame, di bawah selang frame; sengaja tidak dipindah agar `comparePose`, aturan stabilitas, dan state tidak melintas isolate.
- Nilai awal TAK DITUNING di perangkat (konstanta bernama dan terdokumentasi): `FlowConfig.stableFramesRequired = 5` (sekitar 0,5 detik), `staleAfter = 1 detik` (deteksi macet melepas tombol bidik), `LiveAnalyzer.defaultStability`: selisih antar frame translasi 1 persen diagonal, skala 0,97 sampai 1,03, rotasi 2 derajat, tilt 3 derajat.

## D41. Fase 6: koordinat tegak, referensi pose, dan panduan kunjungan dasar
- Stream CameraX tidak diputar. Deteksi (koordinat grid desimasi) dipetakan ke piksel sumber lalu diputar `sensorOrientation / 90` kuartal searah jarum jam ke bingkai tegak SEBELUM analisis; seluruh pose, instruksi ("geser ke kiri" dalam arah layar), hantu, dan overlay berada di bingkai tegak. Layar dikunci potret (`SystemChrome` dan `lockCaptureOrientation`). Ini asumsi tentang CameraX (bingkai analisis tidak diputar plugin); butuh DEVICE_TEST bagian 4.
- Referensi pose (`visits.reference_pose_json`, `ReferencePose`): JSON `{v:1, image:{w,h}, h:[9], pose:{cx,cy,area,rot_deg,tilt_deg}}` ternormalisasi ke sisi panjang 1000 px (agar resolusi live yang berbeda tetap sebanding). Disimpan dari analisis live terakhir yang membuat tombol bidik siap (bukan dari foto diam: OpenCV menerapkan EXIF pada `imdecode`, sehingga orientasi foto diam tidak pasti). Hanya kunjungan dasar menyimpannya. Tidak kompatibel bila rasio aspek berbeda lebih dari 3 persen: panduan memakai aturan umum dan UI menampilkan catatan; JSON rusak diperlakukan sama.
- Tanpa referensi (kunjungan dasar): siap bila gerbang geometri 5.4 lolos DAN kemiringan <= 8 derajat (`PoseThresholds.maxTiltDeltaDeg`) DAN mantap; `resolutionTooCoarse` menghasilkan instruksi `CLOSER`. Dengan referensi: gerbang 5.4 lolos DAN `comparePose` tanpa instruksi DAN mantap. Hantu = empat penanda dari homografi referensi diproyeksikan ke bingkai live (garis putus-putus).
- Pengambilan hanya dari fase `ready`; `shutter()` memanggil reducer secara sinkron sebelum await apa pun sehingga ketukan ganda tak membuat burst ganda. Kunjungan yang tidak lolos (`VisitNotStored`) tidak menulis apa pun (tes: tabel visits kosong dan folder foto kosong). Setelah dasar tersimpan, bidikan berikutnya di layar yang sama menjadi `followup` dengan referensi yang baru disimpan.
- Kartu hasil di layar pengambilan hanya ringkas (jumlah frame diterima, lebar +/- U bila TERUKUR, batas bawah bila di bawah batas ukur, skala perkiraan, label `BELUM_DIVALIDASI`, pernyataan indikatif, peringatan bendera). Layar hasil dan tren penuh tetap tugas fase berikutnya.

## D42. Fase 6: simulasi dan temuan dari tes
- Mode simulasi: `lib/main_fake.dart` (`flutter run -t lib/main_fake.dart`), `FakeCameraService` memutar skrip bingkai live (tanpa penanda, dua penanda, mendekati pose target, diam) dan foto diam sintetis dari renderer core (sekitar 15 detik, di isolate); detektor dan port memakai penanda tertanam (`embedded_ports.dart`, kode jalur yang sama dengan produksi, tanpa native). Foto simulasi bukan JPEG. Seluruh hasil darinya berlabel SINTETIS. Tombol "Uji pengambilan foto (debug, kamera nyata)" di halaman awal hanya muncul di `kDebugMode`, membuat retak uji (lembar 0, skala 1, titik tengah, arah 0) karena layar pembuat retak belum ada.
- Temuan nyata dari tes ujung ke ujung: (1) provider auto-dispose yang hanya di-`read` oleh controller dilepas setelah await pertama sehingga kamera ditutup tepat setelah dibuka; diperbaiki dengan `ref.watch` di `build`. (2) `ref` mati setelah layar ditutup padahal `_start` masih berjalan; semua `ref.read` dipindah sebelum await pertama dan `ref.mounted` diperiksa. (3) Tanpa penjaga, galat query setelah layar ditutup menjadi galat tak tertangani; kini dilaporkan hanya jika layar masih ada.
- Sapuan berkas yatim `sweepOrphanFrames` dipanggil saat start (`main.dart`), menutup catatan D38.
- Dependensi: tidak ada paket baru (`camera` sudah ada sejak Fase 1; kanal platform memakai `flutter/services`).
