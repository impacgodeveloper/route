import 'dart:math' as math;

import '../../core/demo/clock.dart';
import '../../core/utils/result.dart';
import '../models/models.dart';
import '../rules/capacity_rules.dart';
import '../rules/geo_rules.dart';
import '../rules/parameter_catalog.dart';
import '../rules/trip_state_machine.dart';
import 'assignment_service.dart';
import 'optimization_engine.dart';
import 'service_context.dart';

/// Pairwise pooling feasibility with human-readable reasons.
class PoolingCheck {
  const PoolingCheck(this.a, this.b, this.feasible, this.reasons);
  final Employee a;
  final Employee b;
  final bool feasible;
  final List<String> reasons;
}

class PoolGroup {
  const PoolGroup(this.employees, this.reasons, this.suggestedVehicle);
  final List<Employee> employees;
  final List<String> reasons;
  final Vehicle? suggestedVehicle;
}

class PoolingResult {
  const PoolingResult(this.groups, this.unpooled, this.notes);
  final List<PoolGroup> groups;

  /// Employees that could not be pooled, with why.
  final Map<Employee, List<String>> unpooled;
  final List<String> notes;
}

/// EV target vs actual with feasibility explanation.
class EvTargetAnalysis {
  const EvTargetAnalysis({
    required this.targetPct,
    required this.actualPct,
    required this.fleetEvPct,
    required this.maxAchievablePct,
    required this.evTrips,
    required this.totalTrips,
    required this.feasible,
    required this.explanation,
  });

  final int targetPct;
  final double actualPct;
  final double fleetEvPct;
  final double maxAchievablePct;
  final int evTrips;
  final int totalTrips;
  final bool feasible;
  final List<String> explanation;
}

/// Wraps the deterministic engine with persistence, pooling and EV logic.
/// Labelled everywhere as the "local demo optimizer".
class OptimizationService {
  OptimizationService(
    this.ctx,
    this.assignments, {
    this.engine = const OptimizationEngine(),
  });
  final ServiceContext ctx;
  final AssignmentService assignments;
  final OptimizationEngine engine;

  OptimizationInput buildInput({
    required OptimizationConfig config,
    required List<String> employeeIds,
    required DateTime serviceDate,
    List<String>? vehicleIds,
    bool guardRequired = false,
    RouteVariant? variant,
    String? startParkingId,
    int guardsAvailable = 0,
  }) {
    final v = ctx.view;
    final employer = v.employer(config.employerId) ?? v.primaryEmployer;
    return OptimizationInput(
      config: config,
      employer: employer,
      employees: employeeIds.map(v.employee).whereType<Employee>().toList(),
      vehicles:
          (vehicleIds == null
                  ? v.vehicles
                  : vehicleIds.map(v.vehicle).whereType<Vehicle>())
              .toList(),
      drivers: v.drivers,
      locations: v.locationMap,
      serviceDate: dateOnly(serviceDate),
      existingTrips: v.trips.all(),
      guardRequired: guardRequired,
      variantPreference: variant,
      contracts: v.contractsOf(employer.id),
      allocations: v.allocations,
      startParkingId: startParkingId,
      guardsAvailable: guardsAvailable,
    );
  }

  /// Runs the engine (pure) — not persisted until [saveRun].
  OptimizationRun preview(OptimizationInput input) =>
      engine.run(input, runId: 'preview', reference: 'Preview', now: ctx.now);

  Future<Result<OptimizationRun>> runAndSave(
    OptimizationInput input, {
    Actor actor = Actor.fleetManager,
  }) => ctx.run((tx) {
    final id = tx.newId(ctx.db.optimizationRuns, 'OR-');
    final run = engine.run(input, runId: id, reference: id, now: ctx.now);
    tx.insert(ctx.db.optimizationRuns, run);
    ctx.audit(
      tx,
      actor,
      'optimization.run',
      'optimizationRun',
      id,
      '${run.status.label}: ${run.outputSummary}',
    );
    return run;
  }, info: 'Local demo optimizer run saved');

  Future<Result<OptimizationConfig>> saveConfig(
    OptimizationConfig c, {
    Actor actor = Actor.fleetManager,
  }) {
    final errors = <String>[
      if (c.name.trim().length < 3) 'Profile name is too short.',
      if (c.weights.values.any((w) => w < 0 || w > 10))
        'Weights must be between 0 and 10.',
      if (c.weights.values.every((w) => w == 0))
        'At least one weight must be above 0.',
      if (c.allowedVehicleTypes.isEmpty) 'Allow at least one vehicle type.',
      if (c.minimumBufferMinutes < 0 || c.minimumBufferMinutes > 60)
        'Buffer must be 0–60 minutes.',
      for (final e in c.additionalParameters.entries)
        if (ParameterCatalog.byKey(e.key) case final def?)
          if (e.value < def.min || e.value > def.max)
            '${def.name} must be between ${def.min} and ${def.max} ${def.unit}.',
    ];
    if (errors.isNotEmpty) return Future.value(Err(errors));
    return ctx.run((tx) {
      final saved = c.copyWith(updatedAt: ctx.now);
      tx.put(ctx.db.optimizationConfigs, saved);
      ctx.audit(
        tx,
        actor,
        'optimization.config',
        'optimizationConfig',
        c.id,
        'Updated optimization profile "${c.name}".',
      );
      return saved;
    }, info: 'Optimization profile saved');
  }

  /// Validates every plan, then creates trips — all or nothing.
  /// [guardReferences]: vehicleId → guard name/ID for plans whose guard
  /// comes from the pool (required by the hard guard rule).
  Future<Result<List<Trip>>> applyRun(
    String runId, {
    Actor actor = Actor.fleetManager,
    Map<String, String> guardReferences = const {},
  }) {
    final run = ctx.db.optimizationRuns[runId];
    if (run == null) return Future.value(Err.single('Run not found.'));
    if (!run.isFeasible) {
      return Future.value(
        Err.single('This run has no feasible proposal to apply.'),
      );
    }
    if (run.appliedAt != null) {
      return Future.value(
        Err.single('Run already applied (${run.appliedTripIds.join(', ')}).'),
      );
    }
    if (run.isRejected) {
      return Future.value(
        Err.single('Run was rejected and cannot be applied.'),
      );
    }
    final missingGuard = run.plans
        .where(
          (p) =>
              p.guardSource == 'pool' &&
              (guardReferences[p.vehicleId]?.trim().isEmpty ?? true),
        )
        .map((p) => p.vehicleId)
        .toList();
    if (missingGuard.isNotEmpty) {
      return Future.value(
        Err.single(
          'Name the security guard for Vehicle ${missingGuard.join(', ')} before applying.',
        ),
      );
    }
    final missingDriver = run.plans.where((p) => p.driverId == null).toList();
    if (missingDriver.isNotEmpty) {
      return Future.value(
        Err.single(
          'Some vehicles have no driver; re-run after updating availability.',
        ),
      );
    }
    return ctx.run(
      (tx) {
        final created = <Trip>[];
        for (final p in run.plans) {
          final bookingIds = ctx.db.bookings
              .where(
                (b) =>
                    p.employeeIds.contains(b.employeeId) &&
                    b.status.isOpen &&
                    sameDay(b.requestedDate, run.serviceDate),
              )
              .map((b) => b.id)
              .toList();
          final trip = assignments.commitInTx(
            tx,
            AssignmentRequest(
              employerId: run.employerId ?? ctx.view.primaryEmployer.id,
              serviceDate: run.serviceDate,
              employeeIds: p.employeeIds,
              driverId: p.driverId,
              vehicleId: p.vehicleId,
              variant: p.variant,
              plannedStops: p.stops,
              optimizationRunId: run.id,
              bookingIds: bookingIds,
              guardRequired:
                  p.guardSeats > 0 &&
                  !(ctx.db.vehicles[p.vehicleId]?.requiresSecurityGuard ??
                      false),
              guardReference: guardReferences[p.vehicleId],
              instructions:
                  'Created from ${run.reference} (local demo optimizer).',
            ),
            actor,
          );
          created.add(trip);
        }
        tx.put(
          ctx.db.optimizationRuns,
          run.copyWith(
            appliedAt: () => ctx.now,
            appliedTripIds: created.map((t) => t.id).toList(),
          ),
        );
        ctx.audit(
          tx,
          actor,
          'optimization.apply',
          'optimizationRun',
          run.id,
          'Applied ${run.reference}: created ${created.map((t) => t.tripCode).join(', ')}.',
        );
        return created;
      },
      info: 'Proposal applied — trips created and assigned',
      rejectAudit: RejectAudit(
        actor: actor,
        action: 'optimization.apply',
        entityType: 'optimizationRun',
        entityId: run.id,
        summary: 'Apply ${run.reference}',
      ),
    );
  }

  /// Operator rejects a proposal (kept for history, cannot be applied).
  Future<Result<OptimizationRun>> rejectRun(
    String runId,
    String reason, {
    Actor actor = Actor.fleetManager,
  }) {
    if (reason.trim().length < 5) {
      return Future.value(
        Err.single('Give a rejection reason (at least 5 characters).'),
      );
    }
    return ctx.run((tx) {
      final run = ctx.db.optimizationRuns[runId];
      if (run == null) throw ValidationFailure(['Run not found.']);
      if (run.appliedAt != null) {
        throw ValidationFailure(['Run already applied.']);
      }
      if (run.isRejected) throw ValidationFailure(['Run already rejected.']);
      final next = run.copyWith(
        rejectedAt: () => ctx.now,
        rejectionReason: () => reason.trim(),
      );
      tx.put(ctx.db.optimizationRuns, next);
      ctx.audit(
        tx,
        actor,
        'optimization.reject',
        'optimizationRun',
        run.id,
        'Rejected ${run.reference}.',
        outcome: AuditOutcome.rejected,
        reason: reason.trim(),
        simulated: true,
      );
      return next;
    }, info: 'Proposal rejected');
  }

  // ---------------- Pooling ----------------

  PoolingCheck checkPair(Employee a, Employee b, OptimizationConfig c) {
    final v = ctx.view;
    final reasons = <String>[];
    var ok = true;
    final ea = v.employer(a.employerId), eb = v.employer(b.employerId);
    if (!a.isActive || !b.isActive) {
      ok = false;
      reasons.add('Inactive employee');
    }
    if (ea?.allowSharedPooling == false || eb?.allowSharedPooling == false) {
      ok = false;
      reasons.add('Employer policy disallows shared pooling');
    }
    if (a.employerId != b.employerId &&
        !((ea?.allowCrossEmployerPooling ?? false) &&
            (eb?.allowCrossEmployerPooling ?? false))) {
      ok = false;
      reasons.add(
        'Different employers and cross-employer pooling not allowed by both',
      );
    }
    final window = ParameterCatalog.value(c, 'arrival_window_compat_min');
    final dt = (a.requiredArrivalMinutes - b.requiredArrivalMinutes).abs();
    if (dt > window) {
      ok = false;
      reasons.add('Arrival times differ by $dt min (limit ${window.round()})');
    } else {
      reasons.add('Arrival within $dt min');
    }
    final pa = v.location(a.pickupLocationId)!,
        pb = v.location(b.pickupLocationId)!;
    final pickKm = GeoRules.straightKm(pa, pb) * GeoRules.roadFactor;
    final maxDetour = ParameterCatalog.value(c, 'max_detour_km');
    if (pickKm > maxDetour) {
      ok = false;
      reasons.add(
        'Pickups ${pickKm.toStringAsFixed(1)} km apart (limit ${maxDetour.toStringAsFixed(0)} km)',
      );
    } else {
      reasons.add('Pickups ${pickKm.toStringAsFixed(1)} km apart');
    }
    final da = v.location(a.destinationId)!, db = v.location(b.destinationId)!;
    final destKm = GeoRules.straightKm(da, db) * GeoRules.roadFactor;
    final maxGap = ParameterCatalog.value(c, 'max_destination_gap_km');
    if (destKm > maxGap) {
      ok = false;
      reasons.add(
        'Destinations ${destKm.toStringAsFixed(1)} km apart (limit ${maxGap.toStringAsFixed(0)} km)',
      );
    } else {
      reasons.add(
        a.destinationId == b.destinationId
            ? 'Same destination ${a.destinationId}'
            : 'Destinations ${destKm.toStringAsFixed(1)} km apart',
      );
    }
    return PoolingCheck(a, b, ok, reasons);
  }

  /// Greedy, explainable grouping. Never forces an infeasible pool.
  PoolingResult suggestPools(
    List<String> employeeIds,
    OptimizationConfig c,
    DateTime day,
  ) {
    final v = ctx.view;
    final emps = employeeIds.map(v.employee).whereType<Employee>().toList()
      ..sort((a, b) {
        final x = a.requiredArrivalMinutes.compareTo(b.requiredArrivalMinutes);
        return x != 0 ? x : a.destinationId.compareTo(b.destinationId);
      });
    final maxPool = ParameterCatalog.value(c, 'max_pool_size').round();
    final vehicles =
        v.vehicles
            .where(
              (x) =>
                  x.status != VehicleStatus.maintenance &&
                  x.status != VehicleStatus.unavailable,
            )
            .toList()
          ..sort(
            (a, b) => CapacityRules.passengerCapacity(
              b,
            ).compareTo(CapacityRules.passengerCapacity(a)),
          );
    final maxCap = vehicles.isEmpty
        ? 0
        : CapacityRules.passengerCapacity(vehicles.first);
    final limit = math.min(maxPool, maxCap);
    final groups = <List<Employee>>[];
    final unpooled = <Employee, List<String>>{};
    final notes = <String>[
      'Groups use hard limits: arrival window ${ParameterCatalog.value(c, 'arrival_window_compat_min').round()} min, pickup detour ${ParameterCatalog.value(c, 'max_detour_km').toStringAsFixed(0)} km, destination gap ${ParameterCatalog.value(c, 'max_destination_gap_km').toStringAsFixed(0)} km, max pool $limit (largest available vehicle capacity).',
    ];
    for (final e in emps) {
      final busy = v.trips
          .forEmployee(e.id)
          .where(
            (t) =>
                sameDay(t.serviceDate, day) &&
                TripStateMachine.occupiesWindow(t.status),
          );
      if (busy.isNotEmpty) {
        unpooled[e] = ['Already on ${busy.first.tripCode}'];
        continue;
      }
      if (!e.isActive) {
        unpooled[e] = ['Inactive'];
        continue;
      }
      var placed = false;
      for (final g in groups) {
        if (g.length >= limit) continue;
        if (g.every((o) => checkPair(o, e, c).feasible)) {
          g.add(e);
          placed = true;
          break;
        }
      }
      if (!placed) groups.add([e]);
    }
    final result = <PoolGroup>[];
    for (final g in groups) {
      if (g.length == 1) {
        final e = g.first;
        final others = emps.where(
          (o) => o.id != e.id && !unpooled.containsKey(o),
        );
        final why = <String>{
          for (final o in others)
            ...checkPair(e, o, c).reasons.where(
              (r) =>
                  r.contains('limit') ||
                  r.contains('policy') ||
                  r.contains('employers'),
            ),
        };
        unpooled[e] = why.isEmpty
            ? ['No compatible co-rider in this selection (rides alone)']
            : why.take(3).toList();
        continue;
      }
      final cap =
          vehicles
              .where((x) => CapacityRules.passengerCapacity(x) >= g.length)
              .toList()
            ..sort(
              (a, b) => CapacityRules.passengerCapacity(
                a,
              ).compareTo(CapacityRules.passengerCapacity(b)),
            );
      final reasons = <String>[
        'All ${g.length} pairs satisfy arrival, detour and destination limits',
        'Destinations: ${g.map((e) => e.destinationId).toSet().join(', ')}',
        'Arrivals between ${_hm(g.map((e) => e.requiredArrivalMinutes).reduce(math.min))} and ${_hm(g.map((e) => e.requiredArrivalMinutes).reduce(math.max))}',
      ];
      result.add(PoolGroup(g, reasons, cap.firstOrNull));
    }
    return PoolingResult(result, unpooled, notes);
  }

  // ---------------- EV target ----------------

  EvTargetAnalysis evTarget(String employerId, DateTime day) {
    final v = ctx.view;
    final employer = v.employer(employerId) ?? v.primaryEmployer;
    final target = employer.preferredEvPercentage;
    final trips = v.trips
        .onDay(day)
        .where(
          (t) =>
              t.employerId == employer.id &&
              t.isAssigned &&
              t.status != TripStatus.cancelled,
        )
        .toList();
    final evTrips = trips
        .where((t) => v.vehicle(t.assignedVehicleId)?.isEv ?? false)
        .length;
    final actual = trips.isEmpty ? 0.0 : 100.0 * evTrips / trips.length;
    final usable = v.vehicles
        .where(
          (x) =>
              x.status != VehicleStatus.maintenance &&
              x.status != VehicleStatus.unavailable,
        )
        .toList();
    final evUsable = usable.where((x) => x.isEv).toList();
    final fleetEv = v.vehicles.isEmpty
        ? 0.0
        : 100.0 * v.vehicles.where((x) => x.isEv).length / v.vehicles.length;
    final maxAchievable = trips.isEmpty
        ? (usable.isEmpty ? 0.0 : 100.0 * evUsable.length / usable.length)
        : 100.0 * math.min(trips.length, evUsable.length) / trips.length;
    final explanation = <String>[
      'Target $target% of ${employer.code} trips on EVs; ${Fmtx.pct(actual)} today ($evTrips of ${trips.length} assigned trips).',
      'Fleet mix: ${v.vehicles.where((x) => x.isEv).length} of ${v.vehicles.length} vehicles are EV (${Fmtx.pct(fleetEv)}); ${evUsable.length} EV${evUsable.length == 1 ? '' : 's'} currently usable.',
    ];
    final feasible = maxAchievable + 0.01 >= target;
    if (!feasible) {
      explanation.add(
        'Target not achievable today: at most ${Fmtx.pct(maxAchievable)} with ${evUsable.length} usable EV${evUsable.length == 1 ? '' : 's'} '
        'for ${trips.isEmpty ? 'the usable fleet' : '${trips.length} trips'}. EV preference never overrides capacity, deadlines or availability.',
      );
    } else if (actual + 0.01 < target) {
      explanation.add(
        'Achievable but not met: reassigning trips to free EVs (where capacity and time windows allow) would raise the share.',
      );
    } else {
      explanation.add('Target met.');
    }
    for (final x in v.vehicles.where((x) => x.isEv && !usable.contains(x))) {
      explanation.add(
        'Vehicle ${x.vehicleCode} (EV) is ${x.status.label.toLowerCase()}.',
      );
    }
    return EvTargetAnalysis(
      targetPct: target,
      actualPct: actual,
      fleetEvPct: fleetEv,
      maxAchievablePct: maxAchievable,
      evTrips: evTrips,
      totalTrips: trips.length,
      feasible: feasible,
      explanation: explanation,
    );
  }

  static String _hm(int m) {
    final h = m ~/ 60, mm = m % 60;
    final ap = h >= 12 ? 'PM' : 'AM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${mm.toString().padLeft(2, '0')} $ap';
  }
}

abstract final class Fmtx {
  static String pct(double v) => '${v.toStringAsFixed(0)}%';
}
