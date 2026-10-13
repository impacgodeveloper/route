@Tags(['screenshot'])
library;

import 'package:executive_fleet/domain/services/app_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../widget/employer_admin/employer_harness.dart';
import 'screenshot_util.dart';

const _desktop = Size(1440, 900);
const _phone = Size(390, 844);

void main() {
  for (final (name, path) in [
    ('overview', '/employer/overview'),
    ('employees', '/employer/employees'),
    ('employee_detail', '/employer/employees/E1'),
    ('policies', '/employer/policies'),
    ('locations', '/employer/locations'),
    ('assignments', '/employer/assignments'),
    ('trip_detail', '/employer/assignments/TR-1002'),
    ('billing', '/employer/billing'),
    ('billing_detail', '/employer/billing/BL-1002'),
    ('reports', '/employer/reports'),
    ('traffic', '/employer/traffic'),
    ('analytics', '/employer/analytics'),
    ('billing_lines', '/employer/billing?tab=lines'),
    ('billing_config', '/employer/billing?tab=config'),
    ('settings', '/employer/settings'),
  ]) {
    testWidgets('employer $name desktop', (t) async {
      await pumpEmployer(t, location: path, size: _desktop);
      await snap(t, 'employer_${name}_desktop');
    });
  }
  for (final (name, path) in [
    ('overview', '/employer/overview'),
    ('analytics', '/employer/analytics'),
    ('employees', '/employer/employees'),
    ('billing', '/employer/billing'),
  ]) {
    testWidgets('employer $name phone', (t) async {
      await pumpEmployer(t, location: path, size: _phone);
      await snap(t, 'employer_${name}_phone');
    });
  }
  testWidgets('employer invoice detail desktop', (t) async {
    await pumpEmployer(t, location: '/employer/billing', size: _desktop);
    final s = servicesOf(t);
    final e = dataOf(t).primaryEmployer;
    final r = await s.billingCycles.runCycle(
      e.id,
      s.billingCycles.currentPeriod(e).previous,
    );
    await goTo(t, '/employer/billing/invoices/${r.valueOrNull!.id}');
    await snap(t, 'employer_invoice_desktop');
  });
  testWidgets('employer overview with SOS desktop', (t) async {
    await pumpEmployer(t, location: '/employer/overview', size: _desktop);
    await servicesOf(
      t,
    ).incidents.raiseSos(actor: Actor.employee('E1'), tripId: 'TR-1001');
    await t.pumpAndSettle();
    await snap(t, 'employer_overview_sos_desktop');
  });
  testWidgets('employer employee detail phone', (t) async {
    await pumpEmployer(t, location: '/employer/employees/E1', size: _phone);
    await snap(t, 'employer_employee_detail_phone');
  });
  testWidgets('employer import preview desktop', (t) async {
    await pumpEmployer(
      t,
      location: '/employer/policies/import',
      size: _desktop,
    );
    await t.enterText(
      find.byKey(const Key('roster-paste')),
      'employee_code,name,pickup_code,destination_code,arrival_time\nE201,Demo Person,PK01,G1,09:00\nE202,Bad Pickup,PK99,G1,09:00\nE1,Existing,PK01,G1,09:00\n',
    );
    await t.tap(find.text('Preview import'));
    await t.pumpAndSettle();
    await snap(t, 'employer_import_desktop');
  });
}
