import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/demo/clock.dart';
import '../core/export/export_service.dart';
import '../core/persistence/local_database.dart';
import '../data/repositories/repositories.dart';
import '../domain/services/app_services.dart';

export '../data/repositories/repositories.dart';
export '../domain/services/app_services.dart';

/// Time source. Overridden with a FixedClock in tests.
final clockProvider = Provider<Clock>((ref) => const SystemClock());

/// The shared local database. Overridden in `bootstrap()` after it opens.
/// Watching this provider rebuilds on every committed change.
final databaseProvider = ChangeNotifierProvider<LocalDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);

/// Read-side snapshot. Widgets `ref.watch(dataProvider)` to react to
/// changes made in ANY workspace.
final dataProvider = Provider<DataView>((ref) {
  final db = ref.watch(databaseProvider);
  return DataView(db, ref.watch(clockProvider));
});

/// Write-side services (stable; use `ref.read` in callbacks).
/// CSV export adapter (override in tests to avoid writing files).
final exportServiceProvider = Provider<ExportService>(
  (ref) => const ExportService(),
);

final servicesProvider = Provider<AppServices>((ref) {
  final db = ref.read(databaseProvider);
  return AppServices(
    db,
    ref.watch(clockProvider),
    export: ref.watch(exportServiceProvider),
  );
});

/// Metrics computed from the current snapshot.
final metricsProvider = Provider<MetricsService>(
  (ref) => MetricsService(ref.watch(dataProvider)),
);

/// Simulated position provider (demo adapter).
final locationServiceProvider = Provider<LocationService>(
  (ref) => DemoLocationService(ref.watch(dataProvider)),
);

/// Current demo identities (null = not chosen).
final currentEmployeeIdProvider = Provider<String?>(
  (ref) => ref.watch(dataProvider).auth.currentEmployeeId,
);
final currentDriverIdProvider = Provider<String?>(
  (ref) => ref.watch(dataProvider).auth.currentDriverId,
);
