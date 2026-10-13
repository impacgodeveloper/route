import 'package:executive_fleet/app/providers.dart';
import 'package:executive_fleet/domain/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'employee_harness.dart';

void main() {
  testWidgets('redirects to login, signs in as E1 and shows next trip', (
    tester,
  ) async {
    await signInAs(tester, 'Asha Rao');
    expect(find.textContaining('Good morning, Asha'), findsOneWidget);
    expect(find.textContaining('TR-1001'), findsWidgets);
    expect(find.text('Show e-pass'), findsOneWidget);
    expect(find.textContaining('Ravi Kumar'), findsOneWidget);
  });

  testWidgets('E4 requires the configured demo password', (tester) async {
    await pumpEmployeeApp(tester, location: '/employee/login');
    await tester.tap(find.text('Arjun Das'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Password for E4'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'wrong');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Incorrect demo password.'), findsOneWidget);
  });

  testWidgets('bottom tabs navigate', (tester) async {
    await signInAs(tester, 'Asha Rao');
    await tester.tap(find.text('My Trips'));
    await tester.pumpAndSettle();
    expect(find.text('My trips'), findsOneWidget);
    await tester.tap(find.text('Book'));
    await tester.pumpAndSettle();
    expect(find.text('Book transport'), findsOneWidget);
    await tester.tap(find.text('Activity').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Trip history'), findsWidgets);
    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    expect(find.text('My schedule'), findsOneWidget);
  });

  testWidgets(
    'booking submit appears in requests; duplicate is rejected with input kept',
    (tester) async {
      await signInAs(tester, 'Asha Rao');
      await tester.tap(find.text('Book'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Review request'));
      await tester.tap(find.text('Review request'));
      await tester.pumpAndSettle();
      expect(find.text('Review your request'), findsOneWidget);
      await tester.tap(find.textContaining(RegExp(r'^Submit')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(RegExp(r'Request (submitted|waitlisted)')),
        findsOneWidget,
      );

      final c = containerOf(tester);
      final mine = c
          .read(dataProvider)
          .bookingsOf('E1')
          .where((b) => b.status.isOpen)
          .toList();
      expect(mine, hasLength(1));
      // Fleet Manager queue sees it too (shared data).
      expect(
        c.read(dataProvider).openBookings.any((b) => b.id == mine.first.id),
        isTrue,
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'New request'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Review request'));
      await tester.tap(find.text('Review request'));
      await tester.pumpAndSettle();
      expect(find.text('Please fix the following'), findsOneWidget);
      expect(find.textContaining('You already have'), findsOneWidget);

      await tester.tap(find.textContaining('My requests'));
      await tester.pumpAndSettle();
      expect(find.textContaining(mine.first.reference), findsOneWidget);
    },
  );

  testWidgets('trip detail and e-pass open from home', (tester) async {
    await signInAs(tester, 'Asha Rao');
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'TR-1001'), findsOneWidget);
    expect(find.textContaining('Pickup window'), findsOneWidget);
    await tester.tap(find.text('Show e-pass'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('T-PIN'), findsOneWidget);
    expect(find.text('Awaiting pickup'), findsOneWidget);
  });

  testWidgets('opening a notification marks it read and opens the trip', (
    tester,
  ) async {
    await signInAs(tester, 'Asha Rao');
    final c = containerOf(tester);
    final before = c.read(dataProvider).unreadCount(UserRole.employee, 'E1');
    await tester.tap(find.byTooltip('Notifications, $before unread'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pickup reminder'));
    await tester.pumpAndSettle();
    expect(
      c.read(dataProvider).unreadCount(UserRole.employee, 'E1'),
      before - 1,
    );
    expect(find.widgetWithText(AppBar, 'TR-1001'), findsOneWidget);
  });

  for (final size in [phoneSize, tabletSize]) {
    testWidgets(
      'main screens render without overflow at ${size.width.toInt()}px',
      (tester) async {
        await signInAs(tester, 'Kiran Mehta', size: size);
        for (final tab in ['My Trips', 'Book', 'Activity', 'Profile', 'Home']) {
          await tester.tap(find.text(tab).last);
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
