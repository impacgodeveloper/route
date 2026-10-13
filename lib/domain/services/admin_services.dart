import '../../core/utils/formatters.dart';
import '../../core/utils/result.dart';
import '../models/models.dart';
import '../rules/geo_rules.dart';
import '../rules/tolerance_rules.dart';
import 'resource_sync.dart';
import 'service_context.dart';

/// Employer-level policies (Employer Admin console).
class EmployerService {
  EmployerService(this.ctx);
  final ServiceContext ctx;

  List<String> validate(Employer e) => [
    if (e.name.trim().length < 3) 'Company name is too short.',
    if (e.defaultDistanceRate <= 0 || e.defaultDistanceRate > 200)
      'Rate must be between ₹0.01 and ₹200 per km.',
    if (e.preferredEvPercentage < 0 || e.preferredEvPercentage > 100)
      'EV target must be 0–100%.',
    if (e.maximumArrivalMinutes < 360 || e.maximumArrivalMinutes > 720)
      'Maximum arrival must be between 6:00 AM and 12:00 PM.',
    if (e.costPriority < 0 ||
        e.costPriority > 100 ||
        e.punctualityPriority < 0 ||
        e.punctualityPriority > 100)
      'Priorities must be 0–100.',
    if (e.vehicleTypePreferences.isEmpty) 'Allow at least one vehicle type.',
    ?ToleranceRules.validate(e.pickupToleranceMinutes),
    if (e.additionalChargePerTrip < 0 || e.additionalChargePerTrip > 5000)
      'Additional charge per trip must be ₹0–₹5,000.',
    if (!RegExp(r'^[A-Za-z0-9-]{1,12}$').hasMatch(e.code))
      'Company ID must be 1–12 letters/digits.',
    if (e.shifts.map((s) => s.id).toSet().length != e.shifts.length)
      'Shift IDs must be unique.',
    for (final s in e.shifts) ...[
      if (s.label.trim().isEmpty) 'Every shift needs a label.',
      if (s.startMinutes == s.endMinutes)
        'Shift ${s.label}: start and end cannot be equal.',
    ],
  ];

  Future<Result<Employer>> update(
    Employer next, {
    Actor actor = Actor.employerAdmin,
  }) {
    final errors = validate(next);
    if (errors.isNotEmpty) return Future.value(Err(errors));
    return ctx.run((tx) {
      final prev = ctx.db.employers[next.id];
      if (prev == null) throw ValidationFailure(['Employer not found.']);
      final saved = next.copyWith(updatedAt: ctx.now);
      tx.put(ctx.db.employers, saved);
      final changes = <String>[
        if (prev.maximumArrivalMinutes != saved.maximumArrivalMinutes)
          'max arrival ${Fmt.minutesOfDay(prev.maximumArrivalMinutes)} → ${Fmt.minutesOfDay(saved.maximumArrivalMinutes)}',
        if (prev.defaultDistanceRate != saved.defaultDistanceRate)
          'rate ${Fmt.inr(prev.defaultDistanceRate)} → ${Fmt.inr(saved.defaultDistanceRate)}/km',
        if (prev.preferredEvPercentage != saved.preferredEvPercentage)
          'EV target ${prev.preferredEvPercentage}% → ${saved.preferredEvPercentage}%',
        if (prev.luxuryPreference != saved.luxuryPreference)
          'luxury ${prev.luxuryPreference.label} → ${saved.luxuryPreference.label}',
        if (prev.securityGuardPolicyEnabled != saved.securityGuardPolicyEnabled)
          'guard policy ${saved.securityGuardPolicyEnabled ? 'enabled' : 'disabled'}',
        if (prev.costPriority != saved.costPriority ||
            prev.punctualityPriority != saved.punctualityPriority)
          'priorities cost ${saved.costPriority} / punctuality ${saved.punctualityPriority}',
        if (prev.vehicleTypePreferences
                .toSet()
                .difference(saved.vehicleTypePreferences.toSet())
                .isNotEmpty ||
            saved.vehicleTypePreferences
                .toSet()
                .difference(prev.vehicleTypePreferences.toSet())
                .isNotEmpty)
          'vehicle types ${saved.vehicleTypePreferences.map((t) => t.label).join('/')}',
        if (prev.allowSharedPooling != saved.allowSharedPooling)
          'shared pooling ${saved.allowSharedPooling ? 'allowed' : 'not allowed'}',
        if (prev.allowCrossEmployerPooling != saved.allowCrossEmployerPooling)
          'cross-employer pooling ${saved.allowCrossEmployerPooling ? 'allowed' : 'not allowed'}',
        if (prev.name != saved.name) 'name → ${saved.name}',
        if (prev.pickupToleranceMinutes != saved.pickupToleranceMinutes)
          'pickup tolerance ±${prev.pickupToleranceMinutes} → ±${saved.pickupToleranceMinutes} min',
        if (prev.billingCycle != saved.billingCycle)
          'billing cycle ${prev.billingCycle.label} → ${saved.billingCycle.label}',
        if (prev.billingActive != saved.billingActive)
          'billing ${saved.billingActive ? 'activated' : 'paused'}',
        if (prev.additionalChargePerTrip != saved.additionalChargePerTrip)
          'additional charge ${Fmt.inr(prev.additionalChargePerTrip)} → ${Fmt.inr(saved.additionalChargePerTrip)}/trip',
        if (prev.shifts.map((s) => s.toJson().toString()).join() !=
            saved.shifts.map((s) => s.toJson().toString()).join())
          'shifts ${prev.shifts.length} → ${saved.shifts.length} configured',
        if (prev.status != saved.status) 'status → ${saved.status.label}',
      ];
      // Keep the employer's optimization profile EV target in sync.
      for (final c
          in ctx.db.optimizationConfigs
              .where((c) => c.employerId == saved.id)
              .toList()) {
        tx.put(
          ctx.db.optimizationConfigs,
          c.copyWith(
            minimumEvPercentage: saved.preferredEvPercentage,
            maximumArrivalMinutes: saved.maximumArrivalMinutes,
            updatedAt: ctx.now,
          ),
        );
      }
      if (changes.isNotEmpty) {
        ctx.notify(
          tx,
          role: UserRole.fleetManager,
          title: '${saved.code} policy updated',
          body: changes.join('; '),
          category: NotificationCategory.system,
          entityType: 'employer',
          entityId: saved.id,
        );
      }
      ctx.audit(
        tx,
        actor,
        'employer.update',
        'employer',
        saved.id,
        changes.isEmpty
            ? 'No material changes.'
            : 'Policy: ${changes.join('; ')}.',
        changes: changes.join('; '),
        related: {'company': saved.id},
      );
      return saved;
    }, info: 'Company settings saved');
  }

  /// Registers a new company (Fleet Manager). IDs must be unique.
  Future<Result<Employer>> register(
    Employer e, {
    Actor actor = Actor.fleetManager,
  }) {
    final errors = [
      ...validate(e),
      if (ctx.db.employers.any(
        (x) => x.id == e.id || x.code.toLowerCase() == e.code.toLowerCase(),
      ))
        'Company ID ${e.code} already exists.',
    ];
    if (errors.isNotEmpty) return Future.value(Err(errors));
    return ctx.run((tx) {
      tx.insert(ctx.db.employers, e);
      ctx.audit(
        tx,
        actor,
        'company.register',
        'employer',
        e.id,
        'Registered company ${e.code} · ${e.name}.',
        related: {'company': e.id},
      );
      return e;
    }, info: 'Company registered');
  }

  /// Companies are never deleted (history); they are deactivated.
  Future<Result<Employer>> setActive(
    String id,
    bool active, {
    String reason = '',
    Actor actor = Actor.fleetManager,
  }) {
    if (!active && reason.trim().length < 5) {
      return Future.value(Err.single('Give a reason (at least 5 characters).'));
    }
    return ctx.run((tx) {
      final e = ctx.db.employers[id];
      if (e == null) throw ValidationFailure(['Company not found.']);
      if (!active) {
        final upcoming = ctx.db.trips.where(
          (t) => t.employerId == id && t.status.isUpcoming,
        );
        if (upcoming.isNotEmpty) {
          throw ValidationFailure([
            '${upcoming.length} upcoming trip(s) exist for ${e.code}; cancel or complete them first.',
          ]);
        }
      }
      final next = e.copyWith(
        status: active ? RecordStatus.active : RecordStatus.inactive,
        updatedAt: ctx.now,
      );
      tx.put(ctx.db.employers, next);
      ctx.audit(
        tx,
        actor,
        active ? 'company.reactivate' : 'company.deactivate',
        'employer',
        id,
        '${active ? 'Reactivated' : 'Deactivated'} ${e.code}. History preserved.',
        reason: reason.trim().isEmpty ? null : reason.trim(),
        changes: 'status: ${e.status.label} → ${next.status.label}',
        related: {'company': id},
      );
      return next;
    }, info: active ? 'Company reactivated' : 'Company deactivated');
  }
}

/// Employee records (Employer Admin console).
class EmployeeService {
  EmployeeService(this.ctx);
  final ServiceContext ctx;

  List<String> validate(Employee e, {bool isNew = false}) {
    final db = ctx.db;
    final employer = db.employers[e.employerId];
    return [
      if (e.name.trim().length < 2) 'Name is required.',
      if (!RegExp(r'^[A-Za-z0-9-]{1,12}$').hasMatch(e.employeeCode))
        'Employee ID must be 1–12 letters/digits.',
      if (isNew &&
          db.employees
              .where(
                (x) =>
                    x.employeeCode.toLowerCase() ==
                    e.employeeCode.toLowerCase(),
              )
              .isNotEmpty)
        'Employee ID ${e.employeeCode} already exists.',
      if (db.locations[e.pickupLocationId] == null) 'Unknown pickup location.',
      if (db.locations[e.destinationId] == null) 'Unknown destination.',
      if (employer != null &&
          e.requiredArrivalMinutes > employer.maximumArrivalMinutes)
        'Arrival ${Fmt.minutesOfDay(e.requiredArrivalMinutes)} is after the company maximum ${Fmt.minutesOfDay(employer.maximumArrivalMinutes)}.',
      if (e.fictionalEmail.isNotEmpty && !e.fictionalEmail.contains('@'))
        'Email looks invalid.',
      if (employer == null) 'Unknown company ID ${e.employerId}.',
      if (employer != null && !employer.isActive && isNew)
        'Company ${employer.code} is inactive.',
      if (db.locations[e.pickupLocationId] != null &&
          !{
            LocationType.pickup,
            LocationType.intermediateStop,
          }.contains(db.locations[e.pickupLocationId]!.type))
        'Source must be a pickup point.',
      if (db.locations[e.destinationId] != null &&
          !{
            LocationType.office,
            LocationType.destination,
          }.contains(db.locations[e.destinationId]!.type))
        'Destination must be an office/destination.',
      ...ShiftRules.validate(
        start: e.shiftStartMinutes,
        end: e.shiftEndMinutes,
        arrival: e.requiredArrivalMinutes,
      ),
      if ((e.shiftStartMinutes == null) != (e.shiftEndMinutes == null))
        'Enter both shift start and shift end.',
      ?ToleranceRules.validate(e.pickupToleranceMinutes),
      if (e.travelPreferences.entries.any(
        (p) =>
            !TravelPreferenceKeys.all.contains(p.key) ||
            p.value < 0 ||
            p.value > 3,
      ))
        'Invalid travel preference value.',
    ];
  }

  Future<Result<Employee>> save(
    Employee e, {
    bool isNew = false,
    Actor actor = Actor.employerAdmin,
  }) {
    final errors = validate(e, isNew: isNew);
    if (errors.isNotEmpty) return Future.value(Err(errors));
    return ctx.run((tx) {
      final prev = ctx.db.employees[e.id];
      if (isNew) {
        tx.insert(ctx.db.employees, e);
      } else {
        if (prev == null) {
          throw ValidationFailure(['Employee not found.']);
        }
        tx.put(ctx.db.employees, e);
      }
      ctx.audit(
        tx,
        actor,
        isNew ? 'employee.create' : 'employee.update',
        'employee',
        e.id,
        '${isNew ? 'Created' : 'Updated'} ${e.employeeCode} ${e.name}.',
        changes: prev == null ? '' : employeeChanges(prev, e),
        related: {'company': e.employerId},
      );
      return e;
    }, info: isNew ? 'Employee added' : 'Employee updated');
  }

  /// Deactivation keeps all historical trips/billing intact.
  Future<Result<Employee>> setActive(
    String id,
    bool active, {
    String reason = '',
    Actor actor = Actor.employerAdmin,
  }) => ctx.run(
    (tx) {
      final e = ctx.db.employees[id];
      if (e == null) throw ValidationFailure(['Employee not found.']);
      final next = e.copyWith(
        status: active ? RecordStatus.active : RecordStatus.inactive,
      );
      tx.put(ctx.db.employees, next);
      if (!active) {
        for (final b
            in ctx.db.bookings
                .where((b) => b.employeeId == id && b.status.isOpen)
                .toList()) {
          tx.put(
            ctx.db.bookings,
            b.copyWith(
              status: BookingStatus.cancelled,
              decisionReason: () => 'Employee deactivated.',
              updatedAt: ctx.now,
            ),
          );
        }
      }
      ctx.audit(
        tx,
        actor,
        active ? 'employee.reactivate' : 'employee.deactivate',
        'employee',
        id,
        '${active ? 'Reactivated' : 'Deactivated'} ${e.employeeCode}${reason.isNotEmpty ? ': $reason' : ''}. Trip history preserved.',
      );
      return next;
    },
    info: active
        ? 'Employee reactivated'
        : 'Employee deactivated — trip history kept',
  );

  /// Employee self-service pickup change (only permitted pickup points).
  Future<Result<Employee>> updatePickupPreference(
    String id,
    String pickupLocationId,
    TransportPreference pref,
  ) {
    final loc = ctx.db.locations[pickupLocationId];
    if (loc == null ||
        !loc.active ||
        (loc.type != LocationType.pickup &&
            loc.type != LocationType.intermediateStop)) {
      return Future.value(
        Err.single('Choose an active, permitted pickup point.'),
      );
    }
    return ctx.run((tx) {
      final e = ctx.db.employees[id];
      if (e == null) throw ValidationFailure(['Employee not found.']);
      final next = e.copyWith(
        pickupLocationId: pickupLocationId,
        transportPreference: pref,
      );
      tx.put(ctx.db.employees, next);
      ctx.notify(
        tx,
        role: UserRole.employerAdmin,
        title: '${e.employeeCode} updated preferences',
        body: 'Pickup ${loc.code} · ${pref.label}. Applies to future trips.',
        category: NotificationCategory.system,
        entityType: 'employee',
        entityId: e.id,
      );
      ctx.audit(
        tx,
        Actor.employee(id),
        'employee.preferences',
        'employee',
        id,
        'Pickup → ${loc.code}, preference → ${pref.label}.',
      );
      return next;
    }, info: 'Preferences saved — applies to future trips');
  }
}

/// Vehicles, drivers and locations (Fleet Manager console).
class FleetService {
  FleetService(this.ctx);
  final ServiceContext ctx;

  List<String> validateVehicle(Vehicle v, {bool isNew = false}) => [
    if (!RegExp(r'^[A-Za-z0-9-]{1,10}$').hasMatch(v.vehicleCode))
      'Vehicle ID must be 1–10 letters/digits.',
    if (isNew && ctx.db.vehicles[v.id] != null)
      'Vehicle ID ${v.vehicleCode} already exists.',
    if (v.totalSeats < 2 || v.totalSeats > 30)
      'Total seats (including driver) must be 2–30.',
    if (v.requiresSecurityGuard && v.totalSeats < 3)
      'A guard seat needs at least 3 total seats.',
    if (v.fictionalRegistration.trim().isEmpty)
      'Registration is required (use a fictional value).',
    if (v.odometerKm < 0) 'Odometer cannot be negative.',
    if (v.batteryOrFuelPercent != null &&
        (v.batteryOrFuelPercent! < 0 || v.batteryOrFuelPercent! > 100))
      'Battery/fuel must be 0–100%.',
    if (_dup(v.id, v.fictionalRegistration, (x) => x.fictionalRegistration))
      'Registration ${v.fictionalRegistration} is already used by another vehicle.',
    if (v.rcNumber.trim().isNotEmpty &&
        _dup(v.id, v.rcNumber, (x) => x.rcNumber))
      'RC number ${v.rcNumber} is already used by another vehicle.',
    if (v.engineNumber.trim().isNotEmpty &&
        _dup(v.id, v.engineNumber, (x) => x.engineNumber))
      'Engine number ${v.engineNumber} is already used by another vehicle.',
    if (!v.active &&
        ctx.db.trips.any(
          (t) => t.assignedVehicleId == v.id && t.status.isUpcoming,
        ))
      'Vehicle ${v.vehicleCode} has upcoming trips — reassign them before deactivating.',
    if (v.homeParkingId != null && ctx.db.locations[v.homeParkingId] == null)
      'Unknown home parking.',
  ];

  bool _dup(String id, String value, String Function(Vehicle) key) =>
      value.trim().isNotEmpty &&
      ctx.db.vehicles.any(
        (x) =>
            x.id != id &&
            key(x).trim().toLowerCase() == value.trim().toLowerCase(),
      );

  Future<Result<Vehicle>> saveVehicle(
    Vehicle v, {
    bool isNew = false,
    Actor actor = Actor.fleetManager,
  }) {
    final errors = validateVehicle(v, isNew: isNew);
    if (errors.isNotEmpty) return Future.value(Err(errors));
    return ctx.run((tx) {
      final prev = ctx.db.vehicles[v.id];
      if (isNew) {
        tx.insert(ctx.db.vehicles, v);
      } else {
        tx.put(ctx.db.vehicles, v);
      }
      if (prev != null &&
          prev.status != v.status &&
          (v.status == VehicleStatus.maintenance ||
              v.status == VehicleStatus.unavailable)) {
        final affected = ctx.db.trips
            .where(
              (t) =>
                  t.assignedVehicleId == v.id &&
                  t.actualStart == null &&
                  t.status.isUpcoming,
            )
            .toList();
        for (final t in affected) {
          tx.put(
            ctx.db.trips,
            t.copyWith(
              status: TripStatus.needsAttention,
              delayReason: () =>
                  'Vehicle ${v.vehicleCode} set to ${v.status.label.toLowerCase()}.',
              updatedAt: ctx.now,
            ),
          );
        }
      }
      if (prev != null &&
          prev.status != v.status &&
          v.status == VehicleStatus.available) {
        ResourceSync.vehicle(tx, ctx.db, v.id);
      }
      ctx.audit(
        tx,
        actor,
        isNew ? 'vehicle.create' : 'vehicle.update',
        'vehicle',
        v.id,
        '${isNew ? 'Added' : 'Updated'} Vehicle ${v.vehicleCode} (${v.propulsion.label} ${v.type.label}, ${v.totalSeats} seats, ${v.status.label}).',
        changes: prev == null
            ? ''
            : describeChanges({
                'status': (prev.status.label, v.status.label),
                'active': (prev.active, v.active),
                'seats': (prev.totalSeats, v.totalSeats),
                'registration': (
                  prev.fictionalRegistration,
                  v.fictionalRegistration,
                ),
                'rc': (prev.rcNumber, v.rcNumber),
                'engine': (prev.engineNumber, v.engineNumber),
                'colour': (prev.color, v.color),
                'fuel': (
                  prev.effectiveFuelType.label,
                  v.effectiveFuelType.label,
                ),
                'guardRequired': (
                  prev.requiresSecurityGuard,
                  v.requiresSecurityGuard,
                ),
                'guardAssigned': (
                  prev.securityGuardAssigned,
                  v.securityGuardAssigned,
                ),
                'homeParking': (prev.homeParkingId, v.homeParkingId),
              }),
        related: {'vehicle': v.id},
      );
      return v;
    }, info: isNew ? 'Vehicle added' : 'Vehicle saved');
  }

  List<String> validateDriver(Driver d, {bool isNew = false}) => [
    if (!RegExp(r'^[A-Za-z0-9-]{1,10}$').hasMatch(d.driverCode))
      'Driver ID must be 1–10 letters/digits.',
    if (isNew && ctx.db.drivers[d.id] != null)
      'Driver ID ${d.driverCode} already exists.',
    if (d.name.trim().length < 2) 'Name is required.',
    if (d.shiftEndMinutes <= d.shiftStartMinutes)
      'Shift end must be after shift start.',
    if (d.shiftEndMinutes - d.shiftStartMinutes > 12 * 60)
      'Shift cannot exceed 12 hours.',
    if (d.assignedVehicleId != null &&
        ctx.db.vehicles[d.assignedVehicleId] == null)
      'Unknown vehicle.',
    if (d.licenceNumber.trim().isEmpty) 'Licence number is required.',
    if (d.licenceNumber.trim().isNotEmpty &&
        ctx.db.drivers.any(
          (x) =>
              x.id != d.id &&
              x.licenceNumber.trim().toLowerCase() ==
                  d.licenceNumber.trim().toLowerCase(),
        ))
      'Licence ${d.licenceNumber} is already used by another driver.',
    if (d.email.isNotEmpty && !d.email.contains('@')) 'Email looks invalid.',
    if (!d.active &&
        ctx.db.trips.any(
          (t) => t.assignedDriverId == d.id && t.status.isUpcoming,
        ))
      '${d.driverCode} has upcoming trips — reassign them before deactivating.',
  ];

  Future<Result<Driver>> saveDriver(
    Driver d, {
    bool isNew = false,
    Actor actor = Actor.fleetManager,
  }) {
    final errors = validateDriver(d, isNew: isNew);
    if (errors.isNotEmpty) return Future.value(Err(errors));
    return ctx.run((tx) {
      final prev = ctx.db.drivers[d.id];
      if (isNew) {
        tx.insert(ctx.db.drivers, d);
      } else {
        tx.put(ctx.db.drivers, d);
      }
      // Keep the vehicle's default driver link consistent.
      if (prev?.assignedVehicleId != d.assignedVehicleId) {
        final oldV = ctx.db.vehicles[prev?.assignedVehicleId];
        if (oldV != null && oldV.assignedDriverId == d.id) {
          tx.put(ctx.db.vehicles, oldV.copyWith(assignedDriverId: () => null));
        }
        final newV = ctx.db.vehicles[d.assignedVehicleId];
        if (newV != null) {
          tx.put(ctx.db.vehicles, newV.copyWith(assignedDriverId: () => d.id));
        }
      }
      if (prev != null &&
          prev.status != d.status &&
          (d.status == DriverStatus.offDuty ||
              d.status == DriverStatus.unavailable)) {
        for (final t
            in ctx.db.trips
                .where(
                  (t) =>
                      t.assignedDriverId == d.id &&
                      t.actualStart == null &&
                      t.status.isUpcoming,
                )
                .toList()) {
          tx.put(
            ctx.db.trips,
            t.copyWith(
              status: TripStatus.needsAttention,
              delayReason: () =>
                  '${d.driverCode} is ${d.status.label.toLowerCase()}.',
              updatedAt: ctx.now,
            ),
          );
        }
      }
      ctx.audit(
        tx,
        actor,
        isNew ? 'driver.create' : 'driver.update',
        'driver',
        d.id,
        '${isNew ? 'Added' : 'Updated'} ${d.driverCode} ${d.name} (${d.status.label}).',
        changes: prev == null
            ? ''
            : describeChanges({
                'status': (prev.status.label, d.status.label),
                'active': (prev.active, d.active),
                'vehicle': (prev.assignedVehicleId, d.assignedVehicleId),
                'shift': (
                  '${prev.shiftStartMinutes}-${prev.shiftEndMinutes}',
                  '${d.shiftStartMinutes}-${d.shiftEndMinutes}',
                ),
                'licence': (prev.licenceNumber, d.licenceNumber),
                'licenceExpiry': (
                  Fmt.date(prev.licenceExpiry),
                  Fmt.date(d.licenceExpiry),
                ),
              }),
        related: {'driver': d.id},
      );
      return d;
    }, info: isNew ? 'Driver added' : 'Driver saved');
  }

  List<String> validateLocation(Location l, {bool isNew = false}) => [
    if (!RegExp(r'^[A-Za-z0-9-]{1,10}$').hasMatch(l.code))
      'Code must be 1–10 letters/digits.',
    if (isNew && ctx.db.locations[l.id] != null)
      'Code ${l.code} already exists.',
    if (l.name.trim().length < 3) 'Name is required.',
    if (l.demoX < 0 || l.demoX > 40 || l.demoY < 0 || l.demoY > 40)
      'Fictional coordinates must fall inside the demo service area (lat ${GeoRules.latFromY(0)}–${GeoRules.latFromY(40)}, lng ${GeoRules.lngFromX(0)}–${GeoRules.lngFromX(40)}).',
    if (l.latitude != null && !GeoRules.validLat(l.latitude))
      'Latitude must be between −90 and 90.',
    if (l.longitude != null && !GeoRules.validLng(l.longitude))
      'Longitude must be between −180 and 180.',
    if (l.isParking && (l.capacity == null || l.capacity! < 1))
      'Parking capacity must be at least 1 spot.',
    if (l.isParking &&
        l.capacity != null &&
        !isNew &&
        l.capacity! < ctx.view.parkedVehicles(l.id))
      'Capacity cannot be below the ${ctx.view.parkedVehicles(l.id)} vehicle(s) currently based here.',
  ];

  /// Keeps the routing plane (km) in sync with entered fictional lat/lng.
  Location normalizeCoordinates(Location l) {
    if (l.latitude == null || l.longitude == null) {
      return l.copyWith(
        latitude: () => GeoRules.latFromY(l.demoY),
        longitude: () => GeoRules.lngFromX(l.demoX),
      );
    }
    return l.copyWith(
      demoX: double.parse(GeoRules.xFromLng(l.longitude!).toStringAsFixed(2)),
      demoY: double.parse(GeoRules.yFromLat(l.latitude!).toStringAsFixed(2)),
    );
  }

  Future<Result<Location>> saveLocation(
    Location l, {
    bool isNew = false,
    Actor actor = Actor.fleetManager,
  }) {
    l = normalizeCoordinates(l);
    final errors = validateLocation(l, isNew: isNew);
    if (errors.isNotEmpty) return Future.value(Err(errors));
    if (!l.active) {
      final inUse = ctx.db.employees
          .where(
            (e) =>
                e.isActive &&
                (e.pickupLocationId == l.id || e.destinationId == l.id),
          )
          .length;
      if (inUse > 0) {
        return Future.value(
          Err.single(
            '$inUse active employee${inUse == 1 ? '' : 's'} use ${l.code}. Move them before deactivating.',
          ),
        );
      }
    }
    return ctx.run((tx) {
      final prev = ctx.db.locations[l.id];
      if (isNew) {
        tx.insert(ctx.db.locations, l);
      } else {
        tx.put(ctx.db.locations, l);
      }
      ctx.audit(
        tx,
        actor,
        isNew ? 'location.create' : 'location.update',
        'location',
        l.id,
        '${isNew ? 'Added' : 'Updated'} ${l.code} ${l.name} (${l.type.label}).',
        changes: prev == null
            ? ''
            : describeChanges({
                'name': (prev.name, l.name),
                'active': (prev.active, l.active),
                'capacity': (prev.capacity, l.capacity),
                'lat': (prev.latitude, l.latitude),
                'lng': (prev.longitude, l.longitude),
              }),
      );
      return l;
    }, info: isNew ? 'Location added' : 'Location saved');
  }
}

/// Safe before → after summary of employee changes for the audit trail.
String employeeChanges(Employee a, Employee b) {
  String hm(int? m) => m == null ? '—' : Fmt.minutesOfDay(m);
  String prefs(Map<String, int> p) => p.entries
      .where((e) => e.value > 0)
      .map((e) => '${e.key}=${e.value}')
      .join(',');
  return describeChanges({
    'name': (a.name, b.name),
    'pickup': (a.pickupLocationId, b.pickupLocationId),
    'destination': (a.destinationId, b.destinationId),
    'arrival': (hm(a.requiredArrivalMinutes), hm(b.requiredArrivalMinutes)),
    'shift': (
      '${hm(a.shiftStartMinutes)}–${hm(a.shiftEndMinutes)}',
      '${hm(b.shiftStartMinutes)}–${hm(b.shiftEndMinutes)}',
    ),
    'tolerance': (a.pickupToleranceMinutes, b.pickupToleranceMinutes),
    'preference': (a.transportPreference.label, b.transportPreference.label),
    'travelPrefs': (prefs(a.travelPreferences), prefs(b.travelPreferences)),
    'status': (a.status.label, b.status.label),
    'guardEscort': (a.guardEscortRequired, b.guardEscortRequired),
  });
}

/// Employee self-service: soft travel preferences (time/distance/detour/
/// reliability). Persisted locally and read by the optimizer on its next
/// run. Never reassigns existing trips.
extension TravelPreferenceOps on EmployeeService {
  Future<Result<Employee>> updateTravelPreferences(
    String employeeId,
    Map<String, int> preferences,
  ) {
    final bad = preferences.entries.where(
      (p) =>
          !TravelPreferenceKeys.all.contains(p.key) ||
          p.value < 0 ||
          p.value > 3,
    );
    if (bad.isNotEmpty) {
      return Future.value(Err.single('Invalid preference value.'));
    }
    return ctx.run((tx) {
      final e = ctx.db.employees[employeeId];
      if (e == null) throw ValidationFailure(['Employee not found.']);
      final next = e.copyWith(
        travelPreferences: {
          for (final p in preferences.entries)
            if (p.value > 0) p.key: p.value,
        },
      );
      tx.put(ctx.db.employees, next);
      ctx.audit(
        tx,
        Actor.employee(employeeId),
        'employee.travelPreferences',
        'employee',
        employeeId,
        '${e.employeeCode} updated travel preferences (applies to future optimization runs).',
        changes: employeeChanges(e, next),
        related: {'company': e.employerId},
      );
      return next;
    }, info: 'Preferences saved — used by the next optimization run');
  }
}
