import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/persistence/local_database.dart';
import '../core/persistence/storage_adapter.dart';
import '../core/persistence/storage_adapter_factory.dart';
import '../core/widgets/widgets.dart';
import '../data/seed/seed_manager.dart';
import 'providers.dart';
import 'router.dart';

/// Opens local storage, runs migrations, seeds once, then starts the app.
class BootstrapApp extends StatefulWidget {
  const BootstrapApp({
    super.key,
    this.storageOverride,
    this.clock = const SystemClock(),
    this.initialLocation = '/',
    this.extraOverrides = const [],
  });

  /// Tests inject an in-memory adapter.
  final StorageAdapter? storageOverride;
  final Clock clock;
  final String initialLocation;

  /// Additional provider overrides (tests: fake export, etc.).
  final List<Override> extraOverrides;

  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> {
  LocalDatabase? _db;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    setState(() => _error = null);
    try {
      final storage = widget.storageOverride ?? await createPlatformStorage();
      final db = LocalDatabase(storage);
      await db.open();
      await SeedManager(db, widget.clock).ensureSeeded();
      if (mounted) setState(() => _db = db);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = _db;
    if (db == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: Scaffold(
          body: _error == null
              ? const LoadingState(message: 'Preparing local demo data…')
              : ErrorState(
                  title: 'Could not open local data',
                  message: '$_error',
                  onRetry: _open,
                ),
        ),
      );
    }
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWith((ref) => db),
        clockProvider.overrideWithValue(widget.clock),
        ...widget.extraOverrides,
        routerProvider.overrideWith(
          (ref) => buildRouter(initialLocation: widget.initialLocation),
        ),
      ],
      child: const FleetApp(),
    );
  }
}

class FleetApp extends ConsumerWidget {
  const FleetApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Executive Fleet Mobility',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.6,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
