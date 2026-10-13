import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Visual QA helper: renders the current screen to
/// `test/screenshots/out/<name>.png` when run with `--update-goldens`.
/// Screenshot tests are tagged so the normal suite can skip them:
/// `flutter test --exclude-tags screenshot`.
Future<void> snap(WidgetTester tester, String name) async {
  await expectLater(
    find.byType(WidgetsApp).first,
    matchesGoldenFile('out/$name.png'),
  );
}
