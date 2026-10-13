import 'package:executive_fleet/core/demo/clock.dart';
import 'package:executive_fleet/core/persistence/local_database.dart';
import 'package:executive_fleet/core/persistence/storage_adapter.dart';
import 'package:executive_fleet/data/repositories/repositories.dart';
import 'package:executive_fleet/domain/services/app_services.dart';

/// Demo day used by tests: 6:30 AM on the prototype target date.
final testNow = DateTime(2026, 10, 19, 6, 30);

class Harness {
  Harness._(this.storage, this.db, this.clock, this.services);

  final MemoryStorageAdapter storage;
  final LocalDatabase db;
  final FixedClock clock;
  final AppServices services;

  DataView get view => DataView(db, clock);

  static Future<Harness> create({
    MemoryStorageAdapter? storage,
    DateTime? now,
    bool seed = true,
  }) async {
    final s = storage ?? MemoryStorageAdapter();
    final db = LocalDatabase(s);
    await db.open();
    final clock = FixedClock(now ?? testNow);
    final services = AppServices(db, clock);
    if (seed) await services.seed.ensureSeeded();
    return Harness._(s, db, clock, services);
  }

  /// Simulates an app restart against the same storage.
  Future<Harness> restart() async {
    await db.flush();
    return Harness.create(
      storage: MemoryStorageAdapter(Map.of(storage.snapshot)),
      now: clock.now(),
    );
  }
}
