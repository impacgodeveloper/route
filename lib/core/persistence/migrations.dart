import '../../data/seed/v2_fixtures.dart';
import '../../data/seed/v3_fixtures.dart';
import '../../domain/models/models.dart';

/// Current on-disk schema version. Bump it and add a migration whenever a
/// persisted field is renamed, removed or changes meaning.
///
/// * v1 — baseline (four workspaces).
/// * v2 — client-architecture increment: employee shifts/tolerance/
///   preferences, fictional lat/lng, vehicle inventory, driver records,
///   contracts, fleet allocations, invoices, traffic state, route revisions,
///   richer audit records.
/// * v3 — safety & telematics increment: fleet policy (alcohol monitoring,
///   speed/geofence alerts, SOS chain, auto-match, analytics assumptions),
///   alcohol tests, geofences, vehicle events, SOS dispatches, trip
///   absences, vehicle diagnostic codes.
const int currentSchemaVersion = 3;

/// Raw table rows keyed by table name, migrated in place before decoding.
typedef RawTables = Map<String, List<Json>>;

/// Migration context (the demo anchor date for date-relative fixtures).
class MigrationContext {
  const MigrationContext(this.anchor);
  final DateTime anchor;
}

/// `from -> to` migrations. Each entry upgrades data written by schema
/// version `key` to `key + 1`. Steps only ADD fields/rows; existing records
/// and IDs are never replaced.
final Map<int, void Function(RawTables tables, MigrationContext ctx)>
schemaMigrations = {1: _v1ToV2, 2: _v2ToV3};

void _v1ToV2(RawTables t, MigrationContext ctx) {
  List<Json> map<T extends Entity>(
    String table,
    T Function(Json) from,
    T Function(T) apply,
  ) => [for (final r in t[table] ?? <Json>[]) apply(from(r)).toJson()];

  // Only touch datasets that were actually seeded (non-empty).
  if ((t['employers'] ?? []).isEmpty) return;
  t['employers'] = map('employers', Employer.fromJson, V2Fixtures.employer);
  t['employees'] = map('employees', Employee.fromJson, V2Fixtures.employee);
  t['locations'] = map('locations', Location.fromJson, V2Fixtures.location);
  t['vehicles'] = map('vehicles', Vehicle.fromJson, V2Fixtures.vehicle);
  t['drivers'] = map(
    'drivers',
    Driver.fromJson,
    (d) => V2Fixtures.driver(d, ctx.anchor),
  );
  if ((t['contracts'] ?? []).isEmpty) {
    t['contracts'] = [
      for (final c in V2Fixtures.contracts(ctx.anchor)) c.toJson(),
    ];
  }
  if ((t['fleet_allocations'] ?? []).isEmpty) {
    t['fleet_allocations'] = [
      for (final a in V2Fixtures.allocations(ctx.anchor)) a.toJson(),
    ];
  }
  if ((t['traffic_state'] ?? []).isEmpty) {
    t['traffic_state'] = [V2Fixtures.traffic(ctx.anchor).toJson()];
  }
  t['invoices'] ??= [];
  t['route_revisions'] ??= [];
}

void _v2ToV3(RawTables t, MigrationContext ctx) {
  if ((t['employers'] ?? []).isEmpty) return;
  t['vehicles'] = [
    for (final r in t['vehicles'] ?? <Json>[])
      V3Fixtures.vehicle(Vehicle.fromJson(r)).toJson(),
  ];
  if ((t['fleet_policy'] ?? []).isEmpty) {
    t['fleet_policy'] = [V3Fixtures.policy(ctx.anchor).toJson()];
  }
  if ((t['alcohol_tests'] ?? []).isEmpty) {
    t['alcohol_tests'] = [
      for (final a in V3Fixtures.alcoholTests(ctx.anchor)) a.toJson(),
    ];
  }
  if ((t['geofences'] ?? []).isEmpty) {
    t['geofences'] = [
      for (final g in V3Fixtures.geofences(ctx.anchor)) g.toJson(),
    ];
  }
  if ((t['vehicle_events'] ?? []).isEmpty) {
    t['vehicle_events'] = [
      for (final e in V3Fixtures.vehicleEvents(ctx.anchor)) e.toJson(),
    ];
  }
  t['sos_dispatches'] ??= [];
}

/// Applies every migration between [fromVersion] and [currentSchemaVersion].
/// Returns the list of applied steps for logging/diagnostics.
List<String> migrate(
  RawTables tables,
  int fromVersion, {
  MigrationContext? context,
}) {
  final ctx = context ?? MigrationContext(DateTime.now());
  final applied = <String>[];
  for (var v = fromVersion; v < currentSchemaVersion; v++) {
    final step = schemaMigrations[v];
    if (step != null) {
      step(tables, ctx);
      applied.add('v$v→v${v + 1}');
    }
  }
  return applied;
}
