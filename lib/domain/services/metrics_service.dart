import '../../core/demo/clock.dart';
import '../../data/repositories/repositories.dart';
import '../models/models.dart';
import '../rules/capacity_rules.dart';

/// Inclusive date range used by reports.
class DateRange {
  const DateRange(this.start, this.end);
  final DateTime start;
  final DateTime end;

  bool contains(DateTime d) {
    final x = dateOnly(d);
    return !x.isBefore(dateOnly(start)) && !x.isAfter(dateOnly(end));
  }

  int get days => dateOnly(end).difference(dateOnly(start)).inDays + 1;

  factory DateRange.lastDays(DateTime today, int n) => DateRange(
    dateOnly(today).subtract(Duration(days: n - 1)),
    dateOnly(today),
  );
}

class DayValue {
  const DayValue(this.day, this.value);
  final DateTime day;
  final double value;
}

/// All dashboard/report numbers are computed from local records here —
/// no decorative or fabricated metrics.
class MetricsService {
  MetricsService(this.view);
  final DataView view;

  List<Trip> tripsIn(DateRange r, {String? employerId}) => view.trips
      .all()
      .where(
        (t) =>
            r.contains(t.serviceDate) &&
            (employerId == null || t.employerId == employerId),
      )
      .toList();

  Map<TripStatus, int> tripStatusCounts(Iterable<Trip> trips) {
    final m = <TripStatus, int>{};
    for (final t in trips) {
      m[t.status] = (m[t.status] ?? 0) + 1;
    }
    return m;
  }

  /// Deadline = earliest required arrival among the trip's employees.
  DateTime? deadlineOf(Trip t) {
    final emps = t.employeeIds
        .map(view.employee)
        .whereType<Employee>()
        .toList();
    if (emps.isEmpty) return null;
    final employer = view.employer(t.employerId);
    var m = emps
        .map((e) => e.requiredArrivalMinutes)
        .reduce((a, b) => a < b ? a : b);
    if (employer != null && m > employer.maximumArrivalMinutes) {
      m = employer.maximumArrivalMinutes;
    }
    return atMinutes(t.serviceDate, m);
  }

  /// On-time = first drop actually reached before the deadline. Only trips
  /// with recorded timestamps are counted.
  ({int measured, int onTime}) onTime(Iterable<Trip> trips) {
    var measured = 0, ok = 0;
    for (final t in trips.where((t) => t.status == TripStatus.completed)) {
      final drops = view.trips
          .stopsOf(t)
          .where((s) => s.kind == StopKind.drop && s.actualArrival != null)
          .toList();
      final deadline = deadlineOf(t);
      if (drops.isEmpty || deadline == null) continue;
      measured++;
      if (!drops.first.actualArrival!.isAfter(deadline)) ok++;
    }
    return (measured: measured, onTime: ok);
  }

  double recordedDistance(Iterable<Trip> trips) => trips
      .where((t) => t.status == TripStatus.completed)
      .fold(0.0, (s, t) => s + (t.distanceKm ?? 0));

  double charges(String employerId, DateRange r) => view
      .billingOf(employerId)
      .where((b) => r.contains(b.completedAt))
      .fold(0.0, (s, b) => s + b.totalAmount);

  List<DayValue> chargesByDay(String employerId, DateRange r) => [
    for (var i = 0; i < r.days; i++)
      () {
        final d = dateOnly(r.start).add(Duration(days: i));
        return DayValue(
          d,
          view
              .billingOf(employerId)
              .where((b) => sameDay(b.completedAt, d))
              .fold(0.0, (s, b) => s + b.totalAmount),
        );
      }(),
  ];

  List<DayValue> tripsByDay(
    DateRange r, {
    String? employerId,
    bool completedOnly = false,
  }) => [
    for (var i = 0; i < r.days; i++)
      () {
        final d = dateOnly(r.start).add(Duration(days: i));
        return DayValue(
          d,
          tripsIn(DateRange(d, d), employerId: employerId)
              .where((t) => !completedOnly || t.status == TripStatus.completed)
              .length
              .toDouble(),
        );
      }(),
  ];

  /// Seats used ÷ employee seats offered over assigned, non-cancelled trips.
  double utilization(Iterable<Trip> trips) {
    var used = 0, offered = 0;
    for (final t in trips.where(
      (t) => t.isAssigned && t.status != TripStatus.cancelled,
    )) {
      final v = view.vehicle(t.assignedVehicleId);
      if (v == null) continue;
      used += t.employeeIds.length;
      offered += CapacityRules.passengerCapacity(
        v,
        guardRequired: t.guardRequired,
      );
    }
    return offered == 0 ? 0 : 100 * used / offered;
  }

  Map<VehicleStatus, int> vehicleStatusCounts() {
    final m = {for (final s in VehicleStatus.values) s: 0};
    for (final v in view.vehicles) {
      m[v.status] = m[v.status]! + 1;
    }
    return m;
  }

  Map<DriverStatus, int> driverStatusCounts() {
    final m = {for (final s in DriverStatus.values) s: 0};
    for (final d in view.drivers) {
      m[d.status] = m[d.status]! + 1;
    }
    return m;
  }

  /// Per-vehicle km and trips for a range.
  List<({Vehicle vehicle, int trips, double km, double utilization})>
  vehicleUsage(DateRange r) => [
    for (final v in view.vehicles)
      () {
        final ts = tripsIn(
          r,
        ).where((t) => t.assignedVehicleId == v.id).toList();
        return (
          vehicle: v,
          trips: ts.where((t) => t.status == TripStatus.completed).length,
          km: recordedDistance(ts),
          utilization: utilization(ts),
        );
      }(),
  ];

  List<({Driver driver, int assigned, int completed, int incidents})>
  driverPerformance(DateRange r) => [
    for (final d in view.drivers)
      () {
        final ts = tripsIn(r).where((t) => t.assignedDriverId == d.id).toList();
        return (
          driver: d,
          assigned: ts.where((t) => t.status != TripStatus.cancelled).length,
          completed: ts.where((t) => t.status == TripStatus.completed).length,
          incidents: view
              .incidentsByDriver(d.id)
              .where((i) => r.contains(i.createdAt))
              .length,
        );
      }(),
  ];
}
