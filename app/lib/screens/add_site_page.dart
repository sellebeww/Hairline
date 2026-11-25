// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/strings.dart';
import '../providers.dart';
import '../util/parse.dart';
import 'queries.dart';

/// Adds a site. Location is optional and typed by the user (no location permission, 5.8).
class AddSitePage extends ConsumerStatefulWidget {
  const AddSitePage({super.key});

  @override
  ConsumerState<AddSitePage> createState() => _AddSitePageState();
}

class _AddSitePageState extends ConsumerState<AddSitePage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(), _notes = TextEditingController(), _lat = TextEditingController(), _lon = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    _lat.dispose();
    _lon.dispose();
    super.dispose();
  }

  static String? _range(String? v, double limit, String message) {
    if (v == null || v.trim().isEmpty) return null;
    final d = parseDecimal(v);
    return d == null || d.abs() > limit ? message : null;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_lat.text.trim().isEmpty != _lon.text.trim().isEmpty) {
      setState(() => _error = Strings.errLatLonPair);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = ref.read(hairlineRepositoryProvider);
    try {
      final id = await repo.createSite(
        name: _name.text.trim(),
        notes: _notes.text.trim(),
        lat: _lat.text.trim().isEmpty ? null : parseDecimal(_lat.text),
        lon: _lon.text.trim().isEmpty ? null : parseDecimal(_lon.text),
      );
      ref.invalidate(sitesProvider);
      if (mounted) context.pushReplacement('/sites/$id');
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = Strings.errSave;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text(Strings.addSite)),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: Strings.siteName, border: OutlineInputBorder()),
              textInputAction: TextInputAction.next,
              validator: (v) => (v == null || v.trim().isEmpty) ? Strings.errSiteName : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(labelText: Strings.siteNotes, border: OutlineInputBorder()),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _lat,
              decoration: const InputDecoration(labelText: Strings.siteLat, border: OutlineInputBorder()),
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              validator: (v) => _range(v, 90, Strings.errLat),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _lon,
              decoration: const InputDecoration(labelText: Strings.siteLon, border: OutlineInputBorder()),
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              validator: (v) => _range(v, 180, Strings.errLon),
            ),
            const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text(Strings.siteLocationHint)),
            if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            FilledButton(onPressed: _saving ? null : _save, child: const Text(Strings.save)),
          ]),
        ),
      );
}
