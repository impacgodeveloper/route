import 'package:executive_fleet/domain/models/models.dart';
import 'package:executive_fleet/domain/rules/inspection_rules.dart';
import 'package:executive_fleet/domain/services/app_services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_harness.dart';

void main() {
  test('seed + core end-to-end smoke', () async {
    final h = await Harness.create();
    final v = h.view;
    expect(v.employees.length, 100);
    expect(v.vehicles.map((e) => e.id), ['C1', 'C2', 'C3']);
    expect(v.drivers.length, 3);
    expect(v.optimizationRuns.length, 2);
    final runs = {for (final r in v.optimizationRuns) r.id: r};
    // ignore: avoid_print
    print(
      'OR-1001: ${runs['OR-1001']!.status} ${runs['OR-1001']!.outputSummary} ${runs['OR-1001']!.hardConstraintViolations}',
    );
    // ignore: avoid_print
    print(
      'OR-1002: ${runs['OR-1002']!.status} ${runs['OR-1002']!.hardConstraintViolations}',
    );
    expect(runs['OR-1001']!.isFeasible, isTrue);
    expect(runs['OR-1002']!.isFeasible, isFalse);

    // Driver DR1 flow on TR-1001.
    final s = h.services;
    final t1 = v.trips.byId('TR-1001')!;
    // ignore: avoid_print
    print('TR-1001 start ${t1.scheduledStart} arrival ${t1.scheduledArrival}');
    expect(s.driverOps.startBlockers('TR-1001', 'DR1'), isNotEmpty);
    expect((await s.driverOps.checkIn('DR1')).isOk, isTrue);
    expect(
      (await s.driverOps.checkIn('DR1')).isOk,
      isFalse,
      reason: 'duplicate check-in',
    );
    final insp = await s.driverOps.submitInspection(
      driverId: 'DR1',
      vehicleId: 'C1',
      items: InspectionRules.blankChecklist(),
    );
    expect(insp.isOk, isTrue, reason: insp.message);
    final start = await s.driverOps.startTrip('TR-1001', 'DR1');
    expect(start.isOk, isTrue, reason: start.message);

    final ver = const VerificationService();
    for (final stop in h.view.trips.stopsOf(h.view.trips.byId('TR-1001')!)) {
      h.clock.advance(const Duration(minutes: 8));
      expect((await s.driverOps.arriveAtStop(stop.id)).isOk, isTrue);
      final trip = h.view.trips.byId('TR-1001')!;
      if (stop.kind == StopKind.pickup) {
        for (final eid in stop.boardingEmployeeIds) {
          final r = await s.driverOps.verifyAndBoard(
            stopId: stop.id,
            method: VerificationMethod.qrDemo,
            input: ver.qrPayload(trip, h.view.employee(eid)!),
          );
          expect(r.valueOrNull?.ok, isTrue, reason: r.message);
        }
      } else {
        expect(
          (await s.driverOps.alight(
            stopId: stop.id,
            employeeIds: stop.alightingEmployeeIds,
          )).isOk,
          isTrue,
        );
      }
      final dep = await s.driverOps.departStop(stop.id);
      expect(dep.isOk, isTrue, reason: dep.message);
    }
    final trip = h.view.trips.byId('TR-1001')!;
    final done = await s.driverOps.completeTrip(
      tripId: trip.id,
      driverId: 'DR1',
      endOdometerKm: trip.startOdometerKm! + 24.6,
    );
    expect(done.isOk, isTrue, reason: done.message);
    expect(h.view.billingForTrip('TR-1001'), isNotNull);
    expect(
      h.view.billingForTrip('TR-1001')!.totalAmount,
      closeTo(24.6 * 18, 0.01),
    );

    // Booking → assignment for E4 tomorrow.
    final bk = await s.bookings.createTripForBookings(
      ['BK-1004'],
      driverId: 'DR1',
      vehicleId: 'C1',
    );
    expect(bk.isOk, isTrue, reason: bk.message);
    expect(h.view.booking('BK-1004')!.status, BookingStatus.assigned);

    // Persistence across restart.
    final h2 = await h.restart();
    expect(h2.view.booking('BK-1004')!.status, BookingStatus.assigned);
    expect(h2.view.trips.byId('TR-1001')!.status, TripStatus.completed);
    expect(h2.view.employees.length, 100);
  });
}
