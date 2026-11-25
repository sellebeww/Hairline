// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:go_router/go_router.dart';
import 'package:hairline_core/hairline_core.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'capture/capture_page.dart';
import 'screens/about_page.dart';
import 'screens/add_crack_page.dart';
import 'screens/add_site_page.dart';
import 'screens/crack_detail_page.dart';
import 'screens/cracks_page.dart';
import 'screens/help_page.dart';
import 'screens/point_page.dart';
import 'screens/result_page.dart';
import 'screens/sites_page.dart';
import 'screens/trend_page.dart';

part 'router.g.dart';

/// Core version, shown on the about screen.
@riverpod
String coreVersion(Ref ref) => hairlineCoreVersion;

int _id(GoRouterState s, String name) => int.tryParse(s.pathParameters[name] ?? '') ?? -1;

@riverpod
GoRouter router(Ref ref) => GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const SitesPage()),
      GoRoute(path: '/sites/new', builder: (context, state) => const AddSitePage()),
      GoRoute(path: '/sites/:siteId', builder: (context, state) => CracksPage(siteId: _id(state, 'siteId'))),
      GoRoute(path: '/sites/:siteId/cracks/new', builder: (context, state) => AddCrackPage(siteId: _id(state, 'siteId'))),
      GoRoute(path: '/cracks/:crackId', builder: (context, state) => CrackDetailPage(crackId: _id(state, 'crackId'))),
      GoRoute(path: '/capture/:crackId', builder: (context, state) => CapturePage(crackId: _id(state, 'crackId'))),
      GoRoute(path: '/point/:crackId', builder: (context, state) => PointPage(crackId: _id(state, 'crackId'))),
      GoRoute(path: '/result/:visitId', builder: (context, state) => ResultPage(visitId: _id(state, 'visitId'))),
      GoRoute(path: '/trend/:crackId', builder: (context, state) => TrendPage(crackId: _id(state, 'crackId'))),
      GoRoute(path: '/help', builder: (context, state) => const HelpPage()),
      GoRoute(path: '/about', builder: (context, state) => const AboutPage()),
    ]);
