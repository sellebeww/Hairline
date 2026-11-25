// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../widgets/common.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text(Strings.helpTitle)),
        body: ListView(padding: const EdgeInsets.all(16), children: const [
          SectionTitle(Strings.helpHowTitle),
          BulletList(Strings.helpHow),
          SectionTitle(Strings.helpLimitsTitle),
          BulletList(Strings.helpLimits),
          SectionTitle(Strings.helpResultsTitle),
          BulletList(Strings.helpResults),
          SizedBox(height: 12),
          HonestyCard(),
        ]),
      );
}
