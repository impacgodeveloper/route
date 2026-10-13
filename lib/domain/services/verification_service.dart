import '../../core/demo/clock.dart';
import '../models/models.dart';

/// Outcome of a demo QR / T-PIN check. Never contains the secret itself.
class VerificationOutcome {
  const VerificationOutcome(this.status, this.message, {this.employeeId});
  final VerificationStatus status;
  final String message;
  final String? employeeId;
  bool get ok => status == VerificationStatus.verified;
}

/// Demo-only boarding credentials.
///
/// * QR payload: `EFM-DEMO|<tripCode>|<employeeCode>|<yyyyMMdd>|<check>`
/// * T-PIN: 4 digits derived from trip + employee.
/// Both are deterministic, non-secret, and clearly NOT production
/// credentials. Payloads/PINs are never written to logs or the database.
class VerificationService {
  const VerificationService();

  static const prefix = 'EFM-DEMO';

  static int _hash(String s) {
    var h = 0x811C9DC5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  static String _ymd(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  String _check(String tripCode, String employeeCode, String ymd) =>
      (_hash('$tripCode|$employeeCode|$ymd') % 0xFFFF)
          .toRadixString(16)
          .toUpperCase()
          .padLeft(4, '0');

  String qrPayload(Trip trip, Employee employee) {
    final ymd = _ymd(trip.serviceDate);
    return '$prefix|${trip.tripCode}|${employee.employeeCode}|$ymd|${_check(trip.tripCode, employee.employeeCode, ymd)}';
  }

  String tpin(Trip trip, Employee employee) =>
      (_hash('PIN|${trip.tripCode}|${employee.employeeCode}') % 9000 + 1000)
          .toString();

  /// Pass validity: the service day only.
  bool isExpired(Trip trip, DateTime now) =>
      !sameDay(trip.serviceDate, now) && now.isAfter(trip.serviceDate);

  VerificationOutcome verifyQr({
    required String payload,
    required Trip trip,
    required List<Employee> tripEmployees,
    required DateTime now,
  }) {
    final parts = payload.trim().split('|');
    if (parts.length != 5 || parts[0] != prefix) {
      return const VerificationOutcome(
        VerificationStatus.invalid,
        'Not a recognised demo pass.',
      );
    }
    final [_, tripCode, empCode, ymd, check] = parts;
    if (_check(tripCode, empCode, ymd) != check) {
      return const VerificationOutcome(
        VerificationStatus.invalid,
        'Pass check failed — the code may be altered.',
      );
    }
    if (tripCode != trip.tripCode) {
      return VerificationOutcome(
        VerificationStatus.wrongTrip,
        'This pass is for $tripCode, not ${trip.tripCode}.',
      );
    }
    final emp = tripEmployees
        .where((e) => e.employeeCode == empCode)
        .firstOrNull;
    if (emp == null) {
      return VerificationOutcome(
        VerificationStatus.invalid,
        '$empCode is not on this trip manifest.',
      );
    }
    if (ymd != _ymd(now)) {
      return VerificationOutcome(
        VerificationStatus.expired,
        'Pass is valid only on its service date.',
        employeeId: emp.id,
      );
    }
    return _boardingState(trip, emp);
  }

  VerificationOutcome verifyTpin({
    required String pin,
    required Trip trip,
    required Employee employee,
    required DateTime now,
  }) {
    if (!RegExp(r'^\d{4}$').hasMatch(pin.trim())) {
      return const VerificationOutcome(
        VerificationStatus.invalid,
        'Enter the 4-digit T-PIN.',
      );
    }
    if (!trip.employeeIds.contains(employee.id)) {
      return VerificationOutcome(
        VerificationStatus.invalid,
        '${employee.employeeCode} is not on this trip.',
      );
    }
    if (pin.trim() != tpin(trip, employee)) {
      return const VerificationOutcome(
        VerificationStatus.invalid,
        'Incorrect T-PIN.',
      );
    }
    if (!sameDay(trip.serviceDate, now)) {
      return VerificationOutcome(
        VerificationStatus.expired,
        'T-PIN is valid only on the service date.',
        employeeId: employee.id,
      );
    }
    return _boardingState(trip, employee);
  }

  VerificationOutcome _boardingState(Trip trip, Employee e) {
    if (trip.boardedPassengerIds.contains(e.id)) {
      return VerificationOutcome(
        VerificationStatus.duplicate,
        '${e.employeeCode} is already boarded.',
        employeeId: e.id,
      );
    }
    if (trip.alightedPassengerIds.contains(e.id)) {
      return VerificationOutcome(
        VerificationStatus.duplicate,
        '${e.employeeCode} has already completed this trip.',
        employeeId: e.id,
      );
    }
    return VerificationOutcome(
      VerificationStatus.verified,
      '${e.employeeCode} ${e.name} verified.',
      employeeId: e.id,
    );
  }
}
