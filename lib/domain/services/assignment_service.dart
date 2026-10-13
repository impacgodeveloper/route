import '../../core/demo/clock.dart';
import '../../core/persistence/local_database.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/result.dart';
import '../models/models.dart';
import '../rules/capacity_rules.dart';
import '../rules/parameter_catalog.dart';
import '../rules/tolerance_rules.dart';
import '../rules/trip_state_machine.dart';
import 'resource_sync.dart';
import 'route_builder.dart';
import 'service_context.dart';

class AssignmentRequest {
  const AssignmentRequest({
    this.tripId,
    required this.employerId,
    required this.serviceDate,
    required this.employeeIds,
    this.scheduledStart,
    this.driverId,
    this.vehicleId,
    this.guardRequired = false,
    this.variant = RouteVariant.internalRoads,
    this.instructions = '',
    this.allowDriverOverride = false,
    this.overrideReason,
    this.reassignReason,
    this.bookingIds = const [],
    this.optimizationRunId,
    this.plannedStops,
    this.guardReference,
  });

  /// Existing trip to (re)assign; null creates a new trip.
  final String? tripId;
  final String employerId;
  final DateTime serviceDate;
  final List<String> employeeIds;

  /// Null = computed backwards from the earliest arrival deadline.
  final DateTime? scheduledStart;
  final String? driverId;
  final String? vehicleId;
  final bool guardRequired;
  final RouteVariant variant;
  final String instructions;

  /// Explicit, reasoned override to use an off-duty/unavailable driver.
  final bool allowDriverOverride;
  final String? overrideReason;

  /// Required when changing an existing driver/vehicle assignment.
  final String? reassignReason;
  final List<String> bookingIds;
  final String? optimizationRunId;

  /// Pre-computed stop order (from the optimizer). Optional.
  final List<PlannedStop>? plannedStops;

  /// Security guard name/ID when a guard is required (demo reference).
  final String? guardReference;

  AssignmentRequest copyWith({
    String? driverId,
    String? vehicleId,
    List<String>? employeeIds,
    DateTime? scheduledStart,
    String? reassignReason,
  }) => AssignmentRequest(
    tripId: tripId,
    employerId: employerId,
    serviceDate: serviceDate,
    employeeIds: employeeIds ?? this.employeeIds,
    scheduledStart: scheduledStart ?? this.scheduledStart,
    driverId: driverId ?? this.driverId,
    vehicleId: vehicleId ?? this.vehicleId,
    guardRequired: guardRequired,
    variant: variant,
    instructions: instructions,
    allowDriverOverride: allowDriverOverride,
    overrideReason: overrideReason,
    reassignReason: reassignReason ?? this.reassignReason,
    bookingIds: bookingIds,
    optimizationRunId: optimizationRunId,
    plannedStops: plannedStops,
    guardReference: guardReference,
  );
}

class AssignmentValidation {
  AssignmentValidation({
    required this.errors,
    required this.warnings,
    this.seats,
    this.plan,
    this.isReassignment = false,
  });

  final List<String> errors;
  final List<String> warnings;
  final SeatBreakdown? seats;
  final RoutePlan? plan;
  final bool isReassignment;
  bool get ok => errors.isEmpty;
}

/// Validates and saves trip assignments. Every rule here is a hard
/// constraint unless returned as a warning.
class AssignmentService {
  AssignmentService(this.ctx);
  final ServiceContext ctx;

  int _param(String key) {
    final cfg = ctx.db.optimizationConfigs.values.firstOrNull;
    final def = ParameterCatalog.byKey(key)?.defaultValue ?? 0;
    return (cfg == null ? def : ParameterCatalog.value(cfg, key)).round();
  }

  bool _overlaps(Trip t, DateTime start, DateTime end, Duration buffer) =>
      TripStateMachine.occupiesWindow(t.status) &&
      t.scheduledStart.isBefore(end.add(buffer)) &&
      t.windowEnd.add(buffer).isAfter(start);

  AssignmentValidation validate(AssignmentRequest r) {
    final db = ctx.db;
    final errors = <String>[];
    final warnings = <String>[];
    final employer = db.employers[r.employerId];
    if (employer == null) errors.add('Employer ${r.employerId} not found.');
    final existing = r.tripId == null ? null : db.trips[r.tripId];
    if (r.tripId != null && existing == null) {
      errors.add('Trip ${r.tripId} not found.');
    }
    if (existing != null && !TripStateMachine.canAssign(existing.status)) {
      errors.add(
        '${existing.tripCode} is ${existing.status.label.toLowerCase()} and cannot be reassigned.',
      );
    }
    if (r.employeeIds.isEmpty) errors.add('Select at least one employee.');
    final employees = <Employee>[];
    for (final id in r.employeeIds) {
      final e = db.employees[id];
      if (e == null) {
        errors.add('Employee $id not found.');
        continue;
      }
      if (!e.isActive) errors.add('${e.employeeCode} is inactive.');
      if (employer != null &&
          e.employerId != employer.id &&
          !employer.allowCrossEmployerPooling) {
        errors.add(
          '${e.employeeCode} belongs to another employer; cross-employer pooling is not allowed.',
        );
      }
      employees.add(e);
    }
    if (errors.isNotEmpty || employer == null) {
      return AssignmentValidation(errors: errors, warnings: warnings);
    }

    // Booking requests override profile pickup/destination/arrival.
    final linked = {
      for (final b in db.bookings.where(
        (b) =>
            (r.bookingIds.contains(b.id) ||
                (r.tripId != null && b.tripId == r.tripId)) &&
            b.status != BookingStatus.cancelled &&
            b.status != BookingStatus.rejected,
      ))
        b.employeeId: b,
    };
    final planned = [
      for (final e in employees)
        linked[e.id] == null
            ? e
            : e.copyWith(
                pickupLocationId: linked[e.id]!.requestedPickupLocationId,
                destinationId: linked[e.id]!.requestedDestinationId,
                requiredArrivalMinutes: linked[e.id]!.requestedArrivalMinutes,
              ),
    ];

    // Deadline = min(required arrival, shift start, employer maximum).
    final capped = [
      for (final e in planned)
        e.copyWith(
          requiredArrivalMinutes:
              e.arrivalDeadlineMinutes < employer.maximumArrivalMinutes
              ? e.arrivalDeadlineMinutes
              : employer.maximumArrivalMinutes,
        ),
    ];
    if (!employer.isActive) {
      errors.add('Company ${employer.code} is inactive.');
    }

    // Route plan (keep existing route when nothing material changed).
    final locs = ctx.view.locationMap;
    RoutePlan plan;
    final unchanged =
        existing != null &&
        existing.routeId != null &&
        _sameSet(existing.employeeIds, r.employeeIds) &&
        (r.scheduledStart == null ||
            r.scheduledStart == existing.scheduledStart);
    if (unchanged) {
      final stops = ctx.view.trips.stopsOf(existing);
      plan = RoutePlan(
        stops: [
          for (final s in stops)
            PlannedStop(
              locationId: s.locationId,
              kind: s.kind,
              employeeIds: s.kind == StopKind.pickup
                  ? s.boardingEmployeeIds
                  : s.alightingEmployeeIds,
              plannedArrival: s.plannedArrival,
            ),
        ],
        distanceKm: ctx.view.trips.routeOf(existing)?.estimatedDistanceKm ?? 0,
        durationMinutes: existing.estimatedDurationMinutes ?? 0,
        departure: existing.scheduledStart,
        variant: ctx.view.trips.routeOf(existing)?.variant ?? r.variant,
      );
    } else if (r.plannedStops != null && r.plannedStops!.isNotEmpty) {
      plan = RouteBuilder.plan(
        employees: capped,
        locations: locs,
        departure: r.plannedStops!.first.plannedArrival,
        variant: r.variant,
        pickupOrder: r.plannedStops!
            .where((s) => s.kind == StopKind.pickup)
            .map((s) => s.locationId)
            .toList(),
      );
    } else if (r.scheduledStart != null) {
      plan = RouteBuilder.plan(
        employees: capped,
        locations: locs,
        departure: r.scheduledStart!,
        variant: r.variant,
      );
    } else {
      plan = RouteBuilder.planForDeadline(
        employees: capped,
        locations: locs,
        serviceDay: r.serviceDate,
        bufferMinutes: _param('arrival_buffer_min'),
        variant: r.variant,
      );
    }

    if (existing == null || !unchanged) {
      for (final e in capped) {
        final drop = plan.dropTimeFor(e.id);
        final deadline = atMinutes(r.serviceDate, e.requiredArrivalMinutes);
        if (drop != null && drop.isAfter(deadline)) {
          errors.add(
            '${e.employeeCode} would arrive ${Fmt.time(drop)}, after the required ${Fmt.time(deadline)}. Start earlier or split the group.',
          );
        }
      }
      if (existing == null &&
          plan.departure.isBefore(
            ctx.now.subtract(const Duration(minutes: 5)),
          )) {
        errors.add(
          'Planned start ${Fmt.dateTime(plan.departure)} is in the past.',
        );
      }
    }

    final buffer = Duration(minutes: _param('assignment_overlap_buffer_min'));
    final start = plan.departure;
    final end = plan.arrival;
    final others = db.trips.where((t) => t.id != r.tripId).toList();

    for (final e in employees) {
      final clash = others.where(
        (t) =>
            sameDay(t.serviceDate, r.serviceDate) &&
            t.employeeIds.contains(e.id) &&
            TripStateMachine.occupiesWindow(t.status),
      );
      if (clash.isNotEmpty) {
        errors.add(
          '${e.employeeCode} is already on ${clash.first.tripCode} that day.',
        );
      }
    }

    SeatBreakdown? seats;
    if (r.vehicleId != null) {
      final v = db.vehicles[r.vehicleId];
      if (v == null) {
        errors.add('Vehicle ${r.vehicleId} not found.');
      } else {
        final guard = CapacityRules.guardRequired(
          vehicle: v,
          tripGuardRequired: r.guardRequired,
          employer: employer,
          passengers: employees,
        );
        seats = CapacityRules.breakdown(v, guardRequired: guard);
        if (!v.active) {
          errors.add('Vehicle ${v.vehicleCode} is deactivated.');
        }
        if (v.status == VehicleStatus.maintenance) {
          errors.add('Vehicle ${v.vehicleCode} is in maintenance.');
        }
        if (v.status == VehicleStatus.unavailable) {
          errors.add('Vehicle ${v.vehicleCode} is unavailable.');
        }
        if (employees.length > seats.passengerCapacity) {
          errors.add(
            'Over capacity: ${employees.length} employees but Vehicle ${v.vehicleCode} seats ${seats.passengerCapacity} ($seats).',
          );
        }
        if (v.assignedEmployerId != null &&
            v.assignedEmployerId != employer.id) {
          errors.add(
            'Vehicle ${v.vehicleCode} is dedicated to another employer.',
          );
        }
        final conflict = others.where(
          (t) =>
              t.assignedVehicleId == v.id && _overlaps(t, start, end, buffer),
        );
        if (conflict.isNotEmpty) {
          errors.add(
            'Vehicle ${v.vehicleCode} is already assigned to ${conflict.first.tripCode} (${Fmt.time(conflict.first.scheduledStart)}–${Fmt.time(conflict.first.windowEnd)}).',
          );
        }
        if (employer.vehicleTypePreferences.isNotEmpty &&
            !employer.vehicleTypePreferences.contains(v.type)) {
          warnings.add(
            '${v.type.label} is not in ${employer.code}\'s preferred vehicle types.',
          );
        }
        final level = v.batteryOrFuelPercent;
        if (level != null) {
          final min = v.isEv
              ? _param('min_battery_pct')
              : _param('min_fuel_pct');
          if (level < min) {
            warnings.add(
              'Vehicle ${v.vehicleCode} ${v.isEv ? 'battery' : 'fuel'} is $level% (minimum $min%).',
            );
          }
        }
        // Guard is a HARD constraint: a guard must actually be assigned.
        if (guard &&
            !v.securityGuardAssigned &&
            (r.guardReference?.trim().isEmpty ?? true)) {
          errors.add(
            'Security guard required but none assigned — enter the guard reference or assign a guard to Vehicle ${v.vehicleCode}.',
          );
        }
      }
    }
    if (r.driverId != null) {
      final d = db.drivers[r.driverId];
      if (d == null) {
        errors.add('Driver ${r.driverId} not found.');
      } else {
        if (!d.active) errors.add('${d.driverCode} is deactivated.');
        if (d.licenceNumber.trim().isEmpty) {
          errors.add('${d.driverCode} has no licence number on record.');
        } else if (!d.licenceValidOn(r.serviceDate)) {
          errors.add(
            '${d.driverCode} licence expired on ${Fmt.date(d.licenceExpiry)}.',
          );
        } else if (d.licenceExpiry != null &&
            d.licenceExpiry!.difference(r.serviceDate).inDays <= 30) {
          warnings.add(
            '${d.driverCode} licence expires on ${Fmt.date(d.licenceExpiry)}.',
          );
        }
        if (d.status == DriverStatus.offDuty ||
            d.status == DriverStatus.unavailable) {
          if (r.allowDriverOverride &&
              (r.overrideReason?.trim().length ?? 0) >= 5) {
            warnings.add(
              'Override: ${d.driverCode} is ${d.status.label.toLowerCase()} — reason recorded.',
            );
          } else {
            errors.add(
              '${d.driverCode} ${d.name} is ${d.status.label.toLowerCase()}. Use an explicit override with a reason to assign.',
            );
          }
        }
        final conflict = others.where(
          (t) => t.assignedDriverId == d.id && _overlaps(t, start, end, buffer),
        );
        if (conflict.isNotEmpty) {
          errors.add(
            '${d.driverCode} is already assigned to ${conflict.first.tripCode} in an overlapping window.',
          );
        }
        final shiftEnd = atMinutes(r.serviceDate, d.shiftEndMinutes);
        final shiftStart = atMinutes(r.serviceDate, d.shiftStartMinutes);
        if (start.isBefore(shiftStart) || end.isAfter(shiftEnd)) {
          warnings.add(
            'Trip window ${Fmt.time(start)}–${Fmt.time(end)} is outside ${d.driverCode}\'s shift ${Fmt.minutesOfDay(d.shiftStartMinutes)}–${Fmt.minutesOfDay(d.shiftEndMinutes)}.',
          );
        }
      }
    }
    // Contract and fleet-company allocation (hard policy).
    final windowStart = CommercialRules.minutesOf(start);
    final windowEnd = CommercialRules.minutesOf(end);
    if (r.vehicleId != null && db.vehicles[r.vehicleId] != null) {
      final dayVehicles = <String>{
        for (final t in others)
          if (t.employerId == employer.id &&
              t.assignedVehicleId != null &&
              sameDay(t.serviceDate, r.serviceDate) &&
              TripStateMachine.occupiesWindow(t.status))
            t.assignedVehicleId!,
        r.vehicleId!,
      };
      final c = CommercialRules.contract(
        contracts: ctx.view.contractsOf(employer.id),
        employerCode: employer.code,
        day: r.serviceDate,
        vehicleIdsThatDay: dayVehicles,
      );
      errors.addAll(c.errors);
      warnings.addAll(c.warnings);
      final alloc = CommercialRules.allocation(
        resourceAllocations: ctx.view.allocationsFor(
          ResourceType.vehicle,
          r.vehicleId!,
        ),
        employerId: employer.id,
        employerCode: employer.code,
        resourceLabel: 'Vehicle ${db.vehicles[r.vehicleId]!.vehicleCode}',
        startMinutes: windowStart,
        endMinutes: windowEnd,
      );
      if (alloc != null) errors.add(alloc);
    }
    if (r.driverId != null && db.drivers[r.driverId] != null) {
      final alloc = CommercialRules.allocation(
        resourceAllocations: ctx.view.allocationsFor(
          ResourceType.driver,
          r.driverId!,
        ),
        employerId: employer.id,
        employerCode: employer.code,
        resourceLabel: db.drivers[r.driverId]!.driverCode,
        startMinutes: windowStart,
        endMinutes: windowEnd,
      );
      if (alloc != null) errors.add(alloc);
    }
    if (r.driverId == null || r.vehicleId == null) {
      warnings.add(
        'Without both a driver and a vehicle the trip is saved as planned (not assigned).',
      );
    }
    final isReassign =
        existing != null &&
        existing.isAssigned &&
        (existing.assignedDriverId != r.driverId ||
            existing.assignedVehicleId != r.vehicleId);
    if (isReassign && (r.reassignReason?.trim().length ?? 0) < 5) {
      errors.add('Reassignment needs a reason (at least 5 characters).');
    }
    return AssignmentValidation(
      errors: errors,
      warnings: warnings,
      seats: seats,
      plan: plan,
      isReassignment: isReassign,
    );
  }

  /// Creates or updates the trip after re-validating inside the transaction.
  Future<Result<Trip>> commit(
    AssignmentRequest r, {
    Actor actor = Actor.fleetManager,
  }) {
    return ctx.run(
      (tx) => commitInTx(tx, r, actor),
      warnings: (_) => validate(r).warnings,
      rejectAudit: RejectAudit(
        actor: actor,
        action: r.tripId == null ? 'trip.create' : 'assign',
        entityType: 'trip',
        entityId: r.tripId ?? '(new)',
        summary:
            'Assignment ${r.employeeIds.join(', ')} → ${r.driverId ?? '—'} / Vehicle ${r.vehicleId ?? '—'}',
        related: {
          'company': r.employerId,
          if (r.vehicleId != null) 'vehicle': r.vehicleId!,
          if (r.driverId != null) 'driver': r.driverId!,
        },
      ),
    );
  }

  Trip commitInTx(Txn tx, AssignmentRequest r, Actor actor) {
    final db = ctx.db;
    final v = validate(r);
    if (!v.ok) throw ValidationFailure(v.errors);
    final plan = v.plan!;
    final existing = r.tripId == null ? null : db.trips[r.tripId];
    final assigned = r.driverId != null && r.vehicleId != null;
    final now = ctx.now;

    String routeId;
    if (existing != null &&
        existing.routeId != null &&
        _sameSet(existing.employeeIds, r.employeeIds) &&
        (r.scheduledStart == null ||
            r.scheduledStart == existing.scheduledStart)) {
      routeId = existing.routeId!;
    } else {
      // Replace route (only before the trip has started).
      if (existing?.routeId != null) {
        final old = db.routes[existing!.routeId];
        if (old != null) {
          for (final sid in old.stopIds) {
            tx.delete(db.routeStops, sid);
          }
          tx.delete(db.routes, old.id);
        }
      }
      routeId = tx.newId(db.routes, 'R-');
      final emps = r.employeeIds.map((id) => db.employees[id]!).toList();
      final (route, stops) = RouteBuilder.materialize(
        plan: plan,
        routeId: routeId,
        routeCode: routeId.replaceAll('-', ''),
        name:
            '${emps.first.employeeCode}${emps.length > 1 ? '–${emps.last.employeeCode}' : ''} → ${plan.stops.where((s) => s.kind == StopKind.drop).map((s) => s.locationId).join('/')}',
        employerId: r.employerId,
        optimizationRunId: r.optimizationRunId,
      );
      tx.put(db.routes, route);
      for (final s in stops) {
        tx.put(db.routeStops, s);
      }
    }

    final history = [
      ...?existing?.assignmentHistory,
      if (assigned &&
          (existing == null ||
              existing.assignedDriverId != r.driverId ||
              existing.assignedVehicleId != r.vehicleId))
        AssignmentRecord(
          at: now,
          actorRole: actor.role,
          driverId: r.driverId,
          vehicleId: r.vehicleId,
          reason: v.isReassignment
              ? r.reassignReason!.trim()
              : (r.overrideReason?.trim().isNotEmpty == true
                    ? 'Override: ${r.overrideReason!.trim()}'
                    : 'Initial assignment'),
        ),
    ];
    final status = existing?.actualStart != null
        ? TripStatus.inProgress
        : assigned
        ? TripStatus.assigned
        : TripStatus.planned;

    final Trip trip;
    if (existing == null) {
      final id = tx.newId(db.trips, 'TR-');
      trip = Trip(
        id: id,
        tripCode: id,
        employerId: r.employerId,
        assignedDriverId: r.driverId,
        assignedVehicleId: r.vehicleId,
        routeId: routeId,
        serviceDate: dateOnly(r.serviceDate),
        scheduledStart: plan.departure,
        scheduledArrival: plan.arrival,
        originLocationId: plan.stops.first.locationId,
        destinationLocationId: plan.stops.last.locationId,
        employeeIds: r.employeeIds,
        orderedStopIds: plan.stops.map((s) => s.locationId).toList(),
        estimatedDurationMinutes: plan.durationMinutes,
        status: status,
        guardRequired: r.guardRequired,
        guardReference: r.guardReference?.trim().isEmpty ?? true
            ? null
            : r.guardReference!.trim(),
        instructions: r.instructions,
        optimizationRunId: r.optimizationRunId,
        assignmentHistory: history,
        createdAt: now,
        updatedAt: now,
      );
      tx.insert(db.trips, trip);
    } else {
      trip = existing.copyWith(
        assignedDriverId: () => r.driverId,
        assignedVehicleId: () => r.vehicleId,
        routeId: () => routeId,
        scheduledStart: plan.departure,
        scheduledArrival: () => plan.arrival,
        originLocationId: plan.stops.first.locationId,
        destinationLocationId: plan.stops.last.locationId,
        employeeIds: r.employeeIds,
        orderedStopIds: plan.stops.map((s) => s.locationId).toList(),
        estimatedDurationMinutes: () => plan.durationMinutes,
        status:
            existing.status == TripStatus.needsAttention &&
                existing.actualStart != null
            ? TripStatus.inProgress
            : status,
        guardRequired: r.guardRequired,
        guardReference: () => r.guardReference?.trim().isEmpty ?? true
            ? null
            : r.guardReference!.trim(),
        instructions: r.instructions.isEmpty
            ? existing.instructions
            : r.instructions,
        optimizationRunId: r.optimizationRunId == null
            ? null
            : () => r.optimizationRunId,
        assignmentHistory: history,
        inspectionId: () => existing.assignedVehicleId == r.vehicleId
            ? existing.inspectionId
            : null,
        updatedAt: now,
      );
      tx.put(db.trips, trip);
    }

    // Bookings fulfilled by this trip.
    final bookingIds = {
      ...r.bookingIds,
      ...db.bookings.where((b) => b.tripId == trip.id).map((b) => b.id),
    };
    for (final bid in bookingIds) {
      final b = db.bookings[bid];
      if (b == null) continue;
      if (!trip.employeeIds.contains(b.employeeId)) continue;
      tx.put(
        db.bookings,
        b.copyWith(
          tripId: () => trip.id,
          status: assigned ? BookingStatus.assigned : BookingStatus.approved,
          decisionReason: () => assigned
              ? 'Assigned to ${trip.tripCode}.'
              : 'Added to planned trip ${trip.tripCode}.',
          updatedAt: now,
        ),
      );
    }

    // Resource statuses.
    ResourceSync.vehicle(tx, db, trip.assignedVehicleId);
    ResourceSync.driver(tx, db, trip.assignedDriverId);
    if (existing != null) {
      if (existing.assignedVehicleId != trip.assignedVehicleId) {
        ResourceSync.vehicle(tx, db, existing.assignedVehicleId);
      }
      if (existing.assignedDriverId != trip.assignedDriverId) {
        ResourceSync.driver(tx, db, existing.assignedDriverId);
      }
    }

    // Notifications.
    final d = db.drivers[trip.assignedDriverId];
    final veh = db.vehicles[trip.assignedVehicleId];
    final firstPickup = plan.stops.first;
    if (assigned) {
      final verb = v.isReassignment ? 'updated' : 'assigned';
      for (final eid in trip.employeeIds) {
        final pickup = plan.stops.firstWhere(
          (s) => s.kind == StopKind.pickup && s.employeeIds.contains(eid),
          orElse: () => firstPickup,
        );
        ctx.notify(
          tx,
          role: UserRole.employee,
          recipientId: eid,
          title: 'Trip ${trip.tripCode} $verb',
          body:
              'Vehicle ${veh!.vehicleCode} (${veh.propulsion.label} ${veh.type.label}) with ${d!.name}. Pickup ${Fmt.time(pickup.plannedArrival)} on ${Fmt.dateShort(trip.serviceDate)}.',
          category: v.isReassignment
              ? NotificationCategory.routeChange
              : NotificationCategory.tripAssignment,
          entityType: 'trip',
          entityId: trip.id,
        );
      }
      ctx.notify(
        tx,
        role: UserRole.driver,
        recipientId: d!.id,
        title: v.isReassignment
            ? 'Trip ${trip.tripCode} reassigned to you'
            : 'New trip ${trip.tripCode}',
        body:
            '${trip.employeeIds.length} passenger${trip.employeeIds.length == 1 ? '' : 's'} · Vehicle ${veh!.vehicleCode} · start ${Fmt.time(trip.scheduledStart)} ${Fmt.dayLabel(trip.serviceDate, now)}.',
        category: NotificationCategory.tripAssignment,
        entityType: 'trip',
        entityId: trip.id,
      );
      if (v.isReassignment &&
          existing!.assignedDriverId != null &&
          existing.assignedDriverId != d.id) {
        ctx.notify(
          tx,
          role: UserRole.driver,
          recipientId: existing.assignedDriverId,
          title: 'Trip ${trip.tripCode} removed from your schedule',
          body: 'Reassigned by Fleet Manager: ${r.reassignReason}',
          category: NotificationCategory.routeChange,
          entityType: 'trip',
          entityId: trip.id,
        );
      }
      ctx.notify(
        tx,
        role: UserRole.employerAdmin,
        title: 'Trip ${trip.tripCode} $verb',
        body:
            '${trip.employeeIds.length} employees · ${d.driverCode} · Vehicle ${veh.vehicleCode}.',
        category: NotificationCategory.tripAssignment,
        entityType: 'trip',
        entityId: trip.id,
      );
    }
    ctx.audit(
      tx,
      actor,
      v.isReassignment
          ? 'reassign'
          : (existing == null ? 'trip.create' : 'assign'),
      'trip',
      trip.id,
      v.isReassignment
          ? 'Reassigned ${trip.tripCode} from ${existing!.assignedDriverId ?? '—'}/${existing.assignedVehicleId ?? '—'} to ${r.driverId}/${r.vehicleId}: ${r.reassignReason}'
          : '${existing == null ? 'Created' : 'Updated'} ${trip.tripCode} (${trip.employeeIds.join(', ')})${assigned ? ' with ${r.driverId} + Vehicle ${r.vehicleId}' : ' as planned'}.',
    );
    return trip;
  }

  Future<Result<Trip>> cancelTrip(
    String tripId,
    String reason, {
    Actor actor = Actor.fleetManager,
  }) {
    if (reason.trim().length < 5) {
      return Future.value(
        Err.single('Give a cancellation reason (at least 5 characters).'),
      );
    }
    return ctx.run((tx) {
      final db = ctx.db;
      final t = db.trips[tripId];
      if (t == null) throw ValidationFailure(['Trip not found.']);
      if (!TripStateMachine.canTransition(t.status, TripStatus.cancelled)) {
        throw ValidationFailure([
          '${t.tripCode} is ${t.status.label.toLowerCase()} and cannot be cancelled.',
        ]);
      }
      final next = t.copyWith(
        status: TripStatus.cancelled,
        cancellationReason: () => reason.trim(),
        billableStatus: BillableStatus.excluded,
        updatedAt: ctx.now,
      );
      tx.put(db.trips, next);
      final route = db.routes[t.routeId];
      if (route != null) {
        tx.put(db.routes, route.copyWith(status: RouteStatus.cancelled));
      }
      for (final b in db.bookings.where((b) => b.tripId == t.id).toList()) {
        tx.put(
          db.bookings,
          b.copyWith(
            status: BookingStatus.cancelled,
            decisionReason: () => 'Trip cancelled: ${reason.trim()}',
            updatedAt: ctx.now,
          ),
        );
      }
      ResourceSync.vehicle(tx, db, t.assignedVehicleId);
      ResourceSync.driver(tx, db, t.assignedDriverId);
      ctx.notifyEmployees(
        tx,
        t.employeeIds,
        'Trip ${t.tripCode} cancelled',
        reason.trim(),
        NotificationCategory.routeChange,
        entityType: 'trip',
        entityId: t.id,
      );
      if (t.assignedDriverId != null) {
        ctx.notify(
          tx,
          role: UserRole.driver,
          recipientId: t.assignedDriverId,
          title: 'Trip ${t.tripCode} cancelled',
          body: reason.trim(),
          category: NotificationCategory.routeChange,
          entityType: 'trip',
          entityId: t.id,
        );
      }
      ctx.notify(
        tx,
        role: UserRole.employerAdmin,
        title: 'Trip ${t.tripCode} cancelled',
        body: reason.trim(),
        category: NotificationCategory.routeChange,
        entityType: 'trip',
        entityId: t.id,
      );
      ctx.audit(
        tx,
        actor,
        'cancel',
        'trip',
        t.id,
        'Cancelled ${t.tripCode}: ${reason.trim()}',
      );
      return next;
    }, info: 'Trip cancelled');
  }

  /// Candidate vehicles for a trip window with the reason each is blocked.
  List<(Vehicle, List<String>)> vehicleOptions(AssignmentRequest base) => [
    for (final v in ctx.db.vehicles.values)
      (
        v,
        validate(base.copyWith(vehicleId: v.id)).errors
            .where(
              (e) =>
                  e.contains('Vehicle ${v.vehicleCode}') ||
                  e.startsWith('Over capacity'),
            )
            .toList(),
      ),
  ];

  List<(Driver, List<String>)> driverOptions(AssignmentRequest base) => [
    for (final d in ctx.db.drivers.values)
      (
        d,
        validate(
          base.copyWith(driverId: d.id),
        ).errors.where((e) => e.contains(d.driverCode)).toList(),
      ),
  ];

  static bool _sameSet(List<String> a, List<String> b) =>
      a.length == b.length && a.toSet().containsAll(b);
}
