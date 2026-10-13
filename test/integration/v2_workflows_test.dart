import 'package:executive_fleet/domain/models/models.dart';
import 'package:executive_fleet/domain/rules/inspection_rules.dart';
import 'package:executive_fleet/domain/services/app_services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_harness.dart';

/// Cross-application workflows A–G from the v2 client-architecture prompt
/// (§15), plus the end-to-end smoke path (§18).
void main() {
  DateTime tomorrow(Harness h) => h.view.today.add(const Duration(days: 1));

  test(
    'A — employee preferences → optimization → applied assignment, consistent & audited',
    () async {
      final h = await Harness.create();
      final s = h.services;
      final pref = await s.employees.updateTravelPreferences('E2', {
        'travelTime': 3,
        'reliability': 3,
      });
      expect(pref.isOk, isTrue);
      // Employer Admin sees permitted employee settings.
      expect(h.view.employee('E2')!.travelPreferences['travelTime'], 3);
      final run = await s.optimization.runAndSave(
        s.optimization.buildInput(
          config: h.view.optimizationConfigs.first,
          employeeIds: const ['E1', 'E2', 'E3', 'E4'],
          serviceDate: tomorrow(h),
        ),
      );
      final r = run.valueOrNull!;
      expect(r.isFeasible, isTrue);
      expect(r.preferenceSummary.join(), contains('E2 prefers'));
      // Existing trips are not reassigned by the preference change.
      expect(h.view.trips.byId('TR-1001')!.assignedVehicleId, 'C1');
      final applied = await s.optimization.applyRun(r.id);
      expect(applied.isOk, isTrue, reason: applied.message);
      for (final t in applied.valueOrNull!) {
        expect(
          h.view.trips.forDriver(t.assignedDriverId!).any((x) => x.id == t.id),
          isTrue,
        ); // Driver
        for (final e in t.employeeIds) {
          expect(
            h.view.trips.forEmployee(e).any((x) => x.id == t.id),
            isTrue,
          ); // Employee
        }
        expect(t.employerId, 'C1'); // Employer assignments
      }
      final actions = h.view.auditTrail.map((a) => a.action).toSet();
      expect(
        actions,
        containsAll([
          'employee.travelPreferences',
          'optimization.run',
          'optimization.apply',
        ]),
      );
    },
  );

  test(
    'B — company registration → contract/allocation eligibility → valid assignment, audited',
    () async {
      final h = await Harness.create();
      final s = h.services;
      final base = h.view.primaryEmployer;
      final c9 = Employer.fromJson({
        ...base
            .copyWith(
              name: 'Northwind Demo Co (fictional)',
              maximumArrivalMinutes: 600,
              shifts: const [
                ShiftWindow(
                  id: 'N1',
                  label: 'Day',
                  startMinutes: 615,
                  endMinutes: 1155,
                ),
              ],
            )
            .toJson(),
        'id': 'C9',
        'code': 'C9',
      });
      expect((await s.employers.register(c9)).isOk, isTrue);
      expect(
        (await s.employers.register(c9)).errors.join(),
        contains('already exists'),
      );
      for (final (id, pk) in [('N1', 'PK06'), ('N2', 'PK10')]) {
        final e = Employee(
          id: id,
          employeeCode: id,
          employerId: 'C9',
          name: 'Northwind $id',
          fictionalEmail: '${id.toLowerCase()}@nw-demo.example',
          fictionalPhone: '+91 90000 99${id.substring(1)}',
          pickupLocationId: pk,
          destinationId: 'G4',
          requiredArrivalMinutes: 600,
          shiftLabel: 'Day',
          transportPreference: TransportPreference.noPreference,
          status: RecordStatus.active,
          optionalDemoPasswordEnabled: false,
          shiftStartMinutes: 615,
          shiftEndMinutes: 1155,
        );
        final r = await s.employees.save(e, isNew: true);
        expect(r.isOk, isTrue, reason: r.message);
      }
      expect(h.view.companyEmployeeCount('C9'), 2);
      expect(h.view.companyShiftCount('C9'), 1);
      // C3 is allocated to C1 05:00–22:00 → cannot also serve C9 in the morning.
      final clash = await s.allocations.save(
        FleetAllocation(
          id: 'x',
          employerId: 'C9',
          resourceType: ResourceType.vehicle,
          resourceId: 'C3',
          windowStartMinutes: 420,
          windowEndMinutes: 720,
          createdAt: h.clock.now(),
        ),
        isNew: true,
      );
      expect(clash.isOk, isFalse);
      // Add a new vehicle C4 + driver DR4 and allocate them to C9.
      final c4 = Vehicle.fromJson({
        ...h.view.vehicle('C3')!.toJson(),
        'id': 'C4',
        'vehicleCode': 'C4',
        'fictionalRegistration': 'DM-04-EV-4004',
        'rcNumber': 'DEMO-RC-4004',
        'engineNumber': 'EVM-0004-DEMO',
        'assignedDriverId': 'DR4',
        'status': 'available',
      });
      expect((await s.fleet.saveVehicle(c4, isNew: true)).isOk, isTrue);
      final dr4 = Driver.fromJson({
        ...h.view.driver('DR1')!.toJson(),
        'id': 'DR4',
        'driverCode': 'DR4',
        'name': 'Demo Driver Four',
        'licenceNumber': 'DL-DEMO-0004',
        'assignedVehicleId': 'C4',
        'status': 'available',
      });
      expect((await s.fleet.saveDriver(dr4, isNew: true)).isOk, isTrue);
      for (final (type, id) in [
        (ResourceType.vehicle, 'C4'),
        (ResourceType.driver, 'DR4'),
      ]) {
        final a = await s.allocations.save(
          FleetAllocation(
            id: 'x',
            employerId: 'C9',
            resourceType: type,
            resourceId: id,
            windowStartMinutes: 420,
            windowEndMinutes: 720,
            createdAt: h.clock.now(),
          ),
          isNew: true,
        );
        expect(a.isOk, isTrue, reason: a.message);
      }
      // C1's driver DR1 is not allocated to C9 → blocked; C4 + DR4 → accepted.
      final wrong = s.assignments.validate(
        AssignmentRequest(
          employerId: 'C9',
          serviceDate: tomorrow(h),
          employeeIds: const ['N1', 'N2'],
          driverId: 'DR1',
          vehicleId: 'C4',
        ),
      );
      expect(wrong.errors.join(), contains('DR1 is not allocated to C9'));
      final ok = await s.assignments.commit(
        AssignmentRequest(
          employerId: 'C9',
          serviceDate: tomorrow(h),
          employeeIds: const ['N1', 'N2'],
          driverId: 'DR4',
          vehicleId: 'C4',
        ),
      );
      expect(ok.isOk, isTrue, reason: ok.message);
      expect(h.view.trips.forDriver('DR4').single.employerId, 'C9');
      expect(
        h.view.auditTrail.any((a) => a.action == 'company.register'),
        isTrue,
      );
      expect(
        h.view.auditTrail.where((a) => a.action == 'allocation.create').length,
        2,
      );
    },
  );

  test(
    'C — contract constraints: permitted proceeds, hard limit blocks, expiry blocks',
    () async {
      final h = await Harness.create();
      final s = h.services;
      final ok = await s.assignments.commit(
        AssignmentRequest(
          employerId: 'C1',
          serviceDate: tomorrow(h),
          employeeIds: const ['E1', 'E2', 'E3'],
          driverId: 'DR1',
          vehicleId: 'C1',
        ),
      );
      expect(ok.isOk, isTrue, reason: ok.message);
      final contract = h.view.activeContract('C1', h.view.today)!;
      await s.contracts.save(contract.copyWith(agreedVehicleCount: 1));
      final blocked = await s.assignments.commit(
        AssignmentRequest(
          employerId: 'C1',
          serviceDate: tomorrow(h),
          employeeIds: const ['E4'],
          driverId: 'DR3',
          vehicleId: 'C3',
        ),
      );
      expect(blocked.isOk, isFalse);
      expect(blocked.errors.join(), contains('allows 1 car(s)'));
      await s.contracts.save(
        contract.copyWith(validUntil: h.view.today, agreedVehicleCount: 3),
      );
      final expired = s.assignments.validate(
        AssignmentRequest(
          employerId: 'C1',
          serviceDate: tomorrow(h),
          employeeIds: const ['E4'],
          driverId: 'DR3',
          vehicleId: 'C3',
        ),
      );
      expect(expired.errors.join(), contains('No active contract'));
      expect(h.view.auditFor('contract', contract.id).length, 2);
    },
  );

  test(
    'D — traffic movement: simulated change → revision → notifications → consistent views',
    () async {
      final h = await Harness.create();
      final s = h.services;
      final r = await s.traffic.setScenario(
        internalRoads: TrafficLevel.severe,
        ringRoad: TrafficLevel.heavy,
      );
      final revs = r.valueOrNull!;
      final rev = revs.firstWhere((x) => x.tripId == 'TR-1001');
      expect(
        h.view.openRevision('TR-1001')!.id,
        rev.id,
      ); // Fleet & Employer read the same record
      expect(
        h.view
            .notificationsFor(UserRole.driver, 'DR1')
            .any((n) => n.title.contains('Traffic alert')),
        isTrue,
      );
      await s.traffic.applyRevision(rev.id);
      final trip = h.view.trips.byId('TR-1001')!;
      expect(trip.scheduledStart, rev.proposedDeparture);
      final first = h.view.trips.stopsOf(trip).first;
      expect(
        first.plannedArrival,
        rev.stops.first.proposed,
      ); // Driver + Employee see new times
      expect(
        h.view.auditTrail.where((a) => a.simulated).map((a) => a.action),
        containsAll([
          'traffic.scenario',
          'route.revision.proposed',
          'route.revision.apply',
        ]),
      );
    },
  );

  test(
    'E — weekly billing: complete → eligible → cycle → no duplicate → exclusions',
    () async {
      final h = await Harness.create();
      final s = h.services;
      await s.driverOps.checkIn('DR1');
      await s.driverOps.submitInspection(
        driverId: 'DR1',
        vehicleId: 'C1',
        items: InspectionRules.blankChecklist(),
      );
      await s.driverOps.startTrip('TR-1001', 'DR1');
      const ver = VerificationService();
      for (final st in h.view.trips.stopsOf(h.view.trips.byId('TR-1001')!)) {
        await s.driverOps.arriveAtStop(st.id);
        final t = h.view.trips.byId('TR-1001')!;
        if (st.kind == StopKind.pickup) {
          for (final e in st.boardingEmployeeIds) {
            await s.driverOps.verifyAndBoard(
              stopId: st.id,
              method: VerificationMethod.qrDemo,
              input: ver.qrPayload(t, h.view.employee(e)!),
            );
          }
        } else {
          await s.driverOps.alight(
            stopId: st.id,
            employeeIds: st.alightingEmployeeIds,
          );
        }
        await s.driverOps.departStop(st.id);
      }
      final t = h.view.trips.byId('TR-1001')!;
      await s.driverOps.completeTrip(
        tripId: t.id,
        driverId: 'DR1',
        endOdometerKm: t.startOdometerKm! + 30,
      );
      final period = BillingPeriod.of(BillingCycle.weekly, h.view.today);
      final pv = s.billingCycles.preview('C1', period);
      expect(pv.eligible.any((l) => l.trip.id == 'TR-1001'), isTrue);
      expect(
        pv.excluded.where((l) => l.trip.id == 'TR-1002').single.exclusion,
        contains('Not completed'),
      );
      final inv = await s.billingCycles.runCycle('C1', period);
      expect(inv.isOk, isTrue, reason: inv.message);
      expect(inv.valueOrNull!.tripIds, contains('TR-1001'));
      expect(inv.valueOrNull!.total, closeTo(pv.total, 0.001));
      expect((await s.billingCycles.runCycle('C1', period)).isOk, isFalse);
      expect(
        h.view
            .invoicesOf('C1')
            .where((i) => i.periodStart == period.start)
            .length,
        1,
      );
      expect(
        h.view
            .notificationsFor(UserRole.employerAdmin)
            .any((n) => n.relatedEntityType == 'invoice'),
        isTrue,
      );
    },
  );

  test(
    'F — mapping & security guard: accepted with guard, rejected without / over capacity',
    () async {
      final h = await Harness.create();
      final s = h.services;
      final run = await s.optimization.runAndSave(
        s.optimization.buildInput(
          config: h.view.optimizationConfigs.first,
          employeeIds: const ['E1', 'E2', 'E3', 'E4'],
          serviceDate: tomorrow(h),
          guardRequired: true,
          guardsAvailable: 2,
        ),
      );
      final r = run.valueOrNull!;
      expect(r.isFeasible, isTrue, reason: r.hardConstraintViolations.join());
      for (final p in r.plans) {
        expect(p.guardSeats, 1);
        expect(p.employeeIds.length, lessThanOrEqualTo(p.totalSeats - 1 - 1));
        expect(p.guardSource, 'pool');
      }
      expect(
        (await s.optimization.applyRun(r.id)).errors.join(),
        contains('Name the security guard'),
      );
      final names = {
        for (final p in r.plans) p.vehicleId: 'GRD-${p.vehicleId} (demo)',
      };
      final applied = await s.optimization.applyRun(
        r.id,
        guardReferences: names,
      );
      expect(applied.isOk, isTrue, reason: applied.message);
      expect(
        applied.valueOrNull!.every(
          (t) => t.guardRequired && t.guardReference != null,
        ),
        isTrue,
      );
      // No guards available → infeasible with remedy.
      final none = s.optimization.preview(
        s.optimization.buildInput(
          config: h.view.optimizationConfigs.first,
          employeeIds: const ['E23'],
          serviceDate: tomorrow(h).add(const Duration(days: 1)),
          guardRequired: true,
          guardsAvailable: 0,
        ),
      );
      expect(none.isFeasible, isFalse);
      expect(none.remedies.join(), contains('guard'));
    },
  );

  test(
    'G — parking/depot start point used in route calculations; parking changes audited',
    () async {
      final h = await Harness.create();
      final s = h.services;
      final cfg = h.view.optimizationConfigs.first;
      final home = s.optimization.preview(
        s.optimization.buildInput(
          config: cfg,
          employeeIds: const ['E1'],
          serviceDate: tomorrow(h),
        ),
      );
      final p5 = s.optimization.preview(
        s.optimization.buildInput(
          config: cfg,
          employeeIds: const ['E1'],
          serviceDate: tomorrow(h),
          startParkingId: 'P5',
        ),
      );
      expect(p5.plans.single.startLocationId, 'P5');
      expect(home.plans.single.startLocationId, isNot('P5'));
      expect(p5.plans.single.deadheadKm, isNot(home.plans.single.deadheadKm));
      final loc = h.view.location('P5')!;
      final saved = await s.fleet.saveLocation(loc.copyWith(capacity: 12));
      expect(saved.isOk, isTrue);
      expect(
        h.view.auditFor('location', 'P5').first.changes,
        contains('capacity'),
      );
    },
  );

  test(
    'Smoke path: input → preference → optimize → map → drive (traffic) → complete → bill → audit',
    () async {
      final h = await Harness.create();
      final s = h.services;
      // Employee input (shift/tolerance) + preference.
      final e4 = h.view.employee('E4')!;
      expect(
        (await s.employees.save(
          e4.copyWith(pickupToleranceMinutes: () => 10),
        )).isOk,
        isTrue,
      );
      await s.employees.updateTravelPreferences('E4', {'reliability': 3});
      // Optimize & apply for today evening? Use today's free vehicles: none in the morning → use TR-1001 instead.
      // Traffic change before departure → apply revision.
      final rv = (await s.traffic.setScenario(
        internalRoads: TrafficLevel.heavy,
        ringRoad: TrafficLevel.free,
      )).valueOrNull!;
      final rev = rv.firstWhere((r) => r.tripId == 'TR-1001');
      await s.traffic.applyRevision(rev.id);
      // Driver day + completion.
      await s.driverOps.checkIn('DR1');
      await s.driverOps.submitInspection(
        driverId: 'DR1',
        vehicleId: 'C1',
        items: InspectionRules.blankChecklist(),
      );
      expect((await s.driverOps.startTrip('TR-1001', 'DR1')).isOk, isTrue);
      const ver = VerificationService();
      for (final st in h.view.trips.stopsOf(h.view.trips.byId('TR-1001')!)) {
        await s.driverOps.arriveAtStop(st.id);
        final t = h.view.trips.byId('TR-1001')!;
        if (st.kind == StopKind.pickup) {
          for (final e in st.boardingEmployeeIds) {
            await s.driverOps.verifyAndBoard(
              stopId: st.id,
              method: VerificationMethod.tpinDemo,
              input: ver.tpin(t, h.view.employee(e)!),
              employeeId: e,
            );
          }
        } else {
          await s.driverOps.alight(
            stopId: st.id,
            employeeIds: st.alightingEmployeeIds,
          );
        }
        await s.driverOps.departStop(st.id);
      }
      final t = h.view.trips.byId('TR-1001')!;
      expect(
        (await s.driverOps.completeTrip(
          tripId: t.id,
          driverId: 'DR1',
          endOdometerKm: t.startOdometerKm! + 27.5,
        )).isOk,
        isTrue,
      );
      // Optimization for tomorrow incl. E4 preference → apply.
      final run = (await s.optimization.runAndSave(
        s.optimization.buildInput(
          config: h.view.optimizationConfigs.first,
          employeeIds: const ['E4', 'E23'],
          serviceDate: tomorrow(h),
        ),
      )).valueOrNull!;
      expect(
        run.isFeasible,
        isTrue,
        reason: run.hardConstraintViolations.join(),
      );
      expect((await s.optimization.applyRun(run.id)).isOk, isTrue);
      // Billing cycle for the current week.
      final inv = await s.billingCycles.runCycle(
        'C1',
        BillingPeriod.of(BillingCycle.weekly, h.view.today),
      );
      expect(inv.isOk, isTrue, reason: inv.message);
      // Audit inspection.
      final actions = h.view.auditTrail.map((a) => a.action).toSet();
      expect(
        actions,
        containsAll([
          'employee.update',
          'employee.travelPreferences',
          'traffic.scenario',
          'route.revision.apply',
          'shift.checkIn',
          'inspection.submit',
          'trip.start',
          'passenger.board',
          'trip.complete',
          'billing.generate',
          'optimization.run',
          'optimization.apply',
          'billing.cycle',
        ]),
      );
    },
  );
}
