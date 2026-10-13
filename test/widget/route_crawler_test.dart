import 'dart:convert';

import 'package:executive_fleet/app/providers.dart';
import 'package:executive_fleet/app/router.dart';
import 'package:executive_fleet/core/persistence/storage_adapter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/widget_harness.dart';

/// Opens EVERY route of all four workspaces (with real seeded IDs) at
/// several screen sizes and fails on any exception, layout overflow or
/// "Page not found".
void main() {
  List<String> routes(DataView d) {
    final t2 = d.trips.byId('TR-1002')!;
    final stop2 = d.trips.stopsOf(t2)[2].id;
    final bill = d.billingOf('C1').first.id;
    return [
      '/',
      // Employee (E1 signed in)
      '/employee/home',
      '/employee/trips',
      '/employee/book',
      '/employee/activity',
      '/employee/profile',
      '/employee/trip/TR-1001',
      '/employee/trip/TR-1001/pass',
      '/employee/trip/TR-0991',
      '/employee/trip/TR-0991/pass',
      '/employee/notifications',
      '/employee/booking/BK-1001',
      '/employee/support/new',
      '/employee/safety',
      '/employee/roster',
      '/employee/preferences',
      // Driver (DR2 signed in, TR-1002 in progress)
      '/driver/home',
      '/driver/trips',
      '/driver/activity',
      '/driver/profile',
      '/driver/trip/TR-1002',
      '/driver/trip/TR-1002/active',
      '/driver/trip/TR-1002/stop/$stop2',
      '/driver/trip/TR-1002/complete',
      '/driver/trip/TR-1006',
      '/driver/inspection',
      '/driver/alcohol',
      '/driver/attendance',
      '/driver/report',
      '/driver/report?type=delay&trip=TR-1002',
      '/driver/sos',
      '/driver/shift-summary',
      '/driver/notifications',
      '/driver/support',
      // Employer Admin
      '/employer/overview',
      '/employer/employees',
      '/employer/employees/new',
      '/employer/employees/E1',
      '/employer/employees/E99',
      '/employer/policies',
      '/employer/policies/import',
      '/employer/locations',
      '/employer/assignments',
      '/employer/assignments/TR-1001',
      '/employer/assignments/TR-1005',
      '/employer/billing',
      '/employer/billing/$bill',
      '/employer/reports',
      '/employer/traffic', '/employer/settings', '/employer/notifications',
      '/employer/analytics',
      // Fleet Manager
      '/fleet/overview',
      '/fleet/telematics',
      '/fleet/telematics?tab=events',
      '/fleet/telematics?tab=geofences',
      '/fleet/telematics?tab=simulate',
      '/fleet/safety',
      '/fleet/safety?tab=alcohol',
      '/fleet/safety?tab=sos',
      '/fleet/dispatch',
      '/fleet/dispatch/new',
      '/fleet/dispatch/new?employees=E1,E2,E3,E4',
      '/fleet/dispatch/trip/TR-1001',
      '/fleet/dispatch/trip/TR-1004',
      '/fleet/dispatch/trip/TR-1005',
      '/fleet/optimization',
      '/fleet/optimization/parameters',
      '/fleet/optimization/run/OR-1001',
      '/fleet/optimization/run/OR-1002',
      '/fleet/pooling',
      '/fleet/vehicles',
      '/fleet/vehicles/new',
      '/fleet/vehicles/C1',
      '/fleet/drivers',
      '/fleet/drivers/new',
      '/fleet/drivers/DR3',
      '/fleet/parking',
      '/fleet/monitoring',
      '/fleet/monitoring/incident/IC-1001',
      '/fleet/reports',
      '/fleet/companies',
      '/fleet/companies/C1',
      '/fleet/companies/new',
      '/fleet/mapping',
      '/fleet/traffic',
      '/fleet/billing',
      '/fleet/settings', '/fleet/notifications',
    ];
  }

  for (final (label, size, scale) in [
    ('phone', phoneSize, 1.0),
    ('phone large text', phoneSize, 1.3),
    ('tablet', tabletSize, 1.0),
    ('desktop', desktopSize, 1.0),
  ]) {
    testWidgets('every route renders cleanly — $label', (t) async {
      t.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final storage = MemoryStorageAdapter({
        'app_state': jsonEncode({
          'session.employee': 'E1',
          'session.driver': 'DR2',
        }),
      });
      await pumpApp(t, size: size, storage: storage);
      final container = ProviderScope.containerOf(
        t.element(find.byType(MaterialApp).first),
      );
      final router = container.read(routerProvider);
      final failures = <String>[];
      for (final r in routes(container.read(dataProvider))) {
        router.go(r);
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        Object? ex;
        while ((ex = t.takeException()) != null) {
          failures.add('$r → ${ex.toString().split('\n').first}');
        }
        if (find.text('Page not found').evaluate().isNotEmpty) {
          failures.add('$r → Page not found');
        }
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  }
}
