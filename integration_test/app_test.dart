import 'package:executive_fleet/app/app.dart';
import 'package:executive_fleet/core/demo/clock.dart';
import 'package:executive_fleet/core/persistence/storage_adapter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// On-device smoke test (needs a connected device/emulator:
/// `flutter test integration_test`). Uses in-memory storage so it never
/// touches the device's demo data.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final (role, password) in [
    ('Employee', false),
    ('Driver', false),
    ('Employer Admin', true),
    ('Fleet Manager', true),
  ]) {
    testWidgets('sign in as $role opens its application', (tester) async {
      await tester.pumpWidget(
        BootstrapApp(
          key: UniqueKey(),
          storageOverride: MemoryStorageAdapter(),
          clock: FixedClock(DateTime(2026, 10, 19, 6, 30)),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));
      await tester.tap(find.byKey(const Key('roleDropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(role).last);
      await tester.pumpAndSettle();
      if (password) {
        await tester.tap(find.text('Use demo password'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('signInButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('signInButton')), findsNothing);
    });
  }
}
