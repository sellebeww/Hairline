# DEVICE_TEST: daftar uji manual di ponsel Android

Status: **belum dijalankan**. Agent tidak punya ponsel, kamera, atau lembar cetak nyata (CLAUDE.md aturan 7). Semua butir di bawah berstatus `SELESAI-PERLU-UJI-PERANGKAT` sampai pemilik mengisi kolom hasil. Catat model ponsel, versi Android, dan tanggal untuk setiap uji. Jangan menulis angka tanpa label `PERANGKAT` dan tanpa data yang benar-benar diukur.

Prasyarat build (BLOCKERS B1): app harus sudah bergantung pada `packages/hairline_opencv` dan `main.dart` harus meng-override `framePortsFactoryProvider` dengan `openCvPorts` dan `grayDetectorFactoryProvider` dengan `openCvGrayDetector` (DECISIONS D34, D40). Tanpa itu layar pengambilan hanya menampilkan "Detektor penanda belum tersedia". Pasang lembar bingkai nomor 0 (cetak 100 persen, skala dicek dengan penggaris) rata pada bidang uji. Di build debug, tombol "Uji pengambilan foto (debug, kamera nyata)" di halaman awal membuat retak uji (lembar 0, skala 1, titik di pusat jendela, arah 0 derajat).

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
