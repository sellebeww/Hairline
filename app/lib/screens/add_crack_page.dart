// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hairline_core/hairline_core.dart';

import '../l10n/strings.dart';
import '../providers.dart';
import '../theme.dart';
import '../util/parse.dart';
import '../widgets/common.dart';
import '../widgets/setup_illustrations.dart';
import 'queries.dart';

const int _steps = 6;

/// Adds a crack through the guided setup: data, print at 100 percent, measure the scale
/// bar (gives `print_scale`), cut the window, mount flat and permanently, relief. The
/// measurement point does not exist yet: the baseline visit chooses it (5.7).
class AddCrackPage extends ConsumerStatefulWidget {
  const AddCrackPage({super.key, required this.siteId});
  final int siteId;

  @override
  ConsumerState<AddCrackPage> createState() => _AddCrackPageState();
}

class _AddCrackPageState extends ConsumerState<AddCrackPage> {
  final _label = TextEditingController(), _ruler = TextEditingController();
  int _step = 0, _sheet = 0;
  PaperSize _paper = PaperSize.a4;
  double _relief = defaultReliefMm;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    _ruler.dispose();
    super.dispose();
  }

  /// Parsed ruler reading, or the reason it is not acceptable.
  ({PrintScaleReading? reading, String? error}) get _reading {
    if (_ruler.text.trim().isEmpty) return (reading: null, error: null);
    final v = parseDecimal(_ruler.text);
    if (v == null) return (reading: null, error: Strings.errRulerNumber);
    try {
      return (reading: printScaleFromRuler(v), error: null);
    } on PrintScaleException {
      return (reading: null, error: Strings.errRulerRange(minRulerReadingMm, maxRulerReadingMm));
    }
  }

  bool get _canContinue => switch (_step) {
        0 => _label.text.trim().isNotEmpty,
        2 => _reading.reading != null,
        _ => true,
      };

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

  Future<void> _save() async {
    final reading = _reading.reading;
    if (reading == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(hairlineRepositoryProvider);
    try {
      // The point is provisional (window centre): the baseline visit sets the real one.
      final id = await repo.createCrack(
        siteId: widget.siteId,
        label: _label.text.trim(),
        sheetId: _sheet,
        printScale: reading.printScale,
        printScaleURel: reading.uPrintRel,
        pointMm: const Pt(0, 0),
        directionDeg: 0,
        createdAt: DateTime.now().toUtc(),
        reliefMm: _relief,
      );
      ref.invalidate(cracksOfSiteProvider(widget.siteId));
      if (mounted) context.pushReplacement('/cracks/$id');
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = Strings.errSave;
        });
      }
    }
  }

  List<Widget> _content() {
    final theme = Theme.of(context);
    switch (_step) {
      case 0:
        return [
          const Text(Strings.setupDataBody),
          const SizedBox(height: 16),
          TextField(
            controller: _label,
            decoration: InputDecoration(labelText: Strings.crackLabel, hintText: Strings.crackLabelHint, border: const OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _sheet,
            isExpanded: true,
            decoration: const InputDecoration(labelText: Strings.sheetNumber, border: OutlineInputBorder()),
            items: [for (var s = 0; s < sheetIdCount; s++) DropdownMenuItem(value: s, child: Text(Strings.sheetOption(s), overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => _sheet = v ?? 0),
          ),
          const Padding(padding: EdgeInsets.only(top: 8), child: Text(Strings.sheetNumberHint)),
        ];
      case 1:
        return [
          const SetupIllustration(kind: SetupIllustrationKind.print, description: Strings.sheetIllustrationPrint),
          const SizedBox(height: 12),
          const Text(Strings.setupPrintBody),
          const SizedBox(height: 12),
          const Text(Strings.paperSize),
          const SizedBox(height: 8),
          SegmentedButton<PaperSize>(
            segments: [for (final p in PaperSize.values) ButtonSegment(value: p, label: Text(p.label))],
            selected: {_paper},
            onSelectionChanged: (s) => setState(() => _paper = s.first),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 8, children: [
            FilledButton.icon(
              onPressed: _busy ? null : () => _output(() => ref.read(sheetOutputProvider).print(_sheet, _paper)),
              icon: const Icon(Icons.print),
              label: const Text(Strings.printSheet),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _output(() => ref.read(sheetOutputProvider).share(_sheet, _paper)),
              icon: const Icon(Icons.share),
              label: const Text(Strings.shareSheet),
            ),
          ]),
        ];
      case 2:
        final r = _reading;
        return [
          const SetupIllustration(kind: SetupIllustrationKind.ruler, description: Strings.sheetIllustrationRuler),
          const SizedBox(height: 12),
          const Text(Strings.setupRulerBody),
          const SizedBox(height: 12),
          TextField(
            controller: _ruler,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: Strings.rulerReading, errorText: r.error, border: const OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          if (r.reading != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(Strings.printScaleResult(r.reading!.printScale, r.reading!.uPrintRel * 100), style: theme.textTheme.bodyLarge),
            ),
        ];
      case 3:
        return [
          const SetupIllustration(kind: SetupIllustrationKind.cut, description: Strings.sheetIllustrationCut),
          const SizedBox(height: 12),
          const Text(Strings.setupCutBody),
        ];
      case 4:
        return [
          const SetupIllustration(kind: SetupIllustrationKind.mount, description: Strings.sheetIllustrationMount),
          const SizedBox(height: 12),
          const Text(Strings.setupMountBody),
          const SizedBox(height: 12),
          const StatusBadge(icon: Icons.warning_amber_rounded, text: Strings.setupMountWarning, colors: StatusColors.caution),
        ];
      default:
        return [
          const SetupIllustration(kind: SetupIllustrationKind.relief, description: Strings.sheetIllustrationRelief),
          const SizedBox(height: 12),
          const Text(Strings.setupReliefBody),
          const SizedBox(height: 12),
          SegmentedButton<double>(
            segments: const [
              ButtonSegment(value: 0.3, label: Text(Strings.reliefSmooth)),
              ButtonSegment(value: 1.0, label: Text(Strings.reliefRough)),
            ],
            selected: {_relief},
            onSelectionChanged: (s) => setState(() => _relief = s.first),
          ),
        ];
    }
  }

  static const _titles = [
    Strings.setupDataTitle,
    Strings.setupPrintTitle,
    Strings.setupRulerTitle,
    Strings.setupCutTitle,
    Strings.setupMountTitle,
    Strings.setupReliefTitle,
  ];

  @override
  Widget build(BuildContext context) {
    final last = _step == _steps - 1;
    return Scaffold(
      appBar: AppBar(title: const Text(Strings.setupTitle)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(Strings.setupStepOf(_step + 1, _steps), style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Semantics(header: true, child: Text(_titles[_step], style: Theme.of(context).textTheme.headlineSmall)),
        const SizedBox(height: 12),
        ..._content(),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 24),
        Row(children: [
          if (_step > 0) OutlinedButton(onPressed: _busy ? null : () => setState(() => _step--), child: const Text(Strings.back)),
          const Spacer(),
          FilledButton(
            onPressed: !_canContinue || _busy
                ? null
                : () {
                    if (last) {
                      _save();
                    } else {
                      setState(() => _step++);
                    }
                  },
            child: Text(last ? Strings.setupFinish : Strings.next),
          ),
        ]),
      ]),
    );
  }
}
