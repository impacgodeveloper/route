import 'package:executive_fleet/app/app.dart';
import 'package:executive_fleet/app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:executive_fleet/app/router.dart';

import '../../support/widget_harness.dart';

export '../../support/widget_harness.dart'
    show phoneSize, tabletSize, desktopSize;

/// Boots the FULL app (real router, all four workspaces, seed) at [location].
Future<void> pumpEmployer(
  WidgetTester tester, {
  String location = '/employer',
  Size size = desktopSize,
}) => pumpApp(tester, location: location, size: size);

ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(FleetApp)));

DataView dataOf(WidgetTester tester) => containerOf(tester).read(dataProvider);
AppServices servicesOf(WidgetTester tester) =>
    containerOf(tester).read(servicesProvider);

/// Navigates with the real router.
Future<void> goTo(WidgetTester tester, String path) async {
  containerOf(tester).read(routerProvider).go(path);
  await tester.pumpAndSettle();
}

/// Scrolls [f] into view and taps it.
Future<void> tapIt(WidgetTester tester, Finder f) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

String currentPath(WidgetTester tester) => containerOf(
  tester,
).read(routerProvider).routerDelegate.currentConfiguration.uri.path;

/// Selects [option] in one of the shared AuditTrailView filter dropdowns.
Future<void> pickAuditFilter(
  WidgetTester tester,
  String label,
  String option,
) async {
  final field = find
      .ancestor(of: find.text(label), matching: find.byType(InputDecorator))
      .first;
  await tapIt(tester, field);
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}
