import 'package:web/web.dart' as web;

import 'storage_adapter.dart';

Future<StorageAdapter> createStorage() async => WebStorageAdapter();

/// Persists tables in the browser's localStorage for this origin.
class WebStorageAdapter implements StorageAdapter {
  static const _prefix = 'efm_demo_db.';

  web.Storage get _storage => web.window.localStorage;

  @override
  Future<String?> read(String key) async => _storage.getItem('$_prefix$key');

  @override
  Future<void> write(String key, String value) async =>
      _storage.setItem('$_prefix$key', value);

  @override
  Future<void> delete(String key) async => _storage.removeItem('$_prefix$key');

  @override
  Future<List<String>> keys() async {
    final result = <String>[];
    for (var i = 0; i < _storage.length; i++) {
      final k = _storage.key(i);
      if (k != null && k.startsWith(_prefix)) {
        result.add(k.substring(_prefix.length));
      }
    }
    return result;
  }

  @override
  String get description => 'Browser localStorage';
}
