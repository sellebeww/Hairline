// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../pipeline/visit_processor.dart';

part 'pending_baseline.g.dart';

/// Baseline bursts waiting for their measurement point, by crack id. In memory only: if the
/// app is closed before the point is confirmed nothing was stored and the burst is retaken.
@Riverpod(keepAlive: true)
class PendingBaselines extends _$PendingBaselines {
  @override
  Map<int, PendingBaseline> build() => const {};

  void put(PendingBaseline p) => state = {...state, p.crackId: p};

  void remove(int crackId) => state = {...state}..remove(crackId);
}
