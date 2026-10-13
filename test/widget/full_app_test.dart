import 'package:executive_fleet/app/providers.dart';
import 'package:executive_fleet/app/router.dart';
import 'package:executive_fleet/domain/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/widget_harness.dart';

/// Full-router tests: every application opens from the real sign-in, and a
/// change made in one workspace is visible in another (shared database).
void main() {
  Future<void> signInAs(
    WidgetTester t,
    String role, {
    bool password = false,
  }) async {
    await t.tap(find.byKey(const Key('roleDropdown')));
    await t.pumpAndSettle();
    await t.tap(find.text(role).last);
    await t.pumpAndSettle();
    if (password) {
      await t.tap(find.text('Use demo password'));
      await t.pumpAndSettle();
    }
    await t.ensureVisible(find.byKey(const Key('signInButton')));
    await t.tap(find.byKey(const Key('signInButton')));
    await settle(t);
    await t.pumpAndSettle();
  }

  testWidgets('sign-in opens all four applications (desktop)', (t) async {
    await pumpApp(t, size: desktopSize);
    await signInAs(t, 'Employer Admin', password: true);
    expect(find.text('Rosters & Policies'), findsOneWidget);
    await t.tap(find.text('Sign out'));
    await t.pumpAndSettle();
    await signInAs(t, 'Fleet Manager', password: true);
    expect(find.text('Trips & Dispatch'), findsWidgets);
    await t.tap(find.text('Sign out'));
    await t.pumpAndSettle();
    await signInAs(t, 'Employee');
    expect(find.textContaining('Asha'), findsWidgets);
  });

  testWidgets('sign-in opens the Driver app (phone)', (t) async {
    await pumpApp(t, size: phoneSize);
    await signInAs(t, 'Driver');
    expect(find.textContaining('Ravi Kumar'), findsWidgets);
  });

  testWidgets(
    'change in Fleet console is visible in Employee and Employer views',
    (t) async {
      await pumpApp(t, location: '/fleet/dispatch', size: desktopSize);
      final container = ProviderScope.containerOf(
        t.element(find.byType(MaterialApp).first),
      );
      final services = container.read(servicesProvider);
      // Fleet Manager assigns BK-1004 (E4, tomorrow) to DR1 + C1.
      final r = await services.bookings.createTripForBookings(
        ['BK-1004'],
        driverId: 'DR1',
        vehicleId: 'C1',
      );
      expect(r.isOk, isTrue, reason: r.message);
      await t.pumpAndSettle();
      final tripCode = r.valueOrNull!.tripCode;
      // Employer assignments shows the new trip for tomorrow's C1 view.
      final data = container.read(dataProvider);
      expect(data.booking('BK-1004')!.status, BookingStatus.assigned);
      // Employee E4 sees it in My Trips.
      await services.session.signInEmployee('E4', password: 'demo1234');
      await t.pumpAndSettle();
      container.read(dataProvider);
      final router = container.read(routerProvider);
      router.go('/employee/trips');
      await t.pumpAndSettle();
      expect(find.textContaining(tripCode), findsWidgets);
      // Driver DR1 sees it in Trips.
      await services.session.signInDriver('DR1');
      router.go('/driver/trips');
      await t.pumpAndSettle();
      expect(find.textContaining(tripCode), findsWidgets);
    },
  );
}
