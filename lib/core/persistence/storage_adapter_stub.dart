import 'storage_adapter.dart';

Future<StorageAdapter> createStorage() async => MemoryStorageAdapter();
