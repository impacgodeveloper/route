import 'package:executive_fleet/app/providers.dart';
import 'package:executive_fleet/app/router.dart';
import 'package:executive_fleet/domain/models/models.dart';
import 'package:executive_fleet/features/fleet_admin/fleet_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/widget_harness.dart';

/// Fleet v3 (A): telematics & geofences, vehicle diagnostics and the
/// parking placement optimizer — driven through the UI.

ProviderContainer _c(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(FleetShell)));
DataView _data(WidgetTester t) => _c(t).read(dataProvider);
AppServices _svc(WidgetTester t) => _c(t).read(servicesProvider);

Future<void> _tap(WidgetTester t, Finder f) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pump();
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Finder _inDialog(Finder f) =>
    find.descendant(of: find.byType(AlertDialog), matching: f);

Future<void> _go(WidgetTester t, String path) async {
  _c(t).read(routerProvider).go(path);
  await t.pumpAndSettle();
}

Future<void> _pickDropdown(WidgetTester t, Key key, String item) async {
  await _tap(t, find.byKey(key));
  await t.tap(find.text(item).last);
  await t.pumpAndSettle();
}

Future<void> _simulate(WidgetTester t) async {
  await _tap(t, find.byKey(const Key('simRun')));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => WidgetController.hitTestWarningShouldBeFatal = true);

  testWidgets('live table shows C2 moving with speed > 0', (t) async {
    await pumpApp(t, location: '/fleet/telematics', size: desktopSize);
    expect(
      find.text('Simulated telematics — no GPS/OBD hardware connected'),
      findsOneWidget,
    );
    final c2 = _svc(t).telematics.snapshot(_data(t).vehicle('C2')!);
    expect(c2.moving, isTrue);
    expect(c2.speedKmh, greaterThan(0));
    final limit = _data(t).policy.speedLimitKmh;
    expect(find.text('Vehicle C2'), findsWidgets);
    expect(find.text('${c2.speedKmh.round()} / $limit km/h'), findsWidgets);
    expect(find.text('Fleet map'), findsOneWidget);
  });

  testWidgets('simulate speeding C2, then dedupe → no new event', (t) async {
    await pumpApp(
      t,
      location: '/fleet/telematics?tab=simulate',
      size: desktopSize,
    );
    final before = _data(t).vehicleEventsOf('C2').length;
    await t.enterText(find.byKey(const Key('simValue')), '92');
    await _simulate(t);
    expect(find.textContaining('Generated VE'), findsOneWidget);
    final events = _data(t).vehicleEventsOf('C2');
    expect(events.length, before + 1);
    final e = events.firstWhere((e) => e.type == VehicleEventType.speeding);
    expect(e.open, isTrue);
    expect(e.simulated, isTrue);

    await _simulate(t);
    expect(find.textContaining('no new event'), findsOneWidget);
    expect(_data(t).vehicleEventsOf('C2').length, before + 1);

    // It appears in the Events feed.
    await _go(t, '/fleet/telematics?tab=events');
    expect(find.textContaining(e.id), findsOneWidget);
  });

  testWidgets('acknowledge an event and raise an incident', (t) async {
    await pumpApp(
      t,
      location: '/fleet/telematics?tab=simulate',
      size: desktopSize,
    );
    await _simulate(t);
    final e = _data(t).openVehicleEvents.firstWhere(
      (e) => e.vehicleId == 'C2' && e.type == VehicleEventType.speeding,
    );
    await _go(t, '/fleet/telematics?tab=events');
    await _tap(t, find.widgetWithText(FilledButton, 'Acknowledge…').first);
    await t.enterText(
      find.byKey(const Key('ackNote')),
      'Called driver, slowed down',
    );
    await _tap(t, _inDialog(find.text('Raise an incident')));
    await _tap(t, _inDialog(find.widgetWithText(FilledButton, 'Acknowledge')));

    final after = _data(t).vehicleEvents.firstWhere((x) => x.id == e.id);
    expect(after.open, isFalse);
    expect(after.incidentId, isNotNull);
    expect(after.incidentId, startsWith('IC-'));

    // Acknowledged filter shows the incident link.
    await _tap(t, find.text('Acknowledged').first);
    expect(find.text('Incident ${after.incidentId}'), findsOneWidget);
  });

  testWidgets('geofence create with a validation error first', (t) async {
    await pumpApp(
      t,
      location: '/fleet/telematics?tab=geofences',
      size: desktopSize,
    );
    final before = _data(t).geofences.length;
    await _tap(t, find.text('New geofence'));
    await t.enterText(find.byKey(const Key('geofenceRadius')), '99');
    await _tap(t, find.byKey(const Key('saveGeofence')));
    expect(find.text('Not saved'), findsOneWidget);
    expect(find.text('Name is required.'), findsOneWidget);
    expect(find.text('Radius must be 0.1–60 km.'), findsOneWidget);
    expect(_data(t).geofences.length, before);

    await t.enterText(find.byKey(const Key('geofenceName')), 'North campus');
    await t.enterText(find.byKey(const Key('geofenceRadius')), '3.5');
    await _tap(t, _inDialog(find.text('Vehicle C2')));
    await _tap(t, find.byKey(const Key('saveGeofence')));
    expect(find.byType(AlertDialog), findsNothing);
    final g = _data(t).geofences.firstWhere((g) => g.name == 'North campus');
    expect(g.id, startsWith('GF-'));
    expect(g.radiusKm, 3.5);
    expect(g.vehicleIds, ['C2']);
    expect(find.text('North campus'), findsOneWidget);
  });

  testWidgets('diagnostic fault simulated, then cleared on vehicle detail', (
    t,
  ) async {
    await pumpApp(
      t,
      location: '/fleet/telematics?tab=simulate',
      size: desktopSize,
    );
    await _pickDropdown(t, const Key('simType'), 'Diagnostic fault');
    await t.enterText(find.byKey(const Key('simCode')), 'P0420 · Catalyst');
    await _simulate(t);
    expect(find.textContaining('Generated VE'), findsOneWidget);
    expect(
      _data(t).vehicle('C2')!.diagnosticCodes,
      contains('P0420 · Catalyst'),
    );

    await _go(t, '/fleet/vehicles/C2');
    expect(find.text('Telemetry & diagnostics'), findsOneWidget);
    expect(find.text('P0420 · Catalyst'), findsOneWidget);
    await _tap(
      t,
      find.descendant(
        of: find
            .ancestor(
              of: find.text('P0420 · Catalyst'),
              matching: find.byType(Row),
            )
            .first,
        matching: find.text('Clear code'),
      ),
    );
    expect(
      _data(t).vehicle('C2')!.diagnosticCodes,
      isNot(contains('P0420 · Catalyst')),
    );
    expect(find.text('P0420 · Catalyst'), findsNothing);
    expect(
      _data(t).auditTrail.any((a) => a.action == 'telematics.clearDiagnostic'),
      isTrue,
    );
  });

  testWidgets('parking optimize → apply → home parking updated, audited', (
    t,
  ) async {
    await pumpApp(t, location: '/fleet/parking', size: desktopSize);
    final recs = _svc(
      t,
    ).parkingPlanner.recommend().where((r) => r.changes).toList();
    expect(recs, isNotEmpty, reason: 'seed should leave room to optimise');
    expect(find.text('Optimize parking placement'), findsOneWidget);
    expect(
      find.textContaining('Method: for each active vehicle'),
      findsOneWidget,
    );

    await _tap(t, find.text('Select all changes'));
    expect(find.text('Capacity usage after applying the selection'), findsOne);
    await _tap(t, find.byKey(const Key('applyParking')));
    expect(find.textContaining('parking change(s)?'), findsOneWidget);
    await _tap(t, _inDialog(find.widgetWithText(FilledButton, 'Apply')));

    for (final r in recs) {
      expect(
        _data(t).vehicle(r.vehicle.id)!.homeParkingId,
        r.recommendedParkingId,
      );
    }
    final audits = _data(
      t,
    ).auditTrail.where((a) => a.action == 'parking.assign').toList();
    expect(audits.length, recs.length);

    await _go(t, '/fleet/settings');
    expect(
      find.textContaining('Vehicle ${recs.first.vehicle.vehicleCode} parking'),
      findsWidgets,
    );
  });

  for (final size in [phoneSize, tabletSize, desktopSize]) {
    testWidgets(
      'v3 telematics pages render without overflow at ${size.width.toInt()}px',
      (t) async {
        await pumpApp(t, location: '/fleet/telematics', size: size);
        final failures = <String>[];
        for (final path in [
          '/fleet/telematics',
          '/fleet/telematics?tab=events',
          '/fleet/telematics?tab=geofences',
          '/fleet/telematics?tab=simulate',
          '/fleet/vehicles/C2',
          '/fleet/parking',
        ]) {
          _c(t).read(routerProvider).go(path);
          await t.pump();
          await t.pump(const Duration(milliseconds: 300));
          Object? ex;
          while ((ex = t.takeException()) != null) {
            failures.add('$path → ${ex.toString().split('\n').first}');
          }
        }
        expect(failures, isEmpty, reason: failures.join('\n'));
      },
    );
  }
}
