import 'package:executive_fleet/app/providers.dart';
import 'package:executive_fleet/app/router.dart';
import 'package:executive_fleet/domain/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'employee_harness.dart';

/// v3 (client MoM): SOS escalation chain, absence seat release, ad-hoc
/// seat matching.

Future<void> go(WidgetTester t, String path) async {
  containerOf(t).read(routerProvider).go(path);
  await t.pumpAndSettle();
}

Future<void> reveal(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      f,
      250,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await t.ensureVisible(f.first);
  await t.pumpAndSettle();
}

Future<void> tapText(WidgetTester t, String text, {bool last = false}) async {
  final f = find.text(text);
  await reveal(t, f);
  await t.tap(last ? f.last : f.first);
  await t.pumpAndSettle();
}

Future<void> scrollToBottom(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.drag(
      find.byType(Scrollable).first,
      const Offset(0, -600),
      warnIfMissed: false,
    );
    await t.pumpAndSettle();
  }
}

Future<void> raiseSos(WidgetTester t) async {
  await go(t, '/employee/safety');
  await tapText(t, 'Raise SOS');
  await tapText(t, 'Raise SOS', last: true);
}

/// Base trip tomorrow for E1 on Vehicle C3 with DR3 (seat-matching host).
Future<Trip> createBaseTrip(WidgetTester t) async {
  final data = dataOf(t);
  final r = await servicesOf(t).assignments.commit(
    AssignmentRequest(
      employerId: 'C1',
      serviceDate: data.today.add(const Duration(days: 1)),
      employeeIds: const ['E1'],
      driverId: 'DR3',
      vehicleId: 'C3',
    ),
  );
  expect(r.isOk, isTrue, reason: r.message);
  return r.valueOrNull!;
}

void main() {
  testWidgets(
    'SOS shows escalation chain; acknowledgement updates it live; Home + notification',
    (t) async {
      await signInAs(t, 'Asha Rao');
      await raiseSos(t);
      expect(find.textContaining('SOS recorded'), findsOneWidget);
      expect(find.text('In a real emergency'), findsOneWidget);
      expect(
        find.textContaining('Demo only — no real emergency service'),
        findsWidgets,
      );

      final sos = dataOf(
        t,
      ).incidents.firstWhere((i) => i.isSos && i.reportedById == 'E1');
      final chain = dataOf(t).sosDispatchesOf(sos.id);
      expect(chain, isNotEmpty);
      await reveal(t, find.text('ESCALATION'));
      for (final d in chain) {
        await reveal(t, find.text(d.recipient.label));
        expect(find.text(d.recipient.label), findsOneWidget);
      }
      final police = chain.where((d) => d.recipient == SosRecipient.police);
      if (police.isNotEmpty) {
        await reveal(t, find.text('Not contacted — integration required'));
        expect(
          find.text('Not contacted — integration required'),
          findsOneWidget,
        );
      }
      expect(find.text('Alerted in app (local)'), findsWidgets);

      final fm = chain.firstWhere(
        (d) => d.recipient == SosRecipient.fleetManager,
      );
      final ack = await servicesOf(t).incidents.acknowledgeSos(fm.id);
      expect(ack.isOk, isTrue, reason: ack.message);
      await t.pumpAndSettle();
      await reveal(t, find.textContaining('Acknowledged'));
      expect(find.textContaining(RegExp(r'^Acknowledged')), findsOneWidget);
      expect(find.textContaining('1 of'), findsOneWidget);

      await go(t, '/employee/home');
      expect(find.textContaining('SOS active'), findsOneWidget);
      await go(t, '/employee/notifications');
      final n = find.textContaining('SOS acknowledged');
      expect(n, findsOneWidget);
      await t.tap(n);
      await t.pumpAndSettle();
      expect(find.text('Safety centre'), findsOneWidget);
      expect(find.text('ESCALATION'), findsOneWidget);
    },
  );

  testWidgets(
    'absence releases the seat, persists, and moves trip to history',
    (t) async {
      final storage = await pumpEmployeeApp(t);
      await tapText(t, 'Kiran Mehta');
      expect(find.textContaining('TR-1001'), findsWidgets);
      await tapText(t, "I'm not travelling");
      await t.enterText(
        find.byType(TextFormField).first,
        'Working from home today',
      );
      await tapText(t, 'Release my seat');
      final trip = dataOf(t).trips.byId('TR-1001')!;
      expect(trip.employeeIds, isNot(contains('E2')));
      expect(trip.absentEmployeeIds, contains('E2'));
      expect(trip.employeeIds, containsAll(['E1', 'E3']));
      expect(find.text('No upcoming trip assigned'), findsOneWidget);
      await dataOf(t).db.flush();

      await t.pumpWidget(const SizedBox());
      await pumpEmployeeApp(t, location: '/employee/trips', storage: storage);
      expect(
        dataOf(t).trips.byId('TR-1001')!.absentEmployeeIds,
        contains('E2'),
      );
      await t.tap(find.textContaining('Cancelled'));
      await t.pumpAndSettle();
      expect(find.text('You were absent · seat released'), findsOneWidget);
      await t.tap(find.textContaining('TR-1001'));
      await t.pumpAndSettle();
      expect(
        find.text('You marked yourself absent — seat released'),
        findsOneWidget,
      );
      expect(find.text('Show e-pass'), findsNothing);
      expect(find.text("I'm not travelling"), findsNothing);
    },
  );

  testWidgets('absence reason dialog can be cancelled without change', (
    t,
  ) async {
    await signInAs(t, 'Kiran Mehta');
    await go(t, '/employee/trip/TR-1001');
    await tapText(t, "I'm not travelling");
    await tapText(t, 'Cancel');
    expect(dataOf(t).trips.byId('TR-1001')!.employeeIds, contains('E2'));
  });

  testWidgets(
    'ad-hoc booking is matched instantly to an existing trip when policy allows',
    (t) async {
      await pumpEmployeeApp(t);
      final s = servicesOf(t);
      final saved = await s.policy.save(
        dataOf(t).policy.copyWith(autoMatchAdhoc: true),
      );
      expect(saved.isOk, isTrue, reason: saved.message);
      final base = await createBaseTrip(t);
      await t.pumpAndSettle();

      await tapText(t, 'Kiran Mehta');
      await tapText(t, 'Book');
      // Defaults for E2: tomorrow, PK02 → G2, arrive by 9:00 AM.
      expect(find.text('PK02 · Riverside Colony'), findsOneWidget);
      expect(find.text('9:00 AM'), findsOneWidget);
      await tapText(t, 'Review request');
      await t.tap(find.textContaining(RegExp(r'^Submit')));
      await t.pumpAndSettle();
      expect(
        find.text('Matched instantly to ${base.tripCode}'),
        findsOneWidget,
      );
      expect(
        dataOf(t).trips.byId(base.id)!.employeeIds,
        containsAll(['E1', 'E2']),
      );
      final b = dataOf(
        t,
      ).bookingsOf('E2').firstWhere((b) => b.tripId == base.id);
      expect(b.status, BookingStatus.assigned);

      await tapText(t, 'View trip');
      expect(find.widgetWithText(AppBar, base.tripCode), findsOneWidget);
      await go(t, '/employee/booking/${b.id}');
      expect(
        find.text('Matched to a free seat on an existing trip'),
        findsOneWidget,
      );
    },
  );

  testWidgets('ad-hoc booking without auto-match keeps the honest message', (
    t,
  ) async {
    await signInAs(t, 'Kiran Mehta');
    await tapText(t, 'Book');
    await tapText(t, 'Review request');
    await t.tap(find.textContaining(RegExp(r'^Submit')));
    await t.pumpAndSettle();
    expect(
      find.textContaining(RegExp(r'^Request (submitted|waitlisted)')),
      findsOneWidget,
    );
    expect(find.textContaining('Matched instantly'), findsNothing);
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('v3 screens have no overflow at 390 px, text scale $scale', (
      t,
    ) async {
      await pumpEmployeeApp(t, textScale: scale);
      await servicesOf(
        t,
      ).policy.save(dataOf(t).policy.copyWith(autoMatchAdhoc: true));
      await createBaseTrip(t);
      await t.pumpAndSettle();
      await tapText(t, 'Kiran Mehta');
      await go(t, '/employee/home');
      await reveal(t, find.text("I'm not travelling"));
      expect(t.takeException(), isNull, reason: 'home absence action');
      await raiseSos(t);
      await scrollToBottom(t);
      expect(t.takeException(), isNull, reason: 'safety chain');
      await go(t, '/employee/home');
      expect(t.takeException(), isNull, reason: 'home SOS banner');
      await servicesOf(t).matching.reportAbsence('TR-1001', 'E2', 'Leave');
      await go(t, '/employee/trip/TR-1001');
      await scrollToBottom(t);
      expect(t.takeException(), isNull, reason: 'absent trip detail');
      await go(t, '/employee/book');
      await tapText(t, 'Review request');
      await t.tap(find.textContaining(RegExp(r'^Submit')));
      await t.pumpAndSettle();
      expect(find.textContaining('Matched instantly'), findsOneWidget);
      await scrollToBottom(t);
      expect(t.takeException(), isNull, reason: 'matched card');
    });
  }
}
