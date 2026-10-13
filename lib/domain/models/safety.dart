import 'package:flutter/foundation.dart';

import '../enums/enums.dart';
import 'json.dart';

/// Fleet-wide safety, telematics, SOS and matching policy (single row,
/// id "fleet"). Configured by the Fleet Manager.
@immutable
class FleetPolicy implements Entity {
  const FleetPolicy({
    required this.updatedAt,
    this.id = 'fleet',
    this.alcoholMonitoringEnabled = true,
    this.alcoholThresholdMg = 0,
    this.alcoholCheckPoint = AlcoholCheckPoint.shiftStart,
    this.speedLimitKmh = 60,
    this.speedAlertsEnabled = true,
    this.geofenceAlertsEnabled = true,
    this.routeCorridorKm = 2,
    this.sosRecipients = const [
      SosRecipient.fleetManager,
      SosRecipient.companyAdmin,
      SosRecipient.supportTeam,
      SosRecipient.driver,
      SosRecipient.police,
    ],
    this.autoMatchAdhoc = false,
    this.maxAddedDetourMinutes = 25,
    this.carbonCreditPricePerTonne = 1200,
    this.baselineCo2GramsPerKm = 140,
    this.baselineSpeedKmh = 24,
    this.baselineCostPerKm = 16,
  });

  @override
  final String id;

  // ---- Alcohol monitoring ----
  /// When true drivers must pass a breathalyzer test at [alcoholCheckPoint].
  final bool alcoholMonitoringEnabled;

  /// Allowed reading in mg alcohol per 100 ml blood (0 = zero tolerance).
  final double alcoholThresholdMg;
  final AlcoholCheckPoint alcoholCheckPoint;

  // ---- Telematics ----
  final int speedLimitKmh;
  final bool speedAlertsEnabled;
  final bool geofenceAlertsEnabled;

  /// Allowed lateral distance from the planned route (km).
  final double routeCorridorKm;

  // ---- SOS escalation chain ----
  final List<SosRecipient> sosRecipients;

  // ---- Dynamic matching ----
  /// Ad-hoc requests are matched to free seats automatically on submit.
  final bool autoMatchAdhoc;

  /// Max extra minutes a pooled ad-hoc rider may add to an existing trip.
  final int maxAddedDetourMinutes;

  // ---- Analytics assumptions (indicative, editable) ----
  final double carbonCreditPricePerTonne;
  final double baselineCo2GramsPerKm;
  final double baselineSpeedKmh;
  final double baselineCostPerKm;
  final DateTime updatedAt;

  FleetPolicy copyWith({
    bool? alcoholMonitoringEnabled,
    double? alcoholThresholdMg,
    AlcoholCheckPoint? alcoholCheckPoint,
    int? speedLimitKmh,
    bool? speedAlertsEnabled,
    bool? geofenceAlertsEnabled,
    double? routeCorridorKm,
    List<SosRecipient>? sosRecipients,
    bool? autoMatchAdhoc,
    int? maxAddedDetourMinutes,
    double? carbonCreditPricePerTonne,
    double? baselineCo2GramsPerKm,
    double? baselineSpeedKmh,
    double? baselineCostPerKm,
    DateTime? updatedAt,
  }) => FleetPolicy(
    id: id,
    alcoholMonitoringEnabled:
        alcoholMonitoringEnabled ?? this.alcoholMonitoringEnabled,
    alcoholThresholdMg: alcoholThresholdMg ?? this.alcoholThresholdMg,
    alcoholCheckPoint: alcoholCheckPoint ?? this.alcoholCheckPoint,
    speedLimitKmh: speedLimitKmh ?? this.speedLimitKmh,
    speedAlertsEnabled: speedAlertsEnabled ?? this.speedAlertsEnabled,
    geofenceAlertsEnabled: geofenceAlertsEnabled ?? this.geofenceAlertsEnabled,
    routeCorridorKm: routeCorridorKm ?? this.routeCorridorKm,
    sosRecipients: sosRecipients ?? this.sosRecipients,
    autoMatchAdhoc: autoMatchAdhoc ?? this.autoMatchAdhoc,
    maxAddedDetourMinutes: maxAddedDetourMinutes ?? this.maxAddedDetourMinutes,
    carbonCreditPricePerTonne:
        carbonCreditPricePerTonne ?? this.carbonCreditPricePerTonne,
    baselineCo2GramsPerKm: baselineCo2GramsPerKm ?? this.baselineCo2GramsPerKm,
    baselineSpeedKmh: baselineSpeedKmh ?? this.baselineSpeedKmh,
    baselineCostPerKm: baselineCostPerKm ?? this.baselineCostPerKm,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  Json toJson() => {
    'id': id,
    'alcoholMonitoringEnabled': alcoholMonitoringEnabled,
    'alcoholThresholdMg': alcoholThresholdMg,
    'alcoholCheckPoint': alcoholCheckPoint.name,
    'speedLimitKmh': speedLimitKmh,
    'speedAlertsEnabled': speedAlertsEnabled,
    'geofenceAlertsEnabled': geofenceAlertsEnabled,
    'routeCorridorKm': routeCorridorKm,
    'sosRecipients': sosRecipients.map((e) => e.name).toList(),
    'autoMatchAdhoc': autoMatchAdhoc,
    'maxAddedDetourMinutes': maxAddedDetourMinutes,
    'carbonCreditPricePerTonne': carbonCreditPricePerTonne,
    'baselineCo2GramsPerKm': baselineCo2GramsPerKm,
    'baselineSpeedKmh': baselineSpeedKmh,
    'baselineCostPerKm': baselineCostPerKm,
    'updatedAt': dtOut(updatedAt),
  };

  factory FleetPolicy.fromJson(Json j) => FleetPolicy(
    id: (j['id'] as String?) ?? 'fleet',
    alcoholMonitoringEnabled: boolReq(j['alcoholMonitoringEnabled'], true),
    alcoholThresholdMg: dblReq(j['alcoholThresholdMg']),
    alcoholCheckPoint: enumByName(
      AlcoholCheckPoint.values,
      j['alcoholCheckPoint'],
      AlcoholCheckPoint.shiftStart,
    ),
    speedLimitKmh: intReq(j['speedLimitKmh'], 60),
    speedAlertsEnabled: boolReq(j['speedAlertsEnabled'], true),
    geofenceAlertsEnabled: boolReq(j['geofenceAlertsEnabled'], true),
    routeCorridorKm: dblReq(j['routeCorridorKm'], 2),
    sosRecipients: strList(j['sosRecipients'])
        .map(
          (e) => enumByName(SosRecipient.values, e, SosRecipient.fleetManager),
        )
        .toSet()
        .toList(),
    autoMatchAdhoc: boolReq(j['autoMatchAdhoc']),
    maxAddedDetourMinutes: intReq(j['maxAddedDetourMinutes'], 25),
    carbonCreditPricePerTonne: dblReq(j['carbonCreditPricePerTonne'], 1200),
    baselineCo2GramsPerKm: dblReq(j['baselineCo2GramsPerKm'], 140),
    baselineSpeedKmh: dblReq(j['baselineSpeedKmh'], 24),
    baselineCostPerKm: dblReq(j['baselineCostPerKm'], 16),
    updatedAt: dtReq(j['updatedAt']),
  );
}

/// One breathalyzer test. Device readings are SIMULATED in this prototype.
@immutable
class AlcoholTest implements Entity {
  const AlcoholTest({
    required this.id,
    required this.driverId,
    required this.testedAt,
    required this.readingMg,
    required this.thresholdMg,
    required this.result,
    required this.method,
    this.tripId,
    this.vehicleId,
    this.note = '',
    this.clearedBy,
    this.clearedAt,
    this.incidentId,
  });

  @override
  final String id;
  final String driverId;
  final String? tripId;
  final String? vehicleId;
  final DateTime testedAt;

  /// mg alcohol per 100 ml blood (null-free; device error → inconclusive).
  final double readingMg;
  final double thresholdMg;
  final AlcoholResult result;

  /// e.g. "Connected breathalyzer (simulated)" or "Supervisor entry".
  final String method;
  final String note;

  /// Fleet Manager clearance after a failed test (block lifted).
  final String? clearedBy;
  final DateTime? clearedAt;
  final String? incidentId;

  bool get blocking => result != AlcoholResult.pass && clearedAt == null;

  AlcoholTest copyWith({
    ValueGetter<String?>? clearedBy,
    ValueGetter<DateTime?>? clearedAt,
    ValueGetter<String?>? incidentId,
  }) => AlcoholTest(
    id: id,
    driverId: driverId,
    tripId: tripId,
    vehicleId: vehicleId,
    testedAt: testedAt,
    readingMg: readingMg,
    thresholdMg: thresholdMg,
    result: result,
    method: method,
    note: note,
    clearedBy: clearedBy != null ? clearedBy() : this.clearedBy,
    clearedAt: clearedAt != null ? clearedAt() : this.clearedAt,
    incidentId: incidentId != null ? incidentId() : this.incidentId,
  );

  @override
  Json toJson() => {
    'id': id,
    'driverId': driverId,
    'tripId': tripId,
    'vehicleId': vehicleId,
    'testedAt': dtOut(testedAt),
    'readingMg': readingMg,
    'thresholdMg': thresholdMg,
    'result': result.name,
    'method': method,
    'note': note,
    'clearedBy': clearedBy,
    'clearedAt': dtOut(clearedAt),
    'incidentId': incidentId,
  };

  factory AlcoholTest.fromJson(Json j) => AlcoholTest(
    id: j['id'] as String,
    driverId: j['driverId'] as String,
    tripId: j['tripId'] as String?,
    vehicleId: j['vehicleId'] as String?,
    testedAt: dtReq(j['testedAt']),
    readingMg: dblReq(j['readingMg']),
    thresholdMg: dblReq(j['thresholdMg']),
    result: enumByName(
      AlcoholResult.values,
      j['result'],
      AlcoholResult.inconclusive,
    ),
    method: (j['method'] as String?) ?? '',
    note: (j['note'] as String?) ?? '',
    clearedBy: j['clearedBy'] as String?,
    clearedAt: dt(j['clearedAt']),
    incidentId: j['incidentId'] as String?,
  );
}

/// Geofence on the fictional demo plane (km). Circle zones use
/// centre + radius; route corridors apply to every active trip.
@immutable
class Geofence implements Entity {
  const Geofence({
    required this.id,
    required this.name,
    required this.kind,
    required this.createdAt,
    this.centerX = 0,
    this.centerY = 0,
    this.radiusKm = 0,
    this.vehicleIds = const [],
    this.active = true,
    this.notes = '',
  });

  @override
  final String id;
  final String name;
  final GeofenceKind kind;
  final double centerX;
  final double centerY;
  final double radiusKm;

  /// Empty = applies to every vehicle.
  final List<String> vehicleIds;
  final bool active;
  final String notes;
  final DateTime createdAt;

  bool appliesTo(String vehicleId) =>
      vehicleIds.isEmpty || vehicleIds.contains(vehicleId);

  Geofence copyWith({
    String? name,
    double? centerX,
    double? centerY,
    double? radiusKm,
    List<String>? vehicleIds,
    bool? active,
    String? notes,
  }) => Geofence(
    id: id,
    name: name ?? this.name,
    kind: kind,
    centerX: centerX ?? this.centerX,
    centerY: centerY ?? this.centerY,
    radiusKm: radiusKm ?? this.radiusKm,
    vehicleIds: vehicleIds ?? this.vehicleIds,
    active: active ?? this.active,
    notes: notes ?? this.notes,
    createdAt: createdAt,
  );

  @override
  Json toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'centerX': centerX,
    'centerY': centerY,
    'radiusKm': radiusKm,
    'vehicleIds': vehicleIds,
    'active': active,
    'notes': notes,
    'createdAt': dtOut(createdAt),
  };

  factory Geofence.fromJson(Json j) => Geofence(
    id: j['id'] as String,
    name: j['name'] as String,
    kind: enumByName(GeofenceKind.values, j['kind'], GeofenceKind.serviceArea),
    centerX: dblReq(j['centerX']),
    centerY: dblReq(j['centerY']),
    radiusKm: dblReq(j['radiusKm']),
    vehicleIds: strList(j['vehicleIds']),
    active: boolReq(j['active'], true),
    notes: (j['notes'] as String?) ?? '',
    createdAt: dtReq(j['createdAt']),
  );
}

/// Telematics event (simulated): speeding, geofence breach, deviation,
/// diagnostic fault.
@immutable
class VehicleEvent implements Entity {
  const VehicleEvent({
    required this.id,
    required this.vehicleId,
    required this.type,
    required this.occurredAt,
    required this.description,
    this.tripId,
    this.driverId,
    this.geofenceId,
    this.value,
    this.limit,
    this.x,
    this.y,
    this.acknowledgedAt,
    this.incidentId,
    this.simulated = true,
  });

  @override
  final String id;
  final String vehicleId;
  final String? tripId;
  final String? driverId;
  final String? geofenceId;
  final VehicleEventType type;
  final DateTime occurredAt;
  final String description;

  /// Measured value / limit (e.g. 78 km/h vs 60 km/h).
  final double? value;
  final double? limit;
  final double? x;
  final double? y;
  final DateTime? acknowledgedAt;
  final String? incidentId;
  final bool simulated;

  bool get open => acknowledgedAt == null;

  VehicleEvent copyWith({
    ValueGetter<DateTime?>? acknowledgedAt,
    ValueGetter<String?>? incidentId,
  }) => VehicleEvent(
    id: id,
    vehicleId: vehicleId,
    tripId: tripId,
    driverId: driverId,
    geofenceId: geofenceId,
    type: type,
    occurredAt: occurredAt,
    description: description,
    value: value,
    limit: limit,
    x: x,
    y: y,
    acknowledgedAt: acknowledgedAt != null
        ? acknowledgedAt()
        : this.acknowledgedAt,
    incidentId: incidentId != null ? incidentId() : this.incidentId,
    simulated: simulated,
  );

  @override
  Json toJson() => {
    'id': id,
    'vehicleId': vehicleId,
    'tripId': tripId,
    'driverId': driverId,
    'geofenceId': geofenceId,
    'type': type.name,
    'occurredAt': dtOut(occurredAt),
    'description': description,
    'value': value,
    'limit': limit,
    'x': x,
    'y': y,
    'acknowledgedAt': dtOut(acknowledgedAt),
    'incidentId': incidentId,
    'simulated': simulated,
  };

  factory VehicleEvent.fromJson(Json j) => VehicleEvent(
    id: j['id'] as String,
    vehicleId: j['vehicleId'] as String,
    tripId: j['tripId'] as String?,
    driverId: j['driverId'] as String?,
    geofenceId: j['geofenceId'] as String?,
    type: enumByName(
      VehicleEventType.values,
      j['type'],
      VehicleEventType.diagnosticFault,
    ),
    occurredAt: dtReq(j['occurredAt']),
    description: (j['description'] as String?) ?? '',
    value: dbl(j['value']),
    limit: dbl(j['limit']),
    x: dbl(j['x']),
    y: dbl(j['y']),
    acknowledgedAt: dt(j['acknowledgedAt']),
    incidentId: j['incidentId'] as String?,
    simulated: boolReq(j['simulated'], true),
  );
}

/// One leg of an SOS escalation (who was alerted and how).
@immutable
class SosDispatch implements Entity {
  const SosDispatch({
    required this.id,
    required this.incidentId,
    required this.recipient,
    required this.status,
    required this.createdAt,
    this.channel = 'In-app alert',
    this.acknowledgedAt,
    this.acknowledgedBy,
    this.note = '',
  });

  @override
  final String id;
  final String incidentId;
  final SosRecipient recipient;
  final SosDispatchStatus status;

  /// "In-app alert", "Phone call", "Emergency services".
  final String channel;
  final DateTime createdAt;
  final DateTime? acknowledgedAt;
  final String? acknowledgedBy;
  final String note;

  SosDispatch copyWith({
    SosDispatchStatus? status,
    ValueGetter<DateTime?>? acknowledgedAt,
    ValueGetter<String?>? acknowledgedBy,
  }) => SosDispatch(
    id: id,
    incidentId: incidentId,
    recipient: recipient,
    status: status ?? this.status,
    channel: channel,
    createdAt: createdAt,
    acknowledgedAt: acknowledgedAt != null
        ? acknowledgedAt()
        : this.acknowledgedAt,
    acknowledgedBy: acknowledgedBy != null
        ? acknowledgedBy()
        : this.acknowledgedBy,
    note: note,
  );

  @override
  Json toJson() => {
    'id': id,
    'incidentId': incidentId,
    'recipient': recipient.name,
    'status': status.name,
    'channel': channel,
    'createdAt': dtOut(createdAt),
    'acknowledgedAt': dtOut(acknowledgedAt),
    'acknowledgedBy': acknowledgedBy,
    'note': note,
  };

  factory SosDispatch.fromJson(Json j) => SosDispatch(
    id: j['id'] as String,
    incidentId: j['incidentId'] as String,
    recipient: enumByName(
      SosRecipient.values,
      j['recipient'],
      SosRecipient.fleetManager,
    ),
    status: enumByName(
      SosDispatchStatus.values,
      j['status'],
      SosDispatchStatus.alertedInApp,
    ),
    channel: (j['channel'] as String?) ?? 'In-app alert',
    createdAt: dtReq(j['createdAt']),
    acknowledgedAt: dt(j['acknowledgedAt']),
    acknowledgedBy: j['acknowledgedBy'] as String?,
    note: (j['note'] as String?) ?? '',
  );
}
