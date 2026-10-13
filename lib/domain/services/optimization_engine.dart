import 'dart:math' as math;

import '../models/models.dart';
import '../rules/capacity_rules.dart';
import '../rules/geo_rules.dart';
import '../rules/parameter_catalog.dart';
import '../rules/tolerance_rules.dart';
import '../rules/trip_state_machine.dart';
import 'route_builder.dart';

/// Everything the engine needs. The engine is pure and deterministic:
/// identical input always yields identical output.
class OptimizationInput {
  const OptimizationInput({
    required this.config,
    required this.employer,
    required this.employees,
    required this.vehicles,
    required this.drivers,
    required this.locations,
    required this.serviceDate,
    required this.existingTrips,
    this.guardRequired = false,
    this.variantPreference,
    this.contracts = const [],
    this.allocations = const [],
    this.startParkingId,
    this.guardsAvailable = 0,
  });

  final OptimizationConfig config;
  final Employer employer;
  final List<Employee> employees;
  final List<Vehicle> vehicles;
  final List<Driver> drivers;
  final Map<String, Location> locations;
  final DateTime serviceDate;
  final List<Trip> existingTrips;
  final bool guardRequired;

  /// Null = let the engine compare ring road vs internal roads.
  final RouteVariant? variantPreference;

  /// Employer contracts (hard/soft car limits) and fleet allocations.
  final List<Contract> contracts;
  final List<FleetAllocation> allocations;

  /// Parking/depot every vehicle starts from; null = each vehicle's home
  /// parking.
  final String? startParkingId;

  /// Security guards available from the operator's pool for this run
  /// (vehicles with an assigned guard do not consume one).
  final int guardsAvailable;
}

/// Why a vehicle was or was not eligible.
class VehicleEligibility {
  const VehicleEligibility(this.vehicle, this.driver, this.reasons);
  final Vehicle vehicle;
  final Driver? driver;
  final List<String> reasons;
  bool get eligible => reasons.isEmpty;
}

class _Candidate {
  _Candidate(this.plans);
  final List<VehiclePlan> plans;
  double cost = 0, km = 0, minutes = 0;
  double punctualityPenalty = 0, utilizationPenalty = 0, evPenalty = 0;
  double preferencePenalty = 0, safetyPenalty = 0, guardPenalty = 0;
  double detourPenalty = 0, proximityPenalty = 0, employeePrefPenalty = 0;
  double evShare = 0;
  double score = 0;
  List<ScoreComponent> breakdown = const [];
  String get signature =>
      (plans
              .map(
                (p) =>
                    '${p.vehicleId}:${(p.employeeIds.toList()..sort()).join('+')}',
              )
              .toList()
            ..sort())
          .join(' | ');
}

/// Per-employee ride metrics inside a plan.
class _Ride {
  const _Ride(this.minutes, this.km, this.detourRatio, this.slack);
  final int minutes;
  final double km;
  final double detourRatio;
  final int slack;
}

/// Local demo optimizer: cluster-first / route-second search with weighted,
/// explainable scoring. Hard constraints (capacity incl. driver + guard
/// seats, deadlines, availability, licences, contracts, fleet-company
/// allocations, guard availability, allowed types, EV range) are filters and
/// can never be traded away for a better score. Soft employee preferences
/// only influence the score. NOT OR-Tools, NOT production AI.
class OptimizationEngine {
  const OptimizationEngine();

  static const exhaustiveLimit = 6000;

  static const constraintNames = [
    'Employee active & same/permitted company',
    'Employee not already scheduled that day',
    'Arrival deadline (required arrival, shift start, employer maximum)',
    'Vehicle status, active, energy level, allowed type',
    'Driver duty status, active, licence validity',
    'No overlapping vehicle/driver assignments',
    'Fleet-company allocation windows',
    'Contract validity and car limit',
    'Seat capacity: total − driver − guard seats',
    'Security guard availability',
    'Pooling compatibility (arrival window, detour, destination gap)',
    'Max trip duration, route length, stops, EV range',
  ];

  double _param(OptimizationConfig c, String key) =>
      ParameterCatalog.value(c, key);

  DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  List<VehicleEligibility> vehicleEligibility(OptimizationInput input) {
    final c = input.config;
    final day = _day(input.serviceDate);
    final deadlines = input.employees.map((e) => e.arrivalDeadlineMinutes);
    final earliestDeadline = deadlines.isEmpty
        ? 540
        : deadlines.reduce(math.min);
    final latestDeadline = deadlines.isEmpty ? 570 : deadlines.reduce(math.max);
    final windowStart = day.add(Duration(minutes: earliestDeadline - 150));
    final windowEnd = day.add(Duration(minutes: latestDeadline + 15));
    final buffer = Duration(
      minutes: _param(c, 'assignment_overlap_buffer_min').round(),
    );
    final wStartMin = math.max(0, earliestDeadline - 150);
    final wEndMin = math.min(1439, latestDeadline + 15);

    bool overlaps(Trip t) =>
        TripStateMachine.occupiesWindow(t.status) &&
        t.scheduledStart.isBefore(windowEnd.add(buffer)) &&
        t.windowEnd.add(buffer).isAfter(windowStart);

    String? allocationIssue(ResourceType type, String id, String label) =>
        CommercialRules.allocation(
          resourceAllocations: input.allocations
              .where((a) => a.resourceType == type && a.resourceId == id)
              .toList(),
          employerId: input.employer.id,
          employerCode: input.employer.code,
          resourceLabel: label,
          startMinutes: wStartMin,
          endMinutes: wEndMin,
        );

    final result = <VehicleEligibility>[];
    final usedDrivers = <String>{};
    for (final v in input.vehicles) {
      final reasons = <String>[];
      if (!v.active) reasons.add('Deactivated');
      if (v.status == VehicleStatus.maintenance) reasons.add('In maintenance');
      if (v.status == VehicleStatus.unavailable) {
        reasons.add('Marked unavailable');
      }
      if (c.allowedVehicleTypes.isNotEmpty &&
          !c.allowedVehicleTypes.contains(v.type)) {
        reasons.add('${v.type.label} not in allowed vehicle types');
      }
      if (v.assignedEmployerId != null &&
          v.assignedEmployerId != input.employer.id) {
        reasons.add('Dedicated to another employer');
      }
      final level = v.batteryOrFuelPercent;
      if (level != null) {
        final min = v.isEv
            ? _param(c, 'min_battery_pct')
            : _param(c, 'min_fuel_pct');
        if (level < min) {
          reasons.add(
            '${v.isEv ? 'Battery' : 'Fuel'} $level% below minimum ${min.round()}%',
          );
        }
      }
      final conflict = input.existingTrips.where(
        (t) => t.assignedVehicleId == v.id && overlaps(t),
      );
      if (conflict.isNotEmpty) {
        reasons.add('Busy on ${conflict.first.tripCode} in this time window');
      }
      final vAlloc = allocationIssue(
        ResourceType.vehicle,
        v.id,
        'Vehicle ${v.vehicleCode}',
      );
      if (vAlloc != null) reasons.add(vAlloc);

      // Pair with a driver: vehicle's default driver first, then any free one.
      Driver? driver;
      final candidates = [
        ...input.drivers.where((d) => d.id == v.assignedDriverId),
        ...input.drivers.where((d) => d.id != v.assignedDriverId),
      ];
      for (final d in candidates) {
        if (usedDrivers.contains(d.id)) continue;
        if (!d.active) continue;
        if (d.status == DriverStatus.offDuty ||
            d.status == DriverStatus.unavailable) {
          continue;
        }
        if (d.licenceNumber.trim().isEmpty || !d.licenceValidOn(day)) continue;
        if (d.assignedVehicleId != null &&
            d.assignedVehicleId != v.id &&
            input.vehicles.any(
              (x) =>
                  x.id == d.assignedVehicleId &&
                  x.active &&
                  x.status != VehicleStatus.maintenance &&
                  x.status != VehicleStatus.unavailable,
            )) {
          continue; // keep drivers with their own usable vehicle
        }
        if (input.existingTrips.any(
          (t) => t.assignedDriverId == d.id && overlaps(t),
        )) {
          continue;
        }
        if (allocationIssue(ResourceType.driver, d.id, d.driverCode) != null) {
          continue;
        }
        driver = d;
        break;
      }
      if (driver == null) {
        reasons.add(
          'No available, licensed driver allocated to ${input.employer.code} for this window',
        );
      }
      if (reasons.isEmpty && driver != null) usedDrivers.add(driver.id);
      result.add(VehicleEligibility(v, driver, reasons));
    }
    return result;
  }

  OptimizationRun run(
    OptimizationInput input, {
    required String runId,
    required String reference,
    required DateTime now,
  }) {
    final c = input.config;
    final violations = <String>[];
    final warnings = <String>[];
    final explanation = <String>[];
    final maxArrival = math.min(
      c.maximumArrivalMinutes,
      input.employer.maximumArrivalMinutes,
    );
    final day = _day(input.serviceDate);

    // ---- Employee eligibility (hard) ----
    if (input.employees.isEmpty) violations.add('No employees selected.');
    final seenIds = <String>{};
    for (final e in input.employees) {
      if (!seenIds.add(e.id)) {
        violations.add('${e.employeeCode} is selected twice.');
      }
      if (!e.isActive) {
        violations.add(
          '${e.employeeCode} is inactive and cannot be scheduled.',
        );
      }
      if (e.employerId != input.employer.id &&
          !input.employer.allowCrossEmployerPooling) {
        violations.add(
          '${e.employeeCode} belongs to another company and cross-company pooling is not allowed.',
        );
      }
      for (final t in input.existingTrips) {
        final sameDay =
            t.serviceDate.year == day.year &&
            t.serviceDate.month == day.month &&
            t.serviceDate.day == day.day;
        if (sameDay &&
            TripStateMachine.occupiesWindow(t.status) &&
            t.employeeIds.contains(e.id)) {
          violations.add(
            '${e.employeeCode} is already scheduled on ${t.tripCode} that day.',
          );
        }
      }
    }
    // Deadline = min(required arrival, shift start, employer max).
    final employees = [
      for (final e in input.employees)
        e.copyWith(
          requiredArrivalMinutes: math.min(
            e.arrivalDeadlineMinutes,
            maxArrival,
          ),
        ),
    ];
    for (final e in input.employees.where(
      (e) => e.arrivalDeadlineMinutes > maxArrival,
    )) {
      warnings.add(
        '${e.employeeCode} requested ${_hm(e.arrivalDeadlineMinutes)} but the employer maximum is ${_hm(maxArrival)}; the maximum was used.',
      );
    }

    // ---- Vehicle eligibility (hard) ----
    final eligibility = vehicleEligibility(input);
    final eligible = eligibility.where((e) => e.eligible).toList();
    for (final e in eligibility.where((e) => !e.eligible)) {
      explanation.add(
        'Vehicle ${e.vehicle.vehicleCode} excluded: ${e.reasons.join('; ')}.',
      );
    }
    if (eligible.isEmpty) {
      violations.add(
        'No eligible vehicle: every candidate failed availability, allocation, type, energy or driver constraints.',
      );
    }

    final guardRequired =
        input.guardRequired ||
        (input.employer.securityGuardPolicyEnabled &&
            employees.any((e) => e.guardEscortRequired));
    if (guardRequired) {
      explanation.add(
        'Guard policy applies: one seat per vehicle is reserved for a security guard before employee capacity is calculated. '
        'Guards available from pool: ${input.guardsAvailable}; vehicles with an assigned guard: '
        '${eligible.where((e) => e.vehicle.securityGuardAssigned).map((e) => e.vehicle.vehicleCode).join(', ').ifEmpty('none')}.',
      );
      final coverable =
          eligible.where((e) => e.vehicle.securityGuardAssigned).length +
          input.guardsAvailable;
      if (coverable == 0) {
        violations.add(
          'Security guard required but no guard is available (assign a guard to a vehicle or add guards to the pool).',
        );
      }
    }

    final totalCapacity = eligible.fold<int>(
      0,
      (s, e) =>
          s +
          CapacityRules.passengerCapacity(
            e.vehicle,
            guardRequired: guardRequired,
          ),
    );
    if (eligible.isNotEmpty && employees.length > totalCapacity) {
      violations.add(
        'Capacity: ${employees.length} employees but eligible vehicles seat only $totalCapacity '
        '(${eligible.map((e) => '${e.vehicle.vehicleCode}: ${CapacityRules.breakdown(e.vehicle, guardRequired: guardRequired)}').join('; ')}).',
      );
    }

    // ---- Contract car limit (hard/soft) ----
    final usedThatDay = <String>{
      for (final t in input.existingTrips)
        if (t.employerId == input.employer.id &&
            t.assignedVehicleId != null &&
            t.serviceDate.year == day.year &&
            t.serviceDate.month == day.month &&
            t.serviceDate.day == day.day &&
            TripStateMachine.occupiesWindow(t.status))
          t.assignedVehicleId!,
    };
    int? maxNewVehicles;
    if (input.contracts.isNotEmpty) {
      final active = input.contracts.where((k) => k.coversDay(day)).firstOrNull;
      if (active == null) {
        violations.add(
          'No active contract for ${input.employer.code} on ${day.day}/${day.month}/${day.year}.',
        );
      } else {
        explanation.add(
          'Contract ${active.contractCode}: up to ${active.agreedVehicleCount} car(s) per day '
          '(${active.hardVehicleLimit ? 'hard' : 'soft'} limit); already used that day: ${usedThatDay.length}.',
        );
        if (active.hardVehicleLimit) maxNewVehicles = active.agreedVehicleCount;
      }
    }
    bool contractOk(List<VehiclePlan> plans) {
      if (maxNewVehicles == null) return true;
      return {...usedThatDay, ...plans.map((p) => p.vehicleId)}.length <=
          maxNewVehicles;
    }

    bool guardsOk(List<VehiclePlan> plans) {
      if (!guardRequired) return true;
      final pool = plans.where((p) => p.guardSource == 'pool').length;
      return pool <= input.guardsAvailable;
    }

    final maxPool = _param(c, 'max_pool_size').round();
    final feasible = <_Candidate>[];
    final infeasibleReasons = <String, int>{};
    void note(String r) =>
        infeasibleReasons[r] = (infeasibleReasons[r] ?? 0) + 1;

    if (violations.isEmpty) {
      final cache = <String, VehiclePlan?>{};
      final variants = input.variantPreference != null
          ? [input.variantPreference!]
          : RouteVariant.values;

      VehiclePlan? planGroup(VehicleEligibility ve, List<Employee> group) {
        final key =
            '${ve.vehicle.id}|${(group.map((e) => e.id).toList()..sort()).join(',')}';
        if (cache.containsKey(key)) return cache[key];
        VehiclePlan? bestPlan;
        var bestScore = double.infinity;
        String? lastReason;
        for (final variant in variants) {
          final r = _evaluateGroup(
            input,
            ve,
            group,
            day,
            variant,
            guardRequired,
            maxPool,
          );
          if (r.$2 != null) {
            lastReason = r.$2;
            continue;
          }
          final p = r.$1!;
          final ringBias = _param(c, 'ring_road_preference');
          final s =
              p.estimatedCost * (c.costWeight + 1) +
              p.durationMinutes * (c.travelTimeWeight + 1) * 2 -
              (variant == RouteVariant.ringRoad ? ringBias * 10 : 0);
          if (s < bestScore) {
            bestScore = s;
            bestPlan = p;
          }
        }
        if (bestPlan == null && lastReason != null) note(lastReason);
        cache[key] = bestPlan;
        return bestPlan;
      }

      bool compatible(Employee a, Employee b) {
        final la = input.locations[a.pickupLocationId]!,
            lb = input.locations[b.pickupLocationId]!;
        final da = input.locations[a.destinationId]!,
            db = input.locations[b.destinationId]!;
        if ((a.requiredArrivalMinutes - b.requiredArrivalMinutes).abs() >
            _param(c, 'arrival_window_compat_min')) {
          return false;
        }
        if (GeoRules.straightKm(la, lb) * GeoRules.roadFactor >
            _param(c, 'max_detour_km')) {
          return false;
        }
        if (GeoRules.straightKm(da, db) * GeoRules.roadFactor >
            _param(c, 'max_destination_gap_km')) {
          return false;
        }
        if (a.employerId != b.employerId &&
            !input.employer.allowCrossEmployerPooling) {
          return false;
        }
        return true;
      }

      final n = employees.length;
      final vCount = eligible.length;
      final combos = math.pow(vCount + 0.0, n).toDouble();
      const poolingReason =
          'Some employees cannot share a vehicle (arrival window, pickup detour or destination gap limits).';

      void consider(List<List<Employee>> groups) {
        final plans = <VehiclePlan>[];
        for (var vi = 0; vi < groups.length; vi++) {
          final g = groups[vi];
          if (g.isEmpty) continue;
          for (var i = 0; i < g.length; i++) {
            for (var j = i + 1; j < g.length; j++) {
              if (!compatible(g[i], g[j])) {
                note(poolingReason);
                return;
              }
            }
          }
          final p = planGroup(eligible[vi], g);
          if (p == null) return;
          plans.add(p);
        }
        if (!contractOk(plans)) {
          note('Contract car limit would be exceeded by this grouping.');
          return;
        }
        if (!guardsOk(plans)) {
          note('Not enough security guards for this grouping.');
          return;
        }
        feasible.add(_Candidate(plans));
      }

      if (combos <= exhaustiveLimit) {
        final assign = List<int>.filled(n, 0);
        void rec(int i) {
          if (i == n) {
            final groups = List.generate(vCount, (_) => <Employee>[]);
            for (var k = 0; k < n; k++) {
              groups[assign[k]].add(employees[k]);
            }
            for (var vi = 0; vi < vCount; vi++) {
              if (groups[vi].length >
                  CapacityRules.passengerCapacity(
                    eligible[vi].vehicle,
                    guardRequired: guardRequired,
                  )) {
                return;
              }
            }
            consider(groups);
            return;
          }
          for (var v = 0; v < vCount; v++) {
            assign[i] = v;
            rec(i + 1);
          }
        }

        rec(0);
      } else {
        // Greedy regret insertion for larger selections.
        final groups = List.generate(vCount, (_) => <Employee>[]);
        final order = [...employees]
          ..sort((a, b) {
            final x = a.requiredArrivalMinutes.compareTo(
              b.requiredArrivalMinutes,
            );
            return x != 0 ? x : a.id.compareTo(b.id);
          });
        var ok = true;
        for (final e in order) {
          var bestV = -1;
          var bestCost = double.infinity;
          for (var vi = 0; vi < vCount; vi++) {
            final cap = CapacityRules.passengerCapacity(
              eligible[vi].vehicle,
              guardRequired: guardRequired,
            );
            if (groups[vi].length >= cap) continue;
            if (groups[vi].any((o) => !compatible(o, e))) continue;
            final trial = [...groups[vi], e];
            final p = planGroup(eligible[vi], trial);
            if (p == null) continue;
            final prev = groups[vi].isEmpty
                ? null
                : planGroup(eligible[vi], groups[vi]);
            final delta = p.estimatedCost - (prev?.estimatedCost ?? 0);
            if (delta < bestCost) {
              bestCost = delta;
              bestV = vi;
            }
          }
          if (bestV < 0) {
            ok = false;
            violations.add(
              '${e.employeeCode} cannot be placed in any eligible vehicle without breaking a hard constraint.',
            );
            break;
          }
          groups[bestV].add(e);
        }
        if (ok) consider(groups);
      }

      if (feasible.isEmpty && violations.isEmpty) {
        violations.addAll(
          infeasibleReasons.keys.isEmpty
              ? ['No assignment satisfies all hard constraints.']
              : infeasibleReasons.keys,
        );
      }
    }

    _Candidate? best;
    String? preferenceEffect;
    if (feasible.isNotEmpty) {
      _score(feasible, input, guardRequired, c);
      int byScore(_Candidate a, _Candidate b) {
        final x = b.score.compareTo(a.score);
        return x != 0 ? x : a.cost.compareTo(b.cost);
      }

      // Counterfactual: what would win without employee preferences?
      final withoutPrefs = [...feasible]
        ..sort((a, b) {
          final sa = _scoreWithout(a, c, 'employeePreference');
          final sb = _scoreWithout(b, c, 'employeePreference');
          final x = sb.compareTo(sa);
          return x != 0 ? x : a.cost.compareTo(b.cost);
        });
      feasible.sort(byScore);
      best = feasible.first;
      if (employees.any((e) => e.hasTravelPreferences) &&
          c.employeePreferenceWeight > 0) {
        preferenceEffect = withoutPrefs.first.signature == best.signature
            ? 'Saved employee preferences were scored (weight ${c.employeePreferenceWeight.toStringAsFixed(1)}) but did not change the chosen grouping.'
            : 'Saved employee preferences changed the recommendation: without them the optimizer would choose ${_planSummary(input, withoutPrefs.first.plans)}.';
      }
    }

    final configWeights = c.weights;
    final candidateVehicleIds = input.vehicles.map((v) => v.id).toList();
    final candidateDriverIds = input.drivers.map((d) => d.id).toList();

    if (best == null) {
      return OptimizationRun(
        id: runId,
        reference: reference,
        configurationId: c.id,
        employerId: input.employer.id,
        createdAt: now,
        serviceDate: input.serviceDate,
        status: OptimizationRunStatus.noFeasibleSolution,
        inputSummary: _inputSummary(input),
        outputSummary:
            'No feasible assignment. ${violations.length} hard constraint${violations.length == 1 ? '' : 's'} failed.',
        totalDistanceKm: 0,
        estimatedMinutes: 0,
        estimatedCost: 0,
        onTimeScore: 0,
        vehicleUtilization: 0,
        evAllocationPercentage: 0,
        warnings: warnings,
        explanation: [
          'The local demo optimizer did not fabricate a route because hard constraints could not be met.',
          ...explanation,
        ],
        score: 0,
        plans: const [],
        scoreBreakdown: const [],
        hardConstraintViolations: violations,
        employeeIds: input.employees.map((e) => e.id).toList(),
        weightsSnapshot: configWeights,
        remedies: _remedies(violations),
        candidateVehicleIds: candidateVehicleIds,
        candidateDriverIds: candidateDriverIds,
        constraintsEvaluated: constraintNames,
      );
    }

    final b = best;
    final target = math.max(
      c.minimumEvPercentage,
      input.employer.preferredEvPercentage,
    );
    final evVehicles = eligible.where((e) => e.vehicle.isEv).length;
    if (b.evShare + 0.01 < target) {
      final reason = evVehicles == 0
          ? 'no EV is eligible for this window'
          : 'the EV share is limited by eligible EV capacity/deadlines (${b.plans.length} vehicle${b.plans.length == 1 ? '' : 's'} used)';
      warnings.add(
        'EV target $target% not met: proposal uses ${b.evShare.toStringAsFixed(0)}% EV because $reason. EV preference never overrides hard constraints.',
      );
    }
    for (final p in b.plans) {
      final slack = p.deadline.difference(p.latestArrival).inMinutes;
      if (slack < c.minimumBufferMinutes) {
        warnings.add(
          'Vehicle ${_vc(input, p.vehicleId)} arrives with only $slack min buffer (target ${c.minimumBufferMinutes} min).',
        );
      }
    }

    explanation.insert(
      0,
      'Strategy: cluster-first, route-second. Employees were assigned to vehicles by evaluating '
      '${feasible.length} feasible assignment${feasible.length == 1 ? '' : 's'}; pickups are ordered farthest-from-office first and drops by earliest deadline — not nearest-path.',
    );
    for (final p in b.plans) {
      final v = input.vehicles.firstWhere((x) => x.id == p.vehicleId);
      final start = input.locations[p.startLocationId];
      explanation.add(
        'Vehicle ${v.vehicleCode} (${v.propulsion.label} ${v.type.label}, ${p.employeeIds.length}/${p.passengerCapacity} seats): '
        '${p.employeeIds.map((id) => _ec(input, id)).join(', ')} via ${p.variant.label.toLowerCase()}, '
        '${p.distanceKm.toStringAsFixed(1)} km, departs ${_t(p.departure)}, first drop ${_t(p.latestArrival)} (deadline ${_t(p.deadline)})'
        '${start != null ? '; starts from ${start.code} (${p.deadheadKm.toStringAsFixed(1)} km empty to first pickup)' : ''}'
        '${p.guardSource != null ? '; guard from ${p.guardSource == 'vehicle' ? 'vehicle assignment' : 'pool'}' : ''}.',
      );
    }
    explanation.add(
      'EV allocation ${b.evShare.toStringAsFixed(0)}% vs target $target%.',
    );

    final preferenceSummary = _preferenceSummary(input, b, employees);
    if (preferenceEffect != null) preferenceSummary.insert(0, preferenceEffect);

    final alternatives = <String>[
      for (final alt in feasible.skip(1).take(3))
        'Alternative: ${alt.plans.length} vehicle${alt.plans.length == 1 ? '' : 's'} (${alt.plans.map((p) => _vc(input, p.vehicleId)).join(' + ')}) · score ${alt.score.toStringAsFixed(1)} · ${alt.km.toStringAsFixed(1)} km · ₹${alt.cost.toStringAsFixed(0)}',
    ];
    for (final p in b.plans) {
      final other = p.variant == RouteVariant.ringRoad
          ? RouteVariant.internalRoads
          : RouteVariant.ringRoad;
      final ve = eligible.firstWhere((e) => e.vehicle.id == p.vehicleId);
      final group = employees
          .where((e) => p.employeeIds.contains(e.id))
          .toList();
      final r = _evaluateGroup(
        input,
        ve,
        group,
        day,
        other,
        guardRequired,
        maxPool,
      );
      alternatives.add(
        r.$1 == null
            ? 'Vehicle ${ve.vehicle.vehicleCode} via ${other.label.toLowerCase()}: infeasible (${r.$2}).'
            : 'Vehicle ${ve.vehicle.vehicleCode} via ${other.label.toLowerCase()}: ${r.$1!.distanceKm.toStringAsFixed(1)} km, ${r.$1!.durationMinutes} min, ₹${r.$1!.estimatedCost.toStringAsFixed(0)} vs chosen ${p.distanceKm.toStringAsFixed(1)} km, ${p.durationMinutes} min.',
      );
    }
    for (final reason in infeasibleReasons.keys.take(3)) {
      alternatives.add('Rejected groupings: $reason');
    }

    final totalSeats = b.plans.fold<int>(0, (s, p) => s + p.passengerCapacity);
    final onTime = b.plans.every((p) => p.onTime);
    return OptimizationRun(
      id: runId,
      reference: reference,
      configurationId: c.id,
      employerId: input.employer.id,
      createdAt: now,
      serviceDate: input.serviceDate,
      status: OptimizationRunStatus.demoCalculated,
      inputSummary: _inputSummary(input),
      outputSummary:
          '${b.plans.length} vehicle${b.plans.length == 1 ? '' : 's'}, ${employees.length} employees, '
          '${b.km.toStringAsFixed(1)} km, est. ₹${b.cost.toStringAsFixed(0)}, score ${b.score.toStringAsFixed(1)}/100.',
      totalDistanceKm: double.parse(b.km.toStringAsFixed(1)),
      estimatedMinutes: b.minutes.round(),
      estimatedCost: double.parse(b.cost.toStringAsFixed(2)),
      onTimeScore: onTime ? 100 * (1 - b.punctualityPenalty) : 0,
      vehicleUtilization: totalSeats == 0
          ? 0
          : 100 * employees.length / totalSeats,
      evAllocationPercentage: b.evShare,
      warnings: warnings,
      explanation: explanation,
      score: double.parse(b.score.toStringAsFixed(1)),
      plans: b.plans,
      scoreBreakdown: b.breakdown,
      hardConstraintViolations: const [],
      employeeIds: input.employees.map((e) => e.id).toList(),
      alternatives: alternatives,
      weightsSnapshot: configWeights,
      preferenceSummary: preferenceSummary,
      candidateVehicleIds: candidateVehicleIds,
      candidateDriverIds: candidateDriverIds,
      constraintsEvaluated: constraintNames,
    );
  }

  /// Plans one vehicle group; returns (plan, null) or (null, reason).
  (VehiclePlan?, String?) _evaluateGroup(
    OptimizationInput input,
    VehicleEligibility ve,
    List<Employee> group,
    DateTime day,
    RouteVariant variant,
    bool guardRequired,
    int maxPool,
  ) {
    final c = input.config;
    final v = ve.vehicle;
    final cap = CapacityRules.passengerCapacity(
      v,
      guardRequired: guardRequired,
    );
    if (group.length > cap) {
      return (null, 'Vehicle ${v.vehicleCode} seats $cap employees');
    }
    if (group.length > maxPool) return (null, 'Pool size limit $maxPool');

    final pickupIds = group.map((e) => e.pickupLocationId).toSet().toList()
      ..sort();
    final orders = pickupIds.length <= 4 ? _permutations(pickupIds) : [null];
    RoutePlan? bestPlan;
    for (final order in orders) {
      final plan = RouteBuilder.planForDeadline(
        employees: group,
        locations: input.locations,
        serviceDay: day,
        bufferMinutes: c.minimumBufferMinutes,
        variant: variant,
        pickupOrder: order,
        earliestDepartureMinutes: _param(c, 'earliest_pickup_min').round(),
      );
      if (bestPlan == null ||
          plan.durationMinutes < bestPlan.durationMinutes ||
          (plan.durationMinutes == bestPlan.durationMinutes &&
              plan.distanceKm < bestPlan.distanceKm)) {
        bestPlan = plan;
      }
    }
    final plan = bestPlan!;
    for (final e in group) {
      final drop = plan.dropTimeFor(e.id)!;
      final deadline = day.add(Duration(minutes: e.requiredArrivalMinutes));
      if (drop.isAfter(deadline)) {
        return (null, 'Arrival deadline for ${e.employeeCode} cannot be met');
      }
    }
    if (plan.durationMinutes > _param(c, 'max_trip_duration_min')) {
      return (null, 'Trip would exceed maximum duration');
    }
    if (plan.distanceKm > _param(c, 'max_route_km')) {
      return (null, 'Route exceeds maximum length');
    }
    if (plan.stops.length > _param(c, 'max_stops_per_trip')) {
      return (null, 'Too many stops');
    }
    final startId = input.startParkingId ?? v.homeParkingId;
    final start = input.locations[startId];
    final deadheadKm = start == null
        ? 0.0
        : GeoRules.roadKm(
            start,
            input.locations[plan.stops.first.locationId]!,
            variant,
          );
    if (v.isEv) {
      final range =
          _param(c, 'ev_range_km') * ((v.batteryOrFuelPercent ?? 100) / 100);
      if (plan.distanceKm + deadheadKm > range) {
        return (null, 'EV range insufficient for Vehicle ${v.vehicleCode}');
      }
    }
    final buffer = Duration(
      minutes: _param(c, 'assignment_overlap_buffer_min').round(),
    );
    final startT = plan.departure, endT = plan.arrival;
    for (final t in input.existingTrips) {
      if (!TripStateMachine.occupiesWindow(t.status)) continue;
      final overlap =
          t.scheduledStart.isBefore(endT.add(buffer)) &&
          t.windowEnd.add(buffer).isAfter(startT);
      if (!overlap) continue;
      if (t.assignedVehicleId == v.id) {
        return (null, 'Vehicle ${v.vehicleCode} busy on ${t.tripCode}');
      }
      if (ve.driver != null && t.assignedDriverId == ve.driver!.id) {
        return (null, 'Driver busy on ${t.tripCode}');
      }
    }
    final costPerKm = _param(
      c,
      v.isEv
          ? 'ev_cost_per_km'
          : (v.propulsion == Propulsion.hybrid
                ? 'hybrid_cost_per_km'
                : 'ice_cost_per_km'),
    );
    final cost =
        (plan.distanceKm +
                deadheadKm * _param(c, 'deadhead_weight').clamp(0, 1)) *
            costPerKm +
        _param(c, 'fixed_cost_per_vehicle');
    final deadline = day.add(
      Duration(
        minutes: group.map((e) => e.requiredArrivalMinutes).reduce(math.min),
      ),
    );
    final needsGuard = guardRequired || v.requiresSecurityGuard;
    return (
      VehiclePlan(
        vehicleId: v.id,
        driverId: ve.driver?.id,
        employeeIds: group.map((e) => e.id).toList(),
        stops: plan.stops,
        distanceKm: plan.distanceKm,
        durationMinutes: plan.durationMinutes,
        estimatedCost: double.parse(cost.toStringAsFixed(2)),
        departure: plan.departure,
        latestArrival: plan.stops
            .firstWhere((s) => s.kind == StopKind.drop)
            .plannedArrival,
        deadline: deadline,
        passengerCapacity: cap,
        guardSeats: CapacityRules.breakdown(
          v,
          guardRequired: guardRequired,
        ).guardSeats,
        variant: variant,
        startLocationId: start?.id,
        deadheadKm: double.parse(deadheadKm.toStringAsFixed(1)),
        guardSource: needsGuard
            ? (v.securityGuardAssigned ? 'vehicle' : 'pool')
            : null,
        totalSeats: v.totalSeats,
      ),
      null,
    );
  }

  Map<String, _Ride> _rides(
    VehiclePlan p,
    OptimizationInput input,
    DateTime day,
    Map<String, Employee> emp,
  ) {
    final out = <String, _Ride>{};
    for (final id in p.employeeIds) {
      final e = emp[id]!;
      final pickupIdx = p.stops.indexWhere(
        (s) => s.kind == StopKind.pickup && s.employeeIds.contains(id),
      );
      final dropIdx = p.stops.indexWhere(
        (s) => s.kind == StopKind.drop && s.employeeIds.contains(id),
      );
      if (pickupIdx < 0 || dropIdx < 0) continue;
      var km = 0.0;
      for (var i = pickupIdx + 1; i <= dropIdx; i++) {
        km += GeoRules.roadKm(
          input.locations[p.stops[i - 1].locationId]!,
          input.locations[p.stops[i].locationId]!,
          p.variant,
        );
      }
      final direct = GeoRules.roadKm(
        input.locations[e.pickupLocationId]!,
        input.locations[e.destinationId]!,
        p.variant,
      );
      final minutes = p.stops[dropIdx].plannedArrival
          .difference(p.stops[pickupIdx].plannedArrival)
          .inMinutes;
      final slack = day
          .add(Duration(minutes: e.requiredArrivalMinutes))
          .difference(p.stops[dropIdx].plannedArrival)
          .inMinutes;
      out[id] = _Ride(minutes, km, direct <= 0.05 ? 1 : km / direct, slack);
    }
    return out;
  }

  void _score(
    List<_Candidate> cands,
    OptimizationInput input,
    bool guardRequired,
    OptimizationConfig c,
  ) {
    final day = _day(input.serviceDate);
    final target = math
        .max(c.minimumEvPercentage, input.employer.preferredEvPercentage)
        .toDouble();
    final vehicleById = {for (final v in input.vehicles) v.id: v};
    final empById = {for (final e in input.employees) e.id: e};
    final maxRide = math.max(1.0, _param(c, 'max_ride_time_min'));
    final maxRideKm = math.max(1.0, _param(c, 'max_ride_km_per_passenger'));
    for (final cand in cands) {
      cand.cost = cand.plans.fold(0, (s, p) => s + p.estimatedCost);
      cand.km = cand.plans.fold(0, (s, p) => s + p.distanceKm);
      cand.minutes = cand.plans
          .fold(0, (s, p) => s + p.durationMinutes)
          .toDouble();
      var pen = 0.0,
          count = 0,
          detour = 0.0,
          proximity = 0.0,
          prefPen = 0.0,
          prefCount = 0;
      for (final p in cand.plans) {
        final rides = _rides(p, input, day, empById);
        for (final id in p.employeeIds) {
          final e = empById[id]!;
          final ride = rides[id];
          if (ride == null) continue;
          final tol = e.toleranceMinutes(input.employer);
          final buf = math.max(1, c.minimumBufferMinutes);
          var x = ride.slack < buf ? (buf - ride.slack) / buf : 0.0;
          final early = _param(c, 'max_early_arrival_min');
          if (ride.slack > early) {
            x += math.min(1, (ride.slack - early) / early) * 0.5;
          }
          pen += x.clamp(0, 1);
          count++;
          final detourPen = (ride.detourRatio - 1).clamp(0.0, 1.0);
          detour += detourPen;
          // Pickups are at the registered source point → 0 km from source.
          final pickupStop = p.stops.firstWhere(
            (s) => s.kind == StopKind.pickup && s.employeeIds.contains(id),
          );
          final prox = GeoRules.straightKm(
            input.locations[e.pickupLocationId]!,
            input.locations[pickupStop.locationId]!,
          );
          proximity += (prox / 2).clamp(0.0, 1.0);
          // Employee soft preferences (importance-weighted).
          if (e.hasTravelPreferences) {
            final metrics = <String, double>{
              TravelPreferenceKeys.travelTime: (ride.minutes / maxRide).clamp(
                0,
                1,
              ),
              TravelPreferenceKeys.distance: (ride.km / maxRideKm).clamp(0, 1),
              TravelPreferenceKeys.detour: detourPen,
              TravelPreferenceKeys.reliability: ride.slack >= buf + tol
                  ? 0
                  : ((buf + tol - ride.slack) / (buf + tol)).clamp(0, 1),
            };
            var num = 0.0, den = 0.0;
            for (final k in TravelPreferenceKeys.active) {
              final lvl = e.preference(k).toDouble();
              num += lvl * metrics[k]!;
              den += lvl;
            }
            if (den > 0) {
              prefPen += num / den;
              prefCount++;
            }
          }
        }
      }
      cand.punctualityPenalty = count == 0 ? 0 : pen / count;
      cand.detourPenalty = count == 0 ? 0 : detour / count;
      cand.proximityPenalty = count == 0 ? 0 : proximity / count;
      cand.employeePrefPenalty = prefCount == 0 ? 0 : prefPen / prefCount;
      final seats = cand.plans.fold<int>(0, (s, p) => s + p.passengerCapacity);
      final riders = cand.plans.fold<int>(
        0,
        (s, p) => s + p.employeeIds.length,
      );
      cand.utilizationPenalty = seats == 0 ? 1 : 1 - riders / seats;
      final evCount = cand.plans
          .where((p) => vehicleById[p.vehicleId]!.isEv)
          .length;
      cand.evShare = cand.plans.isEmpty ? 0 : 100 * evCount / cand.plans.length;
      cand.evPenalty = target <= 0
          ? 0
          : (math.max(0, target - cand.evShare) / target);
      var mismatches = 0, checks = 0;
      for (final p in cand.plans) {
        final v = vehicleById[p.vehicleId]!;
        checks++;
        if (v.luxuryClass.index < input.employer.luxuryPreference.index) {
          mismatches++;
        }
        checks++;
        if (input.employer.vehicleTypePreferences.isNotEmpty &&
            !input.employer.vehicleTypePreferences.contains(v.type)) {
          mismatches++;
        }
        for (final id in p.employeeIds) {
          final pref = empById[id]!.transportPreference;
          if (pref == TransportPreference.evPreferred) {
            checks++;
            if (!v.isEv) mismatches++;
          } else if (pref == TransportPreference.sedanPreferred) {
            checks++;
            if (v.type != VehicleType.sedan) mismatches++;
          }
        }
      }
      cand.preferencePenalty = checks == 0 ? 0 : mismatches / checks;
      var safety = 0.0;
      for (final p in cand.plans) {
        final v = vehicleById[p.vehicleId]!;
        final validity = Duration(
          hours: _param(c, 'inspection_validity_h').round(),
        );
        if (v.lastInspectionAt == null ||
            day.difference(v.lastInspectionAt!).abs() > validity * 4) {
          safety += 0.5;
        }
      }
      cand.safetyPenalty = cand.plans.isEmpty
          ? 0
          : (safety / cand.plans.length).clamp(0, 1);
      final guardVehiclesUnneeded = cand.plans
          .where(
            (p) =>
                !guardRequired &&
                vehicleById[p.vehicleId]!.requiresSecurityGuard,
          )
          .length;
      cand.guardPenalty = cand.plans.isEmpty
          ? 0
          : guardVehiclesUnneeded / cand.plans.length;
    }

    double norm(double x, double min, double max) =>
        max - min < 1e-9 ? 0 : (x - min) / (max - min);
    final minCost = cands.map((e) => e.cost).reduce(math.min),
        maxCost = cands.map((e) => e.cost).reduce(math.max);
    final minKm = cands.map((e) => e.km).reduce(math.min),
        maxKm = cands.map((e) => e.km).reduce(math.max);
    final minMin = cands.map((e) => e.minutes).reduce(math.min),
        maxMin = cands.map((e) => e.minutes).reduce(math.max);
    final w = c.weights;
    final wSum = w.values.fold<double>(0, (a, b) => a + b);
    final anyPrefs = input.employees.any((e) => e.hasTravelPreferences);
    for (final cand in cands) {
      final comps = <ScoreComponent>[
        ScoreComponent(
          key: 'cost',
          label: 'Operating cost',
          weight: w['cost']!,
          normalizedPenalty: norm(cand.cost, minCost, maxCost),
          detail:
              '₹${cand.cost.toStringAsFixed(0)} (range ₹${minCost.toStringAsFixed(0)}–₹${maxCost.toStringAsFixed(0)} across alternatives)',
        ),
        ScoreComponent(
          key: 'punctuality',
          label: 'Arrival reliability',
          weight: w['punctuality']!,
          normalizedPenalty: cand.punctualityPenalty,
          detail:
              'Average buffer shortfall/early-arrival penalty ${(cand.punctualityPenalty * 100).toStringAsFixed(0)}%',
        ),
        ScoreComponent(
          key: 'distance',
          label: 'Travel distance',
          weight: w['distance']!,
          normalizedPenalty: norm(cand.km, minKm, maxKm),
          detail: '${cand.km.toStringAsFixed(1)} km total',
        ),
        ScoreComponent(
          key: 'travelTime',
          label: 'Travel time',
          weight: w['travelTime']!,
          normalizedPenalty: norm(cand.minutes, minMin, maxMin),
          detail: '${cand.minutes.toStringAsFixed(0)} vehicle-minutes',
        ),
        ScoreComponent(
          key: 'detour',
          label: 'Employee detour',
          weight: w['detour']!,
          normalizedPenalty: cand.detourPenalty,
          detail:
              'Average extra ride vs direct trip ${(cand.detourPenalty * 100).toStringAsFixed(0)}%',
        ),
        ScoreComponent(
          key: 'proximity',
          label: 'Pickup-point proximity',
          weight: w['proximity']!,
          normalizedPenalty: cand.proximityPenalty,
          detail: cand.proximityPenalty == 0
              ? 'All pickups at employees\' registered source points (0 km)'
              : 'Average pickup distance from source',
        ),
        ScoreComponent(
          key: 'utilization',
          label: 'Vehicle utilization',
          weight: w['utilization']!,
          normalizedPenalty: cand.utilizationPenalty,
          detail:
              '${((1 - cand.utilizationPenalty) * 100).toStringAsFixed(0)}% of seats used',
        ),
        ScoreComponent(
          key: 'ev',
          label: 'EV preference',
          weight: w['ev']!,
          normalizedPenalty: cand.evPenalty,
          detail:
              '${cand.evShare.toStringAsFixed(0)}% EV vs ${target.toStringAsFixed(0)}% target',
        ),
        ScoreComponent(
          key: 'customerPreference',
          label: 'Customer/employer preference',
          weight: w['customerPreference']!,
          normalizedPenalty: cand.preferencePenalty,
          detail:
              '${(cand.preferencePenalty * 100).toStringAsFixed(0)}% of preference checks unmet',
        ),
        ScoreComponent(
          key: 'employeePreference',
          label: 'Employee travel preferences',
          weight: w['employeePreference']!,
          normalizedPenalty: cand.employeePrefPenalty,
          detail: anyPrefs
              ? 'Importance-weighted penalty ${(cand.employeePrefPenalty * 100).toStringAsFixed(0)}% for employees with saved preferences'
              : 'No saved employee preferences in this selection',
        ),
        ScoreComponent(
          key: 'safety',
          label: 'Safety (soft)',
          weight: w['safety']!,
          normalizedPenalty: cand.safetyPenalty,
          detail:
              'Hard safety rules already enforced; penalty only for stale inspections',
        ),
        ScoreComponent(
          key: 'guard',
          label: 'Guard requirement',
          weight: w['guard']!,
          normalizedPenalty: cand.guardPenalty,
          detail: guardRequired
              ? 'Guard seat reserved per policy'
              : 'No guard seats spent unnecessarily',
        ),
      ];
      final weighted = comps.fold<double>(
        0,
        (s, x) => s + x.weight * x.normalizedPenalty,
      );
      cand.score = wSum <= 0 ? 100 : 100 * (1 - weighted / wSum);
      cand.breakdown = comps;
    }
  }

  double _scoreWithout(_Candidate cand, OptimizationConfig c, String key) {
    final comps = cand.breakdown.where((x) => x.key != key);
    final wSum = comps.fold<double>(0, (s, x) => s + x.weight);
    final weighted = comps.fold<double>(
      0,
      (s, x) => s + x.weight * x.normalizedPenalty,
    );
    return wSum <= 0 ? 100 : 100 * (1 - weighted / wSum);
  }

  List<String> _preferenceSummary(
    OptimizationInput input,
    _Candidate b,
    List<Employee> employees,
  ) {
    final day = _day(input.serviceDate);
    final emp = {for (final e in employees) e.id: e};
    final out = <String>[];
    for (final p in b.plans) {
      final rides = _rides(p, input, day, emp);
      for (final id in p.employeeIds) {
        final e = emp[id]!;
        if (!e.hasTravelPreferences) continue;
        final r = rides[id];
        if (r == null) continue;
        final prefs = TravelPreferenceKeys.active
            .where((k) => e.preference(k) > 0)
            .map(
              (k) =>
                  '${TravelPreferenceKeys.label(k).toLowerCase()} (${TravelPreferenceKeys.levels[e.preference(k)].toLowerCase()})',
            )
            .join(', ');
        out.add(
          '${e.employeeCode} prefers $prefs → in Vehicle ${_vc(input, p.vehicleId)}: ride ${r.minutes} min, '
          '${r.km.toStringAsFixed(1)} km, detour ${((r.detourRatio - 1) * 100).clamp(0, 999).toStringAsFixed(0)}%, '
          'arrives ${r.slack} min before deadline (±${e.toleranceMinutes(input.employer)} min tolerance).',
        );
      }
    }
    if (out.isEmpty) {
      out.add('No employee in this selection has saved travel preferences.');
    }
    out.add(
      'Preferences are soft: they never override capacity, guard, availability, contract or deadline constraints.',
    );
    return out;
  }

  List<String> _remedies(List<String> violations) {
    final text = violations.join(' ').toLowerCase();
    return [
      if (text.contains('capacity'))
        'Add or enable a larger eligible vehicle (MPV/van), allow more vehicle types in the profile, or split the employees into separate requests.',
      if (text.contains('deadline'))
        'Allow an earlier departure, split distant employees into separate vehicles, or review the employees\' arrival times.',
      if (text.contains('no eligible vehicle') || text.contains('excluded'))
        'Return a vehicle from maintenance, extend fleet-company allocation windows, or free a conflicting assignment.',
      if (text.contains('contract'))
        'Renew/extend the company contract or increase its agreed car count (or mark the limit as soft).',
      if (text.contains('guard'))
        'Assign a security guard to a vehicle or increase the guards available for this run.',
      if (text.contains('cannot share') || text.contains('pooling'))
        'Run the employees separately, or relax pooling limits (arrival window, detour, destination gap) in the parameter catalog.',
      if (text.contains('inactive') || text.contains('already scheduled'))
        'Remove inactive or already-scheduled employees from the selection.',
      if (text.contains('driver'))
        'Bring a licensed driver on duty or add a driver allocation for this company and window.',
    ].ifEmptyList([
      'Review the failed constraints above; no automatic fix is available.',
    ]);
  }

  static List<List<String>> _permutations(List<String> items) {
    if (items.length <= 1) return [items];
    final out = <List<String>>[];
    for (var i = 0; i < items.length; i++) {
      final rest = [...items]..removeAt(i);
      for (final p in _permutations(rest)) {
        out.add([items[i], ...p]);
      }
    }
    return out;
  }

  String _planSummary(OptimizationInput i, List<VehiclePlan> plans) => plans
      .map(
        (p) =>
            'Vehicle ${_vc(i, p.vehicleId)} [${p.employeeIds.map((id) => _ec(i, id)).join(', ')}]',
      )
      .join(' + ');

  String _inputSummary(OptimizationInput i) =>
      '${i.employees.length} employee${i.employees.length == 1 ? '' : 's'} (${i.employees.map((e) => e.employeeCode).take(8).join(', ')}${i.employees.length > 8 ? '…' : ''}), '
      '${i.vehicles.length} candidate vehicle${i.vehicles.length == 1 ? '' : 's'}, profile "${i.config.name}", '
      'allowed types: ${i.config.allowedVehicleTypes.isEmpty ? 'any' : i.config.allowedVehicleTypes.map((t) => t.label).join('/')}, '
      'max arrival ${_hm(math.min(i.config.maximumArrivalMinutes, i.employer.maximumArrivalMinutes))}'
      '${i.startParkingId != null ? ', start point ${i.startParkingId}' : ''}'
      '${i.guardRequired ? ', guard required (${i.guardsAvailable} in pool)' : ''}.';

  String _vc(OptimizationInput i, String id) =>
      i.vehicles
          .where((v) => v.id == id)
          .map((v) => v.vehicleCode)
          .firstOrNull ??
      id;
  String _ec(OptimizationInput i, String id) =>
      i.employees
          .where((e) => e.id == id)
          .map((e) => e.employeeCode)
          .firstOrNull ??
      id;

  static String _hm(int m) {
    final h = m ~/ 60, mm = m % 60;
    final ap = h >= 12 ? 'PM' : 'AM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${mm.toString().padLeft(2, '0')} $ap';
  }

  static String _t(DateTime d) => _hm(d.hour * 60 + d.minute);
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

extension on List<String> {
  List<String> ifEmptyList(List<String> other) => isEmpty ? other : this;
}
