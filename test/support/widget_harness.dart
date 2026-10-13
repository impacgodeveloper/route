import 'package:executive_fleet/app/app.dart';
import 'package:executive_fleet/core/demo/clock.dart';
import 'package:executive_fleet/core/persistence/storage_adapter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:executive_fleet/app/providers.dart';

import 'fake_export.dart';
import 'test_harness.dart';

const phoneSize = Size(390, 844);
const tabletSize = Size(900, 1100);
const desktopSize = Size(1440, 900);

/// Boots the full app (real router, theme, seed) on in-memory storage with a
/// fixed clock, at [size], starting at [location].
Future<MemoryStorageAdapter> pumpApp(
  WidgetTester tester, {
  String location = '/',
  Size size = phoneSize,
  DateTime? now,
  MemoryStorageAdapter? storage,
  FakeExportService? export,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final s = storage ?? MemoryStorageAdapter();
  await tester.pumpWidget(
    BootstrapApp(
      storageOverride: s,
      clock: FixedClock(now ?? testNow),
      initialLocation: location,
      extraOverrides: [
        exportServiceProvider.overrideWithValue(export ?? FakeExportService()),
      ],
    ),
  );
  // Let async open + seed complete.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
  return s;
}

/// Pumps a few frames (use instead of pumpAndSettle when animations loop).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}
