# DEVICE_TEST: daftar uji manual di ponsel Android

Status: **belum dijalankan**. Agent tidak punya ponsel, kamera, atau lembar cetak nyata (CLAUDE.md aturan 7). Semua butir di bawah berstatus `SELESAI-PERLU-UJI-PERANGKAT` sampai pemilik mengisi kolom hasil. Catat model ponsel, versi Android, dan tanggal untuk setiap uji. Jangan menulis angka tanpa label `PERANGKAT` dan tanpa data yang benar-benar diukur.

Urutan yang disarankan: bagian 10 (cetak dan lembar), 1 sampai 9 (kamera dan alur), lalu 11 (validasi pelat, satu-satunya sumber angka akurasi `PERANGKAT`), lalu 12 (APK rilis). Setiap baris dapat langsung dikerjakan: isi kolom Hasil dengan angka atau "lulus" / "gagal" dan catatan.

Prasyarat build (BLOCKERS B1, DECISIONS D48): APK dari `flutter build apk` biasa TIDAK punya detektor penanda (layar pengambilan menampilkan "Detektor penanda belum tersedia"). Untuk ponsel, bangun dengan `make apk-device` (atau `tools/build_device_apk.sh --target-platform android-arm64`), yang menyambungkan `hairline_opencv` lewat `lib/main_device.dart`, lalu pasang `app/build/app/outputs/flutter-apk/app-release.apk` dengan `adb install -r`. Build pertama mengompilasi OpenCV dari sumber (puluhan menit; perlu cmake dan ninja). Bila terjadi galat, catat keluarannya di BLOCKERS. Pasang lembar bingkai nomor 0 (cetak 100 persen, skala dicek dengan penggaris) rata pada bidang uji. Di build debug, tombol "Uji pengambilan foto (debug, kamera nyata)" di halaman awal membuat retak uji (lembar 0, skala 1, titik di pusat jendela, arah 0 derajat).

Cara membaca hasil frame: tiap foto yang diterima menyimpan `quality_json` (sigma_px, anisotropi blur, fraksi jenuh, peringatan) di tabel `frames`; bendera pengambilan ada di `visits.camera_info_json` pada kunci `flags` (`fokus_tidak_terkunci`, `eksposur_tidak_terkunci`).

## 1. Izin kamera
| Uji | Hasil yang diharapkan | Hasil |
|---|---|---|
| Pemasangan baru, buka layar pengambilan | Dialog izin Android muncul; setelah diizinkan pratinjau tampil | |
| Tolak sekali | Pesan "Izin kamera ditolak ...", tombol Ulangi memunculkan dialog lagi | |
| Tolak permanen ("jangan tanya lagi") | Pesan "Izin kamera diblokir ... Pengaturan > Aplikasi > Hairline > Izin" | |
| Izinkan lewat Pengaturan lalu kembali ke app | Ulangi membuka kamera tanpa restart | |
| Manifest rilis gabungan (`aapt dump permissions app-release.apk`) | Hanya `CAMERA` (dan izin internal `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` milik app sendiri); tidak ada `INTERNET`, `RECORD_AUDIO`, penyimpanan, atau jaringan | |

## 2. Fokus dan eksposur terkunci (butir inti)
Kode meminta `FocusMode.locked` dan `ExposureMode.locked` lewat plugin `camera` (backend CameraX). Plugin tidak melempar galat bila perangkat mengabaikan kunci, dan `value.focusMode` diset plugin walau kamera tidak mengubahnya, jadi kode TIDAK dapat membuktikan kunci bertahan. Hanya uji ini yang membuktikan.
| Uji | Cara | Hasil yang diharapkan | Hasil |
|---|---|---|---|
| Fokus bertahan selama burst | Jarak 30 cm, bidik, gerakkan ponsel maju mundur sekitar 2 cm selama enam bidikan | `sigma_px` enam frame konsisten (tanpa fokus terkunci: bervariasi besar atau frame buram) | |
| Pembanding tanpa kunci | Nonaktifkan sementara kunci (ubah `lock()` di `camera_driver.dart`) dan ulangi | Variasi `sigma_px` lebih besar dari uji terkunci; ini menunjukkan kunci bekerja | |
| Eksposur bertahan | Selama burst, tutup sebagian lampu atau bayangi lembar dengan tangan | Kecerahan latar lembar tiap frame hampir sama (bandingkan rata-rata abu-abu patch penanda) | |
| Perangkat tanpa kunci fokus | Cari model yang menolak kunci | Burst tetap jalan, `flags` memuat `fokus_tidak_terkunci`, kartu hasil menampilkan peringatan, frame buram ditolak gerbang `sigma_px` | |
| Fokus otomatis kembali setelah burst | Setelah hasil, tekan Ulangi dan arahkan ke jarak lain | Fokus mengikuti (kunci dibuka oleh `unlock()`) | |

## 3. Siklus hidup
| Uji | Hasil yang diharapkan | Hasil |
|---|---|---|
| Panggilan masuk saat membidik langsung (live) | Kamera dilepas (`inactive`), setelah panggilan selesai pratinjau kembali sendiri dan status kembali "Penanda belum terlihat" lalu siap | |
| Panggilan masuk di tengah burst | Burst berakhir dengan pesan "Pemotretan terputus ..."; tidak ada kunjungan tersimpan; Ulangi pulih | |
| Panggilan masuk saat "Memeriksa kualitas foto" | Pemrosesan lanjut; hasil tampil saat kembali | |
| Tombol Home lalu kembali, 20 kali berturut-turut | Tidak ada crash, pratinjau selalu kembali, memori (profiler Android Studio) tidak naik terus | |
| Layar dikunci lalu dibuka | Sama seperti Home | |
| Dialog izin muncul saat pertama membuka kamera | Dialog memicu `inactive`; kamera ditutup lalu dibuka lagi setelah dialog; tidak ada pratinjau macet | |
| Tombol Back saat burst atau pemrosesan | Layar tidak tertutup (PopScope); setelah selesai bisa keluar | |
| Tutup layar lalu buka lagi 20 kali | Tidak ada isolate atau kamera yatim (`adb shell dumpsys media.camera` menunjukkan kamera bebas) | |
| Aplikasi lain memakai kamera lebih dulu | Pesan "Kamera tidak dapat dibuka ..." | |

## 4. Orientasi dan penyelarasan overlay
Overlay mengasumsikan bingkai tegak (potret terkunci) dan memutar deteksi sebanyak `sensorOrientation / 90` kuartal (DECISIONS D41). Ini asumsi tentang perilaku CameraX, belum terbukti.
| Uji | Hasil yang diharapkan | Hasil |
|---|---|---|
| Garis tepi penanda menempel pada penanda cetak di layar | Selisih kecil (catat dalam piksel layar), tidak bergeser terhadap pratinjau saat ponsel digerakkan | |
| Putar ponsel ke lanskap | Layar tetap potret; overlay tetap sejajar | |
| Model dengan `sensorOrientation` 270 (jarang) | Overlay sejajar | |
| Instruksi arah ("Geser ponsel ke kiri") | Mengikuti arah sebenarnya (setelah digeser ke kiri, lembar mendekati bayangan putih putus-putus) | |
| Rasio aspek pratinjau vs analisis | Bila pratinjau 16:9 sedangkan analisis 4:3, overlay terskala tidak seragam: catat dan laporkan | |

## 5. Beberapa lensa dan model
| Uji | Hasil yang diharapkan | Hasil |
|---|---|---|
| Ponsel dengan lensa utama, ultra lebar, tele | Catat lensa mana yang dipilih (`availableCameras()` lalu yang pertama berarah belakang); `focalLengthMm` dan ukuran sensor dari channel Kotlin untuk id itu cocok dengan lensa yang dipakai | |
| `f_px` dari metadata vs default | Bandingkan kemiringan perkiraan layar dengan kemiringan terukur (busur atau sudut meja) | |
| Id kamera `CameraDescription.name` | Sama dengan id yang dipahami `CameraManager` (jika tidak: info lensa kosong, default dipakai) | |
| Tiga model (murah, menengah, unggulan) | Isi tabel: resolusi stream, fps deteksi nyata, waktu sampai "siap", dukungan kunci, resolusi foto diam | |

## 6. Kinerja, memori, suhu
Stream dan foto diam memakai satu preset (`ResolutionPreset.max`, DECISIONS D39): bingkai live ikut beresolusi maksimum (bidang Y sekitar 12 MP lewat platform channel per frame). Throttle membuang frame lebih dini, tetapi biaya salinan plugin tidak terkendali.
| Uji | Hasil yang diharapkan | Hasil |
|---|---|---|
| fps deteksi nyata (8 sampai 12 target) | Hitung `FrameThrottle.admitted` per detik (tambahkan log sementara; belum ada penghitung di UI) | |
| Frame dibuang | `droppedBusy` besar tidak masalah; antrean tidak ada | |
| 10 menit membidik langsung | Suhu ponsel, penurunan fps, pesan panas sistem; app tidak crash | |
| Memori 5 menit live | RSS stabil (tidak ada kebocoran `Mat` di `OpenCvGrayMarkerDetector`) | |
| Jika fps jauh di bawah 8 atau ponsel panas | Pertimbangkan `ResolutionPreset.veryHigh` (mengorbankan resolusi foto diam); catat keputusan di DECISIONS | |

## 7. Burst dan gerbang kualitas
| Uji | Hasil yang diharapkan | Hasil |
|---|---|---|
| Enam bidikan: waktu total dan jeda | Jeda minimal 200 ms antar bidikan; total kira-kira 2 sampai 4 detik | |
| Berkas cache plugin dihapus | `cache/` app tidak menumpuk berkas JPEG setelah beberapa kunjungan | |
| Orientasi JPEG (EXIF) | Penanda tetap terdeteksi (OpenCV menerapkan EXIF; tidak memengaruhi homografi) | |
| Gerak tangan selama burst | Frame buram ditolak dengan alasan spesifik ("terlalu buram"); kunjungan diterima bila minimal 3 frame lolos | |
| Lembar sebagian tertutup | Pesan "Penanda tertutup"; tombol bidik tetap mati | |
| Terlalu miring (> 20 derajat) | Pesan "Terlalu miring"; instruksi "Luruskan ponsel ..." | |
| Terlalu jauh (> 0,20 mm per piksel) | Pesan "Terlalu jauh dari lembar"; instruksi "Dekatkan ponsel ..." | |

## 8. Panduan pose kunjungan ulang
| Uji | Hasil yang diharapkan | Hasil |
|---|---|---|
| Kunjungan dasar lalu kunjungan ulang beberapa hari kemudian | Bayangan putih putus-putus dari pose dasar tampak; mengikuti instruksi membawa lembar ke bayangan; "Siap" muncul bila selisih di dalam ambang (translasi 3 persen, skala 0,9 sampai 1,1, rotasi 5 derajat, kemiringan 8 derajat) | |
| Ponsel atau orientasi berbeda dari kunjungan dasar | Catatan "Pose acuan berasal dari kamera atau resolusi lain ..." muncul; panduan memakai aturan umum | |
| Stabilitas | Ambang 5 frame stabil (sekitar 0,5 detik) dan batas selisih antar frame (1 persen diagonal, 2 derajat) terlalu ketat atau longgar? Catat dan setel di `FlowConfig` dan `LiveAnalyzer.defaultStability` | |
| Tombol bidik tidak aktif saat deteksi macet | Tutup lensa saat "Siap": dalam sekitar 1 detik status kembali ke "Penanda belum terlihat" | |

## 9. Keamanan data
| Uji | Hasil yang diharapkan | Hasil |
|---|---|---|
| Foto hanya di penyimpanan privat | `adb shell run-as id.vassel.hairline ls files` memuat foto; galeri tidak menampilkannya | |
| Sapuan berkas yatim saat start | Matikan paksa app tepat saat menyimpan, buka lagi: berkas tak terkait hilang | |

## 10. Fase 7: lembar, titik ukur, layar (butuh ponsel dan printer)
| Uji | Hasil yang diharapkan | Hasil |
|---|---|---|
| Cetak PDF A4 dan Letter di printer nyata, "100 persen" | Batang skala terukur 100 mm +- 1 mm dengan penggaris; sisi penanda 30 mm | |
| Cetak dengan "fit to page" menyala | Batang skala meleset; pengguna memasukkan angka ukur sehingga `print_scale` mengoreksi (periksa tampilan skala di langkah 3) | |
| Foto lembar cetak: penanda terdeteksi `hairline_opencv` | Semua id 4s sampai 4s+3 terdeteksi pada 12 lembar (hasil Python/OpenCV di host sudah ada: tools/verify_sheet_raster.py, bukan opencv_dart) | |
| Garis putus-putus dan jendela | Jendela 70 x 70 mm bisa digunting rapi; celah putih 10 mm ke penanda | |
| Printing: dialog cetak dan bagikan | Dialog sistem terbuka; berkas PDF terbagi | |
| Orientasi foto di layar titik ukur | Foto tampil tegak sama dengan hasil dekode OpenCV (EXIF); overlay jendela menimpa jendela di foto. Bila foto tampil terputar, titik meleset: catat | |
| Ketuk retak sungguhan | Titik menempel ke garis tengah retak; arah wajar; segmen 4 mm sejajar | |
| Ketuk retak sangat samar | Pesan "Retak tidak ditemukan ...", tidak ada titik palsu | |
| Dua kunjungan lanjutan dengan retak membesar | Tren menampilkan klasifikasi sesuai; label BELUM_DIVALIDASI tampil | |
| Skala font sistem terbesar dan TalkBack | Tidak ada teks terpotong; pembaca layar membacakan label grafik dan gambar | |

## 11. Fase 8: validasi pelat (menghasilkan angka `PERANGKAT`)
Peralatan: printer, kertas putih, penggaris, pemindai flatbed (minimal 1200 dpi, ideal 2400 dpi) atau lup bertakar, ponsel uji. Agent tidak dapat menjalankan bagian ini; tanpa dijalankan tidak ada angka akurasi perangkat.

| Langkah | Cara | Hasil yang diharapkan | Hasil |
|---|---|---|---|
| 11.1 Cetak pelat | Aplikasi: ikon "Validasi ponsel dengan pelat" di halaman awal > Cetak pelat, 100 persen, tanpa "Fit to page", jangan digunting | Batang skala terukur 100 mm +- 1 mm; 32 garis dan label V1, V2, H1, H2 terbaca | |
| 11.2 Tempel | Tempel pelat rata pada papan keras atau dinding, bidang datar | Tidak ada gelembung atau lipatan | |
| 11.3 Karakterisasi (disarankan) | Pindai pelat rata, abu-abu, tanpa penajaman, simpan TIFF/PNG, ubah ke PGM: `magick scan.tif -colorspace Gray scan.pgm`. Buka di penampil gambar, catat piksel pusat jendela 70 mm (titik asal). `cd tools && dart pub get && dart run measure_scan.dart --image scan.pgm --dpi 2400 --origin X,Y --out truth.csv` (tambah `--angle` bila pelat miring, `--sigma-px` bila penanda tidak ikut terpindai) | Tabel per garis di layar terminal; `truth.csv` berisi 24 sampai 32 baris. Lebar terukur lebih besar dari nominal (dot gain) wajar. Garis `DI_BAWAH_BATAS_UKUR` pada 0,1 mm: naikkan dpi | |
| 11.3b Alternatif | Ukur dengan lup bertakar atau celah feeler gauge, isi CSV `posisi,lebar_mm,u_mm` sendiri (minimal 8 baris, titik desimal) | CSV diterima aplikasi | |
| 11.4 Skala | Ukur batang skala dengan penggaris, masukkan hasilnya (mm) di layar validasi | Skala tercetak ditampilkan di hasil | |
| 11.5 Kebenaran | Pilih "Impor CSV", tempel isi `truth.csv` | Pesan galat spesifik bila CSV rusak (uji dengan CSV salah: header salah, posisi tak dikenal, lebar 10x nominal) | |
| 11.6 Ambil | Mulai validasi, ikuti panduan, ambil burst pada jarak dan cahaya yang SAMA dengan pemakaian untuk retak | Layar hasil validasi dengan label PERANGKAT | |
| 11.7 Baca hasil | Catat per lebar: terukur dari n, bias, RMSE, cakupan; batas bawah empiris; apakah "memenuhi ambang" | Angka berlabel PERANGKAT, model ponsel, tanggal. Catat di README bagian status dengan label itu | |
| 11.8 Efek ke retak | Ukur retak pada ponsel yang sama setelah validasi yang memenuhi ambang | Label BELUM_DIVALIDASI tidak tampil, `u_dev` di anggaran sama dengan hasil validasi | |
| 11.9 Pencabutan | Ulangi validasi dengan kebenaran NOMINAL | Hasil tersimpan tetapi TIDAK memenuhi ambang; pengukuran baru kembali berlabel BELUM_DIVALIDASI | |
| 11.10 Sensitivitas | Ulangi pada jarak lebih jauh dan pada cahaya redup | Lebar terkecil yang terukur andal naik; cakupan dicatat | |
| 11.11 Pindaian vs lup | Bandingkan lebar karakterisasi pindaian dan lup untuk 3 garis | Selisih di dalam `u_mm` keduanya; bila tidak, perbesar `--scale-u-rel` dan laporkan | |

Pertanyaan yang hanya uji ini menjawab: apakah profil retak berkontras rendah diproses ISP ponsel berbeda dari garis cetak hitam (5.3a catatan), apakah cakupan 90 persen bertahan di luar sampel, dan berapa `u_dev` nyata.

## 12. Fase 8: APK rilis
| Uji | Cara | Hasil yang diharapkan | Hasil |
|---|---|---|---|
| Bangun | `cd app && flutter build apk --release && flutter build appbundle --release` | Berhasil; ukuran dicatat di PROGRESS | |
| Izin | `aapt dump permissions app-release.apk` | Hanya `CAMERA` dan izin internal app (`DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`); tanpa `INTERNET` | |
| Tanda tangan | Salin `android/key.properties.example` ke `android/key.properties`, buat keystore (perintah `keytool` di berkas contoh), bangun ulang; `apksigner verify --print-certs app-release.apk` | Sertifikat milik pemilik, bukan "Android Debug" | |
| Pasang dan jalankan | `adb install -r app-release.apk`, buka semua layar | Tidak crash karena R8 (periksa `adb logcat` untuk ClassNotFoundException atau NoSuchMethodError, terutama sqlite, kamera, printing) | |
| Tanpa jaringan | Mode pesawat, jalankan semua alur | Semua berfungsi | |

## 13. Fase 9: banding dengan studi sintetis (setelah bagian 11)
Tujuan: melihat apakah perilaku di ponsel mirip simulasi, tanpa mengklaim hasil simulasi sebagai akurasi perangkat. Bandingkan dengan docs/SYNTHETIC_VALIDATION.md (label SINTETIS) dan tulis kedua angka berdampingan dengan labelnya.
| Langkah | Cara | Hasil yang diharapkan | Hasil |
|---|---|---|---|
| 13.1 Cakupan | Dari hasil validasi PERANGKAT (11.7) ambil cakupan per lebar; bandingkan dengan cakupan SINTETIS pada lebar yang sama (tabel per lebar di dokumen studi) | Cakupan PERANGKAT >= 90 persen pada lebar >= 0,3 mm; bila lebih rendah, `u_dev` terlalu kecil atau profil retak diproses ISP berbeda dari garis cetak: catat dan jangan lepas label | |
| 13.2 Bias | Bandingkan bias PERANGKAT per lebar dengan bias SINTETIS (nilai mikrometer di MEASUREMENT_NOTES) | Bias PERANGKAT lebih besar dari SINTETIS wajar (ISP, JPEG, tanpa linearisasi sempurna); catat tandanya (positif atau negatif) | |
| 13.3 Lebar terkecil | Bandingkan lebar terkecil yang terukur andal (11.7, 11.10) dengan batas pelaporan SINTETIS | Batas PERANGKAT lebih besar; catat | |
| 13.4 Konservatisme | Bandingkan `U` yang ditampilkan (BELUM_DIVALIDASI) dengan galat nyata pelat | Studi sintetis menemukan `U` sekitar 20 kali galat; pada ponsel nyata galat lebih besar, jadi rasio itu mengecil. Rasio < 1 berarti `U` terlalu optimistis: laporkan | |
| 13.5 Positif palsu tren | Ukur dua kunjungan dari retak yang sama (pelat tidak berubah) pada hari berbeda, 10 pasang | Tidak lebih dari 1 pasang dengan z di luar rentang -2 sampai 2 (SINTETIS: positif palsu 0,2 sampai 4,6 persen) | |
| 13.6 Waktu | Catat waktu pemrosesan satu kunjungan (6 foto) | Dicatat; studi tidak mengukur ponsel | |

## 14. Fase 9: uji kunjungan nyata dua minggu
Peralatan: ponsel yang sudah lolos bagian 11 (idealnya), lembar cetak 100 persen yang skalanya diukur, retak nyata (atau retak buatan di dinding uji), lem permanen.
| Hari | Cara | Hasil yang diharapkan | Hasil |
|---|---|---|---|
| 0 | Tempel lembar rata, retak di jendela 70 x 70 mm. Tambah situs dan retak di app, masukkan skala dan relief. Kunjungan dasar: ikuti panduan, ketuk retak | Foto dasar lolos; lebar +- U, `mm_per_px` <= 0,10, label sesuai status validasi; hasil dasar dicatat tangan (foto, lebar yang tampak dengan lup) | |
| 0 | Segera ulang kunjungan kedua dari awal (tanpa membuka layar hasil) | z dalam rentang -2 sampai 2 ("tidak ada perubahan terdeteksi"); catat `delta`, `u_delta`, MDC | |
| 1, 3, 7, 10, 14 | Kunjungan lanjutan pada jam dan cahaya yang berbeda; gunakan hantu pose | Setiap kunjungan diterima (>= 3 frame) atau ditolak dengan alasan spesifik; catat berapa kali panduan menyatakan siap tanpa bantuan | |
| Tiap kunjungan | Catat apakah peringatan muncul (TRACKING_OFFSET, MODEL_MISFIT, dll.) | Tidak ada pada lembar yang tidak disentuh; bila muncul tanpa sebab, laporkan | |
| Hari 5 | Sengaja geser lembar sekitar 1 mm (atau lepas dan tempel ulang, uji pada salinan retak) | Peringatan lembar bergeser muncul, atau retak ditolak; seri harus dianggap terputus | |
| Hari 14 | Buka layar tren | Grafik dengan batang ketidakpastian, tanda perubahan hanya bila melampaui `u_delta`; tidak ada ekstrapolasi | |
| Akhir | Bandingkan dengan hasil lup atau jangka sorong pada hari 0 dan 14 | Selisih wajar terhadap `U`; catat hasil dengan label PERANGKAT | |
| Akhir | Baca semua layar dengan huruf besar dan TalkBack | Semua terbaca, tidak ada teks terpotong | |
