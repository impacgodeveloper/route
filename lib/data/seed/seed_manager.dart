import '../../core/demo/clock.dart';
import '../../core/persistence/local_database.dart';
import '../../domain/models/models.dart';
import 'seed_data.dart';
import 'v2_fixtures.dart';
import 'v3_fixtures.dart';

/// Inserts the baseline dataset exactly once.
///
/// * First run: seeds and records `seededAt` in meta.
/// * Later runs: never touches data (user edits are preserved).
/// * [reset]: wipes everything and re-seeds — only called after the user
///   confirms the "Reset demo data" dialog.
class SeedManager {
  SeedManager(this.db, this.clock);

  final LocalDatabase db;
  final Clock clock;

  bool get isSeeded => db.seededAt != null;

  /// Returns true if seeding happened.
  Future<bool> ensureSeeded() async {
    if (isSeeded) return false;
    // Defensive: if tables already contain rows without meta (e.g. an
    // interrupted reset), do not insert duplicates on top of them.
    if (db.employers.length > 0 || db.employees.length > 0) {
      await db.markSeeded(
        anchorDate: dateOnly(clock.now()),
        seedVersion: 'recovered',
        at: clock.now(),
      );
      return false;
    }
    await _insert(SeedDataset(clock.now()));
    return true;
  }

  Future<void> reset() async {
    await db.wipe();
    await _insert(SeedDataset(clock.now()));
    await db.transaction(
      (tx) => tx.insert(
        db.audit,
        AuditEvent(
          id: tx.newId(db.audit, 'AU-'),
          actorRole: UserRole.system,
          actorId: 'demo-tools',
          action: 'demo.reset',
          entityType: 'dataset',
          entityId: seedVersion,
          timestamp: clock.now(),
          summary: 'Demo data reset to baseline after confirmation.',
        ),
      ),
    );
  }

  Future<void> _insert(SeedDataset s) async {
    await db.transaction((tx) {
      for (final r in s.employers) {
        tx.insert(db.employers, V2Fixtures.employer(r));
      }
      for (final r in s.locations) {
        tx.insert(db.locations, V2Fixtures.location(r));
      }
      for (final r in s.employees) {
        tx.insert(db.employees, V2Fixtures.employee(r));
      }
      for (final r in s.vehicles) {
        tx.insert(db.vehicles, V3Fixtures.vehicle(V2Fixtures.vehicle(r)));
      }
      for (final r in s.drivers) {
        tx.insert(db.drivers, V2Fixtures.driver(r, s.d0));
      }
      for (final r in s.routes) {
        tx.insert(db.routes, r);
      }
      for (final r in s.routeStops) {
        tx.insert(db.routeStops, r);
      }
      for (final r in s.trips) {
        tx.insert(db.trips, r);
      }
      for (final r in s.bookings) {
        tx.insert(db.bookings, r);
      }
      for (final r in s.passengerEvents) {
        tx.insert(db.passengerEvents, r);
      }
      for (final r in s.shifts) {
        tx.insert(db.shifts, r);
      }
      for (final r in s.inspections) {
        tx.insert(db.inspections, r);
      }
      for (final r in s.incidents) {
        tx.insert(db.incidents, r);
      }
      for (final r in s.billing) {
        tx.insert(db.billing, r);
      }
      for (final r in s.configs) {
        tx.insert(db.optimizationConfigs, r);
      }
      for (final r in s.runs) {
        tx.insert(db.optimizationRuns, r);
      }
      for (final r in s.notifications) {
        tx.insert(db.notifications, r);
      }
      for (final r in s.tickets) {
        tx.insert(db.tickets, r);
      }
      for (final r in s.audit) {
        tx.insert(db.audit, r);
      }
      for (final r in V2Fixtures.contracts(s.d0)) {
        tx.insert(db.contracts, r);
      }
      for (final r in V2Fixtures.allocations(s.d0)) {
        tx.insert(db.allocations, r);
      }
      tx.insert(db.trafficStates, V2Fixtures.traffic(s.d0));
      tx.insert(db.fleetPolicies, V3Fixtures.policy(s.anchor));
      for (final r in V3Fixtures.alcoholTests(s.anchor)) {
        tx.insert(db.alcoholTests, r);
      }
      for (final r in V3Fixtures.geofences(s.anchor)) {
        tx.insert(db.geofences, r);
      }
      for (final r in V3Fixtures.vehicleEvents(s.anchor)) {
        tx.insert(db.vehicleEvents, r);
      }
    });
    await db.markSeeded(
      anchorDate: s.d0,
      seedVersion: seedVersion,
      at: clock.now(),
    );
  }
}
