import '../models/models.dart';

/// Pickup/drop-off tolerance rules (client reference: ±7 min default).
///
/// The tolerance is the window communicated to an employee around their
/// PLANNED pickup/drop time. It is deliberately separate from:
/// * vehicle waiting time at a stop (`pickup_wait_tolerance_min`),
/// * the route safety buffer before the office deadline,
/// * the maximum detour.
/// It never excuses a missed mandatory office-arrival deadline.
abstract final class ToleranceRules {
  static const minMinutes = 0;
  static const maxMinutes = 30;
  static const clientReferenceDefault = 7;

  static String? validate(int? minutes) {
    if (minutes == null) return null;
    if (minutes < minMinutes || minutes > maxMinutes) {
      return 'Tolerance must be between $minMinutes and $maxMinutes minutes.';
    }
    return null;
  }

  /// [planned] ± tolerance.
  static (DateTime from, DateTime to) window(DateTime planned, int tolerance) =>
      (
        planned.subtract(Duration(minutes: tolerance)),
        planned.add(Duration(minutes: tolerance)),
      );

  /// Actual − planned in minutes (+ late, − early).
  static int deviation(DateTime actual, DateTime planned) =>
      actual.difference(planned).inMinutes;

  static bool within(DateTime actual, DateTime planned, int tolerance) =>
      deviation(actual, planned).abs() <= tolerance;

  /// "On time", "4 min early", "9 min late (outside ±7)".
  static String describe(DateTime actual, DateTime planned, int tolerance) {
    final d = deviation(actual, planned);
    if (d == 0) return 'On time';
    final base = d > 0 ? '$d min late' : '${-d} min early';
    return d.abs() <= tolerance
        ? '$base (within ±$tolerance)'
        : '$base (outside ±$tolerance)';
  }
}

/// Shift validation shared by forms and services.
abstract final class ShiftRules {
  static List<String> validate({
    required int? start,
    required int? end,
    required int arrival,
    String label = 'Shift',
  }) {
    final errors = <String>[];
    if (start == null || end == null) return errors;
    if (start < 0 || start >= 1440 || end < 0 || end >= 1440) {
      errors.add('$label times must be within the day (00:00–23:59).');
    }
    if (start == end) errors.add('$label start and end cannot be equal.');
    final duration = end < start ? 1440 - start + end : end - start;
    if (duration > 16 * 60) {
      errors.add('$label cannot be longer than 16 hours.');
    }
    if (arrival > start) {
      errors.add(
        'Required office arrival must be at or before the shift start.',
      );
    } else if (start - arrival > 180) {
      errors.add(
        'Required office arrival is more than 3 hours before the shift start.',
      );
    }
    return errors;
  }

  static bool overlaps(int aStart, int aEnd, int bStart, int bEnd) {
    List<(int, int)> segs(int s, int e) =>
        e > s ? [(s, e)] : [(s, 1440), (0, e)];
    for (final x in segs(aStart, aEnd)) {
      for (final y in segs(bStart, bEnd)) {
        if (x.$1 < y.$2 && y.$1 < x.$2) return true;
      }
    }
    return false;
  }

  /// True if the union of [windows] covers [start, end] (minutes of day,
  /// same day). Windows may be overnight.
  static bool covers(List<(int, int)> windows, int start, int end) {
    final segs = <(int, int)>[];
    for (final (s, e) in windows) {
      if (e > s) {
        segs.add((s, e));
      } else {
        segs
          ..add((s, 1440))
          ..add((0, e));
      }
    }
    segs.sort((a, b) => a.$1.compareTo(b.$1));
    var reach = start;
    for (final (s, e) in segs) {
      if (s > reach) break;
      if (e > reach) reach = e;
      if (reach >= end) return true;
    }
    return reach >= end;
  }
}

/// Contract and fleet-allocation constraints used by assignment validation
/// and the optimizer (single implementation).
abstract final class CommercialRules {
  static int minutesOf(DateTime t) => t.hour * 60 + t.minute;

  /// Contract check for an employer's day. [vehicleIdsThatDay] must include
  /// the vehicle(s) being assigned.
  static ({List<String> errors, List<String> warnings}) contract({
    required List<Contract> contracts,
    required String employerCode,
    required DateTime day,
    required Set<String> vehicleIdsThatDay,
  }) {
    final errors = <String>[];
    final warnings = <String>[];
    if (contracts.isEmpty) return (errors: errors, warnings: warnings);
    final active = contracts.where((c) => c.coversDay(day)).firstOrNull;
    if (active == null) {
      final latest = contracts.first;
      errors.add(
        'No active contract for $employerCode on this date '
        '(latest ${latest.contractCode} is ${latest.validityOn(day).label.toLowerCase()}).',
      );
      return (errors: errors, warnings: warnings);
    }
    if (vehicleIdsThatDay.length > active.agreedVehicleCount) {
      final msg =
          'Contract ${active.contractCode} allows ${active.agreedVehicleCount} car(s) per day; '
          'this would use ${vehicleIdsThatDay.length} (${(vehicleIdsThatDay.toList()..sort()).join(', ')}).';
      if (active.hardVehicleLimit) {
        errors.add(msg);
      } else {
        warnings.add('$msg Soft limit — allowed with warning.');
      }
    }
    final daysLeft = DateTime(
      active.validUntil.year,
      active.validUntil.month,
      active.validUntil.day,
    ).difference(DateTime(day.year, day.month, day.day)).inDays;
    if (daysLeft <= 30) {
      warnings.add(
        'Contract ${active.contractCode} expires in $daysLeft day(s).',
      );
    }
    return (errors: errors, warnings: warnings);
  }

  /// Returns an error when [resourceId] has allocations but none for
  /// [employerId] covering the window. Resources with no allocation
  /// records at all are treated as unrestricted (shared pool).
  static String? allocation({
    required List<FleetAllocation> resourceAllocations,
    required String employerId,
    required String employerCode,
    required String resourceLabel,
    required int startMinutes,
    required int endMinutes,
  }) {
    final active = resourceAllocations.where((a) => a.active).toList();
    if (active.isEmpty) return null;
    final mine = active.where((a) => a.employerId == employerId).toList();
    if (mine.isEmpty) {
      return '$resourceLabel is not allocated to $employerCode.';
    }
    final ok = ShiftRules.covers(
      [for (final a in mine) (a.windowStartMinutes, a.windowEndMinutes)],
      startMinutes,
      endMinutes > startMinutes ? endMinutes : startMinutes + 1,
    );
    if (!ok) {
      return '$resourceLabel is not allocated to $employerCode for '
          '${_hm(startMinutes)}–${_hm(endMinutes)} (check fleet-company shift windows).';
    }
    return null;
  }

  static String _hm(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}
