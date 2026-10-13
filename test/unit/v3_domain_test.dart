import 'package:executive_fleet/domain/models/models.dart';
import 'package:executive_fleet/domain/rules/inspection_rules.dart';
import 'package:executive_fleet/domain/services/app_services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_harness.dart';

DateTime tomorrow(Harness h) => h.view.today.add(const Duration(days: 1));

Future<void> readyDr1(Harness h) async {
  await h.services.driverOps.checkIn('DR1');
  await h.services.driverOps.submitInspection(
    driverId: 'DR1',
    vehicleId: 'C1',
    items: InspectionRules.blankChecklist(),
  );
}

void main() {
  group('1 · Alcohol monitoring (configurable)', () {
    test(
      'seeded pass allows start; failed test blocks, raises incident, needs FM clear + retest',
      () async {
        final h = await Harness.create();
        final s = h.services;
        expect(h.view.policy.alcoholMonitoringEnabled, isTrue);
        await readyDr1(h);
        expect(s.driverOps.startBlockers('TR-1001', 'DR1'), isEmpty);
        final fail = await s.alcohol.record(driverId: 'DR1', readingMg: 25);
        expect(fail.valueOrNull!.result, AlcoholResult.fail);
        expect(
          s.driverOps.startBlockers('TR-1001', 'DR1').join(),
          contains('Alcohol test failed'),
        );
        expect(h.view.trips.byId('TR-1001')!.status, TripStatus.needsAttention);
        expect(
          h.view.incident(fail.valueOrNull!.incidentId)!.type,
          IncidentType.safety,
        );
        expect(
          h.view
              .notificationsFor(UserRole.fleetManager)
              .any((n) => n.title.contains('Alcohol test failed')),
          isTrue,
        );
        // Clear without note → rejected; with note → still needs retest.
        expect((await s.alcohol.clear(fail.valueOrNull!.id, '')).isOk, isFalse);
        expect(
          (await s.alcohol.clear(
            fail.valueOrNull!.id,
            'Reviewed with driver (demo)',
          )).isOk,
          isTrue,
        );
        expect(
          s.driverOps.startBlockers('TR-1001', 'DR1').join(),
          contains('Alcohol test required'),
        );
        await s.alcohol.record(driverId: 'DR1', readingMg: 0);
        expect(
          s.driverOps
              .startBlockers('TR-1001', 'DR1')
              .where((b) => b.contains('lcohol')),
          isEmpty,
        );
        expect(
          h.view.auditTrail.any(
            (a) =>
                a.action == 'alcohol.test' &&
                a.outcome == AuditOutcome.rejected,
          ),
          isTrue,
        );
      },
    );

    test(
      'inconclusive needs retest; disabling the policy removes the requirement; every-trip mode',
      () async {
        final h = await Harness.create();
        final s = h.services;
        await readyDr1(h);
        await s.alcohol.record(driverId: 'DR1', readingMg: null);
        expect(
          s.driverOps.startBlockers('TR-1001', 'DR1').join(),
          contains('inconclusive'),
        );
        await s.policy.save(
          h.view.policy.copyWith(alcoholMonitoringEnabled: false),
        );
        expect(s.driverOps.startBlockers('TR-1001', 'DR1'), isEmpty);
        await s.policy.save(
          h.view.policy.copyWith(
            alcoholMonitoringEnabled: true,
            alcoholCheckPoint: AlcoholCheckPoint.everyTrip,
          ),
        );
        expect(
          s.driverOps.startBlockers('TR-1001', 'DR1').join(),
          contains('inconclusive'),
        );
        await s.alcohol.record(driverId: 'DR1', readingMg: 0);
        expect(
          s.driverOps.startBlockers('TR-1001', 'DR1').join(),
          contains('before this trip'),
        );
        await s.alcohol.record(
          driverId: 'DR1',
          readingMg: 0,
          tripId: 'TR-1001',
        );
        expect(s.driverOps.startBlockers('TR-1001', 'DR1'), isEmpty);
        expect((await s.driverOps.startTrip('TR-1001', 'DR1')).isOk, isTrue);
        expect(
          h.view
              .notificationsFor(UserRole.driver, 'DR1')
              .any((n) => n.title.contains('Alcohol monitoring')),
          isTrue,
        );
      },
    );

    test('policy validation', () async {
      final h = await Harness.create();
      final p = h.view.policy;
      expect(
        h.services.policy.validate(p.copyWith(alcoholThresholdMg: -1)),
        isNotEmpty,
      );
      expect(
        h.services.policy
            .validate(p.copyWith(sosRecipients: [SosRecipient.police]))
            .join(),
        contains('Fleet Manager'),
      );
    });
  });

  group('1 · Parking placement optimizer', () {
    test(
      'recommends nearest parking to next first pickup within capacity; apply audited',
      () async {
        final h = await Harness.create();
        final recs = h.services.parkingPlanner.recommend();
        expect(recs.length, 3);
        for (final r in recs) {
          expect(
            r.recommendedDeadheadKm,
            lessThanOrEqualTo(r.currentDeadheadKm + 0.0001),
          );
        }
        final c1 = recs.firstWhere((r) => r.vehicle.id == 'C1');
        expect(c1.targetLabel, contains('TR-1001'));
        final changing = recs
            .where((r) => r.changes)
            .map((r) => r.vehicle.id)
            .toList();
        if (changing.isNotEmpty) {
          final applied = await h.services.parkingPlanner.apply(changing);
          expect(applied.isOk, isTrue);
          for (final id in changing) {
            expect(
              h.view.vehicle(id)!.homeParkingId,
              recs.firstWhere((r) => r.vehicle.id == id).recommendedParkingId,
            );
          }
          expect(
            h.view.auditTrail.any((a) => a.action == 'parking.assign'),
            isTrue,
          );
        }
        // Capacity respected: shrink every parking to 1 spot → no two vehicles share.
        for (final p in h.view.parkingLocations) {
          await h.services.fleet.saveLocation(p.copyWith(capacity: 1));
        }
        final again = h.services.parkingPlanner.recommend();
        expect(
          again.map((r) => r.recommendedParkingId).toSet().length,
          again.length,
        );
      },
    );
  });

  group('2 · Telematics, geofences, speed', () {
    test(
      'simulated telemetry: moving vehicle on active trip, parked vehicle idle',
      () async {
        final h = await Harness.create();
        final c2 = h.services.telematics.snapshot(h.view.vehicle('C2')!);
        expect(c2.trip?.id, 'TR-1002');
        expect(c2.speedKmh, greaterThan(0));
        expect(c2.diagnosticCodes.single, contains('P0420'));
        final c1 = h.services.telematics.snapshot(h.view.vehicle('C1')!);
        expect(c1.status, 'Parked');
        expect(c1.speedKmh, 0);
      },
    );

    test(
      'speeding, route deviation, geofence exit, restricted entry, diagnostics — deduped & acknowledged',
      () async {
        final h = await Harness.create();
        final t = h.services.telematics;
        final sp = await t.simulate('C2', VehicleEventType.speeding, value: 82);
        expect(sp.valueOrNull!.single.type, VehicleEventType.speeding);
        expect(
          h.view
              .notificationsFor(UserRole.driver, 'DR2')
              .any((n) => n.title == 'Slow down'),
          isTrue,
        );
        expect(
          (await t.simulate(
            'C2',
            VehicleEventType.speeding,
            value: 85,
          )).valueOrNull,
          isEmpty,
          reason: 'dedupe open event',
        );
        final dev = await t.simulate('C2', VehicleEventType.routeDeviation);
        expect(
          dev.valueOrNull!.any(
            (e) => e.type == VehicleEventType.routeDeviation,
          ),
          isTrue,
        );
        expect(
          (await t.simulate('C1', VehicleEventType.routeDeviation)).isOk,
          isFalse,
          reason: 'no active trip',
        );
        expect(
          (await t.simulate(
            'C3',
            VehicleEventType.geofenceExit,
          )).valueOrNull!.any((e) => e.type == VehicleEventType.geofenceExit),
          isTrue,
        );
        expect(
          (await t.simulate('C3', VehicleEventType.restrictedEntry))
              .valueOrNull!
              .any((e) => e.type == VehicleEventType.restrictedEntry),
          isTrue,
        );
        await t.simulate(
          'C1',
          VehicleEventType.diagnosticFault,
          code: 'P0171 · System too lean (demo)',
        );
        expect(
          h.view.vehicle('C1')!.diagnosticCodes,
          contains('P0171 · System too lean (demo)'),
        );
        await t.clearDiagnostic('C1', 'P0171 · System too lean (demo)');
        expect(h.view.vehicle('C1')!.diagnosticCodes, isEmpty);
        final ack = await t.acknowledge(
          sp.valueOrNull!.single.id,
          note: 'Driver coached',
          raiseIncident: true,
        );
        expect(ack.valueOrNull!.open, isFalse);
        expect(h.view.incident(ack.valueOrNull!.incidentId), isNotNull);
        expect(
          h.view.auditTrail
              .where((a) => a.action.startsWith('telematics.'))
              .every(
                (a) => a.simulated || a.action == 'telematics.clearDiagnostic',
              ),
          isTrue,
        );
        // Disabled alerts → no events.
        await h.services.policy.save(
          h.view.policy.copyWith(speedAlertsEnabled: false),
        );
        expect(
          (await t.simulate(
            'C3',
            VehicleEventType.speeding,
            value: 99,
          )).valueOrNull,
          isEmpty,
        );
      },
    );

    test('geofence validation and scan of current positions', () async {
      final h = await Harness.create();
      final g = h.view.geofence('GF-3')!;
      expect(
        h.services.geofences.validate(g.copyWith(radiusKm: 0)),
        isNotEmpty,
      );
      final r = await h.services.geofences.save(g.copyWith(radiusKm: 3));
      expect(r.isOk, isTrue);
      final scan = await h.services.telematics.scan();
      expect(scan.isOk, isTrue);
    });
  });

  group('3 · SOS escalation', () {
    test(
      'employee SOS alerts FM, company admin, support, driver; police marked integration required',
      () async {
        final h = await Harness.create();
        await readyDr1(h);
        await h.services.driverOps.startTrip('TR-1001', 'DR1');
        final r = await h.services.incidents.raiseSos(
          actor: Actor.employee('E1'),
          tripId: 'TR-1001',
        );
        final inc = r.valueOrNull!;
        final chain = h.view.sosDispatchesOf(inc.id);
        final by = {for (final d in chain) d.recipient: d};
        expect(
          by[SosRecipient.fleetManager]!.status,
          SosDispatchStatus.alertedInApp,
        );
        expect(
          by[SosRecipient.companyAdmin]!.status,
          SosDispatchStatus.alertedInApp,
        );
        expect(by[SosRecipient.supportTeam]!.note, contains('ticket'));
        expect(by[SosRecipient.driver]!.status, SosDispatchStatus.alertedInApp);
        expect(
          by[SosRecipient.police]!.status,
          SosDispatchStatus.integrationRequired,
        );
        expect(
          h.view
              .notificationsFor(UserRole.employerAdmin)
              .any((n) => n.relatedEntityId == inc.id),
          isTrue,
        );
        expect(
          h.view.tickets.any(
            (t) =>
                t.category == TicketCategory.safety &&
                t.subject.contains(inc.reference),
          ),
          isTrue,
        );
        final ack = await h.services.incidents.acknowledgeSos(
          by[SosRecipient.fleetManager]!.id,
        );
        expect(ack.isOk, isTrue);
        expect(
          h.view.incident(inc.id)!.status,
          IncidentStatus.acknowledgedDemo,
        );
        expect(
          h.view
              .notificationsFor(UserRole.employee, 'E1')
              .any((n) => n.title.contains('SOS acknowledged')),
          isTrue,
        );
        expect(
          (await h.services.incidents.acknowledgeSos(
            by[SosRecipient.police]!.id,
          )).isOk,
          isFalse,
        );
      },
    );
  });

  group('4 · Analytics & carbon credits', () {
    test(
      'savings computed from completed trips vs single-occupancy baseline',
      () async {
        final h = await Harness.create();
        final range = DateRange.lastDays(h.view.today, 7);
        final a = h.services.analytics.summary('C1', range);
        expect(
          a.trips.map((t) => t.trip.id),
          containsAll(['TR-0991', 'TR-0992', 'TR-0993', 'TR-0994']),
        );
        expect(
          a.estimatedDistanceTrips,
          1,
          reason: 'TR-0994 has no recorded distance',
        );
        expect(a.baselineCo2Kg, greaterThan(a.actualCo2Kg));
        expect(a.co2SavedKg, greaterThan(0));
        expect(a.creditTonnes, closeTo(a.co2SavedKg / 1000, 1e-9));
        expect(
          a.indicativeCreditValue,
          closeTo(
            a.creditTonnes * h.view.policy.carbonCreditPricePerTonne,
            1e-6,
          ),
        );
        // EV trip emits less than ICE trip per km.
        final ev = a.trips.firstWhere((t) => t.trip.id == 'TR-0991');
        final ice = a.trips.firstWhere((t) => t.trip.id == 'TR-0992');
        expect(
          ev.actualCo2Kg / ev.actualKm,
          lessThan(ice.actualCo2Kg / ice.actualKm),
        );
        expect(a.co2ByDay().length, 7);
      },
    );
  });

  group('5 · Dynamic booking & seat matching', () {
    test(
      'absence releases a seat; ad-hoc request is matched into an existing route',
      () async {
        final h = await Harness.create();
        final s = h.services;
        // Absence on today's not-started trip.
        final abs = await s.matching.reportAbsence(
          'TR-1001',
          'E2',
          'Working from home',
        );
        expect(abs.isOk, isTrue, reason: abs.message);
        final t = h.view.trips.byId('TR-1001')!;
        expect(t.employeeIds, isNot(contains('E2')));
        expect(t.absentEmployeeIds, contains('E2'));
        expect(h.view.booking('BK-1002')!.status, BookingStatus.cancelled);
        expect(
          h.view
              .notificationsFor(UserRole.driver, 'DR1')
              .any((n) => n.title.contains('not travelling')),
          isTrue,
        );
        expect(
          h.view.auditTrail.any((a) => a.action == 'trip.absence'),
          isTrue,
        );
        // Tomorrow: E1 alone in C3; E2 requests ad-hoc → matched into that trip.
        final base = await s.assignments.commit(
          AssignmentRequest(
            employerId: 'C1',
            serviceDate: tomorrow(h),
            employeeIds: const ['E1'],
            driverId: 'DR3',
            vehicleId: 'C3',
          ),
        );
        expect(base.isOk, isTrue, reason: base.message);
        final req = await s.bookings.submit(
          BookingDraft(
            employeeId: 'E2',
            pickupLocationId: 'PK02',
            destinationId: 'G2',
            date: tomorrow(h),
            arrivalMinutes: 540,
          ),
        );
        expect(req.isOk, isTrue, reason: req.message);
        final sugg = s.matching.suggestions(req.valueOrNull!.id);
        final best = sugg.firstWhere((m) => m.trip.id == base.valueOrNull!.id);
        expect(best.feasible, isTrue, reason: best.reasons.join());
        final m = await s.matching.matchBest(req.valueOrNull!.id);
        expect(m.isOk, isTrue, reason: m.message);
        expect(
          h.view.booking(req.valueOrNull!.id)!.status,
          BookingStatus.assigned,
        );
        expect(
          h.view.trips.byId(base.valueOrNull!.id)!.employeeIds,
          containsAll(['E1', 'E2']),
        );
        final u = s.matching.utilization(h.view.today);
        expect(u.released, 1);
      },
    );

    test(
      'auto-match policy matches on submit; infeasible requests stay open with honest reasons',
      () async {
        final h = await Harness.create();
        final s = h.services;
        await s.assignments.commit(
          AssignmentRequest(
            employerId: 'C1',
            serviceDate: tomorrow(h),
            employeeIds: const ['E1'],
            driverId: 'DR3',
            vehicleId: 'C3',
          ),
        );
        await s.policy.save(h.view.policy.copyWith(autoMatchAdhoc: true));
        final r = await s.matching.submitAdhoc(
          BookingDraft(
            employeeId: 'E2',
            pickupLocationId: 'PK02',
            destinationId: 'G2',
            date: tomorrow(h),
            arrivalMinutes: 540,
          ),
        );
        expect(r.isOk, isTrue);
        expect(
          r.valueOrNull!.status,
          BookingStatus.assigned,
          reason: r.message,
        );
        // TR-1006 tomorrow is full (6/6 in C2) → never offered as feasible.
        final far = await s.bookings.submit(
          BookingDraft(
            employeeId: 'E50',
            pickupLocationId: 'PK11',
            destinationId: 'G2',
            date: tomorrow(h),
            arrivalMinutes: 540,
          ),
        );
        final sugg = s.matching.suggestions(far.valueOrNull!.id);
        final full = sugg.where((m) => m.trip.id == 'TR-1006').single;
        expect(full.feasible, isFalse);
        expect(full.reasons.join(), contains('Over capacity'));
      },
    );

    test('absence after trip start is rejected', () async {
      final h = await Harness.create();
      final r = await h.services.matching.reportAbsence(
        'TR-1002',
        'E7',
        'Sick',
      );
      expect(r.isOk, isFalse);
      expect(r.errors.join(), contains('already started'));
    });
  });
}
