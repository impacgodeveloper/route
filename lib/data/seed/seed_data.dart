import '../../core/demo/clock.dart';
import '../../domain/models/models.dart';
import '../../domain/rules/capacity_rules.dart';
import '../../domain/rules/inspection_rules.dart';
import '../../domain/services/optimization_engine.dart';
import '../../domain/services/route_builder.dart';
import 'v2_fixtures.dart';

/// Bumped when the baseline dataset changes meaningfully.
const seedVersion = '2026.10.13-v3';

/// Demo password for employees with `optionalDemoPasswordEnabled`.
/// Fictional and shown on the login screen — not a real credential.
const demoEmployeePassword = 'demo1234';

/// Deterministic baseline dataset. All names, contacts, registrations and
/// coordinates are fictional. Dates are anchored to [anchor] (the day the
/// demo was first seeded or last reset) so "today" scenarios stay coherent.
class SeedDataset {
  SeedDataset(this.anchor) {
    _build();
  }

  final DateTime anchor;

  final employers = <Employer>[];
  final employees = <Employee>[];
  final drivers = <Driver>[];
  final vehicles = <Vehicle>[];
  final locations = <Location>[];
  final trips = <Trip>[];
  final routes = <TripRoute>[];
  final routeStops = <RouteStop>[];
  final bookings = <Booking>[];
  final passengerEvents = <PassengerEvent>[];
  final shifts = <Shift>[];
  final inspections = <Inspection>[];
  final incidents = <Incident>[];
  final billing = <BillingRecord>[];
  final configs = <OptimizationConfig>[];
  final runs = <OptimizationRun>[];
  final notifications = <AppNotification>[];
  final tickets = <SupportTicket>[];
  final audit = <AuditEvent>[];

  DateTime get d0 => dateOnly(anchor);
  DateTime day(int offset) => d0.add(Duration(days: offset));
  DateTime at(int offset, int h, int m) => atMinutes(day(offset), h * 60 + m);

  static const firstNames = [
    'Aditi',
    'Rahul',
    'Meera',
    'Vikram',
    'Sana',
    'Rohan',
    'Kavya',
    'Nikhil',
    'Isha',
    'Aman',
    'Pooja',
    'Siddharth',
    'Lakshmi',
    'Farhan',
    'Divya',
    'Karthik',
    'Anjali',
    'Varun',
    'Nisha',
    'Harish',
    'Tanvi',
    'Manoj',
    'Shreya',
    'Imran',
    'Deepa',
    'Gaurav',
    'Ritika',
    'Suresh',
    'Zoya',
    'Ajay',
  ];
  static const lastNames = [
    'Nair',
    'Gupta',
    'Reddy',
    'Menon',
    'Joshi',
    'Pillai',
    'Bose',
    'Kulkarni',
    'Verma',
    'Shetty',
    'Chopra',
    'Desai',
    'Hegde',
    'Patil',
    'Banerjee',
    'Kapoor',
    'Saxena',
    'Rao',
    'Mishra',
    'Thomas',
  ];

  void _build() {
    final created = at(-30, 9, 0);

    // ---------------- Employer ----------------
    final c1 = Employer(
      id: 'C1',
      code: 'C1',
      name: 'C1 Corporate Services',
      status: RecordStatus.active,
      currency: 'INR',
      maximumArrivalMinutes: 570,
      defaultDistanceRate: 18,
      preferredEvPercentage: 50,
      vehicleTypePreferences: const [
        VehicleType.sedan,
        VehicleType.mpv,
        VehicleType.van,
      ],
      luxuryPreference: LuxuryClass.standard,
      costPriority: 60,
      punctualityPriority: 80,
      securityGuardPolicyEnabled: false,
      allowSharedPooling: true,
      allowCrossEmployerPooling: false,
      createdAt: created,
      updatedAt: created,
    );
    employers.add(c1);

    // ---------------- Locations (fictional schematic plane, km) ----------------
    const pickups = [
      ('PK01', 'Cedar Park Gate', 4.0, 6.0),
      ('PK02', 'Riverside Colony', 6.0, 10.0),
      ('PK03', 'Orchid Enclave', 9.0, 5.0),
      ('PK04', 'Banyan Circle', 8.0, 14.0),
      ('PK05', 'Hillcrest Layout', 12.0, 22.0),
      ('PK06', 'Silver Oak Avenue', 14.0, 8.0),
      ('PK07', 'Lotus Tower Gate', 3.0, 18.0),
      ('PK08', 'Palm Grove Junction', 16.0, 26.0),
      ('PK09', 'Sunrise Apartments', 11.0, 2.0),
      ('PK10', 'Greenfield Crossing', 18.0, 4.0),
      ('PK11', 'Harbor View Road', 28.0, 24.0),
      ('PK12', 'Mango Lane Stop', 30.0, 6.0),
    ];
    for (final (code, name, x, y) in pickups) {
      locations.add(
        Location(
          id: code,
          code: code,
          name: name,
          type: LocationType.pickup,
          address: '$name, Demo City (fictional)',
          demoX: x,
          demoY: y,
          geofenceRadiusM: 150,
          employerId: 'C1',
        ),
      );
    }
    const offices = [
      ('G1', 'Tech Park Tower A', 22.0, 14.0),
      ('G2', 'Lakeside Business Hub', 24.0, 17.0),
      ('G3', 'Riverside Campus', 20.0, 19.0),
      ('G4', 'Central Square Offices', 26.0, 12.0),
    ];
    for (final (code, name, x, y) in offices) {
      locations.add(
        Location(
          id: code,
          code: code,
          name: name,
          type: LocationType.office,
          address: '$name, Demo City (fictional)',
          demoX: x,
          demoY: y,
          geofenceRadiusM: 200,
          employerId: 'C1',
        ),
      );
    }
    for (var i = 1; i <= 10; i++) {
      locations.add(
        Location(
          id: 'P$i',
          code: 'P$i',
          name: i == 1 ? 'Main Depot' : 'Parking Bay $i',
          type: i == 1 ? LocationType.depot : LocationType.parking,
          address: 'Parking zone $i, Demo City (fictional)',
          demoX: (2.0 + (i * 3.1) % 28),
          demoY: (3.0 + (i * 5.3) % 24),
          capacity: i == 1 ? 20 : 4 + (i % 3) * 2,
          notes: i == 1 ? 'EV charging available (demo)' : '',
        ),
      );
    }
    final locById = {for (final l in locations) l.id: l};

    // ---------------- Employees E1–E100 ----------------
    const named = {
      1: ('Asha Rao', 'PK01', 'G1', 540),
      2: ('Kiran Mehta', 'PK02', 'G2', 540),
      3: ('Neha Iyer', 'PK03', 'G3', 555),
      4: ('Arjun Das', 'PK04', 'G4', 540),
    };
    const arrivals = [510, 540, 555, 570];
    for (var i = 1; i <= 100; i++) {
      final n = named[i];
      final name =
          n?.$1 ??
          '${firstNames[i % firstNames.length]} ${lastNames[(i + 7 * (i ~/ firstNames.length)) % lastNames.length]}';
      final pickup =
          n?.$2 ?? 'PK${(((i * 5) % 12) + 1).toString().padLeft(2, '0')}';
      final dest = n?.$3 ?? 'G${(i % 4) + 1}';
      final arr = n?.$4 ?? arrivals[i % 4];
      employees.add(
        Employee(
          id: 'E$i',
          employeeCode: 'E$i',
          employerId: 'C1',
          name: name,
          fictionalEmail: 'e$i@c1-demo.example',
          fictionalPhone: '+91 90000 ${(10000 + i).toString()}',
          pickupLocationId: pickup,
          destinationId: dest,
          requiredArrivalMinutes: arr,
          shiftLabel: 'Morning ${_hm(arr + 15)}',
          transportPreference:
              TransportPreference.values[i % TransportPreference.values.length],
          status: (i == 99 || i == 100)
              ? RecordStatus.inactive
              : RecordStatus.active,
          optionalDemoPasswordEnabled: i == 4,
        ),
      );
    }
    // Explicit, documented route group for vehicle C2 trips: E5–E10.
    for (var i = 5; i <= 10; i++) {
      final e = employees[i - 1];
      employees[i - 1] = e.copyWith(
        pickupLocationId: [
          'PK05',
          'PK07',
          'PK04',
          'PK02',
          'PK05',
          'PK07',
        ][i - 5],
        destinationId: ['G3', 'G3', 'G2', 'G2', 'G3', 'G1'][i - 5],
        requiredArrivalMinutes: 540,
        shiftLabel: 'Morning 9:15 AM',
      );
    }
    for (var i = 11; i <= 15; i++) {
      final e = employees[i - 1];
      employees[i - 1] = e.copyWith(
        pickupLocationId: ['PK09', 'PK10', 'PK06', 'PK09', 'PK10'][i - 11],
        destinationId: ['G4', 'G1', 'G4', 'G1', 'G4'][i - 11],
        requiredArrivalMinutes: 555,
        shiftLabel: 'Morning 9:30 AM',
      );
    }
    for (var i = 16; i <= 19; i++) {
      final e = employees[i - 1];
      employees[i - 1] = e.copyWith(
        pickupLocationId: ['PK08', 'PK05', 'PK08', 'PK05'][i - 16],
        destinationId: 'G3',
        requiredArrivalMinutes: 555,
      );
    }
    final empById = {for (final e in employees) e.id: e};

    // ---------------- Vehicles & drivers ----------------
    vehicles.addAll([
      Vehicle(
        id: 'C1',
        vehicleCode: 'C1',
        fictionalRegistration: 'DM-01-EV-1001',
        type: VehicleType.sedan,
        propulsion: Propulsion.ev,
        totalSeats: 4,
        luxuryClass: LuxuryClass.premium,
        status: VehicleStatus.assigned,
        odometerKm: 18240,
        batteryOrFuelPercent: 82,
        assignedDriverId: 'DR1',
        lastInspectionAt: at(-2, 6, 10),
        homeParkingId: 'P1',
        model: 'Demo EV Sedan',
      ),
      Vehicle(
        id: 'C2',
        vehicleCode: 'C2',
        fictionalRegistration: 'DM-02-IC-2002',
        type: VehicleType.van,
        propulsion: Propulsion.ice,
        totalSeats: 7,
        luxuryClass: LuxuryClass.standard,
        status: VehicleStatus.onTrip,
        odometerKm: 45210,
        batteryOrFuelPercent: 64,
        assignedDriverId: 'DR2',
        lastInspectionAt: at(0, 6, 15),
        homeParkingId: 'P2',
        model: 'Demo 7-seat Van',
      ),
      Vehicle(
        id: 'C3',
        vehicleCode: 'C3',
        fictionalRegistration: 'DM-03-EV-3003',
        type: VehicleType.mpv,
        propulsion: Propulsion.ev,
        totalSeats: 6,
        luxuryClass: LuxuryClass.standard,
        status: VehicleStatus.onTrip,
        odometerKm: 9650,
        batteryOrFuelPercent: 71,
        assignedDriverId: 'DR3',
        lastInspectionAt: at(0, 6, 35),
        homeParkingId: 'P3',
        model: 'Demo EV MPV',
      ),
    ]);
    drivers.addAll([
      const Driver(
        id: 'DR1',
        driverCode: 'DR1',
        name: 'Ravi Kumar',
        fictionalContact: '+91 98000 00001',
        status: DriverStatus.assigned,
        assignedVehicleId: 'C1',
        shiftStartMinutes: 360,
        shiftEndMinutes: 840,
        attendanceStatus: AttendanceStatus.notCheckedIn,
        completedTripCount: 128,
        safetyChecklistStatus: SafetyChecklistStatus.pending,
      ),
      const Driver(
        id: 'DR2',
        driverCode: 'DR2',
        name: 'Priya Sharma',
        fictionalContact: '+91 98000 00002',
        status: DriverStatus.onTrip,
        assignedVehicleId: 'C2',
        shiftStartMinutes: 360,
        shiftEndMinutes: 840,
        attendanceStatus: AttendanceStatus.checkedIn,
        completedTripCount: 214,
        safetyChecklistStatus: SafetyChecklistStatus.passed,
      ),
      const Driver(
        id: 'DR3',
        driverCode: 'DR3',
        name: 'Arif Khan',
        fictionalContact: '+91 98000 00003',
        status: DriverStatus.onTrip,
        assignedVehicleId: 'C3',
        shiftStartMinutes: 360,
        shiftEndMinutes: 840,
        attendanceStatus: AttendanceStatus.late,
        completedTripCount: 96,
        safetyChecklistStatus: SafetyChecklistStatus.needsReview,
      ),
    ]);

    // ---------------- Trips ----------------
    var routeSeq = 1000;
    Trip makeTrip({
      required String code,
      required int dayOffset,
      required List<String> empIds,
      required TripStatus status,
      String? driverId,
      String? vehicleId,
      int? departMinutes,
      String instructions = '',
    }) {
      routeSeq++;
      final emps = empIds.map((id) => empById[id]!).toList();
      final plan = departMinutes == null
          ? RouteBuilder.planForDeadline(
              employees: emps,
              locations: locById,
              serviceDay: day(dayOffset),
              bufferMinutes: 10,
            )
          : RouteBuilder.plan(
              employees: emps,
              locations: locById,
              departure: atMinutes(day(dayOffset), departMinutes),
            );
      final routeId = 'R-$routeSeq';
      final (route, stops) = RouteBuilder.materialize(
        plan: plan,
        routeId: routeId,
        routeCode: 'R$routeSeq',
        name:
            '${emps.map((e) => e.employeeCode).first}–${emps.last.employeeCode} → ${plan.stops.where((s) => s.kind == StopKind.drop).map((s) => s.locationId).join('/')}',
        employerId: 'C1',
      );
      routes.add(route);
      routeStops.addAll(stops);
      final trip = Trip(
        id: code,
        tripCode: code,
        employerId: 'C1',
        assignedDriverId: driverId,
        assignedVehicleId: vehicleId,
        routeId: routeId,
        serviceDate: day(dayOffset),
        scheduledStart: plan.departure,
        scheduledArrival: plan.arrival,
        originLocationId: plan.stops.first.locationId,
        destinationLocationId: plan.stops.last.locationId,
        employeeIds: empIds,
        orderedStopIds: plan.stops.map((s) => s.locationId).toList(),
        estimatedDurationMinutes: plan.durationMinutes,
        status: status,
        instructions: instructions,
        assignmentHistory: driverId == null
            ? const []
            : [
                AssignmentRecord(
                  at: at(dayOffset - 1, 18, 0),
                  actorRole: UserRole.fleetManager,
                  driverId: driverId,
                  vehicleId: vehicleId,
                  reason: 'Initial assignment',
                ),
              ],
        createdAt: at(dayOffset - 2, 10, 0),
        updatedAt: at(dayOffset - 1, 18, 0),
      );
      trips.add(trip);
      return trip;
    }

    void completeTripData(
      Trip t, {
      double? distance,
      required double startOdo,
    }) {
      final route = routes.firstWhere((r) => r.id == t.routeId);
      final idx = trips.indexOf(t);
      final stops = routeStops.where((s) => s.routeId == route.id).toList();
      for (final s in stops) {
        final i = routeStops.indexOf(s);
        final arrived = s.plannedArrival.add(const Duration(minutes: 2));
        routeStops[i] = s.copyWith(
          status: StopStatus.completed,
          actualArrival: () => arrived,
          departedAt: () => arrived.add(const Duration(minutes: 2)),
        );
        for (final e in s.boardingEmployeeIds) {
          passengerEvents.add(
            PassengerEvent(
              id: 'PE-${t.id}-$e-B',
              tripId: t.id,
              employeeId: e,
              stopId: s.id,
              eventType: PassengerEventType.boarded,
              verificationMethod: VerificationMethod.qrDemo,
              verificationStatus: VerificationStatus.verified,
              eventTime: arrived,
            ),
          );
        }
        for (final e in s.alightingEmployeeIds) {
          passengerEvents.add(
            PassengerEvent(
              id: 'PE-${t.id}-$e-A',
              tripId: t.id,
              employeeId: e,
              stopId: s.id,
              eventType: PassengerEventType.alighted,
              verificationMethod: VerificationMethod.manualAuthorized,
              verificationStatus: VerificationStatus.verified,
              eventTime: arrived,
            ),
          );
        }
      }
      routes[routes.indexOf(route)] = route.copyWith(
        status: RouteStatus.completed,
      );
      final start = t.scheduledStart.add(const Duration(minutes: 1));
      final end = t.scheduledArrival!.add(const Duration(minutes: 3));
      trips[idx] = t.copyWith(
        status: TripStatus.completed,
        actualStart: () => start,
        actualArrival: () => end,
        actualDurationMinutes: () => end.difference(start).inMinutes,
        boardedPassengerIds: t.employeeIds,
        alightedPassengerIds: t.employeeIds,
        distanceKm: () => distance,
        startOdometerKm: () => startOdo,
        endOdometerKm: () => distance == null ? null : startOdo + distance,
        billableStatus: distance == null
            ? BillableStatus.missingDistance
            : BillableStatus.billed,
        completionNotes: () => distance == null
            ? 'Odometer reading not captured at drop-off.'
            : 'All passengers dropped on time.',
      );
    }

    // Historical completed trips (D-1, D-2) — billable.
    final h1 = makeTrip(
      code: 'TR-0991',
      dayOffset: -1,
      empIds: ['E1', 'E2', 'E3'],
      status: TripStatus.assigned,
      driverId: 'DR1',
      vehicleId: 'C1',
    );
    final h2 = makeTrip(
      code: 'TR-0992',
      dayOffset: -1,
      empIds: ['E5', 'E6', 'E7', 'E8', 'E9', 'E10'],
      status: TripStatus.assigned,
      driverId: 'DR2',
      vehicleId: 'C2',
    );
    final h3 = makeTrip(
      code: 'TR-0993',
      dayOffset: -1,
      empIds: ['E11', 'E12', 'E13', 'E14', 'E15'],
      status: TripStatus.assigned,
      driverId: 'DR3',
      vehicleId: 'C3',
    );
    final h4 = makeTrip(
      code: 'TR-0994',
      dayOffset: -2,
      empIds: ['E16', 'E17', 'E18', 'E19'],
      status: TripStatus.assigned,
      driverId: 'DR2',
      vehicleId: 'C2',
    );
    completeTripData(
      h1,
      distance: _r1(
        routes.firstWhere((r) => r.id == h1.routeId).estimatedDistanceKm + 0.6,
      ),
      startOdo: 18180,
    );
    completeTripData(
      h2,
      distance: _r1(
        routes.firstWhere((r) => r.id == h2.routeId).estimatedDistanceKm + 1.2,
      ),
      startOdo: 45140,
    );
    completeTripData(
      h3,
      distance: _r1(
        routes.firstWhere((r) => r.id == h3.routeId).estimatedDistanceKm + 0.4,
      ),
      startOdo: 9590,
    );
    completeTripData(h4, distance: null, startOdo: 45080);

    // Today.
    makeTrip(
      code: 'TR-1001',
      dayOffset: 0,
      empIds: ['E1', 'E2', 'E3'],
      status: TripStatus.assigned,
      driverId: 'DR1',
      vehicleId: 'C1',
      instructions:
          'Core demo route: pickups E1–E3, drops at G1–G3. Confirm each passenger with QR or T-PIN.',
    );
    final t2 = makeTrip(
      code: 'TR-1002',
      dayOffset: 0,
      empIds: ['E5', 'E6', 'E7', 'E8', 'E9', 'E10'],
      status: TripStatus.inProgress,
      driverId: 'DR2',
      vehicleId: 'C2',
    );
    final t3 = makeTrip(
      code: 'TR-1003',
      dayOffset: 0,
      empIds: ['E11', 'E12', 'E13', 'E14', 'E15'],
      status: TripStatus.delayed,
      driverId: 'DR3',
      vehicleId: 'C3',
    );
    makeTrip(
      code: 'TR-1004',
      dayOffset: 1,
      empIds: ['E16', 'E17', 'E18', 'E19'],
      status: TripStatus.planned,
      instructions: 'Awaiting driver and vehicle assignment.',
    );
    final t5 = makeTrip(
      code: 'TR-1005',
      dayOffset: 0,
      empIds: ['E20', 'E21', 'E22'],
      status: TripStatus.cancelled,
    );
    makeTrip(
      code: 'TR-1006',
      dayOffset: 1,
      empIds: ['E5', 'E6', 'E7', 'E8', 'E9', 'E10'],
      status: TripStatus.assigned,
      driverId: 'DR2',
      vehicleId: 'C2',
    );

    // TR-1002 in progress: first two pickup stops done.
    {
      final route = routes.firstWhere((r) => r.id == t2.routeId);
      final stops = routeStops.where((s) => s.routeId == route.id).toList();
      final boarded = <String>[];
      for (final s in stops.take(2)) {
        final i = routeStops.indexOf(s);
        final arr = s.plannedArrival.add(const Duration(minutes: 1));
        routeStops[i] = s.copyWith(
          status: StopStatus.completed,
          actualArrival: () => arr,
          departedAt: () => arr.add(const Duration(minutes: 2)),
        );
        for (final e in s.boardingEmployeeIds) {
          boarded.add(e);
          passengerEvents.add(
            PassengerEvent(
              id: 'PE-${t2.id}-$e-B',
              tripId: t2.id,
              employeeId: e,
              stopId: s.id,
              eventType: PassengerEventType.boarded,
              verificationMethod: e == 'E6'
                  ? VerificationMethod.tpinDemo
                  : VerificationMethod.qrDemo,
              verificationStatus: VerificationStatus.verified,
              eventTime: arr,
            ),
          );
        }
      }
      routes[routes.indexOf(route)] = route.copyWith(
        status: RouteStatus.active,
      );
      trips[trips.indexOf(t2)] = t2.copyWith(
        actualStart: () => t2.scheduledStart.add(const Duration(minutes: 2)),
        boardedPassengerIds: boarded,
        startOdometerKm: () => 45210,
      );
    }
    // TR-1003 delayed: first stop done, then congestion.
    {
      final route = routes.firstWhere((r) => r.id == t3.routeId);
      final stops = routeStops.where((s) => s.routeId == route.id).toList();
      final s = stops.first;
      final i = routeStops.indexOf(s);
      final arr = s.plannedArrival.add(const Duration(minutes: 9));
      routeStops[i] = s.copyWith(
        status: StopStatus.completed,
        actualArrival: () => arr,
        departedAt: () => arr.add(const Duration(minutes: 3)),
      );
      for (final e in s.boardingEmployeeIds) {
        passengerEvents.add(
          PassengerEvent(
            id: 'PE-${t3.id}-$e-B',
            tripId: t3.id,
            employeeId: e,
            stopId: s.id,
            eventType: PassengerEventType.boarded,
            verificationMethod: VerificationMethod.qrDemo,
            verificationStatus: VerificationStatus.verified,
            eventTime: arr,
          ),
        );
      }
      routes[routes.indexOf(route)] = route.copyWith(
        status: RouteStatus.active,
      );
      trips[trips.indexOf(t3)] = t3.copyWith(
        actualStart: () => t3.scheduledStart.add(const Duration(minutes: 8)),
        boardedPassengerIds: s.boardingEmployeeIds,
        delayReason: () =>
            'Heavy congestion near Silver Oak Avenue (demo report)',
        startOdometerKm: () => 9650,
      );
    }
    // TR-1005 cancelled.
    {
      final route = routes.firstWhere((r) => r.id == t5.routeId);
      routes[routes.indexOf(route)] = route.copyWith(
        status: RouteStatus.cancelled,
      );
      trips[trips.indexOf(t5)] = t5.copyWith(
        cancellationReason: () =>
            'Office G3 closed for maintenance (demo service notice).',
        billableStatus: BillableStatus.excluded,
      );
    }

    // ---------------- Billing (3 completed + billable) ----------------
    var billSeq = 0;
    for (final (code, add, adj, status) in [
      ('TR-0991', 0.0, 0.0, BillingStatus.paidDemo),
      ('TR-0992', 120.0, 0.0, BillingStatus.reviewed),
      ('TR-0993', 0.0, -50.0, BillingStatus.generated),
    ]) {
      billSeq++;
      final t = trips.firstWhere((x) => x.id == code);
      final km = t.distanceKm!;
      final total = km * c1.defaultDistanceRate + add + adj;
      billing.add(
        BillingRecord(
          id: 'BL-${1000 + billSeq}',
          employerId: 'C1',
          tripId: t.id,
          tripCode: t.tripCode,
          completedAt: t.actualArrival!,
          billableDistanceKm: km,
          ratePerKm: c1.defaultDistanceRate,
          additionalCharges: add,
          adjustment: adj,
          totalAmount: double.parse(total.toStringAsFixed(2)),
          status: status,
          calculationNotes:
              '${km.toStringAsFixed(1)} km × ₹${c1.defaultDistanceRate.toStringAsFixed(2)}/km'
              '${add != 0 ? ' + ₹${add.toStringAsFixed(2)} additional (toll, demo)' : ''}'
              '${adj != 0 ? ' ${adj < 0 ? '−' : '+'} ₹${adj.abs().toStringAsFixed(2)} adjustment (goodwill, demo)' : ''}',
          createdAt: t.actualArrival!.add(const Duration(minutes: 5)),
          reviewedAt: status == BillingStatus.generated
              ? null
              : t.actualArrival!.add(const Duration(hours: 6)),
        ),
      );
    }

    // ---------------- Bookings (≥10) ----------------
    Booking bk(
      int n,
      String emp,
      int dayOffset,
      BookingStatus s, {
      String? trip,
      String? reason,
      int? arrival,
      String notes = '',
    }) {
      final e = empById[emp]!;
      return Booking(
        id: 'BK-${1000 + n}',
        reference: 'BK-${1000 + n}',
        employeeId: emp,
        tripId: trip,
        requestedPickupLocationId: e.pickupLocationId,
        requestedDestinationId: e.destinationId,
        requestedDate: day(dayOffset),
        requestedArrivalMinutes: arrival ?? e.requiredArrivalMinutes,
        status: s,
        notes: notes,
        preference: e.transportPreference,
        decisionReason: reason,
        createdAt: at(dayOffset - 2, 16, n),
        updatedAt: at(dayOffset - 1, 11, n),
      );
    }

    bookings.addAll([
      bk(1, 'E1', -1, BookingStatus.completed, trip: 'TR-0991'),
      bk(2, 'E2', 0, BookingStatus.assigned, trip: 'TR-1001'),
      bk(3, 'E3', 0, BookingStatus.assigned, trip: 'TR-1001'),
      bk(
        4,
        'E4',
        1,
        BookingStatus.requested,
        notes: 'Client visit day — please confirm by evening.',
      ),
      bk(5, 'E23', 1, BookingStatus.requested),
      bk(
        6,
        'E24',
        1,
        BookingStatus.approved,
        reason: 'Approved — awaiting vehicle assignment.',
      ),
      bk(
        7,
        'E25',
        1,
        BookingStatus.waitlisted,
        reason: 'No vehicle has a free window at the requested time.',
      ),
      bk(
        8,
        'E26',
        1,
        BookingStatus.rejected,
        arrival: 630,
        reason:
            'Requested arrival 10:30 AM exceeds the employer maximum of 9:30 AM.',
      ),
      bk(
        9,
        'E27',
        1,
        BookingStatus.cancelled,
        reason: 'Cancelled by employee.',
      ),
      bk(
        10,
        'E16',
        1,
        BookingStatus.approved,
        trip: 'TR-1004',
        reason: 'Added to planned trip TR-1004.',
      ),
      bk(11, 'E30', 2, BookingStatus.requested),
      bk(
        12,
        'E20',
        0,
        BookingStatus.cancelled,
        trip: 'TR-1005',
        reason: 'Trip cancelled — office G3 closed (demo notice).',
      ),
    ]);

    // ---------------- Shifts ----------------
    Shift shift(
      String id,
      String drv,
      int dayOffset,
      ShiftStatus s, {
      int? inDelta,
      bool done = false,
    }) => Shift(
      id: id,
      driverId: drv,
      shiftDate: day(dayOffset),
      scheduledStart: at(dayOffset, 6, 0),
      scheduledEnd: at(dayOffset, 14, 0),
      actualCheckIn: inDelta == null
          ? null
          : at(dayOffset, 6, 0).add(Duration(minutes: inDelta)),
      actualCheckOut: done ? at(dayOffset, 14, 5) : null,
      status: s,
      handoverParkingId: done ? 'P1' : null,
      handoverNotes: done ? 'Vehicle parked and keys returned (demo).' : null,
    );
    shifts.addAll([
      shift(
        'SH-0991',
        'DR1',
        -1,
        ShiftStatus.completed,
        inDelta: -4,
        done: true,
      ),
      shift(
        'SH-0992',
        'DR2',
        -1,
        ShiftStatus.completed,
        inDelta: 2,
        done: true,
      ),
      shift(
        'SH-0993',
        'DR3',
        -1,
        ShiftStatus.completed,
        inDelta: 0,
        done: true,
      ),
      shift('SH-1001', 'DR1', 0, ShiftStatus.scheduled),
      shift('SH-1002', 'DR2', 0, ShiftStatus.checkedIn, inDelta: 2),
      shift('SH-1003', 'DR3', 0, ShiftStatus.late, inDelta: 22).copyWith(
        status: ShiftStatus.regularizationPending,
        regularizationStatus: () => RegularizationStatus.pending,
        regularizationReason: () =>
            'Vehicle charging took longer at depot (demo).',
      ),
    ]);

    // ---------------- Inspections ----------------
    List<InspectionItem> items(Map<String, CheckResult> overrides) => [
      for (final i in InspectionRules.blankChecklist())
        overrides.containsKey(i.key)
            ? i.copyWith(
                result: overrides[i.key],
                note: 'Reported in demo inspection',
              )
            : i,
    ];
    final insp1 = items({});
    final insp2 = items({'cleanliness': CheckResult.fail});
    final insp3 = items({'tyres': CheckResult.fail});
    inspections.addAll([
      Inspection(
        id: 'IN-1001',
        vehicleId: 'C2',
        driverId: 'DR2',
        date: day(0),
        items: insp1,
        overallStatus: InspectionRules.outcomeFor(insp1),
        submittedAt: at(0, 6, 15),
        notes: 'All good.',
      ),
      Inspection(
        id: 'IN-1002',
        vehicleId: 'C3',
        driverId: 'DR3',
        date: day(0),
        items: insp2,
        overallStatus: InspectionRules.outcomeFor(insp2),
        submittedAt: at(0, 6, 35),
        notes: 'Cabin needs cleaning after charging stop.',
      ),
      Inspection(
        id: 'IN-0990',
        vehicleId: 'C1',
        driverId: 'DR1',
        date: day(-2),
        items: insp3,
        overallStatus: InspectionRules.outcomeFor(insp3),
        submittedAt: at(-2, 6, 10),
        notes: 'Front-left tyre pressure low.',
        defectIncidentId: 'IC-1004',
      ),
    ]);

    // ---------------- Incidents ----------------
    incidents.addAll([
      Incident(
        id: 'IC-1001',
        reference: 'IC-1001',
        type: IncidentType.delay,
        tripId: 'TR-1003',
        driverId: 'DR3',
        vehicleId: 'C3',
        description:
            'Heavy congestion near Silver Oak Avenue; expect ~10 minutes delay.',
        severity: IncidentSeverity.medium,
        status: IncidentStatus.submittedDemo,
        reportedByRole: UserRole.driver,
        reportedById: 'DR3',
        demoLocationLabel: 'Near PK06 Silver Oak Avenue (simulated)',
        createdAt: at(0, 7, 40),
        updatedAt: at(0, 7, 40),
      ),
      Incident(
        id: 'IC-1002',
        reference: 'IC-1002',
        type: IncidentType.breakdown,
        vehicleId: 'C2',
        driverId: 'DR2',
        description:
            'Battery warning light on during return; vehicle pulled over safely.',
        severity: IncidentSeverity.high,
        status: IncidentStatus.resolvedDemo,
        reportedByRole: UserRole.driver,
        reportedById: 'DR2',
        replacementRequested: true,
        resolutionNotes:
            'Battery terminal tightened at depot (demo). Vehicle returned to service.',
        demoLocationLabel: 'Ring road, km 12 (simulated)',
        createdAt: at(-3, 18, 20),
        updatedAt: at(-3, 21, 0),
      ),
      Incident(
        id: 'IC-1003',
        reference: 'IC-1003',
        type: IncidentType.passengerIssue,
        tripId: 'TR-0992',
        driverId: 'DR2',
        vehicleId: 'C2',
        description:
            'Passenger E8 waited at the wrong gate; boarded 4 minutes late.',
        severity: IncidentSeverity.low,
        status: IncidentStatus.acknowledgedDemo,
        reportedByRole: UserRole.driver,
        reportedById: 'DR2',
        createdAt: at(-1, 7, 20),
        updatedAt: at(-1, 9, 0),
      ),
      Incident(
        id: 'IC-1004',
        reference: 'IC-1004',
        type: IncidentType.vehicleDefect,
        vehicleId: 'C1',
        driverId: 'DR1',
        description:
            'Inspection failed: tyres & pressure (critical). Trip start was blocked.',
        severity: IncidentSeverity.high,
        status: IncidentStatus.resolvedDemo,
        reportedByRole: UserRole.driver,
        reportedById: 'DR1',
        resolutionNotes: 'Tyre replaced at depot P1 (demo).',
        createdAt: at(-2, 6, 12),
        updatedAt: at(-2, 9, 30),
      ),
    ]);

    // ---------------- Optimization config + runs ----------------
    final config = OptimizationConfig(
      id: 'OC-1',
      employerId: 'C1',
      name: 'C1 default policy',
      enabled: true,
      costWeight: 6,
      punctualityWeight: 9,
      distanceWeight: 5,
      travelTimeWeight: 5,
      utilizationWeight: 5,
      evPreferenceWeight: 6,
      customerPreferenceWeight: 4,
      safetyWeight: 10,
      guardRequirementWeight: 5,
      maximumArrivalMinutes: 570,
      minimumBufferMinutes: 10,
      allowedVehicleTypes: const [
        VehicleType.sedan,
        VehicleType.mpv,
        VehicleType.van,
        VehicleType.suv,
      ],
      minimumEvPercentage: 50,
      additionalParameters: const {},
      activeParameters: const {},
      createdAt: created,
      updatedAt: created,
    );
    configs.add(config);
    const engine = OptimizationEngine();
    final e14 = [
      'E1',
      'E2',
      'E3',
      'E4',
    ].map((id) => V2Fixtures.employee(empById[id]!)).toList();
    final v2Drivers = [for (final d in drivers) V2Fixtures.driver(d, d0)];
    final v2Contracts = V2Fixtures.contracts(d0);
    final v2Allocations = V2Fixtures.allocations(d0);
    final input = OptimizationInput(
      config: config,
      employer: c1,
      employees: e14,
      vehicles: vehicles,
      drivers: v2Drivers,
      contracts: v2Contracts,
      allocations: v2Allocations,
      locations: locById,
      serviceDate: day(1),
      existingTrips: trips,
    );
    final run1 = engine.run(
      input,
      runId: 'OR-1001',
      reference: 'OR-1001',
      now: at(0, 5, 45),
    );
    final sedanOnly = config.copyWith(
      allowedVehicleTypes: const [VehicleType.sedan],
    );
    final run2 = engine.run(
      OptimizationInput(
        config: sedanOnly,
        employer: c1,
        employees: e14,
        vehicles: vehicles,
        drivers: v2Drivers,
        contracts: v2Contracts,
        allocations: v2Allocations,
        locations: locById,
        serviceDate: day(1),
        existingTrips: trips,
      ),
      runId: 'OR-1002',
      reference: 'OR-1002',
      now: at(0, 5, 50),
    );
    runs.addAll([run1, run2]);

    // ---------------- Notifications (≥8) ----------------
    var nSeq = 1000;
    void notify(
      UserRole role,
      String? to,
      String title,
      String body,
      NotificationCategory cat,
      String? type,
      String? id,
      DateTime when, {
      bool read = false,
    }) {
      nSeq++;
      notifications.add(
        AppNotification(
          id: 'NT-$nSeq',
          recipientRole: role,
          recipientId: to,
          title: title,
          body: body,
          category: cat,
          createdAt: when,
          readAt: read ? when.add(const Duration(minutes: 10)) : null,
          relatedEntityType: type,
          relatedEntityId: id,
        ),
      );
    }

    final t1 = trips.firstWhere((t) => t.id == 'TR-1001');
    notify(
      UserRole.employee,
      'E1',
      'Trip TR-1001 assigned',
      'Vehicle C1 (EV sedan) with driver Ravi Kumar. Pickup ${_t(routeStops.firstWhere((s) => s.routeId == t1.routeId).plannedArrival)} at Cedar Park Gate.',
      NotificationCategory.tripAssignment,
      'trip',
      'TR-1001',
      at(-1, 18, 5),
    );
    notify(
      UserRole.employee,
      'E1',
      'Pickup reminder',
      'Be at Cedar Park Gate 5 minutes before your pickup today.',
      NotificationCategory.pickupReminder,
      'trip',
      'TR-1001',
      at(0, 6, 0),
    );
    notify(
      UserRole.employee,
      'E2',
      'Trip TR-1001 assigned',
      'Vehicle C1 with driver Ravi Kumar.',
      NotificationCategory.tripAssignment,
      'trip',
      'TR-1001',
      at(-1, 18, 5),
    );
    notify(
      UserRole.employee,
      'E3',
      'Trip TR-1001 assigned',
      'Vehicle C1 with driver Ravi Kumar.',
      NotificationCategory.tripAssignment,
      'trip',
      'TR-1001',
      at(-1, 18, 5),
    );
    for (final e in ['E1', 'E2', 'E3', 'E4', 'E20', 'E21', 'E22']) {
      notify(
        UserRole.employee,
        e,
        'Service notice: G3 maintenance',
        'Riverside Campus (G3) is closed today for maintenance. Affected trips were cancelled.',
        NotificationCategory.serviceNotice,
        null,
        null,
        at(-1, 17, 0),
      );
    }
    for (final e in ['E11', 'E12', 'E13', 'E14', 'E15']) {
      notify(
        UserRole.employee,
        e,
        'TR-1003 running late',
        'Heavy congestion reported. Your driver expects ~10 minutes delay.',
        NotificationCategory.delay,
        'trip',
        'TR-1003',
        at(0, 7, 41),
      );
    }
    for (final e in ['E20', 'E21', 'E22']) {
      notify(
        UserRole.employee,
        e,
        'Trip TR-1005 cancelled',
        'Office G3 closed for maintenance today.',
        NotificationCategory.routeChange,
        'trip',
        'TR-1005',
        at(-1, 17, 5),
      );
    }
    notify(
      UserRole.employee,
      'E26',
      'Booking BK-1008 rejected',
      'Requested arrival 10:30 AM exceeds the employer maximum of 9:30 AM.',
      NotificationCategory.bookingUpdate,
      'booking',
      'BK-1008',
      at(0, 9, 0),
    );
    notify(
      UserRole.employee,
      'E1',
      'Trip TR-0991 completed',
      'Thanks for riding. Distance ${trips.firstWhere((t) => t.id == 'TR-0991').distanceKm} km.',
      NotificationCategory.tripAssignment,
      'trip',
      'TR-0991',
      at(-1, 9, 0),
      read: true,
    );
    notify(
      UserRole.driver,
      'DR1',
      'New trip TR-1001',
      '3 passengers · Vehicle C1 · first pickup at Cedar Park Gate.',
      NotificationCategory.tripAssignment,
      'trip',
      'TR-1001',
      at(-1, 18, 5),
    );
    notify(
      UserRole.driver,
      'DR2',
      'Trip TR-1006 assigned for tomorrow',
      '6 passengers · Vehicle C2.',
      NotificationCategory.tripAssignment,
      'trip',
      'TR-1006',
      at(0, 5, 30),
    );
    notify(
      UserRole.fleetManager,
      null,
      'Delay reported on TR-1003',
      'DR3 reported congestion near Silver Oak Avenue.',
      NotificationCategory.incident,
      'incident',
      'IC-1001',
      at(0, 7, 40),
    );
    notify(
      UserRole.fleetManager,
      null,
      'Inspection needs review: Vehicle C3',
      'Non-critical failure: cabin cleanliness.',
      NotificationCategory.incident,
      'vehicle',
      'C3',
      at(0, 6, 36),
    );
    notify(
      UserRole.fleetManager,
      null,
      'New booking request BK-1004',
      'E4 Arjun Das requests tomorrow 9:00 AM to G4.',
      NotificationCategory.bookingUpdate,
      'booking',
      'BK-1004',
      at(-1, 16, 4),
    );
    notify(
      UserRole.fleetManager,
      null,
      'Billing blocked: TR-0994',
      'Completed trip has no recorded distance. Enter distance to bill.',
      NotificationCategory.billing,
      'trip',
      'TR-0994',
      at(-2, 9, 30),
    );
    notify(
      UserRole.employerAdmin,
      null,
      'Billing generated: TR-0993',
      'New billing line ready for review.',
      NotificationCategory.billing,
      'billing',
      'BL-1003',
      at(-1, 9, 10),
    );
    notify(
      UserRole.employerAdmin,
      null,
      'Booking request BK-1004',
      'E4 Arjun Das requested transport for tomorrow.',
      NotificationCategory.bookingUpdate,
      'booking',
      'BK-1004',
      at(-1, 16, 4),
    );

    // ---------------- Support tickets ----------------
    tickets.addAll([
      SupportTicket(
        id: 'TK-1001',
        reference: 'TK-1001',
        createdByRole: UserRole.employee,
        createdById: 'E1',
        category: TicketCategory.trip,
        subject: 'AC was weak on TR-0991',
        description: 'Cabin was warm during the ride.',
        relatedTripId: 'TR-0991',
        status: TicketStatus.resolved,
        response: 'Vehicle AC serviced (demo response).',
        createdAt: at(-1, 10, 0),
        updatedAt: at(-1, 15, 0),
      ),
      SupportTicket(
        id: 'TK-1002',
        reference: 'TK-1002',
        createdByRole: UserRole.driver,
        createdById: 'DR2',
        category: TicketCategory.vehicle,
        subject: 'Fuel card declined (demo)',
        description: 'Fuel card was declined at the depot pump.',
        status: TicketStatus.open,
        createdAt: at(0, 6, 5),
        updatedAt: at(0, 6, 5),
      ),
    ]);

    // ---------------- Audit ----------------
    audit.addAll([
      AuditEvent(
        id: 'AU-1001',
        actorRole: UserRole.system,
        actorId: 'seed',
        action: 'seed',
        entityType: 'dataset',
        entityId: seedVersion,
        timestamp: anchor,
        summary: 'Baseline demo dataset created.',
      ),
      AuditEvent(
        id: 'AU-1002',
        actorRole: UserRole.fleetManager,
        actorId: 'FM',
        action: 'assign',
        entityType: 'trip',
        entityId: 'TR-1001',
        timestamp: at(-1, 18, 0),
        summary: 'Assigned DR1 + Vehicle C1 to TR-1001 (E1–E3).',
      ),
      AuditEvent(
        id: 'AU-1003',
        actorRole: UserRole.fleetManager,
        actorId: 'FM',
        action: 'cancel',
        entityType: 'trip',
        entityId: 'TR-1005',
        timestamp: at(-1, 17, 2),
        summary: 'Cancelled TR-1005: office G3 closed.',
      ),
      AuditEvent(
        id: 'AU-1004',
        actorRole: UserRole.system,
        actorId: 'billing',
        action: 'billing.generate',
        entityType: 'billing',
        entityId: 'BL-1003',
        timestamp: at(-1, 9, 10),
        summary: 'Billing generated for TR-0993.',
      ),
    ]);

    assert(CapacityRules.passengerCapacity(vehicles[0]) == 3);

    // Records that describe things that already happened must never be
    // dated after the moment of seeding (e.g. first launch at 6:30 AM).
    _clampPast(notifications, [
      'createdAt',
      'readAt',
    ], AppNotification.fromJson);
    _clampPast(incidents, ['createdAt', 'updatedAt'], Incident.fromJson);
    _clampPast(tickets, ['createdAt', 'updatedAt'], SupportTicket.fromJson);
    _clampPast(audit, ['timestamp'], AuditEvent.fromJson);
    _clampPast(bookings, ['createdAt', 'updatedAt'], Booking.fromJson);
    _clampPast(inspections, ['submittedAt'], Inspection.fromJson);
  }

  void _clampPast<T extends Entity>(
    List<T> rows,
    List<String> fields,
    T Function(Json) fromJson,
  ) {
    for (var i = 0; i < rows.length; i++) {
      final j = rows[i].toJson();
      var changed = false;
      for (final f in fields) {
        final v = dt(j[f]);
        if (v != null && v.isAfter(anchor)) {
          // Keep relative order: later events stay slightly later.
          j[f] = dtOut(anchor.subtract(Duration(seconds: 60 - (i % 60))));
          changed = true;
        }
      }
      if (changed) rows[i] = fromJson(j);
    }
  }

  static double _r1(double v) => double.parse(v.toStringAsFixed(1));

  static String _hm(int m) {
    final h = m ~/ 60, mm = m % 60;
    final ap = h >= 12 ? 'PM' : 'AM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${mm.toString().padLeft(2, '0')} $ap';
  }

  static String _t(DateTime d) => _hm(d.hour * 60 + d.minute);
}
