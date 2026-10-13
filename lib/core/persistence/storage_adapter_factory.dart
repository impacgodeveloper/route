import 'storage_adapter.dart';
import 'storage_adapter_stub.dart'
    if (dart.library.io) 'storage_adapter_io.dart'
    if (dart.library.js_interop) 'storage_adapter_web.dart';

/// Creates the persistence backend appropriate for the running platform.
Future<StorageAdapter> createPlatformStorage() => createStorage();
