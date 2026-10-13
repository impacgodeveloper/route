import 'dart:math' as math;

import '../../core/demo/clock.dart';
import '../../core/demo/demo_labels.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/result.dart';
import '../models/models.dart';
import '../rules/geo_rules.dart';
import '../rules/parameter_catalog.dart';
import '../rules/tolerance_rules.dart';
import 'service_context.dart';

/// Future integration point for a live traffic API (e.g. Google Maps).
/// This prototype ships only [SimulatedTrafficProvider]; nothing is ever
/// presented as live.
abstract interface class TrafficProvider {
  String get providerLabel;
  bool get isLive;
  TrafficState current();
}

class SimulatedTrafficProvider implements TrafficProvider {
  SimulatedTrafficProvider(this.ctx);
  final ServiceContext ctx;

  @override
  String get providerLabel => DemoLabels.trafficSimulated;
  @override
  bool get isLive => false;
  @override
  TrafficState current() => ctx.view.traffic;
}

/// Computed traffic status of one trip (for the traffic/movement board).
class TrafficTripStatus {
  const TrafficTripStatus({
    required this.trip,
    required this.stops,
    required this.plannedFinal,
    required this.estimatedFinal,
    required this.delayMinutes,
    required this.affectedStopIds,
    required this.feasible,
    required this.violations,
    required this.recommendation,
    required this.earlierDepartureMinutes,
    required this.proposedDeparture,
    required this.proposedTimes,
    required this.outsideToleranceEmployeeIds,
    required this.lastUpdate,
    required this.available,
  });

  final Trip trip;
  final List<RouteStop> stops;
  final DateTime plannedFinal;
  final DateTime estimatedFinal;
  final int delayMinutes;
  final List<String> affectedStopIds;
  final bool feasible;
  final List<String> violations;
  final String recommendation;

  /// > 0 when leaving earlier is recommended (not-started trips only).
  final int earlierDepartureMinutes;
  final DateTime proposedDeparture;

  /// stopId → proposed time (locked stops keep their planned/actual time).
  final Map<String, DateTime> proposedTimes;
  final List<String> outsideToleranceEmployeeIds;
  final DateTime lastUpdate;

  /// False when traffic data is unavailable (planned schedule shown).
  final bool available;

  bool get started => trip.actualStart != null;
  RouteStop? get nextStop => stops.where((s) => !s.isDone).firstOrNull;
  bool get recalculationRecommended =>
      available &&
      (delayMinutes.abs() >= 3 || !feasible || earlierDepartureMinutes > 0);
  String get statusLabel => !available
      ? 'No traffic data'
      : !feasible
      ? 'Deadline at risk'
      : delayMinutes >= 3
      ? 'Delayed ~$delayMinutes min'
      : earlierDepartureMinutes > 0
      ? 'Leave $earlierDepartureMinutes min earlier'
      : 'On schedule';
}

/// Traffic movement, schedule recalculation and route revisions.
class TrafficService {
  TrafficService(this.ctx) : provider = SimulatedTrafficProvider(ctx);
  final ServiceContext ctx;
  final TrafficProvider provider;

  int _param(String key) {
    final cfg = ctx.db.optimizationConfigs.values.firstOrNull;
    final def = ParameterCatalog.byKey(key)?.defaultValue ?? 0;
    return (cfg == null ? def : ParameterCatalog.value(cfg, key)).round();
  }

  /// Trips affected by current traffic: today, assigned, not finished.
  List<Trip> candidateTrips() =>
      ctx.db.trips.values
          .where(
            (t) =>
                sameDay(t.serviceDate, ctx.now) &&
                t.isAssigned &&
                !t.status.isTerminal &&
                t.routeId != null,
          )
          .toList()
        ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));

  List<TrafficTripStatus> board() => [
    for (final t in candidateTrips()) statusOf(t),
  ];

  TrafficTripStatus statusOf(Trip trip, {TrafficState? traffic}) {
    final state = traffic ?? provider.current();
    final view = ctx.view;
    final stops = view.trips.stopsOf(trip);
    final route = view.trips.routeOf(trip);
    final variant = route?.variant ?? RouteVariant.internalRoads;
    final factor = state.factorFor(variant);
    final locs = view.locationMap;
    final employer = view.employer(trip.employerId);
    final plannedFinal = stops.isEmpty
        ? trip.scheduledStart
        : stops.last.plannedArrival;
    if (!state.available || stops.isEmpty) {
      return TrafficTripStatus(
        trip: trip,
        stops: stops,
        plannedFinal: plannedFinal,
        estimatedFinal: plannedFinal,
        delayMinutes: 0,
        affectedStopIds: const [],
        feasible: true,
        violations: const [],
        recommendation: state.available
            ? 'No stops to evaluate.'
            : 'Traffic data unavailable — showing the planned schedule only.',
        earlierDepartureMinutes: 0,
        proposedDeparture: trip.scheduledStart,
        proposedTimes: {
          for (final s in stops) s.id: s.actualArrival ?? s.plannedArrival,
        },
        outsideToleranceEmployeeIds: const [],
        lastUpdate: state.updatedAt,
        available: state.available,
      );
    }
    final boarding = GeoRules.boardingMinutesPerStop;

    // Times for stops[fromIndex..] given the time at stops[fromIndex].
    Map<String, DateTime> timesFrom(int fromIndex, DateTime anchor) {
      final out = <String, DateTime>{stops[fromIndex].id: anchor};
      var t = anchor;
      for (var i = fromIndex + 1; i < stops.length; i++) {
        final leg = GeoRules.roadKm(
          locs[stops[i - 1].locationId]!,
          locs[stops[i].locationId]!,
          variant,
        );
        t = t.add(
          Duration(
            minutes:
                GeoRules.travelMinutes(
                  leg,
                  variant,
                  t,
                  scenarioFactor: factor,
                ) +
                boarding,
          ),
        );
        out[stops[i].id] = t;
      }
      return out;
    }

    final lockedCount =
        stops.lastIndexWhere(
          (s) => s.isDone || s.status == StopStatus.arrived,
        ) +
        1;
    final proposed = <String, DateTime>{};
    for (var i = 0; i < lockedCount; i++) {
      proposed[stops[i].id] = stops[i].actualArrival ?? stops[i].plannedArrival;
    }
    var earlier = 0;
    Map<String, DateTime>? asPlannedTimes;
    DateTime proposedDeparture = trip.scheduledStart;

    if (trip.actualStart == null) {
      // Not started: re-time the whole route from the scheduled departure.
      final buffer = _param('arrival_buffer_min');
      int latenessFor(Map<String, DateTime> times) {
        var worst = -1 << 30;
        for (final s in stops.where((s) => s.kind == StopKind.drop)) {
          final deadline = _dropDeadline(s, trip, employer);
          worst = math.max(
            worst,
            times[s.id]!
                .difference(deadline.subtract(Duration(minutes: buffer)))
                .inMinutes,
          );
        }
        return worst;
      }

      asPlannedTimes = timesFrom(0, trip.scheduledStart);
      var times = asPlannedTimes;
      var dep = trip.scheduledStart;
      // Iterate: travel time depends on time of day (peak factors), so the
      // departure is re-timed after each move (never later than scheduled).
      for (var i = 0; i < 8; i++) {
        final late = latenessFor(times);
        if (late > 0) {
          dep = dep.subtract(Duration(minutes: late));
        } else if (late < -1 && dep.isBefore(trip.scheduledStart)) {
          final later = dep.add(Duration(minutes: -late - 1));
          dep = later.isAfter(trip.scheduledStart)
              ? trip.scheduledStart
              : later;
        } else {
          break;
        }
        times = timesFrom(0, dep);
      }
      // Safety: never leave a positive lateness.
      for (var i = 0; i < 12 && latenessFor(times) > 0; i++) {
        dep = dep.subtract(const Duration(minutes: 1));
        times = timesFrom(0, dep);
      }
      earlier = trip.scheduledStart.difference(dep).inMinutes;
      proposedDeparture = dep;
      proposed.addAll(times);
    } else {
      // Active: re-time remaining stops from the last completed/arrived stop.
      final anchorIdx = math.max(0, lockedCount - 1);
      final anchorStop = stops[anchorIdx];
      final anchor = lockedCount == 0
          ? (trip.actualStart!.isAfter(anchorStop.plannedArrival)
                ? trip.actualStart!
                : anchorStop.plannedArrival)
          : (anchorStop.departedAt ??
                anchorStop.actualArrival ??
                anchorStop.plannedArrival);
      final times = timesFrom(anchorIdx, anchor);
      for (var i = lockedCount; i < stops.length; i++) {
        proposed[stops[i].id] = times[stops[i].id]!;
      }
    }

    final violations = <String>[];
    for (final s in stops.where((s) => s.kind == StopKind.drop)) {
      final deadline = _dropDeadline(s, trip, employer);
      final t = proposed[s.id]!;
      if (t.isAfter(deadline)) {
        violations.add(
          '${s.alightingEmployeeIds.join(', ')} would reach ${view.location(s.locationId)?.code} at ${Fmt.time(t)}, after the ${Fmt.time(deadline)} deadline.',
        );
      }
    }
    if (proposedDeparture.isBefore(
          ctx.now.subtract(const Duration(minutes: 1)),
        ) &&
        trip.actualStart == null &&
        earlier > 0) {
      violations.add(
        'Recommended departure ${Fmt.time(proposedDeparture)} has already passed.',
      );
    }
    final estimatedFinal = proposed[stops.last.id]!;
    // Delay = expected lateness if the vehicle leaves as currently planned.
    final delay = (asPlannedTimes?[stops.last.id] ?? estimatedFinal)
        .difference(plannedFinal)
        .inMinutes;
    final affected = <String>[
      for (var i = lockedCount; i < stops.length; i++)
        if (proposed[stops[i].id]!
                .difference(stops[i].plannedArrival)
                .inMinutes
                .abs() >=
            2)
          stops[i].id,
    ];
    final outside = <String>{};
    for (var i = lockedCount; i < stops.length; i++) {
      final s = stops[i];
      if (s.kind != StopKind.pickup) continue;
      final shift = proposed[s.id]!
          .difference(s.plannedArrival)
          .inMinutes
          .abs();
      for (final eid in s.boardingEmployeeIds) {
        final e = view.employee(eid);
        if (e != null && shift > e.toleranceMinutes(employer)) outside.add(eid);
      }
    }
    final otherVariant = variant == RouteVariant.ringRoad
        ? RouteVariant.internalRoads
        : RouteVariant.ringRoad;
    String recommendation;
    if (violations.isNotEmpty) {
      recommendation =
          'Deadline at risk — consider reassignment, an earlier departure on future runs, or the ${otherVariant.label.toLowerCase()} (${state.factorFor(otherVariant) < factor ? 'currently lighter traffic' : 'check conditions'}).';
    } else if (earlier > 0) {
      recommendation =
          'Depart $earlier min earlier (${Fmt.time(proposedDeparture)}) to keep every drop within its deadline and buffer.';
    } else if (delay >= 3) {
      recommendation =
          'Expect ~$delay min delay; all office deadlines are still met.';
    } else {
      recommendation = 'No change needed.';
    }
    return TrafficTripStatus(
      trip: trip,
      stops: stops,
      plannedFinal: plannedFinal,
      estimatedFinal: estimatedFinal,
      delayMinutes: delay,
      affectedStopIds: affected,
      feasible: violations.isEmpty,
      violations: violations,
      recommendation: recommendation,
      earlierDepartureMinutes: earlier,
      proposedDeparture: proposedDeparture,
      proposedTimes: proposed,
      outsideToleranceEmployeeIds: outside.toList()..sort(),
      lastUpdate: state.updatedAt,
      available: true,
    );
  }

  DateTime _dropDeadline(RouteStop s, Trip trip, Employer? employer) {
    final view = ctx.view;
    var m = 1439;
    for (final eid in s.alightingEmployeeIds) {
      final e = view.employee(eid);
      if (e != null) m = math.min(m, e.arrivalDeadlineMinutes);
    }
    if (employer != null) m = math.min(m, employer.maximumArrivalMinutes);
    return atMinutes(trip.serviceDate, m);
  }

  /// Changes the simulated traffic scenario and proposes route revisions
  /// for affected trips. Same scenario twice → no duplicate revisions or
  /// alerts.
  Future<Result<List<RouteRevision>>> setScenario({
    required TrafficLevel internalRoads,
    required TrafficLevel ringRoad,
    TrafficSource source = TrafficSource.simulated,
    String note = '',
    Actor actor = Actor.fleetManager,
  }) {
    return ctx.run((tx) {
      final db = ctx.db;
      final prev = ctx.view.traffic;
      final next = TrafficState(
        internalRoads: internalRoads,
        ringRoad: ringRoad,
        source: source,
        updatedAt: ctx.now,
        note: note.trim(),
      );
      tx.put(db.trafficStates, next);
      final changed = prev.key != next.key;
      ctx.audit(
        tx,
        actor,
        'traffic.scenario',
        'traffic',
        'current',
        'Traffic set to: ${next.label}.',
        changes: 'scenario: ${prev.label} → ${next.label}',
        simulated: true,
      );
      if (!next.available) {
        if (changed) {
          ctx.notify(
            tx,
            role: UserRole.fleetManager,
            title: 'Traffic data unavailable (demo)',
            body:
                'Views show the planned schedule only. No recalculation was performed.',
            category: NotificationCategory.routeChange,
            entityType: 'traffic',
            entityId: 'current',
          );
        }
        return <RouteRevision>[];
      }
      final created = <RouteRevision>[];
      for (final trip in candidateTrips()) {
        final open = db.routeRevisions.values
            .where(
              (r) => r.tripId == trip.id && r.status == RevisionStatus.proposed,
            )
            .toList();
        // Dedupe: identical condition already proposed → nothing new.
        if (open.any((r) => r.scenarioKey == next.key)) continue;
        final status = statusOf(trip, traffic: next);
        for (final r in open) {
          tx.put(
            db.routeRevisions,
            r.copyWith(status: RevisionStatus.superseded),
          );
        }
        if (!status.recalculationRecommended) continue;
        final id = tx.newId(db.routeRevisions, 'RV-');
        final rev = RouteRevision(
          id: id,
          tripId: trip.id,
          createdAt: ctx.now,
          scenarioKey: next.key,
          scenarioLabel: next.label,
          reason: 'Simulated traffic change: ${next.label}.',
          stops: [
            for (final s in status.stops)
              RevisionStop(
                stopId: s.id,
                locationId: s.locationId,
                previous: s.actualArrival ?? s.plannedArrival,
                proposed: status.proposedTimes[s.id]!,
                locked: s.isDone || s.status == StopStatus.arrived,
                employeeIds: s.kind == StopKind.pickup
                    ? s.boardingEmployeeIds
                    : s.alightingEmployeeIds,
              ),
          ],
          previousDeparture: trip.actualStart ?? trip.scheduledStart,
          proposedDeparture: status.proposedDeparture,
          delayMinutes: status.delayMinutes,
          feasible: status.feasible,
          status: RevisionStatus.proposed,
          violations: status.violations,
          outsideToleranceEmployeeIds: status.outsideToleranceEmployeeIds,
          recommendation: status.recommendation,
        );
        tx.insert(db.routeRevisions, rev);
        created.add(rev);
        // Alerts (deduplicated by the scenario key check above).
        final summary = status.earlierDepartureMinutes > 0
            ? 'Recommended departure ${Fmt.time(status.proposedDeparture)} (${status.earlierDepartureMinutes} min earlier).'
            : status.delayMinutes >= 3
            ? 'Possible delay ~${status.delayMinutes} min.'
            : 'Schedule under review.';
        if (trip.assignedDriverId != null) {
          ctx.notify(
            tx,
            role: UserRole.driver,
            recipientId: trip.assignedDriverId,
            title: 'Traffic alert on ${trip.tripCode} (simulated)',
            body:
                '$summary ${status.feasible ? '' : 'Deadline at risk. '}Awaiting Fleet Manager decision.',
            category: NotificationCategory.delay,
            entityType: 'trip',
            entityId: trip.id,
          );
        }
        if (trip.actualStart != null || status.delayMinutes >= 3) {
          ctx.notifyEmployees(
            tx,
            trip.employeeIds,
            'Traffic update for ${trip.tripCode} (simulated)',
            '$summary You will be notified if your pickup time changes.',
            NotificationCategory.delay,
            entityType: 'trip',
            entityId: trip.id,
          );
        }
        ctx.audit(
          tx,
          actor,
          'route.revision.proposed',
          'trip',
          trip.id,
          'Proposed schedule revision $id for ${trip.tripCode}: ${status.recommendation}',
          related: {'revision': id},
          simulated: true,
        );
      }
      if (created.isNotEmpty) {
        ctx.notify(
          tx,
          role: UserRole.fleetManager,
          title: 'Traffic: ${created.length} trip(s) need review (simulated)',
          body: next.label,
          category: NotificationCategory.routeChange,
          entityType: 'traffic',
          entityId: 'current',
        );
        ctx.notify(
          tx,
          role: UserRole.employerAdmin,
          title: 'Traffic affecting ${created.length} trip(s) (simulated)',
          body: 'The Fleet Manager is reviewing schedule changes.',
          category: NotificationCategory.routeChange,
          entityType: 'traffic',
          entityId: 'current',
        );
      }
      return created;
    }, info: 'Traffic scenario updated (simulated)');
  }

  /// Applies a proposed revision. Completed/arrived stops are never changed;
  /// if the trip progressed since the proposal, the revision is refused.
  Future<Result<Trip>> applyRevision(
    String revisionId, {
    Actor actor = Actor.fleetManager,
  }) {
    return ctx.run((tx) {
      final db = ctx.db;
      final rev = db.routeRevisions[revisionId];
      if (rev == null) throw ValidationFailure(['Revision not found.']);
      if (rev.status != RevisionStatus.proposed) {
        throw ValidationFailure([
          'Revision is ${rev.status.label.toLowerCase()}.',
        ]);
      }
      final trip = db.trips[rev.tripId];
      if (trip == null || trip.status.isTerminal) {
        throw ValidationFailure(['Trip is no longer active.']);
      }
      final changesOut = <String>[];
      final notified = <String>{};
      final employer = db.employers[trip.employerId];
      for (final rs in rev.stops) {
        final stop = db.routeStops[rs.stopId];
        if (stop == null) continue;
        final nowLocked = stop.isDone || stop.status == StopStatus.arrived;
        if (nowLocked) {
          if (!rs.locked) {
            throw ValidationFailure([
              'Stop ${stop.sequence} progressed since this proposal — recalculate before applying.',
            ]);
          }
          continue;
        }
        if (rs.proposed == stop.plannedArrival) continue;
        tx.put(db.routeStops, stop.copyWith(plannedArrival: rs.proposed));
        changesOut.add(
          'stop ${stop.sequence} ${Fmt.time(stop.plannedArrival)} → ${Fmt.time(rs.proposed)}',
        );
        if (stop.kind == StopKind.pickup) {
          for (final eid in stop.boardingEmployeeIds) {
            final e = db.employees[eid];
            final tol = e?.toleranceMinutes(employer) ?? 7;
            final outside = !ToleranceRules.within(
              rs.proposed,
              stop.plannedArrival,
              tol,
            );
            ctx.notify(
              tx,
              role: UserRole.employee,
              recipientId: eid,
              title: 'Pickup time changed: ${trip.tripCode}',
              body:
                  'New pickup ${Fmt.time(rs.proposed)} (was ${Fmt.time(stop.plannedArrival)})${outside ? ' — outside your ±$tol min window' : ''}. Reason: simulated traffic.',
              category: NotificationCategory.routeChange,
              entityType: 'trip',
              entityId: trip.id,
            );
            notified.add(eid);
          }
        }
      }
      final remaining = trip.employeeIds.where((e) => !notified.contains(e));
      ctx.notifyEmployees(
        tx,
        remaining,
        'Schedule updated: ${trip.tripCode}',
        rev.delayMinutes >= 3
            ? 'Expected arrival ~${rev.delayMinutes} min later (simulated traffic).'
            : 'Drop times adjusted for traffic (simulated).',
        NotificationCategory.routeChange,
        entityType: 'trip',
        entityId: trip.id,
      );
      final lastProposed = rev.stops.last.proposed;
      var next = trip.copyWith(
        scheduledArrival: () => lastProposed,
        scheduledStart: trip.actualStart == null ? rev.proposedDeparture : null,
        updatedAt: ctx.now,
      );
      if (trip.actualStart != null &&
          rev.delayMinutes >= 3 &&
          trip.status == TripStatus.inProgress) {
        next = next.copyWith(
          status: TripStatus.delayed,
          delayReason: () => 'Traffic (simulated): ${rev.scenarioLabel}',
        );
      }
      tx.put(db.trips, next);
      final route = db.routes[trip.routeId];
      if (route != null) {
        tx.put(
          db.routes,
          route.copyWith(
            estimatedDurationMinutes: lastProposed
                .difference(next.actualStart ?? next.scheduledStart)
                .inMinutes,
          ),
        );
      }
      tx.put(
        db.routeRevisions,
        rev.copyWith(status: RevisionStatus.applied, appliedAt: () => ctx.now),
      );
      if (trip.assignedDriverId != null) {
        ctx.notify(
          tx,
          role: UserRole.driver,
          recipientId: trip.assignedDriverId,
          title: 'Schedule updated: ${trip.tripCode}',
          body: trip.actualStart == null
              ? 'Depart at ${Fmt.time(rev.proposedDeparture)}.'
              : 'Remaining stop times updated for traffic.',
          category: NotificationCategory.routeChange,
          entityType: 'trip',
          entityId: trip.id,
        );
      }
      ctx.audit(
        tx,
        actor,
        'route.revision.apply',
        'trip',
        trip.id,
        'Applied revision ${rev.id} to ${trip.tripCode}.',
        changes: changesOut.join('; '),
        related: {'revision': rev.id},
        simulated: true,
      );
      return next;
    }, info: 'Revision applied — affected users notified locally');
  }

  Future<Result<RouteRevision>> dismissRevision(
    String revisionId,
    String reason, {
    Actor actor = Actor.fleetManager,
  }) {
    if (reason.trim().length < 5) {
      return Future.value(Err.single('Give a reason (at least 5 characters).'));
    }
    return ctx.run((tx) {
      final rev = ctx.db.routeRevisions[revisionId];
      if (rev == null || rev.status != RevisionStatus.proposed) {
        throw ValidationFailure(['Revision is not open.']);
      }
      final next = rev.copyWith(status: RevisionStatus.dismissed);
      tx.put(ctx.db.routeRevisions, next);
      ctx.audit(
        tx,
        actor,
        'route.revision.dismiss',
        'trip',
        rev.tripId,
        'Dismissed revision ${rev.id}.',
        outcome: AuditOutcome.rejected,
        reason: reason.trim(),
        related: {'revision': rev.id},
        simulated: true,
      );
      return next;
    }, info: 'Revision dismissed');
  }
}
