# Validasi sintetis (SINTETIS)

Label: **SINTETIS**. Semua angka di dokumen ini dihasilkan oleh `packages/hairline_core/tool/run_synthetic_study.dart` (seed tetap 20261117, algoritma `p3-1`, core `0.5.0`). Tidak ada ponsel, kamera, atau pelat cetak nyata. Hasil membuktikan perilaku pada simulasi saja; akurasi dan cakupan pada perangkat nyata BELUM terbukti (butuh validasi pelat `PERANGKAT`).

## 1. Desain studi

- Grid penuh: lebar {0,1; 0,2; 0,3; 0,5; 1,0; 2,0} mm x mm/px {0,04; 0,06; 0,10; 0,15} x sigma blur {0,6; 1,0; 1,5; 2,0} px x derau {1; 3; 6} tingkat abu-abu 8 bit (sd) x tilt {0; 10; 20} derajat = 864 kondisi.
- Replikasi: 5 kunjungan per kondisi untuk kalibrasi (replikasi 0 sampai 4), ditambah 1 replikasi hold-out (tidak dipakai memilih `rho`), tiap kunjungan 5 frame (burst), total 4320 kunjungan dan 21600 frame. Pose acak per kunjungan (azimut tilt 0..360, roll +-20 derajat, geser +-10 mm, f 0,7..0,9 sisi panjang), derau sudut penanda 0,2 px, arah retak acak (hindari sumbu piksel), arah tersimpan meleset U(-3, 3) derajat, retak menyimpang U(-0,3, 0,3) mm dari titik tersimpan. Kontras retak: kedalaman 0,4 dari latar 0,8 (82 tingkat abu-abu). Skala mm/px adalah skala geometrik di titik ukur.
- Rantai nyata: deteksi sudut berderau -> homografi (DLT + LM) -> estimasi tilt (f_px bawaan 0,75 x sisi panjang, sedangkan f sebenarnya 0,7..0,9) -> gerbang geometri 5.4 -> render patch retak (supersample 4, PSF, derau, kuantisasi 8 bit) -> PSF dari tepi penanda (patch penanda terpisah 0,25 mm/px dengan blur, derau, dan sudut pandang yang sama) -> `measureFrame` -> `aggregateVisit` (median, anggaran 5.5).
- Anggaran: `u_print_rel = 0` (tidak ada galat cetak), `dz = 0,3 mm`, tanpa validasi perangkat sehingga `u_dev = 0,5 mm/px` (BELUM_DIVALIDASI). Ketidakpastian kebenaran `u_truth`: renderer tidak eksak, tiap sampel tepi meleset paling banyak 0,5/S px (S = 4, D18); dianggap seragam, dua tepi per lebar: `u_truth = sqrt(2) x 0,5 / (4 sqrt(3)) = 0,1021 px x mm/px` (0,004 sampai 0,015 mm). Interval gabungan `k sqrt(u_c^2 + u_truth^2)`, persis seperti pelat bersertifikat; kolom "ketat" memakai `u_truth = 0`.
- Terukur dihitung hanya pada kunjungan yang dilaporkan aplikasi (status TERUKUR). Galat = terukur - kebenaran. Cakupan = fraksi kunjungan dengan |galat| <= U.
- Tiga tingkat cakupan: **fit** = `k sqrt(u_stat^2 + u_sigma_w^2)` (bagian yang diinflasi `rho`; dipakai untuk kalibrasi), **acak** = `U` dengan `u_dev = u_print = 0` (menambah `u_pos`, `u_par`, `u_geo`; `u_par` mengandaikan relief 0,3 mm yang tidak ada di adegan sintetis, jadi konservatif), **bawaan** = `U` anggaran lengkap yang dilihat pengguna.
- Keterbatasan simulasi: frame dalam satu burst berbagi pose dan render bebas-derau (getaran tangan tidak disimulasikan, sehingga `u_repeat` bisa terlalu kecil dibanding burst nyata; pose berbeda antar kunjungan, jadi cakupan antar kunjungan tetap melihat efeknya); PSF diestimasi dari patch penanda dengan homografi sebenarnya patch itu; kernel render Gaussian dikonvolusi apertur kotak, sedangkan ponsel nyata punya penajaman ISP dan JPEG.

## 2. Kalibrasi `rho`

Kriteria: cakupan fit gabungan >= 90 persen DAN tidak ada kondisi yang secara statistik di bawah 90 persen (batas atas interval Wilson 95 persen < 90 persen). Kondisi yang titik estimasinya di bawah 90 persen tetapi tidak signifikan (misalnya 7 dari 8) dihitung terpisah.

| rho | cakupan fit (%) | fit ketat u_truth=0 (%) | cakupan acak (%) | cakupan bawaan (%) | kondisi < 90% (titik) | kondisi < 90% (signifikan) | kondisi < 90% (signifikan, ketat) |
|---|---|---|---|---|---|---|---|
| 1.0 | 100.0 | 98.7 | 100.0 | 100.0 | 0 | 0 | 5 |
| 1.5 | 100.0 | 98.8 | 100.0 | 100.0 | 0 | 0 | 4 |
| 2.0 | 100.0 | 98.9 | 100.0 | 100.0 | 0 | 0 | 3 |
| 3.0 | 100.0 | 99.0 | 100.0 | 100.0 | 0 | 0 | 3 |
| 4.0 | 100.0 | 99.3 | 100.0 | 100.0 | 0 | 0 | 2 |
| 6.0 | 100.0 | 99.5 | 100.0 | 100.0 | 0 | 0 | 2 |
| 8.0 | 100.0 | 99.6 | 100.0 | 100.0 | 0 | 0 | 2 |
| 12.0 | 100.0 | 99.6 | 100.0 | 100.0 | 0 | 0 | 1 |
| 16.0 | 100.0 | 99.7 | 100.0 | 100.0 | 0 | 0 | 1 |
| 24.0 | 100.0 | 99.8 | 100.0 | 100.0 | 0 | 0 | 1 |
| 32.0 | 100.0 | 99.9 | 100.0 | 100.0 | 0 | 0 | 1 |
| 48.0 | 100.0 | 99.9 | 100.0 | 100.0 | 0 | 0 | 1 |
| 64.0 | 100.0 | 99.9 | 100.0 | 100.0 | 0 | 0 | 0 |


**`rho` terpilih = 1.0** (nilai terkecil yang memenuhi kriteria; kriteria memakai `u_truth` renderer). Nilai sebelumnya `rho = 1,0` tidak dikalibrasi; kini dikalibrasi terhadap simulasi dan tetap 1,0. Kolom ketat (`u_truth = 0`) menunjukkan sisanya: sel lebar 2,0 mm yang galat sebenarnya hanya beberapa um sampai 0,15 px; lihat bagian 6 dan percobaan renderer.

## 3. Cakupan sebelum dan sesudah kalibrasi

Per lebar, semua kondisi lain dipool (kunjungan TERUKUR). Sebelum: `rho = 1`. Sesudah: `rho = 1.0`. Kolom "pada U/2" mengukur kekonservatifan: bila cakupan fit pada setengah lebar interval masih tinggi, interval lebih dari dua kali lebih lebar daripada yang dibutuhkan (konservatif, tetapi mengurangi daya deteksi tren).

| lebar (mm) | TERUKUR | fit sebelum (%) | fit sesudah (%) | fit ketat sebelum (%) | fit ketat sesudah (%) | fit sesudah pada U/2 (%) | acak sebelum (%) | acak sesudah (%) | bawaan sebelum (%) | bawaan sesudah (%) |
|---|---|---|---|---|---|---|---|---|---|---|
| 0.1 | 106 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 |
| 0.2 | 431 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 |
| 0.3 | 556 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 |
| 0.5 | 667 | 100.0 | 100.0 | 99.7 | 99.7 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 |
| 1.0 | 656 | 100.0 | 100.0 | 99.1 | 99.1 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 |
| 2.0 | 664 | 100.0 | 100.0 | 95.3 | 95.3 | 99.5 | 100.0 | 100.0 | 100.0 | 100.0 |
| **semua** | 3080 | 100.0 | 100.0 | 98.7 | 98.7 | 99.9 | 100.0 | 100.0 | 100.0 | 100.0 |


Kekonservatifan: persentil ke-95 dari `|galat| / U` per lebar (nilai 1,0 berarti tepat 95 persen cakupan; makin kecil makin lebar intervalnya dibanding galat yang terjadi). "fit ketat" memakai interval fit tanpa `u_truth`; "bawaan" memakai `U` anggaran lengkap dengan `u_truth`.

| lebar (mm) | p95 galat/U fit ketat | p95 galat/U bawaan | median galat/U bawaan |
|---|---|---|---|
| 0.1 | 0.177 | 0.079 | 0.021 |
| 0.2 | 0.198 | 0.085 | 0.010 |
| 0.3 | 0.212 | 0.058 | 0.009 |
| 0.5 | 0.299 | 0.044 | 0.007 |
| 1.0 | 0.625 | 0.032 | 0.005 |
| 2.0 | 0.976 | 0.029 | 0.005 |
| **semua** | 0.587 | 0.050 | 0.007 |


### Hold-out (replikasi tidak dipakai untuk kalibrasi)

1 replikasi x 864 kondisi, seed yang berbeda dari kalibrasi (replikasi >= 5). `rho` tetap 1.0.

| lebar (mm) | TERUKUR | fit rho=1 (%) | fit rho=1.0 (%) | fit pada U/2 (%) | acak (%) | bawaan (%) |
|---|---|---|---|---|---|---|
| 0.1 | 22 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 |
| 0.2 | 88 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 |
| 0.3 | 111 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 |
| 0.5 | 131 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 |
| 1.0 | 132 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 |
| 2.0 | 132 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 |
| **semua** | 616 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 |


Kondisi hold-out yang signifikan di bawah 90 persen (fit): 0; titik estimasi di bawah 90 persen: 0.


Per skala (mm/px):

| mm/px | TERUKUR | fit sebelum (%) | fit sesudah (%) | acak sesudah (%) | bawaan sesudah (%) |
|---|---|---|---|---|---|
| 0.04 | 897 | 100.0 | 100.0 | 100.0 | 100.0 |
| 0.06 | 850 | 100.0 | 100.0 | 100.0 | 100.0 |
| 0.1 | 721 | 100.0 | 100.0 | 100.0 | 100.0 |
| 0.15 | 612 | 100.0 | 100.0 | 100.0 | 100.0 |


## 4. Bias, RMSE, cakupan dan batas ukur pada `rho = 1.0`

Kolom `U median` dan `batas ukur median` adalah median antar sel dari median per sel. Status dihitung atas semua kunjungan; bias, RMSE, cakupan atas kunjungan TERUKUR.

### 4.1 Lebar x skala

| kelompok | kunjungan | TERUKUR | DI_BAWAH | TIDAK_TERUKUR | DITOLAK | bias (um) | RMSE (um) | cakupan fit (%) | cakupan acak (%) | cakupan bawaan (%) | U median (um) | batas ukur median (um) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0.1 mm, 0.04 mm/px | 180 | 75 | 85 | 0 | 20 | 0.8 | 1.9 | 100.0 | 100.0 | 100.0 | 70.1 | 114.2 |
| 0.1 mm, 0.06 mm/px | 180 | 31 | 139 | 0 | 10 | 3.5 | 4.1 | 100.0 | 100.0 | 100.0 | 84.3 | 149.0 |
| 0.1 mm, 0.1 mm/px | 180 | 0 | 147 | 13 | 20 | - | - | - | - | - | - | 212.3 |
| 0.1 mm, 0.15 mm/px | 180 | 0 | 134 | 31 | 15 | - | - | - | - | - | - | 290.0 |
| 0.2 mm, 0.04 mm/px | 180 | 162 | 0 | 0 | 18 | 0.3 | 1.3 | 100.0 | 100.0 | 100.0 | 72.4 | 73.9 |
| 0.2 mm, 0.06 mm/px | 180 | 152 | 9 | 0 | 19 | 1.1 | 2.8 | 100.0 | 100.0 | 100.0 | 115.3 | 118.2 |
| 0.2 mm, 0.1 mm/px | 180 | 86 | 83 | 0 | 11 | 4.8 | 6.9 | 100.0 | 100.0 | 100.0 | 151.0 | 233.4 |
| 0.2 mm, 0.15 mm/px | 180 | 31 | 130 | 0 | 19 | 17.5 | 18.9 | 100.0 | 100.0 | 100.0 | 189.3 | 341.4 |
| 0.3 mm, 0.04 mm/px | 180 | 173 | 0 | 0 | 7 | 0.1 | 0.9 | 100.0 | 100.0 | 100.0 | 70.2 | 71.6 |
| 0.3 mm, 0.06 mm/px | 180 | 167 | 0 | 0 | 13 | 0.2 | 1.6 | 100.0 | 100.0 | 100.0 | 105.2 | 107.4 |
| 0.3 mm, 0.1 mm/px | 180 | 131 | 34 | 0 | 15 | 2.4 | 6.4 | 100.0 | 100.0 | 100.0 | 158.9 | 191.0 |
| 0.3 mm, 0.15 mm/px | 180 | 85 | 82 | 0 | 13 | 6.3 | 9.1 | 100.0 | 100.0 | 100.0 | 221.2 | 346.0 |
| 0.5 mm, 0.04 mm/px | 180 | 163 | 0 | 0 | 17 | -0.0 | 0.5 | 100.0 | 100.0 | 100.0 | 69.5 | 70.9 |
| 0.5 mm, 0.06 mm/px | 180 | 166 | 0 | 0 | 14 | -0.0 | 0.9 | 100.0 | 100.0 | 100.0 | 83.1 | 84.8 |
| 0.5 mm, 0.1 mm/px | 180 | 170 | 0 | 0 | 10 | 0.3 | 3.1 | 100.0 | 100.0 | 100.0 | 143.4 | 146.3 |
| 0.5 mm, 0.15 mm/px | 180 | 168 | 0 | 0 | 12 | 1.4 | 9.5 | 100.0 | 100.0 | 100.0 | 249.6 | 254.7 |
| 1.0 mm, 0.04 mm/px | 180 | 162 | 0 | 0 | 18 | 0.1 | 0.5 | 100.0 | 100.0 | 100.0 | 69.0 | 70.4 |
| 1.0 mm, 0.06 mm/px | 180 | 171 | 0 | 0 | 9 | -0.0 | 0.8 | 100.0 | 100.0 | 100.0 | 83.2 | 84.9 |
| 1.0 mm, 0.1 mm/px | 180 | 162 | 0 | 0 | 18 | 0.0 | 1.7 | 100.0 | 100.0 | 100.0 | 115.0 | 117.4 |
| 1.0 mm, 0.15 mm/px | 180 | 161 | 0 | 0 | 19 | 0.4 | 4.1 | 100.0 | 100.0 | 100.0 | 181.4 | 185.1 |
| 2.0 mm, 0.04 mm/px | 180 | 162 | 0 | 0 | 18 | 0.0 | 0.5 | 100.0 | 100.0 | 100.0 | 66.9 | 68.3 |
| 2.0 mm, 0.06 mm/px | 180 | 163 | 0 | 0 | 17 | 0.1 | 0.8 | 100.0 | 100.0 | 100.0 | 80.9 | 82.5 |
| 2.0 mm, 0.1 mm/px | 180 | 172 | 0 | 0 | 8 | -0.2 | 1.5 | 100.0 | 100.0 | 100.0 | 113.2 | 115.6 |
| 2.0 mm, 0.15 mm/px | 180 | 167 | 0 | 0 | 13 | 0.0 | 3.8 | 100.0 | 100.0 | 100.0 | 158.4 | 161.6 |


### 4.2 Sigma blur

| kelompok | kunjungan | TERUKUR | DI_BAWAH | TIDAK_TERUKUR | DITOLAK | bias (um) | RMSE (um) | cakupan fit (%) | cakupan acak (%) | cakupan bawaan (%) | U median (um) | batas ukur median (um) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0.6 px | 1080 | 886 | 113 | 0 | 81 | 0.9 | 4.1 | 100.0 | 100.0 | 100.0 | 114.3 | 121.2 |
| 1.0 px | 1080 | 825 | 172 | 0 | 83 | 1.1 | 3.9 | 100.0 | 100.0 | 100.0 | 115.7 | 124.3 |
| 1.5 px | 1080 | 713 | 262 | 15 | 90 | 0.5 | 3.5 | 100.0 | 100.0 | 100.0 | 116.2 | 133.6 |
| 2.0 px | 1080 | 656 | 296 | 29 | 99 | 0.7 | 5.2 | 100.0 | 100.0 | 100.0 | 120.1 | 156.4 |


### 4.3 Derau

| kelompok | kunjungan | TERUKUR | DI_BAWAH | TIDAK_TERUKUR | DITOLAK | bias (um) | RMSE (um) | cakupan fit (%) | cakupan acak (%) | cakupan bawaan (%) | U median (um) | batas ukur median (um) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 tingkat | 1440 | 1013 | 296 | 2 | 129 | 0.7 | 2.4 | 100.0 | 100.0 | 100.0 | 116.3 | 129.9 |
| 3 tingkat | 1440 | 1031 | 297 | 0 | 112 | 0.8 | 3.8 | 100.0 | 100.0 | 100.0 | 115.8 | 129.5 |
| 6 tingkat | 1440 | 1036 | 250 | 42 | 112 | 1.0 | 5.6 | 100.0 | 100.0 | 100.0 | 116.9 | 128.2 |


### 4.4 Tilt sebenarnya

| kelompok | kunjungan | TERUKUR | DI_BAWAH | TIDAK_TERUKUR | DITOLAK | bias (um) | RMSE (um) | cakupan fit (%) | cakupan acak (%) | cakupan bawaan (%) | U median (um) | batas ukur median (um) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 derajat | 1440 | 1145 | 279 | 16 | 0 | 0.9 | 4.3 | 100.0 | 100.0 | 100.0 | 70.1 | 100.3 |
| 10 derajat | 1440 | 1124 | 301 | 15 | 0 | 0.8 | 4.1 | 100.0 | 100.0 | 100.0 | 87.9 | 116.6 |
| 20 derajat | 1440 | 811 | 263 | 13 | 353 | 0.8 | 4.1 | 100.0 | 100.0 | 100.0 | 133.4 | 153.7 |


Tabel lengkap per kondisi (864 baris): `docs/SYNTHETIC_VALIDATION_CONDITIONS.csv`.

## 5. Batas ukur

Batas bawah empiris per setelan (skala, blur, derau, tilt): lebar terkecil yang diuji sehingga kunjungan pada lebar itu dan semua lebar yang lebih besar andal (>= 90 persen dilaporkan, cakupan >= 90 persen, `U` lebih kecil dari lebarnya). Sel "tidak ada" berarti bahkan 2,0 mm tidak andal pada setelan itu. Kunjungan DITOLAK gerbang dikeluarkan (pengguna mengulang). Aplikasi sendiri memakai batas pelaporan 5.5 `max(0,5 mm/px, 2 u_c)`; kolom terakhir adalah median batas itu.

| mm/px | sigma (px) | setelan | batas empiris min (mm) | median (mm) | maks (mm) | setelan tanpa batas | batas 5.5 median (um) |
|---|---|---|---|---|---|---|---|
| 0.04 | 0.6 | 9 | 0,10 | 0,10 | 0,20 | 0 | 71.5 |
| 0.04 | 1.0 | 9 | 0,10 | 0,10 | 0,20 | 0 | 70.0 |
| 0.04 | 1.5 | 9 | 0,10 | 0,20 | 0,20 | 0 | 73.9 |
| 0.04 | 2.0 | 9 | 0,20 | 0,20 | 0,20 | 0 | 89.5 |
| 0.06 | 0.6 | 9 | 0,10 | 0,10 | 0,20 | 0 | 83.4 |
| 0.06 | 1.0 | 9 | 0,20 | 0,20 | 0,20 | 0 | 87.0 |
| 0.06 | 1.5 | 9 | 0,20 | 0,20 | 0,20 | 0 | 103.2 |
| 0.06 | 2.0 | 9 | 0,20 | 0,20 | 0,30 | 0 | 126.4 |
| 0.1 | 0.6 | 9 | 0,20 | 0,20 | 0,20 | 0 | 121.2 |
| 0.1 | 1.0 | 9 | 0,20 | 0,20 | 0,20 | 0 | 151.4 |
| 0.1 | 1.5 | 9 | 0,30 | 0,30 | 0,30 | 0 | 191.0 |
| 0.1 | 2.0 | 9 | 0,50 | 0,50 | 0,50 | 0 | 213.4 |
| 0.15 | 0.6 | 9 | 0,20 | 0,20 | 0,30 | 0 | 185.4 |
| 0.15 | 1.0 | 9 | 0,30 | 0,30 | 0,30 | 0 | 225.7 |
| 0.15 | 1.5 | 9 | 0,50 | 0,50 | 0,50 | 0 | 277.3 |
| 0.15 | 2.0 | 9 | 0,50 | 0,50 | 0,50 | 0 | 437.8 |


### Alasan penolakan frame (set kalibrasi)

Dari 21600 frame, 19839 diterima (91.8 persen). Alasan penolakan (satu frame bisa punya beberapa):

| kode | frame |
|---|---|
| TILT_TOO_HIGH | 1761 |


Tilt 20 derajat sebenarnya sering ditolak karena `f_px` bawaan meleset (tilt terestimasi sampai 4 derajat dari nilai benar, D17); itu perilaku gerbang 5.4 yang diharapkan.


## 6. Kondisi tidak andal

Dari 668 kondisi yang punya kunjungan TERUKUR:

- Interval yang dilihat pengguna (`U` bawaan dengan `u_truth`): **0** kondisi di bawah 90 persen secara signifikan; cakupan bawaan gabungan 100.0 persen.
- Interval fit dengan `u_truth` renderer: **0** kondisi signifikan di bawah 90 persen (Wilson 95 persen); 0 kondisi dengan titik estimasi di bawah 90 persen karena galat sampling (5 replikasi).
- Interval fit dengan kebenaran dianggap eksak (`u_truth = 0`): **5** kondisi signifikan di bawah 90 persen:

| lebar | mm/px | sigma | derau | tilt | TERUKUR | tercakup (ketat) | RMSE (um) | U bawaan median (um) | cakupan bawaan (%) |
|---|---|---|---|---|---|---|---|---|---|
| 2.0 | 0.1 | 0.6 | 3 | 0 | 5 | 3 | 1.1 | 98.0 | 100.0 |
| 2.0 | 0.15 | 0.6 | 3 | 0 | 5 | 3 | 7.6 | 147.1 | 100.0 |
| 2.0 | 0.15 | 1.0 | 6 | 0 | 5 | 3 | 13.4 | 147.2 | 100.0 |
| 2.0 | 0.06 | 0.6 | 1 | 10 | 5 | 3 | 0.6 | 79.8 | 100.0 |
| 2.0 | 0.04 | 1.5 | 3 | 10 | 5 | 3 | 0.6 | 66.3 | 100.0 |


Penyebab kondisi ketat itu: galat absolut hanya beberapa um sampai sekitar 0,15 px, sama besar dengan resolusi renderer (setiap sampel tepi meleset paling banyak 0,5/S px). Percobaan (`renderer-check`, derau acak sama, hanya supersample S yang berubah):

| lebar (mm) | mm/px | sigma (px) | derau | S | galat replikasi 0..4 (um) | RMS (um) |
|---|---|---|---|---|---|---|
| 2.0 | 0.15 | 0.6 | 3 | 4 | -1.1 -1.5 -0.6 -3.1 16.7 | 7.6 |
| 2.0 | 0.15 | 0.6 | 3 | 8 | -1.5 -1.1 -0.3 -2.4 -2.0 | 1.6 |
| 2.0 | 0.15 | 1.0 | 6 | 4 | -17.5 23.1 -1.6 -5.7 -4.4 | 13.4 |
| 2.0 | 0.15 | 1.0 | 6 | 8 | -9.1 -0.3 -1.4 -5.6 -4.3 | 5.2 |

Galat turun nyata saat S dinaikkan, jadi kekurangan cakupan ketat di sini adalah resolusi simulator, bukan ketidakjujuran `u_fit` algoritma; `rho > 1` tidak dipilih karena hanya akan mengejar artefak itu (kalibrasi menuju cakupan ketat pada semua kondisi butuh `rho` 64.0, yaitu `u_fit` 8.0 kali lebih besar untuk semua retak, dan memperlebar interval retak sempit tanpa alasan). Tidak ada kondisi yang perlu ditolak gerbang karena ketidakandalannya: interval yang dilaporkan menutup kebenaran. Kondisi yang memang tidak dilaporkan (di bawah batas ukur, TIDAK_TERUKUR, ditolak) terlihat pada status di bagian 4.


## 7. Tingkat positif palsu tren (rantai penuh, tanpa perubahan nyata)

Dua kunjungan independen dari kondisi yang sama (replikasi 0 dengan 1, 2 dengan 3, ...), keduanya TERUKUR, dibandingkan lewat `computeTrend` dengan `u_print_rel = 0` pada k = 2. Ekspektasi bila `u_rand` jujur dan galat normal: 4,55 persen. Tilt dipisah karena `u_par = dz tan(tilt)/sqrt(3)` (relief 0,3 mm yang tidak ada di adegan sintetis) mendominasi `u_rand` saat tilt > 0 sehingga angka itu konservatif secara konstruksi; tilt 0 adalah uji yang paling jujur untuk `u_rand`.

| tilt | pasangan | positif | positif palsu (%) | Wilson 95% (%) | sd(z) |
|---|---|---|---|---|---|
| 0 derajat | 456 | 1 | 0.2 | 0.0 sampai 1.2 | 0.515 |
| 10 derajat | 448 | 0 | 0.0 | 0.0 sampai 0.9 | 0.055 |
| 20 derajat | 246 | 0 | 0.0 | 0.0 sampai 1.5 | 0.038 |
| **semua** | 1150 | 1 | 0.1 | 0.0 sampai 0.5 | 0.326 |

sd(z) adalah simpangan baku z antar pasangan; untuk `u_delta` yang tepat nilainya 1,0. Nilai jauh di bawah 1 berarti `u_rand` (dan `MDC = 2 u_delta`) lebih besar daripada sebaran nyata antar kunjungan: tren jarang memberi alarm palsu tetapi perubahan kecil yang sebenarnya terdeteksi hanya bila melebihi MDC yang membengkak itu. `u_sigma_w` (bentuk kernel, 10 persen) bersifat sistematis antar kunjungan di kondisi yang sama tetapi masuk `u_rand` menurut 5.5.

## 8. Apakah "kejujuran ketidakpastian" didukung data?

**Didukung (SINTETIS): interval yang dilaporkan tidak optimistis.** `U` bawaan menutup kebenaran pada 100.0 persen dari 3080 kunjungan TERUKUR (kalibrasi) dan 100.0 persen dari 616 kunjungan hold-out; tidak ada kondisi yang signifikan di bawah 90 persen. Lebar yang tidak bisa dibuktikan dilaporkan sebagai "di bawah batas ukur" atau "tidak terukur", bukan angka.

**Tidak didukung: bahwa interval itu tepat (terkalibrasi).** Persentil ke-95 dari `|galat| / U` hanya 0.050, jadi `U` kira-kira 20 kali lebih lebar daripada galat yang terjadi pada cakupan 95 persen; pada tilt 0 `u_delta` tren sekitar 1.9 kali sebaran nyata antar kunjungan, dan pada tilt 10 sampai 20 derajat jauh lebih lebar karena `u_par` mengandaikan relief 0,3 mm. Cakupan 100 persen pada interval 95 persen berarti klaim "95 persen" terlalu hati-hati, bukan tepat. Penyebabnya nilai bawaan yang sengaja konservatif dan tak tervalidasi (`u_dev = 0,5 mm/px`, `dz = 0,3 mm`); hanya validasi pelat `PERANGKAT` yang dapat mengecilkannya dengan dasar. Satu-satunya komponen yang mendekati tepat adalah interval fit untuk retak lebar (2,0 mm: persentil ke-95 `|galat|/U` fit ketat mendekati 1).

**Tidak diuji:** ponsel, optik, ISP, JPEG, pelat cetak nyata, relief, galat cetak, model ponsel berbeda. Cakupan di perangkat nyata BELUM terbukti.

## 9. Yang tidak dibuktikan

- Perilaku pada ponsel, optik, ISP, JPEG, dan pelat cetak nyata. `u_dev` bawaan (0,5 mm/px) tetap TAK TERVALIDASI.
- Relief permukaan, galat cetak, dan perbedaan model ponsel (tidak disimulasikan).
- Cakupan sampai batas statistik: dengan 5 replikasi per kondisi, cakupan per kondisi hanya diketahui kasar; kesimpulan utama ada pada cakupan gabungan dan per kelompok.

