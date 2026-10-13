import 'package:executive_fleet/app/providers.dart';
import 'package:executive_fleet/app/router.dart';
import 'package:executive_fleet/domain/models/models.dart';
import 'package:executive_fleet/features/fleet_admin/fleet_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/widget_harness.dart';

/// v3 (MoM 13 Oct 2026) Fleet Manager part B: safety & SOS, dynamic
/// seat matching, overview cards — driven through the UI.

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

Future<void> _go(WidgetTester t, String path) async {
  _c(t).read(routerProvider).go(path);
  await t.pumpAndSettle();
}

void main() {
  setUp(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);

  testWidgets('policy: FM is mandatory; valid save is confirmed and audited', (
    t,
  ) async {
    await pumpApp(t, location: '/fleet/safety', size: desktopSize);
    final save = find.widgetWithText(FilledButton, 'Save policy');
    expect(
      t.widget<FilledButton>(save).onPressed,
      isNull,
      reason: 'nothing changed yet',
    );

    await _tap(t, find.widgetWithText(FilterChip, 'Fleet Manager (mandatory)'));
    await _tap(t, save);
    expect(
      find.text('The Fleet Manager must always receive SOS alerts.'),
      findsOneWidget,
    );
    expect(_data(t).policy.sosRecipients, contains(SosRecipient.fleetManager));

    await _tap(t, find.widgetWithText(FilterChip, 'Fleet Manager (mandatory)'));
    await t.enterText(find.widgetWithText(TextField, 'Speed limit'), '70');
    await t.enterText(find.widgetWithText(TextField, 'Threshold'), '0');
    await t.pumpAndSettle();
    final auditBefore = _data(t).auditTrail.length;
    await _tap(t, save);
    expect(find.text('Save fleet safety policy?'), findsOneWidget);
    await _tap(t, _inDialog(find.text('Cancel')));
    expect(_data(t).policy.speedLimitKmh, isNot(70));
    await _tap(t, save);
    await _tap(t, _inDialog(find.widgetWithText(FilledButton, 'Save policy')));
    final p = _data(t).policy;
    expect(p.speedLimitKmh, 70);
    expect(p.alcoholThresholdMg, 0);
    expect(_data(t).auditTrail.length, greaterThan(auditBefore));
    expect(find.text('Policy not saved'), findsNothing);
  });

  testWidgets('alcohol fail → blocked list → clear with review note', (
    t,
  ) async {
    await pumpApp(t, location: '/fleet/overview', size: desktopSize);
    final r = await _svc(t).alcohol.record(driverId: 'DR1', readingMg: 25);
    expect(r.isOk, isTrue, reason: r.message);
    expect(r.valueOrNull!.result, AlcoholResult.fail);
    await t.pumpAndSettle();
    // Overview card counts the block.
    final card = find
        .ancestor(
          of: find.text('Alcohol blocks'),
          matching: find.byType(Column),
        )
        .first;
    expect(find.descendant(of: card, matching: find.text('1')), findsOneWidget);
    await _tap(t, find.text('Alcohol blocks'));
    expect(find.text('Blocked drivers (1)'), findsOneWidget);
    expect(find.textContaining('SIMULATED breathalyzer'), findsOneWidget);
    expect(
      _svc(t).driverOps.startBlockers('TR-1001', 'DR1').join(' '),
      isNotEmpty,
    );

    await _tap(t, find.byKey(ValueKey('clear-${r.valueOrNull!.id}')));
    await _tap(t, _inDialog(find.widgetWithText(FilledButton, 'Clear block')));
    expect(find.text('Enter at least 5 characters'), findsOneWidget);
    await t.enterText(
      _inDialog(find.widgetWithText(TextFormField, 'Review note')),
      'Supervised re-test pending; mouthwash (demo)',
    );
    await _tap(t, _inDialog(find.widgetWithText(FilledButton, 'Clear block')));
    final cleared = _data(
      t,
    ).alcoholTests.firstWhere((a) => a.id == r.valueOrNull!.id);
    expect(cleared.blocking, isFalse);
    expect(find.textContaining('Blocked drivers'), findsNothing);

    // Filters + incident link.
    await _tap(
      t,
      find
          .ancestor(
            of: find.text('Result'),
            matching: find.byWidgetPredicate(
              (w) => w is DropdownButtonFormField,
            ),
          )
          .first,
    );
    await t.tap(find.text('Fail').last);
    await t.pumpAndSettle();
    expect(find.textContaining('Fail · cleared'), findsWidgets);
    if (cleared.incidentId != null) {
      await _tapText(t, cleared.incidentId!);
      expect(find.textContaining('${cleared.incidentId} ·'), findsWidgets);
    }
  });

  testWidgets(
    'SOS chain shows statuses; acknowledge in-app alert; police not contacted',
    (t) async {
      await pumpApp(t, location: '/fleet/overview', size: desktopSize);
      final r = await _svc(t).incidents.raiseSos(
        actor: Actor.employee('E5'),
        tripId: 'TR-1002',
        note: 'Passenger feels unsafe (demo)',
      );
      expect(r.isOk, isTrue, reason: r.message);
      final id = r.valueOrNull!.id;
      await t.pumpAndSettle();
      await _tap(t, find.text('Open SOS'));
      expect(
        find.textContaining('SOS ${r.valueOrNull!.reference}'),
        findsOneWidget,
      );
      expect(find.text('Not contacted — integration required'), findsWidgets);
      final fm = _data(t)
          .sosDispatchesOf(id)
          .firstWhere((d) => d.recipient == SosRecipient.fleetManager);
      expect(fm.status, SosDispatchStatus.alertedInApp);
      await _tap(t, find.byKey(ValueKey('ack-${fm.id}')));
      expect(
        _data(t).sosDispatchesOf(id).firstWhere((d) => d.id == fm.id).status,
        SosDispatchStatus.acknowledged,
      );

      // Monitoring shows the chain inline.
      await _go(t, '/fleet/monitoring/incident/$id');
      expect(find.text('SOS escalation chain'), findsOneWidget);
      expect(find.text('Acknowledged'), findsWidgets);
      await _go(t, '/fleet/monitoring?tab=incidents');
      expect(find.textContaining('acknowledged'), findsWidgets);
    },
  );

  testWidgets(
    'seat match: booking finds a feasible seat in an existing trip and is assigned',
    (t) async {
      await pumpApp(t, location: '/fleet/overview', size: desktopSize);
      final tomorrow = _data(t).today.add(const Duration(days: 1));
      final base = await _svc(t).assignments.commit(
        AssignmentRequest(
          employerId: 'C1',
          serviceDate: tomorrow,
          employeeIds: const ['E1'],
          driverId: 'DR3',
          vehicleId: 'C3',
        ),
      );
      expect(base.isOk, isTrue, reason: base.message);
      final bk = await _svc(t).bookings.submit(
        BookingDraft(
          employeeId: 'E2',
          pickupLocationId: 'PK02',
          destinationId: 'G2',
          date: tomorrow,
          arrivalMinutes: 540,
        ),
      );
      expect(bk.isOk, isTrue, reason: bk.message);
      final ref = bk.valueOrNull!.reference;
      await _go(t, '/fleet/dispatch');
      await _tap(t, find.byTooltip('Actions for $ref'));
      await t.tap(find.text('Find seat in existing trip…').last);
      await t.pumpAndSettle();
      expect(
        find.text('Find a seat for ${bk.valueOrNull!.id}'),
        findsOneWidget,
      );
      final tripId = base.valueOrNull!.id;
      expect(
        find.byKey(ValueKey('assign-$tripId')),
        findsOneWidget,
        reason: 'base trip is feasible',
      );
      expect(find.text('Feasible'), findsWidgets);
      await _tap(t, find.byKey(ValueKey('assign-$tripId')));
      final trip = _data(t).trips.byId(tripId)!;
      expect(trip.employeeIds, containsAll(['E1', 'E2']));
      expect(_data(t).booking(bk.valueOrNull!.id)!.tripId, tripId);
      expect(find.text('Seat utilization · Today'), findsOneWidget);
    },
  );

  testWidgets('best match + released seats from an absence', (t) async {
    await pumpApp(t, location: '/fleet/overview', size: desktopSize);
    final tomorrow = _data(t).today.add(const Duration(days: 1));
    final base = await _svc(t).assignments.commit(
      AssignmentRequest(
        employerId: 'C1',
        serviceDate: tomorrow,
        employeeIds: const ['E1', 'E3'],
        driverId: 'DR3',
        vehicleId: 'C3',
      ),
    );
    expect(base.isOk, isTrue, reason: base.message);
    final abs = await _svc(
      t,
    ).matching.reportAbsence(base.valueOrNull!.id, 'E3', 'On leave (demo)');
    expect(abs.isOk, isTrue, reason: abs.message);
    final bk = await _svc(t).bookings.submit(
      BookingDraft(
        employeeId: 'E2',
        pickupLocationId: 'PK02',
        destinationId: 'G2',
        date: tomorrow,
        arrivalMinutes: 540,
      ),
    );
    await _go(t, '/fleet/dispatch/trip/${base.valueOrNull!.id}');
    expect(find.text('Absent · seat released'), findsOneWidget);
    await _go(t, '/fleet/dispatch');
    await _tapText(t, 'Tomorrow · ${_data(t).trips.onDay(tomorrow).length}');
    expect(find.text('1 released'), findsOneWidget);
    await _tap(t, find.byTooltip('Actions for ${bk.valueOrNull!.reference}'));
    await t.tap(find.text('Find seat in existing trip…').last);
    await t.pumpAndSettle();
    await _tap(t, find.widgetWithText(FilledButton, 'Best match'));
    expect(_data(t).booking(bk.valueOrNull!.id)!.tripId, isNotNull);
  });

  testWidgets('overview safety cards link to safety and telematics', (t) async {
    await pumpApp(t, location: '/fleet/overview', size: desktopSize);
    for (final label in ['Alcohol blocks', 'Open SOS', 'Telematics events']) {
      expect(find.text(label), findsOneWidget);
    }
    await _tap(t, find.text('Open SOS'));
    expect(find.text('Safety & SOS'), findsWidgets);
    await _go(t, '/fleet/overview');
    await _tap(t, find.text('Telematics events'));
    expect(
      _c(t).read(routerProvider).routerDelegate.currentConfiguration.uri.path,
      '/fleet/telematics',
    );
  });

  group('Overflow v3', () {
    const locations = [
      '/fleet/safety',
      '/fleet/safety?tab=alcohol',
      '/fleet/safety?tab=sos',
      '/fleet/overview',
      '/fleet/dispatch',
      '/fleet/monitoring',
      '/fleet/monitoring?tab=incidents',
    ];
    for (final size in [phoneSize, tabletSize, desktopSize]) {
      testWidgets('v3 screens at ${size.width.toInt()}px', (t) async {
        await pumpApp(t, location: locations.first, size: size);
        await _svc(t).alcohol.record(driverId: 'DR1', readingMg: 25);
        await _svc(
          t,
        ).incidents.raiseSos(actor: Actor.driver('DR2'), tripId: 'TR-1002');
        for (final loc in locations) {
          await _go(t, loc);
          expect(find.byType(FleetShell), findsOneWidget, reason: loc);
        }
        final sos = _data(
          t,
        ).incidents.firstWhere((i) => i.isSos && i.status.isOpen);
        await _go(t, '/fleet/monitoring/incident/${sos.id}');
      });
    }
  });
}
