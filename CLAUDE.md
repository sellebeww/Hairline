# Hairline: kontrak proyek

Dokumen ini adalah sumber kebenaran tunggal. Baca penuh di awal setiap sesi, lalu baca `docs/PROGRESS.md`. Jika instruksi fase bertentangan dengan dokumen ini, dokumen ini menang kecuali instruksi fase menyebut pengecualian secara eksplisit.

## 1. Tujuan proyek

Hairline adalah aplikasi Flutter (Android lebih dahulu) untuk memantau perkembangan lebar retak bangunan secara longitudinal oleh non-profesional. Pengguna menempel lembar bingkai penanda ArUco (ukuran diketahui) mengelilingi retak. Tiap kunjungan, aplikasi memandu posisi ponsel, mengoreksi perspektif ke bidang metrik lewat homografi, mengukur lebar retak pada satu titik bertanda dengan model profil sub-pixel, menghitung ketidakpastian, dan membandingkannya dengan kunjungan sebelumnya. Peringatan perubahan hanya muncul bila perubahan melebihi ketidakpastian pengukuran.

Pembeda: pengukuran longitudinal untuk non-profesional dengan ketidakpastian yang ditampilkan jujur, panduan pose agar kunjungan ulang konsisten, tanpa perangkat keras tambahan selain lembar cetak.

Tujuan portofolio: computer vision geometri (homografi, sub-pixel, model profil, anggaran ketidakpastian) dengan hasil yang dapat dikuantifikasi dan didemokan hanya dengan ponsel dan kertas.

### Pernyataan jujur (wajib tampil di README, layar hasil, dan layar bantuan)
- Hasil bersifat INDIKATIF dan bukan pengganti inspeksi insinyur struktur. Aplikasi tidak menilai keselamatan bangunan dan tidak pernah menampilkan kata "aman" atau "tidak berbahaya". Teks statis di layar hasil: bila retak tampak melebar, bertambah panjang, atau muncul retak baru, hubungi insinyur atau pihak berwenang.
- "Tidak ada perubahan terdeteksi" berarti perubahan, jika ada, lebih kecil dari ketidakpastian pengukuran. Itu bukan bukti bahwa retak tidak berubah.
- Angka akurasi hanya boleh dilaporkan dengan label asalnya: `SINTETIS` (dari simulasi) atau `PERANGKAT` (dari validasi pelat pada ponsel nyata oleh pemilik). Dilarang menulis angka akurasi tanpa label dan tanpa data yang benar-benar diukur.
- Klaim literatur dan pesaing dalam spesifikasi awal (aplikasi Witteveen+Bos, galat 5 mm pergeseran kamera, lensa tambahan untuk 0,3 sampai 1 mm pada jarak 2 m) belum diverifikasi. Di README tulis sebagai "dilaporkan, tidak diverifikasi" atau verifikasi ke sumber primer dan kutip.
- Hairline tidak mengukur retak yang tidak sebidang dengan lembar penanda secara akurat, dan tidak cocok untuk keputusan regulasi.

## 2. Pemilik dan aturan repo

- Pemilik dan pemegang hak cipta: **Vassel Goleyu**. Cantumkan di `LICENSE` (MIT, "Copyright (c) 2026 Vassel Goleyu"), `pubspec.yaml`, header singkat di file sumber utama, dan README.
- Jangan pernah menambahkan `Co-Authored-By`, footer "Generated with ...", atau URL sesi ke commit atau PR. Agent tidak boleh muncul sebagai author atau kontributor.
- Jangan memakai tanda em dash (U+2014) di teks apa pun (kode, komentar, dokumen, commit, UI). Pakai koma, titik, titik dua, atau kurung.
- Commit kecil, Conventional Commits (`feat(core): ...`). Minimal satu commit per langkah besar, wajib satu commit di akhir tiap fase.
- Jangan commit keystore, `local.properties`, kredensial, atau artefak build.
- Bahasa: UI Bahasa Indonesia (`ARB`/katalog terpusat, tanpa string hardcoded di widget). Kode, komentar, identifier, README, commit Bahasa Inggris. Dokumen kerja `docs/*.md` boleh Bahasa Indonesia.

## 3. Scope lock

### Wajib (MVP, semua harus selesai)
1. Pembuatan lembar bingkai penanda (PDF) dengan panduan pemasangan dan verifikasi skala cetak.
2. Deteksi penanda dan estimasi homografi dengan diagnostik kualitas.
3. Panduan pose real-time (overlay) dan pengambilan burst dengan fokus dan eksposur terkunci, serta gerbang kualitas (blur, eksposur, geometri).
4. Pengukuran lebar retak pada SATU titik bertanda dengan model profil sub-pixel dan ketidakpastian.
5. Penyimpanan lokal offline (Drift), kunjungan, frame, pengukuran.
6. Tren 2 sampai 5 kunjungan dengan batang ketidakpastian dan indikator perubahan signifikan.
7. Validasi pada pelat kalibrasi buatan sendiri: generator pelat, mode validasi di aplikasi, laporan akurasi tersimpan, dan studi validasi sintetis.
8. Pustaka inti Dart murni terpisah dari Flutter dengan test lengkap.

### Dilarang dikerjakan (di luar scope, jangan tambahkan walau terasa berguna)
Laporan PDF kunjungan, notifikasi atau tabel `alerts`, banyak titik per retak (skema disiapkan, fiturnya tidak), sinkronisasi dan Appwrite, akun pengguna, peta atau geofencing, iOS (tidak ditargetkan dan tidak diverifikasi), tablet/desktop UI, pembelajaran mesin untuk deteksi retak, kalibrasi intrinsik kamera dengan papan catur, AR dengan ARCore/ARKit, pengukuran panjang atau area retak, penilaian tingkat keparahan. Indikator "perubahan signifikan" pada layar tren adalah bagian Wajib 6 dan BUKAN sistem peringatan.

Jika menemukan ide di luar daftar Wajib, catat satu baris di `docs/BACKLOG.md` dan lanjutkan.

## 4. Keputusan terkunci (jangan diubah, jangan ditanyakan)

| Hal | Keputusan |
|---|---|
| Framework | Flutter stable terbaru dan Dart yang menyertainya |
| Struktur | Monorepo: `packages/hairline_core` (Dart murni, tanpa dependensi Flutter dan tanpa OpenCV) dan aplikasi Flutter di folder `app/` |
| State | Riverpod dengan code generation (`riverpod_annotation`, `riverpod_generator`, `build_runner`), `go_router` |
| Citra | `opencv_dart` HANYA untuk dekode JPEG, konversi abu-abu, ekstraksi patch, dan deteksi ArUco (`DICT_4X4_50`, refinement sub-pixel sudut). Seluruh geometri dan pengukuran ada di `hairline_core` |
| Kamera | paket `camera` (back camera, still resolution tertinggi, fokus dan eksposur dikunci lewat API paket, flash mati). Platform channel Android kecil hanya untuk membaca karakteristik lensa (focal length, ukuran sensor) |
| Lokal | Drift (SQLite) + `sqlite3_flutter_libs`; foto di penyimpanan privat aplikasi |
| PDF | paket `pdf` (vektor) + `printing` untuk cetak dan bagikan |
| Grafik | `CustomPaint` sendiri (batang ketidakpastian), tanpa paket grafik |
| Platform | Android, minSdk 24. Manifest rilis TIDAK mendeklarasikan `INTERNET` (debug boleh). Izin hanya `CAMERA` |
| Dependensi | Verifikasi koordinat dan versi terbaru yang stabil dari sumber resmi; jangan menebak. Jangan menambah paket di luar daftar tanpa catatan di DECISIONS.md |
| Lisensi | MIT |

## 5. Spesifikasi (wajib diikuti persis)

### 5.1 Geometri lembar bingkai
Sistem koordinat lembar (mm): titik asal di pusat jendela, x ke kanan, y ke bawah.
- Penanda `DICT_4X4_50`, sisi 30 mm (termasuk border hitam), pusat pada TL (-60,-60), TR (60,-60), BR (60,60), BL (-60,60). ID penanda untuk lembar bernomor `s` (0 sampai 11): `4s+0` TL, `4s+1` TR, `4s+2` BR, `4s+3` BL. Sudut tiap penanda dalam urutan OpenCV (TL, TR, BR, BL pada bingkai penanda itu sendiri): untuk pusat `c`, `(c.x-15,c.y-15)`, `(c.x+15,c.y-15)`, `(c.x+15,c.y+15)`, `(c.x-15,c.y+15)`.
- Jendela potong (cut-out) persegi 70 x 70 mm di pusat (batas +-35 mm); retak harus berada di dalamnya, titik ukur dalam 50 x 50 mm tengah. Sisi dalam penanda berjarak 45 mm dari pusat sehingga ada celah putih 10 mm antara garis potong dan penanda.
- Batang skala 100 mm dengan tanda ujung di bawah bingkai; garis potong putus-putus; label ID lembar. Ukuran halaman A4 dan Letter; cetak WAJIB 100 persen (tanpa "fit to page").
- Verifikasi skala cetak: pengguna mengukur batang skala dengan penggaris dan memasukkan hasilnya `L_ukur` (mm). `print_scale = L_ukur / 100`. Ketidakpastian pembacaan penggaris 0,5 mm (distribusi seragam, `u = 0,5/sqrt(3)` mm), sehingga `u_print_rel = (0,5/sqrt(3)) / L_ukur`. Semua dimensi lembar dikalikan `print_scale` saat membangun koordinat.
- Lembar ditempel permanen dan rata pada bidang yang sama dengan retak. Jika lembar bergeser atau dilepas, seri pengukuran retak itu terputus dan harus dimulai baru (UI menjelaskan).

### 5.2 Homografi dan diagnostik (`hairline_core`)
- Input: deteksi penanda (id, 4 sudut px). Terima >= 3 penanda (>= 12 titik); < 3 ditolak. Estimasi `H` lembar->citra dengan DLT ternormalisasi (Hartley) lalu penyempurnaan Levenberg-Marquardt yang meminimalkan galat reproyeksi dalam px; `H_inv` untuk citra->lembar. Implementasi dalam Dart murni (selesaikan sistem linear sendiri; tanpa dependensi aljabar linear berat kecuali dicatat).
- Diagnostik: `rms_px` (reproyeksi), `loo_mm` (leave-one-marker-out: bila 4 penanda terdeteksi, estimasi H tanpa satu penanda, prediksi sudutnya, RMS galat dalam mm di antara keempat putaran), skala lokal `mm_per_px` di titik ukur (dari Jacobian numerik `H_inv`), anisotropi skala (rasio skala sepanjang dua sumbu utama).
- Perkiraan kemiringan (tilt): dekomposisi homografi dengan intrinsik perkiraan (`fx=fy=f_px`, titik utama di tengah). `f_px` dari metadata lensa (`focal_mm / sensor_width_mm * lebar_px`, memperhatikan orientasi) atau default `0,75 x sisi_terpanjang_px`. Tandai `tilt_is_approx=true`. Tilt = sudut antara sumbu optik dan normal bidang.
- Deviasi pose terhadap pose referensi (kunjungan dasar): translasi pusat penanda (fraksi diagonal citra), rasio skala (akar rasio luas), selisih rotasi dalam bidang, selisih tilt. Ambang "siap ambil": translasi <= 3 persen, skala 0,9 sampai 1,1, rotasi <= 5 derajat, tilt <= 8 derajat. Keluaran instruksi enumerasi (`MOVE_LEFT`, `CLOSER`, `ROTATE_CW`, `HOLD_FLAT`, ...) yang dipetakan ke teks Indonesia di UI.

### 5.3 Model profil dan pengukuran (`hairline_core`)
Pengukuran bekerja pada patch abu-abu (`GrayPatch`: origin, lebar, tinggi, `Float32List`) yang diekstrak adapter, bukan pada seluruh citra.
- Terukur (measurand) didefinisikan eksplisit: lebar retak rata-rata sepanjang segmen 4 mm yang berpusat pada titik ukur, diukur tegak lurus garis tengah retak, dalam mm pada bidang lembar.
- Penjejakan: titik ukur disimpan dalam koordinat lembar (mm) beserta arah retak. Tiap kunjungan, proyeksikan titik ke citra lewat `H`, cari punggung retak terdekat dalam radius 1,5 mm (Hessian skala kecil), perbarui arah dengan menyesuaikan garis ke pusat profil.
- Profil: sampel intensitas tegak lurus arah retak dalam ruang metrik (`s` dalam mm, langkah `min(0,02 mm, 0,25 x mm_per_px)`, rentang +-3 mm), interpolasi bikubik Catmull-Rom dari patch lewat `H`. Ambil 40 profil sepanjang segmen 4 mm.
- Model: `I(s) = B + m*s - D*[Phi((s-c+w/2)/sigma) - Phi((s-c-w/2)/sigma)]`, `Phi` CDF normal baku, parameter bebas `B, m, D>=0, c, w>=0`, `sigma` (PSF Gaussian) tetap dari 5.3a. Penyesuaian Levenberg-Marquardt berbatas. Dua lintasan: (1) sesuaikan tiap profil untuk pusat `c_j` dan lebar `w_j`; (2) geser-sejajarkan profil berdasarkan `c_j`, rata-ratakan, sesuaikan sekali lagi untuk `w` akhir dan kovarians. Laporkan juga `w_j` per profil (median, simpangan sepanjang retak `along_sd`, kemiringan `dw/ds` sepanjang retak lewat OLS).
- Kovarians parameter `s2 * (J^T J)^-1` dengan `s2 = RSS/(n-p)`. Karena sampel interpolasi berkorelasi, kalikan varians dengan faktor inflasi `rho` yang dikalibrasi dari studi cakupan sintetis (target cakupan >= 90 persen pada `k=2`); catat `rho` terpilih dan buktinya di `docs/SYNTHETIC_VALIDATION.md`.
- Gerbang kontras: `D / sigma_noise >= 3` (derau dari residu); jika gagal, hasil `TIDAK_TERUKUR` (bukan angka).

5.3a PSF dari tepi penanda: ambil 8 profil tegak lurus tiap tepi luar penanda (lokasi tepi diketahui dari geometri), sesuaikan `I = a + b*Phi((s-s0)/sigma)` dengan `s0` bebas, ambil median `sigma` seluruh tepi (dalam mm) dan simpangan antar tepi sebagai `u_sigma_edge`. Catatan: tepi cetak kontras tinggi mungkin diproses berbeda dari retak berkontras rendah oleh pipeline foto ponsel; ini dikoreksi hanya lewat validasi pelat. Ketidakpastian lebar akibat `sigma` dihitung dengan menyesuaikan ulang pada `sigma +- u_sigma` dan mengambil setengah selisihnya (`u_sigma_w`).

### 5.4 Gerbang kualitas (nilai awal, dapat disetel, belum dituning di perangkat nyata; simpan sebagai konstanta `QualityThresholds` bernama dan terdokumentasi)
Frame diterima bila: penanda >= 3 (4 disarankan), `rms_px <= 0,8`, `loo_mm <= 0,3` (jika tersedia), tilt <= 20 derajat (tolak keras > 30), `mm_per_px <= 0,20` (target <= 0,10), `sigma_px <= 2,5`, rasio anisotropi blur <= 1,6, fraksi piksel jenuh di ROI <= 1 persen, kontras retak lolos. Kunjungan diterima bila >= 3 frame diterima; kurang dari itu: minta ulang, jangan menyimpan hasil sebagai pengukuran. Alasan penolakan ditampilkan spesifik ("terlalu buram", "terlalu miring", "penanda tertutup").

### 5.5 Agregasi dan anggaran ketidakpastian (semua dalam mm, ketidakpastian baku)
Lebar kunjungan `w` = median lebar per frame. Komponen:
- `u_stat = max(u_fit_mean, u_repeat)` dengan `u_fit_mean = sqrt(sum(u_fit_i^2))/n`, `u_repeat = s_w/sqrt(n)` (simpangan baku sampel lebar antar frame, n >= 3). Dipakai `max` agar tidak menghitung ganda.
- `u_sigma_w` (5.3a), `u_pos = |dw/ds| * max(rms_mm, 0,05)` dengan `rms_mm` galat posisi lembar (dari `loo_mm` atau `rms_px * mm_per_px`),
- `u_par = dz * |tan(tilt)| / sqrt(3)` dengan `dz` default 0,3 mm (relief permukaan; pilihan pengguna 0,3 atau 1,0 mm),
- `u_geo = w * sqrt(rms_mm^2 + loo_mm^2) / 120`.
- Sistematis bersama antar kunjungan: `u_print = w * u_print_rel`, `u_dev` = RMSE bias dari validasi `PERANGKAT` terbaru untuk model ponsel itu pada lebar yang sebanding; jika belum ada validasi, pakai `0,5 * mm_per_px` sebagai nilai awal KONSERVATIF TAK TERVALIDASI dan tandai hasil `BELUM_DIVALIDASI`.
- `u_rand^2 = u_stat^2 + u_sigma_w^2 + u_pos^2 + u_par^2 + u_geo^2`; `u_sys^2 = u_print^2 + u_dev^2`; `u_c = sqrt(u_rand^2 + u_sys^2)`.
- Ketidakpastian diperluas `U = k * u_c`, dengan `k` faktor cakupan 95 persen dari Welch-Satterthwaite (derajat kebebasan `u_stat` = n-1 bila komponen itu mendominasi; komponen lain tak hingga) dan tabel t Student (implementasi tabel di core; tanpa pustaka statistik).
- Batas pelaporan bawah: `floor = max(0,5 * mm_per_px, 2 * u_c)`. Jika `w < floor`, tampilkan "di bawah batas ukur (< floor mm)", bukan angka lebar. Selalu tampilkan juga `mm_per_px` dan label `BELUM_DIVALIDASI` bila berlaku.

### 5.6 Tren dan perubahan signifikan
Untuk kunjungan `i` dibanding dasar `0` (dan dibanding kunjungan sebelumnya): `delta = w_i - w_0`, `u_delta = sqrt(u_rand_i^2 + u_rand_0^2 + (delta * u_print_rel)^2)` (komponen sistematis bersama saling meniadakan). `z = delta / u_delta`. Klasifikasi: `|z| < 2` -> "tidak ada perubahan terdeteksi"; `z >= 2` -> "kemungkinan bertambah lebar"; `z <= -2` -> "kemungkinan menyempit". Tampilkan juga perubahan minimum yang dapat dideteksi `MDC = 2 * u_delta`. Kunjungan dengan hasil `TIDAK_TERUKUR` atau di bawah batas ukur tidak membentuk delta numerik (tampil sebagai "tidak terukur"). Tanpa regresi atau ekstrapolasi untuk <= 5 titik. Peringatkan bila model ponsel, versi algoritma, atau lembar berbeda antar kunjungan.

### 5.7 Data (Drift; semua timestamp UTC)
`sites(id,name,lat?,lon?,notes)`, `cracks(id,site_id,label,sheet_id,print_scale,print_scale_u_rel,relief_mm,created_at)`, `crack_points(id,crack_id,x_mm,y_mm,direction_deg)` (tepat satu per retak di MVP, ditegakkan di lapisan aplikasi), `visits(id,crack_id,ts_utc,kind,device_model,camera_info_json,reference_pose_json)`, `frames(id,visit_id,path,sha256,homography_json,rms_px,loo_mm,sigma_mm,tilt_deg,mm_per_px,quality_json,accepted)`, `measurements(id,visit_id,point_id,frame_id?,is_aggregate,algorithm_version,width_mm,u_rand,u_sys,u_expanded,k,components_json,status)`, `validation_runs(id,device_model,ts_utc,plate_truth_json,results_json,bias_mm,rmse_mm,coverage,algorithm_version,source)`. `algorithm_version` memungkinkan pemrosesan ulang foto lama tanpa menimpa hasil lama (baris baru). Simpan hanya frame yang diterima (maks 5) dan hapus sisanya setelah pemrosesan. Skema `alerts` dan `reports` TIDAK dibuat.

### 5.8 Privasi dan keamanan
Semua data lokal; tidak ada jaringan di rilis. Lokasi situs opsional dan tidak diminta sebagai izin runtime (diketik pengguna). Foto di penyimpanan privat aplikasi; ekspor hanya lewat aksi pengguna. Impor CSV kebenaran pelat divalidasi ketat (ukuran, baris, rentang nilai).

## 6. Aturan kerja agent

1. **Kerjakan, jangan hanya menyarankan.** Tulis kode, jalankan build dan test, perbaiki.
2. **Jangan bertanya ke pengguna** kecuali blocker mutlak. Untuk ambiguitas, ambil keputusan paling masuk akal sesuai dokumen ini, catat di `docs/DECISIONS.md` (tanggal, masalah, keputusan, alasan), lanjutkan.
3. **Hanya fase yang sedang diperintahkan.** Jangan mengerjakan fase lain lebih awal dan jangan menambah fitur di luar scope.
4. **Test-first untuk `hairline_core`.** Test numerik memakai seed tetap, toleransi eksplisit dengan alasan, dan data sintetis dengan kebenaran dasar diketahui persis.
5. **Verifikasi nyata.** Perintah standar disimpan di `make verify`:
   `(cd packages/hairline_core && dart analyze --fatal-infos && dart test --coverage) && (cd app && dart run build_runner build --delete-conflicting-outputs && flutter analyze && flutter test)`
   Tempel ringkasan hasil nyata di laporan akhir fase. Dilarang menulis "lulus" tanpa menjalankannya.
6. **Perbaiki semua temuan** (error, test gagal, analyzer, warning relevan) sebelum menutup fase; jalankan ulang verifikasi hingga bersih. Jika masalah gagal diperbaiki setelah 3 percobaan berbeda, tulis akar masalah dan opsi di `docs/BLOCKERS.md`, lanjut ke bagian lain.
7. **Status jujur.** Setiap butir hanya boleh: `SELESAI-TERVERIFIKASI` (ada test/build yang dijalankan), `TERVERIFIKASI-SINTETIS` (akurasi/perilaku terbukti pada data simulasi saja), `SELESAI-PERLU-UJI-PERANGKAT` (kode dan test ditulis, butuh ponsel Android nyata, kamera, atau validasi pelat), `BELUM`. Agent tidak punya ponsel, kamera, atau pelat cetak nyata; tidak boleh mengklaim akurasi atau perilaku kamera nyata sebagai terbukti.
8. **Cek toolchain lebih dulu.** Flutter, Dart, Android SDK, dan `opencv_dart` (pustaka native) mungkin tidak dapat dipasang atau dijalankan di lingkungan agent. Jika tidak bisa, tulis seluruh kode dan test, tandai "ditulis, belum dijalankan", catat penyebab pasti di BLOCKERS.md. Bagian inti Dart murni harus tetap dapat diuji sendiri.
9. **Angka hanya dari pengukuran nyata.** Setiap angka akurasi, kinerja, atau cakupan di dokumen berasal dari proses yang benar-benar dijalankan (catat seed, parameter, versi). Jangan mengekstrapolasi atau menebak.
10. **Kualitas kode.** Tanpa kode mati, tanpa `dynamic` tak perlu, tanpa `print` di produksi, null-safety ketat, semua I/O async, kerja berat di isolate (tidak di thread UI), pembuangan sumber daya kamera dan Mat yang benar (tanpa kebocoran native), pesan galat bagi pengguna dalam Bahasa Indonesia dan spesifik.
11. **Hemat konteks.** Baca file relevan saja, ringkas log panjang.

## 7. Protokol progres

`docs/PROGRESS.md` adalah memori antar sesi: tabel fase 1-9 dengan status; daftar butir Wajib 1-8 dengan status jujur (aturan 7) dan lokasi kode/test; "Konteks untuk sesi berikutnya" maksimal 15 baris. Perbarui di akhir setiap fase dan commit bersama kode.

## 8. Definition of Done global

Sebuah fase selesai hanya jika: DoD fase terpenuhi; verifikasi standar bersih (atau kendala toolchain dicatat jujur di BLOCKERS.md); tidak ada perubahan di luar scope lock; `PROGRESS.md` dan `DECISIONS.md` diperbarui dan commit dibuat sesuai aturan repo; laporan akhir fase (maks 25 baris): apa yang dibuat, hasil verifikasi nyata, status per butir, masalah terbuka.
