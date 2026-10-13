import 'package:executive_fleet/domain/models/models.dart';
import 'package:executive_fleet/domain/rules/parameter_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_harness.dart';

void main() {
  group('Optimization', () {
    test(
      'deterministic, explainable, respects deadlines and capacity',
      () async {
        final h = await Harness.create();
        final opt = h.services.optimization;
        final config = h.view.optimizationConfigs.first;
        final input = opt.buildInput(
          config: config,
          employeeIds: const ['E1', 'E2', 'E3', 'E4'],
          serviceDate: h.view.today.add(const Duration(days: 1)),
        );
        final a = opt.preview(input);
        final b = opt.preview(input);
        expect(a.isFeasible, isTrue, reason: a.hardConstraintViolations.join());
        expect(
          a.toJson()..remove('createdAt'),
          b.toJson()..remove('createdAt'),
        );
        expect(a.plans.expand((p) => p.employeeIds).toSet(), {
          'E1',
          'E2',
          'E3',
          'E4',
        });
        for (final p in a.plans) {
          expect(p.employeeIds.length, lessThanOrEqualTo(p.passengerCapacity));
          for (final eid in p.employeeIds) {
            final drop = p.stops
                .firstWhere(
                  (s) => s.kind == StopKind.drop && s.employeeIds.contains(eid),
                )
                .plannedArrival;
            final e = h.view.employee(eid)!;
            expect(
              drop.isAfter(
                DateTime(
                  drop.year,
                  drop.month,
                  drop.day,
                ).add(Duration(minutes: e.requiredArrivalMinutes)),
              ),
              isFalse,
            );
          }
        }
        expect(a.score, inInclusiveRange(0, 100));
        expect(a.scoreBreakdown.length, 12);
        expect(a.explanation.first, contains('not nearest-path'));
        expect(a.isSimulation, isTrue);
      },
    );

    test('hard constraint failure yields no feasible route', () async {
      final h = await Harness.create();
      final opt = h.services.optimization;
      final sedanOnly = h.view.optimizationConfigs.first.copyWith(
        allowedVehicleTypes: const [VehicleType.sedan],
      );
      final run = opt.preview(
        opt.buildInput(
          config: sedanOnly,
          employeeIds: const ['E1', 'E2', 'E3', 'E4'],
          serviceDate: h.view.today.add(const Duration(days: 1)),
        ),
      );
      expect(run.status, OptimizationRunStatus.noFeasibleSolution);
      expect(run.plans, isEmpty);
      expect(run.hardConstraintViolations.join(), contains('Capacity'));
    });

    test('EV preference never overrides hard constraints', () async {
      final h = await Harness.create();
      final opt = h.services.optimization;
      // Only ICE van allowed: feasible but EV target warning.
      final iceOnly = h.view.optimizationConfigs.first.copyWith(
        allowedVehicleTypes: const [VehicleType.van],
        evPreferenceWeight: 10,
      );
      final run = opt.preview(
        opt.buildInput(
          config: iceOnly,
          employeeIds: const ['E30'],
          serviceDate: h.view.today.add(const Duration(days: 2)),
        ),
      );
      expect(
        run.isFeasible,
        isTrue,
        reason: run.hardConstraintViolations.join(),
      );
      expect(run.evAllocationPercentage, 0);
      expect(run.warnings.join(), contains('EV target'));
    });

    test('apply creates trips once after a saved run', () async {
      final h = await Harness.create();
      final opt = h.services.optimization;
      final saved = await opt.runAndSave(
        opt.buildInput(
          config: h.view.optimizationConfigs.first,
          employeeIds: const ['E1', 'E2', 'E3', 'E4'],
          serviceDate: h.view.today.add(const Duration(days: 1)),
        ),
      );
      expect(saved.isOk, isTrue);
      final applied = await opt.applyRun(saved.valueOrNull!.id);
      expect(applied.isOk, isTrue, reason: applied.message);
      final trips = applied.valueOrNull!;
      expect(
        trips.every(
          (t) =>
              t.status == TripStatus.assigned &&
              t.optimizationRunId == saved.valueOrNull!.id,
        ),
        isTrue,
      );
      expect(
        h.view
            .notificationsFor(UserRole.employee, 'E4')
            .any((n) => n.title.contains('assigned')),
        isTrue,
      );
      expect((await opt.applyRun(saved.valueOrNull!.id)).isOk, isFalse);
      // BK-1004 (E4, tomorrow) was fulfilled by the applied plan.
      expect(h.view.booking('BK-1004')!.status, BookingStatus.assigned);
    });

    test('EV target vs actual is calculated with explanation', () async {
      final h = await Harness.create();
      final a = h.services.optimization.evTarget('C1', h.view.today);
      expect(a.targetPct, 50);
      // Today: TR-1001 C1(EV), TR-1002 C2(ICE), TR-1003 C3(EV) → 2/3.
      expect(a.totalTrips, 3);
      expect(a.evTrips, 2);
      expect(a.actualPct, closeTo(66.7, 0.1));
      expect(a.feasible, isTrue);
      expect(a.explanation, isNotEmpty);
    });

    test('pooling never forces incompatible employees together', () async {
      final h = await Harness.create();
      final config = h.view.optimizationConfigs.first;
      final res = h.services.optimization.suggestPools(
        const ['E1', 'E2', 'E3', 'E4', 'E1'],
        config,
        h.view.today.add(const Duration(days: 1)),
      );
      for (final g in res.groups) {
        for (final a in g.employees) {
          for (final b in g.employees) {
            if (a.id != b.id) {
              expect(
                h.services.optimization.checkPair(a, b, config).feasible,
                isTrue,
              );
            }
          }
        }
      }
      final pair = h.services.optimization.checkPair(
        h.view.employee('E3')!,
        h.view.employee('E4')!,
        config,
      );
      expect(pair.reasons, isNotEmpty);
    });

    test(
      'parameter catalog has 100+ definitions with a labelled live subset',
      () {
        expect(ParameterCatalog.count, greaterThanOrEqualTo(100));
        expect(ParameterCatalog.liveCount, lessThan(ParameterCatalog.count));
        expect(
          ParameterCatalog.all.map((p) => p.key).toSet().length,
          ParameterCatalog.count,
        );
        for (final p in ParameterCatalog.all) {
          expect(p.min <= p.max, isTrue, reason: p.key);
          expect(p.description, isNotEmpty);
          expect(p.unit, isNotEmpty);
          if (!p.usedByDemoOptimizer) {
            expect(p.dataSource, isNot('Local demo records'));
          }
        }
        expect(ParameterCategory.values.length, greaterThanOrEqualTo(12));
      },
    );
  });

  group('Roster CSV import', () {
    test(
      'row validation: duplicates, invalid time, unknown pickup, existing ID',
      () async {
        final h = await Harness.create();
        const csv =
            'employee_code,name,email,phone,pickup_code,destination_code,arrival_time,shift,transport_preference\n'
            'E201,Valid Person,e201@x.example,1,PK01,G1,09:00,,evPreferred\n'
            'E201,Duplicate Row,,,PK01,G1,09:00,,\n'
            'E202,Bad Time,,,PK01,G1,25:99,,\n'
            'E203,Unknown Pickup,,,ZZ9,G1,09:00,,\n'
            'E204,Too Late,,,PK02,G2,10:15,,\n'
            'E1,Existing,,,PK01,G1,09:00,,\n'
            ',No Code,,,PK01,G1,09:00,,\n';
        final p = h.services.roster.preview(csv, employerId: 'C1');
        expect(p.fileErrors, isEmpty);
        expect(p.rows.length, 7);
        expect(p.rows[0].valid, isTrue);
        expect(p.rows[1].errors.join(), contains('Duplicate'));
        expect(p.rows[2].errors.join(), contains('Invalid time'));
        expect(p.rows[3].errors.join(), contains('Unknown pickup'));
        expect(p.rows[4].errors.join(), contains('maximum'));
        expect(p.rows[5].errors.join(), contains('already exists'));
        expect(p.rows[6].errors.join(), contains('missing'));
        expect(p.creates, 1);

        final r = await h.services.roster.commit(p);
        expect(r.valueOrNull, 1);
        expect(
          h.view.employee('E201')!.transportPreference,
          TransportPreference.evPreferred,
        );
        expect(
          h.view.employee('E1')!.name,
          'Asha Rao',
          reason: 'never overwritten silently',
        );

        final upd = h.services.roster.preview(
          'employee_code,name,pickup_code,destination_code,arrival_time\nE1,Asha Updated,PK02,G1,09:00\n',
          employerId: 'C1',
          allowUpdates: true,
        );
        expect(upd.updates, 1);
        await h.services.roster.commit(upd);
        expect(h.view.employee('E1')!.name, 'Asha Updated');
        expect(h.view.employee('E1')!.status, RecordStatus.active);
      },
    );

    test('missing required column mapping is reported', () async {
      final h = await Harness.create();
      final p = h.services.roster.preview(
        'code,name\nE300,X\n',
        employerId: 'C1',
      );
      expect(p.fileErrors.join(), contains('Pickup code'));
      expect(p.canCommit, isFalse);
    });
  });
}
