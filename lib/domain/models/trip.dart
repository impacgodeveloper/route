import 'package:flutter/foundation.dart';

import '../enums/enums.dart';
import 'json.dart';

/// Immutable history entry kept whenever a trip is (re)assigned.
@immutable
class AssignmentRecord {
  const AssignmentRecord({
    required this.at,
    required this.actorRole,
    this.driverId,
    this.vehicleId,
    this.reason = '',
  });

  final DateTime at;
  final UserRole actorRole;
  final String? driverId;
  final String? vehicleId;
  final String reason;

  Json toJson() => {
    'at': dtOut(at),
    'actorRole': actorRole.name,
    'driverId': driverId,
    'vehicleId': vehicleId,
    'reason': reason,
  };

  factory AssignmentRecord.fromJson(Json j) => AssignmentRecord(
    at: dtReq(j['at']),
    actorRole: enumByName(UserRole.values, j['actorRole'], UserRole.system),
    driverId: j['driverId'] as String?,
    vehicleId: j['vehicleId'] as String?,
    reason: (j['reason'] as String?) ?? '',
  );
}

@immutable
class Trip implements Entity {
  const Trip({
    required this.id,
    required this.tripCode,
    required this.employerId,
    required this.serviceDate,
    required this.scheduledStart,
    required this.originLocationId,
    required this.destinationLocationId,
    required this.employeeIds,
    required this.orderedStopIds,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.assignedDriverId,
    this.assignedVehicleId,
    this.routeId,
    this.actualStart,
    this.scheduledArrival,
    this.actualArrival,
    this.boardedPassengerIds = const [],
    this.alightedPassengerIds = const [],
    this.noShowPassengerIds = const [],
    this.distanceKm,
    this.estimatedDurationMinutes,
    this.actualDurationMinutes,
    this.optimizationRunId,
    this.delayReason,
    this.completionNotes,
    this.completionException,
    this.billableStatus = BillableStatus.notYetBillable,
    this.guardRequired = false,
    this.instructions = '',
    this.startOdometerKm,
    this.endOdometerKm,
    this.inspectionId,
    this.assignmentHistory = const [],
    this.cancellationReason,
    this.guardReference,
    this.absentEmployeeIds = const [],
  });

  @override
  final String id;
  final String tripCode;
  final String employerId;
  final String? assignedDriverId;
  final String? assignedVehicleId;
  final String? routeId;
  final DateTime serviceDate;
  final DateTime scheduledStart;
  final DateTime? actualStart;
  final DateTime? scheduledArrival;
  final DateTime? actualArrival;
  final String originLocationId;
  final String destinationLocationId;
  final List<String> employeeIds;

  /// Location IDs in visiting order (pickups then drops).
  final List<String> orderedStopIds;
  final List<String> boardedPassengerIds;
  final List<String> alightedPassengerIds;
  final List<String> noShowPassengerIds;
  final double? distanceKm;
  final int? estimatedDurationMinutes;
  final int? actualDurationMinutes;
  final TripStatus status;
  final String? optimizationRunId;
  final String? delayReason;
  final String? completionNotes;

  /// Authorized exception recorded when completion rules were overridden.
  final String? completionException;
  final BillableStatus billableStatus;

  /// Explicit per-trip guard requirement (policy driven, never inferred).
  final bool guardRequired;
  final String instructions;
  final double? startOdometerKm;
  final double? endOdometerKm;
  final String? inspectionId;
  final List<AssignmentRecord> assignmentHistory;
  final String? cancellationReason;

  /// Security guard assigned to this trip (name/ID reference, demo).
  final String? guardReference;

  /// Employees who reported "not travelling" (seat released; history kept).
  final List<String> absentEmployeeIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  int get expectedPassengerCount => employeeIds.length;
  bool get isAssigned => assignedDriverId != null && assignedVehicleId != null;

  /// End of the occupied time window used for conflict checks.
  DateTime get windowEnd =>
      actualArrival ??
      scheduledArrival ??
      scheduledStart.add(Duration(minutes: estimatedDurationMinutes ?? 90));

  Trip copyWith({
    ValueGetter<String?>? assignedDriverId,
    ValueGetter<String?>? assignedVehicleId,
    ValueGetter<String?>? routeId,
    DateTime? serviceDate,
    DateTime? scheduledStart,
    ValueGetter<DateTime?>? actualStart,
    ValueGetter<DateTime?>? scheduledArrival,
    ValueGetter<DateTime?>? actualArrival,
    String? originLocationId,
    String? destinationLocationId,
    List<String>? employeeIds,
    List<String>? orderedStopIds,
    List<String>? boardedPassengerIds,
    List<String>? alightedPassengerIds,
    List<String>? noShowPassengerIds,
    ValueGetter<double?>? distanceKm,
    ValueGetter<int?>? estimatedDurationMinutes,
    ValueGetter<int?>? actualDurationMinutes,
    TripStatus? status,
    ValueGetter<String?>? optimizationRunId,
    ValueGetter<String?>? delayReason,
    ValueGetter<String?>? completionNotes,
    ValueGetter<String?>? completionException,
    BillableStatus? billableStatus,
    bool? guardRequired,
    String? instructions,
    ValueGetter<double?>? startOdometerKm,
    ValueGetter<double?>? endOdometerKm,
    ValueGetter<String?>? inspectionId,
    List<AssignmentRecord>? assignmentHistory,
    ValueGetter<String?>? cancellationReason,
    ValueGetter<String?>? guardReference,
    List<String>? absentEmployeeIds,
    DateTime? updatedAt,
  }) => Trip(
    id: id,
    tripCode: tripCode,
    employerId: employerId,
    assignedDriverId: assignedDriverId != null
        ? assignedDriverId()
        : this.assignedDriverId,
    assignedVehicleId: assignedVehicleId != null
        ? assignedVehicleId()
        : this.assignedVehicleId,
    routeId: routeId != null ? routeId() : this.routeId,
    serviceDate: serviceDate ?? this.serviceDate,
    scheduledStart: scheduledStart ?? this.scheduledStart,
    actualStart: actualStart != null ? actualStart() : this.actualStart,
    scheduledArrival: scheduledArrival != null
        ? scheduledArrival()
        : this.scheduledArrival,
    actualArrival: actualArrival != null ? actualArrival() : this.actualArrival,
    originLocationId: originLocationId ?? this.originLocationId,
    destinationLocationId: destinationLocationId ?? this.destinationLocationId,
    employeeIds: employeeIds ?? this.employeeIds,
    orderedStopIds: orderedStopIds ?? this.orderedStopIds,
    boardedPassengerIds: boardedPassengerIds ?? this.boardedPassengerIds,
    alightedPassengerIds: alightedPassengerIds ?? this.alightedPassengerIds,
    noShowPassengerIds: noShowPassengerIds ?? this.noShowPassengerIds,
    distanceKm: distanceKm != null ? distanceKm() : this.distanceKm,
    estimatedDurationMinutes: estimatedDurationMinutes != null
        ? estimatedDurationMinutes()
        : this.estimatedDurationMinutes,
    actualDurationMinutes: actualDurationMinutes != null
        ? actualDurationMinutes()
        : this.actualDurationMinutes,
    status: status ?? this.status,
    optimizationRunId: optimizationRunId != null
        ? optimizationRunId()
        : this.optimizationRunId,
    delayReason: delayReason != null ? delayReason() : this.delayReason,
    completionNotes: completionNotes != null
        ? completionNotes()
        : this.completionNotes,
    completionException: completionException != null
        ? completionException()
        : this.completionException,
    billableStatus: billableStatus ?? this.billableStatus,
    guardRequired: guardRequired ?? this.guardRequired,
    instructions: instructions ?? this.instructions,
    startOdometerKm: startOdometerKm != null
        ? startOdometerKm()
        : this.startOdometerKm,
    endOdometerKm: endOdometerKm != null ? endOdometerKm() : this.endOdometerKm,
    inspectionId: inspectionId != null ? inspectionId() : this.inspectionId,
    assignmentHistory: assignmentHistory ?? this.assignmentHistory,
    cancellationReason: cancellationReason != null
        ? cancellationReason()
        : this.cancellationReason,
    guardReference: guardReference != null
        ? guardReference()
        : this.guardReference,
    absentEmployeeIds: absentEmployeeIds ?? this.absentEmployeeIds,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  Json toJson() => {
    'id': id,
    'tripCode': tripCode,
    'employerId': employerId,
    'assignedDriverId': assignedDriverId,
    'assignedVehicleId': assignedVehicleId,
    'routeId': routeId,
    'serviceDate': dtOut(serviceDate),
    'scheduledStart': dtOut(scheduledStart),
    'actualStart': dtOut(actualStart),
    'scheduledArrival': dtOut(scheduledArrival),
    'actualArrival': dtOut(actualArrival),
    'originLocationId': originLocationId,
    'destinationLocationId': destinationLocationId,
    'employeeIds': employeeIds,
    'orderedStopIds': orderedStopIds,
    'boardedPassengerIds': boardedPassengerIds,
    'alightedPassengerIds': alightedPassengerIds,
    'noShowPassengerIds': noShowPassengerIds,
    'distanceKm': distanceKm,
    'estimatedDurationMinutes': estimatedDurationMinutes,
    'actualDurationMinutes': actualDurationMinutes,
    'status': status.name,
    'optimizationRunId': optimizationRunId,
    'delayReason': delayReason,
    'completionNotes': completionNotes,
    'completionException': completionException,
    'billableStatus': billableStatus.name,
    'guardRequired': guardRequired,
    'instructions': instructions,
    'startOdometerKm': startOdometerKm,
    'endOdometerKm': endOdometerKm,
    'inspectionId': inspectionId,
    'assignmentHistory': assignmentHistory.map((e) => e.toJson()).toList(),
    'cancellationReason': cancellationReason,
    'guardReference': guardReference,
    'absentEmployeeIds': absentEmployeeIds,
    'createdAt': dtOut(createdAt),
    'updatedAt': dtOut(updatedAt),
  };

  factory Trip.fromJson(Json j) => Trip(
    id: j['id'] as String,
    tripCode: j['tripCode'] as String,
    employerId: j['employerId'] as String,
    assignedDriverId: j['assignedDriverId'] as String?,
    assignedVehicleId: j['assignedVehicleId'] as String?,
    routeId: j['routeId'] as String?,
    serviceDate: dtReq(j['serviceDate']),
    scheduledStart: dtReq(j['scheduledStart']),
    actualStart: dt(j['actualStart']),
    scheduledArrival: dt(j['scheduledArrival']),
    actualArrival: dt(j['actualArrival']),
    originLocationId: j['originLocationId'] as String,
    destinationLocationId: j['destinationLocationId'] as String,
    employeeIds: strList(j['employeeIds']),
    orderedStopIds: strList(j['orderedStopIds']),
    boardedPassengerIds: strList(j['boardedPassengerIds']),
    alightedPassengerIds: strList(j['alightedPassengerIds']),
    noShowPassengerIds: strList(j['noShowPassengerIds']),
    distanceKm: dbl(j['distanceKm']),
    estimatedDurationMinutes: intOpt(j['estimatedDurationMinutes']),
    actualDurationMinutes: intOpt(j['actualDurationMinutes']),
    status: enumByName(TripStatus.values, j['status'], TripStatus.draft),
    optimizationRunId: j['optimizationRunId'] as String?,
    delayReason: j['delayReason'] as String?,
    completionNotes: j['completionNotes'] as String?,
    completionException: j['completionException'] as String?,
    billableStatus: enumByName(
      BillableStatus.values,
      j['billableStatus'],
      BillableStatus.notYetBillable,
    ),
    guardRequired: boolReq(j['guardRequired']),
    instructions: (j['instructions'] as String?) ?? '',
    startOdometerKm: dbl(j['startOdometerKm']),
    endOdometerKm: dbl(j['endOdometerKm']),
    inspectionId: j['inspectionId'] as String?,
    assignmentHistory: (j['assignmentHistory'] as List? ?? const [])
        .map((e) => AssignmentRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    cancellationReason: j['cancellationReason'] as String?,
    guardReference: j['guardReference'] as String?,
    absentEmployeeIds: strList(j['absentEmployeeIds']),
    createdAt: dtReq(j['createdAt']),
    updatedAt: dtReq(j['updatedAt']),
  );
}

/// A planned route instance. Each trip owns one route so stop progress is
/// tracked independently per trip.
@immutable
class TripRoute implements Entity {
  const TripRoute({
    required this.id,
    required this.routeCode,
    required this.name,
    required this.stopIds,
    required this.estimatedDistanceKm,
    required this.estimatedDurationMinutes,
    required this.status,
    this.employerId,
    this.optimizationRunId,
    this.variant = RouteVariant.internalRoads,
  });

  @override
  final String id;
  final String routeCode;
  final String name;
  final String? employerId;

  /// RouteStop IDs in order.
  final List<String> stopIds;
  final double estimatedDistanceKm;
  final int estimatedDurationMinutes;
  final RouteStatus status;
  final String? optimizationRunId;
  final RouteVariant variant;

  TripRoute copyWith({
    String? name,
    List<String>? stopIds,
    double? estimatedDistanceKm,
    int? estimatedDurationMinutes,
    RouteStatus? status,
    ValueGetter<String?>? optimizationRunId,
    RouteVariant? variant,
  }) => TripRoute(
    id: id,
    routeCode: routeCode,
    name: name ?? this.name,
    employerId: employerId,
    stopIds: stopIds ?? this.stopIds,
    estimatedDistanceKm: estimatedDistanceKm ?? this.estimatedDistanceKm,
    estimatedDurationMinutes:
        estimatedDurationMinutes ?? this.estimatedDurationMinutes,
    status: status ?? this.status,
    optimizationRunId: optimizationRunId != null
        ? optimizationRunId()
        : this.optimizationRunId,
    variant: variant ?? this.variant,
  );

  @override
  Json toJson() => {
    'id': id,
    'routeCode': routeCode,
    'name': name,
    'employerId': employerId,
    'stopIds': stopIds,
    'estimatedDistanceKm': estimatedDistanceKm,
    'estimatedDurationMinutes': estimatedDurationMinutes,
    'status': status.name,
    'optimizationRunId': optimizationRunId,
    'variant': variant.name,
  };

  factory TripRoute.fromJson(Json j) => TripRoute(
    id: j['id'] as String,
    routeCode: j['routeCode'] as String,
    name: j['name'] as String,
    employerId: j['employerId'] as String?,
    stopIds: strList(j['stopIds']),
    estimatedDistanceKm: dblReq(j['estimatedDistanceKm']),
    estimatedDurationMinutes: intReq(j['estimatedDurationMinutes']),
    status: enumByName(RouteStatus.values, j['status'], RouteStatus.planned),
    optimizationRunId: j['optimizationRunId'] as String?,
    variant: enumByName(
      RouteVariant.values,
      j['variant'],
      RouteVariant.internalRoads,
    ),
  );
}

@immutable
class RouteStop implements Entity {
  const RouteStop({
    required this.id,
    required this.routeId,
    required this.locationId,
    required this.sequence,
    required this.kind,
    required this.plannedArrival,
    required this.boardingEmployeeIds,
    required this.alightingEmployeeIds,
    required this.status,
    this.actualArrival,
    this.departedAt,
    this.skipReason,
    this.skipAuthorizedBy,
    this.issueNote,
  });

  @override
  final String id;
  final String routeId;
  final String locationId;
  final int sequence;
  final StopKind kind;
  final DateTime plannedArrival;
  final DateTime? actualArrival;
  final DateTime? departedAt;
  final List<String> boardingEmployeeIds;
  final List<String> alightingEmployeeIds;
  final StopStatus status;
  final String? skipReason;
  final String? skipAuthorizedBy;
  final String? issueNote;

  int get expectedBoardingCount => boardingEmployeeIds.length;
  int get expectedAlightingCount => alightingEmployeeIds.length;
  bool get isDone =>
      status == StopStatus.completed || status == StopStatus.skipped;

  RouteStop copyWith({
    int? sequence,
    DateTime? plannedArrival,
    ValueGetter<DateTime?>? actualArrival,
    ValueGetter<DateTime?>? departedAt,
    List<String>? boardingEmployeeIds,
    List<String>? alightingEmployeeIds,
    StopStatus? status,
    ValueGetter<String?>? skipReason,
    ValueGetter<String?>? skipAuthorizedBy,
    ValueGetter<String?>? issueNote,
  }) => RouteStop(
    id: id,
    routeId: routeId,
    locationId: locationId,
    sequence: sequence ?? this.sequence,
    kind: kind,
    plannedArrival: plannedArrival ?? this.plannedArrival,
    actualArrival: actualArrival != null ? actualArrival() : this.actualArrival,
    departedAt: departedAt != null ? departedAt() : this.departedAt,
    boardingEmployeeIds: boardingEmployeeIds ?? this.boardingEmployeeIds,
    alightingEmployeeIds: alightingEmployeeIds ?? this.alightingEmployeeIds,
    status: status ?? this.status,
    skipReason: skipReason != null ? skipReason() : this.skipReason,
    skipAuthorizedBy: skipAuthorizedBy != null
        ? skipAuthorizedBy()
        : this.skipAuthorizedBy,
    issueNote: issueNote != null ? issueNote() : this.issueNote,
  );

  @override
  Json toJson() => {
    'id': id,
    'routeId': routeId,
    'locationId': locationId,
    'sequence': sequence,
    'kind': kind.name,
    'plannedArrival': dtOut(plannedArrival),
    'actualArrival': dtOut(actualArrival),
    'departedAt': dtOut(departedAt),
    'boardingEmployeeIds': boardingEmployeeIds,
    'alightingEmployeeIds': alightingEmployeeIds,
    'expectedBoardingCount': expectedBoardingCount,
    'expectedAlightingCount': expectedAlightingCount,
    'status': status.name,
    'skipReason': skipReason,
    'skipAuthorizedBy': skipAuthorizedBy,
    'issueNote': issueNote,
  };

  factory RouteStop.fromJson(Json j) => RouteStop(
    id: j['id'] as String,
    routeId: j['routeId'] as String,
    locationId: j['locationId'] as String,
    sequence: intReq(j['sequence']),
    kind: enumByName(StopKind.values, j['kind'], StopKind.pickup),
    plannedArrival: dtReq(j['plannedArrival']),
    actualArrival: dt(j['actualArrival']),
    departedAt: dt(j['departedAt']),
    boardingEmployeeIds: strList(j['boardingEmployeeIds']),
    alightingEmployeeIds: strList(j['alightingEmployeeIds']),
    status: enumByName(StopStatus.values, j['status'], StopStatus.upcoming),
    skipReason: j['skipReason'] as String?,
    skipAuthorizedBy: j['skipAuthorizedBy'] as String?,
    issueNote: j['issueNote'] as String?,
  );
}

@immutable
class Booking implements Entity {
  const Booking({
    required this.id,
    required this.reference,
    required this.employeeId,
    required this.requestedPickupLocationId,
    required this.requestedDestinationId,
    required this.requestedDate,
    required this.requestedArrivalMinutes,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.tripId,
    this.notes = '',
    this.preference = TransportPreference.noPreference,
    this.decisionReason,
  });

  @override
  final String id;
  final String reference;
  final String employeeId;
  final String? tripId;
  final String requestedPickupLocationId;
  final String requestedDestinationId;
  final DateTime requestedDate;
  final int requestedArrivalMinutes;
  final BookingStatus status;
  final String notes;
  final TransportPreference preference;
  final String? decisionReason;
  final DateTime createdAt;
  final DateTime updatedAt;

  Booking copyWith({
    ValueGetter<String?>? tripId,
    BookingStatus? status,
    String? notes,
    ValueGetter<String?>? decisionReason,
    DateTime? updatedAt,
  }) => Booking(
    id: id,
    reference: reference,
    employeeId: employeeId,
    tripId: tripId != null ? tripId() : this.tripId,
    requestedPickupLocationId: requestedPickupLocationId,
    requestedDestinationId: requestedDestinationId,
    requestedDate: requestedDate,
    requestedArrivalMinutes: requestedArrivalMinutes,
    status: status ?? this.status,
    notes: notes ?? this.notes,
    preference: preference,
    decisionReason: decisionReason != null
        ? decisionReason()
        : this.decisionReason,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  Json toJson() => {
    'id': id,
    'reference': reference,
    'employeeId': employeeId,
    'tripId': tripId,
    'requestedPickupLocationId': requestedPickupLocationId,
    'requestedDestinationId': requestedDestinationId,
    'requestedDate': dtOut(requestedDate),
    'requestedArrivalMinutes': requestedArrivalMinutes,
    'status': status.name,
    'notes': notes,
    'preference': preference.name,
    'decisionReason': decisionReason,
    'createdAt': dtOut(createdAt),
    'updatedAt': dtOut(updatedAt),
  };

  factory Booking.fromJson(Json j) => Booking(
    id: j['id'] as String,
    reference: (j['reference'] as String?) ?? j['id'] as String,
    employeeId: j['employeeId'] as String,
    tripId: j['tripId'] as String?,
    requestedPickupLocationId: j['requestedPickupLocationId'] as String,
    requestedDestinationId: j['requestedDestinationId'] as String,
    requestedDate: dtReq(j['requestedDate']),
    requestedArrivalMinutes: intReq(j['requestedArrivalMinutes'], 540),
    status: enumByName(
      BookingStatus.values,
      j['status'],
      BookingStatus.requested,
    ),
    notes: (j['notes'] as String?) ?? '',
    preference: enumByName(
      TransportPreference.values,
      j['preference'],
      TransportPreference.noPreference,
    ),
    decisionReason: j['decisionReason'] as String?,
    createdAt: dtReq(j['createdAt']),
    updatedAt: dtReq(j['updatedAt']),
  );
}

@immutable
class PassengerEvent implements Entity {
  const PassengerEvent({
    required this.id,
    required this.tripId,
    required this.employeeId,
    required this.eventType,
    required this.verificationMethod,
    required this.verificationStatus,
    required this.eventTime,
    this.stopId,
    this.note = '',
    this.authorizedBy,
  });

  @override
  final String id;
  final String tripId;
  final String employeeId;
  final String? stopId;
  final PassengerEventType eventType;
  final VerificationMethod verificationMethod;
  final VerificationStatus verificationStatus;
  final DateTime eventTime;

  /// Never contains the QR payload or T-PIN.
  final String note;
  final String? authorizedBy;

  @override
  Json toJson() => {
    'id': id,
    'tripId': tripId,
    'employeeId': employeeId,
    'stopId': stopId,
    'eventType': eventType.name,
    'verificationMethod': verificationMethod.name,
    'verificationStatus': verificationStatus.name,
    'eventTime': dtOut(eventTime),
    'note': note,
    'authorizedBy': authorizedBy,
  };

  factory PassengerEvent.fromJson(Json j) => PassengerEvent(
    id: j['id'] as String,
    tripId: j['tripId'] as String,
    employeeId: j['employeeId'] as String,
    stopId: j['stopId'] as String?,
    eventType: enumByName(
      PassengerEventType.values,
      j['eventType'],
      PassengerEventType.boarded,
    ),
    verificationMethod: enumByName(
      VerificationMethod.values,
      j['verificationMethod'],
      VerificationMethod.manualAuthorized,
    ),
    verificationStatus: enumByName(
      VerificationStatus.values,
      j['verificationStatus'],
      VerificationStatus.verified,
    ),
    eventTime: dtReq(j['eventTime']),
    note: (j['note'] as String?) ?? '',
    authorizedBy: j['authorizedBy'] as String?,
  );
}
