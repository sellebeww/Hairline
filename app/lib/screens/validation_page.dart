// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hairline_core/hairline_core.dart';

import '../l10n/strings.dart';
import '../providers.dart';
import '../util/parse.dart';
import '../validation/plate_validator.dart';
import '../validation/validation_providers.dart';
import '../widgets/common.dart';
import 'queries.dart';
import 'validation_run_page.dart';

enum _TruthMode { nominal, csv }

/// Sets up a plate validation (print the plate, read the scale bar, choose the truth) and
/// lists the earlier runs. Starting opens the capture flow with the plate as target.
class ValidationPage extends ConsumerStatefulWidget {
  const ValidationPage({super.key});

  @override
  ConsumerState<ValidationPage> createState() => _ValidationPageState();
}

class _ValidationPageState extends ConsumerState<ValidationPage> {
  final _ruler = TextEditingController(), _csv = TextEditingController(), _uTruth = TextEditingController(text: '0,05');
  PaperSize _paper = PaperSize.a4;
  _TruthMode _mode = _TruthMode.nominal;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // A finished or abandoned validation must not leave its setup behind for the next capture.
    Future.microtask(() {
      if (mounted) ref.read(validationSetupProvider.notifier).use(null);
    });
  }

  @override
  void dispose() {
    _ruler.dispose();
    _csv.dispose();
    _uTruth.dispose();
    super.dispose();
  }

  Future<void> _output(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on Object {
      if (mounted) _error = Strings.errPrint;
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && mounted) setState(() => _csv.text = data!.text!);
  }

  void _start() {
    final v = parseDecimal(_ruler.text);
    final PrintScaleReading reading;
    try {
      if (v == null) throw const PrintScaleException('');
      reading = printScaleFromRuler(v);
    } on PrintScaleException {
      setState(() => _error = v == null ? Strings.errRulerNumber : Strings.errRulerRange(minRulerReadingMm, maxRulerReadingMm));
      return;
    }
    final PlateTruth truth;
    if (_mode == _TruthMode.nominal) {
      final u = parseDecimal(_uTruth.text);
      if (u == null || u < 0 || u > plateTruthMaxUMm) {
        setState(() => _error = Strings.errUTruth);
        return;
      }
      truth = PlateTruth.nominal(uMm: u);
    } else {
      if (_csv.text.trim().isEmpty) {
        setState(() => _error = Strings.errCsvEmpty);
        return;
      }
      try {
        truth = PlateTruth.fromCsv(_csv.text);
      } on PlateTruthException catch (e) {
        setState(() => _error = e.message);
        return;
      }
    }
    setState(() => _error = null);
    ref.read(validationSetupProvider.notifier).use(PlateSetup(truth: truth, printScale: reading.printScale, printScaleURel: reading.uPrintRel));
    context.push('/capture/$validationCaptureId');
  }

  @override
  Widget build(BuildContext context) {
    final output = ref.read(sheetOutputProvider);
    final runs = ref.watch(validationRunsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(Strings.validationTitle)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text(Strings.validationIntro),
        const SectionTitle(Strings.validationPlateSection),
        const Text(Strings.validationPlateBody),
        const SizedBox(height: 12),
        SegmentedButton<PaperSize>(
          segments: [for (final p in PaperSize.values) ButtonSegment(value: p, label: Text(p.label))],
          selected: {_paper},
          onSelectionChanged: (s) => setState(() => _paper = s.first),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          FilledButton.tonalIcon(
            onPressed: _busy ? null : () => _output(() => output.printPlate(_paper)),
            icon: const Icon(Icons.print),
            label: const Text(Strings.printPlate),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _output(() => output.sharePlate(_paper)),
            icon: const Icon(Icons.share),
            label: const Text(Strings.sharePlate),
          ),
        ]),
        const SectionTitle(Strings.validationScaleSection),
        const Text(Strings.setupRulerBody),
        const SizedBox(height: 8),
        TextField(
          controller: _ruler,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: Strings.rulerReading, border: OutlineInputBorder()),
        ),
        const SectionTitle(Strings.validationTruthSection),
        RadioGroup<_TruthMode>(
          groupValue: _mode,
          onChanged: (m) => setState(() => _mode = m ?? _mode),
          child: Column(children: [
            const RadioListTile<_TruthMode>(value: _TruthMode.nominal, title: Text(Strings.truthNominal), subtitle: Text(Strings.truthNominalBody)),
            if (_mode == _TruthMode.nominal)
              Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 8),
                child: TextField(
                  controller: _uTruth,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: Strings.uTruthField, border: OutlineInputBorder()),
                ),
              ),
            const RadioListTile<_TruthMode>(value: _TruthMode.csv, title: Text(Strings.truthCsv), subtitle: Text(Strings.truthCsvBody)),
            if (_mode == _TruthMode.csv)
              Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TextField(
                    controller: _csv,
                    minLines: 4,
                    maxLines: 8,
                    decoration: const InputDecoration(labelText: Strings.truthCsvField, border: OutlineInputBorder()),
                  ),
                  TextButton.icon(onPressed: _paste, icon: const Icon(Icons.content_paste), label: const Text(Strings.truthCsvPaste)),
                ]),
              ),
          ]),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(liveRegion: true, child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          ),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _busy ? null : _start, icon: const Icon(Icons.camera_alt), label: const Text(Strings.validationStart)),
        const SectionTitle(Strings.validationRunsTitle),
        asyncBody(runs, (list) {
          if (list.isEmpty) return const Text(Strings.validationNoRuns);
          return Column(children: [
            for (final r in list)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.fact_check_outlined),
                title: Text(Strings.validationRunTitle(Strings.date(r.tsUtc.toLocal()), r.deviceModel)),
                subtitle: Text(describeRun(r)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/validation/run/${r.id}'),
              ),
          ]);
        }),
        const SizedBox(height: 12),
        const HonestyCard(),
      ]),
    );
  }
}
