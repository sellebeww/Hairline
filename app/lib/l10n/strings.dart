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
  static const statusResultStored = 'Kunjungan tersimpan';
  static const statusResultRejected = 'Foto belum memenuhi syarat, tidak disimpan';
  static const statusError = 'Terjadi masalah';
  static const waitingHint = 'Arahkan kamera ke lembar bingkai sampai minimal tiga penanda terlihat utuh.';

  static String burstProgress(int taken, int total) => 'Foto $taken dari $total';
  static String processProgress(int done, int total) => 'Memeriksa foto $done dari $total';
  static String markersSeen(int n) => 'Penanda terlihat: $n dari 4';

  static String tilt(double deg) => 'Kemiringan perkiraan: ${_num(deg, 0)} derajat';
  static String scale(double mmPerPx) => 'Skala perkiraan: ${_num(mmPerPx, 3)} mm per piksel';
  static const tiltAndScaleApprox = 'Nilai kemiringan dan skala hanya perkiraan (kamera belum dikalibrasi).';

  static String _num(double v, int digits) => v.toStringAsFixed(digits).replaceFirst('.', ',');

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
      'Lebar ${_num(w, 3)} mm, ketidakpastian diperluas ${_num(u, 3)} mm (k = ${_num(k, 2)})';
  static String belowFloor(double floorMm) => 'Di bawah batas ukur (< ${_num(floorMm, 3)} mm)';

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

  // Debug.
  static const fakePreview = 'Simulasi kamera (tanpa kamera nyata)';
  static const demoPreparing = 'Menyiapkan simulasi (membuat foto sintetis, sekitar setengah menit)';
  static const debugOpenCapture = 'Uji pengambilan foto (debug, kamera nyata)';
}
