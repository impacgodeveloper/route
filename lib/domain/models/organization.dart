import 'package:flutter/foundation.dart';

import '../enums/enums.dart';
import 'json.dart';

/// A configured company shift (e.g. "Morning 09:15–18:15").
/// Times are minutes after local midnight; `end < start` means the shift
/// ends the next day (overnight).
@immutable
class ShiftWindow {
  const ShiftWindow({
    required this.id,
    required this.label,
    required this.startMinutes,
    required this.endMinutes,
  });

  final String id;
  final String label;
  final int startMinutes;
  final int endMinutes;

  bool get overnight => endMinutes < startMinutes;
  int get durationMinutes =>
      overnight ? 1440 - startMinutes + endMinutes : endMinutes - startMinutes;

  ShiftWindow copyWith({String? label, int? startMinutes, int? endMinutes}) =>
      ShiftWindow(
        id: id,
        label: label ?? this.label,
        startMinutes: startMinutes ?? this.startMinutes,
        endMinutes: endMinutes ?? this.endMinutes,
      );

  Json toJson() => {
    'id': id,
    'label': label,
    'startMinutes': startMinutes,
    'endMinutes': endMinutes,
  };

  factory ShiftWindow.fromJson(Json j) => ShiftWindow(
    id: j['id'] as String,
    label: (j['label'] as String?) ?? '',
    startMinutes: intReq(j['startMinutes'], 540),
    endMinutes: intReq(j['endMinutes'], 1080),
  );
}

/// Parent entity (registered company). Employees, trips and billing belong
/// to an employer.
@immutable
class Employer implements Entity {
  const Employer({
    required this.id,
    required this.code,
    required this.name,
    required this.status,
    required this.currency,
    required this.maximumArrivalMinutes,
    required this.defaultDistanceRate,
    required this.preferredEvPercentage,
    required this.vehicleTypePreferences,
    required this.luxuryPreference,
    required this.costPriority,
    required this.punctualityPriority,
    required this.securityGuardPolicyEnabled,
    required this.allowSharedPooling,
    required this.allowCrossEmployerPooling,
    required this.createdAt,
    required this.updatedAt,
    this.pickupToleranceMinutes = 7,
    this.billingCycle = BillingCycle.weekly,
    this.billingActive = true,
    this.additionalChargePerTrip = 0,
    this.shifts = const [],
    this.contactName = '',
    this.contactEmail = '',
  });

  @override
  final String id;
  final String code;
  final String name;
  final RecordStatus status;
  final String currency;

  /// Latest permitted office arrival, minutes after midnight.
  final int maximumArrivalMinutes;

  /// ₹ per km used by billing.
  final double defaultDistanceRate;
  final int preferredEvPercentage;
  final List<VehicleType> vehicleTypePreferences;
  final LuxuryClass luxuryPreference;

  /// 0–100 relative priority used to seed optimizer weights.
  final int costPriority;
  final int punctualityPriority;

  /// Explicit policy only — never inferred from employee data.
  final bool securityGuardPolicyEnabled;
  final bool allowSharedPooling;
  final bool allowCrossEmployerPooling;

  /// Default ± pickup/drop tolerance communicated to employees (minutes).
  /// Distinct from vehicle waiting time and the route safety buffer.
  final int pickupToleranceMinutes;

  /// Invoice grouping cycle. Weeks run Monday–Sunday (local dates).
  final BillingCycle billingCycle;
  final bool billingActive;

  /// Flat additional charge applied to each billed trip line (₹).
  final double additionalChargePerTrip;

  /// Configured company shift windows.
  final List<ShiftWindow> shifts;
  final String contactName;
  final String contactEmail;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isActive => status == RecordStatus.active;

  Employer copyWith({
    String? name,
    RecordStatus? status,
    int? maximumArrivalMinutes,
    double? defaultDistanceRate,
    int? preferredEvPercentage,
    List<VehicleType>? vehicleTypePreferences,
    LuxuryClass? luxuryPreference,
    int? costPriority,
    int? punctualityPriority,
    bool? securityGuardPolicyEnabled,
    bool? allowSharedPooling,
    bool? allowCrossEmployerPooling,
    int? pickupToleranceMinutes,
    BillingCycle? billingCycle,
    bool? billingActive,
    double? additionalChargePerTrip,
    List<ShiftWindow>? shifts,
    String? contactName,
    String? contactEmail,
    DateTime? updatedAt,
  }) => Employer(
    id: id,
    code: code,
    name: name ?? this.name,
    status: status ?? this.status,
    currency: currency,
    maximumArrivalMinutes: maximumArrivalMinutes ?? this.maximumArrivalMinutes,
    defaultDistanceRate: defaultDistanceRate ?? this.defaultDistanceRate,
    preferredEvPercentage: preferredEvPercentage ?? this.preferredEvPercentage,
    vehicleTypePreferences:
        vehicleTypePreferences ?? this.vehicleTypePreferences,
    luxuryPreference: luxuryPreference ?? this.luxuryPreference,
    costPriority: costPriority ?? this.costPriority,
    punctualityPriority: punctualityPriority ?? this.punctualityPriority,
    securityGuardPolicyEnabled:
        securityGuardPolicyEnabled ?? this.securityGuardPolicyEnabled,
    allowSharedPooling: allowSharedPooling ?? this.allowSharedPooling,
    allowCrossEmployerPooling:
        allowCrossEmployerPooling ?? this.allowCrossEmployerPooling,
    pickupToleranceMinutes:
        pickupToleranceMinutes ?? this.pickupToleranceMinutes,
    billingCycle: billingCycle ?? this.billingCycle,
    billingActive: billingActive ?? this.billingActive,
    additionalChargePerTrip:
        additionalChargePerTrip ?? this.additionalChargePerTrip,
    shifts: shifts ?? this.shifts,
    contactName: contactName ?? this.contactName,
    contactEmail: contactEmail ?? this.contactEmail,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  Json toJson() => {
    'id': id,
    'code': code,
    'name': name,
    'status': status.name,
    'currency': currency,
    'maximumArrivalMinutes': maximumArrivalMinutes,
    'defaultDistanceRate': defaultDistanceRate,
    'preferredEvPercentage': preferredEvPercentage,
    'vehicleTypePreferences': vehicleTypePreferences
        .map((e) => e.name)
        .toList(),
    'luxuryPreference': luxuryPreference.name,
    'costPriority': costPriority,
    'punctualityPriority': punctualityPriority,
    'securityGuardPolicyEnabled': securityGuardPolicyEnabled,
    'allowSharedPooling': allowSharedPooling,
    'allowCrossEmployerPooling': allowCrossEmployerPooling,
    'pickupToleranceMinutes': pickupToleranceMinutes,
    'billingCycle': billingCycle.name,
    'billingActive': billingActive,
    'additionalChargePerTrip': additionalChargePerTrip,
    'shifts': shifts.map((s) => s.toJson()).toList(),
    'contactName': contactName,
    'contactEmail': contactEmail,
    'createdAt': dtOut(createdAt),
    'updatedAt': dtOut(updatedAt),
  };

  factory Employer.fromJson(Json j) => Employer(
    id: j['id'] as String,
    code: j['code'] as String,
    name: j['name'] as String,
    status: enumByName(RecordStatus.values, j['status'], RecordStatus.active),
    currency: (j['currency'] as String?) ?? 'INR',
    maximumArrivalMinutes: intReq(j['maximumArrivalMinutes'], 570),
    defaultDistanceRate: dblReq(j['defaultDistanceRate'], 18),
    preferredEvPercentage: intReq(j['preferredEvPercentage'], 50),
    vehicleTypePreferences: strList(
      j['vehicleTypePreferences'],
    ).map((e) => enumByName(VehicleType.values, e, VehicleType.sedan)).toList(),
    luxuryPreference: enumByName(
      LuxuryClass.values,
      j['luxuryPreference'],
      LuxuryClass.standard,
    ),
    costPriority: intReq(j['costPriority'], 50),
    punctualityPriority: intReq(j['punctualityPriority'], 50),
    securityGuardPolicyEnabled: boolReq(j['securityGuardPolicyEnabled']),
    allowSharedPooling: boolReq(j['allowSharedPooling'], true),
    allowCrossEmployerPooling: boolReq(j['allowCrossEmployerPooling']),
    pickupToleranceMinutes: intReq(j['pickupToleranceMinutes'], 7),
    billingCycle: enumByName(
      BillingCycle.values,
      j['billingCycle'],
      BillingCycle.weekly,
    ),
    billingActive: boolReq(j['billingActive'], true),
    additionalChargePerTrip: dblReq(j['additionalChargePerTrip']),
    shifts: (j['shifts'] as List? ?? const [])
        .map((e) => ShiftWindow.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    contactName: (j['contactName'] as String?) ?? '',
    contactEmail: (j['contactEmail'] as String?) ?? '',
    createdAt: dtReq(j['createdAt']),
    updatedAt: dtReq(j['updatedAt']),
  );
}

/// Importance an employee assigns to a soft travel preference.
/// 0 = not important … 3 = very important.
abstract final class TravelPreferenceKeys {
  static const travelTime = 'travelTime';
  static const distance = 'distance';
  static const detour = 'detour';
  static const reliability = 'reliability';
  static const proximity = 'proximity';

  static const all = [travelTime, distance, detour, reliability, proximity];

  /// Keys the local optimizer actually scores. `proximity` has no effect
  /// while pickups are always at the employee's registered source point.
  static const active = [travelTime, distance, detour, reliability];

  static String label(String key) => switch (key) {
    travelTime => 'Shorter travel time',
    distance => 'Shorter travel distance',
    detour => 'Smaller detour',
    reliability => 'Arrival reliability',
    proximity => 'Pickup point closer to me',
    _ => key,
  };

  static const levels = [
    'Not important',
    'Somewhat',
    'Important',
    'Very important',
  ];
}

@immutable
class Employee implements Entity {
  const Employee({
    required this.id,
    required this.employeeCode,
    required this.employerId,
    required this.name,
    required this.fictionalEmail,
    required this.fictionalPhone,
    required this.pickupLocationId,
    required this.destinationId,
    required this.requiredArrivalMinutes,
    required this.shiftLabel,
    required this.transportPreference,
    required this.status,
    required this.optionalDemoPasswordEnabled,
    this.guardEscortRequired = false,
    this.notes = '',
    this.shiftStartMinutes,
    this.shiftEndMinutes,
    this.pickupToleranceMinutes,
    this.gender = SelfDeclaredGender.notSpecified,
    this.travelPreferences = const {},
  });

  @override
  final String id;
  final String employeeCode;
  final String employerId;
  final String name;
  final String fictionalEmail;
  final String fictionalPhone;

  /// Reusable source/pickup location (holds the fictional coordinates).
  final String pickupLocationId;
  final String destinationId;

  /// Required office arrival, minutes after midnight.
  final int requiredArrivalMinutes;
  final String shiftLabel;
  final TransportPreference transportPreference;
  final RecordStatus status;
  final bool optionalDemoPasswordEnabled;

  /// Explicit synthetic policy flag set by an admin. Never inferred.
  final bool guardEscortRequired;
  final String notes;

  /// Work shift (minutes after midnight). `end < start` = overnight.
  final int? shiftStartMinutes;
  final int? shiftEndMinutes;

  /// Per-employee ± pickup/drop tolerance; null = employer default.
  final int? pickupToleranceMinutes;

  /// Optional, self-declared; not used by any algorithm.
  final SelfDeclaredGender gender;

  /// Soft preferences: key (see [TravelPreferenceKeys]) → importance 0–3.
  final Map<String, int> travelPreferences;

  bool get isActive => status == RecordStatus.active;
  String get firstName => name.split(' ').first;
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  bool get overnightShift =>
      shiftStartMinutes != null &&
      shiftEndMinutes != null &&
      shiftEndMinutes! < shiftStartMinutes!;

  /// Office arrival deadline: required arrival, never after shift start.
  int get arrivalDeadlineMinutes =>
      shiftStartMinutes != null && shiftStartMinutes! < requiredArrivalMinutes
      ? shiftStartMinutes!
      : requiredArrivalMinutes;

  int toleranceMinutes(Employer? employer) =>
      pickupToleranceMinutes ?? employer?.pickupToleranceMinutes ?? 7;

  int preference(String key) => travelPreferences[key] ?? 0;
  bool get hasTravelPreferences => travelPreferences.values.any((v) => v > 0);

  Employee copyWith({
    String? name,
    String? fictionalEmail,
    String? fictionalPhone,
    String? pickupLocationId,
    String? destinationId,
    int? requiredArrivalMinutes,
    String? shiftLabel,
    TransportPreference? transportPreference,
    RecordStatus? status,
    bool? optionalDemoPasswordEnabled,
    bool? guardEscortRequired,
    String? notes,
    ValueGetter<int?>? shiftStartMinutes,
    ValueGetter<int?>? shiftEndMinutes,
    ValueGetter<int?>? pickupToleranceMinutes,
    SelfDeclaredGender? gender,
    Map<String, int>? travelPreferences,
  }) => Employee(
    id: id,
    employeeCode: employeeCode,
    employerId: employerId,
    name: name ?? this.name,
    fictionalEmail: fictionalEmail ?? this.fictionalEmail,
    fictionalPhone: fictionalPhone ?? this.fictionalPhone,
    pickupLocationId: pickupLocationId ?? this.pickupLocationId,
    destinationId: destinationId ?? this.destinationId,
    requiredArrivalMinutes:
        requiredArrivalMinutes ?? this.requiredArrivalMinutes,
    shiftLabel: shiftLabel ?? this.shiftLabel,
    transportPreference: transportPreference ?? this.transportPreference,
    status: status ?? this.status,
    optionalDemoPasswordEnabled:
        optionalDemoPasswordEnabled ?? this.optionalDemoPasswordEnabled,
    guardEscortRequired: guardEscortRequired ?? this.guardEscortRequired,
    notes: notes ?? this.notes,
    shiftStartMinutes: shiftStartMinutes != null
        ? shiftStartMinutes()
        : this.shiftStartMinutes,
    shiftEndMinutes: shiftEndMinutes != null
        ? shiftEndMinutes()
        : this.shiftEndMinutes,
    pickupToleranceMinutes: pickupToleranceMinutes != null
        ? pickupToleranceMinutes()
        : this.pickupToleranceMinutes,
    gender: gender ?? this.gender,
    travelPreferences: travelPreferences ?? this.travelPreferences,
  );

  @override
  Json toJson() => {
    'id': id,
    'employeeCode': employeeCode,
    'employerId': employerId,
    'name': name,
    'fictionalEmail': fictionalEmail,
    'fictionalPhone': fictionalPhone,
    'pickupLocationId': pickupLocationId,
    'destinationId': destinationId,
    'requiredArrivalMinutes': requiredArrivalMinutes,
    'shiftLabel': shiftLabel,
    'transportPreference': transportPreference.name,
    'status': status.name,
    'optionalDemoPasswordEnabled': optionalDemoPasswordEnabled,
    'guardEscortRequired': guardEscortRequired,
    'notes': notes,
    'shiftStartMinutes': shiftStartMinutes,
    'shiftEndMinutes': shiftEndMinutes,
    'pickupToleranceMinutes': pickupToleranceMinutes,
    'gender': gender.name,
    'travelPreferences': travelPreferences,
  };

  factory Employee.fromJson(Json j) => Employee(
    id: j['id'] as String,
    employeeCode: j['employeeCode'] as String,
    employerId: j['employerId'] as String,
    name: j['name'] as String,
    fictionalEmail: (j['fictionalEmail'] as String?) ?? '',
    fictionalPhone: (j['fictionalPhone'] as String?) ?? '',
    pickupLocationId: j['pickupLocationId'] as String,
    destinationId: j['destinationId'] as String,
    requiredArrivalMinutes: intReq(j['requiredArrivalMinutes'], 540),
    shiftLabel: (j['shiftLabel'] as String?) ?? '',
    transportPreference: enumByName(
      TransportPreference.values,
      j['transportPreference'],
      TransportPreference.noPreference,
    ),
    status: enumByName(RecordStatus.values, j['status'], RecordStatus.active),
    optionalDemoPasswordEnabled: boolReq(j['optionalDemoPasswordEnabled']),
    guardEscortRequired: boolReq(j['guardEscortRequired']),
    notes: (j['notes'] as String?) ?? '',
    shiftStartMinutes: intOpt(j['shiftStartMinutes']),
    shiftEndMinutes: intOpt(j['shiftEndMinutes']),
    pickupToleranceMinutes: intOpt(j['pickupToleranceMinutes']),
    gender: enumByName(
      SelfDeclaredGender.values,
      j['gender'],
      SelfDeclaredGender.notSpecified,
    ),
    travelPreferences: j['travelPreferences'] is Map
        ? (j['travelPreferences'] as Map).map(
            (k, v) => MapEntry(k.toString(), (v as num).toInt()),
          )
        : const {},
  );
}

@immutable
class Location implements Entity {
  const Location({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    required this.address,
    required this.demoX,
    required this.demoY,
    this.geofenceRadiusM,
    this.employerId,
    this.active = true,
    this.notes = '',
    this.capacity,
    this.latitude,
    this.longitude,
    this.fleetOwned = false,
  });

  @override
  final String id;
  final String code;
  final String name;
  final LocationType type;
  final String address;

  /// Fictional schematic coordinates in kilometres on a demo plane, used by
  /// the routing model. They are NOT real GPS coordinates.
  final double demoX;
  final double demoY;
  final int? geofenceRadiusM;
  final String? employerId;
  final bool active;
  final String notes;

  /// Parking spots/bays (parking/depot only). Not passenger seating.
  final int? capacity;

  /// Fictional demo latitude/longitude (derived from the demo plane).
  final double? latitude;
  final double? longitude;

  /// Parking owned/operated by the fleet.
  final bool fleetOwned;

  String get label => '$code · $name';
  bool get isParking =>
      type == LocationType.parking || type == LocationType.depot;

  Location copyWith({
    String? name,
    LocationType? type,
    String? address,
    double? demoX,
    double? demoY,
    int? geofenceRadiusM,
    bool? active,
    String? notes,
    int? capacity,
    ValueGetter<double?>? latitude,
    ValueGetter<double?>? longitude,
    bool? fleetOwned,
  }) => Location(
    id: id,
    code: code,
    name: name ?? this.name,
    type: type ?? this.type,
    address: address ?? this.address,
    demoX: demoX ?? this.demoX,
    demoY: demoY ?? this.demoY,
    geofenceRadiusM: geofenceRadiusM ?? this.geofenceRadiusM,
    employerId: employerId,
    active: active ?? this.active,
    notes: notes ?? this.notes,
    capacity: capacity ?? this.capacity,
    latitude: latitude != null ? latitude() : this.latitude,
    longitude: longitude != null ? longitude() : this.longitude,
    fleetOwned: fleetOwned ?? this.fleetOwned,
  );

  @override
  Json toJson() => {
    'id': id,
    'code': code,
    'name': name,
    'type': type.name,
    'address': address,
    'demoX': demoX,
    'demoY': demoY,
    'geofenceRadiusM': geofenceRadiusM,
    'employerId': employerId,
    'active': active,
    'notes': notes,
    'capacity': capacity,
    'latitude': latitude,
    'longitude': longitude,
    'fleetOwned': fleetOwned,
  };

  factory Location.fromJson(Json j) => Location(
    id: j['id'] as String,
    code: j['code'] as String,
    name: j['name'] as String,
    type: enumByName(LocationType.values, j['type'], LocationType.pickup),
    address: (j['address'] as String?) ?? '',
    demoX: dblReq(j['demoX']),
    demoY: dblReq(j['demoY']),
    geofenceRadiusM: intOpt(j['geofenceRadiusM']),
    employerId: j['employerId'] as String?,
    active: boolReq(j['active'], true),
    notes: (j['notes'] as String?) ?? '',
    capacity: intOpt(j['capacity']),
    latitude: dbl(j['latitude']),
    longitude: dbl(j['longitude']),
    fleetOwned: boolReq(j['fleetOwned']),
  );
}
