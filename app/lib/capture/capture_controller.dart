// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hairline_core/hairline_core.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/repository.dart';
import '../l10n/strings.dart';
import '../pipeline/frame_processor.dart';
import '../pipeline/visit_processor.dart';
import '../providers.dart';
import 'camera_driver.dart';
import 'camera_service.dart';
import 'capture_flow.dart';
import 'detection_worker.dart';
import 'device_camera_service.dart';
import 'lens_info.dart';
import 'live_analysis.dart';
import 'reference_pose.dart';

part 'capture_controller.g.dart';

/// The real camera. Tests and the simulation override it with a `FakeCameraService`.
@riverpod
CameraService cameraService(Ref ref) {
  final service = DeviceCameraService(driverFactory: CameraPluginDriver.new, lensSource: MethodChannelLensInfoSource());
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
}

/// Builds the live marker detector inside the detection isolate. Must be overridden by
/// the app with the OpenCV factory (BLOCKERS B1, DECISIONS D34, D40); tests override it
/// with the embedded synthetic detector.
@Riverpod(keepAlive: true)
GrayDetectorFactory grayDetectorFactory(Ref ref) =>
    throw UnimplementedError('Override grayDetectorFactoryProvider with the OpenCV live detector factory.');

@Riverpod(keepAlive: true)
FlowConfig flowConfig(Ref ref) => const FlowConfig();

/// What the capture screen shows: the pure flow state plus facts about the session.
@immutable
final class CaptureUiState {
  const CaptureUiState({this.flow = const CaptureState(), this.starting = true, this.isBaseline = true, this.paused = false, this.note});

  final CaptureState flow;

  /// Camera and detector are still being opened.
  final bool starting;

  /// No baseline visit exists yet: this capture defines the reference pose.
  final bool isBaseline;

  /// The app is in the background: the camera is released and the preview must not be built.
  final bool paused;

  /// Hint about the reference pose (missing or from another camera), if any.
  final String? note;

  CaptureUiState copyWith({CaptureState? flow, bool? starting, bool? isBaseline, bool? paused, Object? note = _keep}) => CaptureUiState(
        flow: flow ?? this.flow,
        starting: starting ?? this.starting,
        isBaseline: isBaseline ?? this.isBaseline,
        paused: paused ?? this.paused,
        note: identical(note, _keep) ? this.note : note as String?,
      );
}

const Object _keep = Object();

/// Orchestrates one capture session for a crack: camera, detection isolate, live pose
/// analysis, the shutter and the quality gate through `VisitProcessor`. All decisions
/// about phases live in `reduceCapture`; this class only feeds it events and runs I/O.
@riverpod
class CaptureController extends _$CaptureController {
  late int _crackId;
  late FlowConfig _config;
  final Stopwatch _clock = Stopwatch()..start();
  bool _disposed = false;
  bool _paused = false;
  CameraService? _camera;
  DetectionWorker? _worker;
  LiveAnalyzer? _analyzer;
  StreamSubscription<DetectionResult>? _results;
  Timer? _tick;
  CancelToken? _cancel;
  CameraSetup? _setup;
  LiveAnalyzer Function(ReferencePose?)? _makeAnalyzer;
  ReferencePose? _reference;

  @override
  CaptureUiState build(int crackId) {
    _crackId = crackId;
    _config = ref.read(flowConfigProvider);
    // Watched, not read: an auto-dispose provider that is only read would be released
    // (and the camera closed) right after the first await.
    _camera = ref.watch(cameraServiceProvider);
    ref.onDispose(_teardown);
    unawaited(Future<void>.microtask(_start));
    return const CaptureUiState();
  }

  void _teardown() {
    _disposed = true;
    _tick?.cancel();
    unawaited(_results?.cancel());
    _cancel?.cancel();
    final worker = _worker;
    if (worker != null) unawaited(worker.dispose());
  }

  void _dispatch(CaptureEvent e) {
    if (_disposed) return;
    final next = reduceCapture(state.flow, e, config: _config);
    if (!identical(next, state.flow)) state = state.copyWith(flow: next);
  }

  void _fail(String message) => _dispatch(FailedEvent(message));

  Future<void> _start() async {
    // Everything that needs `ref` is read before the first await: after the screen is
    // closed the ref is dead, while this method may still be running.
    if (!ref.mounted) return;
    final repo = ref.read(hairlineRepositoryProvider);
    final GrayDetectorFactory detectorFactory;
    try {
      detectorFactory = ref.read(grayDetectorFactoryProvider);
    } on Object {
      // The provider throws (wrapped) when the app never wired a detector: say so in plain words.
      _failStart(Strings.errDetector);
      return;
    }
    try {
      final crack = await repo.crackContext(_crackId);
      final visits = await repo.visitsOfCrack(_crackId);
      final baseline = visits.where((v) => v.kind == 'baseline').firstOrNull;
      _reference = ReferencePose.tryParse(baseline?.referencePoseJson);
      final camera = _camera!;
      final setup = await camera.initialize();
      _setup = setup;
      if (_disposed) return;
      _makeAnalyzer = (reference) => LiveAnalyzer(
            sheetId: crack.crack.sheetId,
            printScale: crack.crack.printScale,
            pointMm: Pt(crack.point.xMm, crack.point.yMm),
            quarterTurns: setup.quarterTurns,
            reference: reference,
            focalMm: setup.lens.focalLengthMm,
            sensorLongSideMm: setup.lens.sensorLongSideMm,
          );
      _analyzer = _makeAnalyzer!(_reference);
      final worker = await DetectionWorker.start(detectorFactory);
      _worker = worker;
      if (_disposed) {
        unawaited(worker.dispose());
        return;
      }
      _results = worker.results.listen(_onDetection, onError: (Object _) => _fail(Strings.errDetectorCrashed));
      await camera.startLiveFrames(worker.offer);
      _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => _dispatch(TickEvent(_clock.elapsed)));
      if (_disposed) return;
      state = state.copyWith(
        starting: false,
        isBaseline: baseline == null,
        note: baseline != null && _reference == null ? Strings.referenceMissingHint : null,
      );
    } on CameraFailure catch (e) {
      _failStart(e.message);
    } on RepositoryException catch (e) {
      _failStart(e.message);
    } on DetectionWorkerException {
      _failStart(Strings.errDetector);
    } on Object {
      // Closing the screen mid-start can fail a query or a port: only report it if the screen is still there.
      _failStart(Strings.errStartup);
    }
  }

  void _failStart(String message) {
    if (_disposed) return;
    state = state.copyWith(starting: false);
    _fail(message);
  }

  void _onDetection(DetectionResult r) {
    final analyzer = _analyzer;
    if (analyzer == null || _paused) return; // a result that was in flight when the camera was released
    LiveAnalysis? analysis;
    try {
      analysis = analyzer.analyze(r);
    } on Object {
      analysis = null; // a frame that cannot be analysed counts as "nothing usable"
    }
    _dispatch(AnalysisEvent(analysis, _clock.elapsed));
    final incompatible = _reference != null && analysis != null && analysis.estimate != null && analysis.deviation == null;
    final note = incompatible ? Strings.referenceIncompatibleHint : (state.isBaseline || _reference != null ? null : Strings.referenceMissingHint);
    if (!_disposed && note != state.note) state = state.copyWith(note: note);
  }

  /// The shutter button. Does nothing unless the flow is ready.
  Future<void> shutter() async {
    final flow = state.flow;
    final camera = _camera, setup = _setup;
    final analysis = flow.analysis;
    if (!flow.canShoot || camera == null || setup == null || analysis == null) return;
    final processor = ref.read(visitProcessorProvider);
    final baseline = state.isBaseline;
    // The reference of the baseline visit is the pose of the frame that made the shutter ready.
    final reference = baseline ? LiveAnalyzer.referenceFrom(analysis) : null;
    _dispatch(ShutterEvent(_config.burstCount));

    final BurstResult burst;
    try {
      burst = await camera.captureBurst(
        count: _config.burstCount,
        minGap: _config.burstMinGap,
        onProgress: (n) => _dispatch(BurstProgressEvent(n)),
      );
    } on CameraFailure catch (e) {
      _fail(e.message);
      return;
    }
    if (_disposed) return;
    _dispatch(BurstDoneEvent(photoCount: burst.photos.length, flags: burst.locks.flags));

    final cancel = _cancel = CancelToken();
    try {
      final outcome = await processor.processBurst(
            crackId: _crackId,
            photos: burst.photos,
            deviceModel: setup.lens.deviceModel,
            camera: setup.lens.toCameraInfo(flags: burst.locks.flags),
            kind: baseline ? 'baseline' : 'followup',
            referencePoseJson: reference?.toJsonString(),
            cancel: cancel,
            onProgress: (done, total) => _dispatch(ProcessProgressEvent(done, total)),
          );
      if (_disposed) return;
      if (outcome is VisitStored && baseline && reference != null) {
        // The next shot on this screen is a follow-up: guide it with the pose just stored.
        _reference = reference;
        _analyzer = _makeAnalyzer?.call(reference);
        state = state.copyWith(isBaseline: false);
      }
      _dispatch(ProcessedEvent(outcome));
    } on VisitCancelledException {
      return;
    } on RepositoryException catch (e) {
      _fail(e.message);
    } on FrameProcessException catch (e) {
      _fail(e.message);
    } on Object {
      _fail(Strings.errProcessing);
    } finally {
      _cancel = null;
    }
  }

  /// "Ulangi": back to aiming, camera and stream re-armed if the failure had stopped them.
  Future<void> retry() async {
    _dispatch(const RetryEvent());
    _analyzer?.reset();
    await _rearm();
  }

  Future<void> _rearm() async {
    final camera = _camera, worker = _worker;
    if (camera == null || worker == null || _disposed || _paused) return;
    try {
      await camera.initialize();
      await camera.startLiveFrames(worker.offer);
    } on CameraFailure catch (e) {
      _fail(e.message);
    }
  }

  /// App lifecycle (a call or the home button sends `inactive`): the camera is released
  /// at once and reopened on `resumed`. A burst in progress fails as interrupted.
  Future<void> onLifecycle(AppLifecycleState s) async {
    final camera = _camera;
    if (camera == null || _disposed) return;
    if (s == AppLifecycleState.resumed) {
      if (!_paused) return;
      _paused = false;
      _analyzer?.reset();
      state = state.copyWith(paused: false);
      try {
        await camera.resume();
      } on CameraFailure catch (e) {
        _fail(e.message);
      }
    } else if (!_paused) {
      _paused = true;
      state = state.copyWith(paused: true); // the preview widget goes first, then the camera is released
      _dispatch(AnalysisEvent(null, _clock.elapsed)); // aiming goes back to "waiting": nothing is stale
      await camera.pause();
    }
  }
}
