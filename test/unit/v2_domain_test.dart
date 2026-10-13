import 'dart:convert';
import 'package:executive_fleet/core/demo/clock.dart';

import 'package:executive_fleet/core/persistence/storage_adapter.dart';
import 'package:executive_fleet/data/seed/seed_data.dart';
import 'package:executive_fleet/domain/models/models.dart';
import 'package:executive_fleet/domain/rules/capacity_rules.dart';
import 'package:executive_fleet/domain/rules/inspection_rules.dart';
import 'package:executive_fleet/domain/services/app_services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_harness.dart';

DateTime tomorrow(Harness h) => h.view.today.add(const Duration(days: 1));

void main() {
  group('Seed & migration (schema v2)', () {
    test('v2 fixtures exist and baseline IDs are preserved', () async {
      final h = await Harness.create();
      final v = h.view;
      expect(v.employees.length, 100);
      expect(v.primaryEmployer.shifts.length, 4);
      expect(v.primaryEmployer.pickupToleranceMinutes, 7);
      expect(v.employee('E1')!.shiftStartMinutes, 555);
      expect(v.employee('E1')!.travelPreferences['travelTime'], 3);
      expect(v.employee('E3')!.pickupToleranceMinutes, 5);
      expect(v.location('P1')!.latitude, isNotNull);
      expect(v.location('P1')!.fleetOwned, isTrue);
      expect(v.vehicle('C1')!.rcNumber, 'DEMO-RC-1001');
      expect(v.driver('DR1')!.licenceNumber, 'DL-DEMO-0001');
      expect(v.contracts.length, 2);
      expect(v.allocations.length, 12);
      expect(v.traffic.normal, isTrue);
    });

    test(
      'v1 data migrates to v2 without losing records or user edits',
      () async {
        final h = await Harness.create();
        await h.services.employees.save(
          h.view.employee('E5')!.copyWith(name: 'Edited Five'),
        );
        await h.db.flush();
        // Downgrade the snapshot to a v1 shape.
        final raw = Map.of(h.storage.snapshot);
        for (final t in [
          'contracts',
          'fleet_allocations',
          'invoices',
          'route_revisions',
          'traffic_state',
        ]) {
          raw.remove(t);
        }
        List<Map<String, dynamic>> rows(String t) =>
            (jsonDecode(raw[t]!) as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
        final emps = rows('employees')
          ..forEach((e) {
            e.remove('shiftStartMinutes');
            e.remove('shiftEndMinutes');
            e.remove('travelPreferences');
            e.remove('pickupToleranceMinutes');
          });
        raw['employees'] = jsonEncode(emps);
        final locs = rows('locations')
          ..forEach((l) {
            l.remove('latitude');
            l.remove('longitude');
            l.remove('fleetOwned');
          });
        raw['locations'] = jsonEncode(locs);
        final emp = rows('employers')
          ..forEach((e) {
            e.remove('shifts');
          });
        raw['employers'] = jsonEncode(emp);
        final meta = Map<String, dynamic>.from(jsonDecode(raw['meta']!) as Map)
          ..['schemaVersion'] = 1;
        raw['meta'] = jsonEncode(meta);

        final h2 = await Harness.create(storage: MemoryStorageAdapter(raw));
        expect(h2.db.appliedMigrations, ['v1→v2', 'v2→v3']);
        expect(h2.db.schemaVersion, 3);
        expect(h2.db.fleetPolicies.length, 1);
        expect(h2.db.geofences.length, 3);
        expect(h2.view.employees.length, 100);
        expect(
          h2.view.employee('E5')!.name,
          'Edited Five',
          reason: 'user edit preserved',
        );
        expect(h2.view.employee('E1')!.shiftStartMinutes, 555);
        expect(h2.view.location('PK01')!.latitude, isNotNull);
        expect(h2.view.contracts.length, 2);
        expect(h2.view.allocations, isNotEmpty);
        expect(h2.view.primaryEmployer.shifts.length, 4);
        expect(h2.view.trips.byId('TR-1001'), isNotNull);
      },
    );
  });

  group('Employee input & preferences', () {
    test('shift, tolerance, company and location validation', () async {
      final h = await Harness.create();
      final s = h.services.employees;
      final e = h.view.employee('E1')!;
      expect(s.validate(e), isEmpty);
      expect(
        s
            .validate(
              e.copyWith(
                shiftStartMinutes: () => 600,
                shiftEndMinutes: () => 600,
              ),
            )
            .join(),
        contains('cannot be equal'),
      );
      expect(
        s
            .validate(
              e.copyWith(
                requiredArrivalMinutes: 570,
                shiftStartMinutes: () => 555,
              ),
            )
            .join(),
        contains('at or before the shift start'),
      );
      expect(
        s.validate(e.copyWith(pickupToleranceMinutes: () => 45)).join(),
        contains('Tolerance'),
      );
      expect(
        s.validate(e.copyWith(pickupLocationId: 'G1')).join(),
        contains('Source must be a pickup point'),
      );
      expect(
        s.validate(e.copyWith(destinationId: 'PK02')).join(),
        contains('Destination must be'),
      );
      // Overnight shift (22:00 → 06:00) is valid.
      final night = e.copyWith(
        requiredArrivalMinutes: 1305,
        shiftStartMinutes: () => 1320,
        shiftEndMinutes: () => 360,
      );
      expect(
        s
            .validate(night)
            .where((m) => m.contains('Shift') || m.contains('shift')),
        isEmpty,
      );
      expect(night.overnightShift, isTrue);
      final unknown = Employee(
        id: 'X1',
        employeeCode: 'X1',
        employerId: 'NOPE',
        name: 'Test',
        fictionalEmail: '',
        fictionalPhone: '',
        pickupLocationId: 'PK01',
        destinationId: 'G1',
        requiredArrivalMinutes: 540,
        shiftLabel: '',
        transportPreference: TransportPreference.noPreference,
        status: RecordStatus.active,
        optionalDemoPasswordEnabled: false,
      );
      expect(
        s.validate(unknown, isNew: true).join(),
        contains('Unknown company'),
      );
    });

    test(
      'travel preferences persist, are audited and change the optimizer score',
      () async {
        final h = await Harness.create();
        final opt = h.services.optimization;
        final cfg = h.view.optimizationConfigs.first;
        // Clear E1–E4 preferences first.
        for (final id in ['E1', 'E2', 'E3', 'E4']) {
          await h.services.employees.updateTravelPreferences(id, {});
        }
        final base = opt.preview(
          opt.buildInput(
            config: cfg,
            employeeIds: const ['E1', 'E2', 'E3', 'E4'],
            serviceDate: tomorrow(h),
          ),
        );
        final noPref = base.scoreBreakdown.firstWhere(
          (c) => c.key == 'employeePreference',
        );
        expect(noPref.normalizedPenalty, 0);
        final r = await h.services.employees.updateTravelPreferences('E1', {
          'travelTime': 3,
          'detour': 3,
        });
        expect(r.isOk, isTrue);
        final h2 = await h.restart();
        expect(h2.view.employee('E1')!.travelPreferences, {
          'travelTime': 3,
          'detour': 3,
        });
        expect(
          h2.view
              .auditFor('employee', 'E1')
              .any((a) => a.action == 'employee.travelPreferences'),
          isTrue,
        );
        final withPref = h2.services.optimization.preview(
          h2.services.optimization.buildInput(
            config: cfg,
            employeeIds: const ['E1', 'E2', 'E3', 'E4'],
            serviceDate: tomorrow(h2),
          ),
        );
        expect(
          withPref.scoreBreakdown
              .firstWhere((c) => c.key == 'employeePreference')
              .normalizedPenalty,
          greaterThan(0),
        );
        expect(withPref.preferenceSummary.join(), contains('E1 prefers'));
        expect(withPref.preferenceSummary.join(), contains('never override'));
      },
    );

    test('preferences never override hard constraints', () async {
      final h = await Harness.create();
      await h.services.employees.updateTravelPreferences('E1', {
        'travelTime': 3,
        'distance': 3,
        'detour': 3,
        'reliability': 3,
      });
      final opt = h.services.optimization;
      final sedanOnly = h.view.optimizationConfigs.first.copyWith(
        allowedVehicleTypes: const [VehicleType.sedan],
        employeePreferenceWeight: 10,
      );
      final run = opt.preview(
        opt.buildInput(
          config: sedanOnly,
          employeeIds: const ['E1', 'E2', 'E3', 'E4'],
          serviceDate: tomorrow(h),
        ),
      );
      expect(run.isFeasible, isFalse);
      expect(run.remedies, isNotEmpty);
      expect(run.constraintsEvaluated.length, greaterThanOrEqualTo(10));
    });
  });

  group('Mapping, guard & assignment rules', () {
    test(
      'guard seat reduces capacity and a missing guard blocks assignment',
      () async {
        final h = await Harness.create();
        expect(
          CapacityRules.passengerCapacity(
            h.view.vehicle('C3')!,
            guardRequired: true,
          ),
          4,
        );
        AssignmentRequest req({
          String? guard,
          List<String> emps = const ['E1', 'E2'],
        }) => AssignmentRequest(
          employerId: 'C1',
          serviceDate: tomorrow(h),
          employeeIds: emps,
          driverId: 'DR3',
          vehicleId: 'C3',
          guardRequired: true,
          guardReference: guard,
        );
        expect(
          h.services.assignments.validate(req()).errors.join(),
          contains('Security guard required'),
        );
        expect(
          h.services.assignments.validate(req(guard: 'GRD-07 (demo)')).errors,
          isEmpty,
        );
        final tooMany = h.services.assignments.validate(
          req(guard: 'GRD-07', emps: const ['E1', 'E2', 'E3', 'E4', 'E23']),
        );
        expect(tooMany.errors.join(), contains('Over capacity'));
        final ok = await h.services.assignments.commit(
          req(guard: 'GRD-07 (demo)'),
        );
        expect(ok.isOk, isTrue, reason: ok.message);
        expect(ok.valueOrNull!.guardReference, 'GRD-07 (demo)');
      },
    );

    test(
      'expired licence, inactive vehicle and duplicate employee are rejected',
      () async {
        final h = await Harness.create();
        await h.services.fleet.saveDriver(
          h.view
              .driver('DR3')!
              .copyWith(
                licenceExpiry: () =>
                    h.view.today.subtract(const Duration(days: 1)),
              ),
        );
        final v = h.services.assignments.validate(
          AssignmentRequest(
            employerId: 'C1',
            serviceDate: tomorrow(h),
            employeeIds: const ['E1', 'E1'],
            driverId: 'DR3',
            vehicleId: 'C3',
          ),
        );
        expect(v.errors.join(), contains('licence expired'));
        // Inactive vehicle cannot be assigned.
        final c4 = h.view
            .vehicle('C3')!
            .copyWith(
              fictionalRegistration: 'DM-04-EV-4004',
              rcNumber: 'RC-4',
              engineNumber: 'EN-4',
              active: false,
            );
        final c4v = Vehicle.fromJson({
          ...c4.toJson(),
          'id': 'C4',
          'vehicleCode': 'C4',
          'assignedDriverId': null,
          'status': 'available',
        });
        expect(
          (await h.services.fleet.saveVehicle(c4v, isNew: true)).isOk,
          isTrue,
        );
        final v2 = h.services.assignments.validate(
          AssignmentRequest(
            employerId: 'C1',
            serviceDate: tomorrow(h),
            employeeIds: const ['E30'],
            driverId: 'DR1',
            vehicleId: 'C4',
          ),
        );
        expect(v2.errors.join(), contains('deactivated'));
      },
    );

    test('rejected assignment is recorded in the audit trail', () async {
      final h = await Harness.create();
      final r = await h.services.assignments.commit(
        AssignmentRequest(
          employerId: 'C1',
          serviceDate: tomorrow(h),
          employeeIds: const ['E1', 'E2', 'E3', 'E4'],
          driverId: 'DR1',
          vehicleId: 'C1',
        ),
      );
      expect(r.isOk, isFalse);
      final last = h.view.auditTrail.first;
      expect(last.outcome, AuditOutcome.rejected);
      expect(last.reason, contains('Over capacity'));
    });
  });

  group('Fleet-company allocations & contracts', () {
    test(
      'allocation windows are enforced and cross-company overlaps detected',
      () async {
        final h = await Harness.create();
        // C1 allocations cover 05:00–22:00; a 23:00 trip is outside.
        final late = h.services.assignments.validate(
          AssignmentRequest(
            employerId: 'C1',
            serviceDate: tomorrow(h),
            employeeIds: const ['E30'],
            driverId: 'DR1',
            vehicleId: 'C1',
            scheduledStart: tomorrow(
              h,
            ).add(const Duration(hours: 22, minutes: 30)),
          ),
        );
        expect(late.errors.join(), contains('not allocated to C1'));
        // Register a second company and try to allocate C1 in an overlapping window.
        final c9 = h.view.primaryEmployer.copyWith(
          name: 'Northwind Demo Co (fictional)',
          shifts: const [],
        );
        final reg = await h.services.employers.register(
          Employer.fromJson({...c9.toJson(), 'id': 'C9', 'code': 'C9'}),
        );
        expect(reg.isOk, isTrue, reason: reg.message);
        final clash = await h.services.allocations.save(
          FleetAllocation(
            id: 'tmp',
            employerId: 'C9',
            resourceType: ResourceType.vehicle,
            resourceId: 'C1',
            windowStartMinutes: 420,
            windowEndMinutes: 600,
            createdAt: h.clock.now(),
          ),
          isNew: true,
        );
        expect(clash.isOk, isFalse);
        expect(clash.errors.join(), contains('already allocated to C1'));
        final night = await h.services.allocations.save(
          FleetAllocation(
            id: 'tmp',
            employerId: 'C9',
            resourceType: ResourceType.vehicle,
            resourceId: 'C1',
            windowStartMinutes: 1330,
            windowEndMinutes: 240,
            createdAt: h.clock.now(),
          ),
          isNew: true,
        );
        expect(night.isOk, isTrue, reason: night.message);
        expect(
          h.view.auditTrail.any((a) => a.action == 'allocation.create'),
          isTrue,
        );
      },
    );

    test('contract validity and hard/soft car limits', () async {
      final h = await Harness.create();
      final c = h.view.activeContract('C1', h.view.today)!;
      expect(c.contractCode, 'CT-2026-01');
      expect(
        h.view.contract('CT-0901')!.validityOn(h.view.today),
        ContractValidity.expired,
      );
      // Hard limit 3: a 4th distinct vehicle on a day already using 3 is blocked.
      final c4 = Vehicle.fromJson({
        ...h.view.vehicle('C3')!.toJson(),
        'id': 'C4',
        'vehicleCode': 'C4',
        'fictionalRegistration': 'DM-04',
        'rcNumber': 'RC-4',
        'engineNumber': 'EN-4',
        'assignedDriverId': null,
        'status': 'available',
      });
      await h.services.fleet.saveVehicle(c4, isNew: true);
      await h.services.allocations.save(
        FleetAllocation(
          id: 'x',
          employerId: 'C1',
          resourceType: ResourceType.vehicle,
          resourceId: 'C4',
          windowStartMinutes: 300,
          windowEndMinutes: 1320,
          createdAt: h.clock.now(),
        ),
        isNew: true,
      );
      final today = h.view.today;
      final req = AssignmentRequest(
        employerId: 'C1',
        serviceDate: today,
        employeeIds: const ['E30'],
        driverId: 'DR1',
        vehicleId: 'C4',
        scheduledStart: today.add(const Duration(hours: 15)),
      );
      expect(
        h.services.assignments.validate(req).errors.join(),
        contains('allows 3 car(s)'),
      );
      await h.services.contracts.save(c.copyWith(hardVehicleLimit: false));
      final soft = h.services.assignments.validate(req);
      expect(soft.errors.where((e) => e.contains('car(s)')), isEmpty);
      expect(soft.warnings.join(), contains('Soft limit'));
      // Suspended contract → no active contract.
      await h.services.contracts.setStatus(
        c.id,
        ContractStatus.suspended,
        reason: 'Payment review (demo)',
      );
      expect(
        h.services.assignments.validate(req).errors.join(),
        contains('No active contract'),
      );
      expect(h.view.auditFor('contract', c.id).length, greaterThanOrEqualTo(2));
    });

    test('contract validation: dates, unique IDs', () async {
      final h = await Harness.create();
      final c = h.view.contracts.first;
      final bad = Contract.fromJson({
        ...c.toJson(),
        'id': 'CT-9',
        'validUntil': c.validFrom
            .subtract(const Duration(days: 1))
            .toIso8601String(),
      });
      expect(
        h.services.contracts.validate(bad, isNew: true).join(),
        contains('cannot be earlier'),
      );
      expect(
        h.services.contracts
            .validate(
              Contract.fromJson({...c.toJson(), 'id': 'CT-9'}),
              isNew: true,
            )
            .join(),
        contains('already exists'),
      );
    });
  });

  group('Company, vehicle, driver, parking metadata', () {
    test('company counts are derived from records', () async {
      final h = await Harness.create();
      expect(h.view.companyEmployeeCount('C1'), 98);
      expect(h.view.companyShiftCount('C1'), 4);
      expect(h.view.companyLocationCount('C1'), 16);
      await h.services.employees.setActive('E5', false);
      expect(h.view.companyEmployeeCount('C1'), 97);
      // Deactivating a company with upcoming trips is blocked (history safe).
      expect(
        (await h.services.employers.setActive(
          'C1',
          false,
          reason: 'Demo check',
        )).isOk,
        isFalse,
      );
    });

    test(
      'vehicle and driver uniqueness, parking capacity and coordinates',
      () async {
        final h = await Harness.create();
        final c2 = h.view.vehicle('C2')!;
        expect(
          h.services.fleet
              .validateVehicle(
                c2.copyWith(fictionalRegistration: 'DM-01-EV-1001'),
              )
              .join(),
          contains('already used'),
        );
        expect(
          h.services.fleet
              .validateVehicle(c2.copyWith(rcNumber: 'DEMO-RC-1001'))
              .join(),
          contains('RC number'),
        );
        expect(
          h.services.fleet
              .validateDriver(
                h.view.driver('DR2')!.copyWith(licenceNumber: 'DL-DEMO-0001'),
              )
              .join(),
          contains('already used'),
        );
        expect(
          h.services.fleet
              .validateDriver(h.view.driver('DR2')!.copyWith(licenceNumber: ''))
              .join(),
          contains('Licence number'),
        );
        final p1 = h.view.location('P1')!;
        expect(
          h.services.fleet.validateLocation(p1.copyWith(capacity: 0)).join(),
          contains('at least 1'),
        );
        final p2 = h.view.location('P2')!;
        expect(h.view.parkedVehicles('P2'), 1);
        // Fictional lat/lng are converted to the routing plane on save.
        final r = await h.services.fleet.saveLocation(
          p2.copyWith(latitude: () => 12.95, longitude: () => 77.60),
        );
        expect(r.isOk, isTrue, reason: r.message);
        expect(h.view.location('P2')!.demoY, closeTo(11.06, 0.1));
        final badLat = await h.services.fleet.saveLocation(
          p2.copyWith(latitude: () => 95),
        );
        expect(badLat.isOk, isFalse);
      },
    );
  });

  group('Billing cycles', () {
    test(
      'weekly and monthly boundaries (local dates, Feb and year change)',
      () {
        final w = BillingPeriod.of(
          BillingCycle.weekly,
          DateTime(2026, 10, 14, 23, 59),
        );
        expect(w.start, DateTime(2026, 10, 12));
        expect(w.end, DateTime(2026, 10, 18));
        expect(w.nextBoundary, DateTime(2026, 10, 19));
        final ye = BillingPeriod.of(
          BillingCycle.weekly,
          DateTime(2026, 12, 31),
        );
        expect(ye.start, DateTime(2026, 12, 28));
        expect(ye.end, DateTime(2027, 1, 3));
        final feb = BillingPeriod.of(
          BillingCycle.monthly,
          DateTime(2028, 2, 10),
        );
        expect(feb.end, DateTime(2028, 2, 29));
        expect(
          BillingPeriod.of(BillingCycle.monthly, DateTime(2027, 2, 1)).end,
          DateTime(2027, 2, 28),
        );
        expect(
          BillingPeriod.of(
            BillingCycle.monthly,
            DateTime(2026, 12, 15),
          ).next.start,
          DateTime(2027, 1, 1),
        );
      },
    );

    test(
      'cycle invoices eligible lines once; exclusions explained; rate change does not rewrite',
      () async {
        final h = await Harness.create();
        final svc = h.services.billingCycles;
        final period = BillingPeriod.of(
          BillingCycle.monthly,
          h.view.today.subtract(const Duration(days: 1)),
        );
        final pv = svc.preview('C1', period);
        final eligibleTrips = pv.eligible.map((l) => l.trip.id).toSet();
        expect(eligibleTrips, containsAll(['TR-0991', 'TR-0992', 'TR-0993']));
        expect(pv.excluded.map((l) => l.trip.id), contains('TR-1005'));
        expect(
          pv.excluded.firstWhere((l) => l.trip.id == 'TR-1005').exclusion,
          contains('Cancelled'),
        );
        final expected = pv.total;
        final r = await svc.runCycle('C1', period);
        expect(r.isOk, isTrue, reason: r.message);
        final inv = r.valueOrNull!;
        expect(inv.total, closeTo(expected, 0.001));
        expect(inv.tripIds.toSet(), eligibleTrips);
        expect(h.view.billingForTrip('TR-0991')!.invoiceId, inv.id);
        // Idempotent.
        final again = await svc.runCycle('C1', period);
        expect(again.isOk, isFalse);
        expect(again.errors.join(), contains('No duplicate'));
        expect(h.view.invoicesOf('C1').length, 1);
        // Rate change does not change the generated invoice.
        await h.services.employers.update(
          h.view.primaryEmployer.copyWith(defaultDistanceRate: 25),
        );
        expect(h.view.invoice(inv.id)!.total, closeTo(expected, 0.001));
        // Missing distance trip becomes eligible only after recording distance → supplementary invoice.
        final p2 = BillingPeriod.of(
          BillingCycle.monthly,
          h.view.trips.byId('TR-0994')!.actualArrival!,
        );
        if (p2 == period) {
          await h.services.billing.recordDistanceAndBill(
            'TR-0994',
            20,
            'From trip log (demo)',
          );
          final sup = await svc.runCycle('C1', period);
          expect(sup.isOk, isTrue, reason: sup.message);
          expect(sup.valueOrNull!.sequence, 2);
          expect(sup.valueOrNull!.tripIds, ['TR-0994']);
        }
        expect(
          h.view.auditTrail.any(
            (a) =>
                a.action == 'billing.cycle' &&
                a.outcome == AuditOutcome.success,
          ),
          isTrue,
        );
        expect(
          h.view.auditTrail.any(
            (a) =>
                a.action == 'billing.cycle' &&
                a.outcome == AuditOutcome.rejected,
          ),
          isTrue,
        );
        // Invoice status flow.
        expect(
          (await svc.setStatus(inv.id, InvoiceStatus.paidDemo)).isOk,
          isFalse,
        );
        expect(
          (await svc.setStatus(inv.id, InvoiceStatus.reviewed)).isOk,
          isTrue,
        );
        expect(
          (await svc.setStatus(inv.id, InvoiceStatus.paidDemo)).isOk,
          isTrue,
        );
      },
    );

    test('paused billing blocks the cycle; due cycles are reported', () async {
      final h = await Harness.create(now: DateTime(2026, 11, 3, 9));
      final svc = h.services.billingCycles;
      final prevMonth = BillingPeriod.of(
        BillingCycle.monthly,
        DateTime(2026, 11, 2),
      );
      await h.services.employers.update(
        h.view.primaryEmployer.copyWith(billingCycle: BillingCycle.monthly),
      );
      final due = svc.dueCycles('C1');
      expect(
        due,
        isEmpty,
        reason: 'seed trips are in the current month at anchor',
      );
      await h.services.employers.update(
        h.view.primaryEmployer.copyWith(billingActive: false),
      );
      expect(
        (await svc.runCycle('C1', prevMonth)).errors.join(),
        contains('paused'),
      );
    });
  });

  group('Traffic & route revisions', () {
    test(
      'scenario change proposes revisions, dedupes alerts, applies safely',
      () async {
        final h = await Harness.create();
        final t = h.services.traffic;
        final before = h.db.notifications.length;
        final r = await t.setScenario(
          internalRoads: TrafficLevel.heavy,
          ringRoad: TrafficLevel.moderate,
        );
        expect(r.isOk, isTrue);
        final revs = r.valueOrNull!;
        expect(revs, isNotEmpty);
        final rev1001 = revs.firstWhere((x) => x.tripId == 'TR-1001');
        expect(
          rev1001.proposedDeparture.isBefore(
            h.view.trips.byId('TR-1001')!.scheduledStart,
          ),
          isTrue,
        );
        expect(rev1001.simulated, isTrue);
        final afterFirst = h.db.notifications.length;
        expect(afterFirst, greaterThan(before));
        // Same condition again → no new revisions or notifications.
        final again = await t.setScenario(
          internalRoads: TrafficLevel.heavy,
          ringRoad: TrafficLevel.moderate,
        );
        expect(again.valueOrNull, isEmpty);
        expect(h.db.notifications.length, afterFirst + 0);
        // Apply on an in-progress trip never changes completed stops.
        final rev1002 = revs.where((x) => x.tripId == 'TR-1002').firstOrNull;
        if (rev1002 != null) {
          final trip = h.view.trips.byId('TR-1002')!;
          final done = h.view.trips
              .stopsOf(trip)
              .where((s) => s.isDone)
              .map((s) => (s.id, s.plannedArrival))
              .toList();
          expect((await t.applyRevision(rev1002.id)).isOk, isTrue);
          for (final (id, planned) in done) {
            expect(h.db.routeStops[id]!.plannedArrival, planned);
          }
        }
        expect((await t.applyRevision(rev1001.id)).isOk, isTrue);
        expect(
          h.view.trips.byId('TR-1001')!.scheduledStart,
          rev1001.proposedDeparture,
        );
        expect(
          h.view
              .notificationsFor(UserRole.employee, 'E1')
              .any((n) => n.title.contains('Pickup time changed')),
          isTrue,
        );
        expect(
          h.view.auditTrail.any(
            (a) => a.action == 'route.revision.apply' && a.simulated,
          ),
          isTrue,
        );
      },
    );

    test('unavailable traffic produces no recalculation', () async {
      final h = await Harness.create();
      final r = await h.services.traffic.setScenario(
        internalRoads: TrafficLevel.severe,
        ringRoad: TrafficLevel.severe,
        source: TrafficSource.unavailable,
      );
      expect(r.valueOrNull, isEmpty);
      expect(h.services.traffic.board().every((s) => !s.available), isTrue);
    });
  });

  group('Audit', () {
    test('audit never contains secrets and persists across restart', () async {
      final h = await Harness.create();
      await h.services.driverOps.checkIn('DR1');
      await h.services.driverOps.submitInspection(
        driverId: 'DR1',
        vehicleId: 'C1',
        items: InspectionRules.blankChecklist(),
      );
      await h.services.driverOps.startTrip('TR-1001', 'DR1');
      final trip = h.view.trips.byId('TR-1001')!;
      final stop = h.view.trips.stopsOf(trip).first;
      await h.services.driverOps.arriveAtStop(stop.id);
      const ver = VerificationService();
      final e = h.view.employee(stop.boardingEmployeeIds.first)!;
      await h.services.driverOps.verifyAndBoard(
        stopId: stop.id,
        method: VerificationMethod.tpinDemo,
        input: ver.tpin(trip, e),
        employeeId: e.id,
      );
      final all = h.db.audit.values.map((a) => jsonEncode(a.toJson())).join();
      expect(all.contains(ver.tpin(trip, e)), isFalse);
      expect(all.contains(ver.qrPayload(trip, e)), isFalse);
      expect(all.contains(demoEmployeePassword), isFalse);
      final count = h.db.audit.length;
      final h2 = await h.restart();
      expect(h2.db.audit.length, count);
    });

    test('demo reset is audited', () async {
      final h = await Harness.create();
      await h.services.seed.reset();
      expect(h.view.auditTrail.first.action, 'demo.reset');
    });
  });

  test(
    'traffic: earlier departure does not overshoot; delay is for leaving as planned',
    () async {
      final h = await Harness.create();
      await h.services.traffic.setScenario(
        internalRoads: TrafficLevel.heavy,
        ringRoad: TrafficLevel.heavy,
      );
      final s = h.services.traffic.statusOf(h.view.trips.byId('TR-1001')!);
      expect(s.delayMinutes, greaterThanOrEqualTo(0));
      expect(s.earlierDepartureMinutes, greaterThan(0));
      // Tightest drop lands close to (not an hour before) its deadline − buffer.
      final trip = h.view.trips.byId('TR-1001')!;
      var minSlack = 1 << 30;
      for (final st in s.stops.where((x) => x.kind == StopKind.drop)) {
        var m = 1439;
        for (final e in st.alightingEmployeeIds) {
          final d = h.view.employee(e)!.arrivalDeadlineMinutes;
          if (d < m) m = d;
        }
        final deadline = atMinutes(
          trip.serviceDate,
          m,
        ).subtract(const Duration(minutes: 10));
        final slack = deadline.difference(s.proposedTimes[st.id]!).inMinutes;
        if (slack < minSlack) minSlack = slack;
      }
      expect(minSlack, inInclusiveRange(0, 15));
    },
  );
}
