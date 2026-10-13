import 'dart:math' as math;

import '../../core/demo/clock.dart';
import '../../core/persistence/local_database.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/result.dart';
import '../models/models.dart';
import '../rules/geo_rules.dart';
import 'service_context.dart';

/// Fleet-wide safety/telematics/SOS/matching policy (Fleet Manager).
class FleetPolicyService {
  FleetPolicyService(this.ctx);
  final ServiceContext ctx;

  List<String> validate(FleetPolicy p) => [
    if (p.alcoholThresholdMg < 0 || p.alcoholThresholdMg > 50)
      'Alcohol threshold must be 0–50 mg/100 ml (0 = zero tolerance).',
    if (p.speedLimitKmh < 20 || p.speedLimitKmh > 120)
      'Speed limit must be 20–120 km/h.',
    if (p.routeCorridorKm < 0.2 || p.routeCorridorKm > 10)
      'Route corridor must be 0.2–10 km.',
    if (p.maxAddedDetourMinutes < 0 || p.maxAddedDetourMinutes > 60)
      'Max added detour must be 0–60 minutes.',
    if (p.sosRecipients.isEmpty) 'SOS escalation needs at least one recipient.',
    if (!p.sosRecipients.contains(SosRecipient.fleetManager))
      'The Fleet Manager must always receive SOS alerts.',
    if (p.carbonCreditPricePerTonne < 0)
      'Carbon credit price cannot be negative.',
    if (p.baselineCo2GramsPerKm <= 0 ||
        p.baselineSpeedKmh <= 0 ||
        p.baselineCostPerKm < 0)
      'Baseline assumptions must be positive.',
  ];

  Future<Result<FleetPolicy>> save(
    FleetPolicy p, {
    Actor actor = Actor.fleetManager,
  }) {
    final errors = validate(p);
    if (errors.isNotEmpty) return Future.value(Err(errors));
    return ctx.run((tx) {
      final prev = ctx.view.policy;
      final saved = p.copyWith(updatedAt: ctx.now);
      tx.put(ctx.db.fleetPolicies, saved);
      ctx.audit(
        tx,
        actor,
        'policy.update',
        'fleetPolicy',
        'fleet',
        'Fleet safety & operations policy updated.',
        changes: describeChanges({
          'alcoholMonitoring': (
            prev.alcoholMonitoringEnabled,
            saved.alcoholMonitoringEnabled,
          ),
          'alcoholThresholdMg': (
            prev.alcoholThresholdMg,
            saved.alcoholThresholdMg,
          ),
          'alcoholCheckPoint': (
            prev.alcoholCheckPoint.label,
            saved.alcoholCheckPoint.label,
          ),
          'speedLimit': (prev.speedLimitKmh, saved.speedLimitKmh),
          'speedAlerts': (prev.speedAlertsEnabled, saved.speedAlertsEnabled),
          'geofenceAlerts': (
            prev.geofenceAlertsEnabled,
            saved.geofenceAlertsEnabled,
          ),
          'corridorKm': (prev.routeCorridorKm, saved.routeCorridorKm),
          'sosChain': (
            prev.sosRecipients.map((e) => e.label).join('/'),
            saved.sosRecipients.map((e) => e.label).join('/'),
          ),
          'autoMatch': (prev.autoMatchAdhoc, saved.autoMatchAdhoc),
          'maxAddedDetour': (
            prev.maxAddedDetourMinutes,
            saved.maxAddedDetourMinutes,
          ),
          'creditPrice': (
            prev.carbonCreditPricePerTonne,
            saved.carbonCreditPricePerTonne,
          ),
        }),
      );
      if (prev.alcoholMonitoringEnabled != saved.alcoholMonitoringEnabled) {
        for (final d in ctx.db.drivers.values) {
          ctx.notify(
            tx,
            role: UserRole.driver,
            recipientId: d.id,
            title:
                'Alcohol monitoring ${saved.alcoholMonitoringEnabled ? 'enabled' : 'disabled'}',
            body: saved.alcoholMonitoringEnabled
                ? 'A breathalyzer test is required ${saved.alcoholCheckPoint.label.toLowerCase()}.'
                : 'Breathalyzer tests are no longer required by fleet policy.',
            category: NotificationCategory.system,
            entityType: 'fleetPolicy',
            entityId: 'fleet',
          );
        }
      }
      return saved;
    }, info: 'Fleet policy saved');
  }
}

/// Breathalyzer checks. Readings come from a SIMULATED device (or a
/// supervisor entry); no real hardware is connected.
class AlcoholService {
  AlcoholService(this.ctx);
  final ServiceContext ctx;

  static const deviceSimulated = 'Connected breathalyzer (simulated)';
  static const supervisorEntry = 'Supervisor entry';

  /// Why the driver cannot start [trip] because of alcohol policy (empty =
  /// OK). Shared by start blockers and the UI.
  List<String> blockers(String driverId, {Trip? trip}) {
    final v = ctx.view;
    final policy = v.policy;
    if (!policy.alcoholMonitoringEnabled) return const [];
    final block = v.blockingAlcoholTest(driverId);
    if (block != null) {
      return [
        block.result == AlcoholResult.fail
            ? 'Alcohol test failed at ${Fmt.time(block.testedAt)} (${block.readingMg.toStringAsFixed(0)} mg/100 ml). Fleet Manager review required.'
            : 'Last alcohol test was inconclusive — retest required.',
      ];
    }
    // The LATEST test today must be a pass (a pass before a later failed or
    // cleared test does not count). Every-trip mode needs it for this trip.
    final today = v
        .alcoholTestsOf(driverId)
        .where((a) => sameDay(a.testedAt, v.now))
        .toList();
    final latest = today.firstOrNull;
    final passed =
        latest != null &&
        latest.result == AlcoholResult.pass &&
        (policy.alcoholCheckPoint == AlcoholCheckPoint.shiftStart ||
            (trip != null && latest.tripId == trip.id));
    if (!passed) {
      return [
        policy.alcoholCheckPoint == AlcoholCheckPoint.everyTrip
            ? 'Alcohol test required before this trip.'
            : 'Alcohol test required before your shift.',
      ];
    }
    return const [];
  }

  Future<Result<AlcoholTest>> record({
    required String driverId,
    required double? readingMg,
    String method = deviceSimulated,
    String? tripId,
    String note = '',
    Actor? actor,
  }) {
    final d = ctx.db.drivers[driverId];
    if (d == null) return Future.value(Err.single('Driver not found.'));
    if (readingMg != null && (readingMg < 0 || readingMg > 400)) {
      return Future.value(Err.single('Reading must be 0–400 mg/100 ml.'));
    }
    final who = actor ?? Actor.driver(driverId);
    return ctx.run(
      (tx) {
        final policy = ctx.view.policy;
        final result = readingMg == null
            ? AlcoholResult.inconclusive
            : (readingMg <= policy.alcoholThresholdMg
                  ? AlcoholResult.pass
                  : AlcoholResult.fail);
        final id = tx.newId(ctx.db.alcoholTests, 'AT-');
        var test = AlcoholTest(
          id: id,
          driverId: driverId,
          tripId: tripId,
          vehicleId: d.assignedVehicleId,
          testedAt: ctx.now,
          readingMg: readingMg ?? 0,
          thresholdMg: policy.alcoholThresholdMg,
          result: result,
          method: method,
          note: note.trim(),
        );
        if (result == AlcoholResult.fail) {
          final incId = tx.newId(ctx.db.incidents, 'IC-');
          tx.insert(
            ctx.db.incidents,
            Incident(
              id: incId,
              reference: incId,
              type: IncidentType.safety,
              driverId: driverId,
              vehicleId: d.assignedVehicleId,
              tripId: tripId,
              description:
                  'Alcohol test failed: ${readingMg!.toStringAsFixed(0)} mg/100 ml (limit ${policy.alcoholThresholdMg.toStringAsFixed(0)}). Trip start blocked pending review (simulated device).',
              severity: IncidentSeverity.high,
              status: IncidentStatus.submittedDemo,
              reportedByRole: UserRole.system,
              reportedById: 'alcohol-monitor',
              createdAt: ctx.now,
              updatedAt: ctx.now,
            ),
          );
          test = test.copyWith(incidentId: () => incId);
          ctx.notify(
            tx,
            role: UserRole.fleetManager,
            title: 'Alcohol test failed: ${d.driverCode}',
            body:
                '${readingMg.toStringAsFixed(0)} mg/100 ml vs limit ${policy.alcoholThresholdMg.toStringAsFixed(0)}. Driver blocked from starting trips.',
            category: NotificationCategory.incident,
            entityType: 'incident',
            entityId: incId,
          );
          // Upcoming trips of this driver today need attention / reassignment.
          for (final t
              in ctx.db.trips
                  .where(
                    (t) =>
                        t.assignedDriverId == driverId &&
                        t.actualStart == null &&
                        t.status.isUpcoming &&
                        sameDay(t.serviceDate, ctx.now),
                  )
                  .toList()) {
            tx.put(
              ctx.db.trips,
              t.copyWith(
                status: TripStatus.needsAttention,
                delayReason: () =>
                    'Driver ${d.driverCode} failed alcohol test — reassign or clear after retest.',
                updatedAt: ctx.now,
              ),
            );
          }
        }
        tx.insert(ctx.db.alcoholTests, test);
        ctx.audit(
          tx,
          who,
          'alcohol.test',
          'driver',
          driverId,
          '${d.driverCode} alcohol test ${result.label.toLowerCase()}${readingMg == null ? '' : ' (${readingMg.toStringAsFixed(0)} mg/100 ml)'}.',
          outcome: result == AlcoholResult.pass
              ? AuditOutcome.success
              : AuditOutcome.rejected,
          related: {'driver': driverId, 'trip': ?tripId},
          simulated: method == deviceSimulated,
        );
        return test;
      },
      info: switch (readingMg) {
        null => 'Device error — please retest',
        _ =>
          readingMg <= ctx.view.policy.alcoholThresholdMg
              ? 'Test passed'
              : 'Test failed — trip start blocked',
      },
    );
  }

  /// Fleet Manager lifts a failed-test block after review/retest.
  Future<Result<AlcoholTest>> clear(
    String testId,
    String note, {
    Actor actor = Actor.fleetManager,
  }) {
    if (note.trim().length < 5) {
      return Future.value(
        Err.single('Add a review note (at least 5 characters).'),
      );
    }
    return ctx.run((tx) {
      final a = ctx.db.alcoholTests[testId];
      if (a == null) throw ValidationFailure(['Test not found.']);
      if (a.result == AlcoholResult.pass || a.clearedAt != null) {
        throw ValidationFailure(['Nothing to clear.']);
      }
      final next = a.copyWith(
        clearedBy: () => actor.label,
        clearedAt: () => ctx.now,
      );
      tx.put(ctx.db.alcoholTests, next);
      // Restore trips that were put on hold because of this failure.
      for (final t
          in ctx.db.trips
              .where(
                (t) =>
                    t.assignedDriverId == a.driverId &&
                    t.status == TripStatus.needsAttention &&
                    t.actualStart == null &&
                    (t.delayReason ?? '').contains('alcohol'),
              )
              .toList()) {
        tx.put(
          ctx.db.trips,
          t.copyWith(
            status: TripStatus.assigned,
            delayReason: () => null,
            updatedAt: ctx.now,
          ),
        );
      }
      final inc = ctx.db.incidents[a.incidentId];
      if (inc != null && inc.status.isOpen) {
        tx.put(
          ctx.db.incidents,
          inc.copyWith(
            status: IncidentStatus.resolvedDemo,
            resolutionNotes: () => note.trim(),
            updatedAt: ctx.now,
          ),
        );
      }
      ctx.notify(
        tx,
        role: UserRole.driver,
        recipientId: a.driverId,
        title: 'Alcohol test review completed',
        body:
            'Block lifted by Fleet Manager. A passing retest is still required before driving.',
        category: NotificationCategory.system,
        entityType: 'driver',
        entityId: a.driverId,
      );
      ctx.audit(
        tx,
        actor,
        'alcohol.clear',
        'driver',
        a.driverId,
        'Cleared failed alcohol test ${a.id}.',
        reason: note.trim(),
      );
      return next;
    }, info: 'Block cleared — driver must pass a retest');
  }
}

/// Geofence CRUD (fictional demo plane).
class GeofenceService {
  GeofenceService(this.ctx);
  final ServiceContext ctx;

  List<String> validate(Geofence g) => [
    if (g.name.trim().length < 3) 'Name is required.',
    if (g.kind != GeofenceKind.routeCorridor &&
        (g.radiusKm <= 0 || g.radiusKm > 60))
      'Radius must be 0.1–60 km.',
    if (g.kind != GeofenceKind.routeCorridor &&
        (g.centerX < -20 ||
            g.centerX > 60 ||
            g.centerY < -20 ||
            g.centerY > 60))
      'Centre must be inside the demo map area.',
    for (final v in g.vehicleIds)
      if (ctx.db.vehicles[v] == null) 'Unknown vehicle $v.',
  ];

  Future<Result<Geofence>> save(
    Geofence g, {
    bool isNew = false,
    Actor actor = Actor.fleetManager,
  }) {
    final errors = validate(g);
    if (errors.isNotEmpty) return Future.value(Err(errors));
    return ctx.run((tx) {
      final id = isNew ? tx.newId(ctx.db.geofences, 'GF-') : g.id;
      final saved = isNew
          ? Geofence(
              id: id,
              name: g.name.trim(),
              kind: g.kind,
              centerX: g.centerX,
              centerY: g.centerY,
              radiusKm: g.radiusKm,
              vehicleIds: g.vehicleIds,
              active: g.active,
              notes: g.notes,
              createdAt: ctx.now,
            )
          : g;
      tx.put(ctx.db.geofences, saved);
      ctx.audit(
        tx,
        actor,
        isNew ? 'geofence.create' : 'geofence.update',
        'geofence',
        id,
        '${isNew ? 'Created' : 'Updated'} geofence ${saved.name} (${saved.kind.label}${saved.active ? '' : ', inactive'}).',
      );
      return saved;
    }, info: isNew ? 'Geofence created' : 'Geofence saved');
  }
}

/// Simulated live telemetry for one vehicle.
class VehicleTelemetry {
  const VehicleTelemetry({
    required this.vehicle,
    required this.status,
    required this.speedKmh,
    required this.x,
    required this.y,
    required this.lastUpdate,
    required this.trip,
    required this.positionLabel,
    required this.diagnosticCodes,
    required this.openEvents,
  });

  final Vehicle vehicle;

  /// "Moving", "Stopped at stop", "Parked", "Out of service".
  final String status;
  final double speedKmh;
  final double x;
  final double y;
  final DateTime lastUpdate;
  final Trip? trip;
  final String positionLabel;
  final List<String> diagnosticCodes;
  final List<VehicleEvent> openEvents;
  bool get moving => speedKmh > 0;
}

/// Vehicle diagnostics, GPS-style position, speed and geofence monitoring.
/// Everything here is SIMULATED from trip progress — no telematics hardware
/// or GPS is connected.
class TelematicsService {
  TelematicsService(this.ctx);
  final ServiceContext ctx;

  TelemetryActiveTrip? _activeTrip(String vehicleId) {
    final t = ctx.db.trips
        .where(
          (t) =>
              t.assignedVehicleId == vehicleId &&
              t.status.isActive &&
              t.actualStart != null,
        )
        .firstOrNull;
    return t == null ? null : TelemetryActiveTrip(t);
  }

  List<VehicleTelemetry> fleet() => [
    for (final v in ctx.db.vehicles.values.where((v) => v.active)) snapshot(v),
  ];

  VehicleTelemetry snapshot(Vehicle v) {
    final view = ctx.view;
    final open = view.vehicleEventsOf(v.id).where((e) => e.open).toList();
    final active = _activeTrip(v.id)?.trip;
    if (v.status == VehicleStatus.maintenance ||
        v.status == VehicleStatus.unavailable) {
      final p = view.location(v.homeParkingId);
      return VehicleTelemetry(
        vehicle: v,
        status: 'Out of service',
        speedKmh: 0,
        x: p?.demoX ?? 0,
        y: p?.demoY ?? 0,
        lastUpdate: v.lastInspectionAt ?? ctx.now,
        trip: null,
        positionLabel: p == null ? 'Unknown' : 'At ${p.code}',
        diagnosticCodes: v.diagnosticCodes,
        openEvents: open,
      );
    }
    if (active != null) {
      final pos = DemoPositionAdapter(view).positionOf(active);
      final stops = view.trips.stopsOf(active);
      final atStop = stops.any((s) => s.status == StopStatus.arrived);
      final route = view.trips.routeOf(active);
      final variant = route?.variant ?? RouteVariant.internalRoads;
      final base = variant == RouteVariant.ringRoad
          ? GeoRules.ringRoadSpeedKmh
          : GeoRules.internalSpeedKmh;
      final traffic = view.traffic.factorFor(variant);
      // Deterministic jitter (±4 km/h) from the minute of the hour.
      final jitter = ((ctx.now.minute * 7) % 9) - 4;
      final speed = atStop ? 0.0 : math.max(5.0, base / traffic + jitter);
      return VehicleTelemetry(
        vehicle: v,
        status: atStop ? 'Stopped at stop' : 'Moving',
        speedKmh: double.parse(speed.toStringAsFixed(0)),
        x: pos.$1,
        y: pos.$2,
        lastUpdate: pos.$4,
        trip: active,
        positionLabel: pos.$3,
        diagnosticCodes: v.diagnosticCodes,
        openEvents: open,
      );
    }
    final p = view.location(v.homeParkingId);
    return VehicleTelemetry(
      vehicle: v,
      status: 'Parked',
      speedKmh: 0,
      x: p?.demoX ?? 0,
      y: p?.demoY ?? 0,
      lastUpdate: ctx.now,
      trip: null,
      positionLabel: p == null ? 'Unknown' : 'Parked at ${p.code}',
      diagnosticCodes: v.diagnosticCodes,
      openEvents: open,
    );
  }

  /// Distance (km) from point to the planned route polyline of [trip].
  double corridorDistance(Trip trip, double x, double y) {
    final view = ctx.view;
    final pts = [
      for (final s in view.trips.stopsOf(trip)) view.location(s.locationId)!,
    ];
    if (pts.length < 2) return 0;
    var best = double.infinity;
    for (var i = 1; i < pts.length; i++) {
      best = math.min(
        best,
        _segDist(
          x,
          y,
          pts[i - 1].demoX,
          pts[i - 1].demoY,
          pts[i].demoX,
          pts[i].demoY,
        ),
      );
    }
    return best;
  }

  static double _segDist(
    double px,
    double py,
    double ax,
    double ay,
    double bx,
    double by,
  ) {
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    final t = len2 == 0
        ? 0.0
        : (((px - ax) * dx + (py - ay) * dy) / len2).clamp(0.0, 1.0);
    final cx = ax + t * dx, cy = ay + t * dy;
    return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
  }

  /// Evaluates a (simulated) position/speed sample against policy and
  /// geofences, recording events. Returns the events created.
  List<VehicleEvent> evaluateSample(
    Txn tx, {
    required Vehicle vehicle,
    required double x,
    required double y,
    required double speedKmh,
    Trip? trip,
  }) {
    final policy = ctx.view.policy;
    final created = <VehicleEvent>[];
    void add(
      VehicleEventType type,
      String description, {
      double? value,
      double? limit,
      String? geofenceId,
    }) {
      // Dedupe: an identical open event for the same vehicle/trip/type.
      final dup = ctx.db.vehicleEvents.any(
        (e) =>
            e.open &&
            e.vehicleId == vehicle.id &&
            e.type == type &&
            e.tripId == trip?.id &&
            e.geofenceId == geofenceId,
      );
      if (dup) return;
      final id = tx.newId(ctx.db.vehicleEvents, 'VE-');
      final ev = VehicleEvent(
        id: id,
        vehicleId: vehicle.id,
        tripId: trip?.id,
        driverId: trip?.assignedDriverId ?? vehicle.assignedDriverId,
        geofenceId: geofenceId,
        type: type,
        occurredAt: ctx.now,
        description: description,
        value: value,
        limit: limit,
        x: x,
        y: y,
      );
      tx.insert(ctx.db.vehicleEvents, ev);
      created.add(ev);
      ctx.notify(
        tx,
        role: UserRole.fleetManager,
        title: '${type.label}: Vehicle ${vehicle.vehicleCode} (simulated)',
        body: description,
        category: NotificationCategory.incident,
        entityType: 'vehicle',
        entityId: vehicle.id,
      );
      final driverId = trip?.assignedDriverId;
      if (driverId != null &&
          (type == VehicleEventType.speeding ||
              type == VehicleEventType.routeDeviation)) {
        ctx.notify(
          tx,
          role: UserRole.driver,
          recipientId: driverId,
          title: type == VehicleEventType.speeding
              ? 'Slow down'
              : 'Off planned route',
          body: description,
          category: NotificationCategory.routeChange,
          entityType: 'trip',
          entityId: trip!.id,
        );
      }
      ctx.audit(
        tx,
        Actor.system,
        'telematics.${type.name}',
        'vehicle',
        vehicle.id,
        description,
        related: {if (trip != null) 'trip': trip.id},
        simulated: true,
      );
    }

    if (policy.speedAlertsEnabled && speedKmh > policy.speedLimitKmh) {
      add(
        VehicleEventType.speeding,
        '${speedKmh.toStringAsFixed(0)} km/h vs ${policy.speedLimitKmh} km/h policy limit (simulated).',
        value: speedKmh,
        limit: policy.speedLimitKmh.toDouble(),
      );
    }
    if (policy.geofenceAlertsEnabled) {
      for (final g in ctx.db.geofences.values.where(
        (g) => g.active && g.appliesTo(vehicle.id),
      )) {
        final d = math.sqrt(
          math.pow(x - g.centerX, 2) + math.pow(y - g.centerY, 2),
        );
        switch (g.kind) {
          case GeofenceKind.serviceArea:
            if (d > g.radiusKm) {
              add(
                VehicleEventType.geofenceExit,
                'Outside "${g.name}" by ${(d - g.radiusKm).toStringAsFixed(1)} km (simulated).',
                value: d,
                limit: g.radiusKm,
                geofenceId: g.id,
              );
            }
          case GeofenceKind.restrictedZone:
            if (d <= g.radiusKm) {
              add(
                VehicleEventType.restrictedEntry,
                'Entered restricted zone "${g.name}" (simulated).',
                geofenceId: g.id,
              );
            }
          case GeofenceKind.routeCorridor:
            if (trip != null) {
              final off = corridorDistance(trip, x, y);
              if (off > policy.routeCorridorKm) {
                add(
                  VehicleEventType.routeDeviation,
                  '${off.toStringAsFixed(1)} km off the planned route of ${trip.tripCode} (corridor ${policy.routeCorridorKm} km, simulated).',
                  value: off,
                  limit: policy.routeCorridorKm,
                  geofenceId: g.id,
                );
              }
            }
        }
      }
    }
    return created;
  }

  /// Checks all vehicles' current simulated positions (e.g. on demand).
  Future<Result<List<VehicleEvent>>> scan({Actor actor = Actor.fleetManager}) =>
      ctx.run((tx) {
        final out = <VehicleEvent>[];
        for (final t in fleet()) {
          out.addAll(
            evaluateSample(
              tx,
              vehicle: t.vehicle,
              x: t.x,
              y: t.y,
              speedKmh: t.speedKmh,
              trip: t.trip,
            ),
          );
        }
        return out;
      }, info: 'Telematics scan complete (simulated)');

  /// Demo injections so the monitoring flow can be exercised without
  /// hardware. Each is clearly simulated.
  Future<Result<List<VehicleEvent>>> simulate(
    String vehicleId,
    VehicleEventType type, {
    double? value,
    String? code,
  }) {
    final v = ctx.db.vehicles[vehicleId];
    if (v == null) return Future.value(Err.single('Vehicle not found.'));
    return ctx.run((tx) {
      final snap = snapshot(v);
      final trip = snap.trip;
      switch (type) {
        case VehicleEventType.speeding:
          return evaluateSample(
            tx,
            vehicle: v,
            x: snap.x,
            y: snap.y,
            speedKmh: value ?? (ctx.view.policy.speedLimitKmh + 18),
            trip: trip,
          );
        case VehicleEventType.routeDeviation:
          if (trip == null) {
            throw ValidationFailure([
              'Vehicle ${v.vehicleCode} has no active trip to deviate from.',
            ]);
          }
          // Push the sample perpendicular-ish away until it is genuinely
          // outside the corridor (deterministic).
          var off = value ?? (ctx.view.policy.routeCorridorKm + 1.5);
          var px = snap.x + off, py = snap.y - off;
          for (
            var i = 0;
            i < 20 &&
                corridorDistance(trip, px, py) <=
                    ctx.view.policy.routeCorridorKm;
            i++
          ) {
            off += 1;
            px = snap.x + off;
            py = snap.y - off;
          }
          return evaluateSample(
            tx,
            vehicle: v,
            x: px,
            y: py,
            speedKmh: snap.speedKmh,
            trip: trip,
          );
        case VehicleEventType.geofenceExit:
          final area = ctx.db.geofences.values
              .where((g) => g.active && g.kind == GeofenceKind.serviceArea)
              .firstOrNull;
          if (area == null) {
            throw ValidationFailure(['No active service-area geofence.']);
          }
          return evaluateSample(
            tx,
            vehicle: v,
            x: area.centerX + area.radiusKm + (value ?? 3),
            y: area.centerY,
            speedKmh: snap.speedKmh,
            trip: trip,
          );
        case VehicleEventType.restrictedEntry:
          final zone = ctx.db.geofences.values
              .where((g) => g.active && g.kind == GeofenceKind.restrictedZone)
              .firstOrNull;
          if (zone == null) {
            throw ValidationFailure(['No active restricted zone.']);
          }
          return evaluateSample(
            tx,
            vehicle: v,
            x: zone.centerX,
            y: zone.centerY,
            speedKmh: snap.speedKmh,
            trip: trip,
          );
        case VehicleEventType.diagnosticFault:
        case VehicleEventType.harshBraking:
          final c = (code?.trim().isNotEmpty ?? false)
              ? code!.trim()
              : 'P0300 · Random misfire detected (demo)';
          if (type == VehicleEventType.diagnosticFault) {
            tx.put(
              ctx.db.vehicles,
              v.copyWith(diagnosticCodes: {...v.diagnosticCodes, c}.toList()),
            );
          }
          final id = tx.newId(ctx.db.vehicleEvents, 'VE-');
          final ev = VehicleEvent(
            id: id,
            vehicleId: v.id,
            tripId: trip?.id,
            driverId: trip?.assignedDriverId,
            type: type,
            occurredAt: ctx.now,
            description: type == VehicleEventType.diagnosticFault
                ? '$c (simulated diagnostic).'
                : 'Harsh braking detected (simulated).',
            x: snap.x,
            y: snap.y,
          );
          tx.insert(ctx.db.vehicleEvents, ev);
          ctx.notify(
            tx,
            role: UserRole.fleetManager,
            title: '${type.label}: Vehicle ${v.vehicleCode} (simulated)',
            body: ev.description,
            category: NotificationCategory.incident,
            entityType: 'vehicle',
            entityId: v.id,
          );
          ctx.audit(
            tx,
            Actor.system,
            'telematics.${type.name}',
            'vehicle',
            v.id,
            ev.description,
            simulated: true,
          );
          return [ev];
      }
    }, info: 'Simulated telematics event recorded');
  }

  Future<Result<VehicleEvent>> acknowledge(
    String eventId, {
    String note = '',
    bool raiseIncident = false,
    Actor actor = Actor.fleetManager,
  }) => ctx.run(
    (tx) {
      final e = ctx.db.vehicleEvents[eventId];
      if (e == null) throw ValidationFailure(['Event not found.']);
      if (!e.open) throw ValidationFailure(['Already acknowledged.']);
      var next = e.copyWith(acknowledgedAt: () => ctx.now);
      if (raiseIncident) {
        final incId = tx.newId(ctx.db.incidents, 'IC-');
        tx.insert(
          ctx.db.incidents,
          Incident(
            id: incId,
            reference: incId,
            type: e.type == VehicleEventType.routeDeviation
                ? IncidentType.routeDeviation
                : IncidentType.safety,
            tripId: e.tripId,
            driverId: e.driverId,
            vehicleId: e.vehicleId,
            description:
                '${e.type.label}: ${e.description}${note.trim().isEmpty ? '' : ' — ${note.trim()}'}',
            severity: IncidentSeverity.medium,
            status: IncidentStatus.acknowledgedDemo,
            reportedByRole: actor.role,
            reportedById: actor.id,
            createdAt: ctx.now,
            updatedAt: ctx.now,
          ),
        );
        next = next.copyWith(incidentId: () => incId);
      }
      tx.put(ctx.db.vehicleEvents, next);
      ctx.audit(
        tx,
        actor,
        'telematics.acknowledge',
        'vehicle',
        e.vehicleId,
        'Acknowledged ${e.type.label.toLowerCase()} event ${e.id}.',
        reason: note.trim().isEmpty ? null : note.trim(),
        simulated: true,
      );
      return next;
    },
    info: raiseIncident
        ? 'Acknowledged — incident created'
        : 'Event acknowledged',
  );

  Future<Result<Vehicle>> clearDiagnostic(
    String vehicleId,
    String code, {
    Actor actor = Actor.fleetManager,
  }) => ctx.run((tx) {
    final v = ctx.db.vehicles[vehicleId];
    if (v == null) throw ValidationFailure(['Vehicle not found.']);
    final next = v.copyWith(
      diagnosticCodes: v.diagnosticCodes.where((c) => c != code).toList(),
    );
    tx.put(ctx.db.vehicles, next);
    for (final e
        in ctx.db.vehicleEvents
            .where(
              (e) =>
                  e.vehicleId == vehicleId &&
                  e.type == VehicleEventType.diagnosticFault &&
                  e.open &&
                  e.description.startsWith(code.split(' ').first),
            )
            .toList()) {
      tx.put(ctx.db.vehicleEvents, e.copyWith(acknowledgedAt: () => ctx.now));
    }
    ctx.audit(
      tx,
      actor,
      'telematics.clearDiagnostic',
      'vehicle',
      vehicleId,
      'Cleared diagnostic code $code on Vehicle ${v.vehicleCode}.',
    );
    return next;
  }, info: 'Diagnostic code cleared');
}

/// Holder used internally by [TelematicsService].
class TelemetryActiveTrip {
  const TelemetryActiveTrip(this.trip);
  final Trip trip;
}

/// Lightweight position estimate (same model as the demo location service).
class DemoPositionAdapter {
  DemoPositionAdapter(this.view);
  final dynamic view;

  (double, double, String, DateTime) positionOf(Trip trip) {
    final stops = view.trips.stopsOf(trip) as List<RouteStop>;
    final locs = view.locationMap as Map<String, Location>;
    final now = view.now as DateTime;
    if (stops.isEmpty) return (0, 0, 'Unknown', now);
    final doneIdx = stops.lastIndexWhere(
      (s) => s.isDone || s.status == StopStatus.arrived,
    );
    if (doneIdx < 0) {
      final first = locs[stops.first.locationId]!;
      return (
        first.demoX - 1.5,
        first.demoY - 1.0,
        'Heading to ${first.code}',
        trip.actualStart ?? now,
      );
    }
    final last = stops[doneIdx];
    final lastLoc = locs[last.locationId]!;
    final lastTime =
        last.departedAt ?? last.actualArrival ?? trip.actualStart ?? now;
    if (last.status == StopStatus.arrived || doneIdx == stops.length - 1) {
      return (lastLoc.demoX, lastLoc.demoY, 'At ${lastLoc.code}', lastTime);
    }
    final next = stops[doneIdx + 1];
    final nextLoc = locs[next.locationId]!;
    final leg = next.plannedArrival
        .difference(last.plannedArrival)
        .inMinutes
        .clamp(1, 240);
    final f = (now.difference(lastTime).inMinutes / leg).clamp(0.0, 0.9);
    return (
      lastLoc.demoX + (nextLoc.demoX - lastLoc.demoX) * f,
      lastLoc.demoY + (nextLoc.demoY - lastLoc.demoY) * f,
      'Between ${lastLoc.code} and ${nextLoc.code}',
      lastTime,
    );
  }
}

/// One parking recommendation.
class ParkingRecommendation {
  const ParkingRecommendation({
    required this.vehicle,
    required this.currentParkingId,
    required this.recommendedParkingId,
    required this.targetLocationId,
    required this.targetLabel,
    required this.currentDeadheadKm,
    required this.recommendedDeadheadKm,
  });

  final Vehicle vehicle;
  final String? currentParkingId;
  final String recommendedParkingId;

  /// First pickup of the vehicle's next trip (or its current parking).
  final String targetLocationId;
  final String targetLabel;
  final double currentDeadheadKm;
  final double recommendedDeadheadKm;
  double get savingKm => currentDeadheadKm - recommendedDeadheadKm;
  bool get changes => recommendedParkingId != currentParkingId;
}

/// Optimal parking placement: assigns each vehicle to the parking spot
/// nearest its next first pickup (min empty km), respecting capacity.
/// Deterministic greedy on sorted (distance, vehicle, parking) pairs.
class ParkingPlannerService {
  ParkingPlannerService(this.ctx);
  final ServiceContext ctx;

  List<ParkingRecommendation> recommend() {
    final view = ctx.view;
    final parkings = view.parkingLocations
        .where((p) => p.active && (p.capacity ?? 0) > 0)
        .toList();
    final vehicles = view.vehicles.where((v) => v.active).toList();
    final targets = <String, (Location, String)>{};
    for (final v in vehicles) {
      final next =
          view.trips
              .all()
              .where(
                (t) =>
                    t.assignedVehicleId == v.id &&
                    t.actualStart == null &&
                    t.status.isUpcoming &&
                    !t.serviceDate.isBefore(dateOnly(ctx.now)),
              )
              .toList()
            ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
      final stops = next.isEmpty
          ? <RouteStop>[]
          : view.trips.stopsOf(next.first);
      final loc = stops.isEmpty
          ? view.location(v.homeParkingId)
          : view.location(stops.first.locationId);
      if (loc == null) continue;
      targets[v.id] = (
        loc,
        next.isEmpty
            ? 'No upcoming trip — keep near current base'
            : 'First pickup of ${next.first.tripCode} (${loc.code})',
      );
    }
    final pairs = <(double, Vehicle, Location)>[];
    for (final v in vehicles) {
      final t = targets[v.id];
      if (t == null) continue;
      for (final p in parkings) {
        pairs.add((GeoRules.roadKm(p, t.$1, RouteVariant.internalRoads), v, p));
      }
    }
    pairs.sort((a, b) {
      final c = a.$1.compareTo(b.$1);
      if (c != 0) return c;
      final d = a.$2.id.compareTo(b.$2.id);
      return d != 0 ? d : a.$3.id.compareTo(b.$3.id);
    });
    final used = <String, int>{};
    final assigned = <String, Location>{};
    for (final (_, v, p) in pairs) {
      if (assigned.containsKey(v.id)) continue;
      if ((used[p.id] ?? 0) >= (p.capacity ?? 0)) continue;
      assigned[v.id] = p;
      used[p.id] = (used[p.id] ?? 0) + 1;
    }
    return [
      for (final v in vehicles)
        if (assigned[v.id] != null && targets[v.id] != null)
          () {
            final target = targets[v.id]!.$1;
            final current = view.location(v.homeParkingId);
            return ParkingRecommendation(
              vehicle: v,
              currentParkingId: v.homeParkingId,
              recommendedParkingId: assigned[v.id]!.id,
              targetLocationId: target.id,
              targetLabel: targets[v.id]!.$2,
              currentDeadheadKm: current == null
                  ? 0
                  : double.parse(
                      GeoRules.roadKm(
                        current,
                        target,
                        RouteVariant.internalRoads,
                      ).toStringAsFixed(1),
                    ),
              recommendedDeadheadKm: double.parse(
                GeoRules.roadKm(
                  assigned[v.id]!,
                  target,
                  RouteVariant.internalRoads,
                ).toStringAsFixed(1),
              ),
            );
          }(),
    ];
  }

  /// Applies selected recommendations (vehicle home parking), audited.
  Future<Result<int>> apply(
    List<String> vehicleIds, {
    Actor actor = Actor.fleetManager,
  }) {
    final recs = {for (final r in recommend()) r.vehicle.id: r};
    final chosen = vehicleIds
        .map((id) => recs[id])
        .whereType<ParkingRecommendation>()
        .where((r) => r.changes)
        .toList();
    if (chosen.isEmpty) {
      return Future.value(Err.single('No parking changes selected.'));
    }
    return ctx.run((tx) {
      for (final r in chosen) {
        final v = ctx.db.vehicles[r.vehicle.id]!;
        tx.put(
          ctx.db.vehicles,
          v.copyWith(homeParkingId: () => r.recommendedParkingId),
        );
        ctx.audit(
          tx,
          actor,
          'parking.assign',
          'vehicle',
          v.id,
          'Vehicle ${v.vehicleCode} parking ${r.currentParkingId ?? '—'} → ${r.recommendedParkingId} (empty km ${r.currentDeadheadKm} → ${r.recommendedDeadheadKm}).',
          changes:
              'homeParking: ${r.currentParkingId ?? '—'} → ${r.recommendedParkingId}',
          related: {'vehicle': v.id},
        );
        if (v.assignedDriverId != null) {
          ctx.notify(
            tx,
            role: UserRole.driver,
            recipientId: v.assignedDriverId,
            title: 'New parking for Vehicle ${v.vehicleCode}',
            body:
                'Park at ${ctx.db.locations[r.recommendedParkingId]?.label} after your shift.',
            category: NotificationCategory.system,
            entityType: 'vehicle',
            entityId: v.id,
          );
        }
      }
      return chosen.length;
    }, info: 'Parking placements applied');
  }
}
