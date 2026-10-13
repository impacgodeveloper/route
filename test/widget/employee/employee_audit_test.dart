import 'package:executive_fleet/app/providers.dart';
import 'package:executive_fleet/app/router.dart';
import 'package:executive_fleet/domain/models/models.dart';
import 'package:executive_fleet/domain/rules/inspection_rules.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'employee_harness.dart';

/// Exhaustive UI audit of the Employee workspace on the real router.
/// Services are used only to set up state from other workspaces.

Future<void> go(WidgetTester t, String path) async {
  containerOf(t).read(routerProvider).go(path);
  await t.pumpAndSettle();
}

Future<void> tapText(WidgetTester t, String text, {bool last = false}) async {
  final f = last ? find.text(text).last : find.text(text);
  if (f.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      f,
      250,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> scrollToBottom(WidgetTester t) async {
  final scrollables = find.byType(Scrollable);
  if (scrollables.evaluate().isEmpty) return;
  for (var i = 0; i < 6; i++) {
    await t.drag(scrollables.first, const Offset(0, -600), warnIfMissed: false);
    await t.pumpAndSettle();
  }
}

const allRoutes = [
  '/employee/home',
  '/employee/trips',
  '/employee/book',
  '/employee/activity',
  '/employee/profile',
  '/employee/trip/TR-1001',
  '/employee/trip/TR-1001/pass',
  '/employee/trip/TR-0991',
  '/employee/trip/TR-0991/pass',
  '/employee/notifications',
  '/employee/booking/BK-1001',
  '/employee/support/new',
  '/employee/safety',
  '/employee/roster',
  '/employee/preferences',
];

void main() {
  // ---------------- Login ----------------
  for (final (name, first) in [
    ('Asha Rao', 'Asha'),
    ('Kiran Mehta', 'Kiran'),
    ('Neha Iyer', 'Neha'),
  ]) {
    testWidgets('login: $name lands on Home', (t) async {
      await signInAs(t, name);
      expect(find.textContaining('Good morning, $first'), findsOneWidget);
    });
  }

  testWidgets('login: E4 wrong then right password; cancel keeps login', (
    t,
  ) async {
    await pumpEmployeeApp(t);
    await tapText(t, 'Arjun Das');
    await tapText(t, 'Cancel');
    expect(find.text('Choose a demo employee to continue.'), findsOneWidget);
    await tapText(t, 'Arjun Das');
    await t.enterText(find.byType(TextField).last, 'nope');
    await tapText(t, 'Sign in');
    expect(find.text('Incorrect demo password.'), findsOneWidget);
    await tapText(t, 'OK');
    await tapText(t, 'Arjun Das');
    await t.enterText(find.byType(TextField).last, 'demo1234');
    await tapText(t, 'Sign in');
    expect(find.textContaining('Good morning, Arjun'), findsOneWidget);
  });

  testWidgets(
    'login: search any employee, no-result state, inactive excluded',
    (t) async {
      await pumpEmployeeApp(t);
      await t.enterText(find.byType(TextField), 'E100');
      await t.pumpAndSettle();
      expect(find.text('No active employee found'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'E27');
      await t.pumpAndSettle();
      await t.tap(find.textContaining('E27 ·'));
      await t.pumpAndSettle();
      expect(find.textContaining('Good morning'), findsOneWidget);
    },
  );

  testWidgets(
    'guard: deep link without identity redirects to login; unknown records show empty states',
    (t) async {
      await pumpEmployeeApp(t, location: '/employee/trip/TR-1001');
      expect(find.text('Choose a demo employee to continue.'), findsOneWidget);
      await tapText(t, 'Asha Rao');
      await go(t, '/employee/trip/NOPE');
      expect(find.text('Trip not available'), findsOneWidget);
      await go(t, '/employee/trip/TR-1002'); // not E1's trip
      expect(find.text('Trip not available'), findsOneWidget);
      await go(t, '/employee/trip/TR-1002/pass');
      expect(find.text('Pass not available'), findsOneWidget);
      await go(t, '/employee/booking/BK-1004'); // E4's booking
      expect(find.text('Request not found'), findsOneWidget);
    },
  );

  // ---------------- Home ----------------
  testWidgets('home: quick actions, bell, next-trip actions, all trips', (
    t,
  ) async {
    await signInAs(t, 'Asha Rao');
    await tapText(t, 'Schedule');
    expect(find.text('My schedule'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    await tapText(t, 'Safety');
    expect(find.text('Safety centre'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    await tapText(t, 'Request');
    expect(find.text('Book transport'), findsOneWidget);
    await tapText(t, 'Home', last: true);
    await t.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip(RegExp(r'^Notifications')));
    await t.pumpAndSettle();
    expect(find.text('Notifications'), findsWidgets);
    await t.pageBack();
    await t.pumpAndSettle();
    await tapText(t, 'Show e-pass');
    expect(find.byType(QrImageView), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    await tapText(t, 'Details');
    expect(find.widgetWithText(AppBar, 'TR-1001'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    await tapText(t, 'All trips');
    expect(find.text('My trips'), findsOneWidget);
  });

  testWidgets('home: employee with no trip sees request empty state', (
    t,
  ) async {
    await pumpEmployeeApp(t);
    await t.enterText(find.byType(TextField), 'E40');
    await t.pumpAndSettle();
    await t.tap(find.textContaining('E40 ·'));
    await t.pumpAndSettle();
    expect(find.text('No upcoming trip assigned'), findsOneWidget);
    await tapText(t, 'Request transport');
    expect(find.text('Book transport'), findsOneWidget);
  });

  // ---------------- My trips ----------------
  testWidgets(
    'trips: segments, search, clear filters, open row, schedule icon',
    (t) async {
      await signInAs(t, 'Asha Rao');
      await tapText(t, 'My Trips');
      expect(find.textContaining('TR-1001'), findsOneWidget);
      await t.tap(find.textContaining('Completed'));
      await t.pumpAndSettle();
      expect(find.textContaining('TR-0991'), findsOneWidget);
      await t.tap(find.textContaining('Cancelled'));
      await t.pumpAndSettle();
      expect(find.text('No cancelled trips'), findsOneWidget);
      await t.tap(find.textContaining('Upcoming'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'zzz');
      await t.pumpAndSettle();
      expect(find.text('No trips match'), findsOneWidget);
      await tapText(t, 'Clear filters');
      expect(find.textContaining('TR-1001'), findsOneWidget);
      await t.tap(find.textContaining('TR-1001'));
      await t.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'TR-1001'), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Weekly schedule'));
      await t.pumpAndSettle();
      expect(find.text('My schedule'), findsOneWidget);
    },
  );

  testWidgets('trips: cancelled trip shows reason banner (E20)', (t) async {
    await pumpEmployeeApp(t);
    await t.enterText(find.byType(TextField), 'E20');
    await t.pumpAndSettle();
    await t.tap(find.textContaining('E20 ·'));
    await t.pumpAndSettle();
    await go(t, '/employee/trip/TR-1005');
    expect(find.text('This trip was cancelled'), findsOneWidget);
    expect(find.text('Show e-pass'), findsNothing);
    await go(t, '/employee/trip/TR-1005/pass');
    expect(find.text('Trip cancelled'), findsOneWidget);
  });

  // ---------------- Booking ----------------
  testWidgets('book: validation error (already scheduled today) keeps input', (
    t,
  ) async {
    await signInAs(t, 'Asha Rao');
    await tapText(t, 'Book');
    await t.enterText(find.byType(TextField).last, 'Keep this note');
    await t.tap(find.text('Tue, 20 Oct'));
    await t.pumpAndSettle();
    await t.tap(find.text('19'));
    await t.pumpAndSettle();
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(find.text('Mon, 19 Oct'), findsOneWidget);
    await tapText(t, 'Review request');
    expect(find.text('Please fix the following'), findsOneWidget);
    expect(find.textContaining('already scheduled on TR-1001'), findsOneWidget);
    expect(find.text('Keep this note'), findsOneWidget);
  });

  testWidgets('book: submit → notification → booking detail → cancel', (
    t,
  ) async {
    await signInAs(t, 'Asha Rao');
    await tapText(t, 'Book');
    await tapText(t, 'Review request');
    expect(find.text('Review your request'), findsOneWidget);
    await tapText(t, 'Edit details');
    expect(find.text('Where and when?'), findsOneWidget);
    await tapText(t, 'Review request');
    await t.tap(find.textContaining(RegExp(r'^Submit')));
    await t.pumpAndSettle();
    final ref = dataOf(
      t,
    ).bookingsOf('E1').firstWhere((b) => b.status.isOpen).reference;
    expect(find.text('Reference $ref'), findsOneWidget);
    // Notification links to the booking.
    await go(t, '/employee/notifications');
    await t.tap(find.text('Request $ref received'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(AppBar, ref), findsOneWidget);
    await tapText(t, 'Cancel request');
    await tapText(t, 'Keep');
    expect(dataOf(t).booking(ref)!.status.isOpen, isTrue);
    await tapText(t, 'Cancel request');
    await tapText(t, 'Cancel request', last: true);
    expect(dataOf(t).booking(ref)!.status, BookingStatus.cancelled);
    expect(find.text('Request cancelled'), findsWidgets);
    // My requests segment lists it with status.
    await go(t, '/employee/book');
    await t.tap(find.textContaining('My requests'));
    await t.pumpAndSettle();
    expect(find.textContaining(ref), findsOneWidget);
  });

  // ---------------- Trip detail / pass ----------------
  testWidgets('pass: T-PIN hidden by default, reveal and hide', (t) async {
    await signInAs(t, 'Asha Rao');
    await go(t, '/employee/trip/TR-1001/pass');
    final trip = dataOf(t).trips.byId('TR-1001')!;
    final pin = servicesOf(
      t,
    ).verification.tpin(trip, dataOf(t).employee('E1')!);
    expect(find.text('• • • •'), findsOneWidget);
    await t.tap(find.byTooltip('Reveal T-PIN'));
    await t.pumpAndSettle();
    expect(find.text(pin.split('').join(' ')), findsOneWidget);
    await t.tap(find.byTooltip('Hide T-PIN'));
    await t.pumpAndSettle();
    expect(find.text('• • • •'), findsOneWidget);
    await go(t, '/employee/trip/TR-0991/pass');
    expect(find.text('Pass expired'), findsOneWidget);
  });

  testWidgets(
    'trip detail: support ticket validation + submit appears in Activity',
    (t) async {
      await signInAs(t, 'Asha Rao');
      await go(t, '/employee/trip/TR-1001');
      await t.tap(find.byTooltip('Report an issue'));
      await t.pumpAndSettle();
      expect(find.text('New support ticket'), findsOneWidget);
      await tapText(t, 'Submit ticket');
      expect(find.text('Subject needs at least 4 characters'), findsOneWidget);
      await t.enterText(
        find.widgetWithText(TextFormField, 'Subject'),
        'Pickup gate question',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Describe the issue'),
        'Which gate should I wait at tomorrow?',
      );
      await tapText(t, 'Submit ticket');
      expect(
        dataOf(t).ticketsBy(UserRole.employee, 'E1').first.relatedTripId,
        'TR-1001',
      );
      await go(t, '/employee/activity');
      await t.tap(find.textContaining('Support'));
      await t.pumpAndSettle();
      expect(find.text('Pickup gate question'), findsOneWidget);
      await t.pump(const Duration(seconds: 6));
      await t.pumpAndSettle();
      await t.tap(find.text('New ticket'));
      await t.pumpAndSettle();
      expect(find.text('New support ticket'), findsOneWidget);
    },
  );

  testWidgets('activity: filter chips and notifications entry', (t) async {
    await signInAs(t, 'Asha Rao');
    await tapText(t, 'Activity', last: true);
    expect(find.textContaining('BK-1001'), findsOneWidget);
    await t.tap(find.textContaining('Trip history'));
    await t.pumpAndSettle();
    expect(find.textContaining('TR-0991'), findsOneWidget);
    await t.tap(find.textContaining('Support ·'));
    await t.pumpAndSettle();
    expect(find.text('AC was weak on TR-0991'), findsOneWidget);
    await tapText(t, 'Notifications');
    expect(find.text('Mark all read'), findsOneWidget);
  });

  // ---------------- Notifications ----------------
  testWidgets('notifications: unread filter, open trip record, mark all read', (
    t,
  ) async {
    await signInAs(t, 'Asha Rao');
    await go(t, '/employee/notifications');
    await t.tap(find.textContaining('Unread'));
    await t.pumpAndSettle();
    await t.tap(find.text('Trip TR-1001 assigned'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'TR-1001'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    await tapText(t, 'Mark all read');
    expect(dataOf(t).unreadCount(UserRole.employee, 'E1'), 0);
    expect(find.text('You\'re all caught up'), findsOneWidget);
    await tapText(t, 'Show all');
    expect(find.text('Pickup reminder'), findsOneWidget);
  });

  // ---------------- Profile ----------------
  testWidgets(
    'profile: pickup change persists after re-pump; toggles persist',
    (t) async {
      final storage = await pumpEmployeeApp(t);
      await tapText(t, 'Asha Rao');
      await tapText(t, 'Profile', last: true);
      final dropdown = find.widgetWithText(
        DropdownButtonFormField<String>,
        'PK01 · Cedar Park Gate',
      );
      await t.scrollUntilVisible(
        dropdown,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(dropdown);
      await t.pumpAndSettle();
      await t.tap(find.text('PK02 · Riverside Colony').last);
      await t.pumpAndSettle();
      await tapText(t, 'Save preferences');
      expect(dataOf(t).employee('E1')!.pickupLocationId, 'PK02');
      await tapText(t, 'Larger text');
      await tapText(t, 'Show simulated vehicle position');
      expect(dataOf(t).settingsFor('employee:E1').largeText, isTrue);
      await dataOf(t).db.flush();

      await t.pumpWidget(const SizedBox());
      await pumpEmployeeApp(t, location: '/employee/profile', storage: storage);
      expect(find.textContaining('PK02 · Riverside Colony'), findsWidgets);
      expect(dataOf(t).settingsFor('employee:E1').largeText, isTrue);
      expect(
        dataOf(t).settingsFor('employee:E1').shareSimulatedLocation,
        isFalse,
      );
      await go(t, '/employee/trip/TR-1001');
      await t.scrollUntilVisible(
        find.text('Location view is off'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Location view is off'), findsOneWidget);
    },
  );

  testWidgets('profile: contact support, switch identity, back to workspaces', (
    t,
  ) async {
    await signInAs(t, 'Asha Rao');
    await tapText(t, 'Profile', last: true);
    await tapText(t, 'Contact support');
    expect(find.text('New support ticket'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    await tapText(t, 'Safety centre');
    expect(find.text('Emergency SOS'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    await tapText(t, 'Switch demo employee');
    expect(find.text('Choose a demo employee to continue.'), findsOneWidget);
    expect(dataOf(t).auth.currentEmployeeId, isNull);
    await tapText(t, 'Kiran Mehta');
    await tapText(t, 'Profile', last: true);
    await tapText(t, 'Sign out');
    expect(find.text('Sign in'), findsOneWidget);
    expect(dataOf(t).auth.currentEmployeeId, isNull);
  });

  // ---------------- Safety ----------------
  testWidgets(
    'safety: SOS confirm-cancel, success, offline failure then retry',
    (t) async {
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => null,
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await signInAs(t, 'Asha Rao');
      await go(t, '/employee/safety');
      await tapText(t, 'Raise SOS');
      await tapText(t, 'Cancel');
      expect(dataOf(t).incidents.where((i) => i.isSos), isEmpty);
      await tapText(t, 'Raise SOS');
      await tapText(t, 'Raise SOS', last: true);
      expect(find.textContaining('SOS recorded'), findsOneWidget);
      expect(
        find.textContaining('Demo only — no real emergency service'),
        findsOneWidget,
      );
      final sos = dataOf(t).incidents.where((i) => i.isSos).toList();
      expect(sos.single.tripId, 'TR-1001');
      await tapText(t, 'Done');

      await servicesOf(
        t,
      ).session.setFlag(IncidentService.simulateOfflineKey, true);
      await t.pumpAndSettle();
      await tapText(t, 'Raise SOS');
      await tapText(t, 'Raise SOS', last: true);
      expect(find.text('SOS not recorded'), findsOneWidget);
      await servicesOf(
        t,
      ).session.setFlag(IncidentService.simulateOfflineKey, false);
      await t.pumpAndSettle();
      await tapText(t, 'Retry');
      expect(find.textContaining('SOS recorded'), findsOneWidget);
      expect(dataOf(t).incidents.where((i) => i.isSos), hasLength(2));
      await tapText(t, 'Share trip details');
      expect(find.textContaining('copied'), findsOneWidget);
    },
  );

  // ---------------- Schedule ----------------
  testWidgets('schedule: week/day toggle, day chips, request shortcut', (
    t,
  ) async {
    await signInAs(t, 'Asha Rao');
    await go(t, '/employee/roster');
    expect(find.textContaining('TR-1001'), findsOneWidget);
    await tapText(t, 'Day');
    await t.tap(find.text('20'));
    await t.pumpAndSettle();
    expect(find.text('No transport scheduled'), findsOneWidget);
    await tapText(t, 'Request');
    expect(find.text('Book transport'), findsOneWidget);
  });

  // ---------------- Cross-app reflection ----------------
  testWidgets('cross-app: driver boards E1 → e-pass shows On board', (t) async {
    await signInAs(t, 'Asha Rao');
    await go(t, '/employee/trip/TR-1001/pass');
    expect(find.text('Awaiting pickup'), findsOneWidget);
    final s = servicesOf(t);
    expect((await s.driverOps.checkIn('DR1')).isOk, isTrue);
    expect(
      (await s.driverOps.submitInspection(
        driverId: 'DR1',
        vehicleId: 'C1',
        items: InspectionRules.blankChecklist(),
      )).isOk,
      isTrue,
    );
    expect((await s.driverOps.startTrip('TR-1001', 'DR1')).isOk, isTrue);
    final data = dataOf(t);
    final trip = data.trips.byId('TR-1001')!;
    final stop = data.trips.pickupStopFor(trip, 'E1')!;
    // Arrive at stops in order up to E1's pickup.
    for (final st in data.trips.stopsOf(trip)) {
      expect((await s.driverOps.arriveAtStop(st.id)).isOk, isTrue);
      if (st.id == stop.id) break;
      for (final e in st.boardingEmployeeIds) {
        await s.driverOps.verifyAndBoard(
          stopId: st.id,
          method: VerificationMethod.qrDemo,
          input: s.verification.qrPayload(
            dataOf(t).trips.byId('TR-1001')!,
            data.employee(e)!,
          ),
        );
      }
      expect((await s.driverOps.departStop(st.id)).isOk, isTrue);
    }
    final r = await s.driverOps.verifyAndBoard(
      stopId: stop.id,
      method: VerificationMethod.tpinDemo,
      employeeId: 'E1',
      input: s.verification.tpin(
        dataOf(t).trips.byId('TR-1001')!,
        data.employee('E1')!,
      ),
    );
    expect(r.valueOrNull?.ok, isTrue, reason: r.message);
    await t.pumpAndSettle();
    expect(find.text('On board'), findsOneWidget);
    await go(t, '/employee/home');
    expect(find.text('Track trip'), findsOneWidget);
    expect(find.text('TRIP IN PROGRESS'), findsOneWidget);
  });

  testWidgets(
    'cross-app: delay on TR-1001 shows on trip and in notifications',
    (t) async {
      await signInAs(t, 'Asha Rao');
      final r = await servicesOf(t).incidents.report(
        const IncidentDraft(
          type: IncidentType.delay,
          description: 'Waterlogging near Orchid Enclave',
          severity: IncidentSeverity.medium,
          reporter: Actor(UserRole.driver, 'DR1'),
          tripId: 'TR-1001',
          delayMinutes: 15,
        ),
      );
      expect(r.isOk, isTrue, reason: r.message);
      await t.pumpAndSettle();
      await go(t, '/employee/trip/TR-1001');
      expect(
        find.textContaining('Waterlogging near Orchid Enclave'),
        findsOneWidget,
      );
      await go(t, '/employee/notifications');
      expect(find.text('TR-1001 running late'), findsOneWidget);
      await t.tap(find.text('TR-1001 running late'));
      await t.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'TR-1001'), findsOneWidget);
    },
  );

  // ---------------- Overflow sweep ----------------
  for (final scale in [1.0, 1.3]) {
    testWidgets('overflow: every route at 390×844, text scale $scale', (
      t,
    ) async {
      await signInAs(t, 'Asha Rao', textScale: scale);
      for (final r in allRoutes) {
        await go(t, r);
        expect(t.takeException(), isNull, reason: r);
        await scrollToBottom(t);
        expect(t.takeException(), isNull, reason: '$r (scrolled)');
      }
      // Active-trip variant (E5 on TR-1002) and E1 large-text preference.
      await go(t, '/employee/profile');
      await tapText(t, 'Larger text');
      expect(dataOf(t).settingsFor('employee:E1').largeText, isTrue);
      for (final r in allRoutes) {
        await go(t, r);
        await scrollToBottom(t);
        expect(t.takeException(), isNull, reason: '$r large text');
      }
      await go(t, '/employee/book');
      await tapText(t, 'Review request');
      expect(t.takeException(), isNull, reason: 'review step');
    });
  }

  testWidgets('overflow: active trip screens for E5 at text scale 1.3', (
    t,
  ) async {
    await pumpEmployeeApp(t, textScale: 1.3);
    await t.enterText(find.byType(TextField), 'E5');
    await t.pumpAndSettle();
    await t.tap(find.textContaining('E5 ·').first);
    await t.pumpAndSettle();
    for (final r in [
      '/employee/home',
      '/employee/trip/TR-1002',
      '/employee/trip/TR-1002/pass',
      '/employee/roster',
    ]) {
      await go(t, r);
      await scrollToBottom(t);
      expect(t.takeException(), isNull, reason: r);
    }
  });
}
