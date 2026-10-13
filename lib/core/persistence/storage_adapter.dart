/// Key/value persistence backend for the local database.
///
/// The database serializes each table to one key. Platform adapters:
/// * native (Android/iOS/Windows): one JSON file per table in the app
///   support directory (`storage_adapter_io.dart`).
/// * web: browser `localStorage` (`storage_adapter_web.dart`).
/// * tests: [MemoryStorageAdapter].
abstract interface class StorageAdapter {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<List<String>> keys();
  String get description;
}

class MemoryStorageAdapter implements StorageAdapter {
  MemoryStorageAdapter([Map<String, String>? initial]) : _data = {...?initial};

  final Map<String, String> _data;

  /// Lets tests simulate an app restart against the same "disk".
  Map<String, String> get snapshot => Map.unmodifiable(_data);

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<List<String>> keys() async => _data.keys.toList();

  @override
  String get description => 'In-memory (tests)';
}
