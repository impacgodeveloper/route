import '../../core/persistence/local_database.dart';
import '../models/models.dart';

/// Recomputes operational status of vehicles/drivers from their trips.
/// Maintenance/unavailable/off-duty states are explicit and preserved.
abstract final class ResourceSync {
  static bool _active(Trip t) => t.status.isActive && t.actualStart != null;
  static bool _upcoming(Trip t) =>
      t.status.isUpcoming ||
      (t.status == TripStatus.needsAttention && t.actualStart == null);

  static void vehicle(Txn tx, LocalDatabase db, String? vehicleId) {
    final v = db.vehicles[vehicleId];
    if (v == null) return;
    if (v.status == VehicleStatus.maintenance ||
        v.status == VehicleStatus.unavailable) {
      return;
    }
    final trips = db.trips.where((t) => t.assignedVehicleId == v.id);
    final next = trips.any(_active)
        ? VehicleStatus.onTrip
        : trips.any(_upcoming)
        ? VehicleStatus.assigned
        : VehicleStatus.available;
    if (next != v.status) tx.put(db.vehicles, v.copyWith(status: next));
  }

  static void driver(Txn tx, LocalDatabase db, String? driverId) {
    final d = db.drivers[driverId];
    if (d == null) return;
    if (d.status == DriverStatus.offDuty ||
        d.status == DriverStatus.unavailable) {
      return;
    }
    final trips = db.trips.where((t) => t.assignedDriverId == d.id);
    final next = trips.any(_active)
        ? DriverStatus.onTrip
        : trips.any(_upcoming)
        ? DriverStatus.assigned
        : DriverStatus.available;
    if (next != d.status) tx.put(db.drivers, d.copyWith(status: next));
  }
}
