import 'package:flutter/foundation.dart';

import '../enums/enums.dart';
import 'json.dart';

@immutable
class OptimizationConfig implements Entity {
  const OptimizationConfig({
    required this.id,
    required this.name,
    required this.enabled,
    required this.costWeight,
    required this.punctualityWeight,
    required this.distanceWeight,
    required this.travelTimeWeight,
    required this.utilizationWeight,
    required this.evPreferenceWeight,
    required this.customerPreferenceWeight,
    required this.safetyWeight,
    required this.guardRequirementWeight,
    required this.maximumArrivalMinutes,
    required this.minimumBufferMinutes,
    required this.allowedVehicleTypes,
    required this.minimumEvPercentage,
    required this.additionalParameters,
    required this.activeParameters,
    required this.createdAt,
    required this.updatedAt,
    this.employerId,
    this.detourWeight = 4,
    this.pickupProximityWeight = 2,
    this.employeePreferenceWeight = 5,
  });

  @override
  final String id;
  final String? employerId;
  final String name;
  final bool enabled;
  final double costWeight;
  final double punctualityWeight;
  final double distanceWeight;
  final double travelTimeWeight;
  final double utilizationWeight;
  final double evPreferenceWeight;
  final double customerPreferenceWeight;
  final double safetyWeight;
  final double guardRequirementWeight;

  /// v2 weights: employee detour, pickup-point proximity and saved
  /// employee travel preferences.
  final double detourWeight;
  final double pickupProximityWeight;
  final double employeePreferenceWeight;
  final int maximumArrivalMinutes;
  final int minimumBufferMinutes;
  final List<VehicleType> allowedVehicleTypes;
  final int minimumEvPercentage;

  /// Values for catalog parameters keyed by parameter key.
  final Map<String, double> additionalParameters;

  /// Active state overrides keyed by parameter key.
  final Map<String, bool> activeParameters;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, double> get weights => {
    'cost': costWeight,
    'punctuality': punctualityWeight,
    'distance': distanceWeight,
    'travelTime': travelTimeWeight,
    'utilization': utilizationWeight,
    'ev': evPreferenceWeight,
    'customerPreference': customerPreferenceWeight,
    'safety': safetyWeight,
    'guard': guardRequirementWeight,
    'detour': detourWeight,
    'proximity': pickupProximityWeight,
    'employeePreference': employeePreferenceWeight,
  };

  OptimizationConfig copyWith({
    String? name,
    bool? enabled,
    double? costWeight,
    double? punctualityWeight,
    double? distanceWeight,
    double? travelTimeWeight,
    double? utilizationWeight,
    double? evPreferenceWeight,
    double? customerPreferenceWeight,
    double? safetyWeight,
    double? guardRequirementWeight,
    double? detourWeight,
    double? pickupProximityWeight,
    double? employeePreferenceWeight,
    int? maximumArrivalMinutes,
    int? minimumBufferMinutes,
    List<VehicleType>? allowedVehicleTypes,
    int? minimumEvPercentage,
    Map<String, double>? additionalParameters,
    Map<String, bool>? activeParameters,
    DateTime? updatedAt,
  }) => OptimizationConfig(
    id: id,
    employerId: employerId,
    name: name ?? this.name,
    enabled: enabled ?? this.enabled,
    costWeight: costWeight ?? this.costWeight,
    punctualityWeight: punctualityWeight ?? this.punctualityWeight,
    distanceWeight: distanceWeight ?? this.distanceWeight,
    travelTimeWeight: travelTimeWeight ?? this.travelTimeWeight,
    utilizationWeight: utilizationWeight ?? this.utilizationWeight,
    evPreferenceWeight: evPreferenceWeight ?? this.evPreferenceWeight,
    customerPreferenceWeight:
        customerPreferenceWeight ?? this.customerPreferenceWeight,
    safetyWeight: safetyWeight ?? this.safetyWeight,
    guardRequirementWeight:
        guardRequirementWeight ?? this.guardRequirementWeight,
    detourWeight: detourWeight ?? this.detourWeight,
    pickupProximityWeight: pickupProximityWeight ?? this.pickupProximityWeight,
    employeePreferenceWeight:
        employeePreferenceWeight ?? this.employeePreferenceWeight,
    maximumArrivalMinutes: maximumArrivalMinutes ?? this.maximumArrivalMinutes,
    minimumBufferMinutes: minimumBufferMinutes ?? this.minimumBufferMinutes,
    allowedVehicleTypes: allowedVehicleTypes ?? this.allowedVehicleTypes,
    minimumEvPercentage: minimumEvPercentage ?? this.minimumEvPercentage,
    additionalParameters: additionalParameters ?? this.additionalParameters,
    activeParameters: activeParameters ?? this.activeParameters,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// Returns a copy with a single named weight changed.
  OptimizationConfig withWeight(String key, double value) => switch (key) {
    'cost' => copyWith(costWeight: value),
    'punctuality' => copyWith(punctualityWeight: value),
    'distance' => copyWith(distanceWeight: value),
    'travelTime' => copyWith(travelTimeWeight: value),
    'utilization' => copyWith(utilizationWeight: value),
    'ev' => copyWith(evPreferenceWeight: value),
    'customerPreference' => copyWith(customerPreferenceWeight: value),
    'safety' => copyWith(safetyWeight: value),
    'guard' => copyWith(guardRequirementWeight: value),
    'detour' => copyWith(detourWeight: value),
    'proximity' => copyWith(pickupProximityWeight: value),
    'employeePreference' => copyWith(employeePreferenceWeight: value),
    _ => this,
  };

  @override
  Json toJson() => {
    'id': id,
    'employerId': employerId,
    'name': name,
    'enabled': enabled,
    'costWeight': costWeight,
    'punctualityWeight': punctualityWeight,
    'distanceWeight': distanceWeight,
    'travelTimeWeight': travelTimeWeight,
    'utilizationWeight': utilizationWeight,
    'evPreferenceWeight': evPreferenceWeight,
    'customerPreferenceWeight': customerPreferenceWeight,
    'safetyWeight': safetyWeight,
    'guardRequirementWeight': guardRequirementWeight,
    'detourWeight': detourWeight,
    'pickupProximityWeight': pickupProximityWeight,
    'employeePreferenceWeight': employeePreferenceWeight,
    'maximumArrivalMinutes': maximumArrivalMinutes,
    'minimumBufferMinutes': minimumBufferMinutes,
    'allowedVehicleTypes': allowedVehicleTypes.map((e) => e.name).toList(),
    'minimumEvPercentage': minimumEvPercentage,
    'additionalParameters': additionalParameters,
    'activeParameters': activeParameters,
    'createdAt': dtOut(createdAt),
    'updatedAt': dtOut(updatedAt),
  };

  factory OptimizationConfig.fromJson(Json j) => OptimizationConfig(
    id: j['id'] as String,
    employerId: j['employerId'] as String?,
    name: j['name'] as String,
    enabled: boolReq(j['enabled'], true),
    costWeight: dblReq(j['costWeight'], 5),
    punctualityWeight: dblReq(j['punctualityWeight'], 5),
    distanceWeight: dblReq(j['distanceWeight'], 5),
    travelTimeWeight: dblReq(j['travelTimeWeight'], 5),
    utilizationWeight: dblReq(j['utilizationWeight'], 5),
    evPreferenceWeight: dblReq(j['evPreferenceWeight'], 5),
    customerPreferenceWeight: dblReq(j['customerPreferenceWeight'], 5),
    safetyWeight: dblReq(j['safetyWeight'], 5),
    guardRequirementWeight: dblReq(j['guardRequirementWeight'], 5),
    detourWeight: dblReq(j['detourWeight'], 4),
    pickupProximityWeight: dblReq(j['pickupProximityWeight'], 2),
    employeePreferenceWeight: dblReq(j['employeePreferenceWeight'], 5),
    maximumArrivalMinutes: intReq(j['maximumArrivalMinutes'], 570),
    minimumBufferMinutes: intReq(j['minimumBufferMinutes'], 10),
    allowedVehicleTypes: strList(
      j['allowedVehicleTypes'],
    ).map((e) => enumByName(VehicleType.values, e, VehicleType.sedan)).toList(),
    minimumEvPercentage: intReq(j['minimumEvPercentage'], 50),
    additionalParameters: dblMap(j['additionalParameters']),
    activeParameters: boolMap(j['activeParameters']),
    createdAt: dtReq(j['createdAt']),
    updatedAt: dtReq(j['updatedAt']),
  );
}

/// One planned stop inside a proposal.
@immutable
class PlannedStop {
  const PlannedStop({
    required this.locationId,
    required this.kind,
    required this.employeeIds,
    required this.plannedArrival,
  });

  final String locationId;
  final StopKind kind;
  final List<String> employeeIds;
  final DateTime plannedArrival;

  Json toJson() => {
    'locationId': locationId,
    'kind': kind.name,
    'employeeIds': employeeIds,
    'plannedArrival': dtOut(plannedArrival),
  };

  factory PlannedStop.fromJson(Json j) => PlannedStop(
    locationId: j['locationId'] as String,
    kind: enumByName(StopKind.values, j['kind'], StopKind.pickup),
    employeeIds: strList(j['employeeIds']),
    plannedArrival: dtReq(j['plannedArrival']),
  );
}

/// One vehicle's share of an optimization proposal.
@immutable
class VehiclePlan {
  const VehiclePlan({
    required this.vehicleId,
    required this.employeeIds,
    required this.stops,
    required this.distanceKm,
    required this.durationMinutes,
    required this.estimatedCost,
    required this.departure,
    required this.latestArrival,
    required this.deadline,
    required this.passengerCapacity,
    required this.guardSeats,
    required this.variant,
    this.driverId,
    this.startLocationId,
    this.deadheadKm = 0,
    this.guardSource,
    this.totalSeats = 0,
  });

  final String vehicleId;
  final String? driverId;
  final List<String> employeeIds;
  final List<PlannedStop> stops;
  final double distanceKm;
  final int durationMinutes;
  final double estimatedCost;
  final DateTime departure;
  final DateTime latestArrival;
  final DateTime deadline;
  final int passengerCapacity;
  final int guardSeats;
  final RouteVariant variant;

  /// Parking/depot the vehicle starts from (fictional demo location).
  final String? startLocationId;

  /// Empty kilometres from the start point to the first pickup.
  final double deadheadKm;

  /// How a required guard is covered: "vehicle" (assigned to vehicle) or
  /// "pool" (from the operator's available guards). Null = not required.
  final String? guardSource;
  final int totalSeats;

  bool get onTime => !latestArrival.isAfter(deadline);
  double get utilization =>
      passengerCapacity == 0 ? 0 : employeeIds.length / passengerCapacity;

  Json toJson() => {
    'vehicleId': vehicleId,
    'driverId': driverId,
    'employeeIds': employeeIds,
    'stops': stops.map((e) => e.toJson()).toList(),
    'distanceKm': distanceKm,
    'durationMinutes': durationMinutes,
    'estimatedCost': estimatedCost,
    'departure': dtOut(departure),
    'latestArrival': dtOut(latestArrival),
    'deadline': dtOut(deadline),
    'passengerCapacity': passengerCapacity,
    'guardSeats': guardSeats,
    'variant': variant.name,
    'startLocationId': startLocationId,
    'deadheadKm': deadheadKm,
    'guardSource': guardSource,
    'totalSeats': totalSeats,
  };

  factory VehiclePlan.fromJson(Json j) => VehiclePlan(
    vehicleId: j['vehicleId'] as String,
    driverId: j['driverId'] as String?,
    employeeIds: strList(j['employeeIds']),
    stops: (j['stops'] as List? ?? const [])
        .map((e) => PlannedStop.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    distanceKm: dblReq(j['distanceKm']),
    durationMinutes: intReq(j['durationMinutes']),
    estimatedCost: dblReq(j['estimatedCost']),
    departure: dtReq(j['departure']),
    latestArrival: dtReq(j['latestArrival']),
    deadline: dtReq(j['deadline']),
    passengerCapacity: intReq(j['passengerCapacity']),
    guardSeats: intReq(j['guardSeats']),
    variant: enumByName(
      RouteVariant.values,
      j['variant'],
      RouteVariant.internalRoads,
    ),
    startLocationId: j['startLocationId'] as String?,
    deadheadKm: dblReq(j['deadheadKm']),
    guardSource: j['guardSource'] as String?,
    totalSeats: intReq(j['totalSeats']),
  );
}

@immutable
class ScoreComponent {
  const ScoreComponent({
    required this.key,
    required this.label,
    required this.weight,
    required this.normalizedPenalty,
    required this.detail,
  });

  final String key;
  final String label;
  final double weight;

  /// 0 = ideal, 1 = worst.
  final double normalizedPenalty;
  final String detail;

  Json toJson() => {
    'key': key,
    'label': label,
    'weight': weight,
    'normalizedPenalty': normalizedPenalty,
    'detail': detail,
  };

  factory ScoreComponent.fromJson(Json j) => ScoreComponent(
    key: j['key'] as String,
    label: j['label'] as String,
    weight: dblReq(j['weight']),
    normalizedPenalty: dblReq(j['normalizedPenalty']),
    detail: (j['detail'] as String?) ?? '',
  );
}

@immutable
class OptimizationRun implements Entity {
  const OptimizationRun({
    required this.id,
    required this.reference,
    required this.configurationId,
    required this.createdAt,
    required this.status,
    required this.inputSummary,
    required this.outputSummary,
    required this.totalDistanceKm,
    required this.estimatedMinutes,
    required this.estimatedCost,
    required this.onTimeScore,
    required this.vehicleUtilization,
    required this.evAllocationPercentage,
    required this.warnings,
    required this.explanation,
    required this.score,
    required this.plans,
    required this.scoreBreakdown,
    required this.hardConstraintViolations,
    required this.employeeIds,
    required this.serviceDate,
    this.alternatives = const [],
    this.isSimulation = true,
    this.appliedAt,
    this.appliedTripIds = const [],
    this.employerId,
    this.weightsSnapshot = const {},
    this.remedies = const [],
    this.preferenceSummary = const [],
    this.candidateVehicleIds = const [],
    this.candidateDriverIds = const [],
    this.constraintsEvaluated = const [],
    this.rejectedAt,
    this.rejectionReason,
  });

  @override
  final String id;
  final String reference;
  final String configurationId;
  final String? employerId;
  final DateTime createdAt;
  final DateTime serviceDate;
  final OptimizationRunStatus status;
  final String inputSummary;
  final String outputSummary;
  final double totalDistanceKm;
  final int estimatedMinutes;
  final double estimatedCost;

  /// 0–100.
  final double onTimeScore;

  /// 0–100.
  final double vehicleUtilization;
  final double evAllocationPercentage;
  final List<String> warnings;
  final List<String> explanation;

  /// Weighted score, 0–100 (higher is better).
  final double score;
  final List<VehiclePlan> plans;
  final List<ScoreComponent> scoreBreakdown;
  final List<String> hardConstraintViolations;
  final List<String> employeeIds;

  /// Short comparison lines for evaluated alternatives.
  final List<String> alternatives;
  final bool isSimulation;
  final DateTime? appliedAt;
  final List<String> appliedTripIds;
  final Map<String, double> weightsSnapshot;

  /// Suggested fixes when no feasible assignment exists.
  final List<String> remedies;

  /// How saved employee travel preferences affected this proposal.
  final List<String> preferenceSummary;
  final List<String> candidateVehicleIds;
  final List<String> candidateDriverIds;

  /// Names of the hard constraints that were checked.
  final List<String> constraintsEvaluated;
  final DateTime? rejectedAt;
  final String? rejectionReason;
  bool get isRejected => rejectedAt != null;

  bool get isFeasible => status == OptimizationRunStatus.demoCalculated;

  OptimizationRun copyWith({
    ValueGetter<DateTime?>? appliedAt,
    List<String>? appliedTripIds,
    ValueGetter<DateTime?>? rejectedAt,
    ValueGetter<String?>? rejectionReason,
  }) => OptimizationRun(
    id: id,
    reference: reference,
    configurationId: configurationId,
    employerId: employerId,
    createdAt: createdAt,
    serviceDate: serviceDate,
    status: status,
    inputSummary: inputSummary,
    outputSummary: outputSummary,
    totalDistanceKm: totalDistanceKm,
    estimatedMinutes: estimatedMinutes,
    estimatedCost: estimatedCost,
    onTimeScore: onTimeScore,
    vehicleUtilization: vehicleUtilization,
    evAllocationPercentage: evAllocationPercentage,
    warnings: warnings,
    explanation: explanation,
    score: score,
    plans: plans,
    scoreBreakdown: scoreBreakdown,
    hardConstraintViolations: hardConstraintViolations,
    employeeIds: employeeIds,
    alternatives: alternatives,
    isSimulation: isSimulation,
    appliedAt: appliedAt != null ? appliedAt() : this.appliedAt,
    appliedTripIds: appliedTripIds ?? this.appliedTripIds,
    weightsSnapshot: weightsSnapshot,
    remedies: remedies,
    preferenceSummary: preferenceSummary,
    candidateVehicleIds: candidateVehicleIds,
    candidateDriverIds: candidateDriverIds,
    constraintsEvaluated: constraintsEvaluated,
    rejectedAt: rejectedAt != null ? rejectedAt() : this.rejectedAt,
    rejectionReason: rejectionReason != null
        ? rejectionReason()
        : this.rejectionReason,
  );

  @override
  Json toJson() => {
    'id': id,
    'reference': reference,
    'configurationId': configurationId,
    'employerId': employerId,
    'createdAt': dtOut(createdAt),
    'serviceDate': dtOut(serviceDate),
    'status': status.name,
    'inputSummary': inputSummary,
    'outputSummary': outputSummary,
    'totalDistanceKm': totalDistanceKm,
    'estimatedMinutes': estimatedMinutes,
    'estimatedCost': estimatedCost,
    'onTimeScore': onTimeScore,
    'vehicleUtilization': vehicleUtilization,
    'evAllocationPercentage': evAllocationPercentage,
    'warnings': warnings,
    'explanation': explanation,
    'score': score,
    'plans': plans.map((e) => e.toJson()).toList(),
    'scoreBreakdown': scoreBreakdown.map((e) => e.toJson()).toList(),
    'hardConstraintViolations': hardConstraintViolations,
    'employeeIds': employeeIds,
    'alternatives': alternatives,
    'isSimulation': isSimulation,
    'appliedAt': dtOut(appliedAt),
    'appliedTripIds': appliedTripIds,
    'weightsSnapshot': weightsSnapshot,
    'remedies': remedies,
    'preferenceSummary': preferenceSummary,
    'candidateVehicleIds': candidateVehicleIds,
    'candidateDriverIds': candidateDriverIds,
    'constraintsEvaluated': constraintsEvaluated,
    'rejectedAt': dtOut(rejectedAt),
    'rejectionReason': rejectionReason,
  };

  factory OptimizationRun.fromJson(Json j) => OptimizationRun(
    id: j['id'] as String,
    reference: (j['reference'] as String?) ?? j['id'] as String,
    configurationId: j['configurationId'] as String,
    employerId: j['employerId'] as String?,
    createdAt: dtReq(j['createdAt']),
    serviceDate: dtReq(j['serviceDate']),
    status: enumByName(
      OptimizationRunStatus.values,
      j['status'],
      OptimizationRunStatus.failedDemo,
    ),
    inputSummary: (j['inputSummary'] as String?) ?? '',
    outputSummary: (j['outputSummary'] as String?) ?? '',
    totalDistanceKm: dblReq(j['totalDistanceKm']),
    estimatedMinutes: intReq(j['estimatedMinutes']),
    estimatedCost: dblReq(j['estimatedCost']),
    onTimeScore: dblReq(j['onTimeScore']),
    vehicleUtilization: dblReq(j['vehicleUtilization']),
    evAllocationPercentage: dblReq(j['evAllocationPercentage']),
    warnings: strList(j['warnings']),
    explanation: strList(j['explanation']),
    score: dblReq(j['score']),
    plans: (j['plans'] as List? ?? const [])
        .map((e) => VehiclePlan.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    scoreBreakdown: (j['scoreBreakdown'] as List? ?? const [])
        .map((e) => ScoreComponent.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    hardConstraintViolations: strList(j['hardConstraintViolations']),
    employeeIds: strList(j['employeeIds']),
    alternatives: strList(j['alternatives']),
    isSimulation: boolReq(j['isSimulation'], true),
    appliedAt: dt(j['appliedAt']),
    appliedTripIds: strList(j['appliedTripIds']),
    weightsSnapshot: dblMap(j['weightsSnapshot']),
    remedies: strList(j['remedies']),
    preferenceSummary: strList(j['preferenceSummary']),
    candidateVehicleIds: strList(j['candidateVehicleIds']),
    candidateDriverIds: strList(j['candidateDriverIds']),
    constraintsEvaluated: strList(j['constraintsEvaluated']),
    rejectedAt: dt(j['rejectedAt']),
    rejectionReason: j['rejectionReason'] as String?,
  );
}
