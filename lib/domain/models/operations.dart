import 'package:flutter/foundation.dart';

import '../enums/enums.dart';
import 'json.dart';

@immutable
class Shift implements Entity {
  const Shift({
    required this.id,
    required this.driverId,
    required this.shiftDate,
    required this.scheduledStart,
    required this.scheduledEnd,
    required this.status,
    this.actualCheckIn,
    this.actualCheckOut,
    this.regularizationStatus,
    this.regularizationReason,
    this.notes = '',
    this.handoverNotes,
    this.handoverParkingId,
    this.endException,
    this.endOdometerKm,
  });

  @override
  final String id;
  final String driverId;
  final DateTime shiftDate;
  final DateTime scheduledStart;
  final DateTime scheduledEnd;
  final DateTime? actualCheckIn;
  final DateTime? actualCheckOut;
  final ShiftStatus status;
  final RegularizationStatus? regularizationStatus;
  final String? regularizationReason;
  final String notes;
  final String? handoverNotes;
  final String? handoverParkingId;

  /// Authorized exception used to end a shift with open tasks.
  final String? endException;
  final double? endOdometerKm;

  bool get isOpen =>
      actualCheckIn != null &&
      actualCheckOut == null &&
      status != ShiftStatus.completed;

  /// Minutes late (positive) or early (negative) at check-in.
  int? get checkInDeltaMinutes =>
      actualCheckIn?.difference(scheduledStart).inMinutes;

  Shift copyWith({
    ValueGetter<DateTime?>? actualCheckIn,
    ValueGetter<DateTime?>? actualCheckOut,
    ShiftStatus? status,
    ValueGetter<RegularizationStatus?>? regularizationStatus,
    ValueGetter<String?>? regularizationReason,
    String? notes,
    ValueGetter<String?>? handoverNotes,
    ValueGetter<String?>? handoverParkingId,
    ValueGetter<String?>? endException,
    ValueGetter<double?>? endOdometerKm,
  }) => Shift(
    id: id,
    driverId: driverId,
    shiftDate: shiftDate,
    scheduledStart: scheduledStart,
    scheduledEnd: scheduledEnd,
    actualCheckIn: actualCheckIn != null ? actualCheckIn() : this.actualCheckIn,
    actualCheckOut: actualCheckOut != null
        ? actualCheckOut()
        : this.actualCheckOut,
    status: status ?? this.status,
    regularizationStatus: regularizationStatus != null
        ? regularizationStatus()
        : this.regularizationStatus,
    regularizationReason: regularizationReason != null
        ? regularizationReason()
        : this.regularizationReason,
    notes: notes ?? this.notes,
    handoverNotes: handoverNotes != null ? handoverNotes() : this.handoverNotes,
    handoverParkingId: handoverParkingId != null
        ? handoverParkingId()
        : this.handoverParkingId,
    endException: endException != null ? endException() : this.endException,
    endOdometerKm: endOdometerKm != null ? endOdometerKm() : this.endOdometerKm,
  );

  @override
  Json toJson() => {
    'id': id,
    'driverId': driverId,
    'shiftDate': dtOut(shiftDate),
    'scheduledStart': dtOut(scheduledStart),
    'scheduledEnd': dtOut(scheduledEnd),
    'actualCheckIn': dtOut(actualCheckIn),
    'actualCheckOut': dtOut(actualCheckOut),
    'status': status.name,
    'regularizationStatus': regularizationStatus?.name,
    'regularizationReason': regularizationReason,
    'notes': notes,
    'handoverNotes': handoverNotes,
    'handoverParkingId': handoverParkingId,
    'endException': endException,
    'endOdometerKm': endOdometerKm,
  };

  factory Shift.fromJson(Json j) => Shift(
    id: j['id'] as String,
    driverId: j['driverId'] as String,
    shiftDate: dtReq(j['shiftDate']),
    scheduledStart: dtReq(j['scheduledStart']),
    scheduledEnd: dtReq(j['scheduledEnd']),
    actualCheckIn: dt(j['actualCheckIn']),
    actualCheckOut: dt(j['actualCheckOut']),
    status: enumByName(ShiftStatus.values, j['status'], ShiftStatus.scheduled),
    regularizationStatus: j['regularizationStatus'] == null
        ? null
        : enumByName(
            RegularizationStatus.values,
            j['regularizationStatus'],
            RegularizationStatus.pending,
          ),
    regularizationReason: j['regularizationReason'] as String?,
    notes: (j['notes'] as String?) ?? '',
    handoverNotes: j['handoverNotes'] as String?,
    handoverParkingId: j['handoverParkingId'] as String?,
    endException: j['endException'] as String?,
    endOdometerKm: dbl(j['endOdometerKm']),
  );
}

@immutable
class InspectionItem {
  const InspectionItem({
    required this.key,
    required this.label,
    required this.critical,
    required this.result,
    this.note = '',
  });

  final String key;
  final String label;

  /// A failed critical item blocks trip start.
  final bool critical;
  final CheckResult result;
  final String note;

  InspectionItem copyWith({CheckResult? result, String? note}) =>
      InspectionItem(
        key: key,
        label: label,
        critical: critical,
        result: result ?? this.result,
        note: note ?? this.note,
      );

  Json toJson() => {
    'key': key,
    'label': label,
    'critical': critical,
    'result': result.name,
    'note': note,
  };

  factory InspectionItem.fromJson(Json j) => InspectionItem(
    key: j['key'] as String,
    label: j['label'] as String,
    critical: boolReq(j['critical']),
    result: enumByName(CheckResult.values, j['result'], CheckResult.pass),
    note: (j['note'] as String?) ?? '',
  );
}

@immutable
class Inspection implements Entity {
  const Inspection({
    required this.id,
    required this.vehicleId,
    required this.driverId,
    required this.date,
    required this.items,
    required this.overallStatus,
    required this.submittedAt,
    this.tripId,
    this.notes = '',
    this.photoPath,
    this.defectIncidentId,
  });

  @override
  final String id;
  final String vehicleId;
  final String driverId;
  final String? tripId;
  final DateTime date;
  final List<InspectionItem> items;
  final String notes;

  /// Optional local photo reference (demo; not uploaded anywhere).
  final String? photoPath;
  final InspectionOutcome overallStatus;
  final DateTime submittedAt;
  final String? defectIncidentId;

  List<InspectionItem> get criticalFailures =>
      items.where((i) => i.critical && i.result == CheckResult.fail).toList();
  List<InspectionItem> get failures =>
      items.where((i) => i.result == CheckResult.fail).toList();

  Inspection copyWith({ValueGetter<String?>? defectIncidentId}) => Inspection(
    id: id,
    vehicleId: vehicleId,
    driverId: driverId,
    tripId: tripId,
    date: date,
    items: items,
    notes: notes,
    photoPath: photoPath,
    overallStatus: overallStatus,
    submittedAt: submittedAt,
    defectIncidentId: defectIncidentId != null
        ? defectIncidentId()
        : this.defectIncidentId,
  );

  @override
  Json toJson() => {
    'id': id,
    'vehicleId': vehicleId,
    'driverId': driverId,
    'tripId': tripId,
    'date': dtOut(date),
    'items': items.map((e) => e.toJson()).toList(),
    'notes': notes,
    'photoPath': photoPath,
    'overallStatus': overallStatus.name,
    'submittedAt': dtOut(submittedAt),
    'defectIncidentId': defectIncidentId,
  };

  factory Inspection.fromJson(Json j) => Inspection(
    id: j['id'] as String,
    vehicleId: j['vehicleId'] as String,
    driverId: j['driverId'] as String,
    tripId: j['tripId'] as String?,
    date: dtReq(j['date']),
    items: (j['items'] as List? ?? const [])
        .map((e) => InspectionItem.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    notes: (j['notes'] as String?) ?? '',
    photoPath: j['photoPath'] as String?,
    overallStatus: enumByName(
      InspectionOutcome.values,
      j['overallStatus'],
      InspectionOutcome.needsReview,
    ),
    submittedAt: dtReq(j['submittedAt']),
    defectIncidentId: j['defectIncidentId'] as String?,
  );
}

@immutable
class Incident implements Entity {
  const Incident({
    required this.id,
    required this.reference,
    required this.type,
    required this.description,
    required this.severity,
    required this.status,
    required this.reportedByRole,
    required this.createdAt,
    required this.updatedAt,
    this.tripId,
    this.driverId,
    this.vehicleId,
    this.locationId,
    this.reportedById,
    this.resolutionNotes,
    this.demoLocationLabel,
    this.replacementRequested = false,
    this.isSos = false,
  });

  @override
  final String id;
  final String reference;
  final IncidentType type;
  final String? tripId;
  final String? driverId;
  final String? vehicleId;
  final String? locationId;
  final String description;
  final IncidentSeverity severity;
  final IncidentStatus status;
  final UserRole reportedByRole;
  final String? reportedById;
  final String? resolutionNotes;

  /// Simulated position description — never a real GPS fix.
  final String? demoLocationLabel;
  final bool replacementRequested;
  final bool isSos;
  final DateTime createdAt;
  final DateTime updatedAt;

  Incident copyWith({
    IncidentStatus? status,
    IncidentSeverity? severity,
    ValueGetter<String?>? resolutionNotes,
    bool? replacementRequested,
    DateTime? updatedAt,
  }) => Incident(
    id: id,
    reference: reference,
    type: type,
    tripId: tripId,
    driverId: driverId,
    vehicleId: vehicleId,
    locationId: locationId,
    description: description,
    severity: severity ?? this.severity,
    status: status ?? this.status,
    reportedByRole: reportedByRole,
    reportedById: reportedById,
    resolutionNotes: resolutionNotes != null
        ? resolutionNotes()
        : this.resolutionNotes,
    demoLocationLabel: demoLocationLabel,
    replacementRequested: replacementRequested ?? this.replacementRequested,
    isSos: isSos,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  Json toJson() => {
    'id': id,
    'reference': reference,
    'type': type.name,
    'tripId': tripId,
    'driverId': driverId,
    'vehicleId': vehicleId,
    'locationId': locationId,
    'description': description,
    'severity': severity.name,
    'status': status.name,
    'reportedByRole': reportedByRole.name,
    'reportedById': reportedById,
    'resolutionNotes': resolutionNotes,
    'demoLocationLabel': demoLocationLabel,
    'replacementRequested': replacementRequested,
    'isSos': isSos,
    'createdAt': dtOut(createdAt),
    'updatedAt': dtOut(updatedAt),
  };

  factory Incident.fromJson(Json j) => Incident(
    id: j['id'] as String,
    reference: j['reference'] as String,
    type: enumByName(IncidentType.values, j['type'], IncidentType.other),
    tripId: j['tripId'] as String?,
    driverId: j['driverId'] as String?,
    vehicleId: j['vehicleId'] as String?,
    locationId: j['locationId'] as String?,
    description: (j['description'] as String?) ?? '',
    severity: enumByName(
      IncidentSeverity.values,
      j['severity'],
      IncidentSeverity.medium,
    ),
    status: enumByName(
      IncidentStatus.values,
      j['status'],
      IncidentStatus.submittedDemo,
    ),
    reportedByRole: enumByName(
      UserRole.values,
      j['reportedByRole'],
      UserRole.system,
    ),
    reportedById: j['reportedById'] as String?,
    resolutionNotes: j['resolutionNotes'] as String?,
    demoLocationLabel: j['demoLocationLabel'] as String?,
    replacementRequested: boolReq(j['replacementRequested']),
    isSos: boolReq(j['isSos']),
    createdAt: dtReq(j['createdAt']),
    updatedAt: dtReq(j['updatedAt']),
  );
}

@immutable
class BillingRecord implements Entity {
  const BillingRecord({
    required this.id,
    required this.employerId,
    required this.tripId,
    required this.tripCode,
    required this.completedAt,
    required this.billableDistanceKm,
    required this.ratePerKm,
    required this.additionalCharges,
    required this.adjustment,
    required this.totalAmount,
    required this.status,
    required this.calculationNotes,
    required this.createdAt,
    this.disputeReason,
    this.reviewedAt,
    this.invoiceId,
  });

  @override
  final String id;
  final String employerId;
  final String tripId;
  final String tripCode;
  final DateTime completedAt;
  final double billableDistanceKm;
  final double ratePerKm;
  final double additionalCharges;
  final double adjustment;
  final double totalAmount;
  final BillingStatus status;
  final String calculationNotes;
  final String? disputeReason;
  final DateTime createdAt;
  final DateTime? reviewedAt;

  /// Invoice (billing period) this line was grouped into, if any.
  final String? invoiceId;

  double get distanceCharge => billableDistanceKm * ratePerKm;

  BillingRecord copyWith({
    BillingStatus? status,
    ValueGetter<String?>? disputeReason,
    ValueGetter<DateTime?>? reviewedAt,
    ValueGetter<String?>? invoiceId,
  }) => BillingRecord(
    id: id,
    employerId: employerId,
    tripId: tripId,
    tripCode: tripCode,
    completedAt: completedAt,
    billableDistanceKm: billableDistanceKm,
    ratePerKm: ratePerKm,
    additionalCharges: additionalCharges,
    adjustment: adjustment,
    totalAmount: totalAmount,
    status: status ?? this.status,
    calculationNotes: calculationNotes,
    disputeReason: disputeReason != null ? disputeReason() : this.disputeReason,
    createdAt: createdAt,
    reviewedAt: reviewedAt != null ? reviewedAt() : this.reviewedAt,
    invoiceId: invoiceId != null ? invoiceId() : this.invoiceId,
  );

  @override
  Json toJson() => {
    'id': id,
    'employerId': employerId,
    'tripId': tripId,
    'tripCode': tripCode,
    'completedAt': dtOut(completedAt),
    'billableDistanceKm': billableDistanceKm,
    'ratePerKm': ratePerKm,
    'additionalCharges': additionalCharges,
    'adjustment': adjustment,
    'totalAmount': totalAmount,
    'status': status.name,
    'calculationNotes': calculationNotes,
    'disputeReason': disputeReason,
    'createdAt': dtOut(createdAt),
    'reviewedAt': dtOut(reviewedAt),
    'invoiceId': invoiceId,
  };

  factory BillingRecord.fromJson(Json j) => BillingRecord(
    id: j['id'] as String,
    employerId: j['employerId'] as String,
    tripId: j['tripId'] as String,
    tripCode: j['tripCode'] as String,
    completedAt: dtReq(j['completedAt']),
    billableDistanceKm: dblReq(j['billableDistanceKm']),
    ratePerKm: dblReq(j['ratePerKm']),
    additionalCharges: dblReq(j['additionalCharges']),
    adjustment: dblReq(j['adjustment']),
    totalAmount: dblReq(j['totalAmount']),
    status: enumByName(
      BillingStatus.values,
      j['status'],
      BillingStatus.generated,
    ),
    calculationNotes: (j['calculationNotes'] as String?) ?? '',
    disputeReason: j['disputeReason'] as String?,
    createdAt: dtReq(j['createdAt']),
    reviewedAt: dt(j['reviewedAt']),
    invoiceId: j['invoiceId'] as String?,
  );
}

@immutable
class AppNotification implements Entity {
  const AppNotification({
    required this.id,
    required this.recipientRole,
    required this.title,
    required this.body,
    required this.category,
    required this.createdAt,
    this.recipientId,
    this.readAt,
    this.relatedEntityType,
    this.relatedEntityId,
    this.demoOnly = true,
  });

  @override
  final String id;
  final UserRole recipientRole;

  /// Null = broadcast to everyone with [recipientRole].
  final String? recipientId;
  final String title;
  final String body;
  final NotificationCategory category;
  final DateTime createdAt;
  final DateTime? readAt;

  /// e.g. 'trip', 'booking', 'incident', 'billing', 'vehicle', 'shift'.
  final String? relatedEntityType;
  final String? relatedEntityId;
  final bool demoOnly;

  bool get isRead => readAt != null;

  AppNotification copyWith({ValueGetter<DateTime?>? readAt}) => AppNotification(
    id: id,
    recipientRole: recipientRole,
    recipientId: recipientId,
    title: title,
    body: body,
    category: category,
    createdAt: createdAt,
    readAt: readAt != null ? readAt() : this.readAt,
    relatedEntityType: relatedEntityType,
    relatedEntityId: relatedEntityId,
    demoOnly: demoOnly,
  );

  @override
  Json toJson() => {
    'id': id,
    'recipientRole': recipientRole.name,
    'recipientId': recipientId,
    'title': title,
    'body': body,
    'category': category.name,
    'createdAt': dtOut(createdAt),
    'readAt': dtOut(readAt),
    'relatedEntityType': relatedEntityType,
    'relatedEntityId': relatedEntityId,
    'demoOnly': demoOnly,
  };

  factory AppNotification.fromJson(Json j) => AppNotification(
    id: j['id'] as String,
    recipientRole: enumByName(
      UserRole.values,
      j['recipientRole'],
      UserRole.employee,
    ),
    recipientId: j['recipientId'] as String?,
    title: j['title'] as String,
    body: (j['body'] as String?) ?? '',
    category: enumByName(
      NotificationCategory.values,
      j['category'],
      NotificationCategory.system,
    ),
    createdAt: dtReq(j['createdAt']),
    readAt: dt(j['readAt']),
    relatedEntityType: j['relatedEntityType'] as String?,
    relatedEntityId: j['relatedEntityId'] as String?,
    demoOnly: boolReq(j['demoOnly'], true),
  );
}

@immutable
class SupportTicket implements Entity {
  const SupportTicket({
    required this.id,
    required this.reference,
    required this.createdByRole,
    required this.createdById,
    required this.category,
    required this.subject,
    required this.description,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.relatedTripId,
    this.response,
  });

  @override
  final String id;
  final String reference;
  final UserRole createdByRole;
  final String createdById;
  final TicketCategory category;
  final String subject;
  final String description;
  final String? relatedTripId;
  final TicketStatus status;
  final String? response;
  final DateTime createdAt;
  final DateTime updatedAt;

  SupportTicket copyWith({
    TicketStatus? status,
    ValueGetter<String?>? response,
    DateTime? updatedAt,
  }) => SupportTicket(
    id: id,
    reference: reference,
    createdByRole: createdByRole,
    createdById: createdById,
    category: category,
    subject: subject,
    description: description,
    relatedTripId: relatedTripId,
    status: status ?? this.status,
    response: response != null ? response() : this.response,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  Json toJson() => {
    'id': id,
    'reference': reference,
    'createdByRole': createdByRole.name,
    'createdById': createdById,
    'category': category.name,
    'subject': subject,
    'description': description,
    'relatedTripId': relatedTripId,
    'status': status.name,
    'response': response,
    'createdAt': dtOut(createdAt),
    'updatedAt': dtOut(updatedAt),
  };

  factory SupportTicket.fromJson(Json j) => SupportTicket(
    id: j['id'] as String,
    reference: j['reference'] as String,
    createdByRole: enumByName(
      UserRole.values,
      j['createdByRole'],
      UserRole.employee,
    ),
    createdById: j['createdById'] as String,
    category: enumByName(
      TicketCategory.values,
      j['category'],
      TicketCategory.other,
    ),
    subject: j['subject'] as String,
    description: (j['description'] as String?) ?? '',
    relatedTripId: j['relatedTripId'] as String?,
    status: enumByName(TicketStatus.values, j['status'], TicketStatus.open),
    response: j['response'] as String?,
    createdAt: dtReq(j['createdAt']),
    updatedAt: dtReq(j['updatedAt']),
  );
}

/// Persistent audit record. Local prototype only — not tamper-proof.
/// Never contains passwords, QR/T-PIN secrets or sensitive identifiers.
@immutable
class AuditEvent implements Entity {
  const AuditEvent({
    required this.id,
    required this.actorRole,
    required this.actorId,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.timestamp,
    required this.summary,
    this.outcome = AuditOutcome.success,
    this.changes = '',
    this.reason,
    this.related = const {},
    this.simulated = false,
  });

  @override
  final String id;
  final UserRole actorRole;
  final String actorId;
  final String action;
  final String entityType;
  final String entityId;
  final DateTime timestamp;
  final String summary;
  final AuditOutcome outcome;

  /// Human-readable before → after summary (safe values only).
  final String changes;

  /// Reason/comment for consequential overrides or rejections.
  final String? reason;

  /// Related entity references, e.g. {'trip': 'TR-1001', 'company': 'C1'}.
  final Map<String, String> related;

  /// True when the event concerns simulated behaviour (traffic, SOS, …).
  final bool simulated;

  @override
  Json toJson() => {
    'id': id,
    'actorRole': actorRole.name,
    'actorId': actorId,
    'action': action,
    'entityType': entityType,
    'entityId': entityId,
    'timestamp': dtOut(timestamp),
    'summary': summary,
    'outcome': outcome.name,
    'changes': changes,
    'reason': reason,
    'related': related,
    'simulated': simulated,
  };

  factory AuditEvent.fromJson(Json j) => AuditEvent(
    id: j['id'] as String,
    actorRole: enumByName(UserRole.values, j['actorRole'], UserRole.system),
    actorId: (j['actorId'] as String?) ?? '',
    action: j['action'] as String,
    entityType: j['entityType'] as String,
    entityId: j['entityId'] as String,
    timestamp: dtReq(j['timestamp']),
    summary: (j['summary'] as String?) ?? '',
    outcome: enumByName(
      AuditOutcome.values,
      j['outcome'],
      AuditOutcome.success,
    ),
    changes: (j['changes'] as String?) ?? '',
    reason: j['reason'] as String?,
    related: j['related'] is Map
        ? (j['related'] as Map).map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          )
        : const {},
    simulated: boolReq(j['simulated']),
  );
}

/// Per-identity local preferences (privacy, notifications).
@immutable
class UserSettings implements Entity {
  const UserSettings({
    required this.id,
    this.shareSimulatedLocation = true,
    this.pickupReminders = true,
    this.delayAlerts = true,
    this.serviceNotices = true,
    this.showPhoneToDriver = false,
    this.largeText = false,
  });

  /// Format: `<role>:<identityId>`, e.g. 'employee:E1'.
  @override
  final String id;
  final bool shareSimulatedLocation;
  final bool pickupReminders;
  final bool delayAlerts;
  final bool serviceNotices;
  final bool showPhoneToDriver;
  final bool largeText;

  UserSettings copyWith({
    bool? shareSimulatedLocation,
    bool? pickupReminders,
    bool? delayAlerts,
    bool? serviceNotices,
    bool? showPhoneToDriver,
    bool? largeText,
  }) => UserSettings(
    id: id,
    shareSimulatedLocation:
        shareSimulatedLocation ?? this.shareSimulatedLocation,
    pickupReminders: pickupReminders ?? this.pickupReminders,
    delayAlerts: delayAlerts ?? this.delayAlerts,
    serviceNotices: serviceNotices ?? this.serviceNotices,
    showPhoneToDriver: showPhoneToDriver ?? this.showPhoneToDriver,
    largeText: largeText ?? this.largeText,
  );

  @override
  Json toJson() => {
    'id': id,
    'shareSimulatedLocation': shareSimulatedLocation,
    'pickupReminders': pickupReminders,
    'delayAlerts': delayAlerts,
    'serviceNotices': serviceNotices,
    'showPhoneToDriver': showPhoneToDriver,
    'largeText': largeText,
  };

  factory UserSettings.fromJson(Json j) => UserSettings(
    id: j['id'] as String,
    shareSimulatedLocation: boolReq(j['shareSimulatedLocation'], true),
    pickupReminders: boolReq(j['pickupReminders'], true),
    delayAlerts: boolReq(j['delayAlerts'], true),
    serviceNotices: boolReq(j['serviceNotices'], true),
    showPhoneToDriver: boolReq(j['showPhoneToDriver']),
    largeText: boolReq(j['largeText']),
  );
}
