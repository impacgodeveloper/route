@Tags(['screenshot'])
library;

import 'package:flutter_test/flutter_test.dart';

import '../support/widget_harness.dart';
import 'screenshot_util.dart';

void main() {
  for (final (name, path) in [
    ('companies', '/fleet/companies'),
    ('company_overview', '/fleet/companies/C1'),
    ('company_contracts', '/fleet/companies/C1?tab=contracts'),
    ('company_allocations', '/fleet/companies/C1?tab=allocations'),
    ('company_register', '/fleet/companies/new'),
    ('vehicle_detail', '/fleet/vehicles/C1'),
    ('driver_detail', '/fleet/drivers/DR3'),
    ('parking', '/fleet/parking'),
  ]) {
    testWidgets('fleet registry $name desktop', (t) async {
      await pumpApp(t, location: path, size: desktopSize);
      await snap(t, 'fleet_registry_${name}_desktop');
    });
  }
  testWidgets('fleet registry companies phone', (t) async {
    await pumpApp(
      t,
      location: '/fleet/companies/C1?tab=allocations',
      size: phoneSize,
    );
    await snap(t, 'fleet_registry_allocations_phone');
  });
}
