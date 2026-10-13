import 'dart:math' as math;

import '../../core/demo/clock.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/result.dart';
import '../models/models.dart';
import '../rules/geo_rules.dart';
import '../rules/parameter_catalog.dart';
import '../rules/trip_state_machine.dart';
import 'assignment_service.dart';
import 'booking_service.dart';
import 'metrics_service.dart';
import 'service_context.dart';

/// Savings for one completed trip vs the single-occupancy baseline.
class TripSavings {
  const TripSavings({
    required this.trip,
    required this.riders,
    required this.actualKm,
    required this.distanceEstimated,
    required this.baselineKm,
    required this.actualVehicleMinutes,
    required this.baselineVehicleMinutes,
    required this.actualCo2Kg,
    required this.baselineCo2Kg,
    required this.actualCost,
    required this.baselineCost,
  });

  final Trip trip;
  final int riders;
  final double actualKm;

  /// True when no recorded distance existed and the route estimate was used.
  final bool distanceEstimated;
  final double baselineKm;
  final double actualVehicleMinutes;
  final double baselineVehicleMinutes;
  final double actualCo2Kg;
  final double baselineCo2Kg;
  final double actualCost;
  final double baselineCost;

  double get co2SavedKg => baselineCo2Kg - actualCo2Kg;
  double get minutesSaved => baselineVehicleMinutes - actualVehicleMinutes;
  double get costSaved => baselineCost - actualCost;
}

class AnalyticsSummary {
  const AnalyticsSummary({
    required this.range,
    required this.trips,
    required this.policy,
  });
  final DateRange range;
  final List<TripSavings> trips;
  final FleetPolicy policy;

  double _sum(double Function(TripSavings) f) =>
      trips.fold(0.0, (s, t) => s + f(t));
  int get riders => trips.fold(0, (s, t) => s + t.riders);
  double get co2SavedKg => _sum((t) => t.co2SavedKg);
  double get baselineCo2Kg => _sum((t) => t.baselineCo2Kg);
  double get actualCo2Kg => _sum((t) => t.actualCo2Kg);
  double get minutesSaved => _sum((t) => t.minutesSaved);
  double get costSaved => _sum((t) => t.costSaved);
  double get baselineCost => _sum((t) => t.baselineCost);
  double get actualCost => _sum((t) => t.actualCost);
  double get vehicleKm => _sum((t) => t.actualKm);
  double get baselineKm => _sum((t) => t.baselineKm);
  int get estimatedDistanceTrips =>
      trips.where((t) => t.distanceEstimated).length;

  /// 1 carbon credit = 1 tonne CO2e avoided (indicative only).
  double get creditTonnes => math.max(0, co2SavedKg) / 1000;
  double get indicativeCreditValue =>
      creditTonnes * policy.carbonCreditPricePerTonne;
  double get co2ReductionPct =>
      baselineCo2Kg <= 0 ? 0 : 100 * co2SavedKg / baselineCo2Kg;

  List<DayValue> co2ByDay() => [
    for (var i = 0; i < range.days; i++)
      () {
        final d = dateOnly(range.start).add(Duration(days: i));
        return DayValue(
          d,
          trips
              .where((t) => sameDay(t.trip.serviceDate, d))
              .fold(0.0, (s, t) => s + t.co2SavedKg),
        );
      }(),
  ];
}

/// Employer analytics: time saved, emissions avoided and financial savings
/// from pooled, optimized routes — computed only from completed local trips.
///
/// Baseline (documented, editable in fleet policy): every rider would have
/// travelled alone, directly from pickup to drop, in a typical ICE car.
/// Carbon credits are INDICATIVE: real credits require eligibility checks,
/// verified measurement and certification (e.g. Verra / Gold Standard).
class AnalyticsService {
  AnalyticsService(this.ctx);
  final ServiceContext ctx;

  double _co2PerKm(Vehicle? v, OptimizationConfig? cfg) {
    double p(String k) => cfg == null
        ? ParameterCatalog.byKey(k)!.defaultValue
        : ParameterCatalog.value(cfg, k);
    return switch (v?.propulsion) {
      Propulsion.ev => p('ev_co2_g_per_km'),
      Propulsion.hybrid => (p('ev_co2_g_per_km') + p('ice_co2_g_per_km')) / 2,
      _ => p('ice_co2_g_per_km'),
    };
  }

  AnalyticsSummary summary(String employerId, DateRange range) {
    final view = ctx.view;
    final policy = view.policy;
    final cfg = view.optimizationConfigs.firstOrNull;
    final out = <TripSavings>[];
    for (final t in view.trips.all()) {
      if (t.employerId != employerId ||
          t.status != TripStatus.completed ||
          !range.contains(t.serviceDate)) {
        continue;
      }
      final riders = t.alightedPassengerIds.isEmpty
          ? t.boardedPassengerIds
          : t.alightedPassengerIds;
      if (riders.isEmpty) continue;
      final route = view.trips.routeOf(t);
      final actualKm = t.distanceKm ?? route?.estimatedDistanceKm ?? 0;
      var baselineKm = 0.0;
      for (final id in riders) {
        final e = view.employee(id);
        final a = view.location(e?.pickupLocationId),
            b = view.location(e?.destinationId);
        if (a != null && b != null) {
          baselineKm += GeoRules.roadKm(a, b, RouteVariant.internalRoads);
        }
      }
      final vehicle = view.vehicle(t.assignedVehicleId);
      final bill = view.billingForTrip(t.id);
      final actualMinutes =
          (t.actualDurationMinutes ?? t.estimatedDurationMinutes ?? 0)
              .toDouble();
      out.add(
        TripSavings(
          trip: t,
          riders: riders.length,
          actualKm: actualKm,
          distanceEstimated: t.distanceKm == null,
          baselineKm: baselineKm,
          actualVehicleMinutes: actualMinutes,
          baselineVehicleMinutes: baselineKm / policy.baselineSpeedKmh * 60,
          actualCo2Kg: actualKm * _co2PerKm(vehicle, cfg) / 1000,
          baselineCo2Kg: baselineKm * policy.baselineCo2GramsPerKm / 1000,
          actualCost:
              bill?.totalAmount ??
              actualKm * (view.employer(employerId)?.defaultDistanceRate ?? 0),
          baselineCost: baselineKm * policy.baselineCostPerKm,
        ),
      );
    }
    return AnalyticsSummary(range: range, trips: out, policy: policy);
  }
}

/// A candidate existing trip for an ad-hoc request.
class SeatMatch {
  const SeatMatch({
    required this.trip,
    required this.feasible,
    required this.reasons,
    required this.addedMinutes,
    required this.addedKm,
    required this.seatsAfter,
    required this.capacity,
  });

  final Trip trip;
  final bool feasible;
  final List<String> reasons;
  final int addedMinutes;
  final double addedKm;
  final int seatsAfter;
  final int capacity;
}

/// Dynamic cab booking & roster optimization:
/// * employees on a scheduled trip can report absence → seat released;
/// * ad-hoc requests are matched to free seats in existing routes (without
///   breaking any deadline, capacity, contract or guard rule);
/// * optional auto-match on submit (fleet policy).
class MatchingService {
  MatchingService(this.ctx, this.assignments, this.bookings);
  final ServiceContext ctx;
  final AssignmentService assignments;
  final BookingService bookings;

  /// Employee reports "not travelling" for a trip that has not started.
  Future<Result<Trip>> reportAbsence(
    String tripId,
    String employeeId,
    String reason, {
    Actor? actor,
  }) async {
    final t = ctx.db.trips[tripId];
    if (t == null) return Err.single('Trip not found.');
    if (!t.employeeIds.contains(employeeId)) {
      return Err.single('You are not on ${t.tripCode}.');
    }
    if (t.actualStart != null) {
      return Err.single(
        '${t.tripCode} has already started — ask the driver to mark a no-show.',
      );
    }
    if (t.status.isTerminal) {
      return Err.single('${t.tripCode} is ${t.status.label.toLowerCase()}.');
    }
    final who = actor ?? Actor.employee(employeeId);
    final remaining = t.employeeIds.where((e) => e != employeeId).toList();
    if (remaining.isEmpty) {
      final r = await assignments.cancelTrip(
        tripId,
        'Only passenger ${ctx.db.employees[employeeId]?.employeeCode} reported absence: ${reason.trim()}',
        actor: who,
      );
      if (!r.isOk) return r;
      await ctx.run((tx) {
        final c = ctx.db.trips[tripId]!;
        tx.put(
          ctx.db.trips,
          c.copyWith(absentEmployeeIds: [...c.absentEmployeeIds, employeeId]),
        );
      });
      return Ok(
        ctx.db.trips[tripId]!,
        info: 'Absence recorded — trip cancelled (no other passengers)',
      );
    }
    final r = await ctx.run((tx) {
      final updated = assignments.commitInTx(
        tx,
        AssignmentRequest(
          tripId: t.id,
          employerId: t.employerId,
          serviceDate: t.serviceDate,
          employeeIds: remaining,
          driverId: t.assignedDriverId,
          vehicleId: t.assignedVehicleId,
          guardRequired: t.guardRequired,
          guardReference: t.guardReference,
          instructions: t.instructions,
        ),
        who,
      );
      final next = updated.copyWith(
        absentEmployeeIds: [...updated.absentEmployeeIds, employeeId],
      );
      tx.put(ctx.db.trips, next);
      for (final b
          in ctx.db.bookings
              .where((b) => b.tripId == t.id && b.employeeId == employeeId)
              .toList()) {
        tx.put(
          ctx.db.bookings,
          b.copyWith(
            status: BookingStatus.cancelled,
            decisionReason: () => 'Employee reported absence.',
            updatedAt: ctx.now,
          ),
        );
      }
      if (t.assignedDriverId != null) {
        ctx.notify(
          tx,
          role: UserRole.driver,
          recipientId: t.assignedDriverId,
          title:
              '${ctx.db.employees[employeeId]?.employeeCode} not travelling · ${t.tripCode}',
          body: 'Pickup removed; route re-timed. 1 seat now free.',
          category: NotificationCategory.routeChange,
          entityType: 'trip',
          entityId: t.id,
        );
      }
      ctx.notify(
        tx,
        role: UserRole.fleetManager,
        title: 'Seat released on ${t.tripCode}',
        body:
            '${ctx.db.employees[employeeId]?.employeeCode} reported absence: ${reason.trim()}. Seat available for ad-hoc matching.',
        category: NotificationCategory.bookingUpdate,
        entityType: 'trip',
        entityId: t.id,
      );
      ctx.audit(
        tx,
        who,
        'trip.absence',
        'trip',
        t.id,
        '${ctx.db.employees[employeeId]?.employeeCode} reported absence from ${t.tripCode}: ${reason.trim()}',
        related: {'employee': employeeId},
      );
      return next;
    }, info: 'Absence recorded — your seat was released');
    return r;
  }

  /// Existing same-day, not-started trips that could take the booking's
  /// employee. Feasibility uses the full assignment validator.
  List<SeatMatch> suggestions(String bookingId) {
    final b = ctx.db.bookings[bookingId];
    if (b == null) return const [];
    final policy = ctx.view.policy;
    final out = <SeatMatch>[];
    for (final t in ctx.db.trips.values) {
      if (!sameDay(t.serviceDate, b.requestedDate) ||
          t.actualStart != null ||
          !t.isAssigned) {
        continue;
      }
      if (!TripStateMachine.canAssign(t.status) ||
          t.status == TripStatus.needsAttention) {
        continue;
      }
      if (t.employeeIds.contains(b.employeeId)) continue;
      final v = ctx.db.vehicles[t.assignedVehicleId];
      if (v == null) continue;
      final emp = ctx.db.employees[b.employeeId];
      if (emp == null) continue;
      final request = AssignmentRequest(
        tripId: t.id,
        employerId: t.employerId,
        serviceDate: t.serviceDate,
        employeeIds: [...t.employeeIds, b.employeeId],
        driverId: t.assignedDriverId,
        vehicleId: t.assignedVehicleId,
        guardRequired: t.guardRequired,
        guardReference: t.guardReference,
        bookingIds: [b.id],
      );
      final val = assignments.validate(request);
      final cap = val.seats?.passengerCapacity ?? 0;
      final before = t.estimatedDurationMinutes ?? 0;
      final added = (val.plan?.durationMinutes ?? before) - before;
      final routeKm = ctx.view.trips.routeOf(t)?.estimatedDistanceKm ?? 0;
      final addedKm = (val.plan?.distanceKm ?? routeKm) - routeKm;
      final reasons = <String>[...val.errors];
      if (val.errors.isEmpty && added > policy.maxAddedDetourMinutes) {
        reasons.add(
          'Adds $added min to the route (policy max ${policy.maxAddedDetourMinutes} min).',
        );
      }
      out.add(
        SeatMatch(
          trip: t,
          feasible: reasons.isEmpty,
          reasons: reasons,
          addedMinutes: added,
          addedKm: double.parse(addedKm.toStringAsFixed(1)),
          seatsAfter: t.employeeIds.length + 1,
          capacity: cap,
        ),
      );
    }
    out.sort((a, b) {
      if (a.feasible != b.feasible) return a.feasible ? -1 : 1;
      final c = a.addedMinutes.compareTo(b.addedMinutes);
      return c != 0 ? c : a.addedKm.compareTo(b.addedKm);
    });
    return out;
  }

  /// Assigns the booking to the best feasible existing trip.
  Future<Result<Trip>> matchBest(
    String bookingId, {
    Actor actor = Actor.fleetManager,
  }) async {
    final best = suggestions(bookingId).where((s) => s.feasible).firstOrNull;
    if (best == null) {
      return Err.single(
        'No existing trip has a feasible free seat for this request.',
      );
    }
    final r = await bookings.assignToTrip(
      bookingId,
      best.trip.id,
      actor: actor,
    );
    if (r.isOk) {
      await ctx.run(
        (tx) => ctx.audit(
          tx,
          actor,
          'booking.seatMatch',
          'booking',
          bookingId,
          'Matched to free seat on ${best.trip.tripCode} (+${best.addedMinutes} min, +${best.addedKm} km).',
          related: {'trip': best.trip.id},
        ),
      );
    }
    return r;
  }

  /// Employee ad-hoc request: submit, then auto-match if fleet policy allows.
  Future<Result<Booking>> submitAdhoc(BookingDraft draft) async {
    final r = await bookings.submit(draft);
    if (!r.isOk || !ctx.view.policy.autoMatchAdhoc) return r;
    final m = await matchBest(r.valueOrNull!.id, actor: Actor.system);
    final b = ctx.db.bookings[r.valueOrNull!.id]!;
    return Ok(
      b,
      info: m.isOk
          ? 'Matched instantly to ${m.valueOrNull!.tripCode}'
          : 'Request submitted — no free seat yet; Fleet Manager will review',
    );
  }

  /// Utilization snapshot for a day: seats released by absences and reused
  /// by matched ad-hoc requests.
  ({int released, int reused, int freeSeats}) utilization(DateTime day) {
    var released = 0, free = 0;
    for (final t in ctx.db.trips.values.where(
      (t) =>
          sameDay(t.serviceDate, day) &&
          t.isAssigned &&
          t.status != TripStatus.cancelled,
    )) {
      released += t.absentEmployeeIds.length;
      final v = ctx.db.vehicles[t.assignedVehicleId];
      if (v != null && t.actualStart == null) {
        free += math.max(
          0,
          (v.totalSeats -
                  1 -
                  ((t.guardRequired || v.requiresSecurityGuard) ? 1 : 0)) -
              t.employeeIds.length,
        );
      }
    }
    final reused = ctx.db.audit.values
        .where(
          (a) => a.action == 'booking.seatMatch' && sameDay(a.timestamp, day),
        )
        .length;
    return (released: released, reused: reused, freeSeats: free);
  }

  String describe(SeatMatch m) => m.feasible
      ? '${m.trip.tripCode}: +${m.addedMinutes} min, +${m.addedKm} km, ${m.seatsAfter}/${m.capacity} seats'
      : '${m.trip.tripCode}: ${m.reasons.first}';

  static String fmtDay(DateTime d) => Fmt.dateShort(d);
}
