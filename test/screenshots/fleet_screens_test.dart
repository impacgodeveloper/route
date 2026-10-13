@Tags(['screenshot'])
library;

import 'package:flutter_test/flutter_test.dart';

import '../support/widget_harness.dart';
import 'screenshot_util.dart';

void main() {
  const desktop = {
    'overview': '/fleet/overview',
    'dispatch': '/fleet/dispatch',
    'wizard_capacity': '/fleet/dispatch/new?employees=E1,E2,E3,E4',
    'trip_detail': '/fleet/dispatch/trip/TR-1002',
    'optimization': '/fleet/optimization',
    'run': '/fleet/optimization/run/OR-1001',
    'run_infeasible': '/fleet/optimization/run/OR-1002',
    'parameters': '/fleet/optimization/parameters',
    'pooling': '/fleet/pooling',
    'vehicle_edit': '/fleet/vehicles/C3',
    'parking': '/fleet/parking',
    'monitoring': '/fleet/monitoring',
    'reports': '/fleet/reports',
    'mapping': '/fleet/mapping',
    'traffic': '/fleet/traffic',
    'billing': '/fleet/billing',
    'settings': '/fleet/settings',
  };
  for (final e in desktop.entries) {
    testWidgets('fleet ${e.key} desktop', (t) async {
      await pumpApp(t, location: e.value, size: desktopSize);
      await snap(t, 'fleet_${e.key}_desktop');
    });
  }
  for (final e in {
    'overview': '/fleet/overview',
    'dispatch': '/fleet/dispatch',
    'optimization': '/fleet/optimization',
    'mapping': '/fleet/mapping',
    'traffic': '/fleet/traffic',
  }.entries) {
    testWidgets('fleet ${e.key} phone', (t) async {
      await pumpApp(t, location: e.value, size: phoneSize);
      await snap(t, 'fleet_${e.key}_phone');
    });
  }
}
