// QA audit: drives the Driver app UI (taps + text entry). Services are used
// only to set up state or to assert persisted results.
import 'package:executive_fleet/app/app.dart';
import 'package:executive_fleet/app/providers.dart';
import 'package:executive_fleet/app/router.dart';
import 'package:executive_fleet/core/demo/demo_labels.dart';
import 'package:executive_fleet/domain/models/models.dart';
import 'package:executive_fleet/domain/rules/inspection_rules.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/widget_harness.dart';

const _v = VerificationService();

ProviderContainer _c(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(FleetApp)));
DataView _data(WidgetTester t) => _c(t).read(dataProvider);
AppServices _svc(WidgetTester t) => _c(t).read(servicesProvider);

Future<void> _go(WidgetTester t, String loc) async {
  _c(t).read(routerProvider).go(loc);
  await t.pumpAndSettle();
}

final _vertical = find.byWidgetPredicate(
  (w) =>
      w is Scrollable &&
      axisDirectionIsReversed(w.axisDirection) == false &&
      (w.axisDirection == AxisDirection.down),
);

/// Scrolls the front-most vertical list until [f] is built (lazy lists).
Future<void> _reveal(WidgetTester t, Finder f) async {
  // Page scrollables only: skip text fields' internal scrollables and pick
  // the front-most, tallest one.
  final pages = _vertical.evaluate().where((e) {
    var underField = false;
    e.visitAncestorElements((a) {
      if (a.widget is EditableText) underField = true;
      return !underField;
    });
    final box = e.renderObject;
    return !underField &&
        box is RenderBox &&
        box.hasSize &&
        box.size.height > 120;
  }).toList();
  if (f.evaluate().isEmpty && pages.isNotEmpty) {
    final state = (pages.last as StatefulElement).state as ScrollableState;
    final pos = state.position;
    // Lazy lists keep their scroll offset across navigation: sweep from the
    // top down until the target is built.
    pos.jumpTo(pos.minScrollExtent);
    await t.pumpAndSettle();
    while (f.evaluate().isEmpty && pos.pixels < pos.maxScrollExtent) {
      pos.jumpTo(
        (pos.pixels + 250).clamp(pos.minScrollExtent, pos.maxScrollExtent),
      );
      await t.pump();
    }
    await t.pumpAndSettle();
  }
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await _reveal(t, f);
  expect(f, findsWidgets, reason: "missing $f");
  await t.ensureVisible(f.first);
  await t.pumpAndSettle();
  await t.tap(f.first);
  await t.pumpAndSettle();
}

Future<void> _tapText(WidgetTester t, String text) => _tap(t, find.text(text));
Future<void> _tapButton(WidgetTester t, String text) => _tap(
  t,
  find.ancestor(
    of: find.text(text),
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  ),
);

Future<void> _enter(WidgetTester t, Finder field, String text) async {
  await _reveal(t, field);
  await t.ensureVisible(field.first);
  await t.enterText(field.first, text);
  await t.pumpAndSettle();
}

Finder _field(String label) => find.widgetWithText(TextField, label);

Future<void> _passengerMenu(WidgetTester t, String item) async {
  await _tap(t, find.byTooltip('Passenger actions'));
  await _tap(t, find.text(item));
}

Future<void> _scan(WidgetTester t, Finder option) async {
  await _tapText(t, 'Scan QR');
  await _tap(t, option);
}

Future<void> _tpin(WidgetTester t, String pin) async {
  await _tapText(t, 'Enter T-PIN');
  await t.enterText(find.byKey(const Key('tpinField')), pin);
  await _tapButton(t, 'Verify T-PIN');
}

Future<void> _reasonDialog(
  WidgetTester t,
  String reason,
  String confirm, {
  String? authorizer,
}) async {
  await t.enterText(find.widgetWithText(TextFormField, 'Reason').first, reason);
  if (authorizer != null) {
    await t.enterText(
      find.widgetWithText(TextFormField, 'Authorized by'),
      authorizer,
    );
  }
  await t.pumpAndSettle();
  await _tap(t, find.widgetWithText(FilledButton, confirm));
}

void main() {
  testWidgets(
    'AUDIT 1 · DR1 full day via UI: shift → inspection → every stop scenario → completion → end shift',
    (t) async {
      await pumpApp(t, location: '/driver');

      // Login.
      expect(find.text('Driver sign-in'), findsOneWidget);
      await _tapText(t, 'DR1 · Ravi Kumar');
      expect(find.text('Start shift'), findsOneWidget);

      // Start shift + duplicate check-in guard.
      await _tapButton(t, 'Start shift');
      expect(_data(t).todayShift('DR1')!.actualCheckIn, isNotNull);
      expect(find.text('Start shift'), findsNothing);
      expect(
        (await _svc(t).driverOps.checkIn('DR1')).errors.single,
        contains('Already checked in'),
      );
      await _tapText(t, 'Attendance');
      expect(find.text('Already checked in'), findsOneWidget);
      expect(find.text('Check in now'), findsNothing);

      // Attendance regularization (DR1 checked in 6:30, 30 min late).
      expect(find.text('30 min late'), findsOneWidget);
      await _tapButton(t, 'Request regularization');
      await _reasonDialog(
        t,
        'Depot gate was locked until 6:25 (demo).',
        'Send request',
      );
      expect(
        _data(t).todayShift('DR1')!.regularizationStatus,
        RegularizationStatus.pending,
      );
      expect(find.text('Request regularization'), findsNothing);
      await _tap(t, find.byTooltip('Back'));

      // Inspection pass.
      await _tapButton(t, 'Inspect Vehicle C1');
      await _tapButton(t, 'Submit inspection');
      expect(find.text('Inspection passed'), findsOneWidget);
      await _tapButton(t, 'Back to Home');

      // Start TR-1001.
      expect(find.text('Cannot start yet'), findsNothing);
      await _tapButton(t, 'Start trip TR-1001');
      expect(find.text('Arrived at stop'), findsOneWidget);
      final trip0 = _data(t).trips.byId('TR-1001')!;
      expect(trip0.status, TripStatus.inProgress);

      // Vehicle-moving lock hides detailed controls; Arrived stays usable.
      await _tap(t, find.byType(Switch));
      expect(find.text('Eyes on the road'), findsOneWidget);
      await _tapButton(t, 'Understood');
      expect(find.text('Stop safely before interacting'), findsOneWidget);
      expect(find.text('Report delay').hitTestable(), findsNothing);
      expect(find.text('Demo navigation').hitTestable(), findsNothing);
      expect(find.text('Arrived at stop').hitTestable(), findsOneWidget);
      await _tapButton(t, 'I have stopped the vehicle');
      expect(find.text('Stop safely before interacting'), findsNothing);

      // Demo navigation sheet (simulated).
      await _tapText(t, 'Demo navigation');
      expect(find.text('Simulated directions'), findsOneWidget);
      await t.tapAt(const Offset(195, 30));
      await t.pumpAndSettle();

      // Report delay from the active trip.
      await _tapButton(t, 'Report delay');
      await _enter(
        t,
        _field('Description'),
        'Slow traffic near Cedar Park Gate',
      );
      await _tapButton(t, 'Submit report');
      expect(find.textContaining('Delay recorded · IC-'), findsOneWidget);
      expect(find.text(DemoLabels.incidentDemo), findsWidgets);
      expect(_data(t).trips.byId('TR-1001')!.status, TripStatus.delayed);
      await _tapButton(t, 'Back to trip');

      final stops = _data(t).trips.stopsOf(trip0);
      final pickups = stops.where((s) => s.kind == StopKind.pickup).toList();
      expect(pickups.length, 3);
      final a = _data(t).employee(pickups[0].boardingEmployeeIds.single)!;
      final b = _data(t).employee(pickups[1].boardingEmployeeIds.single)!;
      final c = _data(t).employee(pickups[2].boardingEmployeeIds.single)!;

      // ---- Stop 1: every QR scenario + T-PIN wrong/right + correct status.
      await _tapButton(t, 'Arrived at stop');
      expect(find.text('Stop 1'), findsOneWidget);
      await _tpin(t, _v.tpin(trip0, a) == '1234' ? '4321' : '1234');
      expect(find.text('Invalid — not boarded'), findsOneWidget);
      await _scan(t, find.text('Altered / invalid code'));
      expect(find.text('Invalid — not boarded'), findsOneWidget);
      await _scan(t, find.text('Expired pass (yesterday)'));
      expect(find.text('Expired pass — not boarded'), findsOneWidget);
      await _scan(t, find.textContaining('Pass for another trip'));
      expect(find.text('Wrong trip — not boarded'), findsOneWidget);
      expect(_data(t).trips.byId('TR-1001')!.boardedPassengerIds, isEmpty);
      // Pasted code (valid).
      await _tapText(t, 'Scan QR');
      await _enter(t, _field('Paste pass code'), _v.qrPayload(trip0, a));
      await _tapButton(t, 'Verify pasted code');
      expect(find.text('Verified · boarded'), findsOneWidget);
      await _scan(t, find.textContaining('Duplicate ·'));
      expect(find.text('Duplicate — not boarded again'), findsOneWidget);
      expect(_data(t).trips.byId('TR-1001')!.boardedPassengerIds, [a.id]);
      // Correct status → awaiting, then valid scenario + right T-PIN path.
      await _passengerMenu(t, 'Correct status');
      await _reasonDialog(t, 'Scanned wrong card', 'Reset status');
      expect(_data(t).trips.byId('TR-1001')!.boardedPassengerIds, isEmpty);
      await _tpin(t, _v.tpin(trip0, a));
      expect(find.text('Verified · boarded'), findsOneWidget);
      await _tapButton(t, 'Complete stop');
      expect(
        _data(t).db.routeStops[pickups[0].id]!.status,
        StopStatus.completed,
      );

      // ---- Stop 2: no-show → correct → manual override (authorized).
      await _tapButton(t, 'Arrived at stop');
      await _passengerMenu(t, 'Mark no-show');
      await _tap(t, find.widgetWithText(FilledButton, 'Mark no-show'));
      expect(_data(t).trips.byId('TR-1001')!.noShowPassengerIds, [b.id]);
      expect(find.text('No show'), findsOneWidget);
      await _passengerMenu(t, 'Correct status');
      await _reasonDialog(t, 'Passenger arrived late', 'Reset status');
      await _passengerMenu(t, 'Manual override (authorized)');
      await _reasonDialog(
        t,
        'Phone battery dead, ID checked',
        'Board passenger',
        authorizer: 'FM on call',
      );
      final ev = _data(t).trips.eventsOf(_data(t).trips.byId('TR-1001')!).last;
      expect(ev.verificationMethod, VerificationMethod.manualAuthorized);
      expect(ev.authorizedBy, 'FM on call');
      await _tapButton(t, 'Complete stop');

      // ---- Stop 3: nobody boards → discrepancy reason required.
      await _tapButton(t, 'Arrived at stop');
      expect(find.text('Passenger mismatch'), findsOneWidget);
      await _tapButton(t, 'Complete stop');
      expect(find.text('Complete with mismatch?'), findsOneWidget);
      await t.enterText(
        find.widgetWithText(TextFormField, 'Reason for the mismatch'),
        'Passenger not reachable',
      );
      await _tap(t, find.widgetWithText(FilledButton, 'Record & complete'));
      expect(
        _data(t).db.routeStops[pickups[2].id]!.issueNote,
        contains('Passenger not reachable'),
      );

      // ---- Drops: record drop-off; skip c's drop with authorizer.
      for (final s in stops.where((s) => s.kind == StopKind.drop)) {
        await _tapButton(t, 'Arrived at stop');
        if (s.alightingEmployeeIds.contains(c.id)) {
          await _tapText(t, 'Skip stop (authorized)');
          await _reasonDialog(
            t,
            'Passenger never boarded',
            'Skip stop',
            authorizer: 'FM on call',
          );
          expect(_data(t).db.routeStops[s.id]!.status, StopStatus.skipped);
        } else {
          await _tap(t, find.textContaining('Record drop-off'));
          await _tapButton(t, 'Complete stop');
        }
      }
      final tr = _data(t).trips.byId('TR-1001')!;
      expect(tr.alightedPassengerIds.toSet(), {a.id, b.id});

      // ---- Completion: requirement blocks without exception, then exception + odometer.
      await _tapButton(t, 'Complete trip');
      expect(find.textContaining('Not accounted for: ${c.id}'), findsOneWidget);
      await _enter(
        t,
        find.byKey(const Key('endOdometer')),
        '${tr.startOdometerKm! + 24.6}',
      );
      expect(find.textContaining('Trip distance 24.6 km'), findsOneWidget);
      await _tapButton(t, 'Complete trip');
      await _reveal(t, find.text('Trip not completed'));
      expect(find.text('Trip not completed'), findsOneWidget);
      await _enter(
        t,
        _field('Exception reason (min 10 characters)'),
        'Passenger unreachable at pickup',
      );
      await _enter(t, _field('Authorized by'), 'FM on call');
      await _tapButton(t, 'Complete trip');
      expect(find.text('Trip completed'), findsOneWidget);
      expect(find.textContaining('Billing generated (BL-'), findsOneWidget);
      expect(
        _data(t).billingForTrip('TR-1001')!.totalAmount,
        closeTo(24.6 * 18, 0.01),
      );
      await _tapButton(t, 'Back to Home');

      // ---- Activity tabs + notifications opening the right record.
      await _tap(t, find.text('Activity').last);
      for (final tab in [
        'Trips',
        'Attendance',
        'Inspections',
        'Incidents',
        'Tickets',
      ]) {
        await _tap(t, find.widgetWithText(ChoiceChip, tab));
        expect(t.takeException(), isNull);
      }
      await _tap(t, find.widgetWithText(ChoiceChip, 'Incidents'));
      expect(find.textContaining('· Delay'), findsOneWidget);
      await _tap(t, find.widgetWithText(ChoiceChip, 'Inspections'));
      expect(find.textContaining('Vehicle C1 ·'), findsWidgets);
      await _tapText(t, 'Notifications');
      await _tapText(t, 'New trip TR-1001');
      expect(find.text('VEHICLE & ROUTE'), findsOneWidget);
      expect(find.text('TR-1001'), findsWidgets);
      await _go(t, '/driver/home');

      // ---- Shift summary → end shift → Home shows complete.
      await _tapButton(t, 'Review & end shift');
      expect(find.text('Shift summary'), findsOneWidget);
      await _tapButton(t, 'End shift');
      await _tap(t, find.widgetWithText(FilledButton, 'End shift').last);
      expect(find.text('Shift complete'), findsOneWidget);
      expect(_data(t).driver('DR1')!.status, DriverStatus.offDuty);
      expect(_data(t).todayShift('DR1')!.status, ShiftStatus.completed);
    },
  );

  testWidgets(
    'AUDIT 2 · critical inspection failure via UI blocks start + replacement',
    (t) async {
      await pumpApp(t, location: '/driver/login');
      await _tapText(t, 'DR1 · Ravi Kumar');
      await _tapButton(t, 'Start shift');
      await _tapButton(t, 'Inspect Vehicle C1');
      // Fail tyres without a note → validation keeps the form.
      await _tap(t, find.text('Fail').first);
      await _tapButton(t, 'Submit with 1 failure');
      await _tapButton(t, 'Submit & report defect');
      await _reveal(t, find.text('Fix before submitting'));
      expect(find.text('Fix before submitting'), findsOneWidget);
      await _enter(
        t,
        _field('What is wrong? (required)'),
        'Front-left tyre flat',
      );
      await _tapButton(t, 'Submit with 1 failure');
      await _tapButton(t, 'Submit & report defect');
      expect(find.text('Trip start blocked'), findsOneWidget);
      expect(_data(t).vehicle('C1')!.status, VehicleStatus.maintenance);
      expect(_data(t).trips.byId('TR-1001')!.status, TripStatus.needsAttention);
      await _tapButton(t, 'Request replacement vehicle');
      expect(find.text('Replacement requested'), findsWidgets);
      expect(_data(t).incidents.first.replacementRequested, isTrue);
      await _go(t, '/driver/home');
      expect(find.text('Trip start blocked'), findsOneWidget);
      expect(find.text('Start trip TR-1001'), findsNothing);
      expect(
        (await _svc(t).driverOps.startTrip('TR-1001', 'DR1')).isOk,
        isFalse,
      );
    },
  );

  testWidgets(
    'AUDIT 3 · profile switch to DR2, continue in-progress TR-1002, complete without odometer → billing blocked',
    (t) async {
      await pumpApp(t);
      await _svc(t).session.signInDriver('DR1');
      await _go(t, '/driver/profile');
      await _tapButton(t, 'Switch driver');
      expect(find.text('Driver sign-in'), findsOneWidget);
      await _tapText(t, 'DR2 · Priya Sharma');
      expect(find.text('TR-1002 IN PROGRESS'), findsOneWidget);
      await _tapButton(t, 'Open active trip');
      final trip = _data(t).trips.byId('TR-1002')!;
      final current = _data(t).trips.currentStop(trip)!;
      expect(current.sequence, 3);
      await _tapButton(t, 'Arrived at stop');
      for (final id in current.boardingEmployeeIds) {
        final e = _data(t).employee(id)!;
        await _scan(t, find.text('Valid pass · ${e.employeeCode} ${e.name}'));
        expect(find.text('Verified · boarded'), findsOneWidget);
      }
      await _tapButton(t, 'Complete stop');
      // Remaining stops via services (setup only).
      final ops = _svc(t).driverOps;
      for (final s in _data(t).trips.stopsOf(trip).where((s) => !s.isDone)) {
        await ops.arriveAtStop(s.id);
        final tt = _data(t).trips.byId('TR-1002')!;
        for (final id in s.boardingEmployeeIds) {
          await ops.verifyAndBoard(
            stopId: s.id,
            method: VerificationMethod.qrDemo,
            input: _v.qrPayload(tt, _data(t).employee(id)!),
          );
        }
        if (s.kind == StopKind.drop) {
          await ops.alight(stopId: s.id, employeeIds: s.alightingEmployeeIds);
        }
        expect((await ops.departStop(s.id)).isOk, isTrue);
      }
      await _go(t, '/driver/trip/TR-1002/active');
      await _tapButton(t, 'Complete trip');
      await _tapButton(t, 'Complete trip');
      expect(find.text('Complete without distance?'), findsOneWidget);
      await _tap(t, find.widgetWithText(FilledButton, 'Complete anyway'));
      expect(find.text('Billing blocked — distance missing'), findsOneWidget);
      expect(_data(t).billingForTrip('TR-1002'), isNull);
      expect(
        _data(t).trips.byId('TR-1002')!.billableStatus,
        BillableStatus.missingDistance,
      );
    },
  );

  testWidgets(
    'AUDIT 4 · breakdown + replacement, offline failure keeps values + Retry, SOS failure then success',
    (t) async {
      await pumpApp(t);
      final s = _svc(t);
      await s.session.signInDriver('DR1');
      await s.driverOps.checkIn('DR1');
      await s.driverOps.submitInspection(
        driverId: 'DR1',
        vehicleId: 'C1',
        items: InspectionRules.blankChecklist(),
      );
      await s.driverOps.startTrip('TR-1001', 'DR1');

      // Offline failure keeps values; Retry succeeds.
      await s.session.setFlag(IncidentService.simulateOfflineKey, true);
      await _go(t, '/driver/report?type=delay&trip=TR-1001');
      await _enter(t, _field('Expected delay (minutes)'), '25');
      await _enter(t, _field('Description'), 'Accident blocking the main road');
      await _tapButton(t, 'Submit report');
      expect(find.text('Not submitted'), findsOneWidget);
      expect(find.text('Accident blocking the main road'), findsOneWidget);
      expect(find.text('25'), findsOneWidget);
      await s.session.setFlag(IncidentService.simulateOfflineKey, false);
      await _tapButton(t, 'Retry');
      expect(find.textContaining('Delay recorded · IC-'), findsOneWidget);
      expect(_data(t).incidents.first.description, contains('25 min'));

      // SOS failure (offline) → alternatives → Retry success.
      await s.session.setFlag(IncidentService.simulateOfflineKey, true);
      await _go(t, '/driver/sos?trip=TR-1001');
      await _tapButton(t, 'Raise SOS now');
      await t.pump(const Duration(milliseconds: 700));
      await t.pumpAndSettle();
      expect(find.text('SOS could not be recorded'), findsOneWidget);
      expect(find.text('Use an alternative now'), findsOneWidget);
      await s.session.setFlag(IncidentService.simulateOfflineKey, false);
      await _tapButton(t, 'Retry');
      await t.pump(const Duration(milliseconds: 700));
      await t.pumpAndSettle();
      expect(
        find.text('No real emergency service was contacted'),
        findsOneWidget,
      );
      expect(_data(t).incidents.first.isSos, isTrue);
      await _tapButton(t, 'Request control-room call-back (simulated)');
      expect(
        find.textContaining('Simulated control-room contact recorded'),
        findsOneWidget,
      );

      // Breakdown with replacement.
      await _go(t, '/driver/report?type=breakdown&trip=TR-1001');
      await _enter(
        t,
        _field('Description'),
        'Warning light on, stopped safely',
      );
      await _tapText(t, 'Request a replacement vehicle');
      await _tapButton(t, 'Submit report');
      expect(find.textContaining('Breakdown recorded'), findsOneWidget);
      expect(find.text('Requested'), findsOneWidget);
      final inc = _data(t).incidents.first;
      expect(inc.replacementRequested, isTrue);
      expect(inc.severity, IncidentSeverity.high);
      expect(_data(t).vehicle('C1')!.status, VehicleStatus.maintenance);
      expect(_data(t).trips.byId('TR-1001')!.status, TripStatus.needsAttention);
    },
  );

  testWidgets('AUDIT 5 · support ticket + call-back from Support screen', (
    t,
  ) async {
    await pumpApp(t);
    await _svc(t).session.signInDriver('DR1');
    await _go(t, '/driver/activity');
    await _tapText(t, 'Support');
    await _tapButton(t, 'Request call-back (simulated)');
    expect(
      find.textContaining('Simulated control-room contact recorded'),
      findsOneWidget,
    );
    await _tapButton(t, 'Submit ticket');
    expect(find.text('Subject needs at least 4 characters'), findsOneWidget);
    await _enter(t, _field('Subject'), 'Seat belt stiff');
    await _enter(
      t,
      _field('Describe the issue'),
      'Rear-left seat belt is hard to buckle.',
    );
    await _tapButton(t, 'Submit ticket');
    expect(
      _data(t).ticketsBy(UserRole.driver, 'DR1').single.subject,
      'Seat belt stiff',
    );
    await _tap(t, find.widgetWithText(ChoiceChip, 'Tickets'));
    expect(find.textContaining('Seat belt stiff'), findsOneWidget);
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets(
      'AUDIT 6 · every driver screen at 390×844, text scale $scale, no overflow',
      (t) async {
        t.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpApp(t, size: phoneSize);
        final s = _svc(t);
        await _go(t, '/driver/login');
        await s.session.signInDriver('DR1');
        await _go(t, '/driver/home');
        await s.driverOps.checkIn('DR1');
        await _go(t, '/driver/home');
        await s.driverOps.submitInspection(
          driverId: 'DR1',
          vehicleId: 'C1',
          items: InspectionRules.blankChecklist(),
        );
        await _go(t, '/driver/home');
        await s.driverOps.startTrip('TR-1001', 'DR1');
        final trip = _data(t).trips.byId('TR-1001')!;
        final stop = _data(t).trips.stopsOf(trip).first;
        await s.driverOps.arriveAtStop(stop.id);
        for (final loc in [
          '/driver/home',
          '/driver/trips',
          '/driver/activity',
          '/driver/profile',
          '/driver/trip/TR-1001',
          '/driver/trip/TR-1001/active',
          '/driver/trip/TR-1001/stop/${stop.id}',
          '/driver/trip/TR-1001/complete',
          '/driver/attendance',
          '/driver/inspection?vehicle=C2',
          '/driver/report?type=delay&trip=TR-1001',
          '/driver/sos?trip=TR-1001',
          '/driver/shift-summary',
          '/driver/notifications',
          '/driver/support',
        ]) {
          await _go(t, loc);
          expect(t.takeException(), isNull, reason: loc);
        }
        // Sheets too.
        await _go(t, '/driver/trip/TR-1001/stop/${stop.id}');
        await _tapText(t, 'Scan QR');
        expect(t.takeException(), isNull);
      },
    );
  }
}
