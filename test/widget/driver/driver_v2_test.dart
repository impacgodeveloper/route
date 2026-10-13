import 'package:executive_fleet/app/app.dart';
import 'package:executive_fleet/app/providers.dart';
import 'package:executive_fleet/app/router.dart';
import 'package:executive_fleet/core/demo/demo_labels.dart';
import 'package:executive_fleet/domain/models/models.dart';
import 'package:executive_fleet/domain/rules/inspection_rules.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/widget_harness.dart';

ProviderContainer _c(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(FleetApp)));
DataView _data(WidgetTester t) => _c(t).read(dataProvider);
AppServices _svc(WidgetTester t) => _c(t).read(servicesProvider);

Future<void> _go(WidgetTester t, String loc) async {
  _c(t).read(routerProvider).go(loc);
  await t.pumpAndSettle();
}

/// Scrolls the main vertical list until [f] is built.
Future<void> _reveal(WidgetTester t, Finder f) async {
  if (f.evaluate().isNotEmpty) return;
  final lists = find.byWidgetPredicate(
    (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
  );
  await t.scrollUntilVisible(f, 250, scrollable: lists.first, maxScrolls: 40);
  await t.pumpAndSettle();
}

/// DR1 checked in, C1 inspected, TR-1001 started (clock 06:30).
Future<RouteStop> _startTrip(WidgetTester t) async {
  final s = _svc(t);
  await s.session.signInDriver('DR1');
  await s.driverOps.checkIn('DR1');
  await s.driverOps.submitInspection(
    driverId: 'DR1',
    vehicleId: 'C1',
    items: InspectionRules.blankChecklist(),
  );
  expect((await s.driverOps.startTrip('TR-1001', 'DR1')).isOk, isTrue);
  final trip = _data(t).trips.byId('TR-1001')!;
  return _data(t).trips.stopsOf(trip).first;
}

void main() {
  testWidgets('stop screen shows pickup window and tolerance deviation', (
    t,
  ) async {
    await pumpApp(t);
    final stop = await _startTrip(t);
    await _svc(t).driverOps.arriveAtStop(stop.id);
    await _go(t, '/driver/trip/TR-1001/stop/${stop.id}');

    final data = _data(t);
    final e = data.employee(stop.boardingEmployeeIds.first)!;
    final tol = e.toleranceMinutes(data.employer(e.employerId));
    expect(find.text('Tolerance window'), findsOneWidget);
    expect(find.textContaining('(±$tol)'), findsWidgets);
    expect(find.textContaining('Pickup window'), findsOneWidget);
    // Arrived at 06:30 vs planned 07:10 → 40 min early, outside tolerance.
    final early = stop.plannedArrival
        .difference(DateTime(2026, 10, 19, 6, 30))
        .inMinutes;
    expect(find.text('$early min early (outside ±$tol)'), findsOneWidget);
    expect(find.textContaining('Outside ±$tol min'), findsOneWidget);

    // Active trip timeline shows the same deviation badge.
    await _go(t, '/driver/trip/TR-1001/active');
    await _reveal(t, find.text('$early min early (outside ±$tol)'));
    expect(find.text('$early min early (outside ±$tol)'), findsOneWidget);
  });

  testWidgets('heavy traffic shows delay banner, pending revision and label', (
    t,
  ) async {
    await pumpApp(t);
    await _startTrip(t);
    await _go(t, '/driver/trip/TR-1001/active');
    expect(find.text('On schedule'), findsOneWidget);

    final r = await _svc(t).traffic.setScenario(
      internalRoads: TrafficLevel.heavy,
      ringRoad: TrafficLevel.heavy,
    );
    expect(r.isOk, isTrue);
    await t.pumpAndSettle();
    final status = _svc(t).traffic.statusOf(_data(t).trips.byId('TR-1001')!);
    expect(status.delayMinutes, greaterThan(0));
    expect(find.text(status.statusLabel), findsOneWidget);
    expect(find.text('~${status.delayMinutes} min'), findsOneWidget);
    expect(find.textContaining(DemoLabels.trafficSimulated), findsOneWidget);
    expect(_data(t).openRevision("TR-1001"), isNotNull);
    expect(
      find.text('Schedule change pending Fleet Manager decision'),
      findsOneWidget,
    );

    // Home shows the same status.
    await _go(t, '/driver/home');
    await _reveal(t, find.text(status.statusLabel));
    expect(find.text(status.statusLabel), findsOneWidget);

    // Unavailable data is labelled honestly.
    await _svc(t).traffic.setScenario(
      internalRoads: TrafficLevel.free,
      ringRoad: TrafficLevel.free,
      source: TrafficSource.unavailable,
    );
    await _go(t, '/driver/trip/TR-1001/active');
    expect(find.text('Traffic data unavailable'), findsOneWidget);
  });

  testWidgets('applied revision updates planned stop times', (t) async {
    await pumpApp(t);
    await _startTrip(t);
    await _svc(t).traffic.setScenario(
      internalRoads: TrafficLevel.severe,
      ringRoad: TrafficLevel.severe,
    );
    final rev = _data(t).openRevision('TR-1001');
    expect(rev, isNotNull, reason: "severe traffic should propose a revision");
    if (rev == null) return;
    final r = await _svc(t).traffic.applyRevision(rev.id);
    expect(r.isOk, isTrue, reason: r.message);
    await _go(t, '/driver/trip/TR-1001/active');
    expect(
      find.text('Schedule change pending Fleet Manager decision'),
      findsNothing,
    );
    final last = _data(t).trips.stopsOf(_data(t).trips.byId('TR-1001')!).last;
    final proposed = rev.stops.firstWhere((s) => s.stopId == last.id).proposed;
    expect(last.plannedArrival, proposed);
  });

  testWidgets('guard requirement and seat breakdown on trip preview', (
    t,
  ) async {
    await pumpApp(t);
    await _svc(t).session.signInDriver('DR1');
    await _go(t, '/driver/trip/TR-1001');
    await _reveal(t, find.text('Security guard'));
    expect(find.text('Security guard'), findsOneWidget);
    expect(find.textContaining('total − 1 driver'), findsOneWidget);
    expect(find.textContaining('employee seats'), findsOneWidget);
  });

  testWidgets('DR3 profile warns that the licence expires within 30 days', (
    t,
  ) async {
    await pumpApp(t);
    await _svc(t).session.signInDriver('DR3');
    await _go(t, '/driver/profile');
    expect(find.textContaining('Licence expires in'), findsOneWidget);
    expect(find.text('Gender (self-declared)'), findsOneWidget);
    expect(find.textContaining('Aadhaar'), findsNothing);
    expect(find.textContaining('Age'), findsNothing);
    await _go(t, '/driver/home');
    expect(find.textContaining('Licence expires in'), findsOneWidget);
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('v2 driver screens at 390 px, text scale $scale, no overflow', (
      t,
    ) async {
      t.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpApp(t, size: phoneSize);
      final stop = await _startTrip(t);
      await _svc(t).driverOps.arriveAtStop(stop.id);
      await _svc(t).traffic.setScenario(
        internalRoads: TrafficLevel.heavy,
        ringRoad: TrafficLevel.moderate,
      );
      for (final loc in [
        '/driver/home',
        '/driver/trip/TR-1001',
        '/driver/trip/TR-1001/active',
        '/driver/trip/TR-1001/stop/${stop.id}',
        '/driver/profile',
      ]) {
        await _go(t, loc);
        expect(t.takeException(), isNull, reason: loc);
      }
      await _svc(t).session.signInDriver('DR3');
      await _go(t, '/driver/profile');
      expect(t.takeException(), isNull);
      await _go(t, '/driver/home');
      expect(t.takeException(), isNull);
    });
  }
}
