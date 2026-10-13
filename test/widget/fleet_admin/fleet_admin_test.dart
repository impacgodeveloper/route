import 'package:executive_fleet/app/providers.dart';
import 'package:executive_fleet/domain/models/models.dart';
import 'package:executive_fleet/domain/rules/parameter_catalog.dart';
import 'package:executive_fleet/features/fleet_admin/fleet_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/widget_harness.dart';

DataView _data(WidgetTester t) => ProviderScope.containerOf(
  t.element(find.byType(FleetShell)),
).read(dataProvider);

Future<void> _tapText(WidgetTester t, String text, {bool last = false}) async {
  final f = last ? find.text(text).last : find.text(text).first;
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('sidebar navigates across all 10 sections', (t) async {
    await pumpApp(t, location: '/fleet', size: desktopSize);
    const sections = {
      'Overview': 'Fleet overview',
      'Trips & Dispatch': 'Trips & dispatch',
      'Route Optimization': 'Route optimization',
      'Employee Pooling': 'Employee pooling',
      'Vehicles': 'Add vehicle',
      'Drivers': 'Add driver',
      'Parking & Stops': 'Parking & stops',
      'Monitoring & Incidents': 'Monitoring & incidents',
      'Reports': 'Operational reports',
      'Settings': 'Audit trail',
    };
    final sidebar = find.byType(Scrollable).first;
    for (final e in sections.entries) {
      await t.scrollUntilVisible(
        find.text(e.key).first,
        80,
        scrollable: sidebar,
      );
      await t.pumpAndSettle();
      await t.tap(find.text(e.key).first);

      await t.pumpAndSettle();
      expect(find.text(e.value), findsWidgets, reason: e.key);
    }
  });

  testWidgets('approve booking BK-1004 then assign E4 to DR1 + C1 tomorrow', (
    t,
  ) async {
    await pumpApp(t, location: '/fleet/dispatch', size: desktopSize);
    await t.tap(find.byTooltip('Actions for BK-1004'));
    await t.pumpAndSettle();
    await t.tap(find.text('Approve').last);
    await t.pumpAndSettle();
    expect(_data(t).booking('BK-1004')!.status, BookingStatus.approved);

    await t.tap(find.byTooltip('Actions for BK-1004'));
    await t.pumpAndSettle();
    await t.tap(find.text('Create trip…').last);
    await t.pumpAndSettle();
    expect(find.text('New trip'), findsWidgets);
    await _tapText(t, 'Vehicle C1 · EV Sedan');
    await _tapText(t, 'DR1 Ravi Kumar');
    await _tapText(t, 'Save & assign trip');
    final b = _data(t).booking('BK-1004')!;
    expect(b.status, BookingStatus.assigned);
    final trip = _data(t).trips.byId(b.tripId)!;
    expect(trip.assignedDriverId, 'DR1');
    expect(trip.assignedVehicleId, 'C1');
  });

  testWidgets('E1–E4 in Vehicle C1 shows capacity error and suggests C3', (
    t,
  ) async {
    await pumpApp(
      t,
      location: '/fleet/dispatch/new?employees=E1,E2,E3,E4',
      size: desktopSize,
    );
    await _tapText(t, 'Vehicle C1 · EV Sedan');
    expect(find.textContaining('Over capacity: 4 employees'), findsWidgets);
    expect(find.textContaining('Use Vehicle C3'), findsOneWidget);
    await _tapText(t, 'Use Vehicle C3 (5 seats)');
    expect(find.text('All hard constraints pass'), findsOneWidget);
  });

  testWidgets('reassignment requires a reason and records history', (t) async {
    await pumpApp(
      t,
      location: '/fleet/dispatch/trip/TR-1006?reassign=1',
      size: desktopSize,
    );
    expect(find.text('Reassign TR-1006'), findsOneWidget);
    await t.tap(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.textContaining('DR2 Priya Sharma'),
          )
          .first,
    );
    await t.pumpAndSettle();
    await t.tap(find.textContaining('DR1 Ravi Kumar').last);
    await t.pumpAndSettle();
    expect(find.textContaining('Reassignment needs a reason'), findsOneWidget);
    final save = find.widgetWithText(FilledButton, 'Save reassignment');
    expect(t.widget<FilledButton>(save).onPressed, isNull);
    await t.enterText(
      find.widgetWithText(TextField, 'Reassignment reason (required)'),
      'DR2 requested leave (demo)',
    );
    await t.pumpAndSettle();
    await t.tap(save);
    await t.pumpAndSettle();
    final trip = _data(t).trips.byId('TR-1006')!;
    expect(trip.assignedDriverId, 'DR1');
    expect(trip.assignmentHistory.length, 2);
    expect(trip.assignmentHistory.last.reason, 'DR2 requested leave (demo)');
  });

  testWidgets('optimizer run on E1–E4 shows score and Apply creates trips', (
    t,
  ) async {
    await pumpApp(t, location: '/fleet/optimization', size: desktopSize);
    await _tapText(t, 'Run local demo optimizer');
    expect(find.text('/ 100 score'), findsOneWidget);
    await _tapText(t, 'Apply proposal');
    expect(find.textContaining('Apply OR-'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Apply proposal').last);
    await t.pumpAndSettle();
    final run = _data(t).optimizationRuns.first;
    expect(run.appliedAt, isNotNull);
    expect(run.appliedTripIds, isNotEmpty);
    for (final id in run.appliedTripIds) {
      expect(_data(t).trips.byId(id)!.status, TripStatus.assigned);
    }
  });

  testWidgets('sedan-only run shows No feasible assignment', (t) async {
    await pumpApp(
      t,
      location: '/fleet/optimization/run/OR-1002',
      size: desktopSize,
    );
    expect(find.text('No feasible assignment'), findsOneWidget);
    expect(find.textContaining('Capacity: 4 employees'), findsWidgets);
    expect(find.text('Apply proposal'), findsNothing);
  });

  testWidgets('parameter catalog lists 100+ definitions', (t) async {
    await pumpApp(
      t,
      location: '/fleet/optimization/parameters',
      size: desktopSize,
    );
    expect(ParameterCatalog.count, greaterThanOrEqualTo(100));
    expect(
      find.textContaining(
        '${ParameterCatalog.count} parameters · ${ParameterCatalog.liveCount} active in demo',
      ),
      findsOneWidget,
    );
    expect(find.text('Catalog only (not connected)'), findsWidgets);
  });

  testWidgets('vehicle edit persists', (t) async {
    await pumpApp(t, location: '/fleet/vehicles/C3', size: desktopSize);
    await t.enterText(
      find.widgetWithText(TextField, 'Model'),
      'Demo EV MPV 2027',
    );
    await _tapText(t, 'Save changes');
    expect(_data(t).vehicle('C3')!.model, 'Demo EV MPV 2027');
  });

  testWidgets('incident resolve', (t) async {
    await pumpApp(
      t,
      location: '/fleet/monitoring/incident/IC-1001',
      size: desktopSize,
    );
    await _tapText(t, 'Resolve');
    await t.enterText(
      find.widgetWithText(TextField, 'Resolution notes'),
      'Traffic cleared, trip continued (demo).',
    );
    await t.tap(find.widgetWithText(FilledButton, 'Resolve').last);
    await t.pumpAndSettle();
    expect(_data(t).incident('IC-1001')!.status, IncidentStatus.resolvedDemo);
  });

  for (final size in [desktopSize, tabletSize, phoneSize]) {
    for (final loc in [
      '/fleet/overview',
      '/fleet/dispatch',
      '/fleet/optimization',
      '/fleet/dispatch/new?employees=E1,E2',
      '/fleet/monitoring',
      '/fleet/reports',
    ]) {
      testWidgets('no overflow $loc at ${size.width.toInt()}px', (t) async {
        await pumpApp(t, location: loc, size: size);
        expect(find.byType(FleetShell), findsOneWidget);
      });
    }
  }
}
