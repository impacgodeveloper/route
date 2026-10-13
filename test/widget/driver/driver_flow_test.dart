import 'package:executive_fleet/app/app.dart';
import 'package:executive_fleet/app/providers.dart';
import 'package:executive_fleet/app/router.dart';
import 'package:executive_fleet/domain/models/models.dart';
import 'package:executive_fleet/domain/rules/inspection_rules.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/widget_harness.dart';

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(FleetApp)));

Future<void> _go(WidgetTester tester, String location) async {
  _container(tester).read(routerProvider).go(location);
  await tester.pumpAndSettle();
}

Future<AppServices> _signInDr1(WidgetTester tester) async {
  await pumpApp(tester);
  final s = _container(tester).read(servicesProvider);
  await s.session.signInDriver('DR1');
  return s;
}

/// DR1 checked in, C1 inspected (passed) and TR-1001 started.
Future<AppServices> _startedTrip(WidgetTester tester) async {
  final s = await _signInDr1(tester);
  expect((await s.driverOps.checkIn('DR1')).isOk, isTrue);
  expect(
    (await s.driverOps.submitInspection(
      driverId: 'DR1',
      vehicleId: 'C1',
      items: InspectionRules.blankChecklist(),
    )).isOk,
    isTrue,
  );
  expect((await s.driverOps.startTrip('TR-1001', 'DR1')).isOk, isTrue);
  return s;
}

void main() {
  testWidgets('login with demo identity opens stateful Home (before shift)', (
    tester,
  ) async {
    await pumpApp(tester, location: '/driver');
    expect(find.text('Driver sign-in'), findsOneWidget);
    await tester.tap(find.text('DR1 · Ravi Kumar'));
    await tester.pumpAndSettle();
    expect(find.text('Start shift'), findsOneWidget);
  });

  testWidgets(
    'Home changes by duty state: shift → inspection → trip → active',
    (tester) async {
      await _signInDr1(tester);
      await _go(tester, '/driver/home');
      expect(find.text('Start shift'), findsOneWidget);

      await tester.tap(find.text('Start shift'));
      await tester.pumpAndSettle();
      expect(find.text('Inspect Vehicle C1'), findsWidgets);

      await tester.tap(find.widgetWithText(FilledButton, 'Inspect Vehicle C1'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Submit inspection'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Submit inspection'));
      await tester.pumpAndSettle();
      expect(find.text('Inspection passed'), findsOneWidget);

      await tester.tap(find.text('Back to Home'));
      await tester.pumpAndSettle();
      expect(find.text('Start trip TR-1001'), findsOneWidget);
      expect(find.text('Cannot start yet'), findsNothing);

      await tester.tap(find.text('Start trip TR-1001'));
      await tester.pumpAndSettle();
      expect(find.text('Arrived at stop'), findsOneWidget);
      await _go(tester, '/driver/home');
      expect(find.text('Open active trip'), findsOneWidget);
      expect(find.text('SOS'), findsOneWidget); // persistent accessory
    },
  );

  testWidgets('critical inspection failure blocks start and shows defect', (
    tester,
  ) async {
    final s = await _signInDr1(tester);
    await s.driverOps.checkIn('DR1');
    final items = [
      for (final i in InspectionRules.blankChecklist())
        i.key == 'brakes'
            ? i.copyWith(result: CheckResult.fail, note: 'Soft pedal')
            : i,
    ];
    expect(
      (await s.driverOps.submitInspection(
        driverId: 'DR1',
        vehicleId: 'C1',
        items: items,
      )).isOk,
      isTrue,
    );
    await _go(tester, '/driver/home');
    expect(find.text('Trip start blocked'), findsOneWidget);
    expect(find.text('Request replacement vehicle'), findsOneWidget);
    expect(s.driverOps.startBlockers('TR-1001', 'DR1'), isNotEmpty);
    expect((await s.driverOps.startTrip('TR-1001', 'DR1')).isOk, isFalse);
  });

  testWidgets('valid demo QR boards; invalid T-PIN does not; stop completes', (
    tester,
  ) async {
    final s = await _startedTrip(tester);
    final view = _container(tester).read(dataProvider);
    final trip = view.trips.byId('TR-1001')!;
    final stop = view.trips.stopsOf(trip).first;
    await s.driverOps.arriveAtStop(stop.id);
    final passenger = view.employee(stop.boardingEmployeeIds.first)!;

    await _go(tester, '/driver/trip/TR-1001/stop/${stop.id}');
    expect(find.text('Awaiting'), findsWidgets);

    // Invalid T-PIN first: never boards.
    await tester.tap(find.text('Enter T-PIN'));
    await tester.pumpAndSettle();
    final correct = const VerificationService().tpin(trip, passenger);
    await tester.enterText(
      find.byKey(const Key('tpinField')),
      correct == '1111' ? '2222' : '1111',
    );
    await tester.tap(find.text('Verify T-PIN'));
    await tester.pumpAndSettle();
    expect(find.text('Invalid — not boarded'), findsOneWidget);
    expect(
      _container(
        tester,
      ).read(dataProvider).trips.byId('TR-1001')!.boardedPassengerIds,
      isEmpty,
    );

    // Valid simulated QR scan boards the passenger.
    await tester.tap(find.text('Scan QR'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Valid pass · ${passenger.employeeCode} ${passenger.name}'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Verified · boarded'), findsOneWidget);
    expect(find.text('Boarded'), findsWidgets);
    expect(
      _container(
        tester,
      ).read(dataProvider).trips.byId('TR-1001')!.boardedPassengerIds,
      contains(passenger.id),
    );

    // Duplicate scan is rejected.
    await tester.tap(find.text('Scan QR'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Duplicate ·'));
    await tester.pumpAndSettle();
    expect(find.text('Duplicate — not boarded again'), findsOneWidget);

    // Board everyone else at this stop, then complete it.
    for (final id in stop.boardingEmployeeIds.skip(1)) {
      final e = view.employee(id)!;
      await s.driverOps.verifyAndBoard(
        stopId: stop.id,
        method: VerificationMethod.qrDemo,
        input: const VerificationService().qrPayload(trip, e),
      );
    }
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Complete stop'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Complete stop'));
    await tester.pumpAndSettle();
    final after = _container(tester).read(dataProvider).db.routeStops[stop.id]!;
    expect(after.status, StopStatus.completed);
    expect(
      find.text('Arrived at stop'),
      findsOneWidget,
    ); // back on active trip, next stop
  });

  testWidgets('SOS shows honest demo outcome', (tester) async {
    await _startedTrip(tester);
    await _go(tester, '/driver/sos?trip=TR-1001');
    await tester.tap(find.text('Raise SOS now'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(
      find.text('No real emergency service was contacted'),
      findsOneWidget,
    );
  });

  testWidgets('all main driver screens render on phone without overflow', (
    tester,
  ) async {
    await _startedTrip(tester);
    for (final loc in [
      '/driver/home',
      '/driver/trips',
      '/driver/activity',
      '/driver/profile',
      '/driver/trip/TR-1001',
      '/driver/trip/TR-1001/active',
      '/driver/trip/TR-1001/complete',
      '/driver/attendance',
      '/driver/inspection',
      '/driver/report?type=breakdown&trip=TR-1001',
      '/driver/shift-summary',
      '/driver/notifications',
      '/driver/support',
    ]) {
      await _go(tester, loc);
      expect(tester.takeException(), isNull, reason: loc);
    }
  });
}
