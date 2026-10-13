import 'package:executive_fleet/app/providers.dart';
import 'package:executive_fleet/app/router.dart';
import 'package:executive_fleet/domain/models/models.dart';
import 'package:executive_fleet/features/fleet_admin/fleet_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/widget_harness.dart';

/// v2 client-architecture increment (Fleet Manager part B), driven via UI.

ProviderContainer _c(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(FleetShell)));
DataView _data(WidgetTester t) => _c(t).read(dataProvider);
AppServices _svc(WidgetTester t) => _c(t).read(servicesProvider);
String _routeId(WidgetTester t) => _c(t)
    .read(routerProvider)
    .routerDelegate
    .currentConfiguration
    .uri
    .pathSegments
    .last;

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> _tapText(WidgetTester t, String text, {bool last = false}) =>
    _tap(t, last ? find.text(text).last : find.text(text).first);

Finder _inDialog(Finder f) =>
    find.descendant(of: find.byType(AlertDialog), matching: f);

Future<void> _go(WidgetTester t, String path) async {
  _c(t).read(routerProvider).go(path);
  await t.pumpAndSettle();
}

Future<void> _pick(WidgetTester t, Finder dropdown, String item) async {
  await _tap(t, dropdown);
  await t.tap(find.text(item).last);
  await t.pumpAndSettle();
}

/// Any DropdownButtonFormField whose decoration label is [label].
Finder _dropdown(String label) => find
    .ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField),
    )
    .first;
String _tomorrowIso(WidgetTester t) => _data(
  t,
).today.add(const Duration(days: 1)).toIso8601String().substring(0, 10);

void main() {
  setUp(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);

  group('Vehicle mapping', () {
    testWidgets('rows match trips with seat maths; guard deduction shown', (
      t,
    ) async {
      await pumpApp(t, location: '/fleet/mapping', size: desktopSize);
      final data = _data(t);
      final today = data.trips
          .onDay(data.today)
          .where((x) => x.assignedVehicleId != null)
          .toList();
      expect(
        find.text('${today.length} mapping${today.length == 1 ? '' : 's'}'),
        findsOneWidget,
      );
      // C1: 4 total / 1 driver / 0 guard = 3 employee seats, 3 assigned.
      final c1 = find
          .ancestor(of: find.text('Vehicle C1'), matching: find.byType(Row))
          .first;
      expect(
        find.descendant(of: c1, matching: find.text('4/1/0 = 3')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: c1, matching: find.text('3/3')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: c1, matching: find.textContaining('E1, E2, E3')),
        findsOneWidget,
      );

      // Create a guarded mapping through the validated assignment flow.
      final r = await _svc(t).assignments.commit(
        AssignmentRequest(
          employerId: 'C1',
          serviceDate: data.today.add(const Duration(days: 1)),
          employeeIds: const ['E4'],
          driverId: 'DR1',
          vehicleId: 'C3',
          guardRequired: true,
          guardReference: 'G-7 Suresh (demo)',
        ),
      );
      expect(r.isOk, isTrue, reason: r.message);
      await _tapText(t, 'Tomorrow');
      final c3 = find
          .ancestor(of: find.text('Vehicle C3'), matching: find.byType(Row))
          .first;
      expect(
        find.descendant(of: c3, matching: find.text('6/1/1 = 4')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: c3, matching: find.text('Y · G-7 Suresh (demo)')),
        findsOneWidget,
      );

      // Guard filter and row actions.
      await _pick(t, _dropdown('Guard'), 'Required');
      expect(find.text('1 mapping'), findsOneWidget);
      await _tap(t, find.byTooltip('Actions for ${r.valueOrNull!.id}'));
      await _tapText(t, 'Audit history', last: true);
      expect(find.text('Audit · ${r.valueOrNull!.id}'), findsOneWidget);
      expect(
        find.textContaining('Created ${r.valueOrNull!.tripCode}'),
        findsWidgets,
      );
      Navigator.of(t.element(find.text('Audit · ${r.valueOrNull!.id}'))).pop();
      await t.pumpAndSettle();
      await t.pumpAndSettle();
      await _tap(t, find.byTooltip('Actions for ${r.valueOrNull!.id}'));
      await _tapText(t, 'Reassign…', last: true);
      expect(find.text('Reassign ${r.valueOrNull!.tripCode}'), findsOneWidget);
      expect(
        _inDialog(find.widgetWithText(TextField, 'Security guard reference')),
        findsOneWidget,
      );
    });

    testWidgets('missing guard reference is a hard error in reassign', (
      t,
    ) async {
      await pumpApp(t, location: '/fleet/overview', size: desktopSize);
      final r = await _svc(t).assignments.commit(
        AssignmentRequest(
          employerId: 'C1',
          serviceDate: _data(t).today.add(const Duration(days: 1)),
          employeeIds: const ['E4'],
          driverId: 'DR1',
          vehicleId: 'C3',
          guardRequired: true,
          guardReference: 'G-7 Suresh (demo)',
        ),
      );
      expect(r.isOk, isTrue, reason: r.message);
      await _go(t, '/fleet/dispatch/trip/${r.valueOrNull!.id}?reassign=1');
      expect(
        find.text('Security guard'),
        findsOneWidget,
        reason: 'shown on assignment card',
      );
      final guard = _inDialog(
        find.widgetWithText(TextField, 'Security guard reference'),
      );
      expect(t.widget<TextField>(guard).controller!.text, 'G-7 Suresh (demo)');
      await t.enterText(guard, '');
      await t.pumpAndSettle();
      expect(
        _inDialog(
          find.textContaining('Security guard required but none assigned'),
        ),
        findsOneWidget,
      );
      expect(
        t
            .widget<FilledButton>(
              _inDialog(find.widgetWithText(FilledButton, 'Save reassignment')),
            )
            .onPressed,
        isNull,
      );
    });
  });

  group('Optimizer v2', () {
    testWidgets('new sliders, start parking, preference summary for E1', (
      t,
    ) async {
      await pumpApp(t, location: '/fleet/optimization', size: desktopSize);
      for (final label in [
        'Arrival reliability',
        'Employee detour',
        'Pickup-point proximity',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(
        find.text('Employee preferences'),
        findsNWidgets(2),
        reason: 'slider + summary panel',
      );
      expect(find.byType(Slider), findsNWidgets(13));
      expect(find.text('E1 · Asha Rao'), findsWidgets);
      expect(
        find.textContaining('selected employees have saved preferences'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Very important').evaluate().length +
            find.textContaining('Important').evaluate().length,
        greaterThan(0),
      );

      await _pick(
        t,
        find.widgetWithText(
          DropdownButtonFormField<String?>,
          'Each vehicle\'s home parking (default)',
        ),
        'P1 · Main Depot',
      );
      await _tapText(t, 'Run local demo optimizer');
      final run = _data(t).optimizationRun(_routeId(t))!;
      expect(run.isFeasible, isTrue);
      expect(run.plans.every((p) => p.startLocationId == 'P1'), isTrue);
      expect(find.textContaining('Starts from P1 · Main Depot'), findsWidgets);
      expect(find.text('Mapping preview'), findsOneWidget);
      expect(find.text('Candidates'), findsOneWidget);
      if (run.preferenceSummary.isNotEmpty) {
        expect(find.text('Preferences & weights'), findsOneWidget);
      }
      if (run.constraintsEvaluated.isNotEmpty) {
        expect(find.text('Constraints evaluated'), findsOneWidget);
      }
    });

    testWidgets('infeasible run shows remedies', (t) async {
      await pumpApp(t, location: '/fleet/optimization', size: desktopSize);
      for (final type in ['MPV', 'Van', 'SUV']) {
        await _tap(t, find.widgetWithText(FilterChip, type));
      }
      await _tapText(t, 'Run local demo optimizer');
      final run = _data(t).optimizationRun(_routeId(t))!;
      expect(run.isFeasible, isFalse);
      expect(find.text('No feasible assignment'), findsWidgets);
      expect(run.remedies, isNotEmpty);
      expect(find.text('Possible remedies'), findsOneWidget);
      expect(find.text(run.remedies.first), findsOneWidget);
    });

    testWidgets('reject run with reason', (t) async {
      await pumpApp(
        t,
        location: '/fleet/optimization/run/OR-1001',
        size: desktopSize,
      );
      await _tap(t, find.widgetWithText(OutlinedButton, 'Reject'));
      await _tap(t, _inDialog(find.widgetWithText(FilledButton, 'Reject run')));
      expect(find.text('Enter at least 5 characters'), findsOneWidget);
      await t.enterText(
        _inDialog(find.widgetWithText(TextFormField, 'Reason')),
        'Client asked for EV-only fleet',
      );
      await _tap(t, _inDialog(find.widgetWithText(FilledButton, 'Reject run')));
      final run = _data(t).optimizationRun('OR-1001')!;
      expect(run.isRejected, isTrue);
      expect(run.rejectionReason, 'Client asked for EV-only fleet');
      expect(find.textContaining('Rejected'), findsWidgets);
      expect(find.text('Apply proposal'), findsNothing);
      await _tapText(t, 'Optimization');
      expect(find.text('Rejected'), findsWidgets);
    });

    testWidgets('apply requires a guard name for a pool-guard plan', (t) async {
      await pumpApp(t, location: '/fleet/overview', size: desktopSize);
      await _go(
        t,
        '/fleet/optimization?employees=E1,E2&date=${_tomorrowIso(t)}',
      );
      expect(find.text('Employees (2)'), findsOneWidget);
      await _tap(
        t,
        find.widgetWithText(SwitchListTile, 'Security guard required'),
      );
      expect(
        find.widgetWithText(DropdownButtonFormField<int>, '1'),
        findsOneWidget,
        reason: 'guards available defaults to 1',
      );
      await _tapText(t, 'Run local demo optimizer');
      final run = _data(t).optimizationRun(_routeId(t))!;
      expect(
        run.isFeasible,
        isTrue,
        reason: run.hardConstraintViolations.join('; '),
      );
      final pool = run.plans.where((p) => p.guardSource == 'pool').toList();
      expect(pool, hasLength(1));
      expect(find.textContaining('from guard pool'), findsWidgets);
      await _tap(t, find.widgetWithText(FilledButton, 'Apply proposal'));
      final applyBtn = _inDialog(
        find.widgetWithText(FilledButton, 'Apply proposal'),
      );
      expect(
        t.widget<FilledButton>(applyBtn).onPressed,
        isNull,
        reason: 'guard name required',
      );
      await t.enterText(
        _inDialog(
          find.widgetWithText(
            TextField,
            'Guard for Vehicle ${pool.first.vehicleId}',
          ),
        ),
        'Imran (pool guard, demo)',
      );
      await t.pumpAndSettle();
      await _tap(t, applyBtn);
      final applied = _data(t).optimizationRun(run.id)!;
      expect(applied.appliedAt, isNotNull);
      final trip = _data(t).trips.byId(applied.appliedTripIds.single)!;
      expect(trip.guardReference, 'Imran (pool guard, demo)');
      expect(trip.guardRequired, isTrue);
    });
  });

  group('Operator workflow', () {
    testWidgets(
      'Optimize selected opens optimizer prefilled with the requests',
      (t) async {
        await pumpApp(t, location: '/fleet/dispatch', size: desktopSize);
        for (final ref in ['BK-1004', 'BK-1005']) {
          final row = find
              .ancestor(
                of: find.textContaining('$ref ·'),
                matching: find.byType(Row),
              )
              .first;
          await _tap(
            t,
            find.descendant(of: row, matching: find.byType(Checkbox)),
          );
        }
        await _tapText(t, 'Optimize selected (2)');
        expect(find.text('Route optimization'), findsOneWidget);
        expect(find.text('Prefilled from 2 selected requests'), findsOneWidget);
        expect(find.text('Employees (2)'), findsOneWidget);
        await _tapText(t, 'Run local demo optimizer');
        expect(find.textContaining('Run OR-'), findsOneWidget);
        final run = _data(t).optimizationRun(_routeId(t))!;
        expect(run.employeeIds.toSet(), {'E4', 'E23'});
      },
    );
  });

  group('Traffic & movement', () {
    testWidgets(
      'heavy scenario → proposals → apply; same scenario twice adds none',
      (t) async {
        await pumpApp(t, location: '/fleet/traffic', size: desktopSize);
        expect(find.text('Revision history'), findsOneWidget);
        final before = _data(t).routeRevisions.length;
        await _pick(
          t,
          find.widgetWithText(
            DropdownButtonFormField<TrafficLevel>,
            'Internal roads',
          ),
          'Heavy (×1.6)',
        );
        await _pick(
          t,
          find.widgetWithText(
            DropdownButtonFormField<TrafficLevel>,
            'Ring road',
          ),
          'Heavy (×1.6)',
        );
        await _tapText(t, 'Apply scenario & recalculate');
        await _tapText(t, 'OK', last: true).catchError((_) {});
        final afterFirst = _data(t).routeRevisions.length;
        expect(afterFirst, greaterThan(before), reason: 'proposals created');
        final proposed = _data(
          t,
        ).routeRevisions.firstWhere((r) => r.status == RevisionStatus.proposed);
        final tripBefore = _data(t).trips.byId(proposed.tripId)!;
        final stopsBefore = _data(
          t,
        ).trips.stopsOf(tripBefore).map((s) => s.plannedArrival).toList();

        await _tapText(t, 'Apply scenario & recalculate');
        expect(
          _data(t).routeRevisions.length,
          afterFirst,
          reason: 'same scenario twice → no new proposals',
        );

        await _tap(t, find.widgetWithText(FilledButton, 'Apply').first);
        await _tap(t, _inDialog(find.widgetWithText(FilledButton, 'Apply')));
        final applied = _data(t).routeRevisions
            .where((r) => r.status == RevisionStatus.applied)
            .toList();
        expect(applied, isNotEmpty);
        final tripAfter = _data(t).trips.byId(applied.first.tripId)!;
        final stopsAfter = _data(
          t,
        ).trips.stopsOf(tripAfter).map((s) => s.plannedArrival).toList();
        if (applied.first.tripId == tripBefore.id) {
          expect(stopsAfter, isNot(stopsBefore), reason: 'schedule updated');
        }
        await _tapText(t, 'Applied · ${applied.length}');
        expect(find.text(applied.first.id), findsWidgets);
      },
    );

    testWidgets('monitoring links to traffic and shows traffic status', (
      t,
    ) async {
      await pumpApp(t, location: '/fleet/monitoring', size: desktopSize);
      expect(find.textContaining('Traffic (simulated):'), findsWidgets);
      await _tap(t, find.widgetWithText(OutlinedButton, 'Traffic & Movement'));
      expect(find.text('Traffic & movement'), findsOneWidget);
    });
  });

  group('Fleet billing', () {
    testWidgets('run billing cycle (demo) for a due period, idempotent', (
      t,
    ) async {
      await pumpApp(t, location: '/fleet/billing', size: desktopSize);
      expect(find.text('Billing cycle · C1'), findsOneWidget);
      expect(find.text('Trip distance & cost assumptions'), findsOneWidget);
      expect(find.text('Contract context'), findsOneWidget);
      expect(_data(t).invoicesOf('C1'), isEmpty);
      final prev = find.widgetWithText(FilledButton, 'Run');
      await _tap(t, prev);
      expect(_inDialog(find.textContaining('Demo only')), findsWidgets);
      await _tap(t, _inDialog(find.text('Cancel')));
      expect(_data(t).invoicesOf('C1'), isEmpty);
      await _tap(t, prev);
      await _tap(
        t,
        _inDialog(
          find.widgetWithText(FilledButton, 'Run billing cycle (demo)'),
        ),
      );
      if (find.text('OK').evaluate().isNotEmpty) {
        await _tapText(t, 'OK', last: true);
      }
      final invoices = _data(t).invoicesOf('C1');
      expect(invoices, hasLength(1));
      expect(find.text(invoices.single.reference), findsOneWidget);

      // Re-running the same period must not duplicate lines.
      expect(prev, findsNothing, reason: 'period no longer due');
      expect(
        find.text('No completed periods are waiting to be billed.'),
        findsOneWidget,
      );
      final period = _data(t).invoicesOf('C1').single;
      await _svc(t).billingCycles.runCycle(
        'C1',
        BillingPeriod.of(period.cycle, period.periodStart),
      );
      await t.pumpAndSettle();
      final all = _data(t).invoicesOf('C1');
      final billedTrips = all.expand((i) => i.tripIds).toList();
      expect(
        billedTrips.toSet().length,
        billedTrips.length,
        reason: 'no trip billed twice',
      );
    });
  });

  group('Settings audit', () {
    testWidgets('audit result filter and open record', (t) async {
      await pumpApp(t, location: '/fleet/settings', size: desktopSize);
      final total = _data(t).auditTrail.length;
      final trips = _data(
        t,
      ).auditTrail.where((a) => a.entityType == 'trip').length;
      await _pick(t, _dropdown('Record type'), 'trip');
      expect(
        find.text('$trips of $total events · newest first'),
        findsOneWidget,
      );
      await _pick(t, _dropdown('Result'), 'Success');
      final ok = _data(t).auditTrail
          .where(
            (a) => a.entityType == 'trip' && a.outcome == AuditOutcome.success,
          )
          .length;
      expect(find.text('$ok of $total events · newest first'), findsOneWidget);
    });
  });

  group('Overflow v2', () {
    const locations = [
      '/fleet/mapping',
      '/fleet/traffic',
      '/fleet/billing',
      '/fleet/optimization',
      '/fleet/optimization/run/OR-1001',
      '/fleet/optimization/run/OR-1002',
      '/fleet/settings',
      '/fleet/monitoring',
      '/fleet/dispatch',
      '/fleet/dispatch/new?employees=E1,E2',
    ];
    for (final size in [phoneSize, tabletSize, desktopSize]) {
      testWidgets('v2 screens at ${size.width.toInt()}px', (t) async {
        await pumpApp(t, location: locations.first, size: size);
        for (final loc in locations) {
          await _go(t, loc);
          expect(find.byType(FleetShell), findsOneWidget, reason: loc);
        }
      });
    }
  });
}
