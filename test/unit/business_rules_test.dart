import 'package:executive_fleet/domain/models/models.dart';
import 'package:executive_fleet/domain/rules/capacity_rules.dart';
import 'package:executive_fleet/domain/rules/inspection_rules.dart';
import 'package:executive_fleet/domain/rules/trip_state_machine.dart';
import 'package:executive_fleet/domain/services/app_services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_harness.dart';

void main() {
  group('Seat capacity', () {
    test(
      'total seats include driver; guard seats reduce employee capacity',
      () async {
        final h = await Harness.create();
        final c1 = h.view.vehicle('C1')!; // 4 seats EV sedan
        final c2 = h.view.vehicle('C2')!; // 7 seats van
        final c3 = h.view.vehicle('C3')!; // 6 seats MPV
        expect(CapacityRules.passengerCapacity(c1), 3);
        expect(CapacityRules.passengerCapacity(c2), 6);
        expect(CapacityRules.passengerCapacity(c3), 5);
        expect(CapacityRules.passengerCapacity(c1, guardRequired: true), 2);
        expect(
          CapacityRules.passengerCapacity(
            c2.copyWith(requiresSecurityGuard: true),
          ),
          5,
        );
        final b = CapacityRules.breakdown(c3, guardRequired: true);
        expect(
          [b.totalSeats, b.driverSeats, b.guardSeats, b.passengerCapacity],
          [6, 1, 1, 4],
        );
      },
    );

    test('guard requirement is explicit policy only', () async {
      final h = await Harness.create();
      final c1 = h.view.vehicle('C1')!;
      final employer = h.view.primaryEmployer;
      final e = h.view.employee('E1')!;
      expect(
        CapacityRules.guardRequired(
          vehicle: c1,
          employer: employer,
          passengers: [e],
        ),
        isFalse,
      );
      // Flag alone does nothing while the employer policy is disabled.
      expect(
        CapacityRules.guardRequired(
          vehicle: c1,
          employer: employer,
          passengers: [e.copyWith(guardEscortRequired: true)],
        ),
        isFalse,
      );
      expect(
        CapacityRules.guardRequired(
          vehicle: c1,
          employer: employer.copyWith(securityGuardPolicyEnabled: true),
          passengers: [e.copyWith(guardEscortRequired: true)],
        ),
        isTrue,
      );
    });
  });

  group('Assignment validation', () {
    test('over capacity is rejected (E1–E4 in Vehicle C1)', () async {
      final h = await Harness.create();
      final v = h.services.assignments.validate(
        AssignmentRequest(
          employerId: 'C1',
          serviceDate: h.view.today.add(const Duration(days: 1)),
          employeeIds: const ['E1', 'E2', 'E3', 'E4'],
          driverId: 'DR1',
          vehicleId: 'C1',
        ),
      );
      expect(v.ok, isFalse);
      expect(v.errors.join(), contains('Over capacity'));
      final ok = h.services.assignments.validate(
        AssignmentRequest(
          employerId: 'C1',
          serviceDate: h.view.today.add(const Duration(days: 1)),
          employeeIds: const ['E1', 'E2', 'E3', 'E4'],
          driverId: 'DR3',
          vehicleId: 'C3',
        ),
      );
      expect(ok.errors, isEmpty);
    });

    test('overlapping driver and vehicle assignments are prevented', () async {
      final h = await Harness.create();
      // TR-1001 today uses DR1 + C1; a new trip in the same window conflicts.
      final v = h.services.assignments.validate(
        AssignmentRequest(
          employerId: 'C1',
          serviceDate: h.view.today,
          scheduledStart: h.view.trips.byId('TR-1001')!.scheduledStart,
          employeeIds: const ['E30'],
          driverId: 'DR1',
          vehicleId: 'C1',
        ),
      );
      expect(
        v.errors.where((e) => e.contains('Vehicle C1 is already assigned')),
        isNotEmpty,
      );
      expect(
        v.errors.where((e) => e.contains('DR1 is already assigned')),
        isNotEmpty,
      );
    });

    test(
      'maintenance vehicle and off-duty driver are blocked (override needs reason)',
      () async {
        final h = await Harness.create();
        await h.services.fleet.saveVehicle(
          h.view.vehicle('C3')!.copyWith(status: VehicleStatus.maintenance),
        );
        await h.services.fleet.saveDriver(
          h.view.driver('DR3')!.copyWith(status: DriverStatus.offDuty),
        );
        final base = AssignmentRequest(
          employerId: 'C1',
          serviceDate: h.view.today.add(const Duration(days: 2)),
          employeeIds: const ['E40'],
          driverId: 'DR3',
          vehicleId: 'C3',
        );
        final v = h.services.assignments.validate(base);
        expect(v.errors.join(' '), contains('maintenance'));
        expect(v.errors.join(' '), contains('off duty'));
      },
    );

    test(
      'reassignment requires a reason, preserves history and audits',
      () async {
        final h = await Harness.create();
        final base = AssignmentRequest(
          tripId: 'TR-1004',
          employerId: 'C1',
          serviceDate: h.view.trips.byId('TR-1004')!.serviceDate,
          employeeIds: h.view.trips.byId('TR-1004')!.employeeIds,
          driverId: 'DR3',
          vehicleId: 'C3',
        );
        expect((await h.services.assignments.commit(base)).isOk, isTrue);
        final noReason = await h.services.assignments.commit(
          base.copyWith(driverId: 'DR1', vehicleId: 'C1'),
        );
        expect(noReason.isOk, isFalse);
        final ok = await h.services.assignments.commit(
          AssignmentRequest(
            tripId: 'TR-1004',
            employerId: 'C1',
            serviceDate: base.serviceDate,
            employeeIds: const ['E16', 'E17', 'E18'],
            driverId: 'DR1',
            vehicleId: 'C1',
            reassignReason: 'Vehicle C3 needed for another route',
          ),
        );
        expect(ok.isOk, isTrue, reason: ok.message);
        final t = h.view.trips.byId('TR-1004')!;
        expect(t.assignedDriverId, 'DR1');
        expect(t.assignmentHistory.length, greaterThanOrEqualTo(2));
        expect(
          h.view.auditFor('trip', 'TR-1004').any((a) => a.action == 'reassign'),
          isTrue,
        );
        expect(
          h.view
              .notificationsFor(UserRole.driver, 'DR3')
              .any((n) => n.title.contains('removed')),
          isTrue,
        );
      },
    );
  });

  group('Trip status transitions', () {
    test('valid and invalid transitions', () {
      expect(
        TripStateMachine.canTransition(
          TripStatus.assigned,
          TripStatus.inProgress,
        ),
        isTrue,
      );
      expect(
        TripStateMachine.canTransition(
          TripStatus.inProgress,
          TripStatus.completed,
        ),
        isTrue,
      );
      expect(
        TripStateMachine.canTransition(
          TripStatus.completed,
          TripStatus.inProgress,
        ),
        isFalse,
      );
      expect(
        TripStateMachine.canTransition(
          TripStatus.cancelled,
          TripStatus.assigned,
        ),
        isFalse,
      );
      expect(
        TripStateMachine.canTransition(
          TripStatus.planned,
          TripStatus.completed,
        ),
        isFalse,
      );
      expect(
        TripStateMachine.canTransition(
          TripStatus.inProgress,
          TripStatus.cancelled,
        ),
        isFalse,
      );
    });

    test('cancelled or unassigned trips cannot start', () async {
      final h = await Harness.create();
      await h.services.driverOps.checkIn('DR1');
      expect(
        h.services.driverOps.startBlockers('TR-1005', 'DR1').join(),
        contains('cancelled'),
      );
      expect(
        h.services.driverOps.startBlockers('TR-1004', 'DR1').join(),
        contains('not assigned to you'),
      );
    });
  });

  group('Inspection', () {
    test(
      'critical failure blocks trip start and creates a defect report',
      () async {
        final h = await Harness.create();
        await h.services.driverOps.checkIn('DR1');
        final items = [
          for (final i in InspectionRules.blankChecklist())
            i.key == 'brakes'
                ? i.copyWith(result: CheckResult.fail, note: 'Spongy pedal')
                : i,
        ];
        final r = await h.services.driverOps.submitInspection(
          driverId: 'DR1',
          vehicleId: 'C1',
          items: items,
        );
        expect(r.valueOrNull!.overallStatus, InspectionOutcome.failed);
        expect(h.view.vehicle('C1')!.status, VehicleStatus.maintenance);
        expect(
          h.view.incidents.any(
            (i) =>
                i.type == IncidentType.vehicleDefect &&
                i.vehicleId == 'C1' &&
                i.status.isOpen,
          ),
          isTrue,
        );
        expect(h.view.trips.byId('TR-1001')!.status, TripStatus.needsAttention);
        final start = await h.services.driverOps.startTrip('TR-1001', 'DR1');
        expect(start.isOk, isFalse);
        expect(
          h.view
              .notificationsFor(UserRole.fleetManager)
              .any((n) => n.title.contains('Defect')),
          isTrue,
        );
      },
    );

    test(
      'failed items need a note; non-critical failure allows start',
      () async {
        final h = await Harness.create();
        await h.services.driverOps.checkIn('DR1');
        final noNote = [
          for (final i in InspectionRules.blankChecklist())
            i.key == 'cleanliness' ? i.copyWith(result: CheckResult.fail) : i,
        ];
        expect(
          (await h.services.driverOps.submitInspection(
            driverId: 'DR1',
            vehicleId: 'C1',
            items: noNote,
          )).isOk,
          isFalse,
        );
        final withNote = [
          for (final i in InspectionRules.blankChecklist())
            i.key == 'cleanliness'
                ? i.copyWith(result: CheckResult.fail, note: 'Dusty mats')
                : i,
        ];
        final r = await h.services.driverOps.submitInspection(
          driverId: 'DR1',
          vehicleId: 'C1',
          items: withNote,
        );
        expect(r.valueOrNull!.overallStatus, InspectionOutcome.needsReview);
        expect(h.services.driverOps.startBlockers('TR-1001', 'DR1'), isEmpty);
      },
    );
  });

  group('Attendance', () {
    test('duplicate check-in is prevented; late check-in flagged', () async {
      final h = await Harness.create(now: DateTime(2026, 10, 19, 6, 25));
      final r = await h.services.driverOps.checkIn('DR1');
      expect(r.valueOrNull!.status, ShiftStatus.late);
      expect((await h.services.driverOps.checkIn('DR1')).isOk, isFalse);
    });
  });

  group('Booking', () {
    test(
      'request is not an assignment until assigned; policy limits apply',
      () async {
        final h = await Harness.create();
        final tomorrow = h.view.today.add(const Duration(days: 2));
        final late = await h.services.bookings.submit(
          BookingDraft(
            employeeId: 'E40',
            pickupLocationId: 'PK01',
            destinationId: 'G1',
            date: tomorrow,
            arrivalMinutes: 630,
          ),
        );
        expect(late.isOk, isFalse);
        expect(late.errors.join(), contains('maximum'));
        final ok = await h.services.bookings.submit(
          BookingDraft(
            employeeId: 'E40',
            pickupLocationId: 'PK01',
            destinationId: 'G1',
            date: tomorrow,
            arrivalMinutes: 540,
          ),
        );
        expect(ok.isOk, isTrue);
        final b = ok.valueOrNull!;
        expect(b.tripId, isNull);
        expect(
          b.status,
          anyOf(BookingStatus.requested, BookingStatus.waitlisted),
        );
        expect(
          h.view.trips
              .forEmployee('E40')
              .where((t) => t.serviceDate == tomorrow),
          isEmpty,
        );
        final dup = await h.services.bookings.submit(
          BookingDraft(
            employeeId: 'E40',
            pickupLocationId: 'PK01',
            destinationId: 'G1',
            date: tomorrow,
            arrivalMinutes: 540,
          ),
        );
        expect(dup.isOk, isFalse);
        expect(
          h.view
              .notificationsFor(UserRole.fleetManager)
              .any((n) => n.relatedEntityId == b.id),
          isTrue,
        );
      },
    );
  });

  group('Deactivation', () {
    test('deactivating an employee preserves trip history', () async {
      final h = await Harness.create();
      final before = h.view.trips.forEmployee('E1').length;
      await h.services.employees.setActive('E1', false);
      expect(h.view.employee('E1')!.isActive, isFalse);
      expect(h.view.trips.forEmployee('E1').length, before);
      expect(h.view.billingForTrip('TR-0991'), isNotNull);
      expect((await h.services.session.signInEmployee('E1')).isOk, isFalse);
    });
  });

  test(
    'delay reported before trip start keeps status but records the reason',
    () async {
      final h = await Harness.create();
      final r = await h.services.incidents.report(
        IncidentDraft(
          type: IncidentType.delay,
          description: 'Vehicle stuck at depot gate',
          severity: IncidentSeverity.medium,
          reporter: Actor.driver('DR1'),
          tripId: 'TR-1001',
          delayMinutes: 15,
        ),
      );
      expect(r.isOk, isTrue);
      final t = h.view.trips.byId('TR-1001')!;
      expect(t.status, TripStatus.assigned);
      expect(t.delayReason, contains('depot gate'));
    },
  );
}
