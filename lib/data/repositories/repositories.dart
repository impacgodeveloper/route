import '../../core/demo/clock.dart';
import '../../core/persistence/local_database.dart';
import '../../domain/models/models.dart';
import '../../domain/rules/capacity_rules.dart';

/// Read-side repository interfaces. Writes go through domain services.
/// Local implementations read the shared [LocalDatabase]; a future API
/// adapter can implement the same interfaces over a synced cache.
abstract interface class TripRepository {
  List<Trip> all();
  Trip? byId(String? id);
  List<Trip> forEmployee(String employeeId);
  List<Trip> forDriver(String driverId);
  List<Trip> onDay(DateTime day);
  TripRoute? routeOf(Trip trip);
  List<RouteStop> stopsOf(Trip trip);
  List<PassengerEvent> eventsOf(Trip trip);
  PassengerState passengerState(Trip trip, String employeeId);
}

/// Local demo identity — NOT real authentication.
abstract interface class AuthRepository {
  String? get currentEmployeeId;
  String? get currentDriverId;
  String? get lastWorkspace;
}

class LocalTripRepository implements TripRepository {
  LocalTripRepository(this._db);
  final LocalDatabase _db;

  int _byStart(Trip a, Trip b) => a.scheduledStart.compareTo(b.scheduledStart);

  @override
  List<Trip> all() => _db.trips.values.toList()..sort(_byStart);

  @override
  Trip? byId(String? id) => _db.trips[id];

  @override
  List<Trip> forEmployee(String employeeId) =>
      _db.trips.where((t) => t.employeeIds.contains(employeeId)).toList()
        ..sort(_byStart);

  @override
  List<Trip> forDriver(String driverId) =>
      _db.trips.where((t) => t.assignedDriverId == driverId).toList()
        ..sort(_byStart);

  @override
  List<Trip> onDay(DateTime day) =>
      _db.trips.where((t) => sameDay(t.serviceDate, day)).toList()
        ..sort(_byStart);

  @override
  TripRoute? routeOf(Trip trip) => _db.routes[trip.routeId];

  @override
  List<RouteStop> stopsOf(Trip trip) {
    final route = routeOf(trip);
    if (route == null) return const [];
    return route.stopIds
        .map((id) => _db.routeStops[id])
        .whereType<RouteStop>()
        .toList()
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
  }

  @override
  List<PassengerEvent> eventsOf(Trip trip) =>
      _db.passengerEvents.where((e) => e.tripId == trip.id).toList()
        ..sort((a, b) => a.eventTime.compareTo(b.eventTime));

  @override
  PassengerState passengerState(Trip trip, String employeeId) {
    if (trip.alightedPassengerIds.contains(employeeId)) {
      return PassengerState.alighted;
    }
    if (trip.boardedPassengerIds.contains(employeeId)) {
      return PassengerState.boarded;
    }
    if (trip.noShowPassengerIds.contains(employeeId)) {
      return PassengerState.noShow;
    }
    return PassengerState.awaiting;
  }

  /// The stop where [employeeId] boards / alights.
  RouteStop? pickupStopFor(Trip trip, String employeeId) => stopsOf(
    trip,
  ).where((s) => s.boardingEmployeeIds.contains(employeeId)).firstOrNull;
  RouteStop? dropStopFor(Trip trip, String employeeId) => stopsOf(
    trip,
  ).where((s) => s.alightingEmployeeIds.contains(employeeId)).firstOrNull;

  /// Next stop not yet completed/skipped.
  RouteStop? currentStop(Trip trip) =>
      stopsOf(trip).where((s) => !s.isDone).firstOrNull;
}

class LocalAuthRepository implements AuthRepository {
  LocalAuthRepository(this._db);
  final LocalDatabase _db;

  static const employeeKey = 'session.employee';
  static const driverKey = 'session.driver';
  static const workspaceKey = 'lastWorkspace';

  @override
  String? get currentEmployeeId => _db.appState(employeeKey);
  @override
  String? get currentDriverId => _db.appState(driverKey);
  @override
  String? get lastWorkspace => _db.appState(workspaceKey);
}

/// Read-only, query-friendly view over every table.
///
/// A new [DataView] is produced on every committed change (see
/// `dataProvider`), so widgets that watch it rebuild across workspaces.
class DataView {
  DataView(this.db, this.clock)
    : trips = LocalTripRepository(db),
      auth = LocalAuthRepository(db);

  final LocalDatabase db;
  final Clock clock;
  final LocalTripRepository trips;
  final LocalAuthRepository auth;

  DateTime get now => clock.now();
  DateTime get today => dateOnly(clock.now());
  int get revision => db.revision;

  // ---- Organization ----
  List<Employer> get employers => db.employers.all;
  Employer? employer(String? id) => db.employers[id];
  Employer get primaryEmployer => db.employers.values.first;

  List<Employee> get employees => db.employees.all;
  Employee? employee(String? id) => db.employees[id];
  List<Employee> employeesOf(String employerId) =>
      db.employees.where((e) => e.employerId == employerId).toList();
  Employee? employeeByCode(String code) => db.employees
      .where((e) => e.employeeCode.toLowerCase() == code.toLowerCase())
      .firstOrNull;

  // ---- Fleet ----
  List<Driver> get drivers => db.drivers.all;
  Driver? driver(String? id) => db.drivers[id];
  List<Vehicle> get vehicles => db.vehicles.all;
  Vehicle? vehicle(String? id) => db.vehicles[id];
  int capacityOf(Vehicle v, {bool guardRequired = false}) =>
      CapacityRules.passengerCapacity(v, guardRequired: guardRequired);

  // ---- Locations ----
  List<Location> get locations => db.locations.all;
  Location? location(String? id) => db.locations[id];
  Map<String, Location> get locationMap => {
    for (final l in db.locations.values) l.id: l,
  };
  List<Location> locationsOfType(Set<LocationType> types) =>
      db.locations.where((l) => types.contains(l.type)).toList();
  List<Location> get pickupLocations => locationsOfType({
    LocationType.pickup,
    LocationType.intermediateStop,
  }).where((l) => l.active).toList();
  List<Location> get destinations => locationsOfType({
    LocationType.office,
    LocationType.destination,
  }).where((l) => l.active).toList();
  List<Location> get parkingLocations =>
      locationsOfType({LocationType.parking, LocationType.depot});

  // ---- Bookings ----
  List<Booking> get bookings =>
      db.bookings.values.toList()..sort(_newestFirst((r) => r.createdAt));
  Booking? booking(String? id) => db.bookings[id];
  List<Booking> bookingsOf(String employeeId) =>
      bookings.where((b) => b.employeeId == employeeId).toList();
  List<Booking> get openBookings =>
      bookings.where((b) => b.status.isOpen).toList();

  // ---- Driver operations ----
  List<Shift> shiftsOf(String driverId) =>
      db.shifts.where((s) => s.driverId == driverId).toList()
        ..sort(_newestFirst((r) => r.shiftDate));
  Shift? shiftOn(String driverId, DateTime day) => db.shifts
      .where((s) => s.driverId == driverId && sameDay(s.shiftDate, day))
      .firstOrNull;
  Shift? todayShift(String driverId) => shiftOn(driverId, today);

  List<Inspection> get inspections =>
      db.inspections.values.toList()..sort(_newestFirst((r) => r.submittedAt));
  List<Inspection> inspectionsOfVehicle(String vehicleId) =>
      inspections.where((i) => i.vehicleId == vehicleId).toList();
  List<Inspection> inspectionsByDriver(String driverId) =>
      inspections.where((i) => i.driverId == driverId).toList();

  /// Latest inspection of [vehicleId] submitted today (any driver).
  Inspection? todayInspection(String vehicleId) => inspections
      .where((i) => i.vehicleId == vehicleId && sameDay(i.date, today))
      .firstOrNull;

  // ---- Incidents ----
  List<Incident> get incidents =>
      db.incidents.values.toList()..sort(_newestFirst((r) => r.createdAt));
  Incident? incident(String? id) => db.incidents[id];
  List<Incident> get openIncidents =>
      incidents.where((i) => i.status.isOpen).toList();
  List<Incident> incidentsOfTrip(String tripId) =>
      incidents.where((i) => i.tripId == tripId).toList();
  List<Incident> incidentsByDriver(String driverId) => incidents
      .where((i) => i.driverId == driverId || i.reportedById == driverId)
      .toList();

  // ---- Billing ----
  List<BillingRecord> billingOf(String employerId) =>
      db.billing.where((b) => b.employerId == employerId).toList()
        ..sort(_newestFirst((r) => r.completedAt));
  BillingRecord? billingForTrip(String tripId) =>
      db.billing.where((b) => b.tripId == tripId).firstOrNull;
  BillingRecord? billingRecord(String? id) => db.billing[id];

  // ---- Optimization ----
  List<OptimizationConfig> get optimizationConfigs =>
      db.optimizationConfigs.all;
  OptimizationConfig? optimizationConfig(String? id) =>
      db.optimizationConfigs[id];
  List<OptimizationRun> get optimizationRuns =>
      db.optimizationRuns.values.toList()..sort((a, b) {
        final c = b.createdAt.compareTo(a.createdAt);
        return c != 0 ? c : _idNum(b.id).compareTo(_idNum(a.id));
      });
  OptimizationRun? optimizationRun(String? id) => db.optimizationRuns[id];

  // ---- Notifications ----
  List<AppNotification> notificationsFor(
    UserRole role, [
    String? recipientId,
  ]) =>
      db.notifications
          .where(
            (n) =>
                n.recipientRole == role &&
                (n.recipientId == null || n.recipientId == recipientId),
          )
          .toList()
        ..sort(_newestFirst((r) => r.createdAt));
  int unreadCount(UserRole role, [String? recipientId]) =>
      notificationsFor(role, recipientId).where((n) => !n.isRead).length;

  // ---- Support & audit ----
  List<SupportTicket> get tickets =>
      db.tickets.values.toList()..sort(_newestFirst((r) => r.createdAt));
  List<SupportTicket> ticketsBy(UserRole role, String id) => tickets
      .where((t) => t.createdByRole == role && t.createdById == id)
      .toList();
  List<AuditEvent> get auditTrail =>
      db.audit.values.toList()..sort(_newestFirst((r) => r.timestamp));
  List<AuditEvent> auditFor(String entityType, String entityId) => auditTrail
      .where((a) => a.entityType == entityType && a.entityId == entityId)
      .toList();

  // ---------------- v2: commercial & operations ----------------

  List<Invoice> invoicesOf(String employerId) =>
      db.invoices.where((i) => i.employerId == employerId).toList()
        ..sort((a, b) {
          final c = b.periodStart.compareTo(a.periodStart);
          return c != 0 ? c : b.sequence.compareTo(a.sequence);
        });
  Invoice? invoice(String? id) => db.invoices[id];

  List<Contract> contractsOf(String employerId) =>
      db.contracts.where((c) => c.employerId == employerId).toList()
        ..sort((a, b) => b.validFrom.compareTo(a.validFrom));
  List<Contract> get contracts =>
      db.contracts.values.toList()
        ..sort((a, b) => b.validFrom.compareTo(a.validFrom));
  Contract? contract(String? id) => db.contracts[id];

  /// The contract in force for [employerId] on [day], if any.
  Contract? activeContract(String employerId, DateTime day) =>
      contractsOf(employerId).where((c) => c.coversDay(day)).firstOrNull;

  List<FleetAllocation> get allocations => db.allocations.all;
  List<FleetAllocation> allocationsOf(String employerId) =>
      db.allocations.where((a) => a.employerId == employerId).toList();
  List<FleetAllocation> allocationsFor(ResourceType type, String resourceId) =>
      db.allocations
          .where((a) => a.resourceType == type && a.resourceId == resourceId)
          .toList();

  List<RouteRevision> get routeRevisions =>
      db.routeRevisions.values.toList()..sort((a, b) {
        final c = b.createdAt.compareTo(a.createdAt);
        return c != 0 ? c : _idNum(b.id).compareTo(_idNum(a.id));
      });
  List<RouteRevision> revisionsOf(String tripId) =>
      routeRevisions.where((r) => r.tripId == tripId).toList();
  RouteRevision? openRevision(String tripId) => revisionsOf(
    tripId,
  ).where((r) => r.status == RevisionStatus.proposed).firstOrNull;

  TrafficState get traffic =>
      db.trafficStates['current'] ?? TrafficState.initial(today);

  // ---------------- v3: safety, telematics, SOS ----------------

  FleetPolicy get policy =>
      db.fleetPolicies['fleet'] ?? FleetPolicy(updatedAt: today);

  List<AlcoholTest> alcoholTestsOf(String driverId) =>
      db.alcoholTests.where((a) => a.driverId == driverId).toList()
        ..sort(_newestFirst((a) => a.testedAt));
  List<AlcoholTest> get alcoholTests =>
      db.alcoholTests.values.toList()..sort(_newestFirst((a) => a.testedAt));

  /// Blocking test today: an uncleared FAIL (needs Fleet Manager
  /// clearance) or an inconclusive reading with no later pass.
  AlcoholTest? blockingAlcoholTest(String driverId) {
    final today = alcoholTestsOf(
      driverId,
    ).where((a) => sameDay(a.testedAt, now));
    final fail = today
        .where((a) => a.result == AlcoholResult.fail && a.blocking)
        .firstOrNull;
    if (fail != null) return fail;
    final latest = today.firstOrNull;
    return latest != null && latest.result == AlcoholResult.inconclusive
        ? latest
        : null;
  }

  /// Latest passing test today (null = none).
  AlcoholTest? passedAlcoholTestToday(String driverId, {String? tripId}) =>
      alcoholTestsOf(driverId)
          .where(
            (a) =>
                sameDay(a.testedAt, now) &&
                a.result == AlcoholResult.pass &&
                (tripId == null || a.tripId == tripId),
          )
          .firstOrNull;

  List<Geofence> get geofences => db.geofences.all;
  Geofence? geofence(String? id) => db.geofences[id];

  List<VehicleEvent> get vehicleEvents =>
      db.vehicleEvents.values.toList()..sort(_newestFirst((e) => e.occurredAt));
  List<VehicleEvent> vehicleEventsOf(String vehicleId) =>
      vehicleEvents.where((e) => e.vehicleId == vehicleId).toList();
  List<VehicleEvent> get openVehicleEvents =>
      vehicleEvents.where((e) => e.open).toList();

  List<SosDispatch> sosDispatchesOf(String incidentId) =>
      db.sosDispatches.where((d) => d.incidentId == incidentId).toList()
        ..sort((a, b) => a.id.compareTo(b.id));

  // ---- Company metadata (derived from records, never hardcoded) ----
  int companyEmployeeCount(String employerId, {bool activeOnly = true}) => db
      .employees
      .where((e) => e.employerId == employerId && (!activeOnly || e.isActive))
      .length;
  int companyShiftCount(String employerId) =>
      employer(employerId)?.shifts.length ?? 0;
  int companyLocationCount(String employerId) =>
      db.locations.where((l) => l.employerId == employerId && l.active).length;

  // ---- Parking occupancy (derived from vehicles' home parking) ----
  int parkedVehicles(String parkingId) =>
      db.vehicles.where((v) => v.active && v.homeParkingId == parkingId).length;
  int? parkingAvailable(String parkingId) {
    final cap = location(parkingId)?.capacity;
    return cap == null ? null : cap - parkedVehicles(parkingId);
  }

  UserSettings settingsFor(String id) =>
      db.userSettings[id] ?? UserSettings(id: id);

  // ---- Convenience ----
  String employeeLabel(String id) {
    final e = employee(id);
    return e == null ? id : '${e.employeeCode} · ${e.name}';
  }

  String locationLabel(String? id) => location(id)?.label ?? (id ?? '—');
}

/// Numeric suffix of IDs like "OR-1003" (for stable tie-breaking).
int _idNum(String id) => int.tryParse(id.replaceAll(RegExp(r'\D'), '')) ?? 0;

/// Newest first, ties broken by the numeric part of the ID (newer IDs are
/// larger), so lists stay deterministic when timestamps are equal.
Comparator<T> _newestFirst<T extends Entity>(DateTime Function(T) key) =>
    (a, b) {
      final c = key(b).compareTo(key(a));
      return c != 0 ? c : _idNum(b.id).compareTo(_idNum(a.id));
    };
