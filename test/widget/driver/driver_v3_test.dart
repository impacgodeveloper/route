import 'package:executive_fleet/app/app.dart';
import 'package:executive_fleet/app/providers.dart';
import 'package:executive_fleet/app/router.dart';
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

Future<void> _tapButton(WidgetTester t, String text) async {
  final f = find.ancestor(
    of: find.text(text),
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  );
  expect(f, findsWidgets, reason: 'button "$text"');
  await t.ensureVisible(f.first);
  await t.pumpAndSettle();
  await t.tap(f.first);
  await t.pumpAndSettle();
}

/// DR1 signed in and checked in, with a device error as the latest test.
Future<void> _dr1Inconclusive(WidgetTester t) async {
  final s = _svc(t);
  await s.session.signInDriver('DR1');
  await s.driverOps.checkIn('DR1');
  final r = await s.alcohol.record(driverId: 'DR1', readingMg: null);
  expect(r.valueOrNull?.result, AlcoholResult.inconclusive);
}

void main() {
  testWidgets('alcohol step appears when required (inconclusive → retest)', (
    t,
  ) async {
    await pumpApp(t);
    await _dr1Inconclusive(t);
    await _go(t, '/driver/home');
    expect(find.text('Alcohol test'), findsOneWidget);
    expect(find.textContaining('retest required'), findsOneWidget);
    expect(find.text('Inspect Vehicle C1'), findsNothing);
    await _tapButton(t, 'Take alcohol test');
    expect(
      find.text('Connected breathalyzer (simulated)'.toUpperCase()),
      findsOneWidget,
    );
  });

  testWidgets('failed test blocks trip start with review banner', (t) async {
    await pumpApp(t);
    await _dr1Inconclusive(t);
    await _go(t, '/driver/alcohol');
    await t.tap(find.text('Fail 25 mg'));
    await t.pumpAndSettle();
    await _tapButton(t, 'Blow into breathalyzer');
    expect(find.text('Fleet Manager review required'), findsOneWidget);
    expect(find.text('Blow into breathalyzer'), findsNothing);
    expect(_data(t).trips.byId('TR-1001')!.status, TripStatus.needsAttention);
    final blockers = _svc(t).driverOps.startBlockers('TR-1001', 'DR1');
    expect(blockers.join(' '), contains('Alcohol test failed'));
    await _go(t, '/driver/home');
    expect(find.text('Fleet Manager review required'), findsOneWidget);
    expect(find.textContaining('Do not drive'), findsOneWidget);
    expect(find.text('Start trip TR-1001'), findsNothing);

    // Fleet Manager clears → block lifted, retest required.
    final fail = _data(t).blockingAlcoholTest('DR1')!;
    expect(
      (await _svc(t).alcohol.clear(fail.id, 'Reviewed with supervisor')).isOk,
      isTrue,
    );
    await t.pumpAndSettle();
    expect(find.text('Block lifted — retest required'), findsOneWidget);
    expect(find.text('Take alcohol test'), findsOneWidget);
  });

  testWidgets('passing test allows start', (t) async {
    await pumpApp(t);
    await _dr1Inconclusive(t);
    await _go(t, '/driver/alcohol');
    await _tapButton(t, 'Blow into breathalyzer');
    expect(find.textContaining('Passed · 0 mg'), findsOneWidget);
    await _tapButton(t, 'Continue');
    expect(find.text('Inspect Vehicle C1'), findsWidgets);
    await _svc(t).driverOps.submitInspection(
      driverId: 'DR1',
      vehicleId: 'C1',
      items: InspectionRules.blankChecklist(),
    );
    await t.pumpAndSettle();
    expect(find.text('Start trip TR-1001'), findsOneWidget);
    expect(_svc(t).driverOps.startBlockers('TR-1001', 'DR1'), isEmpty);
    // History in Activity.
    await _go(t, '/driver/activity');
    await t.tap(find.widgetWithText(ChoiceChip, 'Alcohol tests'));
    await t.pumpAndSettle();
    expect(find.text('Inconclusive / device error'), findsOneWidget);
    expect(find.text('Pass'), findsWidgets);
  });

  testWidgets('disabled policy hides the alcohol step', (t) async {
    await pumpApp(t);
    final s = _svc(t);
    final p = _data(t).policy;
    expect(
      (await s.policy.save(p.copyWith(alcoholMonitoringEnabled: false))).isOk,
      isTrue,
    );
    await _dr1Inconclusive(t);
    await _go(t, '/driver/home');
    expect(find.text('Take alcohol test'), findsNothing);
    expect(find.text('Inspect Vehicle C1'), findsWidgets);
  });

  testWidgets('speeding and off-route banners for DR2 (simulated)', (t) async {
    await pumpApp(t);
    final s = _svc(t);
    await s.session.signInDriver('DR2');
    expect(
      (await s.telematics.simulate('C2', VehicleEventType.speeding)).isOk,
      isTrue,
    );
    await _go(t, '/driver/trip/TR-1002/active');
    expect(find.text('Slow down'), findsOneWidget);
    expect(find.textContaining('Simulated telemetry'), findsOneWidget);
    expect(find.text('km/h'), findsOneWidget);
    await s.telematics.simulate('C2', VehicleEventType.routeDeviation);
    await t.pumpAndSettle();
    expect(find.text('Off planned route'), findsOneWidget);
    // Notification opens the active trip.
    await _go(t, '/driver/notifications');
    final n = find.textContaining('Slow down');
    if (n.evaluate().isNotEmpty) {
      await t.tap(n.first);
      await t.pumpAndSettle();
      expect(find.text('TR-1002'), findsWidgets);
    }
  });

  testWidgets('SOS shows the escalation chain', (t) async {
    await pumpApp(t);
    await _svc(t).session.signInDriver('DR2');
    await _go(t, '/driver/sos?trip=TR-1002');
    await _tapButton(t, 'Raise SOS now');
    await t.pump(const Duration(milliseconds: 700));
    await t.pumpAndSettle();
    expect(find.text('Escalation chain'), findsOneWidget);
    expect(find.text('Fleet Manager'), findsWidgets);
    expect(find.text('Not contacted — integration required'), findsWidgets);
  });

  testWidgets('absent passenger shown as not travelling', (t) async {
    await pumpApp(t);
    final s = _svc(t);
    await s.session.signInDriver('DR1');
    final r = await s.matching.reportAbsence('TR-1001', 'E2', 'On leave');
    expect(r.isOk, isTrue, reason: r.message);
    await s.driverOps.checkIn('DR1');
    await s.driverOps.submitInspection(
      driverId: 'DR1',
      vehicleId: 'C1',
      items: InspectionRules.blankChecklist(),
    );
    await s.driverOps.startTrip('TR-1001', 'DR1');
    final trip = _data(t).trips.byId('TR-1001')!;
    expect(trip.employeeIds, isNot(contains('E2')));
    await _go(t, '/driver/trip/TR-1001');
    await t.scrollUntilVisible(
      find.text('Not travelling (reported)'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Not travelling (reported)'), findsOneWidget);
    // On the stop screen at E2's pickup point (if it is still a stop).
    final e2 = _data(t).employee('E2')!;
    final stop = _data(t).trips
        .stopsOf(trip)
        .where((x) => x.locationId == e2.pickupLocationId)
        .firstOrNull;
    if (stop != null) {
      await _go(t, '/driver/trip/TR-1001/stop/${stop.id}');
      expect(find.text('Not travelling (reported)'), findsOneWidget);
    }
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('v3 driver screens at 390 px, text scale $scale', (t) async {
      t.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpApp(t, size: phoneSize);
      final s = _svc(t);
      await _dr1Inconclusive(t);
      for (final loc in ['/driver/home', '/driver/alcohol']) {
        await _go(t, loc);
        expect(t.takeException(), isNull, reason: loc);
      }
      await s.alcohol.record(driverId: 'DR1', readingMg: 25);
      for (final loc in [
        '/driver/home',
        '/driver/alcohol',
        '/driver/activity',
      ]) {
        await _go(t, loc);
        expect(t.takeException(), isNull, reason: loc);
      }
      await s.session.signInDriver('DR2');
      await s.telematics.simulate('C2', VehicleEventType.speeding);
      await s.telematics.simulate('C2', VehicleEventType.routeDeviation);
      for (final loc in [
        '/driver/home',
        '/driver/trip/TR-1002',
        '/driver/trip/TR-1002/active',
        '/driver/shift-summary',
        '/driver/profile',
      ]) {
        await _go(t, loc);
        expect(t.takeException(), isNull, reason: loc);
      }
      await _go(t, '/driver/sos?trip=TR-1002');
      await _tapButton(t, 'Raise SOS now');
      await t.pump(const Duration(milliseconds: 700));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
}
