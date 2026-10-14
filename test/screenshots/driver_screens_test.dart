@Tags(['screenshot'])
library;

import 'package:executive_fleet/app/app.dart';
import 'package:executive_fleet/app/providers.dart';
import 'package:executive_fleet/app/router.dart';
import 'package:executive_fleet/domain/models/models.dart';
import 'package:executive_fleet/domain/rules/inspection_rules.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/widget_harness.dart';
import 'screenshot_util.dart';

ProviderContainer _c(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(FleetApp)));

Future<void> _go(WidgetTester t, String loc) async {
  _c(t).read(routerProvider).go(loc);
  await t.pumpAndSettle();
}

Future<AppServices> _signed(WidgetTester t) async {
  await pumpApp(t);
  final s = _c(t).read(servicesProvider);
  await s.session.signInDriver('DR1');
  return s;
}

Future<AppServices> _started(WidgetTester t) async {
  final s = await _signed(t);
  await s.driverOps.checkIn('DR1');
  await s.driverOps.submitInspection(
    driverId: 'DR1',
    vehicleId: 'C1',
    items: InspectionRules.blankChecklist(),
  );
  await s.driverOps.startTrip('TR-1001', 'DR1');
  return s;
}

void main() {
  testWidgets('driver login', (t) async {
    await pumpApp(t, location: '/driver/login');
    await snap(t, 'driver_login');
  });

  testWidgets('driver home before shift', (t) async {
    await _signed(t);
    await _go(t, '/driver/home');
    await snap(t, 'driver_home_before_shift');
  });

  testWidgets('driver home ready for trip', (t) async {
    final s = await _signed(t);
    await s.driverOps.checkIn('DR1');
    await s.driverOps.submitInspection(
      driverId: 'DR1',
      vehicleId: 'C1',
      items: InspectionRules.blankChecklist(),
    );
    await _go(t, '/driver/home');
    await snap(t, 'driver_home_ready');
  });

  testWidgets('driver inspection', (t) async {
    final s = await _signed(t);
    await s.driverOps.checkIn('DR1');
    await _go(t, '/driver/inspection');
    await snap(t, 'driver_inspection');
  });

  testWidgets('driver home inspection failed', (t) async {
    final s = await _signed(t);
    await s.driverOps.checkIn('DR1');
    await s.driverOps.submitInspection(
      driverId: 'DR1',
      vehicleId: 'C1',
      items: [
        for (final i in InspectionRules.blankChecklist())
          i.key == 'tyres'
              ? i.copyWith(result: CheckResult.fail, note: 'Flat')
              : i,
      ],
    );
    await _go(t, '/driver/home');
    await snap(t, 'driver_home_blocked');
  });

  testWidgets('driver active trip + home active', (t) async {
    await _started(t);
    await _go(t, '/driver/trip/TR-1001/active');
    await snap(t, 'driver_active_trip');
    await _go(t, '/driver/home');
    await snap(t, 'driver_home_active');
  });

  testWidgets('driver stop manifest', (t) async {
    final s = await _started(t);
    final v = _c(t).read(dataProvider);
    final trip = v.trips.byId('TR-1001')!;
    final stop = v.trips.stopsOf(trip).first;
    await s.driverOps.arriveAtStop(stop.id);
    await s.driverOps.verifyAndBoard(
      stopId: stop.id,
      method: VerificationMethod.qrDemo,
      input: const VerificationService().qrPayload(
        trip,
        v.employee(stop.boardingEmployeeIds.first)!,
      ),
    );
    await _go(t, '/driver/trip/TR-1001/stop/${stop.id}');
    await snap(t, 'driver_stop');
  });

  testWidgets('driver complete + trips + summary + report', (t) async {
    await _started(t);
    await _go(t, '/driver/trip/TR-1001/complete');
    await snap(t, 'driver_complete');
    await _go(t, '/driver/trips');
    await snap(t, 'driver_trips');
    await _go(t, '/driver/shift-summary');
    await snap(t, 'driver_shift_summary');
    await _go(t, '/driver/report?type=breakdown&trip=TR-1001');
    await snap(t, 'driver_report');
    await _go(t, '/driver/activity');
    await snap(t, 'driver_activity');
    await _go(t, '/driver/profile');
    await snap(t, 'driver_profile');
  });

  testWidgets('driver v2: heavy traffic, tolerance, licence warning', (
    t,
  ) async {
    final s = await _started(t);
    final v = _c(t).read(dataProvider);
    final trip = v.trips.byId('TR-1001')!;
    final stop = v.trips.stopsOf(trip).first;
    await s.driverOps.arriveAtStop(stop.id);
    await s.traffic.setScenario(
      internalRoads: TrafficLevel.heavy,
      ringRoad: TrafficLevel.heavy,
    );
    await _go(t, '/driver/trip/TR-1001/active');
    await t.drag(find.byType(ListView).last, const Offset(0, -420));
    await t.pumpAndSettle();
    await snap(t, 'driver_v2_traffic');
    await _go(t, '/driver/trip/TR-1001/stop/${stop.id}');
    await snap(t, 'driver_v2_stop_tolerance');
    await s.session.signInDriver('DR3');
    await _go(t, '/driver/profile');
    await snap(t, 'driver_v2_profile_licence');
  });

  testWidgets('driver v3: alcohol test, blocked, activity', (t) async {
    final s = await _signed(t);
    await s.driverOps.checkIn('DR1');
    await s.alcohol.record(driverId: 'DR1', readingMg: null);
    await _go(t, '/driver/home');
    await snap(t, 'driver_v3_home_alcohol_retest');
    await _go(t, '/driver/alcohol');
    await snap(t, 'driver_v3_alcohol');
    await s.alcohol.record(driverId: 'DR1', readingMg: 25);
    await _go(t, '/driver/alcohol');
    await snap(t, 'driver_v3_alcohol_failed');
    await _go(t, '/driver/home');
    await snap(t, 'driver_v3_home_blocked');
    await _go(t, '/driver/activity');
    await snap(t, 'driver_v3_activity');
  });

  testWidgets('driver v3: speed warning + shift summary', (t) async {
    await _started(t);
    await _go(t, '/driver/trip/TR-1001/active');
    await snap(t, 'driver_v3_active_speed');
    await _go(t, '/driver/shift-summary');
    await snap(t, 'driver_v3_shift_summary');
  });
}
