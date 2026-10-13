import 'package:executive_fleet/app/router.dart';
import 'package:executive_fleet/core/demo/demo_labels.dart';
import 'package:executive_fleet/domain/models/models.dart';
import 'package:executive_fleet/features/employee/employee_common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'employee_harness.dart';

/// v2 client-architecture increment: travel preferences, schedule card,
/// pickup tolerance window, simulated traffic and schedule revisions.

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
  await t.ensureVisible(f);
  await t.pumpAndSettle();
}

Future<void> tapText(WidgetTester t, String text) async {
  final f = find.text(text);
  await reveal(t, f);
  await t.tap(f);
  await t.pumpAndSettle();
}

/// Taps a 0–3 slider inside the card titled [label] at [level].
Future<void> setLevel(WidgetTester t, String label, int level) async {
  await reveal(t, find.text(label));
  final card = find
      .ancestor(of: find.text(label), matching: find.byType(Column))
      .first;
  final slider = find.descendant(of: card, matching: find.byType(Slider));
  final rect = t.getRect(slider);
  // Material slider track is inset by ~24 px on each side.
  const inset = 24.0;
  final x = rect.left + inset + (rect.width - 2 * inset) * level / 3;
  await t.tapAt(Offset(x, rect.center.dy));
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

void main() {
  testWidgets(
    'travel preferences: save, inline success, audit, persists after restart',
    (t) async {
      final storage = await pumpEmployeeApp(t);
      await tapText(t, 'Asha Rao');
      await tapText(t, 'Profile');
      await tapText(t, 'Travel preferences');
      expect(find.text('Travel preferences'), findsWidgets);
      // Seeded E1: travel time 3, reliability 2. Proximity is shown but inactive.
      expect(find.text('Very important'), findsWidgets);
      await reveal(t, find.text('Pickup point closer to me'));
      expect(find.text('Not active'), findsOneWidget);
      expect(
        find.textContaining(
          'no effect while pickups are at your registered point',
        ),
        findsOneWidget,
      );

      await setLevel(t, 'Shorter travel distance', 2);
      expect(find.text('Discard changes'), findsOneWidget);
      await tapText(t, 'Save preferences');
      expect(find.text('Preferences saved'), findsOneWidget);
      expect(find.textContaining('NEXT optimization run'), findsOneWidget);
      expect(
        find.textContaining('existing trips are not changed'),
        findsOneWidget,
      );

      final e1 = dataOf(t).employee('E1')!;
      expect(e1.preference(TravelPreferenceKeys.distance), 2);
      expect(e1.preference(TravelPreferenceKeys.travelTime), 3);
      final audit = dataOf(t).auditFor('employee', 'E1');
      expect(
        audit.any(
          (a) =>
              a.action == 'employee.travelPreferences' &&
              a.actorRole == UserRole.employee,
        ),
        isTrue,
      );
      // Existing trip untouched.
      expect(dataOf(t).trips.byId('TR-1001')!.status, TripStatus.assigned);
      await dataOf(t).db.flush();

      await t.pumpWidget(const SizedBox());
      await pumpEmployeeApp(t, location: '/employee/profile', storage: storage);
      expect(
        dataOf(t).employee('E1')!.preference(TravelPreferenceKeys.distance),
        2,
      );
      await reveal(
        t,
        find.textContaining('Shorter travel distance: Important'),
      );
      expect(
        find.textContaining('Shorter travel distance: Important'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'profile schedule card shows shift, deadline, tolerance, fictional coordinates',
    (t) async {
      await signInAs(t, 'Asha Rao');
      await tapText(t, 'Profile');
      await reveal(t, find.text('My schedule'));
      await reveal(t, find.text('9:15 AM – 6:15 PM'));
      expect(find.text('9:15 AM – 6:15 PM'), findsOneWidget);
      expect(find.text('Arrival deadline'), findsOneWidget);
      expect(find.text('±7 min · company default'), findsOneWidget);
      expect(find.textContaining('PK01'), findsWidgets);
      await reveal(t, find.text(DemoLabels.fictionalCoordinates));
      expect(find.text('Coordinates'), findsOneWidget);
      final data = dataOf(t);
      final e = data.employee('E1')!;
      expect(effectiveDeadlineMinutes(e, data.employer('C1')), 540);
    },
  );

  testWidgets('E3 shows own tolerance override', (t) async {
    await signInAs(t, 'Neha Iyer');
    await tapText(t, 'Profile');
    await reveal(t, find.text('±5 min · your setting'));
    expect(find.text('±5 min · your setting'), findsOneWidget);
  });

  testWidgets(
    'self-declared gender edit is saved and audited; not used by algorithms',
    (t) async {
      await signInAs(t, 'Asha Rao');
      await tapText(t, 'Profile');
      await reveal(t, find.text('Self-declared gender (optional)'));
      expect(find.text('Not used by any algorithm.'), findsOneWidget);
      await tapText(t, 'Edit');
      await t.tap(find.text('Prefer not to say'));
      await t.pumpAndSettle();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(
        dataOf(t).employee('E1')!.gender,
        SelfDeclaredGender.preferNotToSay,
      );
      expect(
        dataOf(t)
            .auditFor('employee', 'E1')
            .any((a) => a.action == 'employee.update' && a.actorId == 'E1'),
        isTrue,
      );
    },
  );

  testWidgets(
    'trip detail and e-pass show the pickup window (planned ± tolerance)',
    (t) async {
      await signInAs(t, 'Asha Rao');
      final data = dataOf(t);
      final trip = data.trips.byId('TR-1001')!;
      final planned = data.trips.pickupStopFor(trip, 'E1')!.plannedArrival;
      final window = pickupWindowText(planned, 7);
      await go(t, '/employee/trip/TR-1001');
      expect(find.text('Pickup window $window'), findsOneWidget);
      expect(find.textContaining('Arrival deadline 9:00 AM'), findsOneWidget);
      await go(t, '/employee/trip/TR-1001/pass');
      await reveal(t, find.text(window));
      expect(find.text('Pickup window'), findsOneWidget);
    },
  );

  testWidgets(
    'heavy simulated traffic shows delay; applied revision shows updated pickup; notification opens trip',
    (t) async {
      await signInAs(t, 'Asha Rao');
      await go(t, '/employee/trip/TR-1001');
      await reveal(t, find.text('Simulated traffic'));
      expect(find.text('Simulated traffic'), findsOneWidget);

      final s = servicesOf(t);
      final r = await s.traffic.setScenario(
        internalRoads: TrafficLevel.heavy,
        ringRoad: TrafficLevel.heavy,
      );
      expect(r.isOk, isTrue, reason: r.message);
      await t.pumpAndSettle();
      final status = s.traffic.statusOf(dataOf(t).trips.byId('TR-1001')!);
      // Not-started trips report the impact as "leave earlier".
      expect(
        status.delayMinutes > 0 || status.earlierDepartureMinutes > 0,
        isTrue,
      );
      await go(t, '/employee/home');
      await go(t, '/employee/trip/TR-1001');
      await reveal(t, find.text('Estimated delay'));
      expect(
        find.text(
          status.earlierDepartureMinutes > 0
              ? '~${status.earlierDepartureMinutes} min if leaving as planned'
              : '~${status.delayMinutes} min',
        ),
        findsOneWidget,
      );
      expect(find.text(status.statusLabel), findsOneWidget);
      expect(find.text('Schedule under review'), findsOneWidget);

      final rev = dataOf(t).openRevision('TR-1001');
      expect(rev, isNotNull);
      expect((await s.traffic.applyRevision(rev!.id)).isOk, isTrue);
      await t.pumpAndSettle();
      await go(t, '/employee/home');
      await go(t, '/employee/trip/TR-1001');
      expect(
        find.textContaining(
          RegExp(r'(Pickup time|Schedule) updated for traffic'),
        ),
        findsOneWidget,
      );

      // Notifications about the change open the trip.
      await go(t, '/employee/notifications');
      final traffic = find.textContaining(
        RegExp(r'^(Pickup time changed|Schedule updated|Traffic update)'),
      );
      expect(traffic, findsWidgets);
      await t.tap(traffic.first);
      await t.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'TR-1001'), findsOneWidget);
      // Home surfaces the traffic alert.
      await go(t, '/employee/home');
      await reveal(t, find.text('Service alerts'));
      expect(
        find.textContaining(
          RegExp(r'(Pickup time changed|Schedule updated|Traffic update)'),
        ),
        findsWidgets,
      );
    },
  );

  testWidgets('traffic data unavailable is stated honestly', (t) async {
    await signInAs(t, 'Asha Rao');
    final r = await servicesOf(t).traffic.setScenario(
      internalRoads: TrafficLevel.free,
      ringRoad: TrafficLevel.free,
      source: TrafficSource.unavailable,
    );
    expect(r.isOk, isTrue, reason: r.message);
    await go(t, '/employee/trip/TR-1001');
    await reveal(t, find.text('Traffic data unavailable'));
    expect(find.text('Traffic data unavailable'), findsOneWidget);
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('v2 screens have no overflow at 390 px, text scale $scale', (
      t,
    ) async {
      await signInAs(t, 'Asha Rao', textScale: scale);
      await servicesOf(t).traffic.setScenario(
        internalRoads: TrafficLevel.severe,
        ringRoad: TrafficLevel.heavy,
      );
      await t.pumpAndSettle();
      for (final r in [
        '/employee/preferences',
        '/employee/profile',
        '/employee/trip/TR-1001',
        '/employee/trip/TR-1001/pass',
        '/employee/home',
      ]) {
        await go(t, r);
        expect(t.takeException(), isNull, reason: r);
        await scrollToBottom(t);
        expect(t.takeException(), isNull, reason: '$r scrolled');
      }
      final rev = dataOf(t).openRevision('TR-1001');
      if (rev != null) await servicesOf(t).traffic.applyRevision(rev.id);
      await go(t, '/employee/trip/TR-1001');
      await scrollToBottom(t);
      expect(t.takeException(), isNull, reason: 'applied revision');
    });
  }
}
