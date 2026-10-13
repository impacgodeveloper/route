import '../../domain/models/models.dart';

/// Deterministic v3 fixtures (safety, telematics, SOS, analytics, dynamic
/// matching). Shared by first-run seed and the v2→v3 migration; only fills
/// missing data.
abstract final class V3Fixtures {
  static DateTime _at(DateTime anchor, int dayOffset, int h, int m) {
    final t = DateTime(anchor.year, anchor.month, anchor.day + dayOffset, h, m);
    return t.isAfter(anchor) ? anchor.subtract(const Duration(minutes: 1)) : t;
  }

  static FleetPolicy policy(DateTime anchor) =>
      FleetPolicy(updatedAt: _at(anchor, -30, 9, 0));

  /// Passed tests today for DR1–DR3 (so baseline flows keep working) plus
  /// history incl. one cleared failure.
  static List<AlcoholTest> alcoholTests(DateTime anchor) => [
    for (final (i, d) in [(1, 'DR1'), (2, 'DR2'), (3, 'DR3')])
      AlcoholTest(
        id: 'AT-100$i',
        driverId: d,
        vehicleId: 'C$i',
        testedAt: _at(anchor, 0, 5, 50 + i * 3),
        readingMg: 0,
        thresholdMg: 0,
        result: AlcoholResult.pass,
        method: 'Connected breathalyzer (simulated)',
      ),
    AlcoholTest(
      id: 'AT-0990',
      driverId: 'DR3',
      vehicleId: 'C3',
      testedAt: _at(anchor, -5, 6, 5),
      readingMg: 12,
      thresholdMg: 0,
      result: AlcoholResult.fail,
      method: 'Connected breathalyzer (simulated)',
      note: 'Mouthwash suspected; retest passed at 06:25 (demo).',
      clearedBy: 'Fleet Manager',
      clearedAt: _at(anchor, -5, 6, 30),
    ),
    AlcoholTest(
      id: 'AT-0991',
      driverId: 'DR3',
      vehicleId: 'C3',
      testedAt: _at(anchor, -5, 6, 25),
      readingMg: 0,
      thresholdMg: 0,
      result: AlcoholResult.pass,
      method: 'Connected breathalyzer (simulated)',
    ),
  ];

  static List<Geofence> geofences(DateTime anchor) => [
    Geofence(
      id: 'GF-1',
      name: 'Demo City service area',
      kind: GeofenceKind.serviceArea,
      centerX: 16,
      centerY: 14,
      radiusKm: 22,
      notes: 'Vehicles must stay inside the operating area (fictional).',
      createdAt: _at(anchor, -30, 9, 0),
    ),
    Geofence(
      id: 'GF-2',
      name: 'Planned route corridor',
      kind: GeofenceKind.routeCorridor,
      notes: 'Applies to every active trip; width from fleet policy.',
      createdAt: _at(anchor, -30, 9, 0),
    ),
    Geofence(
      id: 'GF-3',
      name: 'Restricted: industrial zone (demo)',
      kind: GeofenceKind.restrictedZone,
      centerX: 33,
      centerY: 30,
      radiusKm: 2,
      notes: 'No passenger vehicles (fictional rule).',
      createdAt: _at(anchor, -30, 9, 0),
    ),
  ];

  static List<VehicleEvent> vehicleEvents(DateTime anchor) => [
    VehicleEvent(
      id: 'VE-1001',
      vehicleId: 'C3',
      tripId: 'TR-1003',
      driverId: 'DR3',
      type: VehicleEventType.speeding,
      occurredAt: _at(anchor, 0, 7, 32),
      description:
          '68 km/h in a 60 km/h policy limit near Silver Oak Avenue (simulated).',
      value: 68,
      limit: 60,
      x: 14,
      y: 8,
    ),
    VehicleEvent(
      id: 'VE-1002',
      vehicleId: 'C2',
      type: VehicleEventType.diagnosticFault,
      occurredAt: _at(anchor, -1, 18, 10),
      description:
          'P0420 · Catalyst efficiency below threshold (simulated diagnostic).',
    ),
    VehicleEvent(
      id: 'VE-0990',
      vehicleId: 'C1',
      tripId: 'TR-0991',
      driverId: 'DR1',
      type: VehicleEventType.routeDeviation,
      occurredAt: _at(anchor, -1, 8, 5),
      description: '2.6 km outside the planned corridor (road closure, demo).',
      value: 2.6,
      limit: 2,
      acknowledgedAt: _at(anchor, -1, 8, 20),
    ),
  ];

  static Vehicle vehicle(Vehicle v) => v.id == 'C2' && v.diagnosticCodes.isEmpty
      ? v.copyWith(
          diagnosticCodes: const [
            'P0420 · Catalyst efficiency below threshold (demo)',
          ],
        )
      : v;
}
