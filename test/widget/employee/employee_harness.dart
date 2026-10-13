import 'package:executive_fleet/app/providers.dart';
import 'package:executive_fleet/core/persistence/storage_adapter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/widget_harness.dart';

export '../../support/widget_harness.dart';

/// Boots the FULL app (real router, all workspaces) at an employee route.
Future<MemoryStorageAdapter> pumpEmployeeApp(
  WidgetTester tester, {
  String location = '/employee',
  Size size = phoneSize,
  double textScale = 1.0,
  MemoryStorageAdapter? storage,
}) async {
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  return pumpApp(tester, location: location, size: size, storage: storage);
}

ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Navigator).first));

AppServices servicesOf(WidgetTester tester) =>
    containerOf(tester).read(servicesProvider);
DataView dataOf(WidgetTester tester) => containerOf(tester).read(dataProvider);

/// Opens the app and signs in as [name] through the login UI.
Future<void> signInAs(
  WidgetTester tester,
  String name, {
  Size size = phoneSize,
  double textScale = 1.0,
}) async {
  await pumpEmployeeApp(tester, size: size, textScale: textScale);
  expect(find.text('Choose a demo employee to continue.'), findsOneWidget);
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}
