import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'safety_page.dart';
import 'telematics_page.dart';

/// Telematics & geofences, safety (alcohol, SOS) — placeholder replaced by
/// the implementation.
List<RouteBase> v3Routes(
  Page<void> Function(GoRouterState s, Widget child) page,
) => [
  // Telematics & geofences (fleet A agent).
  GoRoute(
    path: '/fleet/telematics',
    pageBuilder: (c, s) =>
        page(s, TelematicsPage(initialTab: s.uri.queryParameters['tab'])),
  ),
  // Safety & SOS (fleet B agent).
  GoRoute(
    path: '/fleet/safety',
    pageBuilder: (c, s) =>
        page(s, SafetyPage(initialTab: s.uri.queryParameters['tab'])),
  ),
];
