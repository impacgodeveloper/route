import 'package:flutter/foundation.dart';

import '../enums/enums.dart';
import 'json.dart';

/// Invoice for one employer billing period. Groups per-trip billing lines
/// (`BillingRecord`) without changing the per-trip model. Generated
/// locally — never emailed, submitted or paid.
@immutable
class Invoice implements Entity {
  const Invoice({
    required this.id,
    required this.reference,
    required this.employerId,
    required this.cycle,
    required this.periodStart,
    required this.periodEnd,
    required this.sequence,
    required this.billingRecordIds,
    required this.tripIds,
    required this.distanceKm,
    required this.distanceCharges,
    required this.additionalCharges,
    required this.adjustments,
    required this.total,
    required this.status,
    required this.generatedAt,
    this.notes = '',
    this.disputeReason,
    this.reviewedAt,
  });

  @override
  final String id;
  final String reference;
  final String employerId;
  final BillingCycle cycle;

  /// Inclusive local business dates.
  final DateTime periodStart;
  final DateTime periodEnd;

  /// 1 = first invoice for the period; 2+ = supplementary (late lines).
  final int sequence;
  final List<String> billingRecordIds;
  final List<String> tripIds;
  final double distanceKm;
  final double distanceCharges;
  final double additionalCharges;
  final double adjustments;
  final double total;
  final InvoiceStatus status;
  final DateTime generatedAt;
  final String notes;
  final String? disputeReason;
  final DateTime? reviewedAt;

  String get periodKey =>
      '${periodStart.year}-${periodStart.month}-${periodStart.day}';

  Invoice copyWith({
    InvoiceStatus? status,
    ValueGetter<String?>? disputeReason,
    ValueGetter<DateTime?>? reviewedAt,
  }) => Invoice(
    id: id,
    reference: reference,
    employerId: employerId,
    cycle: cycle,
    periodStart: periodStart,
    periodEnd: periodEnd,
    sequence: sequence,
    billingRecordIds: billingRecordIds,
    tripIds: tripIds,
    distanceKm: distanceKm,
    distanceCharges: distanceCharges,
    additionalCharges: additionalCharges,
    adjustments: adjustments,
    total: total,
    status: status ?? this.status,
    generatedAt: generatedAt,
    notes: notes,
    disputeReason: disputeReason != null ? disputeReason() : this.disputeReason,
    reviewedAt: reviewedAt != null ? reviewedAt() : this.reviewedAt,
  );

  @override
  Json toJson() => {
    'id': id,
    'reference': reference,
    'employerId': employerId,
    'cycle': cycle.name,
    'periodStart': dtOut(periodStart),
    'periodEnd': dtOut(periodEnd),
    'sequence': sequence,
    'billingRecordIds': billingRecordIds,
    'tripIds': tripIds,
    'distanceKm': distanceKm,
    'distanceCharges': distanceCharges,
    'additionalCharges': additionalCharges,
    'adjustments': adjustments,
    'total': total,
    'status': status.name,
    'generatedAt': dtOut(generatedAt),
    'notes': notes,
    'disputeReason': disputeReason,
    'reviewedAt': dtOut(reviewedAt),
  };

  factory Invoice.fromJson(Json j) => Invoice(
    id: j['id'] as String,
    reference: (j['reference'] as String?) ?? j['id'] as String,
    employerId: j['employerId'] as String,
    cycle: enumByName(BillingCycle.values, j['cycle'], BillingCycle.weekly),
    periodStart: dtReq(j['periodStart']),
    periodEnd: dtReq(j['periodEnd']),
    sequence: intReq(j['sequence'], 1),
    billingRecordIds: strList(j['billingRecordIds']),
    tripIds: strList(j['tripIds']),
    distanceKm: dblReq(j['distanceKm']),
    distanceCharges: dblReq(j['distanceCharges']),
    additionalCharges: dblReq(j['additionalCharges']),
    adjustments: dblReq(j['adjustments']),
    total: dblReq(j['total']),
    status: enumByName(
      InvoiceStatus.values,
      j['status'],
      InvoiceStatus.generated,
    ),
    generatedAt: dtReq(j['generatedAt']),
    notes: (j['notes'] as String?) ?? '',
    disputeReason: j['disputeReason'] as String?,
    reviewedAt: dt(j['reviewedAt']),
  );
}

/// Fleet–company contract. Document reference is metadata only (no file).
@immutable
class Contract implements Entity {
  const Contract({
    required this.id,
    required this.contractCode,
    required this.employerId,
    required this.documentRef,
    required this.validFrom,
    required this.validUntil,
    required this.status,
    required this.agreedVehicleCount,
    required this.costPerVehicle,
    required this.createdAt,
    required this.updatedAt,
    this.currency = 'INR',
    this.costPeriod = 'month',
    this.hardVehicleLimit = true,
    this.contactId = '',
    this.contactName = '',
    this.notes = '',
  });

  @override
  final String id;
  final String contractCode;
  final String employerId;

  /// Contract document reference (metadata only, e.g. "DOC-C1-2026-01").
  final String documentRef;

  /// Inclusive local dates.
  final DateTime validFrom;
  final DateTime validUntil;
  final ContractStatus status;

  /// Number of cars agreed for simultaneous service on a day.
  final int agreedVehicleCount;

  /// Agreed cost per car per [costPeriod]. Informational for fleet cost
  /// views — it does NOT replace distance-based trip billing.
  final double costPerVehicle;
  final String currency;
  final String costPeriod;

  /// Hard = assignments exceeding the agreed car count are blocked.
  /// Soft = they are allowed with a warning.
  final bool hardVehicleLimit;
  final String contactId;
  final String contactName;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  ContractValidity validityOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    switch (status) {
      case ContractStatus.draft:
        return ContractValidity.draft;
      case ContractStatus.suspended:
        return ContractValidity.suspended;
      case ContractStatus.terminated:
        return ContractValidity.terminated;
      case ContractStatus.active:
        if (d.isBefore(
          DateTime(validFrom.year, validFrom.month, validFrom.day),
        )) {
          return ContractValidity.notYetValid;
        }
        if (d.isAfter(
          DateTime(validUntil.year, validUntil.month, validUntil.day),
        )) {
          return ContractValidity.expired;
        }
        return ContractValidity.active;
    }
  }

  bool coversDay(DateTime day) => validityOn(day) == ContractValidity.active;

  Contract copyWith({
    String? documentRef,
    DateTime? validFrom,
    DateTime? validUntil,
    ContractStatus? status,
    int? agreedVehicleCount,
    double? costPerVehicle,
    bool? hardVehicleLimit,
    String? contactId,
    String? contactName,
    String? notes,
    DateTime? updatedAt,
  }) => Contract(
    id: id,
    contractCode: contractCode,
    employerId: employerId,
    documentRef: documentRef ?? this.documentRef,
    validFrom: validFrom ?? this.validFrom,
    validUntil: validUntil ?? this.validUntil,
    status: status ?? this.status,
    agreedVehicleCount: agreedVehicleCount ?? this.agreedVehicleCount,
    costPerVehicle: costPerVehicle ?? this.costPerVehicle,
    currency: currency,
    costPeriod: costPeriod,
    hardVehicleLimit: hardVehicleLimit ?? this.hardVehicleLimit,
    contactId: contactId ?? this.contactId,
    contactName: contactName ?? this.contactName,
    notes: notes ?? this.notes,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  Json toJson() => {
    'id': id,
    'contractCode': contractCode,
    'employerId': employerId,
    'documentRef': documentRef,
    'validFrom': dtOut(validFrom),
    'validUntil': dtOut(validUntil),
    'status': status.name,
    'agreedVehicleCount': agreedVehicleCount,
    'costPerVehicle': costPerVehicle,
    'currency': currency,
    'costPeriod': costPeriod,
    'hardVehicleLimit': hardVehicleLimit,
    'contactId': contactId,
    'contactName': contactName,
    'notes': notes,
    'createdAt': dtOut(createdAt),
    'updatedAt': dtOut(updatedAt),
  };

  factory Contract.fromJson(Json j) => Contract(
    id: j['id'] as String,
    contractCode: j['contractCode'] as String,
    employerId: j['employerId'] as String,
    documentRef: (j['documentRef'] as String?) ?? '',
    validFrom: dtReq(j['validFrom']),
    validUntil: dtReq(j['validUntil']),
    status: enumByName(
      ContractStatus.values,
      j['status'],
      ContractStatus.draft,
    ),
    agreedVehicleCount: intReq(j['agreedVehicleCount'], 1),
    costPerVehicle: dblReq(j['costPerVehicle']),
    currency: (j['currency'] as String?) ?? 'INR',
    costPeriod: (j['costPeriod'] as String?) ?? 'month',
    hardVehicleLimit: boolReq(j['hardVehicleLimit'], true),
    contactId: (j['contactId'] as String?) ?? '',
    contactName: (j['contactName'] as String?) ?? '',
    notes: (j['notes'] as String?) ?? '',
    createdAt: dtReq(j['createdAt']),
    updatedAt: dtReq(j['updatedAt']),
  );
}

/// Normalized fleet–company allocation: one vehicle OR driver eligible to
/// serve one company during one daily time window. Not a permanent
/// dedication — the same resource may serve other companies in
/// non-overlapping windows.
@immutable
class FleetAllocation implements Entity {
  const FleetAllocation({
    required this.id,
    required this.employerId,
    required this.resourceType,
    required this.resourceId,
    required this.windowStartMinutes,
    required this.windowEndMinutes,
    required this.createdAt,
    this.label = '',
    this.active = true,
  });

  @override
  final String id;
  final String employerId;
  final ResourceType resourceType;
  final String resourceId;

  /// Daily window, minutes after midnight; end < start = overnight.
  final int windowStartMinutes;
  final int windowEndMinutes;
  final String label;
  final bool active;
  final DateTime createdAt;

  bool get overnight => windowEndMinutes < windowStartMinutes;

  FleetAllocation copyWith({
    int? windowStartMinutes,
    int? windowEndMinutes,
    String? label,
    bool? active,
  }) => FleetAllocation(
    id: id,
    employerId: employerId,
    resourceType: resourceType,
    resourceId: resourceId,
    windowStartMinutes: windowStartMinutes ?? this.windowStartMinutes,
    windowEndMinutes: windowEndMinutes ?? this.windowEndMinutes,
    label: label ?? this.label,
    active: active ?? this.active,
    createdAt: createdAt,
  );

  @override
  Json toJson() => {
    'id': id,
    'employerId': employerId,
    'resourceType': resourceType.name,
    'resourceId': resourceId,
    'windowStartMinutes': windowStartMinutes,
    'windowEndMinutes': windowEndMinutes,
    'label': label,
    'active': active,
    'createdAt': dtOut(createdAt),
  };

  factory FleetAllocation.fromJson(Json j) => FleetAllocation(
    id: j['id'] as String,
    employerId: j['employerId'] as String,
    resourceType: enumByName(
      ResourceType.values,
      j['resourceType'],
      ResourceType.vehicle,
    ),
    resourceId: j['resourceId'] as String,
    windowStartMinutes: intReq(j['windowStartMinutes']),
    windowEndMinutes: intReq(j['windowEndMinutes'], 1439),
    label: (j['label'] as String?) ?? '',
    active: boolReq(j['active'], true),
    createdAt: dtReq(j['createdAt']),
  );
}

/// One stop's planned vs proposed time inside a [RouteRevision].
@immutable
class RevisionStop {
  const RevisionStop({
    required this.stopId,
    required this.locationId,
    required this.previous,
    required this.proposed,
    required this.locked,
    this.employeeIds = const [],
  });

  final String stopId;
  final String locationId;
  final DateTime previous;
  final DateTime proposed;

  /// Completed/arrived stops are never changed.
  final bool locked;
  final List<String> employeeIds;

  int get shiftMinutes => proposed.difference(previous).inMinutes;

  Json toJson() => {
    'stopId': stopId,
    'locationId': locationId,
    'previous': dtOut(previous),
    'proposed': dtOut(proposed),
    'locked': locked,
    'employeeIds': employeeIds,
  };

  factory RevisionStop.fromJson(Json j) => RevisionStop(
    stopId: j['stopId'] as String,
    locationId: j['locationId'] as String,
    previous: dtReq(j['previous']),
    proposed: dtReq(j['proposed']),
    locked: boolReq(j['locked']),
    employeeIds: strList(j['employeeIds']),
  );
}

/// Traffic-driven schedule revision for one trip. Proposed first; applied
/// only by an operator. Always simulated in this prototype.
@immutable
class RouteRevision implements Entity {
  const RouteRevision({
    required this.id,
    required this.tripId,
    required this.createdAt,
    required this.scenarioKey,
    required this.scenarioLabel,
    required this.reason,
    required this.stops,
    required this.previousDeparture,
    required this.proposedDeparture,
    required this.delayMinutes,
    required this.feasible,
    required this.status,
    this.violations = const [],
    this.outsideToleranceEmployeeIds = const [],
    this.recommendation = '',
    this.appliedAt,
    this.simulated = true,
  });

  @override
  final String id;
  final String tripId;
  final DateTime createdAt;

  /// Signature of the traffic condition (dedupes repeated alerts).
  final String scenarioKey;
  final String scenarioLabel;
  final String reason;
  final List<RevisionStop> stops;
  final DateTime previousDeparture;
  final DateTime proposedDeparture;

  /// Expected delay at the final stop vs the current plan (+late, −early).
  final int delayMinutes;

  /// False when a hard arrival deadline would be missed.
  final bool feasible;
  final RevisionStatus status;
  final List<String> violations;

  /// Employees whose pickup moves beyond their ± tolerance.
  final List<String> outsideToleranceEmployeeIds;
  final String recommendation;
  final DateTime? appliedAt;
  final bool simulated;

  RouteRevision copyWith({
    RevisionStatus? status,
    ValueGetter<DateTime?>? appliedAt,
  }) => RouteRevision(
    id: id,
    tripId: tripId,
    createdAt: createdAt,
    scenarioKey: scenarioKey,
    scenarioLabel: scenarioLabel,
    reason: reason,
    stops: stops,
    previousDeparture: previousDeparture,
    proposedDeparture: proposedDeparture,
    delayMinutes: delayMinutes,
    feasible: feasible,
    status: status ?? this.status,
    violations: violations,
    outsideToleranceEmployeeIds: outsideToleranceEmployeeIds,
    recommendation: recommendation,
    appliedAt: appliedAt != null ? appliedAt() : this.appliedAt,
    simulated: simulated,
  );

  @override
  Json toJson() => {
    'id': id,
    'tripId': tripId,
    'createdAt': dtOut(createdAt),
    'scenarioKey': scenarioKey,
    'scenarioLabel': scenarioLabel,
    'reason': reason,
    'stops': stops.map((s) => s.toJson()).toList(),
    'previousDeparture': dtOut(previousDeparture),
    'proposedDeparture': dtOut(proposedDeparture),
    'delayMinutes': delayMinutes,
    'feasible': feasible,
    'status': status.name,
    'violations': violations,
    'outsideToleranceEmployeeIds': outsideToleranceEmployeeIds,
    'recommendation': recommendation,
    'appliedAt': dtOut(appliedAt),
    'simulated': simulated,
  };

  factory RouteRevision.fromJson(Json j) => RouteRevision(
    id: j['id'] as String,
    tripId: j['tripId'] as String,
    createdAt: dtReq(j['createdAt']),
    scenarioKey: (j['scenarioKey'] as String?) ?? '',
    scenarioLabel: (j['scenarioLabel'] as String?) ?? '',
    reason: (j['reason'] as String?) ?? '',
    stops: (j['stops'] as List? ?? const [])
        .map((e) => RevisionStop.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    previousDeparture: dtReq(j['previousDeparture']),
    proposedDeparture: dtReq(j['proposedDeparture']),
    delayMinutes: intReq(j['delayMinutes']),
    feasible: boolReq(j['feasible'], true),
    status: enumByName(
      RevisionStatus.values,
      j['status'],
      RevisionStatus.proposed,
    ),
    violations: strList(j['violations']),
    outsideToleranceEmployeeIds: strList(j['outsideToleranceEmployeeIds']),
    recommendation: (j['recommendation'] as String?) ?? '',
    appliedAt: dt(j['appliedAt']),
    simulated: boolReq(j['simulated'], true),
  );
}

/// Current simulated traffic condition (single row, id "current").
@immutable
class TrafficState implements Entity {
  const TrafficState({
    required this.internalRoads,
    required this.ringRoad,
    required this.source,
    required this.updatedAt,
    this.note = '',
    this.id = 'current',
  });

  @override
  final String id;
  final TrafficLevel internalRoads;
  final TrafficLevel ringRoad;
  final TrafficSource source;
  final DateTime updatedAt;
  final String note;

  static TrafficState initial(DateTime at) => TrafficState(
    internalRoads: TrafficLevel.free,
    ringRoad: TrafficLevel.free,
    source: TrafficSource.simulated,
    updatedAt: at,
  );

  /// Stable signature used for deduplicating alerts.
  String get key => '${source.name}:${internalRoads.name}:${ringRoad.name}';
  bool get available => source != TrafficSource.unavailable;
  bool get normal =>
      internalRoads == TrafficLevel.free && ringRoad == TrafficLevel.free;
  String get label => !available
      ? 'Traffic data unavailable'
      : normal
      ? 'Free-flowing (simulated)'
      : 'Internal roads: ${internalRoads.label} · Ring road: ${ringRoad.label} (simulated)';

  double factorFor(RouteVariant v) => !available
      ? 1.0
      : (v == RouteVariant.ringRoad ? ringRoad.factor : internalRoads.factor);

  @override
  Json toJson() => {
    'id': id,
    'internalRoads': internalRoads.name,
    'ringRoad': ringRoad.name,
    'source': source.name,
    'updatedAt': dtOut(updatedAt),
    'note': note,
  };

  factory TrafficState.fromJson(Json j) => TrafficState(
    id: (j['id'] as String?) ?? 'current',
    internalRoads: enumByName(
      TrafficLevel.values,
      j['internalRoads'],
      TrafficLevel.free,
    ),
    ringRoad: enumByName(TrafficLevel.values, j['ringRoad'], TrafficLevel.free),
    source: enumByName(
      TrafficSource.values,
      j['source'],
      TrafficSource.simulated,
    ),
    updatedAt: dtReq(j['updatedAt']),
    note: (j['note'] as String?) ?? '',
  );
}
