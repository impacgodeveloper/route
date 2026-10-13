import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the bundled Inter font so widget tests measure text like the real
/// app (the default test font is much wider and hides real layout issues).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final loader = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final file = File('assets/fonts/Inter-$w.ttf');
    if (file.existsSync()) {
      final bytes = file.readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
  }
  await loader.load();
  // Material icons (for readable screenshot renders during visual QA).
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final icons = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    );
    if (icons.existsSync()) {
      final iconLoader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
      await iconLoader.load();
    }
  }
  await testMain();
}
