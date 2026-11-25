// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:hairline_core/hairline_core.dart';

/// Central catalog of user-visible text (Bahasa Indonesia). Widgets never hold literals.
abstract final class Strings {
  // Capture screen.
  static const captureTitle = 'Ambil foto retak';
  static const shutter = 'Bidik';
  static const shutterDisabledHint = 'Tombol bidik aktif setelah posisi ponsel sesuai dan stabil.';
  static const retry = 'Ulangi';
  static const close = 'Tutup';
  static const baselineHint = 'Kunjungan dasar: posisi ponsel saat ini akan menjadi acuan kunjungan berikutnya.';
  static const referenceMissingHint = 'Pose acuan kunjungan dasar tidak tersedia. Panduan memakai syarat umum.';
  static const referenceIncompatibleHint = 'Pose acuan berasal dari kamera atau resolusi lain, panduan memakai syarat umum.';

  // Status per phase (icon plus text, never color alone).
  static const statusWaiting = 'Penanda belum terlihat';
  static const statusAdjusting = 'Sesuaikan posisi ponsel';
  static const statusReady = 'Siap diambil, tahan ponsel';
  static const statusBurst = 'Mengambil foto, jangan bergerak';
  static const statusProcessing = 'Memeriksa kualitas foto';
  static const statusBaselineCaptured = 'Foto dasar diambil, tentukan titik ukur';
  static const baselineCapturedHint = 'Foto dasar lolos pemeriksaan geometri. Langkah berikutnya: ketuk retak pada foto untuk menentukan titik ukur.';
  static const choosePoint = 'Tentukan titik ukur';
  static const openResult = 'Lihat hasil';
  static const statusResultStored = 'Kunjungan tersimpan';
  static const statusResultRejected = 'Foto belum memenuhi syarat, tidak disimpan';
  static const statusValidated = 'Validasi tersimpan';
  static const statusError = 'Terjadi masalah';
  static const waitingHint = 'Arahkan kamera ke lembar bingkai sampai minimal tiga penanda terlihat utuh.';

  static String burstProgress(int taken, int total) => 'Foto $taken dari $total';
  static String processProgress(int done, int total) => 'Memeriksa foto $done dari $total';
  static String markersSeen(int n) => 'Penanda terlihat: $n dari 4';

  static String tilt(double deg) => 'Kemiringan perkiraan: ${num(deg, 0)} derajat';
  static String scale(double mmPerPx) => 'Skala perkiraan: ${num(mmPerPx, 3)} mm per piksel';
  static const tiltAndScaleApprox = 'Nilai kemiringan dan skala hanya perkiraan (kamera belum dikalibrasi).';

  static String num(double v, int digits) => v.toStringAsFixed(digits).replaceFirst('.', ',');

  /// What to do with the phone for each pose instruction (5.2).
  static String instruction(PoseInstruction i) => switch (i) {
        PoseInstruction.holdFlat => 'Luruskan ponsel agar tegak lurus terhadap lembar',
        PoseInstruction.closer => 'Dekatkan ponsel ke lembar',
        PoseInstruction.farther => 'Jauhkan ponsel dari lembar',
        PoseInstruction.rotateCw => 'Putar ponsel searah jarum jam',
        PoseInstruction.rotateCcw => 'Putar ponsel berlawanan arah jarum jam',
        PoseInstruction.moveLeft => 'Geser ponsel ke kiri',
        PoseInstruction.moveRight => 'Geser ponsel ke kanan',
        PoseInstruction.moveUp => 'Geser ponsel ke atas',
        PoseInstruction.moveDown => 'Geser ponsel ke bawah',
      };

  /// Short reason shown live when the geometry gate would reject the frame.
  static String rejection(FrameRejection r) => switch (r) {
        FrameRejection.tooFewMarkers => 'Penanda tertutup',
        FrameRejection.rmsTooHigh => 'Posisi penanda tidak konsisten',
        FrameRejection.looTooHigh => 'Lembar tidak rata',
        FrameRejection.tiltTooHigh => 'Terlalu miring',
        FrameRejection.tiltHardReject => 'Sangat miring',
        FrameRejection.resolutionTooCoarse => 'Terlalu jauh dari lembar',
        FrameRejection.homographyFailed => 'Posisi penanda tidak dapat dihitung',
        FrameRejection.imageUnreadable => 'Foto tidak terbaca',
      };

  // Capture flags saved with the visit.
  static const flagFocusNotLocked = 'fokus_tidak_terkunci';
  static const flagExposureNotLocked = 'eksposur_tidak_terkunci';
  static const warnFocusNotLocked =
      'Fokus tidak dapat dikunci di perangkat ini. Foto tetap diperiksa kualitasnya, tetapi mungkin buram.';
  static const warnExposureNotLocked = 'Eksposur tidak dapat dikunci di perangkat ini. Kecerahan foto bisa berubah antar bidikan.';

  // Result.
  static String framesAccepted(int accepted, int total) => '$accepted dari $total foto diterima';
  static const resultIndicative =
      'Hasil bersifat indikatif dan bukan pengganti inspeksi insinyur struktur. Bila retak tampak melebar, bertambah panjang, '
      'atau muncul retak baru, hubungi insinyur atau pihak berwenang.';
  static const notValidated = 'BELUM_DIVALIDASI';
  static const statusNotMeasurable = 'Tidak terukur';
  static String widthWithU(double w, double u, double k) =>
      'Lebar ${num(w, 3)} mm, ketidakpastian diperluas ${num(u, 3)} mm (k = ${num(k, 2)})';
  static String belowFloor(double floorMm) => 'Di bawah batas ukur (< ${num(floorMm, 3)} mm)';

  // Camera and pipeline errors.
  static const errPermissionDenied = 'Izin kamera ditolak. Izinkan kamera untuk Hairline di pengaturan ponsel, lalu buka layar ini lagi.';
  static const errPermissionDeniedForever =
      'Izin kamera diblokir. Buka Pengaturan > Aplikasi > Hairline > Izin, aktifkan Kamera, lalu coba lagi.';
  static const errNoCamera = 'Kamera belakang tidak ditemukan di perangkat ini.';
  static const errCameraOpen = 'Kamera tidak dapat dibuka. Tutup aplikasi lain yang memakai kamera, lalu ulangi.';
  static const errCameraInterrupted = 'Pemotretan terputus (aplikasi sempat berpindah atau ada panggilan masuk). Ulangi pemotretan.';
  static const errCameraBusy = 'Kamera sedang dipakai untuk pemotretan. Tunggu sebentar.';
  static const errCapture = 'Foto gagal diambil. Ulangi pemotretan.';
  static const errDetector =
      'Detektor penanda belum tersedia di build ini (pustaka OpenCV belum tersambung). Pengambilan foto tidak dapat dipandu.';
  static const errDetectorCrashed = 'Pendeteksi penanda berhenti tak terduga. Tutup layar ini dan buka lagi.';
  static const errProcessing = 'Pemrosesan foto gagal. Ulangi pemotretan.';
  static const errStartup = 'Layar pengambilan foto gagal dimulai. Tutup layar ini dan buka lagi.';
  static const errCrackMissing = 'Data retak tidak ditemukan. Kembali dan pilih retak lagi.';

  // Shared.
  static const appName = 'Hairline';
  static const menuHelp = 'Bantuan';
  static const menuAbout = 'Tentang';
  static const save = 'Simpan';
  static const next = 'Lanjut';
  static const back = 'Kembali';
  static const loading = 'Memuat';
  static const errLoad = 'Data tidak dapat dimuat. Tutup layar ini dan buka lagi.';
  static const errSave = 'Data tidak dapat disimpan. Coba lagi.';

  // Sites.
  static const sitesTitle = 'Situs';
  static const sitesEmpty = 'Belum ada situs. Tambahkan situs, misalnya nama bangunan, lalu catat retaknya.';
  static const addSite = 'Tambah situs';
  static const siteName = 'Nama situs';
  static const siteNotes = 'Catatan (opsional)';
  static const siteLat = 'Lintang (opsional, ketik sendiri)';
  static const siteLon = 'Bujur (opsional, ketik sendiri)';
  static const siteLocationHint = 'Lokasi hanya disimpan di ponsel ini dan tidak pernah diminta lewat izin lokasi.';
  static const errSiteName = 'Nama situs wajib diisi.';
  static const errLat = 'Lintang harus berupa angka antara -90 dan 90.';
  static const errLon = 'Bujur harus berupa angka antara -180 dan 180.';
  static const errLatLonPair = 'Isi lintang dan bujur bersama-sama, atau kosongkan keduanya.';

  // Cracks.
  static String cracksTitle(String site) => 'Retak di $site';
  static const cracksEmpty = 'Belum ada retak di situs ini. Tambahkan retak lalu pasang lembar bingkai di sekelilingnya.';
  static const addCrack = 'Tambah retak';
  static const crackLabel = 'Label retak';
  static const crackLabelHint = 'Contoh: dinding kamar tidur, dekat jendela';
  static const sheetNumber = 'Nomor lembar';
  static const sheetNumberHint = 'Pilih 0 sampai 11. Pakai nomor berbeda untuk tiap retak di satu lokasi agar tidak tertukar.';
  static String sheetOption(int s) => 'Lembar $s (penanda ${4 * s} sampai ${4 * s + 3})';
  static const crackNoBaseline = 'Belum ada kunjungan dasar';
  static String crackVisitCount(int n) => '$n kunjungan';
  static const crackNotFound = 'Retak tidak ditemukan.';

  // Guided setup (add crack).
  static const setupTitle = 'Pasang lembar bingkai';
  static String setupStepOf(int step, int total) => 'Langkah $step dari $total';
  static const setupDataTitle = 'Data retak';
  static const setupDataBody = 'Beri label retak dan pilih nomor lembar yang akan dicetak.';
  static const setupPrintTitle = 'Cetak 100 persen';
  static const setupPrintBody =
      'Cetak lembar dengan ukuran asli (100 persen). Matikan pilihan "Fit to page" atau "Sesuaikan ke halaman" di pengaturan cetak. '
      'Pakai kertas putih biasa dan cetak hitam pekat.';
  static const paperSize = 'Ukuran kertas';
  static const printSheet = 'Cetak lembar';
  static const shareSheet = 'Bagikan PDF';
  static const errPrint = 'Lembar tidak dapat dicetak atau dibagikan dari ponsel ini. Bagikan berkasnya ke aplikasi lain lalu cetak dari sana.';
  static const setupRulerTitle = 'Ukur batang skala';
  static const setupRulerBody =
      'Ukur batang skala di bagian bawah bingkai dengan penggaris, dari ujung tanda kiri sampai ujung tanda kanan. '
      'Hasilnya harus mendekati 100 mm. Masukkan angka yang Anda baca, dalam milimeter.';
  static const rulerReading = 'Hasil ukur batang skala (mm)';
  static const errRulerNumber = 'Masukkan angka dalam milimeter, misalnya 99,5.';
  static String errRulerRange(double lo, double hi) =>
      'Angka di luar rentang ${num(lo, 0)} sampai ${num(hi, 0)} mm. Pastikan satuannya milimeter dan yang diukur adalah batang skala.';
  static String printScaleResult(double scale, double uRelPercent) =>
      'Skala cetak ${num(scale, 4)} (ketidakpastian pembacaan penggaris sekitar ${num(uRelPercent, 2)} persen).';
  static const setupCutTitle = 'Gunting jendela';
  static const setupCutBody =
      'Gunting tepat di garis putus-putus sehingga jendela persegi 70 x 70 mm terbuka. Jangan memotong penanda hitam.';
  static const setupMountTitle = 'Tempel rata dan permanen';
  static const setupMountBody =
      'Tempelkan lembar pada bidang yang sama dengan retak, dengan retak terlihat penuh di dalam jendela. Rekatkan rata dan kuat '
      '(lem atau selotip dua sisi di seluruh tepi), tanpa kerutan dan tanpa gelembung.';
  static const setupMountWarning =
      'Jangan memindahkan lembar. Bila lembar bergeser atau dilepas, seri pengukuran retak ini terputus dan harus dimulai baru: buat retak baru dan ulangi pemasangan.';
  static const setupReliefTitle = 'Relief permukaan';
  static const setupReliefBody =
      'Bila permukaan di sekitar retak tidak rata (misalnya plesteran kasar), jarak antara lembar dan retak bisa berbeda beberapa persepuluh milimeter. '
      'Pilih perkiraan relief; nilai yang lebih besar membuat ketidakpastian lebih besar.';
  static const reliefSmooth = 'Rata, 0,3 mm';
  static const reliefRough = 'Kasar, 1,0 mm';
  static const setupFinish = 'Simpan retak';
  static const sheetIllustrationPrint = 'Gambar: lembar di dalam pencetak, pengaturan ukuran 100 persen.';
  static const sheetIllustrationRuler = 'Gambar: penggaris di atas batang skala 100 mm.';
  static const sheetIllustrationCut = 'Gambar: gunting memotong garis putus-putus di sekeliling jendela.';
  static const sheetIllustrationMount = 'Gambar: lembar tertempel rata pada dinding, retak berada di dalam jendela.';
  static const sheetIllustrationRelief = 'Gambar: penampang permukaan dengan jarak relief antara lembar dan retak.';

  // Text printed on the sheet (Latin-1 only, standard PDF font).
  static String sheetPrintedTitle(int s) => 'LEMBAR $s';
  static const sheetPrintedCutHint = 'Potong garis putus-putus';
  static const sheetPrintedScaleBar = 'Batang skala: harus tepat 100 mm bila dicetak 100 persen';
  static const sheetPrintedNotes = [
    'CETAK 100 PERSEN (ukuran asli). Matikan "Fit to page" / "Sesuaikan ke halaman".',
    'Ukur batang skala dengan penggaris dan masukkan hasilnya di aplikasi Hairline.',
    'Tempel rata dan permanen pada bidang yang sama dengan retak. Jangan dipindahkan.',
  ];

  // Crack detail.
  static const crackDetailTitle = 'Detail retak';
  static String crackInfo(int sheet, double scale) => 'Lembar $sheet, skala cetak ${num(scale, 4)}';
  static const visitsTitle = 'Kunjungan';
  static const noVisits = 'Belum ada kunjungan. Mulai dengan kunjungan dasar: foto pertama menjadi acuan semua kunjungan berikutnya.';
  static const newBaselineVisit = 'Ambil kunjungan dasar';
  static const newFollowupVisit = 'Kunjungan baru';
  static const viewTrend = 'Lihat tren';
  static const visitBaseline = 'Kunjungan dasar';
  static const visitFollowup = 'Kunjungan lanjutan';
  static const seriesBrokenNote =
      'Bila lembar bergeser atau dilepas, seri pengukuran retak ini terputus. Buat retak baru dan mulai dari kunjungan dasar.';
  static String date(DateTime t) {
    final l = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
  }

  static String dateShort(DateTime t) {
    final l = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}';
  }

  // Measurement point screen.
  static const pointTitle = 'Tentukan titik ukur';
  static const pointInstruction =
      'Ketuk retak di dalam jendela, dekat bagian tengah. Titik dipasang pada garis tengah retak terdekat. Anda dapat mengetuk lagi untuk memindahkannya.';
  static const pointZoneHint = 'Kotak putus-putus menandai area ukur 50 x 50 mm. Garis tebal menandai jendela 70 x 70 mm.';
  static const pointPreparing = 'Menyiapkan foto';
  static const pointLocating = 'Mencari retak';
  static const pointSegmentCaption = 'Garis pendek: segmen 4 mm yang dirata-ratakan, searah retak.';
  static String pointDirection(double deg) => 'Arah retak: ${num(deg, 0)} derajat dari sumbu x lembar';
  static String pointCoordinates(double x, double y) => 'Posisi pada lembar: x ${num(x, 2)} mm, y ${num(y, 2)} mm dari pusat jendela';
  static const pointConfirm = 'Gunakan titik ini';
  static const pointSaving = 'Menyimpan kunjungan dasar';
  static const pointNoPending = 'Foto dasar tidak ada lagi (aplikasi sempat ditutup). Ambil foto dasar lagi.';
  static const pointRecapture = 'Ambil ulang foto dasar';
  static const pointPhotoMissing = 'Foto tidak dapat ditampilkan.';
  static const pointPhotoSemantics = 'Foto dasar retak. Ketuk retak untuk menentukan titik ukur.';
  static const pointNotStored = 'Kunjungan dasar tidak disimpan.';

  // Result screen.
  static const resultTitle = 'Hasil kunjungan';
  static const resultNotFound = 'Kunjungan tidak ditemukan.';
  static String resultWidthHeadline(double w, double u) => '${num(w, 3)} ± ${num(u, 3)} mm';
  static const resultWidthMeaning = 'Lebar retak w ± U. U adalah ketidakpastian diperluas, tingkat kepercayaan sekitar 95 persen.';
  static String resultBelowFloor(double floorMm) => belowFloor(floorMm);
  static const resultBelowFloorMeaning =
      'Retak terlalu sempit untuk diukur dengan jarak dan foto ini. Tidak ada angka lebar yang ditampilkan. Dekatkan ponsel bila memungkinkan.';
  static const resultNotMeasurableMeaning = 'Lebar tidak dapat ditentukan dari foto-foto ini, sehingga tidak ada angka yang ditampilkan.';
  static const reasonMostlyUnmeasurable =
      'Sebagian besar foto yang diterima tidak memenuhi syarat kontras atau kecocokan model: retak terlalu samar, terlalu sempit, atau bentuknya tidak seperti garis.';
  static const reasonTooFewFrames = 'Foto yang diterima kurang dari 3.';
  static String resultFramesAccepted(int n) => '$n foto diterima';
  static String resultMmPerPx(double v) => 'Skala foto: ${num(v, 3)} mm per piksel';
  static String resultAlgorithm(String v) => 'Versi algoritma: $v';
  static String resultDevice(String model) => 'Ponsel: $model';
  static const notValidatedBadge = 'BELUM_DIVALIDASI';
  static const notValidatedMeaning =
      'Ponsel ini belum divalidasi dengan pelat kalibrasi. Komponen ketidakpastian sistematis perangkat memakai nilai awal konservatif yang tidak tervalidasi, '
      'sehingga angka akurasi belum dapat dinyatakan.';
  static const componentsTitle = 'Rincian ketidakpastian (mm, ketidakpastian baku)';
  static const resultPhotoTitle = 'Foto terbaik kunjungan ini';
  static const resultPhotoMissing = 'Foto tidak dapat ditampilkan.';
  static const resultBaselineNote = 'Ini kunjungan dasar. Pembanding baru tersedia setelah kunjungan lanjutan.';
  static String componentLabel(String key) => switch (key) {
        'u_fit_mean' => 'u_fit (rata-rata penyesuaian model)',
        'u_repeat' => 'u_repeat (sebaran antar foto)',
        'u_stat' => 'u_stat (terbesar dari keduanya)',
        'u_sigma_w' => 'u_sigma_w (lebar blur dari tepi penanda)',
        'u_pos' => 'u_pos (galat posisi lembar x kemiringan lebar)',
        'u_par' => 'u_par (paralaks relief permukaan)',
        'u_geo' => 'u_geo (galat geometri homografi)',
        'u_print' => 'u_print (skala cetak, sistematis)',
        'u_dev' => 'u_dev (perangkat, sistematis)',
        'u_rand' => 'u_rand (gabungan acak)',
        'u_sys' => 'u_sys (gabungan sistematis)',
        'u_c' => 'u_c (gabungan baku)',
        'u_expanded' => 'U = k x u_c (diperluas)',
        _ => key,
      };
  static String kFactor(double k) => 'Faktor cakupan k = ${num(k, 2)} (95 persen)';

  // Honest statements (CLAUDE.md section 1), shown on result, help and trend.
  static const honestyTitle = 'Pernyataan jujur';
  static const honestyIndicative =
      'Hasil bersifat indikatif dan bukan pengganti inspeksi insinyur struktur. Hairline tidak menilai keselamatan bangunan.';
  static const honestyNoChange =
      '"Tidak ada perubahan terdeteksi" berarti perubahan, jika ada, lebih kecil dari ketidakpastian pengukuran. Itu bukan bukti bahwa retak tidak berubah.';
  static const honestyAccuracy =
      'Angka akurasi hanya berlaku bila berlabel asalnya: SINTETIS (dari simulasi) atau PERANGKAT (dari validasi pelat pada ponsel nyata). '
      'Saat ini belum ada validasi PERANGKAT di aplikasi ini.';
  static const honestyCoplanar =
      'Hairline tidak mengukur secara akurat retak yang tidak sebidang dengan lembar penanda, dan tidak cocok untuk keputusan regulasi.';
  static const honestyEngineer =
      'Bila retak tampak melebar, bertambah panjang, atau muncul retak baru, hubungi insinyur atau pihak berwenang.';

  // Trend screen.
  static const trendTitle = 'Tren lebar retak';
  static const trendNeedTwo = 'Tren membutuhkan minimal 2 kunjungan. Lakukan kunjungan lanjutan untuk membandingkan dengan kunjungan dasar.';
  static const trendBaselineLine = 'Garis putus-putus: lebar kunjungan dasar';
  static const trendChartNote = 'Batang: w ± U (95 persen). Bentuk titik: lingkaran = tidak ada perubahan terdeteksi, segitiga naik = kemungkinan bertambah lebar, segitiga turun = kemungkinan menyempit, silang = tidak terukur.';
  static String trendChartSemantics(List<String> items) => 'Grafik lebar retak terhadap waktu. ${items.join('. ')}.';
  static String trendChartItem(int n, String date, String what) => 'Kunjungan $n, $date: $what';
  static String trendXAxisLabel(DateTime t) => dateShort(t);
  static String trendYAxisLabel(double v) => '${num(v, 2)} mm';
  static String trendClass(TrendClass c) => switch (c) {
        TrendClass.tidakAdaPerubahanTerdeteksi => 'Tidak ada perubahan terdeteksi',
        TrendClass.kemungkinanBertambahLebar => 'Kemungkinan bertambah lebar',
        TrendClass.kemungkinanMenyempit => 'Kemungkinan menyempit',
        TrendClass.tidakTerukur => 'Tidak terukur',
      };
  static const trendClassNoneNote = 'Perubahan, jika ada, lebih kecil dari ketidakpastian pengukuran.';
  static const trendBaselineTag = 'Kunjungan dasar (pembanding)';
  static const trendVsBaseline = 'Terhadap kunjungan dasar';
  static const trendVsPrevious = 'Terhadap kunjungan sebelumnya';
  static String trendDelta(double delta, double uDelta) =>
      'Selisih ${delta >= 0 ? '+' : '-'}${num(delta.abs(), 3)} mm, ketidakpastian selisih ${num(uDelta, 3)} mm';
  static String trendMdc(double mdc) => 'Perubahan minimum yang dapat dideteksi (MDC): ${num(mdc, 3)} mm';
  static String trendVisitWidth(double w, double u) => 'w = ${num(w, 3)} ± ${num(u, 3)} mm';
  static const trendNoNumber = 'tidak ada angka lebar';
  static const trendNoForecast = 'Tren hanya membandingkan pasangan kunjungan. Tidak ada garis regresi dan tidak ada perkiraan ke depan.';
  static String contextWarning(ContextWarning w) => switch (w) {
        ContextWarning.deviceModelDiffers => 'Model ponsel berbeda dari pembanding: pembatalan galat sistematis kurang andal.',
        ContextWarning.algorithmVersionDiffers => 'Versi algoritma berbeda dari pembanding. Proses ulang kunjungan agar sama.',
        ContextWarning.sheetDiffers => 'Lembar berbeda dari pembanding. Seri pengukuran seharusnya memakai satu lembar yang tidak dipindah.',
      };
  static const trendWarningsTitle = 'Peringatan konteks';
  static const reprocess = 'Proses ulang kunjungan';
  static const reprocessBody = 'Mengukur ulang foto tersimpan dengan versi algoritma terbaru. Hasil lama tidak dihapus.';
  static String reprocessUpToDate(String v) => 'Semua kunjungan sudah memakai versi algoritma $v.';
  static String reprocessProgress(int done, int total) => 'Memproses ulang kunjungan $done dari $total';
  static String reprocessDone(int ok, int failed) =>
      failed == 0 ? '$ok kunjungan diproses ulang.' : '$ok kunjungan diproses ulang, $failed gagal (foto tidak memenuhi syarat atau berkas rusak).';

  // Help.
  static const helpTitle = 'Bantuan';
  static const helpHowTitle = 'Cara mengukur dengan benar';
  static const helpHow = [
    'Pasang lembar bingkai rata dan permanen pada bidang yang sama dengan retak, dengan retak di dalam jendela. Jangan dipindahkan.',
    'Cetak 100 persen dan ukur batang skala dengan penggaris. Masukkan hasilnya di aplikasi.',
    'Ambil foto dengan cahaya cukup dan merata, tanpa silau. Pegang ponsel sejajar dengan lembar dan diam saat pemotretan.',
    'Ikuti panduan di layar. Pada kunjungan lanjutan, cocokkan posisi ponsel dengan garis hantu dari kunjungan dasar.',
    'Ulangi pada selang waktu yang teratur dan bandingkan di layar tren.',
  ];
  static const helpLimitsTitle = 'Keterbatasan';
  static const helpLimits = [
    'Hanya satu titik ukur pada tiap retak, yaitu lebar rata-rata pada segmen 4 mm di titik itu.',
    'Retak yang lebih sempit dari batas ukur ditampilkan sebagai "di bawah batas ukur", tanpa angka.',
    'Foto buram, miring, gelap, silau, atau penanda tertutup ditolak. Pesan di layar menyebut alasannya.',
    'Permukaan yang tidak rata menambah ketidakpastian (pengaturan relief).',
    'Ketidakpastian ditampilkan apa adanya dan bisa lebih lebar dari yang Anda duga. Itu disengaja.',
  ];
  static const helpResultsTitle = 'Arti tanda pada hasil';
  static const helpResults = [
    'BELUM_DIVALIDASI: ponsel ini belum diuji dengan pelat kalibrasi.',
    'Di bawah batas ukur: retak lebih sempit dari yang dapat diukur dengan jarak foto ini.',
    'Tidak terukur: foto-foto tidak cukup jelas untuk menentukan lebar.',
    'Kemungkinan bertambah lebar atau menyempit: selisih lebih dari dua kali ketidakpastian selisih. Bukan penilaian tingkat keparahan.',
  ];

  // About.
  static const aboutTitle = 'Tentang Hairline';
  static String aboutVersion(String v) => 'Versi $v';
  static String aboutCoreVersion(String v) => 'Pustaka inti hairline_core $v';
  static const aboutPurpose = 'Pemantauan perkembangan lebar retak bangunan oleh non-profesional, dengan ketidakpastian yang ditampilkan jujur.';
  static const aboutOwner = 'Pemilik dan pemegang hak cipta: Vassel Goleyu';
  static const aboutLicense = 'Lisensi MIT. Hak cipta (c) 2026 Vassel Goleyu.';
  static const aboutPrivacy = 'Semua data tersimpan di ponsel ini. Versi rilis tidak memakai internet dan hanya meminta izin kamera.';
  static const aboutThirdParty = 'Lisensi paket pihak ketiga';

  // Plate validation (phase 8).
  static const validationEntry = 'Validasi ponsel dengan pelat';
  static const validationTitle = 'Validasi dengan pelat kalibrasi';
  static const validationIntro =
      'Cetak pelat validasi, ukur batang skalanya, lalu foto pelat dengan alur yang sama seperti retak. Aplikasi mengukur 32 garis hitam berlebar tertentu '
      'dan membandingkannya dengan lebar sebenarnya. Hasilnya hanya berlaku untuk ponsel ini, jarak, dan pencahayaan saat uji.';
  static const validationPlateSection = '1. Cetak pelat';
  static const validationPlateBody =
      'Cetak 100 persen tanpa "Fit to page", jangan dipotong, tempel rata pada permukaan keras. Lebar garis tercetak berbeda dari nominal (toner atau tinta menyebar), '
      'jadi lebar sebenarnya sebaiknya diukur dengan pemindai flatbed minimal 2400 dpi (lihat tools/measure_scan.dart) atau lup bertakar.';
  static const printPlate = 'Cetak pelat';
  static const sharePlate = 'Bagikan PDF pelat';
  static const validationScaleSection = '2. Ukur batang skala';
  static const validationTruthSection = '3. Lebar sebenarnya garis';
  static const truthNominal = 'NOMINAL (tidak dikarakterisasi)';
  static const truthNominalBody =
      'Memakai lebar nominal dengan ketidakpastian awal di bawah. Ini nilai awal, bukan hasil ukur. Hasil dengan kebenaran nominal disimpan tetapi tidak pernah dianggap sebagai validasi.';
  static const truthCsv = 'Impor CSV hasil karakterisasi';
  static const truthCsvBody = 'Tempel isi berkas CSV dengan baris pertama persis: posisi,lebar_mm,u_mm. Contoh baris: V1-3,0.331,0.008 (titik desimal).';
  static const truthCsvField = 'Isi CSV';
  static const truthCsvPaste = 'Tempel dari papan klip';
  static const uTruthField = 'u_truth awal (mm)';
  static const errUTruth = 'Masukkan angka antara 0 dan 1 mm, misalnya 0,05.';
  static const errCsvEmpty = 'Tempel isi CSV terlebih dahulu.';
  static const validationStart = 'Mulai validasi';
  static const validationRunsTitle = 'Validasi sebelumnya';
  static const validationNoRuns = 'Belum ada validasi.';
  static const validationCaptureTitle = 'Foto pelat validasi';
  static const validationCaptureHint = 'Arahkan kamera ke pelat validasi (lembar 11). Alur sama seperti retak: ikuti panduan dan tahan ponsel diam.';
  static const validationResultTitle = 'Hasil validasi';
  static const sourcePerangkat = 'PERANGKAT';
  static const sourceSintetis = 'SINTETIS';
  static const sourceSintetisNote = 'SINTETIS: dari foto simulasi, bukan dari ponsel. Tidak mengubah ketidakpastian pengukuran retak mana pun.';
  static const sourcePerangkatNote = 'PERANGKAT: dari foto pelat yang diambil ponsel ini.';
  static const verdictValidated =
      'Memenuhi ambang validasi. Ketidakpastian perangkat (u_dev) untuk ponsel ini kini diturunkan dari bias yang terukur, dan label BELUM_DIVALIDASI tidak lagi tampil pada pengukuran baru.';
  static const verdictNotValidated =
      'Belum memenuhi ambang validasi. Label BELUM_DIVALIDASI tetap tampil dan u_dev tetap nilai awal yang konservatif.';
  static const validationScope =
      'Angka di bawah hanya berlaku untuk ponsel ini, jarak dan pencahayaan saat uji, dan kebenaran dasar yang dipakai. Cakupan dihitung pada data yang sama dengan penurunan u_dev, jadi cenderung optimistis.';
  static String validationTruthSource(bool characterized) => characterized ? 'Kebenaran dasar: KARAKTERISASI (CSV)' : 'Kebenaran dasar: $truthNominal';
  static String validationOverall(int reported, int n, String bias, String rmse, String coverage) =>
      'Garis terukur $reported dari $n. Bias $bias mm, RMSE $rmse mm, cakupan $coverage.';
  static String validationLowerLimit(String mm) => 'Batas pelaporan bawah empiris: $mm mm (lebar terkecil yang terukur andal bersama semua lebar di atasnya).';
  static const validationNoLowerLimit = 'Batas pelaporan bawah empiris: belum ada lebar yang terukur andal.';
  static const validationGroupsTitle = 'Galat per lebar';
  static String validationGroupRow(String truth, int reported, int n, String bias, String rmse, String coverage) =>
      'Lebar $truth mm: terukur $reported dari $n, bias $bias mm, RMSE $rmse mm, cakupan $coverage';
  static const validationLinesTitle = 'Semua garis';
  static String validationLineRow(String id, String truth, String measured, String status) => '$id (sebenarnya $truth mm): $measured, $status';
  static const validationRecommendTitle = 'Saran';
  static const recCloser = 'Dekatkan ponsel sampai penanda mengisi layar: skala mm per piksel lebih kecil membuat garis sempit terukur.';
  static const recLight = 'Pakai cahaya merata tanpa silau dan tanpa bayangan pada pelat.';
  static const recSteady = 'Tahan ponsel lebih diam atau sandarkan pada permukaan: foto buram ditolak.';
  static const recUseCsv = 'Karakterisasi lebar garis dengan pemindai flatbed atau lup, impor CSV-nya, lalu ulangi validasi.';
  static const recRepeat = 'Ulangi validasi bila kondisi pengukuran retak (jarak, cahaya) berbeda dari kondisi uji ini.';
  static const validationNotStoredTitle = 'Validasi tidak disimpan';
  static const validationOpenResult = 'Lihat hasil validasi';
  static String validationRunTitle(String when, String model) => '$when, $model';
  static String validationRunSubtitle(String source, String truth, bool validated) =>
      '$source, $truth${validated ? ', memenuhi ambang' : ', belum memenuhi ambang'}';
  static String validationDevResult(String mm) => 'u_dev untuk lebar sebanding dengan hasil ini: sekitar $mm mm.';
  static const printPlateTitleLabel = 'PELAT VALIDASI';
  static const plateCutHint = 'Pelat kalibrasi: jangan dipotong';
  static const plateLegend = [
    'Nomor garis: 1 = 0,1 mm   2 = 0,2 mm   3 = 0,3 mm   4 = 0,5 mm',
    '5 = 0,8 mm   6 = 1,0 mm   7 = 1,5 mm   8 = 2,0 mm (nominal)',
    'V1, V2: garis tegak. H1, H2: garis mendatar.',
    'Lebar tercetak berbeda dari nominal: karakterisasi dahulu.',
  ];

  // Debug.
  static const fakePreview = 'Simulasi kamera (tanpa kamera nyata)';
  static const demoPreparing = 'Menyiapkan simulasi (membuat foto sintetis, sekitar setengah menit)';
}
