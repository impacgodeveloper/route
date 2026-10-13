import '../../core/demo/clock.dart';
import '../../core/persistence/local_database.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/result.dart';
import '../models/models.dart';
import '../rules/inspection_rules.dart';
import '../rules/parameter_catalog.dart';
import '../rules/trip_state_machine.dart';
import 'billing_service.dart';
import 'safety_services.dart';
import 'resource_sync.dart';
import 'service_context.dart';
import 'verification_service.dart';

/// Counts used for passenger reconciliation.
class PassengerReconciliation {
  const PassengerReconciliation({
    required this.expected,
    required this.boarded,
    required this.alighted,
    required this.noShow,
    required this.awaiting,
    required this.stillOnboard,
  });

  final int expected;
  final int boarded;
  final int alighted;
  final int noShow;
  final List<String> awaiting;
  final List<String> stillOnboard;

  /// Everyone is accounted for: alighted or no-show.
  bool get reconciled =>
      awaiting.isEmpty && stillOnboard.isEmpty && alighted + noShow == expected;
}

class CompletionReport {
  const CompletionReport({
    required this.blockers,
    required this.reconciliation,
    required this.openStops,
  });
  final List<String> blockers;
  final PassengerReconciliation reconciliation;
  final List<RouteStop> openStops;
  bool get canComplete => blockers.isEmpty;
}

class ShiftSummary {
  const ShiftSummary({
    required this.shift,
    required this.trips,
    required this.completedTrips,
    required this.passengersCarried,
    required this.noShows,
    required this.openIncidents,
    required this.endBlockers,
    required this.distanceKm,
  });

  final Shift? shift;
  final List<Trip> trips;
  final int completedTrips;
  final int passengersCarried;
  final int noShows;
  final List<Incident> openIncidents;
  final List<String> endBlockers;
  final double distanceKm;
}

/// Driver workflow rules: attendance → inspection → trip → stops →
/// passengers → completion → shift end.
class DriverOpsService {
  DriverOpsService(
    this.ctx,
    this.billing, {
    this.verification = const VerificationService(),
  });
  final ServiceContext ctx;
  final BillingService billing;
  final VerificationService verification;

  LocalDatabase get db => ctx.db;

  int _param(String key) {
    final cfg = db.optimizationConfigs.values.firstOrNull;
    final def = ParameterCatalog.byKey(key)?.defaultValue ?? 0;
    return (cfg == null ? def : ParameterCatalog.value(cfg, key)).round();
  }

  // ---------------- Attendance ----------------

  Future<Result<Shift>> checkIn(String driverId) {
    final d = db.drivers[driverId];
    if (d == null) return Future.value(Err.single('Driver not found.'));
    final existing = ctx.view.todayShift(driverId);
    if (existing?.actualCheckIn != null) {
      return Future.value(
        Err.single(
          existing!.status == ShiftStatus.completed
              ? 'Today\'s shift is already completed.'
              : 'Already checked in at ${Fmt.time(existing.actualCheckIn)}.',
        ),
      );
    }
    return ctx.run((tx) {
      final now = ctx.now;
      final today = dateOnly(now);
      final base =
          existing ??
          Shift(
            id: tx.newId(db.shifts, 'SH-'),
            driverId: driverId,
            shiftDate: today,
            scheduledStart: atMinutes(today, d.shiftStartMinutes),
            scheduledEnd: atMinutes(today, d.shiftEndMinutes),
            status: ShiftStatus.scheduled,
          );
      final late =
          now.difference(base.scheduledStart).inMinutes >
          _param('late_checkin_threshold_min');
      final shift = base.copyWith(
        actualCheckIn: () => now,
        status: late ? ShiftStatus.late : ShiftStatus.checkedIn,
      );
      tx.put(db.shifts, shift);
      tx.put(
        db.drivers,
        d.copyWith(
          attendanceStatus: late
              ? AttendanceStatus.late
              : AttendanceStatus.checkedIn,
          status:
              (d.status == DriverStatus.offDuty ||
                  d.status == DriverStatus.unavailable)
              ? DriverStatus.available
              : d.status,
          safetyChecklistStatus: SafetyChecklistStatus.pending,
        ),
      );
      ResourceSync.driver(tx, db, driverId);
      if (late) {
        ctx.notify(
          tx,
          role: UserRole.fleetManager,
          title: '${d.driverCode} checked in late',
          body:
              'Checked in ${Fmt.time(now)} (scheduled ${Fmt.time(base.scheduledStart)}).',
          category: NotificationCategory.shift,
          entityType: 'shift',
          entityId: shift.id,
        );
      }
      ctx.audit(
        tx,
        Actor.driver(driverId),
        'shift.checkIn',
        'shift',
        shift.id,
        '${d.driverCode} checked in at ${Fmt.time(now)}${late ? ' (late)' : ''}.',
      );
      return shift;
    }, info: 'Checked in');
  }

  Future<Result<Shift>> requestRegularization(String shiftId, String reason) {
    if (reason.trim().length < 10) {
      return Future.value(
        Err.single('Explain the reason in at least 10 characters.'),
      );
    }
    return ctx.run((tx) {
      final s = db.shifts[shiftId];
      if (s == null) throw ValidationFailure(['Shift not found.']);
      if (s.regularizationStatus == RegularizationStatus.pending) {
        throw ValidationFailure([
          'A regularization request is already pending.',
        ]);
      }
      final next = s.copyWith(
        status: ShiftStatus.regularizationPending,
        regularizationStatus: () => RegularizationStatus.pending,
        regularizationReason: () => reason.trim(),
      );
      tx.put(db.shifts, next);
      ctx.notify(
        tx,
        role: UserRole.fleetManager,
        title: 'Regularization request',
        body: '${s.driverId}: ${reason.trim()}',
        category: NotificationCategory.shift,
        entityType: 'shift',
        entityId: s.id,
      );
      ctx.audit(
        tx,
        Actor.driver(s.driverId),
        'shift.regularize',
        'shift',
        s.id,
        'Requested attendance regularization.',
      );
      return next;
    }, info: 'Regularization requested');
  }

  Future<Result<Shift>> decideRegularization(
    String shiftId,
    bool approve, {
    Actor actor = Actor.fleetManager,
  }) => ctx.run((tx) {
    final s = db.shifts[shiftId];
    if (s == null || s.regularizationStatus != RegularizationStatus.pending) {
      throw ValidationFailure(['No pending request.']);
    }
    final next = s.copyWith(
      regularizationStatus: () => approve
          ? RegularizationStatus.approved
          : RegularizationStatus.rejected,
      status: s.actualCheckOut != null
          ? ShiftStatus.completed
          : (approve ? ShiftStatus.checkedIn : ShiftStatus.late),
    );
    tx.put(db.shifts, next);
    ctx.notify(
      tx,
      role: UserRole.driver,
      recipientId: s.driverId,
      title: 'Regularization ${approve ? 'approved' : 'rejected'}',
      body: 'Shift ${Fmt.date(s.shiftDate)}',
      category: NotificationCategory.shift,
      entityType: 'shift',
      entityId: s.id,
    );
    ctx.audit(
      tx,
      actor,
      'shift.regularization',
      'shift',
      s.id,
      'Regularization ${approve ? 'approved' : 'rejected'}.',
    );
    return next;
  });

  // ---------------- Inspection ----------------

  Future<Result<Inspection>> submitInspection({
    required String driverId,
    required String vehicleId,
    required List<InspectionItem> items,
    String notes = '',
    String? photoPath,
    String? tripId,
  }) {
    final missingNotes = items
        .where((i) => i.result == CheckResult.fail && i.note.trim().isEmpty)
        .toList();
    if (missingNotes.isNotEmpty) {
      return Future.value(
        Err([
          'Add a note for each failed item: ${missingNotes.map((i) => i.label).join(', ')}.',
        ]),
      );
    }
    final shift = ctx.view.todayShift(driverId);
    if (shift?.actualCheckIn == null) {
      return Future.value(
        Err.single('Check in to your shift before inspecting a vehicle.'),
      );
    }
    return ctx.run((tx) {
      final v = db.vehicles[vehicleId];
      final d = db.drivers[driverId];
      if (v == null || d == null) {
        throw ValidationFailure(['Vehicle or driver not found.']);
      }
      final outcome = InspectionRules.outcomeFor(items);
      final id = tx.newId(db.inspections, 'IN-');
      var insp = Inspection(
        id: id,
        vehicleId: v.id,
        driverId: d.id,
        tripId: tripId,
        date: dateOnly(ctx.now),
        items: items,
        notes: notes.trim(),
        photoPath: photoPath,
        overallStatus: outcome,
        submittedAt: ctx.now,
      );
      tx.put(db.vehicles, v.copyWith(lastInspectionAt: () => ctx.now));
      tx.put(
        db.drivers,
        d.copyWith(
          safetyChecklistStatus: switch (outcome) {
            InspectionOutcome.passed => SafetyChecklistStatus.passed,
            InspectionOutcome.failed => SafetyChecklistStatus.failed,
            InspectionOutcome.needsReview => SafetyChecklistStatus.needsReview,
          },
        ),
      );
      if (outcome == InspectionOutcome.failed) {
        final crit = insp.criticalFailures.map((i) => i.label).join(', ');
        final incId = tx.newId(db.incidents, 'IC-');
        tx.insert(
          db.incidents,
          Incident(
            id: incId,
            reference: incId,
            type: IncidentType.vehicleDefect,
            vehicleId: v.id,
            driverId: d.id,
            tripId: tripId,
            description:
                'Inspection failed — critical: $crit.${notes.trim().isNotEmpty ? ' ${notes.trim()}' : ''}',
            severity: IncidentSeverity.high,
            status: IncidentStatus.submittedDemo,
            reportedByRole: UserRole.driver,
            reportedById: d.id,
            createdAt: ctx.now,
            updatedAt: ctx.now,
          ),
        );
        insp = insp.copyWith(defectIncidentId: () => incId);
        tx.put(
          db.vehicles,
          db.vehicles[v.id]!.copyWith(
            status: VehicleStatus.maintenance,
            notes: 'Defect $incId: $crit',
          ),
        );
        // Block not-yet-started trips on this vehicle.
        for (final t
            in db.trips
                .where(
                  (t) =>
                      t.assignedVehicleId == v.id &&
                      t.actualStart == null &&
                      TripStateMachine.occupiesWindow(t.status),
                )
                .toList()) {
          tx.put(
            db.trips,
            t.copyWith(
              status: TripStatus.needsAttention,
              delayReason: () =>
                  'Vehicle ${v.vehicleCode} failed inspection ($crit).',
              updatedAt: ctx.now,
            ),
          );
          ctx.notifyEmployees(
            tx,
            t.employeeIds,
            'Trip ${t.tripCode} under review',
            'The assigned vehicle needs attention. The Fleet Manager will confirm a replacement.',
            NotificationCategory.routeChange,
            entityType: 'trip',
            entityId: t.id,
          );
        }
        ctx.notify(
          tx,
          role: UserRole.fleetManager,
          title: 'Defect: Vehicle ${v.vehicleCode} blocked',
          body:
              '${d.driverCode} failed inspection ($crit). Vehicle set to maintenance; affected trips need reassignment.',
          category: NotificationCategory.incident,
          entityType: 'incident',
          entityId: incId,
        );
      } else if (outcome == InspectionOutcome.needsReview) {
        ctx.notify(
          tx,
          role: UserRole.fleetManager,
          title: 'Inspection needs review: Vehicle ${v.vehicleCode}',
          body:
              'Non-critical: ${insp.failures.map((i) => i.label).join(', ')}.',
          category: NotificationCategory.incident,
          entityType: 'vehicle',
          entityId: v.id,
        );
      }
      tx.insert(db.inspections, insp);
      ctx.audit(
        tx,
        Actor.driver(d.id),
        'inspection.submit',
        'inspection',
        id,
        'Vehicle ${v.vehicleCode} inspection ${outcome.label.toLowerCase()}.',
      );
      return insp;
    }, info: 'Inspection submitted');
  }

  // ---------------- Trip lifecycle ----------------

  /// Every reason the driver cannot start [tripId] right now.
  List<String> startBlockers(String tripId, String driverId) {
    final t = db.trips[tripId];
    if (t == null) return ['Trip not found.'];
    final b = <String>[];
    if (t.status == TripStatus.cancelled) {
      return [
        '${t.tripCode} was cancelled${t.cancellationReason != null ? ': ${t.cancellationReason}' : ''}.',
      ];
    }
    if (t.status == TripStatus.completed) {
      return ['${t.tripCode} is already completed.'];
    }
    if (t.assignedDriverId != driverId) {
      return ['${t.tripCode} is not assigned to you.'];
    }
    if (!t.isAssigned) b.add('Trip has no vehicle assigned.');
    if (t.actualStart != null) b.add('Trip already started.');
    if (t.status == TripStatus.needsAttention) {
      b.add(
        'Trip needs Fleet Manager attention: ${t.delayReason ?? 'pending review'}.',
      );
    }
    if (!sameDay(t.serviceDate, ctx.now)) {
      b.add('Trip is scheduled for ${Fmt.date(t.serviceDate)}.');
    }
    final shift = ctx.view.todayShift(driverId);
    if (shift?.actualCheckIn == null) b.add('Check in to your shift first.');
    if (shift?.status == ShiftStatus.completed) b.add('Your shift has ended.');
    final v = db.vehicles[t.assignedVehicleId];
    if (v != null) {
      if (v.status == VehicleStatus.maintenance ||
          v.status == VehicleStatus.unavailable) {
        b.add('Vehicle ${v.vehicleCode} is ${v.status.label.toLowerCase()}.');
      }
      final insp = ctx.view.todayInspection(v.id);
      if (insp == null) {
        b.add('Complete today\'s inspection for Vehicle ${v.vehicleCode}.');
      } else if (!InspectionRules.allowsTripStart(insp)) {
        b.add('Vehicle ${v.vehicleCode} failed inspection (critical item).');
      }
      if (db.trips.any(
        (o) =>
            o.id != t.id &&
            o.assignedVehicleId == v.id &&
            o.status.isActive &&
            o.actualStart != null,
      )) {
        b.add('Vehicle ${v.vehicleCode} is on another active trip.');
      }
    }
    if (db.trips.any(
      (o) =>
          o.id != t.id &&
          o.assignedDriverId == driverId &&
          o.status.isActive &&
          o.actualStart != null,
    )) {
      b.add('Finish your active trip first.');
    }
    b.addAll(AlcoholService(ctx).blockers(driverId, trip: t));
    return b;
  }

  Future<Result<Trip>> acceptTrip(String tripId, String driverId) => ctx.run((
    tx,
  ) {
    final t = db.trips[tripId];
    if (t == null || t.assignedDriverId != driverId) {
      throw ValidationFailure(['Trip not assigned to you.']);
    }
    if (!TripStateMachine.canTransition(t.status, TripStatus.driverAccepted)) {
      throw ValidationFailure([
        'Cannot accept a ${t.status.label.toLowerCase()} trip.',
      ]);
    }
    final next = t.copyWith(
      status: TripStatus.driverAccepted,
      updatedAt: ctx.now,
    );
    tx.put(db.trips, next);
    ctx.audit(
      tx,
      Actor.driver(driverId),
      'trip.accept',
      'trip',
      t.id,
      '${t.tripCode} accepted by $driverId.',
    );
    return next;
  }, info: 'Trip accepted');

  Future<Result<Trip>> startTrip(String tripId, String driverId) {
    final blockers = startBlockers(tripId, driverId);
    if (blockers.isNotEmpty) return Future.value(Err(blockers));
    return ctx.run((tx) {
      final t = db.trips[tripId]!;
      if (!TripStateMachine.canTransition(t.status, TripStatus.inProgress)) {
        throw ValidationFailure([
          'Cannot start a ${t.status.label.toLowerCase()} trip.',
        ]);
      }
      final v = db.vehicles[t.assignedVehicleId]!;
      final insp = ctx.view.todayInspection(v.id);
      final next = t.copyWith(
        status: TripStatus.inProgress,
        actualStart: () => ctx.now,
        startOdometerKm: () => v.odometerKm,
        inspectionId: () => insp?.id,
        updatedAt: ctx.now,
      );
      tx.put(db.trips, next);
      final route = db.routes[t.routeId];
      if (route != null) {
        tx.put(db.routes, route.copyWith(status: RouteStatus.active));
      }
      ResourceSync.vehicle(tx, db, v.id);
      ResourceSync.driver(tx, db, driverId);
      ctx.notifyEmployees(
        tx,
        t.employeeIds,
        'Your cab is on the way',
        'Trip ${t.tripCode} started · Vehicle ${v.vehicleCode} (${v.fictionalRegistration}).',
        NotificationCategory.pickupReminder,
        entityType: 'trip',
        entityId: t.id,
      );
      ctx.audit(
        tx,
        Actor.driver(driverId),
        'trip.start',
        'trip',
        t.id,
        '${t.tripCode} started at ${Fmt.time(ctx.now)}.',
      );
      return next;
    }, info: 'Trip started');
  }

  RouteStop _stop(String stopId) {
    final s = db.routeStops[stopId];
    if (s == null) throw ValidationFailure(['Stop not found.']);
    return s;
  }

  Trip _tripOfStop(RouteStop s) {
    final t = db.trips.where((t) => t.routeId == s.routeId).firstOrNull;
    if (t == null) throw ValidationFailure(['Trip not found for stop.']);
    if (!t.status.isActive || t.actualStart == null) {
      throw ValidationFailure(['${t.tripCode} is not in progress.']);
    }
    return t;
  }

  Future<Result<RouteStop>> arriveAtStop(String stopId) => ctx.run((tx) {
    final s = _stop(stopId);
    final t = _tripOfStop(s);
    final current = ctx.view.trips.currentStop(t);
    if (current?.id != s.id) {
      throw ValidationFailure(['Complete or skip the current stop first.']);
    }
    if (s.status != StopStatus.upcoming) {
      throw ValidationFailure([
        'Stop already ${s.status.label.toLowerCase()}.',
      ]);
    }
    final next = s.copyWith(
      status: StopStatus.arrived,
      actualArrival: () => ctx.now,
    );
    tx.put(db.routeStops, next);
    if (s.kind == StopKind.pickup) {
      ctx.notifyEmployees(
        tx,
        s.boardingEmployeeIds,
        'Your cab has arrived',
        'Trip ${t.tripCode} is at ${db.locations[s.locationId]?.name}. Show your demo pass or T-PIN.',
        NotificationCategory.pickupReminder,
        entityType: 'trip',
        entityId: t.id,
      );
    }
    ctx.audit(
      tx,
      Actor.driver(t.assignedDriverId ?? ''),
      'stop.arrive',
      'trip',
      t.id,
      'Arrived at stop ${s.sequence} (${s.locationId}).',
    );
    return next;
  }, info: 'Arrival recorded');

  void _board(
    Txn tx,
    Trip t,
    RouteStop s,
    String employeeId,
    VerificationMethod method,
    VerificationStatus vs, {
    String note = '',
    String? authorizedBy,
  }) {
    tx.insert(
      db.passengerEvents,
      PassengerEvent(
        id: tx.newId(db.passengerEvents, 'PE-'),
        tripId: t.id,
        employeeId: employeeId,
        stopId: s.id,
        eventType: method == VerificationMethod.manualAuthorized
            ? PassengerEventType.manualOverride
            : PassengerEventType.boarded,
        verificationMethod: method,
        verificationStatus: vs,
        eventTime: ctx.now,
        note: note,
        authorizedBy: authorizedBy,
      ),
    );
    tx.put(
      db.trips,
      t.copyWith(
        boardedPassengerIds: [...t.boardedPassengerIds, employeeId],
        noShowPassengerIds: t.noShowPassengerIds
            .where((x) => x != employeeId)
            .toList(),
        updatedAt: ctx.now,
      ),
    );
  }

  void _requireArrived(RouteStop s) {
    if (s.status != StopStatus.arrived) {
      throw ValidationFailure(['Mark arrival at this stop first.']);
    }
  }

  /// Verifies a demo QR payload or T-PIN and boards the passenger on success.
  /// Failed checks never mark anyone verified.
  Future<Result<VerificationOutcome>> verifyAndBoard({
    required String stopId,
    required VerificationMethod method,
    required String input,
    String? employeeId,
  }) async {
    final s = db.routeStops[stopId];
    if (s == null) return Err.single('Stop not found.');
    final t = db.trips.where((t) => t.routeId == s.routeId).firstOrNull;
    if (t == null) return Err.single('Trip not found.');
    final emps = t.employeeIds
        .map((id) => db.employees[id])
        .whereType<Employee>()
        .toList();
    VerificationOutcome outcome;
    if (method == VerificationMethod.qrDemo) {
      outcome = verification.verifyQr(
        payload: input,
        trip: t,
        tripEmployees: emps,
        now: ctx.now,
      );
    } else {
      final e = db.employees[employeeId];
      if (e == null) return Err.single('Select the passenger first.');
      outcome = verification.verifyTpin(
        pin: input,
        trip: t,
        employee: e,
        now: ctx.now,
      );
    }
    if (!outcome.ok) return Ok(outcome, info: outcome.message);
    if (!s.boardingEmployeeIds.contains(outcome.employeeId)) {
      final who = db.employees[outcome.employeeId]!;
      return Ok(
        VerificationOutcome(
          VerificationStatus.invalid,
          '${who.employeeCode} boards at a different stop.',
          employeeId: who.id,
        ),
        info: '${who.employeeCode} boards at a different stop.',
      );
    }
    final r = await ctx.run((tx) {
      final st = _stop(stopId);
      final trip = _tripOfStop(st);
      _requireArrived(st);
      _board(
        tx,
        trip,
        st,
        outcome.employeeId!,
        method,
        VerificationStatus.verified,
      );
      ctx.audit(
        tx,
        Actor.driver(trip.assignedDriverId ?? ''),
        'passenger.board',
        'trip',
        trip.id,
        '${db.employees[outcome.employeeId]?.employeeCode} boarded via ${method.label}.',
      );
      return outcome;
    }, info: outcome.message);
    return r;
  }

  Future<Result<void>> manualBoard({
    required String stopId,
    required String employeeId,
    required String reason,
    required String authorizedBy,
  }) {
    if (reason.trim().length < 5) {
      return Future.value(
        Err.single('Give an override reason (at least 5 characters).'),
      );
    }
    if (authorizedBy.trim().isEmpty) {
      return Future.value(Err.single('Name who authorized the override.'));
    }
    return ctx.run((tx) {
      final s = _stop(stopId);
      final t = _tripOfStop(s);
      _requireArrived(s);
      if (!t.employeeIds.contains(employeeId)) {
        throw ValidationFailure(['Passenger is not on this trip.']);
      }
      if (t.boardedPassengerIds.contains(employeeId) ||
          t.alightedPassengerIds.contains(employeeId)) {
        throw ValidationFailure([
          'Already boarded — use "Correct status" to change it.',
        ]);
      }
      _board(
        tx,
        t,
        s,
        employeeId,
        VerificationMethod.manualAuthorized,
        VerificationStatus.overridden,
        note: reason.trim(),
        authorizedBy: authorizedBy.trim(),
      );
      ctx.audit(
        tx,
        Actor.driver(t.assignedDriverId ?? ''),
        'passenger.override',
        'trip',
        t.id,
        '${db.employees[employeeId]?.employeeCode} boarded by manual override (${authorizedBy.trim()}): ${reason.trim()}',
      );
    }, info: 'Boarded by authorized override');
  }

  Future<Result<void>> markNoShow({
    required String stopId,
    required String employeeId,
    required String reason,
  }) {
    if (reason.trim().length < 3) {
      return Future.value(Err.single('Add a short reason.'));
    }
    return ctx.run((tx) {
      final s = _stop(stopId);
      final t = _tripOfStop(s);
      _requireArrived(s);
      if (!s.boardingEmployeeIds.contains(employeeId)) {
        throw ValidationFailure(['Passenger does not board at this stop.']);
      }
      if (t.boardedPassengerIds.contains(employeeId)) {
        throw ValidationFailure([
          'Passenger is boarded — correct the status first.',
        ]);
      }
      if (t.noShowPassengerIds.contains(employeeId)) {
        throw ValidationFailure(['Already marked no-show.']);
      }
      tx.insert(
        db.passengerEvents,
        PassengerEvent(
          id: tx.newId(db.passengerEvents, 'PE-'),
          tripId: t.id,
          employeeId: employeeId,
          stopId: s.id,
          eventType: PassengerEventType.noShow,
          verificationMethod: VerificationMethod.manualAuthorized,
          verificationStatus: VerificationStatus.overridden,
          eventTime: ctx.now,
          note: reason.trim(),
        ),
      );
      tx.put(
        db.trips,
        t.copyWith(
          noShowPassengerIds: [...t.noShowPassengerIds, employeeId],
          updatedAt: ctx.now,
        ),
      );
      ctx.notify(
        tx,
        role: UserRole.employee,
        recipientId: employeeId,
        title: 'Marked as no-show on ${t.tripCode}',
        body:
            'Driver note: ${reason.trim()}. Contact support if this is wrong.',
        category: NotificationCategory.delay,
        entityType: 'trip',
        entityId: t.id,
      );
      ctx.notify(
        tx,
        role: UserRole.fleetManager,
        title: 'No-show on ${t.tripCode}',
        body: '$employeeId · ${reason.trim()}',
        category: NotificationCategory.incident,
        entityType: 'trip',
        entityId: t.id,
      );
      ctx.audit(
        tx,
        Actor.driver(t.assignedDriverId ?? ''),
        'passenger.noShow',
        'trip',
        t.id,
        '$employeeId marked no-show: ${reason.trim()}',
      );
    }, info: 'Marked no-show');
  }

  /// Explicit correction of a passenger state (duplicate/mistake fix).
  Future<Result<void>> correctPassenger({
    required String tripId,
    required String employeeId,
    required String reason,
  }) {
    if (reason.trim().length < 5) {
      return Future.value(
        Err.single('Give a correction reason (at least 5 characters).'),
      );
    }
    return ctx.run((tx) {
      final t = db.trips[tripId];
      if (t == null || !t.status.isActive) {
        throw ValidationFailure(['Trip is not in progress.']);
      }
      tx.insert(
        db.passengerEvents,
        PassengerEvent(
          id: tx.newId(db.passengerEvents, 'PE-'),
          tripId: t.id,
          employeeId: employeeId,
          eventType: PassengerEventType.manualOverride,
          verificationMethod: VerificationMethod.manualAuthorized,
          verificationStatus: VerificationStatus.overridden,
          eventTime: ctx.now,
          note: 'Correction: ${reason.trim()}',
        ),
      );
      tx.put(
        db.trips,
        t.copyWith(
          boardedPassengerIds: t.boardedPassengerIds
              .where((x) => x != employeeId)
              .toList(),
          alightedPassengerIds: t.alightedPassengerIds
              .where((x) => x != employeeId)
              .toList(),
          noShowPassengerIds: t.noShowPassengerIds
              .where((x) => x != employeeId)
              .toList(),
          updatedAt: ctx.now,
        ),
      );
      ctx.audit(
        tx,
        Actor.driver(t.assignedDriverId ?? ''),
        'passenger.correct',
        'trip',
        t.id,
        '$employeeId status reset: ${reason.trim()}',
      );
    }, info: 'Passenger status reset');
  }

  Future<Result<void>> alight({
    required String stopId,
    required List<String> employeeIds,
  }) => ctx.run((tx) {
    final s = _stop(stopId);
    var t = _tripOfStop(s);
    _requireArrived(s);
    for (final id in employeeIds) {
      if (!t.boardedPassengerIds.contains(id)) {
        throw ValidationFailure(['$id is not on board.']);
      }
      if (t.alightedPassengerIds.contains(id)) continue;
      tx.insert(
        db.passengerEvents,
        PassengerEvent(
          id: tx.newId(db.passengerEvents, 'PE-'),
          tripId: t.id,
          employeeId: id,
          stopId: s.id,
          eventType: PassengerEventType.alighted,
          verificationMethod: VerificationMethod.manualAuthorized,
          verificationStatus: VerificationStatus.verified,
          eventTime: ctx.now,
        ),
      );
      t = t.copyWith(
        alightedPassengerIds: [...t.alightedPassengerIds, id],
        updatedAt: ctx.now,
      );
    }
    tx.put(db.trips, t);
    ctx.audit(
      tx,
      Actor.driver(t.assignedDriverId ?? ''),
      'passenger.alight',
      'trip',
      t.id,
      '${employeeIds.join(', ')} alighted at stop ${s.sequence}.',
    );
  }, info: 'Drop-off recorded');

  /// Discrepancies at a stop: expected vs actual (empty = consistent).
  List<String> stopDiscrepancies(RouteStop s) {
    final t = db.trips.where((t) => t.routeId == s.routeId).firstOrNull;
    if (t == null) return const [];
    final out = <String>[];
    if (s.kind == StopKind.pickup) {
      final unresolved = s.boardingEmployeeIds
          .where(
            (id) =>
                !t.boardedPassengerIds.contains(id) &&
                !t.noShowPassengerIds.contains(id),
          )
          .toList();
      if (unresolved.isNotEmpty) {
        final boardedHere = s.boardingEmployeeIds
            .where(t.boardedPassengerIds.contains)
            .length;
        out.add(
          'Expected ${s.expectedBoardingCount} boarding, $boardedHere boarded; not accounted for: ${unresolved.join(', ')}.',
        );
      }
    } else {
      final pending = s.alightingEmployeeIds
          .where(
            (id) =>
                t.boardedPassengerIds.contains(id) &&
                !t.alightedPassengerIds.contains(id),
          )
          .toList();
      if (pending.isNotEmpty) {
        out.add('Still on board for this drop: ${pending.join(', ')}.');
      }
    }
    return out;
  }

  Future<Result<RouteStop>> departStop(
    String stopId, {
    String? discrepancyReason,
  }) {
    final s0 = db.routeStops[stopId];
    if (s0 == null) return Future.value(Err.single('Stop not found.'));
    final issues = stopDiscrepancies(s0);
    if (issues.isNotEmpty && (discrepancyReason?.trim().length ?? 0) < 5) {
      return Future.value(
        Err(['Passenger mismatch — resolve or record a reason:', ...issues]),
      );
    }
    return ctx.run((tx) {
      final s = _stop(stopId);
      final t = _tripOfStop(s);
      _requireArrived(s);
      final next = s.copyWith(
        status: StopStatus.completed,
        departedAt: () => ctx.now,
        issueNote: issues.isEmpty
            ? null
            : () => '${issues.join(' ')} Reason: ${discrepancyReason!.trim()}',
      );
      tx.put(db.routeStops, next);
      if (issues.isNotEmpty) {
        ctx.notify(
          tx,
          role: UserRole.fleetManager,
          title: 'Passenger discrepancy on ${t.tripCode}',
          body: '${issues.join(' ')} Driver: ${discrepancyReason!.trim()}',
          category: NotificationCategory.incident,
          entityType: 'trip',
          entityId: t.id,
        );
      }
      ctx.audit(
        tx,
        Actor.driver(t.assignedDriverId ?? ''),
        'stop.complete',
        'trip',
        t.id,
        'Stop ${s.sequence} completed${issues.isEmpty ? '' : ' with discrepancy: ${discrepancyReason!.trim()}'}.',
      );
      return next;
    }, info: 'Stop completed');
  }

  Future<Result<RouteStop>> skipStop(
    String stopId, {
    required String reason,
    required String authorizedBy,
  }) {
    if (reason.trim().length < 5) {
      return Future.value(
        Err.single('Give a skip reason (at least 5 characters).'),
      );
    }
    if (authorizedBy.trim().isEmpty) {
      return Future.value(
        Err.single(
          'Skipping a stop needs authorization — name who approved it.',
        ),
      );
    }
    return ctx.run((tx) {
      final s = _stop(stopId);
      var t = _tripOfStop(s);
      if (s.isDone) {
        throw ValidationFailure([
          'Stop already ${s.status.label.toLowerCase()}.',
        ]);
      }
      if (s.kind == StopKind.drop &&
          s.alightingEmployeeIds.any(
            (id) =>
                t.boardedPassengerIds.contains(id) &&
                !t.alightedPassengerIds.contains(id),
          )) {
        throw ValidationFailure([
          'Passengers on board are due to alight here — this drop cannot be skipped.',
        ]);
      }
      final next = s.copyWith(
        status: StopStatus.skipped,
        skipReason: () => reason.trim(),
        skipAuthorizedBy: () => authorizedBy.trim(),
        actualArrival: () => s.actualArrival,
      );
      tx.put(db.routeStops, next);
      if (s.kind == StopKind.pickup) {
        final missed = s.boardingEmployeeIds
            .where(
              (id) =>
                  !t.boardedPassengerIds.contains(id) &&
                  !t.noShowPassengerIds.contains(id),
            )
            .toList();
        t = t.copyWith(
          noShowPassengerIds: [...t.noShowPassengerIds, ...missed],
          updatedAt: ctx.now,
        );
        tx.put(db.trips, t);
        ctx.notifyEmployees(
          tx,
          missed,
          'Pickup skipped on ${t.tripCode}',
          'Reason: ${reason.trim()}. Contact support for alternatives.',
          NotificationCategory.routeChange,
          entityType: 'trip',
          entityId: t.id,
        );
      }
      ctx.notify(
        tx,
        role: UserRole.fleetManager,
        title: 'Stop skipped on ${t.tripCode}',
        body:
            '${s.locationId}: ${reason.trim()} (authorized by ${authorizedBy.trim()})',
        category: NotificationCategory.routeChange,
        entityType: 'trip',
        entityId: t.id,
      );
      ctx.audit(
        tx,
        Actor.driver(t.assignedDriverId ?? ''),
        'stop.skip',
        'trip',
        t.id,
        'Skipped stop ${s.sequence}: ${reason.trim()} (by ${authorizedBy.trim()}).',
      );
      return next;
    }, info: 'Stop skipped');
  }

  PassengerReconciliation reconcile(Trip t) {
    final awaiting = t.employeeIds
        .where(
          (id) =>
              !t.boardedPassengerIds.contains(id) &&
              !t.noShowPassengerIds.contains(id) &&
              !t.alightedPassengerIds.contains(id),
        )
        .toList();
    final onboard = t.boardedPassengerIds
        .where((id) => !t.alightedPassengerIds.contains(id))
        .toList();
    return PassengerReconciliation(
      expected: t.employeeIds.length,
      boarded: t.boardedPassengerIds.length,
      alighted: t.alightedPassengerIds.length,
      noShow: t.noShowPassengerIds.length,
      awaiting: awaiting,
      stillOnboard: onboard,
    );
  }

  CompletionReport completionReport(String tripId) {
    final t = db.trips[tripId];
    if (t == null) {
      return const CompletionReport(
        blockers: ['Trip not found.'],
        reconciliation: PassengerReconciliation(
          expected: 0,
          boarded: 0,
          alighted: 0,
          noShow: 0,
          awaiting: [],
          stillOnboard: [],
        ),
        openStops: [],
      );
    }
    final stops = ctx.view.trips.stopsOf(t);
    final open = stops.where((s) => !s.isDone).toList();
    final rec = reconcile(t);
    final blockers = <String>[
      if (!t.status.isActive || t.actualStart == null)
        '${t.tripCode} is not in progress.',
      if (open.isNotEmpty)
        '${open.length} stop${open.length == 1 ? '' : 's'} not completed or skipped.',
      if (rec.awaiting.isNotEmpty)
        'Not accounted for: ${rec.awaiting.join(', ')} (board or mark no-show).',
      if (rec.stillOnboard.isNotEmpty)
        'Still on board: ${rec.stillOnboard.join(', ')} (record drop-off).',
      if (rec.boarded != rec.alighted)
        'Boarded ${rec.boarded} ≠ alighted ${rec.alighted}.',
    ];
    return CompletionReport(
      blockers: blockers,
      reconciliation: rec,
      openStops: open,
    );
  }

  Future<Result<Trip>> completeTrip({
    required String tripId,
    required String driverId,
    double? endOdometerKm,
    String notes = '',
    String? exceptionReason,
    String? exceptionAuthorizedBy,
  }) {
    final t0 = db.trips[tripId];
    if (t0 == null) return Future.value(Err.single('Trip not found.'));
    if (t0.assignedDriverId != driverId) {
      return Future.value(Err.single('Trip not assigned to you.'));
    }
    final report = completionReport(tripId);
    final hardBlock = report.blockers
        .where((b) => b.contains('not in progress'))
        .toList();
    if (hardBlock.isNotEmpty) return Future.value(Err(hardBlock));
    final hasException =
        (exceptionReason?.trim().length ?? 0) >= 10 &&
        (exceptionAuthorizedBy?.trim().isNotEmpty ?? false);
    if (!report.canComplete && !hasException) {
      return Future.value(
        Err([
          'Completion requirements not met:',
          ...report.blockers,
          'Resolve them, or record an authorized exception (reason ≥ 10 characters + approver).',
        ]),
      );
    }
    if (endOdometerKm != null &&
        t0.startOdometerKm != null &&
        endOdometerKm < t0.startOdometerKm!) {
      return Future.value(
        Err.single(
          'End odometer ${endOdometerKm.toStringAsFixed(1)} is below the start reading ${t0.startOdometerKm!.toStringAsFixed(1)}.',
        ),
      );
    }
    if (endOdometerKm != null &&
        t0.startOdometerKm != null &&
        endOdometerKm - t0.startOdometerKm! > 400) {
      return Future.value(
        Err.single(
          'Distance over 400 km looks wrong — check the odometer reading.',
        ),
      );
    }
    return ctx.run((tx) {
      final now = ctx.now;
      var t = db.trips[tripId]!;
      if (!TripStateMachine.canTransition(t.status, TripStatus.completed)) {
        throw ValidationFailure([
          'Cannot complete a ${t.status.label.toLowerCase()} trip.',
        ]);
      }
      // Close any open stops under the authorized exception.
      for (final s in report.openStops) {
        tx.put(
          db.routeStops,
          s.copyWith(
            status: StopStatus.skipped,
            skipReason: () =>
                'Closed at completion: ${exceptionReason!.trim()}',
            skipAuthorizedBy: () => exceptionAuthorizedBy!.trim(),
          ),
        );
      }
      final distance = (endOdometerKm != null && t.startOdometerKm != null)
          ? double.parse(
              (endOdometerKm - t.startOdometerKm!).toStringAsFixed(1),
            )
          : null;
      t = t.copyWith(
        status: TripStatus.completed,
        actualArrival: () => now,
        actualDurationMinutes: () => now.difference(t.actualStart!).inMinutes,
        endOdometerKm: () => endOdometerKm,
        distanceKm: () => distance,
        completionNotes: () => notes.trim().isEmpty ? null : notes.trim(),
        completionException: hasException
            ? () =>
                  '${exceptionReason!.trim()} (authorized by ${exceptionAuthorizedBy!.trim()})'
            : null,
        updatedAt: now,
      );
      tx.put(db.trips, t);
      final route = db.routes[t.routeId];
      if (route != null) {
        tx.put(db.routes, route.copyWith(status: RouteStatus.completed));
      }
      final v = db.vehicles[t.assignedVehicleId];
      if (v != null && endOdometerKm != null) {
        tx.put(db.vehicles, v.copyWith(odometerKm: endOdometerKm));
      }
      final d = db.drivers[driverId]!;
      tx.put(
        db.drivers,
        d.copyWith(completedTripCount: d.completedTripCount + 1),
      );
      for (final b
          in db.bookings
              .where(
                (b) => b.tripId == t.id && b.status == BookingStatus.assigned,
              )
              .toList()) {
        tx.put(
          db.bookings,
          b.copyWith(status: BookingStatus.completed, updatedAt: now),
        );
      }
      ResourceSync.vehicle(tx, db, t.assignedVehicleId);
      ResourceSync.driver(tx, db, driverId);
      ctx.notifyEmployees(
        tx,
        t.alightedPassengerIds,
        'Trip ${t.tripCode} completed',
        'Thanks for riding${distance != null ? ' · ${distance.toStringAsFixed(1)} km' : ''}.',
        NotificationCategory.tripAssignment,
        entityType: 'trip',
        entityId: t.id,
      );
      ctx.notify(
        tx,
        role: UserRole.fleetManager,
        title: 'Trip ${t.tripCode} completed',
        body:
            '${t.alightedPassengerIds.length}/${t.employeeIds.length} passengers dropped${hasException ? ' · exception recorded' : ''}.',
        category: NotificationCategory.tripAssignment,
        entityType: 'trip',
        entityId: t.id,
      );
      ctx.audit(
        tx,
        Actor.driver(driverId),
        'trip.complete',
        'trip',
        t.id,
        '${t.tripCode} completed${distance != null ? ', ${distance.toStringAsFixed(1)} km' : ', distance missing'}${hasException ? ' with exception: ${exceptionReason!.trim()}' : ''}.',
      );
      billing.generateInTx(tx, t.id);
      return db.trips[t.id]!;
    }, info: 'Trip completed');
  }

  // ---------------- Shift end ----------------

  ShiftSummary shiftSummary(String driverId) {
    final shift = ctx.view.todayShift(driverId);
    final trips = ctx.view.trips
        .forDriver(driverId)
        .where((t) => sameDay(t.serviceDate, ctx.now))
        .toList();
    final completed = trips
        .where((t) => t.status == TripStatus.completed)
        .toList();
    final blockers = <String>[
      if (shift?.actualCheckIn == null) 'You have not checked in today.',
      if (shift?.status == ShiftStatus.completed) 'Shift already ended.',
      ...trips
          .where((t) => t.status.isActive && t.actualStart != null)
          .map((t) => '${t.tripCode} is still in progress.'),
      ...trips
          .where(
            (t) =>
                t.actualStart == null &&
                TripStateMachine.occupiesWindow(t.status),
          )
          .map((t) => '${t.tripCode} is assigned but not started.'),
    ];
    return ShiftSummary(
      shift: shift,
      trips: trips,
      completedTrips: completed.length,
      passengersCarried: completed.fold(
        0,
        (s, t) => s + t.alightedPassengerIds.length,
      ),
      noShows: trips.fold(0, (s, t) => s + t.noShowPassengerIds.length),
      openIncidents: ctx.view
          .incidentsByDriver(driverId)
          .where((i) => i.status.isOpen)
          .toList(),
      endBlockers: blockers,
      distanceKm: completed.fold(0.0, (s, t) => s + (t.distanceKm ?? 0)),
    );
  }

  Future<Result<Shift>> endShift({
    required String driverId,
    required String? handoverParkingId,
    String handoverNotes = '',
    double? endOdometerKm,
    String? exceptionReason,
    String? exceptionAuthorizedBy,
  }) {
    final summary = shiftSummary(driverId);
    final hard = summary.endBlockers
        .where(
          (b) =>
              b.contains('in progress') ||
              b.contains('not checked in') ||
              b.contains('already ended'),
        )
        .toList();
    if (hard.isNotEmpty) return Future.value(Err(hard));
    final soft = summary.endBlockers.where((b) => !hard.contains(b)).toList();
    final hasException =
        (exceptionReason?.trim().length ?? 0) >= 10 &&
        (exceptionAuthorizedBy?.trim().isNotEmpty ?? false);
    final errors = <String>[
      if (handoverParkingId == null)
        'Select where the vehicle is parked for handover.',
      if (soft.isNotEmpty && !hasException) ...[
        ...soft,
        'Hand these back to the Fleet Manager, or record an authorized exception.',
      ],
    ];
    if (errors.isNotEmpty) return Future.value(Err(errors));
    return ctx.run((tx) {
      final s = summary.shift!;
      final d = db.drivers[driverId]!;
      final next = s.copyWith(
        actualCheckOut: () => ctx.now,
        status: ShiftStatus.completed,
        handoverParkingId: () => handoverParkingId,
        handoverNotes: () => handoverNotes.trim(),
        endOdometerKm: () => endOdometerKm,
        endException: hasException
            ? () =>
                  '${exceptionReason!.trim()} (authorized by ${exceptionAuthorizedBy!.trim()})'
            : null,
      );
      tx.put(db.shifts, next);
      tx.put(
        db.drivers,
        d.copyWith(
          attendanceStatus: AttendanceStatus.checkedOut,
          status: DriverStatus.offDuty,
        ),
      );
      final v = db.vehicles[d.assignedVehicleId];
      if (v != null) {
        tx.put(
          db.vehicles,
          v.copyWith(
            homeParkingId: () => handoverParkingId,
            odometerKm: (endOdometerKm != null && endOdometerKm >= v.odometerKm)
                ? endOdometerKm
                : v.odometerKm,
          ),
        );
      }
      ctx.notify(
        tx,
        role: UserRole.fleetManager,
        title: '${d.driverCode} ended shift',
        body:
            '${summary.completedTrips} trips · ${summary.passengersCarried} passengers · vehicle at $handoverParkingId${hasException ? ' · exception recorded' : ''}.',
        category: NotificationCategory.shift,
        entityType: 'shift',
        entityId: s.id,
      );
      ctx.audit(
        tx,
        Actor.driver(driverId),
        'shift.end',
        'shift',
        s.id,
        '${d.driverCode} ended shift at ${Fmt.time(ctx.now)}${hasException ? ' with exception: ${exceptionReason!.trim()}' : ''}.',
      );
      return next;
    }, info: 'Shift ended');
  }
}
