import 'package:flutter/foundation.dart';

import '../enums/enums.dart';
import 'json.dart';

@immutable
class Driver implements Entity {
  const Driver({
    required this.id,
    required this.driverCode,
    required this.name,
    required this.fictionalContact,
    required this.status,
    required this.shiftStartMinutes,
    required this.shiftEndMinutes,
    required this.attendanceStatus,
    required this.completedTripCount,
    required this.safetyChecklistStatus,
    this.assignedVehicleId,
    this.licenceClass = 'LMV (demo)',
    this.notes = '',
    this.licenceNumber = '',
    this.licenceExpiry,
    this.email = '',
    this.address = '',
    this.gender = SelfDeclaredGender.notSpecified,
    this.active = true,
  });

  @override
  final String id;
  final String driverCode;
  final String name;
  final String fictionalContact;
  final DriverStatus status;

  /// Default vehicle for the shift; trips may still use any pool vehicle.
  final String? assignedVehicleId;
  final int shiftStartMinutes;
  final int shiftEndMinutes;
  final AttendanceStatus attendanceStatus;
  final int completedTripCount;
  final SafetyChecklistStatus safetyChecklistStatus;
  final String licenceClass;
  final String notes;

  /// Fictional licence reference. Expired licence blocks assignment.
  final String licenceNumber;
  final DateTime? licenceExpiry;
  final String email;
  final String address;

  /// Optional, self-declared; never used for assignment.
  final SelfDeclaredGender gender;

  /// Deactivated drivers keep history but cannot be assigned.
  final bool active;

  bool licenceValidOn(DateTime day) =>
      licenceExpiry == null ||
      !licenceExpiry!.isBefore(DateTime(day.year, day.month, day.day));

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : ''))
        .toUpperCase();
  }

  Driver copyWith({
    String? name,
    String? fictionalContact,
    DriverStatus? status,
    ValueGetter<String?>? assignedVehicleId,
    int? shiftStartMinutes,
    int? shiftEndMinutes,
    AttendanceStatus? attendanceStatus,
    int? completedTripCount,
    SafetyChecklistStatus? safetyChecklistStatus,
    String? licenceClass,
    String? notes,
    String? licenceNumber,
    ValueGetter<DateTime?>? licenceExpiry,
    String? email,
    String? address,
    SelfDeclaredGender? gender,
    bool? active,
  }) => Driver(
    id: id,
    driverCode: driverCode,
    name: name ?? this.name,
    fictionalContact: fictionalContact ?? this.fictionalContact,
    status: status ?? this.status,
    assignedVehicleId: assignedVehicleId != null
        ? assignedVehicleId()
        : this.assignedVehicleId,
    shiftStartMinutes: shiftStartMinutes ?? this.shiftStartMinutes,
    shiftEndMinutes: shiftEndMinutes ?? this.shiftEndMinutes,
    attendanceStatus: attendanceStatus ?? this.attendanceStatus,
    completedTripCount: completedTripCount ?? this.completedTripCount,
    safetyChecklistStatus: safetyChecklistStatus ?? this.safetyChecklistStatus,
    licenceClass: licenceClass ?? this.licenceClass,
    notes: notes ?? this.notes,
    licenceNumber: licenceNumber ?? this.licenceNumber,
    licenceExpiry: licenceExpiry != null ? licenceExpiry() : this.licenceExpiry,
    email: email ?? this.email,
    address: address ?? this.address,
    gender: gender ?? this.gender,
    active: active ?? this.active,
  );

  @override
  Json toJson() => {
    'id': id,
    'driverCode': driverCode,
    'name': name,
    'fictionalContact': fictionalContact,
    'status': status.name,
    'assignedVehicleId': assignedVehicleId,
    'shiftStartMinutes': shiftStartMinutes,
    'shiftEndMinutes': shiftEndMinutes,
    'attendanceStatus': attendanceStatus.name,
    'completedTripCount': completedTripCount,
    'safetyChecklistStatus': safetyChecklistStatus.name,
    'licenceClass': licenceClass,
    'notes': notes,
    'licenceNumber': licenceNumber,
    'licenceExpiry': dtOut(licenceExpiry),
    'email': email,
    'address': address,
    'gender': gender.name,
    'active': active,
  };

  factory Driver.fromJson(Json j) => Driver(
    id: j['id'] as String,
    driverCode: j['driverCode'] as String,
    name: j['name'] as String,
    fictionalContact: (j['fictionalContact'] as String?) ?? '',
    status: enumByName(DriverStatus.values, j['status'], DriverStatus.offDuty),
    assignedVehicleId: j['assignedVehicleId'] as String?,
    shiftStartMinutes: intReq(j['shiftStartMinutes'], 360),
    shiftEndMinutes: intReq(j['shiftEndMinutes'], 840),
    attendanceStatus: enumByName(
      AttendanceStatus.values,
      j['attendanceStatus'],
      AttendanceStatus.notCheckedIn,
    ),
    completedTripCount: intReq(j['completedTripCount']),
    safetyChecklistStatus: enumByName(
      SafetyChecklistStatus.values,
      j['safetyChecklistStatus'],
      SafetyChecklistStatus.pending,
    ),
    licenceClass: (j['licenceClass'] as String?) ?? 'LMV (demo)',
    notes: (j['notes'] as String?) ?? '',
    licenceNumber: (j['licenceNumber'] as String?) ?? '',
    licenceExpiry: dt(j['licenceExpiry']),
    email: (j['email'] as String?) ?? '',
    address: (j['address'] as String?) ?? '',
    gender: enumByName(
      SelfDeclaredGender.values,
      j['gender'],
      SelfDeclaredGender.notSpecified,
    ),
    active: boolReq(j['active'], true),
  );
}

/// Seat convention: [totalSeats] INCLUDES the driver seat.
/// Passenger capacity = totalSeats − 1 (driver) − guard seats.
@immutable
class Vehicle implements Entity {
  const Vehicle({
    required this.id,
    required this.vehicleCode,
    required this.fictionalRegistration,
    required this.type,
    required this.propulsion,
    required this.totalSeats,
    required this.luxuryClass,
    required this.status,
    required this.odometerKm,
    this.batteryOrFuelPercent,
    this.assignedDriverId,
    this.assignedEmployerId,
    this.requiresSecurityGuard = false,
    this.securityGuardAssigned = false,
    this.notes = '',
    this.lastInspectionAt,
    this.homeParkingId,
    this.model = '',
    this.rcNumber = '',
    this.engineNumber = '',
    this.color = '',
    this.fuelType,
    this.active = true,
    this.diagnosticCodes = const [],
  });

  @override
  final String id;
  final String vehicleCode;
  final String fictionalRegistration;
  final VehicleType type;
  final Propulsion propulsion;
  final int totalSeats;
  final LuxuryClass luxuryClass;
  final VehicleStatus status;
  final double odometerKm;
  final int? batteryOrFuelPercent;
  final String? assignedDriverId;

  /// Null = shared, non-dedicated pool (default).
  final String? assignedEmployerId;
  final bool requiresSecurityGuard;
  final bool securityGuardAssigned;
  final String notes;
  final DateTime? lastInspectionAt;
  final String? homeParkingId;
  final String model;

  /// Synthetic registration-certificate and engine numbers (demo only).
  final String rcNumber;
  final String engineNumber;
  final String color;

  /// Detailed fuel type; null = derived from [propulsion].
  final FuelType? fuelType;

  /// Deactivated vehicles keep history but cannot be assigned.
  final bool active;

  /// Active diagnostic trouble codes (simulated telematics).
  final List<String> diagnosticCodes;

  FuelType get effectiveFuelType =>
      fuelType ??
      switch (propulsion) {
        Propulsion.ev => FuelType.electric,
        Propulsion.hybrid => FuelType.hybrid,
        Propulsion.ice => FuelType.diesel,
      };

  bool get isEv => propulsion == Propulsion.ev;
  String get displayId => 'Vehicle $vehicleCode';

  Vehicle copyWith({
    String? fictionalRegistration,
    VehicleType? type,
    Propulsion? propulsion,
    int? totalSeats,
    LuxuryClass? luxuryClass,
    VehicleStatus? status,
    double? odometerKm,
    ValueGetter<int?>? batteryOrFuelPercent,
    ValueGetter<String?>? assignedDriverId,
    ValueGetter<String?>? assignedEmployerId,
    bool? requiresSecurityGuard,
    bool? securityGuardAssigned,
    String? notes,
    ValueGetter<DateTime?>? lastInspectionAt,
    ValueGetter<String?>? homeParkingId,
    String? model,
    String? rcNumber,
    String? engineNumber,
    String? color,
    ValueGetter<FuelType?>? fuelType,
    bool? active,
    List<String>? diagnosticCodes,
  }) => Vehicle(
    id: id,
    vehicleCode: vehicleCode,
    fictionalRegistration: fictionalRegistration ?? this.fictionalRegistration,
    type: type ?? this.type,
    propulsion: propulsion ?? this.propulsion,
    totalSeats: totalSeats ?? this.totalSeats,
    luxuryClass: luxuryClass ?? this.luxuryClass,
    status: status ?? this.status,
    odometerKm: odometerKm ?? this.odometerKm,
    batteryOrFuelPercent: batteryOrFuelPercent != null
        ? batteryOrFuelPercent()
        : this.batteryOrFuelPercent,
    assignedDriverId: assignedDriverId != null
        ? assignedDriverId()
        : this.assignedDriverId,
    assignedEmployerId: assignedEmployerId != null
        ? assignedEmployerId()
        : this.assignedEmployerId,
    requiresSecurityGuard: requiresSecurityGuard ?? this.requiresSecurityGuard,
    securityGuardAssigned: securityGuardAssigned ?? this.securityGuardAssigned,
    notes: notes ?? this.notes,
    lastInspectionAt: lastInspectionAt != null
        ? lastInspectionAt()
        : this.lastInspectionAt,
    homeParkingId: homeParkingId != null ? homeParkingId() : this.homeParkingId,
    model: model ?? this.model,
    rcNumber: rcNumber ?? this.rcNumber,
    engineNumber: engineNumber ?? this.engineNumber,
    color: color ?? this.color,
    fuelType: fuelType != null ? fuelType() : this.fuelType,
    active: active ?? this.active,
    diagnosticCodes: diagnosticCodes ?? this.diagnosticCodes,
  );

  @override
  Json toJson() => {
    'id': id,
    'vehicleCode': vehicleCode,
    'fictionalRegistration': fictionalRegistration,
    'type': type.name,
    'propulsion': propulsion.name,
    'totalSeats': totalSeats,
    'luxuryClass': luxuryClass.name,
    'status': status.name,
    'odometerKm': odometerKm,
    'batteryOrFuelPercent': batteryOrFuelPercent,
    'assignedDriverId': assignedDriverId,
    'assignedEmployerId': assignedEmployerId,
    'requiresSecurityGuard': requiresSecurityGuard,
    'securityGuardAssigned': securityGuardAssigned,
    'notes': notes,
    'lastInspectionAt': dtOut(lastInspectionAt),
    'homeParkingId': homeParkingId,
    'model': model,
    'rcNumber': rcNumber,
    'engineNumber': engineNumber,
    'color': color,
    'fuelType': fuelType?.name,
    'active': active,
    'diagnosticCodes': diagnosticCodes,
  };

  factory Vehicle.fromJson(Json j) => Vehicle(
    id: j['id'] as String,
    vehicleCode: j['vehicleCode'] as String,
    fictionalRegistration: (j['fictionalRegistration'] as String?) ?? '',
    type: enumByName(VehicleType.values, j['type'], VehicleType.sedan),
    propulsion: enumByName(Propulsion.values, j['propulsion'], Propulsion.ice),
    totalSeats: intReq(j['totalSeats'], 4),
    luxuryClass: enumByName(
      LuxuryClass.values,
      j['luxuryClass'],
      LuxuryClass.standard,
    ),
    status: enumByName(
      VehicleStatus.values,
      j['status'],
      VehicleStatus.available,
    ),
    odometerKm: dblReq(j['odometerKm']),
    batteryOrFuelPercent: intOpt(j['batteryOrFuelPercent']),
    assignedDriverId: j['assignedDriverId'] as String?,
    assignedEmployerId: j['assignedEmployerId'] as String?,
    requiresSecurityGuard: boolReq(j['requiresSecurityGuard']),
    securityGuardAssigned: boolReq(j['securityGuardAssigned']),
    notes: (j['notes'] as String?) ?? '',
    lastInspectionAt: dt(j['lastInspectionAt']),
    homeParkingId: j['homeParkingId'] as String?,
    model: (j['model'] as String?) ?? '',
    rcNumber: (j['rcNumber'] as String?) ?? '',
    engineNumber: (j['engineNumber'] as String?) ?? '',
    color: (j['color'] as String?) ?? '',
    fuelType: j['fuelType'] == null
        ? null
        : enumByName(FuelType.values, j['fuelType'], FuelType.diesel),
    active: boolReq(j['active'], true),
    diagnosticCodes: strList(j['diagnosticCodes']),
  );
}
