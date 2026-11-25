// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'plate_validator.dart';

/// Route parameter and controller key of the plate validation capture: real cracks start at 1.
const int validationCaptureId = 0;

/// The plate setup of the validation in progress (truth, print scale); null outside one.
class ValidationSetupNotifier extends Notifier<PlateSetup?> {
  @override
  PlateSetup? build() => null;

  // A method, not a setter: Notifier state is changed by calls.
  void use(PlateSetup? setup) => state = setup;
}

final validationSetupProvider = NotifierProvider<ValidationSetupNotifier, PlateSetup?>(ValidationSetupNotifier.new);

final plateValidatorProvider = Provider<PlateValidator>((ref) => PlateValidator(
      frames: ref.watch(frameProcessorProvider),
      repository: ref.watch(hairlineRepositoryProvider),
      algorithmVersion: ref.watch(currentAlgorithmVersionProvider),
    ));
