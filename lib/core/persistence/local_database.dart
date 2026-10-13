import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../domain/models/models.dart';
import 'migrations.dart';
import 'storage_adapter.dart';

/// Typed, ordered in-memory table backed by persistent storage.
///
/// Rows are immutable; every mutation replaces the row through a [Txn].
class DbTable<T extends Entity> {
  DbTable(this.name, this._fromJson);

  final String name;
  final T Function(Json json) _fromJson;
  Map<String, T> _rows = <String, T>{};

  bool any(bool Function(T row) test) => _rows.values.any(test);
  T? firstWhereOrNull(bool Function(T row) test) {
    for (final r in _rows.values) {
      if (test(r)) return r;
    }
    return null;
  }

  T? operator [](String? id) => id == null ? null : _rows[id];
  T? byId(String? id) => this[id];
  bool contains(String? id) => id != null && _rows.containsKey(id);
  Iterable<T> get values => _rows.values;
  List<T> get all => List.unmodifiable(_rows.values);
  int get length => _rows.length;
  Iterable<T> where(bool Function(T row) test) => _rows.values.where(test);

  String _encode() =>
      jsonEncode(_rows.values.map((r) => r.toJson()).toList(growable: false));

  void _clear() => _rows = <String, T>{};

  void _restore(Map<String, Entity> snapshot) {
    _rows = {for (final e in snapshot.entries) e.key: e.value as T};
  }

  void _load(List<Json> raw) {
    final next = <String, T>{};
    for (final row in raw) {
      final entity = _fromJson(row);
      next[entity.id] = entity;
    }
    _rows = next;
  }
}

/// Thrown inside a transaction to abort it with a user-facing message.
class TxnAbort implements Exception {
  TxnAbort(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Write handle passed to [LocalDatabase.transaction].
class Txn {
  Txn._(this._db);

  final LocalDatabase _db;
  final Map<DbTable, Map<String, Entity>> _snapshots = {};

  void _snapshot(DbTable table) {
    _snapshots.putIfAbsent(table, () => Map<String, Entity>.of(table._rows));
  }

  /// Inserts or replaces [row].
  void put<T extends Entity>(DbTable<T> table, T row) {
    _snapshot(table);
    table._rows[row.id] = row;
  }

  /// Inserts [row]; fails if the ID already exists (stable, unique IDs).
  void insert<T extends Entity>(DbTable<T> table, T row) {
    if (table.contains(row.id)) {
      throw TxnAbort('Duplicate ID "${row.id}" in ${table.name}.');
    }
    put(table, row);
  }

  void delete<T extends Entity>(DbTable<T> table, String id) {
    _snapshot(table);
    table._rows.remove(id);
  }

  void clear<T extends Entity>(DbTable<T> table) {
    _snapshot(table);
    table._rows.clear();
  }

  /// Generates a new unique ID with [prefix] for [table].
  String newId(DbTable table, String prefix) => _db.ids.next(table, prefix);

  void _rollback() {
    for (final entry in _snapshots.entries) {
      entry.key._restore(entry.value);
    }
  }

  Set<DbTable> get _dirty => _snapshots.keys.toSet();
}

/// Generates collision-free sequential IDs per prefix (e.g. TR-1007).
class IdGenerator {
  final Map<String, int> _counters = {};

  String next(DbTable table, String prefix) {
    var n = _counters[prefix] ?? _maxExisting(table, prefix);
    String id;
    do {
      n++;
      id = '$prefix$n';
    } while (table.contains(id));
    _counters[prefix] = n;
    return id;
  }

  int _maxExisting(DbTable table, String prefix) {
    var max = 0;
    for (final row in table.values) {
      final id = (row).id;
      if (id.startsWith(prefix)) {
        final n = int.tryParse(id.substring(prefix.length));
        if (n != null && n > max) max = n;
      }
    }
    return max;
  }

  void reset() => _counters.clear();
}

/// Local relational store shared by all four workspaces.
///
/// * Reads are synchronous over in-memory tables.
/// * Writes happen only inside [transaction]; all-or-nothing, then
///   persisted and broadcast via [notifyListeners] so every workspace
///   reflects the change immediately.
/// * Foreign keys are validated by domain services before commit.
class LocalDatabase extends ChangeNotifier {
  LocalDatabase(this.storage);

  final StorageAdapter storage;
  final ids = IdGenerator();

  static const _metaKey = 'meta';
  static const _appStateKey = 'app_state';

  final employers = DbTable<Employer>('employers', Employer.fromJson);
  final employees = DbTable<Employee>('employees', Employee.fromJson);
  final drivers = DbTable<Driver>('drivers', Driver.fromJson);
  final vehicles = DbTable<Vehicle>('vehicles', Vehicle.fromJson);
  final locations = DbTable<Location>('locations', Location.fromJson);
  final trips = DbTable<Trip>('trips', Trip.fromJson);
  final routes = DbTable<TripRoute>('routes', TripRoute.fromJson);
  final routeStops = DbTable<RouteStop>('route_stops', RouteStop.fromJson);
  final bookings = DbTable<Booking>('bookings', Booking.fromJson);
  final passengerEvents = DbTable<PassengerEvent>(
    'passenger_events',
    PassengerEvent.fromJson,
  );
  final shifts = DbTable<Shift>('shifts', Shift.fromJson);
  final inspections = DbTable<Inspection>('inspections', Inspection.fromJson);
  final incidents = DbTable<Incident>('incidents', Incident.fromJson);
  final billing = DbTable<BillingRecord>('billing', BillingRecord.fromJson);
  final optimizationConfigs = DbTable<OptimizationConfig>(
    'optimization_configs',
    OptimizationConfig.fromJson,
  );
  final optimizationRuns = DbTable<OptimizationRun>(
    'optimization_runs',
    OptimizationRun.fromJson,
  );
  final notifications = DbTable<AppNotification>(
    'notifications',
    AppNotification.fromJson,
  );
  final tickets = DbTable<SupportTicket>('tickets', SupportTicket.fromJson);
  final audit = DbTable<AuditEvent>('audit', AuditEvent.fromJson);
  final userSettings = DbTable<UserSettings>(
    'user_settings',
    UserSettings.fromJson,
  );

  // ---- v2 tables ----
  final invoices = DbTable<Invoice>('invoices', Invoice.fromJson);
  final contracts = DbTable<Contract>('contracts', Contract.fromJson);
  final allocations = DbTable<FleetAllocation>(
    'fleet_allocations',
    FleetAllocation.fromJson,
  );
  final routeRevisions = DbTable<RouteRevision>(
    'route_revisions',
    RouteRevision.fromJson,
  );
  final trafficStates = DbTable<TrafficState>(
    'traffic_state',
    TrafficState.fromJson,
  );

  // ---- v3 tables ----
  final fleetPolicies = DbTable<FleetPolicy>(
    'fleet_policy',
    FleetPolicy.fromJson,
  );
  final alcoholTests = DbTable<AlcoholTest>(
    'alcohol_tests',
    AlcoholTest.fromJson,
  );
  final geofences = DbTable<Geofence>('geofences', Geofence.fromJson);
  final vehicleEvents = DbTable<VehicleEvent>(
    'vehicle_events',
    VehicleEvent.fromJson,
  );
  final sosDispatches = DbTable<SosDispatch>(
    'sos_dispatches',
    SosDispatch.fromJson,
  );

  late final List<DbTable> tables = [
    employers,
    employees,
    drivers,
    vehicles,
    locations,
    trips,
    routes,
    routeStops,
    bookings,
    passengerEvents,
    shifts,
    inspections,
    incidents,
    billing,
    optimizationConfigs,
    optimizationRuns,
    notifications,
    tickets,
    audit,
    userSettings,
    invoices,
    contracts,
    allocations,
    routeRevisions,
    trafficStates,
    fleetPolicies,
    alcoholTests,
    geofences,
    vehicleEvents,
    sosDispatches,
  ];

  Json _meta = {};
  Json _appState = {};
  int _revision = 0;
  bool _opened = false;
  bool _inTxn = false;
  Future<void> _writeQueue = Future.value();
  Object? lastPersistError;

  int get revision => _revision;
  bool get isOpen => _opened;
  int get schemaVersion => intReq(_meta['schemaVersion'], currentSchemaVersion);
  DateTime? get seededAt => dt(_meta['seededAt']);

  /// The calendar day the demo dataset is anchored to.
  DateTime? get seedAnchorDate => dt(_meta['anchorDate']);
  String? get seedVersion => _meta['seedVersion'] as String?;
  List<String> appliedMigrations = const [];

  /// Loads all tables from storage and runs pending migrations.
  Future<void> open() async {
    final metaRaw = await storage.read(_metaKey);
    _meta = metaRaw == null
        ? {}
        : Map<String, dynamic>.from(jsonDecode(metaRaw));
    final appRaw = await storage.read(_appStateKey);
    _appState = appRaw == null
        ? {}
        : Map<String, dynamic>.from(jsonDecode(appRaw));

    final raw = <String, List<Json>>{};
    for (final t in tables) {
      final s = await storage.read(t.name);
      raw[t.name] = s == null
          ? <Json>[]
          : (jsonDecode(s) as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
    }
    final stored = intReq(_meta['schemaVersion'], currentSchemaVersion);
    appliedMigrations = migrate(
      raw,
      stored,
      context: MigrationContext(dt(_meta['anchorDate']) ?? DateTime.now()),
    );
    for (final t in tables) {
      t._load(raw[t.name]!);
    }
    if (appliedMigrations.isNotEmpty) {
      _meta['schemaVersion'] = currentSchemaVersion;
      await _persistAll();
    }
    _opened = true;
  }

  /// Runs [body] atomically. If it throws, every table touched is rolled
  /// back and nothing is persisted. Nested transactions join the outer one.
  Future<T> transaction<T>(T Function(Txn tx) body) async {
    if (_inTxn) {
      throw StateError('Nested transactions are not supported.');
    }
    final tx = Txn._(this);
    _inTxn = true;
    late T result;
    try {
      result = body(tx);
    } catch (_) {
      tx._rollback();
      _inTxn = false;
      rethrow;
    }
    _inTxn = false;
    final dirty = tx._dirty;
    if (dirty.isNotEmpty) {
      _revision++;
      notifyListeners();
      await _persist(dirty);
    }
    return result;
  }

  Future<void> _persist(Iterable<DbTable> dirty) {
    final payload = {for (final t in dirty) t.name: t._encode()};
    _writeQueue = _writeQueue.then((_) async {
      try {
        for (final e in payload.entries) {
          await storage.write(e.key, e.value);
        }
        lastPersistError = null;
      } catch (e) {
        lastPersistError = e;
      }
    });
    return _writeQueue;
  }

  Future<void> _persistAll() async {
    await _persist(tables);
    await storage.write(_metaKey, jsonEncode(_meta));
  }

  Future<void> markSeeded({
    required DateTime anchorDate,
    required String seedVersion,
    required DateTime at,
  }) async {
    _meta
      ..['schemaVersion'] = currentSchemaVersion
      ..['seededAt'] = dtOut(at)
      ..['anchorDate'] = dtOut(anchorDate)
      ..['seedVersion'] = seedVersion;
    await storage.write(_metaKey, jsonEncode(_meta));
  }

  /// Small persisted app state: selected workspace, demo sessions.
  String? appState(String key) => _appState[key] as String?;

  Future<void> setAppState(String key, String? value) async {
    if (value == null) {
      _appState.remove(key);
    } else {
      _appState[key] = value;
    }
    _revision++;
    notifyListeners();
    await storage.write(_appStateKey, jsonEncode(_appState));
  }

  /// Removes every table, meta and app state. Used only by "Reset demo
  /// data" after explicit confirmation.
  Future<void> wipe() async {
    await _writeQueue;
    for (final t in tables) {
      t._clear();
      await storage.delete(t.name);
    }
    _meta = {};
    _appState = {};
    ids.reset();
    await storage.delete(_metaKey);
    await storage.delete(_appStateKey);
    _revision++;
    notifyListeners();
  }

  /// Waits for pending writes (tests, app shutdown).
  Future<void> flush() => _writeQueue;
}
