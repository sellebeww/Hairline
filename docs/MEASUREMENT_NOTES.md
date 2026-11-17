# Catatan pengukuran lebar retak (Fase 3)

Dokumen ini menjelaskan model, asumsi, batas, dan hasil sapuan pengukuran lebar retak di `packages/hairline_core`. Semua angka berlabel **SINTETIS**: berasal dari citra simulasi dengan kebenaran dasar yang diketahui (harness Fase 2), dihasilkan oleh `tool/measurement_sweep.dart` dengan seed tetap. Tidak ada angka **PERANGKAT**: belum ada foto ponsel nyata atau pelat validasi. Semua yang dikatakan di sini tentang perilaku kamera nyata adalah dugaan, bukan bukti.

Status butir Wajib 4 (bagian inti): **TERVERIFIKASI-SINTETIS**. Tanpa validasi perangkat, tidak satu pun angka galat di bawah boleh dikutip sebagai akurasi aplikasi.

Konvensi tabel: bias, sd, rms, `u_frame` dalam mikrometer (um) pada 0,06 mm/px; "6 seed" kecuali dinyatakan; `coverage` = fraksi frame dengan `|galat| <= 2 u_frame`; `misfit rel` = bagian sistematis residu akhir dibagi kedalaman lembah (dasar peringatan `MODEL_MISFIT`, ambang 1 persen). `u_frame = sqrt(u_fit^2 + u_sigma_w^2)` adalah bagian anggaran 5.5 yang dapat dihitung dari satu frame; komponen posisi, paralaks, geometri, dan sistematis menyusul di fase agregasi.

## 1. Model

**Terukur**: lebar retak rata-rata sepanjang segmen 4 mm yang berpusat pada titik ukur, tegak lurus garis tengah retak, dalam mm pada bidang lembar.

**Alur satu frame** (`measure.dart`): validasi masukan, PSF dari tepi penanda (`psf.dart`), gerbang blur/anisotropi/jenuh, pencarian punggung retak dalam radius 1,5 mm (`ridge.dart`), dua lintasan profil (`profile_fit.dart`), status.

**Profil** (`patch.dart`): 40 profil sepanjang segmen, tiap profil rentang +-3 mm tegak lurus retak, langkah `min(0,02 mm, 0,25 x mm/px)`, sampel bikubik Catmull-Rom dari patch lewat `H` (seragam dalam mm di bidang lembar, bukan piksel).

**Model**: `I(s) = B + m s - D [Phi((s-c+w/2)/sigma) - Phi((s-c-w/2)/sigma)]`. Bebas: `B, m, D in [0, latar], c in +-1,5 mm, w in [0, 3 mm]`. `sigma` tetap dari PSF.

**PSF** (`psf.dart`): `I = a + b Phi((s-s0)/sigma)` pada 8 profil per tepi luar penanda, median lintas tepi, `u_sigma_edge` = simpangan antar tepi. `sigma` adalah kernel semu (lensa + ISP + apertur piksel, varians 1/12 px^2); untuk PSF Gaussian `sigma_g` nilainya sekitar `sqrt(sigma_g^2 + 1/12)`. Isotropik di piksel; diubah ke mm dengan skala sepanjang normal retak (D20).

**Dua lintasan**: (1) tiap profil disesuaikan untuk `c_j`, `w_j`; (2) profil disampel ulang sejajar pada kurva kuadrat robust melalui `c_j`, dirata-ratakan, disesuaikan sekali untuk `w`, `c`, kovarians `rho s2 (J^T J)^-1`. Keluaran tambahan: `w_j`, `along_sd`, `dw/ds` (OLS), `misfitRel`.

**Ketidakpastian frame**: `u_fit = sqrt(rho Var(w))` dengan `rho = 1,0` TIDAK dikalibrasi (ditandai `rhoCalibrated = false`); `u_sigma_w` = setengah selisih lebar pada `sigma +- sqrt(u_sigma_edge^2 + (0,10 sigma)^2)` (suku 0,10 adalah ketidakpastian bentuk kernel, D24, belum divalidasi perangkat).

**Status**: `TIDAK_TERUKUR` bila `kedalaman lembah model / sigma_noise < 3`, fit gagal, atau `J^T J` tidak stabil; `DI_BAWAH_BATAS_UKUR` bila `w < max(0,5 mm/px, 2 u_frame)` (tidak ada angka lebar yang boleh ditampilkan); selain itu `TERUKUR`. Penolakan (bukan status): patch terlalu kecil, tepi PSF tak tersedia, blur terlalu besar (`sigma_px > 2,5`), blur anisotropik (rasio > 1,6), jenuh (> 1 persen), retak tak ditemukan, masukan tak valid.

## 2. Batas fisik resolusi

Untuk `w << sigma` hanya luas `D w` yang teridentifikasi dari data: `D` dan `w` kolinear. Akibatnya `u_fit` membesar dan kondisi `J^T J` memburuk saat `w/sigma` mengecil. Tabel di bawah (kontras realistis: kedalaman 0,3, derau 0,02) memperlihatkannya; `w/sigma_app` memakai sigma kernel semu.

- `u_frame` naik tajam bila `w/sigma_app` turun di bawah sekitar 3 (mis. sigma 1 px: 6 um pada 0,3 mm, 41 um pada 0,1 mm, 48 um pada 0,05 mm).
- Di sekitar `w/sigma_app` 1 muncul `DI_BAWAH_BATAS_UKUR`; di bawah sekitar 0,5 hasilnya `TIDAK_TERUKUR` (fit gagal atau parameter di batas).
- Bias sistematis positif pada `w` sempit (+9,8 sampai +39 um) berasal dari bentuk kernel (Gaussian dikonvolusi kotak, bukan Gaussian) dan tidak terlihat oleh `u_fit` maupun `u_sigma_edge`. Itulah dasar suku 0,10 sigma (bagian 5).

Realistic contrast: depth 0.3, noise 0.02. Rows: w; columns of the table per sigma.

**sigma = 0.6 px generator** (apparent 0.666 px)

| w (mm) | w/sigma_app | bias (um) | sd (um) | rms (um) | median u_frame (um) | coverage abs(err)<=2u | misfit rel (%) | status |
|---|---|---|---|---|---|---|---|---|
| 1.0 | 25.03 | 1.5 | 0.9 | 1.8 | 0.8 | 67% | 0.13 | TERUKUR 6 |
| 0.5 | 12.52 | 0.6 | 1.0 | 1.1 | 1.2 | 100% | 0.07 | TERUKUR 6 |
| 0.3 | 7.51 | 0.3 | 1.5 | 1.4 | 1.9 | 100% | 0.00 | TERUKUR 6 |
| 0.2 | 5.01 | 1.1 | 1.7 | 1.9 | 4.0 | 100% | 0.06 | TERUKUR 6 |
| 0.1 | 2.50 | 9.8 | 3.1 | 10.2 | 13.1 | 100% | 0.00 | TERUKUR 6 |
| 0.05 | 1.25 | 25.2 | 8.6 | 26.4 | 24.0 | 100% | 0.00 | DI_BAWAH_BATAS_UKUR 2, TERUKUR 4 |

**sigma = 1.0 px generator** (apparent 1.041 px)

| w (mm) | w/sigma_app | bias (um) | sd (um) | rms (um) | median u_frame (um) | coverage abs(err)<=2u | misfit rel (%) | status |
|---|---|---|---|---|---|---|---|---|
| 1.0 | 16.01 | 1.9 | 1.5 | 2.4 | 1.2 | 83% | 0.00 | TERUKUR 6 |
| 0.5 | 8.01 | 0.6 | 1.0 | 1.1 | 2.5 | 100% | 0.00 | TERUKUR 6 |
| 0.3 | 4.80 | 1.4 | 1.8 | 2.2 | 6.2 | 100% | 0.00 | TERUKUR 6 |
| 0.2 | 3.20 | 3.7 | 3.3 | 4.8 | 14.2 | 100% | 0.00 | TERUKUR 6 |
| 0.1 | 1.60 | 12.6 | 8.1 | 14.6 | 41.3 | 100% | 0.00 | TERUKUR 6 |
| 0.05 | 0.80 | 31.5 | 29.2 | 41.3 | 48.1 | 83% | 0.00 | DI_BAWAH_BATAS_UKUR 5, TERUKUR 1 |

**sigma = 1.5 px generator** (apparent 1.528 px)

| w (mm) | w/sigma_app | bias (um) | sd (um) | rms (um) | median u_frame (um) | coverage abs(err)<=2u | misfit rel (%) | status |
|---|---|---|---|---|---|---|---|---|
| 1.0 | 10.91 | 2.3 | 2.3 | 3.1 | 2.3 | 83% | 0.00 | TERUKUR 6 |
| 0.5 | 5.46 | 1.2 | 1.5 | 1.8 | 7.0 | 100% | 0.00 | TERUKUR 6 |
| 0.3 | 3.27 | 3.2 | 2.0 | 3.7 | 20.4 | 100% | 0.00 | TERUKUR 6 |
| 0.2 | 2.18 | 6.6 | 4.9 | 8.0 | 40.7 | 100% | 0.00 | TERUKUR 6 |
| 0.1 | 1.09 | 15.0 | 16.9 | 21.5 | 71.9 | 100% | 0.00 | DI_BAWAH_BATAS_UKUR 6 |
| 0.05 | 0.55 | 27.0 | 49.8 | 52.9 | 83.9 | 100% | 0.00 | TIDAK_TERUKUR 6 [MODEL_MISFIT,PARAMETER_AT_BOUND] |

**sigma = 2.0 px generator** (apparent 2.021 px)

| w (mm) | w/sigma_app | bias (um) | sd (um) | rms (um) | median u_frame (um) | coverage abs(err)<=2u | misfit rel (%) | status |
|---|---|---|---|---|---|---|---|---|
| 1.0 | 8.25 | 2.7 | 2.9 | 3.8 | 4.2 | 100% | 0.00 | TERUKUR 6 |
| 0.5 | 4.12 | 1.8 | 2.3 | 2.8 | 16.6 | 100% | 0.00 | TERUKUR 6 |
| 0.3 | 2.47 | 3.9 | 1.6 | 4.2 | 44.3 | 100% | 0.00 | TERUKUR 6 |
| 0.2 | 1.65 | 6.6 | 4.1 | 7.6 | 87.4 | 100% | 0.00 | TERUKUR 6 |
| 0.1 | 0.82 | 14.3 | 18.3 | 22.0 | 91.2 | 100% | 0.00 | DI_BAWAH_BATAS_UKUR 6 [MODEL_MISFIT] |
| 0.05 | 0.41 | 39.3 | 55.1 | 63.8 | 105.6 | 100% | 0.00 | TIDAK_TERUKUR 6 [MODEL_MISFIT] |

Uji monoton (`profile_fit_test`, `measure_test`): `u_frame` dan `u_frame / w` bertambah saat `w` mengecil (median 5 seed), dan `u_frame` bertambah saat sigma membesar pada `w` tetap. Kovarians fit saja (tanpa `u_sigma_w`) naik dari 0,14 um (w 0,5 mm) menjadi 2,0 um (w 0,05 mm) pada sigma 1 px, derau 0,005.

## 3. Daftar asumsi dan uji pelanggarannya

Tiap asumsi model ditulis, dilanggar dengan sengaja di harness, dan hasilnya dicatat. "Perlindungan" menyebut apa yang mencegah angka palsu; "tidak ada" berarti kelemahan nyata.

| # | Asumsi | Pelanggaran yang diuji | Akibat (SINTETIS, w 0,5 mm kecuali dicatat) | Perlindungan |
|---|---|---|---|---|
| A1 | Tepi retak lurus dan sejajar, lebar konstan di segmen | tepi kasar amplitudo 0,03 / 0,08 / 0,15 mm; retak meruncing | 0,03: +1,8 um (tak berbahaya); 0,08: +14,4 um dengan `u_frame` 3,0 um; 0,15: +62 um dengan `u_frame` 4,6 um. Meruncing 0,1 mm/mm: `dw/ds` pulih (uji) | `MODEL_MISFIT` pada 0,08 dan 0,15. Angka `u_frame` sendiri TERLALU KECIL (kelemahan) |
| A2 | Latar linear di rentang +-3 mm | bayangan satu sisi x0,9 / 0,7 / 0,5; noda di samping amplitudo 0,1 / 0,25 / 0,4; gradien iluminasi; retak kedua 2,5 dan 4,0 mm | bayangan 0,9: +1,1 um; 0,7: +13,7 um; 0,5: 996 um (sampah, `TIDAK_TERUKUR`); noda 0,1 / 0,25: +0,4 / +0,8 um; 0,4: +90 um; gradien sampai 0,5: tanpa bias, 1,0: ditolak jenuh; retak kedua 2,5 mm: `TIDAK_TERUKUR`; 4,0 mm: tanpa efek | `MODEL_MISFIT` pada semua bayangan dan noda (juga yang tak berbahaya), `TIDAK_TERUKUR` pada kasus ekstrem, gerbang jenuh |
| A3 | PSF Gaussian dan sama untuk tepi penanda dan retak | retak lebih buram f x sigma tepi, f 0,8 sampai 1,5 | w 0,3 mm: f 0,9 / 1,1: -4,7 / +6,7 um (dalam `u_frame` 6,5); f 1,25: +17,5 um dengan `u_frame` 5,4; f 1,5: +39 um | `MODEL_MISFIT` hanya mulai f 1,5 (w 0,3) atau f 1,25 (w 1,0). Antara itu: TIDAK ADA |
| A4 | Blur isotropik di piksel | blur anisotropik 1 x 2 px; blur yang sama dengan lembar diputar 45 derajat | rasio terdeteksi 1,9 (uji PSF); pada 45 derajat rasio terdeteksi 1,0 (BATAS DIKETAHUI), sigma besar tetap tertangkap gerbang `sigma_px` | gerbang anisotropi 1,6 dan sigma 2,5; buta pada 45 derajat |
| A5 | Derau piksel iid | derau berkorelasi (kernel [1 2 1]/4 dua kali) | estimator derau patch kurang dari 0,6 x derau sebenarnya (uji); bias lebar -1,4 um pada derau 0,02 | gerbang kontras memakai juga residu per profil (maks); `rho` belum dikalibrasi |
| A6 | Intensitas linear terhadap cahaya | nilai terenkode gamma sRGB (I^(1/2,2)) dengan PSF dari penanda yang juga terenkode | w 0,5: -19,6 um (-3,9 persen); w 0,2: -25,6 um (-13 persen); w 0,1: -36,8 um; setelah `linearizedFromSrgb()`: +1,7 / +3,8 / +10,7 um | TIDAK ADA di dalam inti; adapter WAJIB memanggil `linearizedFromSrgb()`; apakah kurva nada ponsel mendekati sRGB hanya bisa diuji di perangkat |
| A7 | Retak lebih gelap dari latar (`D >= 0`) | garis terang (efloresensi) | `TIDAK_TERUKUR`, `MODEL_MISFIT`, parameter di batas | batas `D >= 0` dan gerbang kontras |
| A8 | Lebar <= 3 mm; tervalidasi sampai 2,0 mm | retak 2,6 dan 3,4 mm | 2,6: +68 um (sd 56) dengan `u_frame` 0,2 um; 3,4: `TIDAK_TERUKUR` | peringatan `WIDTH_BEYOND_VALIDATED` (> 2,1 mm), parameter di batas |
| A9 | Segmen 4 mm cukup lurus | lengkung 0,02 / 0,05 / 0,1 / 0,2 per mm (jari-jari 50 / 20 / 10 / 5 mm) | +0,2 / +1,3 / +4,0 / +16,0 um dengan `u_frame` 2,2 um | TIDAK ADA di atas 0,2 per mm (jari-jari 5 mm, tidak realistis untuk retak bangunan); penjajaran kuadrat menahan sampai 0,1 |
| A10 | `H` dan skala lembar benar | skala `H` salah 1 persen | lebar salah 1 persen (-4,8 / +5,1 um) | tidak ada di fase ini: ditanggung `u_geo` dan `u_print` di 5.5 |
| A11 | Titik tersimpan dalam 1,5 mm dari retak; arah tersimpan kira-kira benar | titik bergeser 1 mm; 2 mm; arah salah sampai 15 derajat | 1 mm: pulih (lebar sama dalam 3 um), 2 mm: ditolak `CRACK_NOT_FOUND`; arah salah 15 derajat: tanpa efek (0,1 um) | radius pencarian dan ambang sinyal/derau 5 |
| A12 | Piksel tidak jenuh | latar terpotong | ditolak `SATURATED` | gerbang 1 persen |
| A13 | Retak sebidang dengan lembar | tidak dapat diuji (harness planar) | tidak diketahui | `u_par` di 5.5 |
| A14 | Interpolasi tidak mengubah profil | Catmull-Rom pada sinyal halus | galat < 0,05 x turunan ketiga (uji analitik); mengubah sedikit kernel semu | sigma diukur lewat rantai yang sama |
| A15 | Orientasi retak tidak khusus | retak sejajar sumbu piksel | +10,3 um pada 0 dan 90 derajat di S=4 renderer (-4,6 um di S=8, +0,3 um pada 20 derajat S=8): ARTEFAK HARNESS (kuantisasi sub-sampel eksak: 17 sampel per sisi = 8,5 px pada S=4, 33 = 8,25 px pada S=8, benar 8,333 px), bukan bias algoritma | uji eksplisit `measure_test` |

## 4. Hasil sapuan

Parameter dasar: 0,06 mm/px, tilt 0, sigma generator 1 px (kernel semu 1,041 px), derau 0,005, kedalaman 0,6, PSF diestimasi dari bingkai penanda 0,2 mm/px dengan blur dan derau yang sama (seed 3), 6 seed per baris. Algoritma `p3-1`.

### 4.1 Kasus ideal (derau rendah 0,002)

Low noise 0.002, sigma 1 px, depth 0.6.

| w (mm) | bias (um) | sd (um) | rms (um) | median u_frame (um) | coverage abs(err)<=2u | misfit rel (%) | status |
|---|---|---|---|---|---|---|---|
| 0.3 | 0.6 | 0.1 | 0.6 | 6.1 | 100% | 0.08 | TERUKUR 6 |
| 0.5 | 0.1 | 0.1 | 0.1 | 2.3 | 100% | 0.09 | TERUKUR 6 |
| 1.0 | 0.1 | 0.1 | 0.2 | 0.8 | 100% | 0.10 | TERUKUR 6 |
| 2.0 | -0.0 | 0.1 | 0.1 | 0.2 | 100% | 0.09 | TERUKUR 6 |

Galat di bawah 1 um; toleransi uji kasus ideal (2 um + 3 `u_frame` pada `profile_fit_test`, 1,5 um + 3 `u_frame` pada `measure_test`) berasal dari galat sistematis tanpa derau (kurang dari 1 um) ditambah tiga kali `u_frame`. `u_frame` di tabel ini jauh di atas galat nyata (0,2 sampai 6 um) karena suku bentuk kernel 0,10 sigma.

### 4.2 Blur

w = 0.3 and 1.0 mm, noise 0.005, depth 0.6.

| sigma (px) | w | bias (um) | sd (um) | rms (um) | median u_frame (um) | coverage abs(err)<=2u | misfit rel (%) | status |
|---|---|---|---|---|---|---|---|---|
| 0.6 | 0.3 | 0.3 | 0.2 | 0.3 | 1.7 | 100% | 0.24 | TERUKUR 6 |
| 0.6 | 1.0 | 0.3 | 0.1 | 0.4 | 0.4 | 100% | 0.25 | TERUKUR 6 |
| 0.8 | 0.3 | 0.3 | 0.2 | 0.4 | 3.4 | 100% | 0.12 | TERUKUR 6 |
| 0.8 | 1.0 | 0.3 | 0.2 | 0.3 | 0.5 | 100% | 0.13 | TERUKUR 6 |
| 1.0 | 0.3 | 0.6 | 0.3 | 0.6 | 6.1 | 100% | 0.07 | TERUKUR 6 |
| 1.0 | 1.0 | 0.3 | 0.2 | 0.3 | 0.8 | 100% | 0.09 | TERUKUR 6 |
| 1.5 | 0.3 | 1.9 | 0.3 | 1.9 | 19.8 | 100% | 0.00 | TERUKUR 6 |
| 1.5 | 1.0 | 0.4 | 0.3 | 0.4 | 1.9 | 100% | 0.06 | TERUKUR 6 |
| 2.0 | 0.3 | 2.1 | 0.2 | 2.1 | 43.9 | 100% | 0.00 | TERUKUR 6 |
| 2.0 | 1.0 | 0.5 | 0.3 | 0.5 | 3.9 | 100% | 0.02 | TERUKUR 6 |
| 2.5 | 0.3 | - | - | - | - | - | - | rejected 6/6 |
| 2.5 | 1.0 | - | - | - | - | - | - | rejected 6/6 |

Sigma 2,5 px ditolak (kernel semu 2,52 px melewati batas 2,5 px). Bias `w` 0,3 mm naik dari 0,3 ke 2,1 um saat sigma 0,6 ke 2,0 px; `u_frame` naik dari 1,7 ke 44 um.

### 4.3 Derau

w = 0.3 and 1.0 mm, sigma 1 px, depth 0.3 (contrast 0.24).

| noise sd | w | bias (um) | sd (um) | rms (um) | median u_frame (um) | coverage abs(err)<=2u | misfit rel (%) | status |
|---|---|---|---|---|---|---|---|---|
| 0.002 | 0.3 | 0.6 | 0.3 | 0.6 | 6.1 | 100% | 0.08 | TERUKUR 6 |
| 0.002 | 1.0 | 0.3 | 0.2 | 0.3 | 0.8 | 100% | 0.09 | TERUKUR 6 |
| 0.005 | 0.3 | 0.6 | 0.5 | 0.8 | 6.1 | 100% | 0.01 | TERUKUR 6 |
| 0.005 | 1.0 | 0.5 | 0.4 | 0.6 | 0.8 | 100% | 0.09 | TERUKUR 6 |
| 0.01 | 0.3 | 0.8 | 1.2 | 1.4 | 6.2 | 100% | 0.00 | TERUKUR 6 |
| 0.01 | 1.0 | 1.0 | 0.8 | 1.2 | 0.9 | 83% | 0.07 | TERUKUR 6 |
| 0.02 | 0.3 | 1.4 | 1.8 | 2.2 | 6.2 | 100% | 0.00 | TERUKUR 6 |
| 0.02 | 1.0 | 1.9 | 1.5 | 2.4 | 1.2 | 83% | 0.00 | TERUKUR 6 |
| 0.04 | 0.3 | 2.6 | 4.1 | 4.5 | 6.8 | 100% | 0.00 | TERUKUR 6 |
| 0.04 | 1.0 | 3.9 | 3.3 | 4.9 | 1.9 | 83% | 0.00 | TERUKUR 6 |
| 0.08 | 0.3 | 6.0 | 7.8 | 9.3 | 8.0 | 100% | 0.00 | TIDAK_TERUKUR 5, TERUKUR 1 [MODEL_MISFIT] |
| 0.08 | 1.0 | 8.6 | 6.6 | 10.5 | 3.7 | 50% | 0.08 | TIDAK_TERUKUR 3, TERUKUR 3 [MODEL_MISFIT] |

Kontras 0,24 (kedalaman 0,3). Sampai derau 0,04 bias di bawah 4 um. Pada derau 0,08 (kontras/derau = 3) sebagian frame `TIDAK_TERUKUR`.

### 4.4 Tilt

w = 0.5 mm, sigma 1 px, noise 0.005. Roll 15 deg for tilt > 0. PSF is the same in px.

| tilt (deg) | w | bias (um) | sd (um) | rms (um) | median u_frame (um) | coverage abs(err)<=2u | misfit rel (%) | status |
|---|---|---|---|---|---|---|---|---|
| 0.0 | 0.3 | 0.6 | 0.3 | 0.6 | 6.1 | 100% | 0.07 | TERUKUR 6 |
| 0.0 | 0.5 | 0.1 | 0.1 | 0.2 | 2.3 | 100% | 0.08 | TERUKUR 6 |
| 10.0 | 0.3 | 0.6 | 0.5 | 0.8 | 6.4 | 100% | 0.07 | TERUKUR 6 |
| 10.0 | 0.5 | 0.4 | 0.3 | 0.5 | 2.4 | 100% | 0.07 | TERUKUR 6 |
| 20.0 | 0.3 | 0.9 | 0.3 | 0.9 | 7.3 | 100% | 0.07 | TERUKUR 6 |
| 20.0 | 0.5 | 0.2 | 0.5 | 0.5 | 2.7 | 100% | 0.07 | TERUKUR 6 |
| 30.0 | 0.3 | 1.1 | 0.2 | 1.1 | 9.1 | 100% | 0.10 | TERUKUR 6 |
| 30.0 | 0.5 | 0.5 | 0.3 | 0.6 | 3.2 | 100% | 0.11 | TERUKUR 6 |

Tilt 0 sampai 30 derajat dengan `f_px` benar: bias di bawah 1,1 um. Galat `f_px` (D17) tidak disimulasikan di sini: ia menggeser tilt yang dipakai `u_par`, bukan lebar.

### 4.5 Gradien iluminasi

w = 0.5 mm, sigma 1 px, noise 0.005. Gradient across the patch (relative change, +-g/2).

| gradient | w | bias (um) | sd (um) | rms (um) | median u_frame (um) | coverage abs(err)<=2u | misfit rel (%) | status |
|---|---|---|---|---|---|---|---|---|
| 0.0 | 0.3 | 0.6 | 0.3 | 0.6 | 6.1 | 100% | 0.07 | TERUKUR 6 |
| 0.0 | 0.5 | 0.1 | 0.1 | 0.2 | 2.3 | 100% | 0.08 | TERUKUR 6 |
| 0.2 | 0.3 | 0.6 | 0.3 | 0.7 | 6.1 | 100% | 0.07 | TERUKUR 6 |
| 0.2 | 0.5 | 0.1 | 0.2 | 0.2 | 2.3 | 100% | 0.08 | TERUKUR 6 |
| 0.5 | 0.3 | 0.6 | 0.2 | 0.6 | 6.1 | 100% | 0.07 | TERUKUR 6 |
| 0.5 | 0.5 | 0.1 | 0.2 | 0.2 | 2.3 | 100% | 0.08 | TERUKUR 6 |
| 1.0 | 0.3 | - | - | - | - | - | - | rejected 6/6 |
| 1.0 | 0.5 | - | - | - | - | - | - | rejected 6/6 |

### 4.6 Orientasi, arah tersimpan, lengkung

Crack orientation (true direction; stored direction exact), w = 0.5 mm.

| direction (deg) | bias (um) | sd (um) | rms (um) | median u_frame (um) | coverage abs(err)<=2u | misfit rel (%) | status |
|---|---|---|---|---|---|---|---|
| 0.0 | 10.3 | 0.2 | 10.3 | 2.2 | 0% | 0.11 | TERUKUR 6 |
| 20.0 | 0.1 | 0.1 | 0.2 | 2.3 | 100% | 0.08 | TERUKUR 6 |
| 45.0 | -1.4 | 0.2 | 1.4 | 2.3 | 100% | 0.06 | TERUKUR 6 |
| 70.0 | 0.2 | 0.3 | 0.3 | 2.3 | 100% | 0.09 | TERUKUR 6 |
| 90.0 | 10.1 | 0.3 | 10.1 | 2.2 | 0% | 0.13 | TERUKUR 6 |

Axis-aligned cracks: the +10 um is the renderer (supersampling S=4 quantises every edge sample the same way). Prediction: half width quantised to the sub-sample grid, 0.5 mm = 8.333 px: S=4 gives +0.167 px = +10 um, S=8 gives +0.042 px = +2.5 um.

| direction (deg), supersample S | bias (um) | sd (um) | rms (um) | median u_frame (um) | coverage abs(err)<=2u | misfit rel (%) | status |
|---|---|---|---|---|---|---|---|
| 0.0, S=4 | 10.3 | 0.2 | 10.3 | 2.2 | 0% | 0.11 | TERUKUR 6 |
| 0.0, S=8 | -4.6 | 0.2 | 4.6 | 2.3 | 83% | 0.12 | TERUKUR 6 |
| 20.0, S=8 | 0.3 | 0.2 | 0.3 | 2.3 | 100% | 0.08 | TERUKUR 6 |

Stored direction error (ridge must refine it), true direction 20 deg, w = 0.5 mm.

| stored dir error (deg) | bias (um) | sd (um) | rms (um) | median u_frame (um) | coverage abs(err)<=2u | misfit rel (%) | status |
|---|---|---|---|---|---|---|---|
| 0.0 | 0.1 | 0.1 | 0.2 | 2.3 | 100% | 0.08 | TERUKUR 6 |
| 3.0 | 0.1 | 0.1 | 0.2 | 2.3 | 100% | 0.08 | TERUKUR 6 |
| 6.0 | 0.1 | 0.1 | 0.2 | 2.3 | 100% | 0.08 | TERUKUR 6 |
| 10.0 | 0.1 | 0.1 | 0.2 | 2.3 | 100% | 0.07 | TERUKUR 6 |
| 15.0 | 0.1 | 0.1 | 0.2 | 2.3 | 100% | 0.07 | TERUKUR 6 |

Curved crack (circular arc), w = 0.5 mm, direction 20.

| curvature (1/mm) | radius (mm) | bias (um) | sd (um) | rms (um) | median u_frame (um) | coverage abs(err)<=2u | misfit rel (%) | status |
|---|---|---|---|---|---|---|---|---|
| 0.0 | - | 0.1 | 0.1 | 0.2 | 2.3 | 100% | 0.08 | TERUKUR 6 |
| 0.02 | 50 | 0.2 | 0.2 | 0.3 | 2.3 | 100% | 0.08 | TERUKUR 6 |
| 0.05 | 20 | 1.3 | 0.2 | 1.3 | 2.3 | 100% | 0.09 | TERUKUR 6 |
| 0.1 | 10 | 4.0 | 0.2 | 4.0 | 2.3 | 100% | 0.12 | TERUKUR 6 |
| 0.2 | 5 | 16.0 | 0.2 | 16.0 | 2.2 | 0% | 0.25 | TERUKUR 6 |

Curved, alignment on raw per-profile centres instead of the smoothed curve (config).

| curvature (1/mm) | radius (mm) | bias (um) | sd (um) | rms (um) | median u_frame (um) | coverage abs(err)<=2u | misfit rel (%) | status |
|---|---|---|---|---|---|---|---|---|
| 0.05 | 20 | 1.3 | 0.2 | 1.3 | 2.3 | 100% | 0.09 | TERUKUR 6 |
| 0.1 | 10 | 4.0 | 0.2 | 4.0 | 2.3 | 100% | 0.12 | TERUKUR 6 |
| 0.2 | 5 | 16.0 | 0.2 | 16.0 | 2.2 | 0% | 0.25 | TERUKUR 6 |

Penjajaran lintasan 2 pada kurva kuadrat versus pusat mentah per profil (D22), SNR rendah:

Pass-2 alignment: smoothed curve (default) versus the raw per-profile centres (literal 5.3). Low SNR: depth 0.3, noise 0.04, sigma 1 px; and a curved crack.

| case | alignment | bias (um) | sd (um) | rms (um) | median u_frame (um) | coverage abs(err)<=2u | misfit rel (%) | status |
|---|---|---|---|---|---|---|---|---|
| w 0.3, straight | smoothed | 3.3 | 4.0 | 5.0 | 6.9 | 100% | 0.00 | TERUKUR 12 |
| w 0.3, straight | raw c_j | 2.3 | 4.8 | 5.1 | 7.0 | 100% | 0.00 | TERUKUR 12 |
| w 0.15, straight | smoothed | 11.3 | 7.0 | 13.1 | 22.8 | 100% | 0.00 | TERUKUR 12 |
| w 0.15, straight | raw c_j | 12.8 | 13.3 | 18.0 | 23.5 | 92% | 0.00 | TERUKUR 12 [MODEL_MISFIT] |
| w 0.3, curvature 0.1/mm | smoothed | 4.0 | 4.4 | 5.8 | 6.8 | 100% | 0.00 | TERUKUR 12 [MODEL_MISFIT] |
| w 0.3, curvature 0.1/mm | raw c_j | 2.9 | 5.6 | 6.1 | 6.8 | 92% | 0.00 | TERUKUR 12 [MODEL_MISFIT] |

Pada SNR rendah dan `w` 0,15 mm, penjajaran mentah memberi sd 13,3 um dibanding 7,0 um (rms 18,0 versus 13,1 um) dan memunculkan `MODEL_MISFIT`; pada SNR tinggi keduanya sama sampai 0,1 um.

### 4.7 Ketidakcocokan PSF retak dan tepi

The crack is blurred more than the marker edges (processing differs by contrast, 5.3a note). sigma_crack = f * sigma_edge (generator, px). w = 0.3 mm and 1.0 mm.

| f | w | bias (um) | sd (um) | rms (um) | median u_frame (um) | coverage abs(err)<=2u | misfit rel (%) | status |
|---|---|---|---|---|---|---|---|---|
| 0.8 | 0.3 | -9.2 | 0.3 | 9.2 | 6.8 | 100% | 0.63 | TERUKUR 6 |
| 0.8 | 1.0 | -1.0 | 0.2 | 1.0 | 1.1 | 100% | 0.87 | TERUKUR 6 |
| 0.9 | 0.3 | -4.7 | 0.3 | 4.7 | 6.5 | 100% | 0.27 | TERUKUR 6 |
| 0.9 | 1.0 | -0.4 | 0.2 | 0.4 | 0.9 | 100% | 0.39 | TERUKUR 6 |
| 1.0 | 0.3 | 0.6 | 0.3 | 0.6 | 6.1 | 100% | 0.07 | TERUKUR 6 |
| 1.0 | 1.0 | 0.3 | 0.2 | 0.3 | 0.8 | 100% | 0.09 | TERUKUR 6 |
| 1.1 | 0.3 | 6.7 | 0.2 | 6.7 | 5.8 | 100% | 0.39 | TERUKUR 6 |
| 1.1 | 1.0 | 1.1 | 0.3 | 1.1 | 1.0 | 100% | 0.53 | TERUKUR 6 |
| 1.25 | 0.3 | 17.5 | 0.2 | 17.5 | 5.4 | 0% | 0.81 | TERUKUR 6 |
| 1.25 | 1.0 | 2.5 | 0.3 | 2.5 | 1.4 | 83% | 1.17 | TERUKUR 6 [MODEL_MISFIT] |
| 1.5 | 0.3 | 39.3 | 0.3 | 39.3 | 4.7 | 0% | 1.44 | TERUKUR 6 [MODEL_MISFIT] |
| 1.5 | 1.0 | 5.6 | 0.3 | 5.6 | 2.2 | 0% | 2.18 | TERUKUR 6 [MODEL_MISFIT] |

### 4.8 Pelanggaran asumsi (pembanding)

Assumption violations (comparison only). w = 0.5 mm nominal, sigma 1 px, noise 0.005, depth 0.6.

| case | what is the truth | bias (um) | sd (um) | rms (um) | median u_frame (um) | coverage abs(err)<=2u | misfit rel (%) | status |
|---|---|---|---|---|---|---|---|---|
| rough edges, amplitude 0.03 mm | mean width over 4 mm = 0.5005 | 1.8 | 0.2 | 1.8 | 2.4 | 100% | 0.35 | TERUKUR 6 |
| rough edges, amplitude 0.08 mm | mean width over 4 mm = 0.5012 | 14.4 | 0.3 | 14.4 | 3.0 | 0% | 1.64 | TERUKUR 6 [MODEL_MISFIT] |
| rough edges, amplitude 0.15 mm | mean width over 4 mm = 0.5023 | 62.1 | 0.5 | 62.1 | 4.6 | 0% | 3.70 | TERUKUR 6 [MODEL_MISFIT] |
| shadow, one side x0.9 | 0.5 | 1.1 | 0.1 | 1.1 | 4.0 | 100% | 3.42 | TERUKUR 6 [MODEL_MISFIT] |
| shadow, one side x0.7 | 0.5 | 13.7 | 0.2 | 13.7 | 11.1 | 100% | 11.40 | TERUKUR 6 [MODEL_MISFIT] |
| shadow, one side x0.5 | 0.5 | 995.6 | 10.9 | 995.7 | 25.9 | 0% | 30.27 | TIDAK_TERUKUR 6 [MODEL_MISFIT,ALIGNMENT_FALLBACK] |
| stain 0.9 mm beside, amp 0.1 | 0.5 | 0.4 | 0.1 | 0.4 | 2.5 | 100% | 1.21 | TERUKUR 6 [MODEL_MISFIT] |
| stain 0.9 mm beside, amp 0.25 | 0.5 | 0.8 | 0.1 | 0.8 | 3.6 | 100% | 3.03 | TERUKUR 6 [MODEL_MISFIT] |
| stain 0.9 mm beside, amp 0.4 | 0.5 | 90.5 | 5.3 | 90.6 | 8.0 | 0% | 7.97 | TERUKUR 6 [MODEL_MISFIT] |

More assumption violations. w = 0.5 mm, sigma 1 px, depth 0.6 unless noted.

| case | what is the truth | bias (um) | sd (um) | rms (um) | median u_frame (um) | coverage abs(err)<=2u | misfit rel (%) | status |
|---|---|---|---|---|---|---|---|---|
| correlated noise sd 0.02 (iid estimate is blind to it) | 0.5 | -1.4 | 0.0 | 1.4 | 2.5 | 100% | 0.54 | TERUKUR 6 |
| gamma-encoded, w 0.5 | 0.5 | -19.6 | 0.1 | 19.6 | 2.7 | 0% | 0.14 | TERUKUR 6 |
| gamma-encoded then linearised, w 0.5 | 0.5 | 1.7 | 0.1 | 1.7 | 2.3 | 100% | 0.08 | TERUKUR 6 |
| gamma-encoded, w 0.2 | 0.2 | -25.6 | 0.5 | 25.6 | 21.6 | 100% | 0.01 | TERUKUR 6 |
| gamma-encoded then linearised, w 0.2 | 0.2 | 3.8 | 0.4 | 3.8 | 13.8 | 100% | 0.02 | TERUKUR 6 |
| gamma-encoded, w 0.1 | 0.1 | -36.8 | 1.9 | 36.8 | 41.2 | 100% | 0.00 | DI_BAWAH_BATAS_UKUR 6 |
| gamma-encoded then linearised, w 0.1 | 0.1 | 10.7 | 1.0 | 10.7 | 38.5 | 100% | 0.03 | TERUKUR 6 |
| second crack 2.5 mm away | 0.5 | -500.0 | 0.0 | 500.0 | Infinity | 100% | 999.00 | TIDAK_TERUKUR 6 [PARAMETER_AT_BOUND] |
| second crack 4.0 mm away | 0.5 | 0.1 | 0.1 | 0.2 | 2.3 | 100% | 0.08 | TERUKUR 6 |
| bright line (efflorescence), depth -0.15 | - | 2500.0 | 0.0 | 2500.0 | 55.0 | 0% | 52.73 | TIDAK_TERUKUR 6 [MODEL_MISFIT,PARAMETER_AT_BOUND,WIDTH_BEYOND_VALIDATED] |
| wide crack 2.6 mm | 2.6 | 67.9 | 55.8 | 84.9 | 0.2 | 17% | 0.25 | TERUKUR 6 [WIDTH_BEYOND_VALIDATED] |
| wide crack 3.4 mm | 3.4 | -400.0 | 0.0 | 400.0 | 18.0 | 0% | 21.10 | TIDAK_TERUKUR 6 [MODEL_MISFIT,PARAMETER_AT_BOUND,WIDTH_BEYOND_VALIDATED] |
| H scale x1.01 (mm wrong by 1 percent) | 0.5 | -4.8 | 0.1 | 4.8 | 2.3 | 17% | 0.08 | TERUKUR 6 |
| H scale x0.99 (mm wrong by 1 percent) | 0.5 | 5.1 | 0.1 | 5.2 | 2.3 | 0% | 0.07 | TERUKUR 6 |

### 4.9 Diagnostik misfit (tiga seed per baris)

`ratio` = residu akhir / ekspektasi derau murni; `rel` = residu total / kedalaman lembah (bukan bagian sistematis). Rasio melonjak pada data sangat bersih (derau 0,002: sampai 3,2) sehingga tidak dipakai sebagai ambang; peringatan memakai bagian sistematis residu `sqrt(max(0, rms^2 - derau^2/N))` terhadap kedalaman, yang di tabel sapuan lain terbaca sebagai `misfit rel`.

Model-misfit diagnostics: ratio = final residual rms / noise-only expectation, rel = residual rms / dip depth. 3 seeds per row.

| case | ratio min..max | rel (percent) min..max | abs err (um) max |
|---|---|---|---|
| CLEAN sigma 0.6 noise 0.002 depth 0.6 w 0.2 | 2.9..3.0 | 0.23..0.24 | 0.7 |
| CLEAN sigma 0.6 noise 0.002 depth 0.6 w 1.0 | 3.1..3.2 | 0.25..0.26 | 0.3 |
| CLEAN sigma 0.6 noise 0.002 depth 0.6 w 2.0 | 3.1..3.2 | 0.25..0.26 | 0.1 |
| CLEAN sigma 0.6 noise 0.002 depth 0.3 w 0.2 | 1.8..2.0 | 0.25..0.27 | 0.6 |
| CLEAN sigma 0.6 noise 0.002 depth 0.3 w 1.0 | 2.0..2.2 | 0.26..0.29 | 0.6 |
| CLEAN sigma 0.6 noise 0.002 depth 0.3 w 2.0 | 2.0..2.1 | 0.26..0.28 | 0.2 |
| CLEAN sigma 0.6 noise 0.01 depth 0.6 w 0.2 | 1.2..1.4 | 0.33..0.37 | 0.7 |
| CLEAN sigma 0.6 noise 0.01 depth 0.6 w 1.0 | 1.2..1.5 | 0.33..0.39 | 0.9 |
| CLEAN sigma 0.6 noise 0.01 depth 0.6 w 2.0 | 1.2..1.4 | 0.33..0.36 | 0.6 |
| CLEAN sigma 0.6 noise 0.01 depth 0.3 w 0.2 | 1.0..1.2 | 0.51..0.61 | 0.5 |
| CLEAN sigma 0.6 noise 0.01 depth 0.3 w 1.0 | 1.0..1.2 | 0.50..0.61 | 1.6 |
| CLEAN sigma 0.6 noise 0.01 depth 0.3 w 2.0 | 1.0..1.1 | 0.52..0.58 | 1.2 |
| CLEAN sigma 0.6 noise 0.04 depth 0.6 w 0.2 | 0.9..1.1 | 0.93..1.17 | 1.0 |
| CLEAN sigma 0.6 noise 0.04 depth 0.6 w 1.0 | 0.9..1.1 | 0.93..1.15 | 3.3 |
| CLEAN sigma 0.6 noise 0.04 depth 0.6 w 2.0 | 0.9..1.1 | 0.96..1.10 | 2.5 |
| CLEAN sigma 0.6 noise 0.04 depth 0.3 w 0.2 | 0.9..1.1 | 1.79..2.30 | 2.0 |
| CLEAN sigma 0.6 noise 0.04 depth 0.3 w 1.0 | 0.9..1.1 | 1.78..2.22 | 6.5 |
| CLEAN sigma 0.6 noise 0.04 depth 0.3 w 2.0 | 0.9..1.0 | 1.85..2.17 | 4.8 |
| CLEAN sigma 1.0 noise 0.002 depth 0.6 w 0.2 | 1.0..1.3 | 0.07..0.09 | 2.2 |
| CLEAN sigma 1.0 noise 0.002 depth 0.6 w 1.0 | 1.6..1.9 | 0.10..0.12 | 0.3 |
| CLEAN sigma 1.0 noise 0.002 depth 0.6 w 2.0 | 1.8..1.8 | 0.11..0.11 | 0.2 |
| CLEAN sigma 1.0 noise 0.002 depth 0.3 w 0.2 | 0.9..1.1 | 0.12..0.15 | 2.1 |
| CLEAN sigma 1.0 noise 0.002 depth 0.3 w 1.0 | 1.1..1.4 | 0.14..0.16 | 0.4 |
| CLEAN sigma 1.0 noise 0.002 depth 0.3 w 2.0 | 1.1..1.3 | 0.14..0.16 | 0.1 |
| CLEAN sigma 1.0 noise 0.01 depth 0.6 w 0.2 | 0.9..1.1 | 0.25..0.31 | 2.1 |
| CLEAN sigma 1.0 noise 0.01 depth 0.6 w 1.0 | 0.9..1.1 | 0.23..0.30 | 1.3 |
| CLEAN sigma 1.0 noise 0.01 depth 0.6 w 2.0 | 1.0..1.1 | 0.25..0.29 | 0.8 |
| CLEAN sigma 1.0 noise 0.01 depth 0.3 w 0.2 | 0.9..1.1 | 0.50..0.61 | 2.2 |
| CLEAN sigma 1.0 noise 0.01 depth 0.3 w 1.0 | 0.9..1.1 | 0.45..0.55 | 2.4 |
| CLEAN sigma 1.0 noise 0.01 depth 0.3 w 2.0 | 0.9..1.1 | 0.47..0.55 | 1.7 |
| CLEAN sigma 1.0 noise 0.04 depth 0.6 w 0.2 | 0.9..1.1 | 1.00..1.25 | 4.8 |
| CLEAN sigma 1.0 noise 0.04 depth 0.6 w 1.0 | 0.9..1.1 | 0.90..1.11 | 5.1 |
| CLEAN sigma 1.0 noise 0.04 depth 0.6 w 2.0 | 0.9..1.1 | 0.97..1.10 | 2.7 |
| CLEAN sigma 1.0 noise 0.04 depth 0.3 w 0.2 | 0.9..1.1 | 1.95..2.53 | 4.2 |
| CLEAN sigma 1.0 noise 0.04 depth 0.3 w 1.0 | 0.9..1.0 | 1.78..2.18 | 10.0 |
| CLEAN sigma 1.0 noise 0.04 depth 0.3 w 2.0 | 0.9..1.1 | 1.86..2.20 | 5.1 |
| CLEAN sigma 2.0 noise 0.002 depth 0.6 w 0.2 | 0.8..1.1 | 0.09..0.11 | 5.1 |
| CLEAN sigma 2.0 noise 0.002 depth 0.6 w 1.0 | 1.1..1.2 | 0.06..0.07 | 0.6 |
| CLEAN sigma 2.0 noise 0.002 depth 0.6 w 2.0 | 1.1..1.2 | 0.07..0.07 | 0.1 |
| CLEAN sigma 2.0 noise 0.002 depth 0.3 w 0.2 | 0.8..1.1 | 0.17..0.21 | 4.2 |
| CLEAN sigma 2.0 noise 0.002 depth 0.3 w 1.0 | 0.9..1.1 | 0.11..0.13 | 0.8 |
| CLEAN sigma 2.0 noise 0.002 depth 0.3 w 2.0 | 1.0..1.2 | 0.12..0.14 | 0.4 |
| CLEAN sigma 2.0 noise 0.01 depth 0.6 w 0.2 | 0.9..1.1 | 0.39..0.46 | 3.0 |
| CLEAN sigma 2.0 noise 0.01 depth 0.6 w 1.0 | 0.9..1.0 | 0.23..0.27 | 1.6 |
| CLEAN sigma 2.0 noise 0.01 depth 0.6 w 2.0 | 0.9..1.1 | 0.23..0.28 | 0.8 |
| CLEAN sigma 2.0 noise 0.01 depth 0.3 w 0.2 | 0.9..1.1 | 0.77..0.93 | 2.0 |
| CLEAN sigma 2.0 noise 0.01 depth 0.3 w 1.0 | 0.9..1.0 | 0.45..0.53 | 3.5 |
| CLEAN sigma 2.0 noise 0.01 depth 0.3 w 2.0 | 0.9..1.1 | 0.46..0.54 | 1.5 |
| CLEAN sigma 2.0 noise 0.04 depth 0.6 w 0.2 | 0.9..1.1 | 1.53..1.88 | 14.2 |
| CLEAN sigma 2.0 noise 0.04 depth 0.6 w 1.0 | 0.9..1.1 | 0.92..1.09 | 7.9 |
| CLEAN sigma 2.0 noise 0.04 depth 0.6 w 2.0 | 0.9..1.1 | 0.94..1.10 | 3.4 |
| CLEAN sigma 2.0 noise 0.04 depth 0.3 w 0.2 | 0.9..1.1 | 3.03..3.82 | 13.4 |
| CLEAN sigma 2.0 noise 0.04 depth 0.3 w 1.0 | 0.9..1.0 | 1.82..2.17 | 15.1 |
| CLEAN sigma 2.0 noise 0.04 depth 0.3 w 2.0 | 0.9..1.1 | 1.85..2.22 | 6.3 |
| VIOL rough edges 0.03 | 2.7..2.9 | 0.36..0.39 | 2.5 |
| VIOL rough edges 0.08 | 11.1..11.3 | 1.64..1.69 | 15.9 |
| VIOL rough edges 0.15 | 19.6..20.0 | 3.70..3.72 | 65.1 |
| VIOL shadow x0.9 | 6.1..6.1 | 3.48..3.50 | 1.3 |
| VIOL shadow x0.7 | 6.3..6.3 | 11.55..11.59 | 13.7 |
| VIOL shadow x0.5 | NaN..NaN | 30.23..30.41 | 1010.7 |
| VIOL stain 0.1 | 7.9..8.3 | 1.21..1.22 | 0.5 |
| VIOL stain 0.25 | 18.3..19.6 | 3.03..3.03 | 0.9 |
| VIOL stain 0.4 | 35.0..42.6 | 7.95..8.26 | 98.5 |
| VIOL gamma w 0.5 | 1.4..1.7 | 0.15..0.19 | 19.6 |
| VIOL curved 0.2/mm | 2.0..2.1 | 0.28..0.29 | 16.1 |
| VIOL axis aligned 0 deg | 1.2..1.3 | 0.16..0.17 | 10.4 |
| VIOL psf mismatch x1.25 (w 0.3) | 4.2..4.3 | 0.83..0.86 | 17.6 |

## 5. Faktor `rho` dan suku bentuk kernel (cakupan SINTETIS, 30 seed)

Kontras realistis (kedalaman 0,3, derau 0,02). `eps` = suku bentuk kernel relatif pada `u_sigma_w`.

Coverage over 30 noise realisations, sigma 1 px and 0.6 px, depth 0.3, noise 0.02. eps = kernel shape relative uncertainty added to u_sigma_w.

| sigma | w (mm) | eps | n | bias (um) | rms err (um) | mean u_fit (um) | mean u_frame (um) | rms/u_frame | frac abs(err)<=2u_fit | frac abs(err)<=2u_frame | below-limit |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 0.6 | 1.0 | 0.0 | 30 | 0.6 | 1.7 | 0.7 | 0.7 | 2.32 | 63% | 63% | 0 |
| 0.6 | 1.0 | 0.05 | 30 | 0.6 | 1.7 | 0.7 | 0.7 | 2.27 | 63% | 67% | 0 |
| 0.6 | 1.0 | 0.1 | 30 | 0.6 | 1.7 | 0.7 | 0.8 | 2.13 | 63% | 67% | 0 |
| 0.6 | 0.5 | 0.0 | 30 | 0.4 | 1.6 | 0.7 | 0.8 | 2.01 | 73% | 73% | 0 |
| 0.6 | 0.5 | 0.05 | 30 | 0.4 | 1.6 | 0.7 | 0.9 | 1.78 | 73% | 73% | 0 |
| 0.6 | 0.5 | 0.1 | 30 | 0.4 | 1.6 | 0.7 | 1.2 | 1.39 | 73% | 83% | 0 |
| 0.6 | 0.3 | 0.0 | 30 | -0.1 | 1.6 | 0.8 | 1.0 | 1.58 | 67% | 80% | 0 |
| 0.6 | 0.3 | 0.05 | 30 | -0.1 | 1.6 | 0.8 | 1.3 | 1.20 | 67% | 90% | 0 |
| 0.6 | 0.3 | 0.1 | 30 | -0.1 | 1.6 | 0.8 | 2.0 | 0.80 | 67% | 100% | 0 |
| 0.6 | 0.2 | 0.0 | 30 | 0.5 | 2.1 | 0.9 | 1.6 | 1.30 | 67% | 87% | 0 |
| 0.6 | 0.2 | 0.05 | 30 | 0.5 | 2.1 | 0.9 | 2.4 | 0.85 | 67% | 97% | 0 |
| 0.6 | 0.2 | 0.1 | 30 | 0.5 | 2.1 | 0.9 | 4.0 | 0.51 | 67% | 100% | 0 |
| 0.6 | 0.1 | 0.0 | 30 | 9.1 | 9.8 | 1.7 | 4.6 | 2.12 | 3% | 50% | 0 |
| 0.6 | 0.1 | 0.05 | 30 | 9.1 | 9.8 | 1.7 | 7.7 | 1.27 | 3% | 97% | 0 |
| 0.6 | 0.1 | 0.1 | 30 | 9.1 | 9.8 | 1.7 | 13.4 | 0.73 | 3% | 100% | 0 |
| 0.6 | 0.05 | 0.0 | 30 | 23.5 | 25.1 | 4.1 | 9.1 | 2.75 | 3% | 33% | 0 |
| 0.6 | 0.05 | 0.05 | 30 | 23.5 | 25.1 | 4.1 | 15.1 | 1.66 | 3% | 60% | 0 |
| 0.6 | 0.05 | 0.1 | 30 | 23.5 | 25.1 | 4.1 | 27.9 | 0.90 | 3% | 97% | 10 |
| 1.0 | 1.0 | 0.0 | 30 | 0.7 | 2.3 | 0.9 | 0.9 | 2.46 | 67% | 70% | 0 |
| 1.0 | 1.0 | 0.05 | 30 | 0.7 | 2.3 | 0.9 | 1.0 | 2.25 | 67% | 70% | 0 |
| 1.0 | 1.0 | 0.1 | 30 | 0.7 | 2.3 | 0.9 | 1.2 | 1.85 | 67% | 77% | 0 |
| 1.0 | 0.5 | 0.0 | 30 | 0.4 | 2.1 | 1.0 | 1.2 | 1.83 | 67% | 70% | 0 |
| 1.0 | 0.5 | 0.05 | 30 | 0.4 | 2.1 | 1.0 | 1.6 | 1.31 | 67% | 90% | 0 |
| 1.0 | 0.5 | 0.1 | 30 | 0.4 | 2.1 | 1.0 | 2.6 | 0.83 | 67% | 97% | 0 |
| 1.0 | 0.3 | 0.0 | 30 | 0.7 | 2.4 | 1.1 | 2.1 | 1.18 | 63% | 90% | 0 |
| 1.0 | 0.3 | 0.05 | 30 | 0.7 | 2.4 | 1.1 | 3.6 | 0.68 | 63% | 100% | 0 |
| 1.0 | 0.3 | 0.1 | 30 | 0.7 | 2.4 | 1.1 | 6.3 | 0.39 | 63% | 100% | 0 |
| 1.0 | 0.2 | 0.0 | 30 | 2.6 | 4.3 | 1.6 | 4.2 | 1.01 | 43% | 93% | 0 |
| 1.0 | 0.2 | 0.05 | 30 | 2.6 | 4.3 | 1.6 | 8.0 | 0.53 | 43% | 100% | 0 |
| 1.0 | 0.2 | 0.1 | 30 | 2.6 | 4.3 | 1.6 | 14.3 | 0.30 | 43% | 100% | 0 |
| 1.0 | 0.1 | 0.0 | 30 | 10.0 | 13.5 | 4.1 | 11.3 | 1.20 | 30% | 93% | 0 |
| 1.0 | 0.1 | 0.05 | 30 | 10.0 | 13.5 | 4.1 | 21.8 | 0.62 | 30% | 100% | 0 |
| 1.0 | 0.1 | 0.1 | 30 | 10.0 | 13.5 | 4.1 | 41.9 | 0.32 | 30% | 100% | 4 |
| 1.0 | 0.05 | 0.0 | 29 | 20.2 | 33.3 | 15.9 | 24.6 | 1.35 | 45% | 76% | 7 |
| 1.0 | 0.05 | 0.05 | 29 | 20.2 | 33.3 | 15.9 | 38.6 | 0.86 | 45% | 90% | 19 |
| 1.0 | 0.05 | 0.1 | 29 | 20.2 | 33.3 | 15.9 | 51.7 | 0.64 | 45% | 97% | 27 |

Temuan:

1. **`rho`**: untuk `w >= 0,3 mm`, `rms / u_fit` sekitar 2,0 sampai 2,6, jadi `rho` yang menghasilkan cakupan 95 persen pada `k = 2` kira-kira 4 sampai 7 (sampel profil 0,25 px berkorelasi). Nilai bawaan `rho = 1,0` memberi cakupan hanya 63 sampai 73 persen untuk retak lebar. `rho` TIDAK diubah: kalibrasi resmi tetap di studi cakupan (butir 7, `docs/SYNTHETIC_VALIDATION.md`).
2. **`eps`**: pada `w` sempit (sigma 0,6 px, `w` 0,05 mm) cakupan `2 u_frame` hanya 33 persen tanpa suku bentuk kernel, 60 persen dengan 0,05, 97 persen dengan 0,10 (sigma 1 px: 76, 90, 97 persen). `eps = 0,10` adalah nilai terkecil yang dicoba yang mencapai 90 persen pada kasus terburuk; ini keputusan konservatif SINTETIS, bukan hasil validasi perangkat.
3. Cakupan retak lebar tidak diperbaiki `eps` (kekurangannya dari `rho`), dan tidak boleh dikejar dengan menaikkan `eps`.

## 6. Waktu dan determinisme

Mesin pengembangan: macOS 14.8.9 arm64, 8 inti, Dart 3.13.4 VM (JIT, bukan AOT). Diukur oleh `tool/measurement_sweep.dart timing` saat hanya satu proses lain berjalan:

- Satu frame penuh (patch 1702 x 1702, penanda + retak, 0,1 mm/px, termasuk PSF dari tepi dan estimasi derau): 122, 124, 125, 128, 146 ms (lima eksekusi berurutan).
- Hanya patch retak 336 x 336 dengan PSF diberikan: 83 sampai 118 ms, satu pencilan 436 ms.
- Panggilan pertama dalam proses uji (JIT dingin): 986 ms.

Belum diukur: patch penuh 2500 x 2500 (0,06 mm/px), kompilasi AOT, dan CPU ponsel. Estimasi derau memakai paling banyak sekitar 200 ribu piksel dan tepi PSF hanya menyentuh profil, sehingga biaya tidak berskala dengan luas patch, tetapi ini belum dibuktikan pada ponsel. Hasil deterministik: masukan sama memberi lebar, ketidakpastian, dan titik yang identik (uji).

## 7. Kelemahan yang diketahui (jujur)

1. Seluruh akurasi di sini SINTETIS dengan model rendering yang sama kelasnya dengan model pengukuran (PSF Gaussian, derau Gaussian). Perilaku ponsel nyata (penajaman ISP, JPEG, HDR, kurva nada, derau berkorelasi, fokus) tidak diketahui.
2. `u_frame` bukan batas galat penuh. Bias diam-diam (tanpa peringatan) tercatat: gamma tanpa linearisasi (-3,9 persen pada 0,5 mm), ketidakcocokan PSF 10 sampai 25 persen (sampai 17,5 um pada 0,3 mm), lengkung 0,2 per mm (16 um), skala `H` salah (ditanggung 5.5). Komponen sistematis `u_dev` (5.5, nilai awal `0,5 mm/px` = 30 um pada 0,06 mm/px) menutup sebagian besar bias ini pada anggaran kunjungan, tetapi itu nilai awal konservatif tak tervalidasi.
3. `MODEL_MISFIT` hanya peringatan. Pada tepi kasar 0,08 mm dan bayangan 0,7x angka tetap keluar dengan `u_frame` terlalu kecil; lapisan agregasi dan UI harus memperlakukan frame berperingatan sebagai tidak dapat dipercaya (mis. tidak dihitung ke kunjungan terterima).
4. Blur gerak pada 45 derajat terhadap tepi penanda tidak terdeteksi sebagai anisotropi.
5. Estimator derau patch mengandaikan derau iid dan meremehkan derau berkorelasi (kurang dari 0,6 x).
6. `rho = 1,0` dan `eps = 0,10` tidak dikalibrasi/divalidasi di perangkat.
7. `dw/ds` dan `along_sd` hanya ada bila setidaknya 8 profil dapat dipakai; untuk retak sempit biasanya tidak ada (NaN). Fase 5.5 harus memperlakukan NaN sebagai "tidak diketahui" (konservatif), bukan 0.
8. Panduan lebar > 2,1 mm: peringatan saja; 2,6 mm punya galat sampai puluhan um tanpa `u_frame` yang mencerminkannya.
9. Patch harus mencakup sekitar +-8 mm di sekitar titik ukur dan, untuk PSF, tepi luar penanda (praktis bingkai 150 mm). Adapter Fase 5 harus menjamin ini dan memanggil `linearizedFromSrgb()`.

## 8. Mereproduksi

```
cd packages/hairline_core
dart test                                            # semua uji, seed tetap
dart run tool/measurement_sweep.dart                 # semua sapuan (sekitar 10 menit)
dart run tool/measurement_sweep.dart subpixel coverage timing   # bagian tertentu
```

Bagian: `ideal subpixel blur noise tilt illum geometry violations violations2 psfmismatch misfit align coverage timing`.

## Fase 5: rantai ujung-ke-ujung dengan JPEG nyata (SINTETIS, seed tetap)

Sumber: `packages/hairline_core/test/frame_pipeline_test.dart`, `dart test` (dijalankan 2026-11-17). Foto 1600 x 1500, 0,12 mm/px, tilt 8 derajat, roll 12, lembar 0, retak 0,6 mm (5 px) arah 25 derajat, sigma 1 px, derau 0,004 (cahaya linear), derau sudut 0,2 px, burst 4 frame (derau berbeda per frame, seed 7). Pipeline: render linear -> sRGB 8 bit -> (JPEG, paket `image` 4.13.1, pengaturan bawaan) -> dekode ke abu-abu -> `processFrame` (linearisasi, patch per penanda, PSF, `measureFrame`) -> `aggregateVisit`. Detektor penanda adalah sudut yang diproyeksikan ditambah derau (OpenCV tidak berjalan di host ini), jadi tes ini TIDAK menguji deteksi sub-pixel pada citra terkompresi.

| Masukan | Lebar (um) | Galat (um) | U (um) | u_c (um) |
|---|---|---|---|---|
| mentah (tanpa JPEG) | 599,2 | -0,8 | 128,7 | 65,6 |
| JPEG kualitas 95 | 599,5 | -0,5 | 128,7 | 65,6 |
| JPEG kualitas 85 | 599,7 | -0,3 | 128,7 | 65,7 |

- Pergeseran akibat JPEG terhadap mentah: +0,2 um (q95), +0,5 um (q85), atau sekitar 0,1 sampai 0,4 persen dari `U`. Lebar terukur berada di dalam `U` yang dilaporkan di ketiga kasus (ditegakkan di tes; batas pergeseran 5 um dan `U/10`).
- Batas penafsiran: satu seed, satu geometri, citra abu-abu yang disandikan sebagai RGB; codec `image` bukan libjpeg ponsel dan tidak ada penajaman ISP, pengurangan derau, atau subsampling krominans yang berarti. Angka ini membuktikan bahwa kuantisasi DCT (q85 dan q95) sendiri bukan masalah pada lebar 5 px, BUKAN bahwa foto ponsel nyata akan sama. Anggaran 5.5 tidak punya suku JPEG; validasi `PERANGKAT` (Fase 7) yang akan menangkapnya lewat `u_dev`.
- `U` hampir seluruhnya `u_dev` bawaan 0,5 mm/px (D29), sebab itu 128,7 um jauh di atas galat nyata (sekitar 1 um).
- Memori (terukur sebagai luas, bukan byte): empat patch penanda masing-masing sekitar 4 sampai 5 persen luas foto, total di bawah 25 persen; tidak ada patch seluruh lembar. Pada foto 12 MP dengan lembar memenuhi bingkai (sekitar 0,05 mm/px) ekstrapolasi kasar dari rasio itu memberi sekitar 2 Mpx Float32 (8 MB) plus salinan linear (8 MB), bukan sekitar 46 MB per salinan untuk satu patch seluruh lembar. Ekstrapolasi ini belum diukur di ponsel.
