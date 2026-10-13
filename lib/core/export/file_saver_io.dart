import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String> saveTextFile(String fileName, String content) async {
  Directory? dir;
  try {
    dir = await getDownloadsDirectory();
  } catch (_) {
    dir = null;
  }
  dir ??= await getApplicationDocumentsDirectory();
  final file = File('${dir.path}${Platform.pathSeparator}$fileName');
  await file.writeAsString(content, flush: true);
  return 'Saved to ${file.path}';
}
