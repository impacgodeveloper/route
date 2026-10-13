import '../models/models.dart';

/// Seat breakdown for a vehicle on a given trip.
class SeatBreakdown {
  const SeatBreakdown({
    required this.totalSeats,
    required this.driverSeats,
    required this.guardSeats,
  });

  final int totalSeats;
  final int driverSeats;
  final int guardSeats;

  int get passengerCapacity =>
      (totalSeats - driverSeats - guardSeats).clamp(0, totalSeats);

  @override
  String toString() =>
      '$totalSeats total − $driverSeats driver − $guardSeats guard = $passengerCapacity employee seats';
}

/// Single source of truth for seat maths.
///
/// Convention: `Vehicle.totalSeats` INCLUDES the driver seat.
/// Employee capacity = totalSeats − 1 driver seat − required guard seats.
abstract final class CapacityRules {
  static const driverSeats = 1;
  static const guardSeatsWhenRequired = 1;

  /// A guard seat is required when the vehicle policy requires one, or
  /// the trip explicitly requires one (employer guard policy), or any
  /// passenger has an explicit admin-set escort flag while the employer
  /// guard policy is enabled. Never inferred from names.
  static bool guardRequired({
    required Vehicle vehicle,
    bool tripGuardRequired = false,
    Employer? employer,
    Iterable<Employee> passengers = const [],
  }) {
    if (vehicle.requiresSecurityGuard || tripGuardRequired) return true;
    if (employer != null && employer.securityGuardPolicyEnabled) {
      return passengers.any((e) => e.guardEscortRequired);
    }
    return false;
  }

  static SeatBreakdown breakdown(
    Vehicle vehicle, {
    bool guardRequired = false,
  }) => SeatBreakdown(
    totalSeats: vehicle.totalSeats,
    driverSeats: driverSeats,
    guardSeats: (guardRequired || vehicle.requiresSecurityGuard)
        ? guardSeatsWhenRequired
        : 0,
  );

  static int passengerCapacity(Vehicle vehicle, {bool guardRequired = false}) =>
      breakdown(vehicle, guardRequired: guardRequired).passengerCapacity;
}
