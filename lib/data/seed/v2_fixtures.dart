import '../../domain/models/models.dart';
import '../../domain/rules/geo_rules.dart';

/// Deterministic v2 (client-architecture) demo fixtures.
///
/// Shared by the first-run seed AND the v1→v2 migration so both produce the
/// same records. Every function only FILLS missing data — it never
/// overwrites values a user has already edited.
abstract final class V2Fixtures {
  static DateTime _day(DateTime anchor, int offset) => DateTime(
    anchor.year,
    anchor.month,
    anchor.day,
  ).add(Duration(days: offset));

  /// C1 company shift windows (start = office arrival + 15 min).
  static const c1Shifts = [
    ShiftWindow(
      id: 'S1',
      label: 'S1 · Early',
      startMinutes: 525,
      endMinutes: 1065,
    ),
    ShiftWindow(
      id: 'S2',
      label: 'S2 · General',
      startMinutes: 555,
      endMinutes: 1095,
    ),
    ShiftWindow(
      id: 'S3',
      label: 'S3 · Late morning',
      startMinutes: 570,
      endMinutes: 1110,
    ),
    ShiftWindow(
      id: 'S4',
      label: 'S4 · Mid',
      startMinutes: 585,
      endMinutes: 1125,
    ),
  ];

  static Employer employer(Employer e) {
    if (e.id != 'C1' || e.shifts.isNotEmpty) return e;
    return e.copyWith(
      shifts: c1Shifts,
      pickupToleranceMinutes: 7,
      billingCycle: BillingCycle.weekly,
      billingActive: true,
      contactName: e.contactName.isEmpty
          ? 'Transport desk (fictional)'
          : e.contactName,
      contactEmail: e.contactEmail.isEmpty
          ? 'transport@c1-demo.example'
          : e.contactEmail,
    );
  }

  static const _prefs = {
    'E1': {'travelTime': 3, 'reliability': 2},
    'E2': {'distance': 2},
    'E3': {'detour': 3},
    'E4': {'reliability': 3},
  };

  static Employee employee(Employee e) {
    var out = e;
    if (out.shiftStartMinutes == null || out.shiftEndMinutes == null) {
      final start = out.requiredArrivalMinutes + 15;
      final shift = c1Shifts.where((s) => s.startMinutes == start).firstOrNull;
      out = out.copyWith(
        shiftStartMinutes: () => start,
        shiftEndMinutes: () => (start + 540) % 1440,
        shiftLabel: shift == null ? out.shiftLabel : shift.label,
      );
    }
    if (out.travelPreferences.isEmpty && _prefs.containsKey(out.id)) {
      out = out.copyWith(travelPreferences: Map.of(_prefs[out.id]!));
    }
    if (out.id == 'E3' && out.pickupToleranceMinutes == null) {
      out = out.copyWith(pickupToleranceMinutes: () => 5);
    }
    return out;
  }

  static Location location(Location l) {
    var out = l;
    if (out.latitude == null || out.longitude == null) {
      out = out.copyWith(
        latitude: () => GeoRules.latFromY(out.demoY),
        longitude: () => GeoRules.lngFromX(out.demoX),
      );
    }
    if (out.isParking && !out.fleetOwned) out = out.copyWith(fleetOwned: true);
    return out;
  }

  static const _vehicleMeta = {
    'C1': ('DEMO-RC-1001', 'EVM-0001-DEMO', 'Pearl white', FuelType.electric),
    'C2': ('DEMO-RC-2002', 'DSL-2002-DEMO', 'Graphite grey', FuelType.diesel),
    'C3': ('DEMO-RC-3003', 'EVM-0003-DEMO', 'Midnight blue', FuelType.electric),
  };

  static Vehicle vehicle(Vehicle v) {
    final m = _vehicleMeta[v.id];
    if (m == null || v.rcNumber.isNotEmpty) return v;
    return v.copyWith(
      rcNumber: m.$1,
      engineNumber: m.$2,
      color: m.$3,
      fuelType: () => m.$4,
    );
  }

  static Driver driver(Driver d, DateTime anchor) {
    if (d.licenceNumber.isNotEmpty) return d;
    final n = d.id.replaceAll(RegExp(r'\D'), '').padLeft(4, '0');
    return d.copyWith(
      licenceNumber: 'DL-DEMO-$n',
      // DR3's licence expires soon (to demo the warning); others are valid.
      licenceExpiry: () => _day(anchor, d.id == 'DR3' ? 25 : 400),
      email: '${d.id.toLowerCase()}@fleet-demo.example',
      address: 'Depot P1, Demo City (fictional)',
    );
  }

  static List<Contract> contracts(DateTime anchor) => [
    Contract(
      id: 'CT-1001',
      contractCode: 'CT-2026-01',
      employerId: 'C1',
      documentRef: 'DOC-C1-2026-01 (reference only)',
      validFrom: _day(anchor, -60),
      validUntil: _day(anchor, 305),
      status: ContractStatus.active,
      agreedVehicleCount: 3,
      costPerVehicle: 55000,
      hardVehicleLimit: true,
      contactId: 'CN-C1-01',
      contactName: 'Transport desk (fictional)',
      notes: 'Shared pool; up to 3 cars per service day.',
      createdAt: _day(anchor, -62),
      updatedAt: _day(anchor, -62),
    ),
    Contract(
      id: 'CT-0901',
      contractCode: 'CT-2025-02',
      employerId: 'C1',
      documentRef: 'DOC-C1-2025-02 (reference only)',
      validFrom: _day(anchor, -425),
      validUntil: _day(anchor, -61),
      status: ContractStatus.active,
      agreedVehicleCount: 2,
      costPerVehicle: 50000,
      hardVehicleLimit: true,
      contactId: 'CN-C1-01',
      contactName: 'Transport desk (fictional)',
      notes: 'Previous term — kept for history.',
      createdAt: _day(anchor, -430),
      updatedAt: _day(anchor, -61),
    ),
  ];

  /// C1 may use vehicles C1–C3 and drivers DR1–DR3 in two daily windows.
  static List<FleetAllocation> allocations(DateTime anchor) {
    final out = <FleetAllocation>[];
    var n = 1000;
    for (final (type, ids) in [
      (ResourceType.vehicle, ['C1', 'C2', 'C3']),
      (ResourceType.driver, ['DR1', 'DR2', 'DR3']),
    ]) {
      for (final id in ids) {
        for (final (start, end, label) in [
          (300, 780, 'Morning operations'),
          (780, 1320, 'Evening operations'),
        ]) {
          n++;
          out.add(
            FleetAllocation(
              id: 'FA-$n',
              employerId: 'C1',
              resourceType: type,
              resourceId: id,
              windowStartMinutes: start,
              windowEndMinutes: end,
              label: label,
              createdAt: _day(anchor, -60),
            ),
          );
        }
      }
    }
    return out;
  }

  static TrafficState traffic(DateTime anchor) =>
      TrafficState.initial(_day(anchor, 0));
}
