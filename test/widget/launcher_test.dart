import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/widget_harness.dart';

/// Sign-in screen: the role dropdown routes to the right application.
Future<void> chooseRole(WidgetTester t, String role) async {
  await t.tap(find.byKey(const Key('roleDropdown')));
  await t.pumpAndSettle();
  await t.tap(find.text(role).last);
  await t.pumpAndSettle();
}

Future<void> signIn(WidgetTester t) async {
  await t.ensureVisible(find.byKey(const Key('signInButton')));
  await t.tap(find.byKey(const Key('signInButton')));
  await settle(t);
  await t.pumpAndSettle();
}

void main() {
  for (final size in [phoneSize, tabletSize, desktopSize]) {
    testWidgets('sign-in renders without overflow at ${size.width.toInt()}px', (
      t,
    ) async {
      await pumpApp(t, size: size);
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.byKey(const Key('roleDropdown')), findsOneWidget);
      expect(find.text('Sign in as Employee'), findsOneWidget);
      expect(find.text('DEMO DATA'), findsWidgets);
    });
  }

  testWidgets('Employee E1 signs in and lands on Employee home', (t) async {
    await pumpApp(t, size: phoneSize);
    await signIn(t);
    expect(find.textContaining('Asha'), findsWidgets);
    expect(find.text('My Trips'), findsOneWidget);
  });

  testWidgets('Driver role opens the Driver app', (t) async {
    await pumpApp(t, size: phoneSize);
    await chooseRole(t, 'Driver');
    expect(find.byKey(const Key('driverDropdown')), findsOneWidget);
    expect(find.byKey(const Key('passwordField')), findsNothing);
    await signIn(t);
    expect(find.text('Ravi Kumar'), findsWidgets);
    expect(find.text('Start shift'), findsOneWidget);
  });

  testWidgets('Employer Admin requires the demo password', (t) async {
    await pumpApp(t, size: desktopSize);
    await chooseRole(t, 'Employer Admin');
    await signIn(t);
    expect(find.text('Enter the password.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('passwordField')), 'wrong');
    await signIn(t);
    expect(find.text('Incorrect demo password.'), findsOneWidget);
    await t.tap(find.text('Use demo password'));
    await t.pumpAndSettle();
    await signIn(t);
    expect(find.text('Rosters & Policies'), findsOneWidget);
  });

  testWidgets('Fleet Manager opens the Fleet console; Sign out returns', (
    t,
  ) async {
    await pumpApp(t, size: desktopSize);
    await chooseRole(t, 'Fleet Manager');
    await t.tap(find.text('Use demo password'));
    await t.pumpAndSettle();
    await signIn(t);
    expect(find.text('Trips & Dispatch'), findsOneWidget);
    await t.tap(find.text('Sign out'));
    await t.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
    // Last used role is remembered.
    expect(find.text('Sign in as Fleet Manager'), findsOneWidget);
  });

  testWidgets('demo tools reset requires confirmation and cancel keeps data', (
    t,
  ) async {
    await pumpApp(t, size: desktopSize);
    await t.tap(find.text('Demo tools'));
    await t.pumpAndSettle();
    await t.tap(find.text('Reset demo data'));
    await t.pumpAndSettle();
    expect(find.text('Reset demo data?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(find.text('Reset demo data?'), findsNothing);
  });
}
