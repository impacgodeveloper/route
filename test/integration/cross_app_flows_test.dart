import 'package:executive_fleet/domain/models/models.dart';
import 'package:executive_fleet/domain/rules/inspection_rules.dart';
import 'package:executive_fleet/domain/services/app_services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_harness.dart';

/// Cross-workspace flows (spec §10 / §15 integration list) exercised through
/// the shared services and read model that all four workspaces use. Each
/// expectation is phrased as what a specific workspace sees.
void main() {
  const ver = VerificationService();

  test(
    '1. Booking → assignment → Employee and Driver update (flow B)',
    () async {
      final h = await Harness.create();
      final s = h.services;
      final day = h.view.today.add(const Duration(days: 2));
      final req = await s.bookings.submit(
        BookingDraft(
          employeeId: 'E1',
          pickupLocationId: 'PK01',
          destinationId: 'G1',
          date: day,
          arrivalMinutes: 540,
        ),
      );
      expect(req.isOk, isTrue, reason: req.message);
      final id = req.valueOrNull!.id;
      // Fleet Manager + Employer see it.
      expect(h.view.openBookings.any((b) => b.id == id), isTrue);
      expect(
        h.view
            .notificationsFor(UserRole.employerAdmin)
            .any((n) => n.relatedEntityId == id),
        isTrue,
      );
      // Employee: not a trip yet.
      expect(
        h.view.trips.forEmployee('E1').where((t) => t.serviceDate == day),
        isEmpty,
      );
      // Fleet Manager approves and assigns.
      expect((await s.bookings.approve(id)).isOk, isTrue);
      final trip = await s.bookings.createTripForBookings(
        [id],
        driverId: 'DR1',
        vehicleId: 'C1',
      );
      expect(trip.isOk, isTrue, reason: trip.message);
      final t = trip.valueOrNull!;
      // Employee view.
      expect(h.view.booking(id)!.status, BookingStatus.assigned);
      expect(
        h.view.trips
            .forEmployee('E1')
            .any((x) => x.id == t.id && x.assignedVehicleId == 'C1'),
        isTrue,
      );
      expect(
        h.view
            .notificationsFor(UserRole.employee, 'E1')
            .any((n) => n.relatedEntityId == t.id),
        isTrue,
      );
      // Driver view.
      expect(h.view.trips.forDriver('DR1').any((x) => x.id == t.id), isTrue);
      expect(
        h.view
            .notificationsFor(UserRole.driver, 'DR1')
            .any((n) => n.relatedEntityId == t.id),
        isTrue,
      );
      // Employer view (assignments).
      expect(
        h.view.trips.all().where((x) => x.employerId == 'C1' && x.id == t.id),
        isNotEmpty,
      );
    },
  );

  test('2. Shift → inspection → trip start (flow D)', () async {
    final h = await Harness.create();
    final ops = h.services.driverOps;
    expect(
      ops.startBlockers('TR-1001', 'DR1'),
      contains('Check in to your shift first.'),
    );
    await ops.checkIn('DR1');
    expect(ops.startBlockers('TR-1001', 'DR1').join(), contains('inspection'));
    await ops.submitInspection(
      driverId: 'DR1',
      vehicleId: 'C1',
      items: InspectionRules.blankChecklist(),
    );
    expect(ops.startBlockers('TR-1001', 'DR1'), isEmpty);
    expect((await ops.startTrip('TR-1001', 'DR1')).isOk, isTrue);
    expect(h.view.trips.byId('TR-1001')!.status, TripStatus.inProgress);
    expect(h.view.vehicle('C1')!.status, VehicleStatus.onTrip);
    expect(h.view.driver('DR1')!.status, DriverStatus.onTrip);
  });

  test('3. Boarding → passenger status update (flow E)', () async {
    final h = await Harness.create();
    final ops = h.services.driverOps;
    await ops.checkIn('DR1');
    await ops.submitInspection(
      driverId: 'DR1',
      vehicleId: 'C1',
      items: InspectionRules.blankChecklist(),
    );
    await ops.startTrip('TR-1001', 'DR1');
    final trip = h.view.trips.byId('TR-1001')!;
    final stop = h.view.trips.stopsOf(trip).first;
    final eid = stop.boardingEmployeeIds.first;
    expect(h.view.trips.passengerState(trip, eid), PassengerState.awaiting);
    await ops.arriveAtStop(stop.id);
    final r = await ops.verifyAndBoard(
      stopId: stop.id,
      method: VerificationMethod.tpinDemo,
      input: ver.tpin(trip, h.view.employee(eid)!),
      employeeId: eid,
    );
    expect(r.valueOrNull!.ok, isTrue);
    final after = h.view.trips.byId('TR-1001')!;
    // Employee e-pass status and driver manifest read the same record.
    expect(h.view.trips.passengerState(after, eid), PassengerState.boarded);
    expect(ops.reconcile(after).boarded, 1);
    expect(
      h.view.trips.eventsOf(after).single.verificationMethod,
      VerificationMethod.tpinDemo,
    );
    expect(
      h.view.trips.eventsOf(after).single.note,
      isNot(contains(ver.tpin(trip, h.view.employee(eid)!))),
    );
  });

  test('4. Trip completion → Employer billing (flows F + G)', () async {
    final h = await Harness.create();
    final ops = h.services.driverOps;
    await ops.checkIn('DR1');
    await ops.submitInspection(
      driverId: 'DR1',
      vehicleId: 'C1',
      items: InspectionRules.blankChecklist(),
    );
    await ops.startTrip('TR-1001', 'DR1');
    for (final st in h.view.trips.stopsOf(h.view.trips.byId('TR-1001')!)) {
      await ops.arriveAtStop(st.id);
      final t = h.view.trips.byId('TR-1001')!;
      if (st.kind == StopKind.pickup) {
        for (final e in st.boardingEmployeeIds) {
          await ops.verifyAndBoard(
            stopId: st.id,
            method: VerificationMethod.qrDemo,
            input: ver.qrPayload(t, h.view.employee(e)!),
          );
        }
      } else {
        await ops.alight(stopId: st.id, employeeIds: st.alightingEmployeeIds);
      }
      await ops.departStop(st.id);
    }
    final before = h.view
        .billingOf('C1')
        .fold<double>(0, (s, b) => s + b.totalAmount);
    final t = h.view.trips.byId('TR-1001')!;
    final done = await ops.completeTrip(
      tripId: t.id,
      driverId: 'DR1',
      endOdometerKm: t.startOdometerKm! + 28,
    );
    expect(done.isOk, isTrue, reason: done.message);
    final line = h.view.billingForTrip('TR-1001')!;
    expect(line.totalAmount, 28 * h.view.employer('C1')!.defaultDistanceRate);
    expect(
      h.view.billingOf('C1').fold<double>(0, (s, b) => s + b.totalAmount),
      closeTo(before + line.totalAmount, 0.001),
    );
    expect(
      h.view
          .notificationsFor(UserRole.employerAdmin)
          .any((n) => n.relatedEntityId == line.id),
      isTrue,
    );
    expect(h.view.booking('BK-1002')!.status, BookingStatus.completed);
    expect(h.view.vehicle('C1')!.odometerKm, t.startOdometerKm! + 28);
  });

  test(
    '5. Vehicle defect → Fleet Manager alert and assignment block',
    () async {
      final h = await Harness.create();
      await h.services.driverOps.checkIn('DR1');
      final items = [
        for (final i in InspectionRules.blankChecklist())
          i.key == 'tyres'
              ? i.copyWith(result: CheckResult.fail, note: 'Puncture')
              : i,
      ];
      await h.services.driverOps.submitInspection(
        driverId: 'DR1',
        vehicleId: 'C1',
        items: items,
      );
      expect(
        h.view.openIncidents.any(
          (i) => i.type == IncidentType.vehicleDefect && i.vehicleId == 'C1',
        ),
        isTrue,
      );
      expect(
        h.view
            .notificationsFor(UserRole.fleetManager)
            .any((n) => n.title.contains('Vehicle C1')),
        isTrue,
      );
      final v = h.services.assignments.validate(
        AssignmentRequest(
          employerId: 'C1',
          serviceDate: h.view.today.add(const Duration(days: 1)),
          employeeIds: const ['E1'],
          driverId: 'DR1',
          vehicleId: 'C1',
        ),
      );
      expect(v.errors.join(), contains('maintenance'));
      expect(h.view.trips.byId('TR-1001')!.status, TripStatus.needsAttention);
      // Employee notified that the trip is under review.
      expect(
        h.view
            .notificationsFor(UserRole.employee, 'E1')
            .any((n) => n.title.contains('under review')),
        isTrue,
      );
    },
  );

  test(
    '6. EV target set by Employer → Fleet Manager target vs actual + optimizer (flows H + I)',
    () async {
      final h = await Harness.create();
      final employer = h.view.employer('C1')!;
      final saved = await h.services.employers.update(
        employer.copyWith(preferredEvPercentage: 100),
      );
      expect(saved.isOk, isTrue);
      expect(
        h.view.optimizationConfigs.first.minimumEvPercentage,
        100,
        reason: 'profile synced',
      );
      final ev = h.services.optimization.evTarget('C1', h.view.today);
      expect(ev.targetPct, 100);
      expect(ev.feasible, isFalse, reason: 'only 2 EVs for 3 trips today');
      expect(ev.explanation.join(), contains('not achievable'));
      final opt = h.services.optimization;
      final run = await opt.runAndSave(
        opt.buildInput(
          config: h.view.optimizationConfigs.first,
          employeeIds: const ['E1', 'E2', 'E3', 'E4'],
          serviceDate: h.view.today.add(const Duration(days: 1)),
        ),
      );
      expect(run.valueOrNull!.isFeasible, isTrue);
      final applied = await opt.applyRun(run.valueOrNull!.id);
      expect(applied.isOk, isTrue, reason: applied.message);
      for (final t in applied.valueOrNull!) {
        expect(
          h.view.trips.forDriver(t.assignedDriverId!).any((x) => x.id == t.id),
          isTrue,
        );
      }
    },
  );

  test('7. Reassignment updates all relevant views (flow K)', () async {
    final h = await Harness.create();
    final t = h.view.trips.byId('TR-1001')!;
    final r = await h.services.assignments.commit(
      AssignmentRequest(
        tripId: t.id,
        employerId: t.employerId,
        serviceDate: t.serviceDate,
        employeeIds: t.employeeIds,
        driverId: 'DR3',
        vehicleId: 'C3',
        scheduledStart: t.scheduledStart.add(const Duration(minutes: 90)),
        reassignReason: 'C1 sent for battery service',
      ),
    );
    // C3/DR3 are busy on TR-1003 in the same morning window → must be rejected.
    expect(r.isOk, isFalse);
    // Use tomorrow's planned trip instead: assign → reassign.
    final p = h.view.trips.byId('TR-1004')!;
    await h.services.assignments.commit(
      AssignmentRequest(
        tripId: p.id,
        employerId: 'C1',
        serviceDate: p.serviceDate,
        employeeIds: p.employeeIds,
        driverId: 'DR3',
        vehicleId: 'C3',
      ),
    );
    final rr = await h.services.assignments.commit(
      AssignmentRequest(
        tripId: p.id,
        employerId: 'C1',
        serviceDate: p.serviceDate,
        employeeIds: p.employeeIds,
        driverId: 'DR2',
        vehicleId: 'C2',
        reassignReason: 'Rebalancing EV usage',
      ),
    );
    // DR2/C2 run TR-1006 tomorrow morning; validator explains the conflict honestly.
    if (!rr.isOk) {
      expect(rr.errors.join(), contains('already assigned'));
      final ok = await h.services.assignments.commit(
        AssignmentRequest(
          tripId: p.id,
          employerId: 'C1',
          serviceDate: p.serviceDate,
          employeeIds: p.employeeIds.take(3).toList(),
          driverId: 'DR1',
          vehicleId: 'C1',
          reassignReason: 'Rebalancing EV usage',
        ),
      );
      expect(ok.isOk, isTrue, reason: ok.message);
    }
    final after = h.view.trips.byId(p.id)!;
    expect(after.assignedDriverId, isNot('DR3'));
    expect(
      h.view.trips.forDriver('DR3').any((x) => x.id == p.id),
      isFalse,
      reason: 'old driver no longer sees it',
    );
    expect(
      h.view.trips.forDriver(after.assignedDriverId!).any((x) => x.id == p.id),
      isTrue,
    );
    expect(
      h.view
          .notificationsFor(UserRole.driver, 'DR3')
          .any((n) => n.title.contains('removed')),
      isTrue,
    );
    expect(
      h.view
          .notificationsFor(UserRole.employee, after.employeeIds.first)
          .any((n) => n.relatedEntityId == p.id),
      isTrue,
    );
    expect(
      h.view.auditFor('trip', p.id).any((a) => a.action == 'reassign'),
      isTrue,
    );
    expect(after.assignmentHistory.length, greaterThanOrEqualTo(2));
  });

  test('8. Reset restores baseline seed data', () async {
    final h = await Harness.create();
    await h.services.bookings.submit(
      BookingDraft(
        employeeId: 'E50',
        pickupLocationId: 'PK01',
        destinationId: 'G1',
        date: h.view.today.add(const Duration(days: 3)),
        arrivalMinutes: 540,
      ),
    );
    await h.services.driverOps.checkIn('DR1');
    final countBefore = h.view.bookings.length;
    await h.services.seed.reset();
    expect(h.view.bookings.length, countBefore - 1);
    expect(h.view.todayShift('DR1')!.actualCheckIn, isNull);
    expect(h.view.auth.currentEmployeeId, isNull);
    final h2 = await h.restart();
    expect(h2.view.bookings.length, countBefore - 1);
  });

  test(
    '9. Incident / SOS → Fleet Manager queue, trip status, employee notice (flow J)',
    () async {
      final h = await Harness.create();
      final r = await h.services.incidents.report(
        IncidentDraft(
          type: IncidentType.delay,
          description: 'Road closed near Banyan Circle',
          severity: IncidentSeverity.medium,
          reporter: Actor.driver('DR2'),
          tripId: 'TR-1002',
          delayMinutes: 15,
        ),
      );
      expect(r.isOk, isTrue);
      expect(h.view.trips.byId('TR-1002')!.status, TripStatus.delayed);
      expect(h.view.openIncidents.first.id, isNotEmpty);
      expect(
        h.view
            .notificationsFor(UserRole.employee, 'E5')
            .any(
              (n) =>
                  n.category == NotificationCategory.delay &&
                  n.relatedEntityId == 'TR-1002',
            ),
        isTrue,
      );
      final res = await h.services.incidents.setStatus(
        r.valueOrNull!.id,
        IncidentStatus.resolvedDemo,
        notes: 'Detour taken',
      );
      expect(res.isOk, isTrue);
    },
  );
}
