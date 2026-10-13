import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'storage_adapter.dart';

Future<StorageAdapter> createStorage() async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory('${base.path}${Platform.pathSeparator}efm_demo_db');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return FileStorageAdapter(dir);
}

/// Stores each table as `<key>.json` in a private app directory.
/// Writes go to a temp file first and are then renamed (atomic replace).
class FileStorageAdapter implements StorageAdapter {
  FileStorageAdapter(this.directory);

  final Directory directory;

  File _file(String key) =>
      File('${directory.path}${Platform.pathSeparator}$key.json');

  @override
  Future<String?> read(String key) async {
    final f = _file(key);
    return f.existsSync() ? f.readAsString() : null;
  }

  @override
  Future<void> write(String key, String value) async {
    final f = _file(key);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(value, flush: true);
    if (f.existsSync()) await f.delete();
    await tmp.rename(f.path);
  }

  @override
  Future<void> delete(String key) async {
    final f = _file(key);
    if (f.existsSync()) await f.delete();
  }

  @override
  Future<List<String>> keys() async => directory
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((n) => n.endsWith('.json'))
      .map((n) => n.substring(0, n.length - 5))
      .toList();

  @override
  String get description => 'Local JSON tables (${directory.path})';
}
