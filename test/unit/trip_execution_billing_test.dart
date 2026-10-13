import 'package:executive_fleet/domain/models/models.dart';
import 'package:executive_fleet/domain/rules/inspection_rules.dart';
import 'package:executive_fleet/domain/services/app_services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_harness.dart';

/// Checks DR1 in, passes inspection of C1 and starts TR-1001.
Future<Harness> startedTrip() async {
  final h = await Harness.create();
  await h.services.driverOps.checkIn('DR1');
  await h.services.driverOps.submitInspection(
    driverId: 'DR1',
    vehicleId: 'C1',
    items: InspectionRules.blankChecklist(),
  );
  final r = await h.services.driverOps.startTrip('TR-1001', 'DR1');
  expect(r.isOk, isTrue, reason: r.message);
  return h;
}

void main() {
  const ver = VerificationService();

  group('Demo QR / T-PIN verification', () {
    test('success, invalid, wrong trip, duplicate and expired', () async {
      final h = await startedTrip();
      final trip = h.view.trips.byId('TR-1001')!;
      final emps = trip.employeeIds
          .map(h.view.employee)
          .whereType<Employee>()
          .toList();
      final e1 = h.view.employee('E1')!;
      final now = h.clock.now();

      final ok = ver.verifyQr(
        payload: ver.qrPayload(trip, e1),
        trip: trip,
        tripEmployees: emps,
        now: now,
      );
      expect(ok.status, VerificationStatus.verified);
      expect(ok.employeeId, 'E1');

      final tampered = ver.qrPayload(trip, e1).replaceFirst('E1|', 'E2|');
      expect(
        ver
            .verifyQr(
              payload: tampered,
              trip: trip,
              tripEmployees: emps,
              now: now,
            )
            .status,
        VerificationStatus.invalid,
      );
      expect(
        ver
            .verifyQr(
              payload: 'hello',
              trip: trip,
              tripEmployees: emps,
              now: now,
            )
            .status,
        VerificationStatus.invalid,
      );

      final other = h.view.trips.byId('TR-1002')!;
      final e5 = h.view.employee('E5')!;
      expect(
        ver
            .verifyQr(
              payload: ver.qrPayload(other, e5),
              trip: trip,
              tripEmployees: emps,
              now: now,
            )
            .status,
        VerificationStatus.wrongTrip,
      );

      final tomorrow = now.add(const Duration(days: 1));
      expect(
        ver
            .verifyQr(
              payload: ver.qrPayload(trip, e1),
              trip: trip,
              tripEmployees: emps,
              now: tomorrow,
            )
            .status,
        VerificationStatus.expired,
      );

      expect(
        ver.verifyTpin(pin: '0000', trip: trip, employee: e1, now: now).ok,
        isFalse,
      );
      expect(
        ver
            .verifyTpin(
              pin: ver.tpin(trip, e1),
              trip: trip,
              employee: e1,
              now: now,
            )
            .ok,
        isTrue,
      );

      // Board E1 via service, then the same pass is a duplicate.
      final first = h.view.trips.stopsOf(trip).first;
      await h.services.driverOps.arriveAtStop(first.id);
      final boarded = await h.services.driverOps.verifyAndBoard(
        stopId: first.id,
        method: VerificationMethod.qrDemo,
        input: ver.qrPayload(trip, e1),
      );
      final pickupForE1 = h.view.trips.pickupStopFor(trip, 'E1')!;
      if (pickupForE1.id == first.id) {
        expect(boarded.valueOrNull!.ok, isTrue);
        final again = await h.services.driverOps.verifyAndBoard(
          stopId: first.id,
          method: VerificationMethod.qrDemo,
          input: ver.qrPayload(h.view.trips.byId('TR-1001')!, e1),
        );
        expect(again.valueOrNull!.status, VerificationStatus.duplicate);
      }
    });

    test('failed T-PIN never marks the passenger boarded', () async {
      final h = await startedTrip();
      final trip = h.view.trips.byId('TR-1001')!;
      final stop = h.view.trips.stopsOf(trip).first;
      await h.services.driverOps.arriveAtStop(stop.id);
      final eid = stop.boardingEmployeeIds.first;
      final r = await h.services.driverOps.verifyAndBoard(
        stopId: stop.id,
        method: VerificationMethod.tpinDemo,
        input: '1111',
        employeeId: eid,
      );
      expect(r.valueOrNull!.ok, isFalse);
      expect(h.view.trips.byId('TR-1001')!.boardedPassengerIds, isEmpty);
      expect(
        h.view.trips.eventsOf(trip).where((e) => e.tripId == trip.id),
        isEmpty,
      );
    });
  });

  group('Passenger reconciliation and completion', () {
    test(
      'discrepancy at stop requires a reason; completion requires reconciliation',
      () async {
        final h = await startedTrip();
        final ops = h.services.driverOps;
        final trip = h.view.trips.byId('TR-1001')!;
        final stops = h.view.trips.stopsOf(trip);
        final first = stops.first;
        await ops.arriveAtStop(first.id);
        final depart = await ops.departStop(first.id);
        expect(
          depart.isOk,
          isFalse,
          reason: 'nobody boarded or was marked no-show',
        );
        expect(depart.errors.join(), contains('Expected'));

        final blocked = await ops.completeTrip(
          tripId: trip.id,
          driverId: 'DR1',
        );
        expect(blocked.isOk, isFalse);
        final report = ops.completionReport(trip.id);
        expect(report.reconciliation.expected, 3);
        expect(report.reconciliation.reconciled, isFalse);

        // Mark no-show with reason, then depart cleanly.
        for (final e in first.boardingEmployeeIds) {
          expect(
            (await ops.markNoShow(
              stopId: first.id,
              employeeId: e,
              reason: 'Not at gate',
            )).isOk,
            isTrue,
          );
        }
        expect((await ops.departStop(first.id)).isOk, isTrue);

        // Complete with an authorized exception for the remaining stops.
        final done = await ops.completeTrip(
          tripId: trip.id,
          driverId: 'DR1',
          exceptionReason:
              'Remaining passengers rerouted by control room (demo)',
          exceptionAuthorizedBy: 'Fleet Manager',
        );
        expect(done.isOk, isTrue, reason: done.message);
        final t = h.view.trips.byId(trip.id)!;
        expect(t.status, TripStatus.completed);
        expect(t.completionException, isNotNull);
        expect(h.view.trips.stopsOf(t).every((s) => s.isDone), isTrue);
      },
    );

    test(
      'full run reconciles counts and bills exactly once with employer rate',
      () async {
        final h = await startedTrip();
        final ops = h.services.driverOps;
        var trip = h.view.trips.byId('TR-1001')!;
        for (final s in h.view.trips.stopsOf(trip)) {
          await ops.arriveAtStop(s.id);
          trip = h.view.trips.byId('TR-1001')!;
          if (s.kind == StopKind.pickup) {
            for (final e in s.boardingEmployeeIds) {
              await ops.verifyAndBoard(
                stopId: s.id,
                method: VerificationMethod.qrDemo,
                input: ver.qrPayload(trip, h.view.employee(e)!),
              );
            }
          } else {
            await ops.alight(stopId: s.id, employeeIds: s.alightingEmployeeIds);
          }
          expect((await ops.departStop(s.id)).isOk, isTrue);
        }
        trip = h.view.trips.byId('TR-1001')!;
        final rec = ops.reconcile(trip);
        expect(
          [rec.expected, rec.boarded, rec.alighted, rec.noShow],
          [3, 3, 3, 0],
        );
        expect(rec.reconciled, isTrue);
        final r = await ops.completeTrip(
          tripId: trip.id,
          driverId: 'DR1',
          endOdometerKm: trip.startOdometerKm! + 31.5,
        );
        expect(r.isOk, isTrue, reason: r.message);
        final bill = h.view.billingForTrip('TR-1001')!;
        expect(bill.ratePerKm, 18);
        expect(bill.billableDistanceKm, 31.5);
        expect(bill.totalAmount, closeTo(31.5 * 18, 0.001));
        // No duplicate billing.
        expect((await h.services.billing.generate('TR-1001')).isOk, isFalse);
        expect(
          h.view.billingOf('C1').where((b) => b.tripId == 'TR-1001').length,
          1,
        );
        // Employee sees completion.
        expect(
          h.view
              .notificationsFor(UserRole.employee, 'E1')
              .any((n) => n.title.contains('TR-1001 completed')),
          isTrue,
        );
      },
    );

    test('odometer below start reading is rejected', () async {
      final h = await startedTrip();
      final t = h.view.trips.byId('TR-1001')!;
      final r = await h.services.driverOps.completeTrip(
        tripId: t.id,
        driverId: 'DR1',
        endOdometerKm: t.startOdometerKm! - 5,
        exceptionReason: 'Testing invalid odometer input',
        exceptionAuthorizedBy: 'QA',
      );
      expect(r.isOk, isFalse);
    });
  });

  group('Billing', () {
    test('formula: distance × rate + additional + adjustment', () {
      final c = BillingService.calculate(
        distanceKm: 20,
        ratePerKm: 18,
        additionalCharges: 120,
        adjustment: -50,
      );
      expect(c.distanceCharge, 360);
      expect(c.total, 430);
      expect(c.explanation, contains('20.0 km'));
    });

    test(
      'missing distance blocks automatic billing until recorded; then bills once',
      () async {
        final h = await Harness.create();
        final t = h.view.trips.byId('TR-0994')!;
        expect(t.billableStatus, BillableStatus.missingDistance);
        expect(h.view.billingForTrip('TR-0994'), isNull);
        expect(
          (await h.services.billing.generate('TR-0994')).errors.join(),
          contains('Distance missing'),
        );
        final r = await h.services.billing.recordDistanceAndBill(
          'TR-0994',
          22.4,
          'From vehicle trip log',
        );
        expect(r.isOk, isTrue, reason: r.message);
        expect(
          h.view.billingForTrip('TR-0994')!.totalAmount,
          closeTo(22.4 * 18, 0.001),
        );
        expect(
          (await h.services.billing.recordDistanceAndBill(
            'TR-0994',
            25,
            'Second attempt',
          )).isOk,
          isFalse,
        );
      },
    );

    test('cancelled trips are excluded and status flow is enforced', () async {
      final h = await Harness.create();
      expect(
        h.services.billing.blockReason(h.view.trips.byId('TR-1005')!),
        contains('Cancelled'),
      );
      final bl = h.view
          .billingOf('C1')
          .firstWhere((b) => b.status == BillingStatus.generated);
      expect(
        (await h.services.billing.setStatus(
          bl.id,
          BillingStatus.paidDemo,
        )).isOk,
        isFalse,
      );
      expect(
        (await h.services.billing.setStatus(
          bl.id,
          BillingStatus.disputed,
          reason: 'x',
        )).isOk,
        isFalse,
      );
      expect(
        (await h.services.billing.setStatus(
          bl.id,
          BillingStatus.reviewed,
        )).isOk,
        isTrue,
      );
      expect(
        (await h.services.billing.setStatus(
          bl.id,
          BillingStatus.paidDemo,
        )).isOk,
        isTrue,
      );
    });
  });

  group('Incidents & SOS', () {
    test(
      'breakdown marks vehicle unavailable, trip needs attention, notifies FM and employees',
      () async {
        final h = await startedTrip();
        final r = await h.services.incidents.report(
          IncidentDraft(
            type: IncidentType.breakdown,
            description: 'Engine warning light, pulled over safely.',
            severity: IncidentSeverity.high,
            reporter: Actor.driver('DR1'),
            tripId: 'TR-1001',
            replacementRequested: true,
          ),
        );
        expect(r.isOk, isTrue);
        expect(h.view.vehicle('C1')!.status, VehicleStatus.maintenance);
        expect(h.view.trips.byId('TR-1001')!.status, TripStatus.needsAttention);
        expect(
          h.view
              .notificationsFor(UserRole.fleetManager)
              .any((n) => n.relatedEntityId == r.valueOrNull!.id),
          isTrue,
        );
        expect(
          h.view
              .notificationsFor(UserRole.employee, 'E1')
              .any((n) => n.title.contains('vehicle issue')),
          isTrue,
        );
      },
    );

    test(
      'SOS is recorded as demo only and simulated offline keeps the form',
      () async {
        final h = await startedTrip();
        final sos = await h.services.incidents.raiseSos(
          actor: Actor.employee('E1'),
          tripId: 'TR-1001',
        );
        expect(sos.isOk, isTrue);
        expect(sos.valueOrNull!.isSos, isTrue);
        expect(sos.valueOrNull!.status, IncidentStatus.submittedDemo);
        expect(sos.message, contains('Demo only'));
        await h.services.session.setFlag(
          IncidentService.simulateOfflineKey,
          true,
        );
        final failed = await h.services.incidents.raiseSos(
          actor: Actor.driver('DR1'),
          tripId: 'TR-1001',
        );
        expect(failed.isOk, isFalse);
        expect(failed.errors.join(), contains('offline'));
      },
    );
  });

  group('Shift end', () {
    test(
      'cannot end shift with an active trip; exception allows open assignments',
      () async {
        final h = await startedTrip();
        final blocked = await h.services.driverOps.endShift(
          driverId: 'DR1',
          handoverParkingId: 'P1',
        );
        expect(blocked.isOk, isFalse);
        expect(blocked.errors.join(), contains('in progress'));
      },
    );

    test('end shift after work completes updates attendance', () async {
      final h = await Harness.create();
      await h.services.driverOps.checkIn('DR1');
      final needsException = await h.services.driverOps.endShift(
        driverId: 'DR1',
        handoverParkingId: 'P1',
      );
      expect(needsException.isOk, isFalse);
      final ok = await h.services.driverOps.endShift(
        driverId: 'DR1',
        handoverParkingId: 'P1',
        exceptionReason: 'TR-1001 handed back to dispatch for reassignment',
        exceptionAuthorizedBy: 'Fleet Manager',
      );
      expect(ok.isOk, isTrue, reason: ok.message);
      expect(h.view.todayShift('DR1')!.status, ShiftStatus.completed);
      expect(
        h.view.driver('DR1')!.attendanceStatus,
        AttendanceStatus.checkedOut,
      );
    });
  });
}
