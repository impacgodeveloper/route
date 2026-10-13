@Tags(['screenshot'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/widget_harness.dart';
import 'screenshot_util.dart';

void main() {
  testWidgets('sign-in phone', (t) async {
    await pumpApp(t, size: phoneSize);
    await snap(t, 'login_phone');
  });
  testWidgets('sign-in phone role menu', (t) async {
    await pumpApp(t, size: phoneSize);
    await t.tap(find.byKey(const Key('roleDropdown')));
    await t.pumpAndSettle();
    await snap(t, 'login_phone_roles');
  });
  testWidgets('sign-in desktop', (t) async {
    await pumpApp(t, size: desktopSize);
    await snap(t, 'login_desktop');
  });
  testWidgets('sign-in desktop fleet', (t) async {
    await pumpApp(t, size: desktopSize);
    await t.tap(find.byKey(const Key('roleDropdown')));
    await t.pumpAndSettle();
    await t.tap(find.text('Fleet Manager').last);
    await t.pumpAndSettle();
    await snap(t, 'login_desktop_fleet');
  });
}
