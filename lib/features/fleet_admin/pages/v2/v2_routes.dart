import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'billing_page.dart';
import 'mapping_page.dart';
import 'traffic_page.dart';

/// Vehicle mapping, traffic & movement and fleet billing.
List<RouteBase> v2Routes(
  Page<void> Function(GoRouterState s, Widget child) page,
) => [
  GoRoute(
    path: '/fleet/mapping',
    pageBuilder: (c, s) => page(s, const VehicleMappingPage()),
  ),
  GoRoute(
    path: '/fleet/traffic',
    pageBuilder: (c, s) => page(s, const TrafficPage()),
  ),
  GoRoute(
    path: '/fleet/billing',
    pageBuilder: (c, s) => page(s, const FleetBillingPage()),
  ),
];
