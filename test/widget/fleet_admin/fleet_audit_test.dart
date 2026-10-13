import 'package:executive_fleet/app/providers.dart';
import 'package:executive_fleet/app/router.dart';
import 'package:executive_fleet/core/demo/clock.dart';
import 'package:executive_fleet/core/widgets/app_card.dart';
import 'package:executive_fleet/core/widgets/form_fields.dart';
import 'package:executive_fleet/domain/models/models.dart';
import 'package:executive_fleet/features/fleet_admin/fleet_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_export.dart';
import '../../support/widget_harness.dart';

/// QA audit: drives the Fleet Manager console through the UI (taps, text
/// entry) and asserts the shared local records change accordingly.

ProviderContainer _c(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(FleetShell)));
DataView _data(WidgetTester t) => _c(t).read(dataProvider);
AppServices _svc(WidgetTester t) => _c(t).read(servicesProvider);

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

Future<void> _reason(
  WidgetTester t,
  String text, {
  String label = 'Reason',
}) async {
  await t.enterText(_inDialog(find.widgetWithText(TextFormField, label)), text);
  await t.pumpAndSettle();
}

Future<void> _rowAction(
  WidgetTester t,
  String bookingRef,
  String action,
) async {
  await _tap(t, find.byTooltip('Actions for $bookingRef'));
  await t.tap(find.text(action).last);
  await t.pumpAndSettle();
}

Future<void> _go(WidgetTester t, String path) async {
  _c(t).read(routerProvider).go(path);
  await t.pumpAndSettle();
}

Future<void> _dismissDialogsIfAny(WidgetTester t) async {
  if (find.text('OK').evaluate().isNotEmpty) {
    await t.tap(find.text('OK').last);
    await t.pumpAndSettle();
  }
}

void main() {
  setUp(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);

  group('Requests queue', () {
    testWidgets('reject: cancel keeps request, confirm with reason rejects', (
      t,
    ) async {
      await pumpApp(t, location: '/fleet/dispatch', size: desktopSize);
      await _rowAction(t, 'BK-1005', 'Reject…');
      expect(find.text('Reject BK-1005?'), findsOneWidget);
      await _tap(t, _inDialog(find.text('Cancel')));
      expect(_data(t).booking('BK-1005')!.status, BookingStatus.requested);

      await _rowAction(t, 'BK-1005', 'Reject…');
      await _tap(t, _inDialog(find.widgetWithText(FilledButton, 'Reject')));
      expect(
        find.text('Enter at least 5 characters'),
        findsOneWidget,
        reason: 'reason is mandatory',
      );
      await _reason(t, 'Outside service area (demo)');
      await _tap(t, _inDialog(find.widgetWithText(FilledButton, 'Reject')));
      final b = _data(t).booking('BK-1005')!;
      expect(b.status, BookingStatus.rejected);
      expect(b.decisionReason, 'Outside service area (demo)');
    });

    testWidgets('waitlist with prefilled reason', (t) async {
      await pumpApp(t, location: '/fleet/dispatch', size: desktopSize);
      await _rowAction(t, 'BK-1011', 'Waitlist…');
      await _tap(t, _inDialog(find.widgetWithText(FilledButton, 'Waitlist')));
      expect(_data(t).booking('BK-1011')!.status, BookingStatus.waitlisted);
    });

    testWidgets('approve, then add to existing trip TR-1004', (t) async {
      await pumpApp(t, location: '/fleet/dispatch', size: desktopSize);
      await _rowAction(t, 'BK-1004', 'Approve');
      expect(_data(t).booking('BK-1004')!.status, BookingStatus.approved);

      await _rowAction(t, 'BK-1006', 'Add to existing trip…');
      expect(find.text('Add E24 to an existing trip'), findsOneWidget);
      // Only not-started trips on the request date are offered.
      expect(_inDialog(find.text('TR-1001')), findsNothing);
      await _tap(t, _inDialog(find.text('TR-1004')));
      final trip = _data(t).trips.byId('TR-1004')!;
      expect(trip.employeeIds, contains('E24'));
      expect(_data(t).booking('BK-1006')!.tripId, 'TR-1004');
    });

    testWidgets('add to a full trip is rejected with reason (TR-1006 is 6/6)', (
      t,
    ) async {
      await pumpApp(t, location: '/fleet/dispatch', size: desktopSize);
      await _rowAction(t, 'BK-1006', 'Add to existing trip…');
      await _tap(t, _inDialog(find.text('TR-1006')));
      expect(find.text('Could not add to trip'), findsOneWidget);
      expect(find.textContaining('Over capacity'), findsWidgets);
      await _tapText(t, 'OK', last: true);
      expect(_data(t).booking('BK-1006')!.tripId, isNull);
    });

    testWidgets(
      'multi-select two requests → wizard prefilled → save as planned',
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
        await _tapText(t, 'Create trip (2)');
        expect(find.text('New trip'), findsWidgets);
        expect(find.widgetWithText(InputChip, 'E4'), findsOneWidget);
        expect(find.widgetWithText(InputChip, 'E23'), findsOneWidget);
        await _tapText(t, 'Save as planned trip');
        await _dismissDialogsIfAny(t);
        final b4 = _data(t).booking('BK-1004')!;
        expect(b4.tripId, isNotNull);
        expect(_data(t).booking('BK-1005')!.tripId, b4.tripId);
        expect(_data(t).trips.byId(b4.tripId)!.status, TripStatus.planned);
        expect(
          find.text('Trip ${b4.tripId}'),
          findsOneWidget,
          reason: 'navigated to trip detail',
        );
      },
    );

    testWidgets('trip list: day chips, status filter, search, clear filters', (
      t,
    ) async {
      await pumpApp(t, location: '/fleet/dispatch', size: desktopSize);
      expect(find.text('TR-1003'), findsWidgets);
      await _tap(t, find.text('Tomorrow · 2').first);
      expect(find.text('TR-1006'), findsWidgets);
      await _tap(t, find.text('Today · 4').first);
      await _tapText(t, 'Cancelled');
      expect(find.text('TR-1005'), findsWidgets);
      expect(find.text('TR-1001'), findsNothing);
      await _tapText(t, 'All');
      await t.enterText(
        find.widgetWithText(TextField, 'Trip, driver, vehicle or employee ID'),
        'zzz',
      );
      await t.pumpAndSettle();
      expect(find.text('No trips match'), findsOneWidget);
      await _tapText(t, 'Clear filters');
      expect(find.text('TR-1001'), findsWidgets);
      final field = t.widget<TextField>(
        find.widgetWithText(TextField, 'Trip, driver, vehicle or employee ID'),
      );
      expect(field.controller!.text, isEmpty, reason: 'search box resets');
    });
  });

  group('Dispatch wizard', () {
    testWidgets(
      'search, manual/auto start, capacity error + fix, guard reduces capacity, save',
      (t) async {
        await pumpApp(t, location: '/fleet/dispatch/new', size: desktopSize);
        expect(
          find.text('Select employees to validate the assignment.'),
          findsOneWidget,
        );
        await t.enterText(
          find.widgetWithText(
            TextField,
            'Search by ID, name, pickup (PK01) or office (G1)',
          ),
          'Asha',
        );
        await t.pumpAndSettle();
        expect(find.text('E2 · Kiran Mehta'), findsNothing);
        await _tapText(t, 'E1 · Asha Rao');
        expect(find.text('All hard constraints pass'), findsOneWidget);

        // Manual start at the time picker default (9:00 AM) is too late.
        await _tap(t, find.byType(TimeOfDayField));
        await _tapText(t, 'OK', last: true);
        expect(find.textContaining('would arrive'), findsOneWidget);
        await _tapText(t, 'Use automatic start time');
        expect(find.text('All hard constraints pass'), findsOneWidget);

        // Add E2–E4 via search.
        for (final e in [
          'E2 · Kiran Mehta',
          'E3 · Neha Iyer',
          'E4 · Arjun Das',
        ]) {
          await t.enterText(
            find.widgetWithText(
              TextField,
              'Search by ID, name, pickup (PK01) or office (G1)',
            ),
            e.split(' · ').last,
          );
          await t.pumpAndSettle();
          await _tapText(t, e);
        }
        expect(find.text('Employees (4 selected)'), findsOneWidget);
        await _tapText(t, 'Vehicle C1 · EV Sedan');
        expect(
          find.textContaining(
            'Over capacity: 4 employees but Vehicle C1 seats 3',
          ),
          findsWidgets,
        );
        await _tapText(t, 'Use Vehicle C3 (5 seats)');
        expect(
          find.textContaining(
            '6 total − 1 driver − 0 guard = 5 employee seats',
          ),
          findsWidgets,
        );

        await _tap(
          t,
          find.widgetWithText(SwitchListTile, 'Security guard required'),
        );
        expect(
          find.textContaining(
            '6 total − 1 driver − 1 guard = 4 employee seats',
          ),
          findsWidgets,
        );
        // Hard rule: a required guard must be named (C3 has none assigned).
        expect(
          find.textContaining('Security guard required but none assigned'),
          findsWidgets,
        );
        await t.enterText(
          find.widgetWithText(TextField, 'Security guard reference'),
          'G-101 Ramesh (demo)',
        );
        await t.pumpAndSettle();
        expect(
          find.text('All hard constraints pass'),
          findsOneWidget,
          reason: '4 employees still fit',
        );

        await _tapText(t, 'DR3 Arif Khan');
        await _tapText(t, 'Save & assign trip');
        await _dismissDialogsIfAny(t);
        final trip = _data(t).trips.all().firstWhere(
          (x) =>
              x.employeeIds.toSet().containsAll(['E1', 'E2', 'E3', 'E4']) &&
              x.status == TripStatus.assigned,
        );
        expect(trip.assignedVehicleId, 'C3');
        expect(trip.guardRequired, isTrue);
        expect(trip.guardReference, 'G-101 Ramesh (demo)');
      },
    );

    testWidgets('off-duty driver needs explicit override with reason', (
      t,
    ) async {
      await pumpApp(t, location: '/fleet/overview', size: desktopSize);
      final d = _data(t).driver('DR1')!;
      await _svc(t).fleet.saveDriver(d.copyWith(status: DriverStatus.offDuty));
      await _go(t, '/fleet/dispatch/new?employees=E4');
      await _tapText(t, 'DR1 Ravi Kumar');
      expect(find.textContaining('Use an explicit override'), findsWidgets);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save as planned trip'),
            )
            .onPressed,
        isNull,
      );
      await _tapText(t, 'Override with reason');
      await t.enterText(
        find.widgetWithText(TextField, 'Override reason (min 5 characters)'),
        'Volunteered for cover shift',
      );
      await t.pumpAndSettle();
      expect(find.textContaining('Override: DR1 is off duty'), findsOneWidget);
      await _tapText(t, 'Vehicle C1 · EV Sedan');
      await _tapText(t, 'Save & assign trip');
      await _dismissDialogsIfAny(t);
      final trip = _data(t).trips.all().firstWhere(
        (x) => x.employeeIds.contains('E4') && x.assignedDriverId == 'DR1',
      );
      expect(trip.assignmentHistory.last.reason, contains('Override'));
    });
  });

  group('Trip detail', () {
    testWidgets(
      'reassign needs reason; cancel needs reason; cancel dialog cancel',
      (t) async {
        // Today every vehicle is busy in TR-1001's window: options show blocked.
        await pumpApp(
          t,
          location: '/fleet/dispatch/trip/TR-1001',
          size: desktopSize,
        );
        await _tapText(t, 'Reassign');
        await _tap(
          t,
          _inDialog(find.textContaining('Vehicle C1 · EV Sedan')).first,
        );
        expect(
          find.textContaining('Vehicle C3 · EV MPV · 5 seats · blocked'),
          findsWidgets,
        );
        await t.tap(find.textContaining('Vehicle C3 · EV MPV').last);
        await t.pumpAndSettle();
        expect(
          _inDialog(
            find.textContaining('Vehicle C3 is already assigned to TR-1003'),
          ),
          findsOneWidget,
        );
        await _tap(t, _inDialog(find.text('Cancel')));
        expect(_data(t).trips.byId('TR-1001')!.assignedVehicleId, 'C1');

        // Planned TR-1004 (tomorrow): first assignment needs no reason.
        await _go(t, '/fleet/dispatch/trip/TR-1004');
        await _tapText(t, 'Assign driver & vehicle');
        await _tap(
          t,
          _inDialog(
            find.widgetWithText(DropdownButtonFormField<String?>, 'Vehicle'),
          ),
        );
        await t.tap(find.textContaining('Vehicle C3 · EV MPV').last);
        await t.pumpAndSettle();
        await _tap(
          t,
          _inDialog(
            find.widgetWithText(DropdownButtonFormField<String?>, 'Driver'),
          ),
        );
        await t.tap(find.textContaining('DR3 Arif Khan').last);
        await t.pumpAndSettle();
        expect(
          _inDialog(
            find.widgetWithText(TextField, 'Reassignment reason (required)'),
          ),
          findsNothing,
        );
        await _tap(t, find.widgetWithText(FilledButton, 'Assign'));
        expect(_data(t).trips.byId('TR-1004')!.status, TripStatus.assigned);

        // Reassign driver: reason required.
        await _tapText(t, 'Reassign');
        await _tap(t, _inDialog(find.textContaining('DR3 Arif Khan')).first);
        await t.tap(find.textContaining('DR1 Ravi Kumar').last);
        await t.pumpAndSettle();
        final save = find.widgetWithText(FilledButton, 'Save reassignment');
        expect(t.widget<FilledButton>(save).onPressed, isNull);
        await t.enterText(
          _inDialog(
            find.widgetWithText(TextField, 'Reassignment reason (required)'),
          ),
          'DR3 on leave tomorrow',
        );
        await t.pumpAndSettle();
        await _tap(t, save);
        final trip = _data(t).trips.byId('TR-1004')!;
        expect(trip.assignedDriverId, 'DR1');
        expect(trip.assignmentHistory.last.reason, 'DR3 on leave tomorrow');
        expect(
          find.textContaining('DR3 on leave tomorrow'),
          findsOneWidget,
          reason: 'history shown',
        );

        await _tap(t, find.widgetWithText(OutlinedButton, 'Cancel trip'));
        await _tap(t, _inDialog(find.text('Cancel')));
        expect(_data(t).trips.byId('TR-1004')!.status, TripStatus.assigned);
        await _tap(t, find.widgetWithText(OutlinedButton, 'Cancel trip'));
        await _reason(t, 'Client event postponed');
        await _tap(
          t,
          _inDialog(find.widgetWithText(FilledButton, 'Cancel trip')),
        );
        expect(_data(t).trips.byId('TR-1004')!.status, TripStatus.cancelled);
        expect(
          find.widgetWithText(OutlinedButton, 'Cancel trip'),
          findsNothing,
          reason: 'terminal trip has no cancel',
        );
      },
    );

    testWidgets(
      'needs-attention trip: keep current assignment fails while vehicle in maintenance',
      (t) async {
        await pumpApp(t, location: '/fleet/overview', size: desktopSize);
        final v = _data(t).vehicle('C1')!;
        await _svc(
          t,
        ).fleet.saveVehicle(v.copyWith(status: VehicleStatus.maintenance));
        await _go(t, '/fleet/dispatch/trip/TR-1001');
        expect(find.text('Needs attention'), findsWidgets);
        await _tapText(t, 'Keep current assignment');
        expect(find.text('Current assignment is not valid'), findsOneWidget);
        expect(
          find.textContaining('Vehicle C1 is in maintenance'),
          findsWidgets,
        );
      },
    );
  });

  group('Optimizer', () {
    testWidgets(
      'weights, allowed types, sedan-only infeasible, E1–E4 feasible, compare, apply cancel/confirm, save profile',
      (t) async {
        await pumpApp(t, location: '/fleet/optimization', size: desktopSize);
        final sliders = find.byType(Slider);
        expect(sliders, findsNWidgets(13), reason: '12 weights + min EV share');
        for (var i = 0; i < 12; i++) {
          await t.ensureVisible(sliders.at(i));
          await t.pumpAndSettle();
          await t.drag(sliders.at(i), const Offset(-30, 0));
          await t.pumpAndSettle();
        }
        await _tapText(t, 'Save profile');
        final cfg = _data(t).optimizationConfigs.first;
        expect([
          cfg.costWeight,
          cfg.punctualityWeight,
          cfg.distanceWeight,
          cfg.travelTimeWeight,
          cfg.utilizationWeight,
          cfg.evPreferenceWeight,
          cfg.customerPreferenceWeight,
          cfg.safetyWeight,
          cfg.guardRequirementWeight,
        ], isNot([6, 9, 5, 5, 5, 6, 4, 10, 5]));

        // Sedan only → infeasible, no fabricated route.
        for (final type in ['MPV', 'Van', 'SUV']) {
          await _tap(t, find.widgetWithText(FilterChip, type));
        }
        await _tapText(t, 'Run local demo optimizer');
        expect(find.text('No feasible assignment'), findsWidgets);
        expect(find.text('Apply proposal'), findsNothing);

        await _tapText(t, 'Optimization');
        for (final type in ['MPV', 'Van', 'SUV']) {
          await _tap(t, find.widgetWithText(FilterChip, type));
        }
        await _tapText(t, 'Run local demo optimizer');
        expect(find.text('/ 100 score'), findsOneWidget);
        final runId = _c(t)
            .read(routerProvider)
            .routerDelegate
            .currentConfiguration
            .uri
            .pathSegments
            .last;
        expect(_data(t).optimizationRun(runId)!.isFeasible, isTrue);

        await _tapText(t, 'Apply proposal');
        await _tap(t, _inDialog(find.text('Cancel')));
        expect(_data(t).optimizationRun(runId)!.appliedAt, isNull);
        await _tapText(t, 'Apply proposal');
        await _tap(
          t,
          _inDialog(find.widgetWithText(FilledButton, 'Apply proposal')),
        );
        expect(_data(t).optimizationRun(runId)!.appliedAt, isNotNull);
        expect(find.textContaining('Applied'), findsWidgets);

        // Compare two saved runs.
        await _tapText(t, 'Optimization');
        final checks = find.descendant(
          of: find
              .ancestor(
                of: find.text('Saved runs'),
                matching: find.byType(AppCard),
              )
              .first,
          matching: find.byType(Checkbox),
        );
        await _tap(t, checks.at(0));
        await _tap(t, checks.at(1));
        expect(find.text('Comparison'), findsOneWidget);
        expect(find.text('Seat utilization'), findsOneWidget);
      },
    );
  });

  group('Parameter catalog', () {
    testWidgets('search, edit live parameter, read-only catalog params', (
      t,
    ) async {
      await pumpApp(
        t,
        location: '/fleet/optimization/parameters',
        size: desktopSize,
      );
      await t.enterText(
        find.widgetWithText(TextField, 'Search parameters'),
        'detour',
      );
      await t.pumpAndSettle();
      expect(find.text('Max pickup detour'), findsOneWidget);
      expect(find.text('Rain slowdown factor'), findsNothing);
      await t.enterText(
        find.byKey(const ValueKey('param-max_detour_km')),
        '14',
      );
      await t.pumpAndSettle();
      await _tapText(t, 'Save changes (1)');
      expect(
        _data(
          t,
        ).optimizationConfigs.first.additionalParameters['max_detour_km'],
        14,
      );

      await t.enterText(
        find.widgetWithText(TextField, 'Search parameters'),
        'rain',
      );
      await t.pumpAndSettle();
      expect(find.text('Rain slowdown factor'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('param-rain_factor')),
        findsNothing,
        reason: 'catalog-only is read-only',
      );
      expect(find.text('Catalog only (not connected)'), findsWidgets);
    });

    testWidgets('out-of-bounds value is rejected inline', (t) async {
      await pumpApp(
        t,
        location: '/fleet/optimization/parameters',
        size: desktopSize,
      );
      await t.enterText(
        find.widgetWithText(TextField, 'Search parameters'),
        'detour',
      );
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('param-max_detour_km')),
        '99',
      );
      await t.pumpAndSettle();
      await _tapText(t, 'Save changes (1)');
      expect(find.textContaining('must be between'), findsWidgets);
    });
  });

  group('Pooling', () {
    testWidgets('suggest pools, pair check, create trip from group', (t) async {
      await pumpApp(t, location: '/fleet/pooling', size: desktopSize);
      expect(find.text('Pool suggestions appear here'), findsOneWidget);
      await _tapText(t, 'Suggest pools');
      expect(find.textContaining('Pool 1 ·'), findsOneWidget);
      expect(
        find.textContaining('Can be pooled').evaluate().length +
            find.textContaining('Cannot be pooled').evaluate().length,
        1,
      );
      await _tap(t, find.widgetWithText(FilledButton, 'Create trip').first);
      expect(find.text('New trip'), findsWidgets);
      expect(find.byType(InputChip), findsWidgets);
    });
  });

  group('Vehicles & drivers', () {
    testWidgets(
      'add vehicle with validation; edit + maintenance confirm (cancel and confirm)',
      (t) async {
        await pumpApp(t, location: '/fleet/vehicles', size: desktopSize);
        await _tapText(t, 'Add vehicle');
        await t.enterText(find.widgetWithText(TextField, 'Vehicle ID'), 'C4');
        await _tap(t, find.widgetWithText(FilledButton, 'Add vehicle'));
        expect(find.textContaining('Registration is required'), findsOneWidget);
        await t.enterText(
          find.widgetWithText(TextField, 'Registration (fictional)'),
          'DM-04-EV-4004',
        );
        await _tap(t, find.widgetWithText(FilledButton, 'Add vehicle'));
        expect(_data(t).vehicle('C4'), isNotNull);
        expect(find.text('Vehicle C4'), findsWidgets);

        await _go(t, '/fleet/vehicles/C1');
        await _tap(
          t,
          find.widgetWithText(
            DropdownButtonFormField<VehicleStatus>,
            'Assigned',
          ),
        );
        await t.tap(find.text('Maintenance').last);
        await t.pumpAndSettle();
        expect(find.text('Out of service'), findsOneWidget);
        await _tapText(t, 'Save changes');
        expect(find.text('Take Vehicle C1 out of service?'), findsOneWidget);
        await _tap(t, _inDialog(find.text('Cancel')));
        expect(_data(t).vehicle('C1')!.status, VehicleStatus.assigned);
        await _tapText(t, 'Save changes');
        await _tap(t, _inDialog(find.text('Set maintenance')));
        expect(_data(t).vehicle('C1')!.status, VehicleStatus.maintenance);
        expect(
          _data(t).trips.byId('TR-1001')!.status,
          TripStatus.needsAttention,
        );
      },
    );

    testWidgets('vehicle list filters and search', (t) async {
      await pumpApp(t, location: '/fleet/vehicles', size: desktopSize);
      await t.enterText(
        find.widgetWithText(TextField, 'Search ID, registration, model'),
        'van',
      );
      await t.pumpAndSettle();
      expect(find.text('Vehicle C2'), findsOneWidget);
      expect(find.text('Vehicle C1'), findsNothing);
      await t.enterText(
        find.widgetWithText(TextField, 'Search ID, registration, model'),
        '',
      );
      await _tap(
        t,
        find.widgetWithText(DropdownButtonFormField<Propulsion?>, 'Any'),
      );
      await t.tap(find.text('ICE').last);
      await t.pumpAndSettle();
      expect(find.text('Vehicle C2'), findsOneWidget);
      expect(find.text('Vehicle C3'), findsNothing);
    });

    testWidgets('add driver with validation, edit, regularization approve', (
      t,
    ) async {
      await pumpApp(t, location: '/fleet/drivers', size: desktopSize);
      expect(
        find.textContaining('Attendance regularization · DR3'),
        findsOneWidget,
      );
      await _tapText(t, 'Approve');
      expect(
        _data(t).todayShift('DR3')!.regularizationStatus,
        RegularizationStatus.approved,
      );

      await _tapText(t, 'Add driver');
      await t.enterText(find.widgetWithText(TextField, 'Driver ID'), 'DR4');
      await _tap(t, find.widgetWithText(FilledButton, 'Add driver'));
      expect(find.textContaining('Name is required'), findsOneWidget);
      await t.enterText(
        find.widgetWithText(TextField, 'Name (fictional)'),
        'Meena Pillai',
      );
      await _tap(t, find.widgetWithText(FilledButton, 'Add driver'));
      expect(find.textContaining('Licence number is required'), findsOneWidget);
      expect(_data(t).driver('DR4'), isNull);
      await t.enterText(
        find.widgetWithText(TextField, 'Licence number (fictional, required)'),
        'DL-DEMO-0004',
      );
      await _tap(t, find.widgetWithText(FilledButton, 'Add driver'));
      expect(_data(t).driver('DR4')!.name, 'Meena Pillai');
      expect(_data(t).driver('DR4')!.licenceNumber, 'DL-DEMO-0004');

      await t.enterText(
        find.widgetWithText(TextField, 'Licence class'),
        'LMV-TR (demo)',
      );
      await _tapText(t, 'Save changes');
      expect(_data(t).driver('DR4')!.licenceClass, 'LMV-TR (demo)');
    });

    testWidgets('regularization reject from driver detail', (t) async {
      await pumpApp(t, location: '/fleet/drivers/DR3', size: desktopSize);
      await _tapText(t, 'Reject');
      expect(
        _data(t).todayShift('DR3')!.regularizationStatus,
        RegularizationStatus.rejected,
      );
    });
  });

  group('Parking', () {
    testWidgets('add and edit location', (t) async {
      await pumpApp(t, location: '/fleet/parking', size: desktopSize);
      await _tapText(t, 'Add location');
      await t.enterText(
        _inDialog(find.widgetWithText(TextField, 'Code')),
        'P11',
      );
      await t.enterText(
        _inDialog(find.widgetWithText(TextField, 'Name (fictional)')),
        'Parking Bay 11',
      );
      await _tap(t, _inDialog(find.widgetWithText(FilledButton, 'Add')));
      expect(find.textContaining('at least 1 spot'), findsOneWidget);
      await t.enterText(
        _inDialog(find.widgetWithText(TextField, 'Parking spots (capacity)')),
        '6',
      );
      await _tap(t, _inDialog(find.widgetWithText(FilledButton, 'Add')));
      expect(_data(t).location('P11')!.name, 'Parking Bay 11');
      expect(_data(t).location('P11')!.capacity, 6);
      expect(_data(t).location('P11')!.latitude, isNotNull);

      await _tap(t, find.byTooltip('Edit P2'));
      await t.enterText(
        _inDialog(find.widgetWithText(TextField, 'Name (fictional)')),
        'North Bay',
      );
      await _tap(t, _inDialog(find.widgetWithText(FilledButton, 'Save')));
      expect(_data(t).location('P2')!.name, 'North Bay');
    });

    testWidgets('invalid coordinates rejected inline', (t) async {
      await pumpApp(t, location: '/fleet/parking', size: desktopSize);
      await _tapText(t, 'Add location');
      await t.enterText(
        _inDialog(find.widgetWithText(TextField, 'Code')),
        'P12',
      );
      await t.enterText(
        _inDialog(find.widgetWithText(TextField, 'Name (fictional)')),
        'Far Away',
      );
      await t.enterText(
        _inDialog(find.widgetWithText(TextField, 'Parking spots (capacity)')),
        '4',
      );
      await t.enterText(
        _inDialog(find.widgetWithText(TextField, 'Latitude (fictional)')),
        '95',
      );
      await _tap(t, _inDialog(find.widgetWithText(FilledButton, 'Add')));
      expect(find.textContaining('Latitude must be between'), findsOneWidget);
      expect(find.textContaining('demo service area'), findsOneWidget);
      expect(_data(t).location('P12'), isNull);
    });
  });

  group('Monitoring & incidents', () {
    testWidgets('acknowledge, reassign shortcut, ticket status', (t) async {
      await pumpApp(t, location: '/fleet/monitoring', size: desktopSize);
      expect(find.text('TR-1003'), findsWidgets);
      await _tapText(t, 'Incidents · 2');
      await _tapText(t, 'IC-1001');
      await _tapText(t, 'Acknowledge');
      expect(
        _data(t).incident('IC-1001')!.status,
        IncidentStatus.acknowledgedDemo,
      );
      await _tapText(t, 'Reassign vehicle / driver');
      expect(
        find.text('Reassign TR-1003'),
        findsNothing,
        reason: 'in-progress delayed trip cannot be reassigned',
      );
      await _tapText(t, 'Monitoring & Incidents');

      await _go(t, '/fleet/monitoring?tab=tickets');
      await _tap(t, find.byTooltip('Update TK-1002'));
      await t.tap(find.text('Mark resolved').last);
      await t.pumpAndSettle();
      await _reason(t, 'Fuel card reissued (demo)', label: 'Response to DR2');
      await _tap(t, _inDialog(find.widgetWithText(FilledButton, 'Resolve')));
      final tk = _data(t).tickets.firstWhere((x) => x.id == 'TK-1002');
      expect(tk.status, TicketStatus.resolved);
      expect(tk.response, 'Fuel card reissued (demo)');
    });

    testWidgets('driver breakdown reflects here; resolve restores vehicle', (
      t,
    ) async {
      await pumpApp(t, location: '/fleet/overview', size: desktopSize);
      final r = await _svc(t).incidents.report(
        IncidentDraft(
          type: IncidentType.breakdown,
          description: 'Engine warning light, pulled over safely',
          severity: IncidentSeverity.high,
          reporter: Actor.driver('DR2'),
          tripId: 'TR-1002',
          replacementRequested: true,
        ),
      );
      expect(r.isOk, isTrue);
      final id = r.valueOrNull!.id;
      await t.pumpAndSettle();
      expect(
        find.text('Vehicle C2 maintenance'),
        findsOneWidget,
        reason: 'overview needs-attention',
      );
      await _go(t, '/fleet/monitoring?tab=incidents');
      expect(find.text(id), findsWidgets);
      await _tapText(t, id);
      expect(find.text('Replacement requested'), findsOneWidget);
      await _tapText(t, 'Resolve');
      final restore = _inDialog(find.byType(CheckboxListTile));
      expect(t.widget<CheckboxListTile>(restore).value, isTrue);
      await _tap(t, _inDialog(find.widgetWithText(FilledButton, 'Resolve')));
      expect(find.text('Enter at least 5 characters'), findsOneWidget);
      await t.enterText(
        _inDialog(find.byType(TextField)),
        'Sensor fault, cleared at depot (demo)',
      );
      await _tap(t, _inDialog(find.widgetWithText(FilledButton, 'Resolve')));
      expect(_data(t).incident(id)!.status, IncidentStatus.resolvedDemo);
      expect(_data(t).vehicle('C2')!.status, isNot(VehicleStatus.maintenance));
    });

    testWidgets('reassign shortcut on a not-started trip opens the dialog', (
      t,
    ) async {
      await pumpApp(t, location: '/fleet/overview', size: desktopSize);
      final r = await _svc(t).incidents.report(
        IncidentDraft(
          type: IncidentType.vehicleDefect,
          description: 'Door lock not engaging on rear left',
          severity: IncidentSeverity.high,
          reporter: Actor.driver('DR1'),
          tripId: 'TR-1001',
        ),
      );
      await _go(t, '/fleet/monitoring/incident/${r.valueOrNull!.id}');
      await _tapText(t, 'Reassign vehicle / driver');
      expect(find.text('Reassign TR-1001'), findsOneWidget);
    });
  });

  group('Reports, settings, notifications', () {
    testWidgets('report ranges and CSV exports reach the export service', (
      t,
    ) async {
      final fake = FakeExportService();
      await pumpApp(
        t,
        location: '/fleet/reports',
        size: desktopSize,
        export: fake,
      );
      for (final r in ['14 days', '30 days', '7 days']) {
        await _tapText(t, r);
        expect(find.text('Operational reports'), findsOneWidget);
      }
      await _tapText(t, 'Export trips CSV');
      expect(find.text('Saved fleet_trips_7d.csv (test)'), findsOneWidget);
      final trips = fake.saved['fleet_trips_7d.csv']!;
      expect(
        trips.split('\r\n').first,
        startsWith('trip,date,status,driver,vehicle'),
      );
      expect(trips, contains('TR-1001'));

      final csv = find.ancestor(
        of: find.text('CSV'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      expect(csv, findsNWidgets(2));
      await _tap(t, csv.at(0));
      await _tap(
        t,
        find
            .ancestor(
              of: find.text('CSV'),
              matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
            )
            .at(1),
      );
      final usage = fake.saved['vehicle_usage_7d.csv']!;
      expect(usage.split('\r\n'), hasLength(1 + _data(t).vehicles.length));
      expect(usage, contains('C1,EV'));
      final perf = fake.saved['driver_performance_7d.csv']!;
      expect(
        perf.split('\r\n').first,
        'driver,name,status,assigned,completed,incidents',
      );
      expect(perf, contains('DR1,Ravi Kumar'));

      // Range changes the exported file.
      await _tapText(t, '30 days');
      await _tapText(t, 'Export trips CSV');
      expect(fake.saved.keys, contains('fleet_trips_30d.csv'));
      expect(fake.saved['fleet_trips_30d.csv'], contains('TR-0991'));
    });

    testWidgets(
      'settings audit filter/search, profile discard resets slider and dropdown',
      (t) async {
        await pumpApp(t, location: '/fleet/settings', size: desktopSize);
        await _tap(
          t,
          find.widgetWithText(DropdownButtonFormField<int>, '10 min'),
        );
        await t.tap(find.text('20 min').last);
        await t.pumpAndSettle();
        expect(find.text('Discard'), findsOneWidget);
        await _tapText(t, 'Discard');
        expect(
          find.widgetWithText(DropdownButtonFormField<int>, '10 min'),
          findsOneWidget,
          reason: 'dropdown resets',
        );
        expect(find.text('Discard'), findsNothing);

        // Shared AuditTrailView: record-type filter, search, open record.
        await _tap(
          t,
          find.widgetWithText(DropdownButtonFormField<String?>, 'Record type'),
        );
        await t.tap(find.text('trip').last);
        await t.pumpAndSettle();
        expect(find.textContaining('TR-1001'), findsWidgets);
        expect(find.textContaining('Baseline demo dataset'), findsNothing);
        await t.enterText(
          find.widgetWithText(
            TextField,
            'Search by audit ID, record ID, actor or text',
          ),
          'zzzz',
        );
        await t.pumpAndSettle();
        expect(find.text('No audit events'), findsOneWidget);
        await t.enterText(
          find.widgetWithText(
            TextField,
            'Search by audit ID, record ID, actor or text',
          ),
          'TR-1001',
        );
        await t.pumpAndSettle();
        await _tap(
          t,
          find.textContaining('Assigned DR1 + Vehicle C1 to TR-1001').first,
        );
        await _tapText(t, 'Open record');
        expect(find.text('Trip TR-1001'), findsOneWidget);
      },
    );

    testWidgets('notifications panel routes to the related record', (t) async {
      await pumpApp(t, location: '/fleet/overview', size: desktopSize);
      await _tap(t, find.byTooltip('Notifications'));
      await _tapText(t, 'Delay reported on TR-1003');
      expect(find.textContaining('IC-1001 · Delay'), findsOneWidget);
      await _tap(t, find.byTooltip('Notifications'));
      await _tapText(t, 'New booking request BK-1004');
      expect(find.text('Trips & dispatch'), findsOneWidget);
      await _tap(t, find.byTooltip('Notifications'));
      await _tapText(t, 'Inspection needs review: Vehicle C3');
      expect(find.text('Vehicle C3'), findsWidgets);
    });
  });

  group('Cross-app reflection', () {
    testWidgets('employee booking appears in the queue immediately', (t) async {
      await pumpApp(t, location: '/fleet/dispatch', size: desktopSize);
      final e = _data(t).employee('E50')!;
      final r = await _svc(t).bookings.submit(
        BookingDraft(
          employeeId: e.id,
          pickupLocationId: e.pickupLocationId,
          destinationId: e.destinationId,
          date: dateOnly(_data(t).now).add(const Duration(days: 2)),
          arrivalMinutes: 540,
        ),
      );
      expect(r.isOk, isTrue, reason: r.message);
      await t.pumpAndSettle();
      expect(
        find.textContaining('${r.valueOrNull!.reference} · E50'),
        findsOneWidget,
      );
    });
  });

  group('Remaining controls', () {
    testWidgets('overview quick actions and needs-attention Reassign', (
      t,
    ) async {
      await pumpApp(t, location: '/fleet/overview', size: desktopSize);
      await _tapText(t, 'New trip');
      expect(
        find.text('Select employees to validate the assignment.'),
        findsOneWidget,
      );
      await _tapText(t, 'Overview');
      await _tapText(t, 'Optimize');
      expect(find.text('Route optimization'), findsOneWidget);
      await _tapText(t, 'Overview');
      await _tap(t, find.textContaining('Vehicles available'));
      expect(find.text('Add vehicle'), findsOneWidget);
      final v = _data(t).vehicle('C1')!;
      await _svc(
        t,
      ).fleet.saveVehicle(v.copyWith(status: VehicleStatus.maintenance));
      await _go(t, '/fleet/overview');
      await _tap(t, find.widgetWithText(FilledButton, 'Reassign').first);
      expect(find.text('Reassign TR-1001'), findsOneWidget);
    });

    testWidgets(
      'optimizer inputs: chips, candidate vehicle, variant, guard, EV slider',
      (t) async {
        await pumpApp(t, location: '/fleet/optimization', size: desktopSize);
        await _tapText(t, 'Clear');
        expect(find.text('Employees (0)'), findsOneWidget);
        final run = find.widgetWithText(
          FilledButton,
          'Run local demo optimizer',
        );
        expect(
          t.widget<FilledButton>(run).onPressed,
          isNull,
          reason: 'needs employees',
        );
        await _tapText(t, 'E1–E4');
        expect(find.text('Employees (4)'), findsOneWidget);
        await _tap(
          t,
          find.widgetWithText(CheckboxListTile, 'Vehicle C3 · EV MPV'),
        );
        await _tap(
          t,
          find.widgetWithText(
            DropdownButtonFormField<RouteVariant?>,
            'Auto — compare ring road vs internal roads',
          ),
        );
        await t.tap(find.text('Ring road').last);
        await t.pumpAndSettle();
        await _tap(
          t,
          find.widgetWithText(SwitchListTile, 'Security guard required'),
        );
        final ev = find.byType(Slider).last;
        await t.ensureVisible(ev);
        await t.drag(ev, const Offset(60, 0));
        await t.pumpAndSettle();
        await _tap(t, run);
        // Without C3 and with a guard seat, C1 (2 seats) + C2 (busy) cannot seat 4.
        expect(find.text('No feasible assignment'), findsWidgets);
        final id = _c(t)
            .read(routerProvider)
            .routerDelegate
            .currentConfiguration
            .uri
            .pathSegments
            .last;
        expect(
          _data(t).optimizationRun(id)!.hardConstraintViolations,
          isNotEmpty,
        );
      },
    );

    testWidgets('pooling quick chips and date reset results', (t) async {
      await pumpApp(t, location: '/fleet/pooling', size: desktopSize);
      await _tapText(t, 'E21–E40');
      expect(find.text('20 selected for Tue, 20 Oct'), findsOneWidget);
      await _tapText(t, 'Suggest pools');
      expect(find.textContaining('Rules applied'), findsWidgets);
      await _tapText(t, 'Clear');
      expect(find.text('Pool suggestions appear here'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Suggest pools'),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets(
      'drivers/parking/monitoring filters and notifications mark all read',
      (t) async {
        await pumpApp(t, location: '/fleet/drivers', size: desktopSize);
        await _tapText(t, 'On trip · 2');
        expect(find.text('DR1 · Ravi Kumar'), findsNothing);
        expect(find.text('DR2 · Priya Sharma'), findsOneWidget);

        await _go(t, '/fleet/parking');
        await _tapText(t, 'Destinations · 4');
        expect(find.text('G1 · Tech Park Tower A'), findsOneWidget);
        expect(find.text('P1 · Main Depot'), findsNothing);
        await _tapText(t, 'Pickup stops · 12');
        expect(find.text('PK01 · Cedar Park Gate'), findsOneWidget);

        await _go(t, '/fleet/monitoring?tab=incidents');
        await _tapText(t, 'Resolved');
        expect(find.text('IC-1002'), findsWidgets);
        expect(find.text('IC-1001'), findsNothing);
        await _tapText(t, 'All');
        await _tap(
          t,
          find.widgetWithText(
            DropdownButtonFormField<IncidentType?>,
            'All types',
          ),
        );
        await t.tap(find.text('Passenger issue').last);
        await t.pumpAndSettle();
        expect(find.text('IC-1003'), findsWidgets);
        expect(find.text('IC-1002'), findsNothing);
        await _tapText(t, 'Live board · 2');
        await _tap(t, find.text('TR-1003').first);
        expect(find.text('Trip TR-1003'), findsOneWidget);

        await _go(t, '/fleet/settings');
        await _tapText(t, 'Open notifications');
        await _tapText(t, 'Mark all read');
        expect(_data(t).unreadCount(UserRole.fleetManager), 0);
        await _tapText(t, 'Unread · 0');
        expect(find.text('You\'re all caught up'), findsOneWidget);
      },
    );
  });

  group('Overflow', () {
    const locations = [
      '/fleet/overview',
      '/fleet/dispatch',
      '/fleet/dispatch/new?employees=E1,E2,E3,E4',
      '/fleet/dispatch/trip/TR-1002',
      '/fleet/optimization',
      '/fleet/optimization/run/OR-1001',
      '/fleet/optimization/run/OR-1002',
      '/fleet/optimization/parameters',
      '/fleet/pooling',
      '/fleet/vehicles',
      '/fleet/vehicles/C1',
      '/fleet/vehicles/new',
      '/fleet/drivers',
      '/fleet/drivers/DR3',
      '/fleet/parking',
      '/fleet/monitoring',
      '/fleet/monitoring?tab=incidents',
      '/fleet/monitoring?tab=tickets',
      '/fleet/monitoring/incident/IC-1001',
      '/fleet/reports',
      '/fleet/settings',
      '/fleet/notifications',
    ];
    for (final size in [phoneSize, tabletSize, desktopSize]) {
      testWidgets('all screens at ${size.width.toInt()}px', (t) async {
        await pumpApp(t, location: locations.first, size: size);
        for (final loc in locations) {
          await _go(t, loc);
          expect(find.byType(FleetShell), findsOneWidget, reason: loc);
        }
      });
    }
    testWidgets('all screens at 1440px with text scale 1.3', (t) async {
      t.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpApp(t, location: locations.first, size: desktopSize);
      for (final loc in locations) {
        await _go(t, loc);
      }
    });
    testWidgets('all screens at 390px with text scale 1.3', (t) async {
      t.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpApp(t, location: locations.first, size: phoneSize);
      for (final loc in locations) {
        await _go(t, loc);
      }
    });
  });
}
