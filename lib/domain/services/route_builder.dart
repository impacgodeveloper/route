import '../models/models.dart';
import '../rules/geo_rules.dart';

/// Result of planning an ordered route for a set of employees.
class RoutePlan {
  const RoutePlan({
    required this.stops,
    required this.distanceKm,
    required this.durationMinutes,
    required this.departure,
    required this.variant,
  });

  final List<PlannedStop> stops;
  final double distanceKm;
  final int durationMinutes;
  final DateTime departure;
  final RouteVariant variant;

  DateTime get arrival => stops.isEmpty ? departure : stops.last.plannedArrival;

  /// Arrival at each employee's own destination stop.
  DateTime? dropTimeFor(String employeeId) {
    for (final s in stops) {
      if (s.kind == StopKind.drop && s.employeeIds.contains(employeeId)) {
        return s.plannedArrival;
      }
    }
    return null;
  }
}

/// Builds ordered pickup → drop stop sequences with planned times.
///
/// Ordering strategy (deliberately NOT nearest-neighbour):
/// * pickups: farthest-from-destination first ("sweep inward"), so the
///   vehicle collects outlying employees early and moves monotonically
///   towards the offices;
/// * drops: earliest arrival deadline first, ties broken by distance.
/// A caller (the optimizer) can pass an explicit [pickupOrder] it chose by
/// scoring permutations.
abstract final class RouteBuilder {
  static RoutePlan plan({
    required List<Employee> employees,
    required Map<String, Location> locations,
    required DateTime departure,
    RouteVariant variant = RouteVariant.internalRoads,
    List<String>? pickupOrder,
    int boardingMinutes = GeoRules.boardingMinutesPerStop,
    double scenarioFactor = 1.0,
  }) {
    if (employees.isEmpty) {
      return RoutePlan(
        stops: const [],
        distanceKm: 0,
        durationMinutes: 0,
        departure: departure,
        variant: variant,
      );
    }
    final byPickup = <String, List<String>>{};
    final byDrop = <String, List<Employee>>{};
    for (final e in employees) {
      byPickup.putIfAbsent(e.pickupLocationId, () => []).add(e.id);
      byDrop.putIfAbsent(e.destinationId, () => []).add(e);
    }

    final dropLocs = byDrop.keys.map((id) => locations[id]!).toList();
    final cx =
        dropLocs.map((l) => l.demoX).reduce((a, b) => a + b) / dropLocs.length;
    final cy =
        dropLocs.map((l) => l.demoY).reduce((a, b) => a + b) / dropLocs.length;
    final centroid = Location(
      id: '_c',
      code: '_c',
      name: 'centroid',
      type: LocationType.office,
      address: '',
      demoX: cx,
      demoY: cy,
    );

    final pickupIds = pickupOrder != null
        ? pickupOrder.where(byPickup.containsKey).toList()
        : (byPickup.keys.toList()..sort((a, b) {
            final da = GeoRules.straightKm(locations[a]!, centroid);
            final db = GeoRules.straightKm(locations[b]!, centroid);
            final c = db.compareTo(da);
            return c != 0 ? c : a.compareTo(b);
          }));
    // Include any pickup missing from an explicit order.
    for (final id in byPickup.keys) {
      if (!pickupIds.contains(id)) pickupIds.add(id);
    }

    final lastPickup = locations[pickupIds.last]!;
    final dropIds = byDrop.keys.toList()
      ..sort((a, b) {
        int deadline(String id) => byDrop[id]!
            .map((e) => e.requiredArrivalMinutes)
            .reduce((x, y) => x < y ? x : y);
        final c = deadline(a).compareTo(deadline(b));
        if (c != 0) return c;
        return GeoRules.straightKm(
          lastPickup,
          locations[a]!,
        ).compareTo(GeoRules.straightKm(lastPickup, locations[b]!));
      });

    final stops = <PlannedStop>[];
    var t = departure;
    var km = 0.0;
    Location? prev;
    void visit(String locId, StopKind kind, List<String> ids) {
      final loc = locations[locId]!;
      if (prev != null) {
        final leg = GeoRules.roadKm(prev!, loc, variant);
        km += leg;
        t = t.add(
          Duration(
            minutes:
                GeoRules.travelMinutes(
                  leg,
                  variant,
                  t,
                  scenarioFactor: scenarioFactor,
                ) +
                boardingMinutes,
          ),
        );
      }
      stops.add(
        PlannedStop(
          locationId: locId,
          kind: kind,
          employeeIds: ids,
          plannedArrival: t,
        ),
      );
      prev = loc;
    }

    for (final id in pickupIds) {
      visit(id, StopKind.pickup, byPickup[id]!);
    }
    for (final id in dropIds) {
      visit(id, StopKind.drop, byDrop[id]!.map((e) => e.id).toList());
    }
    return RoutePlan(
      stops: stops,
      distanceKm: double.parse(km.toStringAsFixed(1)),
      durationMinutes: t.difference(departure).inMinutes,
      departure: departure,
      variant: variant,
    );
  }

  /// Plans backwards from the earliest employee deadline minus [bufferMinutes]
  /// so the vehicle arrives on time. Iterates because travel time depends on
  /// the (traffic-sensitive) departure time.
  static RoutePlan planForDeadline({
    required List<Employee> employees,
    required Map<String, Location> locations,
    required DateTime serviceDay,
    required int bufferMinutes,
    RouteVariant variant = RouteVariant.internalRoads,
    List<String>? pickupOrder,
    int? earliestDepartureMinutes,
    double scenarioFactor = 1.0,
  }) {
    final day = DateTime(serviceDay.year, serviceDay.month, serviceDay.day);
    final deadlineMin = employees
        .map((e) => e.requiredArrivalMinutes)
        .reduce((a, b) => a < b ? a : b);
    final target = day.add(Duration(minutes: deadlineMin - bufferMinutes));
    var departure = target.subtract(const Duration(minutes: 60));
    RoutePlan plan = RouteBuilder.plan(
      employees: employees,
      locations: locations,
      departure: departure,
      variant: variant,
      pickupOrder: pickupOrder,
      scenarioFactor: scenarioFactor,
    );
    for (var i = 0; i < 5; i++) {
      // Align the tightest employee (largest lateness vs own deadline).
      var delta = -1 << 30;
      for (final e in employees) {
        final own = day.add(
          Duration(minutes: e.requiredArrivalMinutes - bufferMinutes),
        );
        final late = plan.dropTimeFor(e.id)!.difference(own).inMinutes;
        if (late > delta) delta = late;
      }
      if (delta == 0) break;
      departure = departure.subtract(Duration(minutes: delta));
      if (earliestDepartureMinutes != null) {
        final earliest = day.add(Duration(minutes: earliestDepartureMinutes));
        if (departure.isBefore(earliest)) departure = earliest;
      }
      plan = RouteBuilder.plan(
        employees: employees,
        locations: locations,
        departure: departure,
        variant: variant,
        pickupOrder: pickupOrder,
        scenarioFactor: scenarioFactor,
      );
    }
    // Round departure down to 5 minutes for a clean schedule, then make
    // sure nobody is late (traffic factors can make the iteration oscillate
    // around peak boundaries; moving earlier is monotonic).
    var rounded = departure.subtract(Duration(minutes: departure.minute % 5));
    var result = RouteBuilder.plan(
      employees: employees,
      locations: locations,
      departure: rounded,
      variant: variant,
      pickupOrder: pickupOrder,
      scenarioFactor: scenarioFactor,
    );
    for (var i = 0; i < 12; i++) {
      var worst = 0;
      for (final e in employees) {
        final own = day.add(
          Duration(minutes: e.requiredArrivalMinutes - bufferMinutes),
        );
        final late = result.dropTimeFor(e.id)!.difference(own).inMinutes;
        if (late > worst) worst = late;
      }
      if (worst <= 0) break;
      final step = ((worst + 4) ~/ 5) * 5;
      final earliest = earliestDepartureMinutes == null
          ? null
          : day.add(Duration(minutes: earliestDepartureMinutes));
      final next = rounded.subtract(Duration(minutes: step));
      if (earliest != null && next.isBefore(earliest)) break;
      rounded = next;
      result = RouteBuilder.plan(
        employees: employees,
        locations: locations,
        departure: rounded,
        variant: variant,
        pickupOrder: pickupOrder,
        scenarioFactor: scenarioFactor,
      );
    }
    return result;
  }

  /// Converts a plan into persisted route + stop rows.
  static (TripRoute, List<RouteStop>) materialize({
    required RoutePlan plan,
    required String routeId,
    required String routeCode,
    required String name,
    String? employerId,
    String? optimizationRunId,
  }) {
    final stops = <RouteStop>[];
    for (var i = 0; i < plan.stops.length; i++) {
      final s = plan.stops[i];
      stops.add(
        RouteStop(
          id: '$routeId-S${i + 1}',
          routeId: routeId,
          locationId: s.locationId,
          sequence: i + 1,
          kind: s.kind,
          plannedArrival: s.plannedArrival,
          boardingEmployeeIds: s.kind == StopKind.pickup
              ? s.employeeIds
              : const [],
          alightingEmployeeIds: s.kind == StopKind.drop
              ? s.employeeIds
              : const [],
          status: StopStatus.upcoming,
        ),
      );
    }
    final route = TripRoute(
      id: routeId,
      routeCode: routeCode,
      name: name,
      employerId: employerId,
      stopIds: stops.map((s) => s.id).toList(),
      estimatedDistanceKm: plan.distanceKm,
      estimatedDurationMinutes: plan.durationMinutes,
      status: RouteStatus.planned,
      optimizationRunId: optimizationRunId,
      variant: plan.variant,
    );
    return (route, stops);
  }
}
