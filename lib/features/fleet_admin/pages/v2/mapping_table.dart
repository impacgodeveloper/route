import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../domain/models/models.dart';
import '../../../../domain/rules/capacity_rules.dart';

/// One car-to-employee mapping. Derived from a [Trip] (persisted mapping)
/// or a [VehiclePlan] (optimizer proposal) — never a separate table.
class MappingRow {
  const MappingRow({
    required this.vehicleId,
    required this.companyId,
    required this.employeeIds,
    required this.driverId,
    required this.guardRequired,
    required this.guardReference,
    required this.totalSeats,
    required this.guardSeats,
    required this.capacity,
    required this.stopCount,
    required this.start,
    required this.end,
    required this.statusLabel,
    required this.tone,
    required this.problems,
    this.tripId,
    this.routeCode,
    this.runId,
    this.tripStatus,
  });

  final String? tripId;
  final String vehicleId;
  final String companyId;
  final List<String> employeeIds;
  final String? driverId;
  final bool guardRequired;
  final String? guardReference;
  final int totalSeats;
  final int guardSeats;
  final int capacity;
  final String? routeCode;
  final int stopCount;
  final DateTime start;
  final DateTime end;
  final String statusLabel;
  final StatusTone tone;
  final List<String> problems;
  final String? runId;
  final TripStatus? tripStatus;

  int get driverSeats => CapacityRules.driverSeats;
  int get assigned => employeeIds.length;
  bool get feasible => problems.isEmpty;

  /// Rows for every assigned (vehicle-bearing) trip.
  static List<MappingRow> fromTrips(DataView data, Iterable<Trip> trips) => [
    for (final t in trips)
      if (t.assignedVehicleId != null &&
          data.vehicle(t.assignedVehicleId) != null)
        fromTrip(data, t),
  ];

  static MappingRow fromTrip(DataView data, Trip t) {
    final v = data.vehicle(t.assignedVehicleId)!;
    final guard = CapacityRules.guardRequired(
      vehicle: v,
      tripGuardRequired: t.guardRequired,
      employer: data.employer(t.employerId),
      passengers: t.employeeIds.map(data.employee).whereType<Employee>(),
    );
    final seats = CapacityRules.breakdown(v, guardRequired: guard);
    final problems = <String>[
      if (t.employeeIds.length > seats.passengerCapacity)
        'Over capacity (${t.employeeIds.length} > ${seats.passengerCapacity})',
      if (guard &&
          !v.securityGuardAssigned &&
          (t.guardReference?.trim().isEmpty ?? true))
        'Guard required but not assigned',
      if (t.assignedDriverId == null) 'No driver',
      if (!t.status.isTerminal &&
          (v.status == VehicleStatus.maintenance ||
              v.status == VehicleStatus.unavailable))
        'Vehicle ${v.status.label.toLowerCase()}',
      if (t.status == TripStatus.needsAttention)
        t.delayReason ?? 'Needs attention',
    ];
    final route = data.trips.routeOf(t);
    return MappingRow(
      tripId: t.id,
      vehicleId: v.id,
      companyId: t.employerId,
      employeeIds: t.employeeIds,
      driverId: t.assignedDriverId,
      guardRequired: guard,
      guardReference:
          t.guardReference ??
          (v.securityGuardAssigned ? 'Vehicle guard' : null),
      totalSeats: v.totalSeats,
      guardSeats: seats.guardSeats,
      capacity: seats.passengerCapacity,
      routeCode: route?.routeCode,
      stopCount: route?.stopIds.length ?? t.orderedStopIds.length,
      start: t.actualStart ?? t.scheduledStart,
      end: t.windowEnd,
      statusLabel: t.status.label,
      tone: problems.isNotEmpty && !t.status.isTerminal
          ? StatusTone.warning
          : Tones.trip(t.status),
      problems: t.status.isTerminal ? const [] : problems,
      runId: t.optimizationRunId,
      tripStatus: t.status,
    );
  }

  /// Preview rows for an optimizer proposal (not yet applied).
  static List<MappingRow> fromRun(DataView data, OptimizationRun run) => [
    for (final p in run.plans)
      MappingRow(
        vehicleId: p.vehicleId,
        companyId: run.employerId ?? data.primaryEmployer.id,
        employeeIds: p.employeeIds,
        driverId: p.driverId,
        guardRequired: p.guardSeats > 0,
        guardReference: p.guardSource == 'vehicle'
            ? 'Vehicle guard'
            : p.guardSource == 'pool'
            ? 'From pool (name on apply)'
            : null,
        totalSeats: p.totalSeats > 0
            ? p.totalSeats
            : (data.vehicle(p.vehicleId)?.totalSeats ?? 0),
        guardSeats: p.guardSeats,
        capacity: p.passengerCapacity,
        stopCount: p.stops.length,
        start: p.departure,
        end: p.stops.isEmpty ? p.departure : p.stops.last.plannedArrival,
        statusLabel: run.appliedAt != null
            ? 'Applied'
            : (run.isRejected ? 'Rejected' : 'Proposed'),
        tone: run.appliedAt != null ? StatusTone.success : StatusTone.info,
        problems: [
          if (p.employeeIds.length > p.passengerCapacity) 'Over capacity',
          if (!p.onTime) 'Arrives after deadline',
        ],
        runId: run.id,
      ),
  ];
}

/// Car-to-employee mapping table (wide) / cards (narrow).
class MappingTable extends ConsumerWidget {
  const MappingTable({super.key, required this.rows, this.actions, this.empty});

  final List<MappingRow> rows;
  final Widget Function(MappingRow row)? actions;
  final Widget? empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final data = ref.watch(dataProvider);
    String company(MappingRow r) =>
        data.employer(r.companyId)?.code ?? r.companyId;
    Widget guard(MappingRow r) => r.guardRequired
        ? StatusBadge(
            'Y · ${r.guardReference ?? 'missing'}',
            tone: r.guardReference == null
                ? StatusTone.danger
                : StatusTone.info,
            dense: true,
          )
        : const StatusBadge('N', dense: true);
    return AdaptiveTable<MappingRow>(
      rows: rows,
      breakpoint: 1100,
      empty: empty,
      columns: [
        TableCol(
          'Vehicle',
          (r) => Text('Vehicle ${r.vehicleId}', style: t.titleSmall),
          flex: 2,
        ),
        TableCol('Co.', (r) => Text(company(r)), flex: 1),
        TableCol(
          'Employees',
          (r) => Text(
            '${r.employeeIds.join(', ')} (${r.assigned})',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          flex: 4,
        ),
        TableCol('Driver', (r) => Text(r.driverId ?? '—'), flex: 2),
        TableCol('Guard', guard, flex: 3),
        TableCol(
          'Seats (T/D/G=cap)',
          (r) => Tooltip(
            message:
                '${r.totalSeats} total − ${r.driverSeats} driver − ${r.guardSeats} guard = ${r.capacity} employee seats',
            child: Text(
              '${r.totalSeats}/${r.driverSeats}/${r.guardSeats} = ${r.capacity}',
            ),
          ),
          flex: 2,
        ),
        TableCol('Used', (r) => Text('${r.assigned}/${r.capacity}'), flex: 1),
        TableCol(
          'Route',
          (r) => Text('${r.routeCode ?? '—'} · ${r.stopCount}'),
          flex: 2,
        ),
        TableCol(
          'Window',
          (r) => Text(
            '${Fmt.dateShort(r.start)} ${Fmt.time(r.start)}–${Fmt.time(r.end)}',
          ),
          flex: 3,
        ),
        TableCol(
          'Status',
          (r) => Tooltip(
            message: r.problems.isEmpty ? 'Feasible' : r.problems.join('\n'),
            child: StatusBadge(
              r.problems.isEmpty
                  ? r.statusLabel
                  : '${r.statusLabel} · ${r.problems.length} issue${r.problems.length == 1 ? '' : 's'}',
              tone: r.tone,
              dense: true,
            ),
          ),
          flex: 3,
        ),
        TableCol('Run', (r) => Text(r.runId ?? '—'), flex: 2),
        if (actions != null) TableCol('', actions!, flex: 1, numeric: true),
      ],
      mobileCard: (r) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Vehicle ${r.vehicleId} · ${company(r)}${r.tripId != null ? ' · ${r.tripId}' : ''}',
                  style: t.titleSmall,
                ),
              ),
              ?actions?.call(r),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${r.employeeIds.join(', ')} · driver ${r.driverId ?? '—'}',
            style: t.bodySmall,
          ),
          Text(
            '${r.totalSeats} total − ${r.driverSeats} driver − ${r.guardSeats} guard = ${r.capacity} seats · ${r.assigned} assigned · ${r.stopCount} stops',
            style: AppText.muted(context),
          ),
          Text(
            '${Fmt.dateShort(r.start)} ${Fmt.time(r.start)}–${Fmt.time(r.end)}${r.runId != null ? ' · ${r.runId}' : ''}',
            style: AppText.muted(context),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              guard(r),
              StatusBadge(r.statusLabel, tone: r.tone, dense: true),
            ],
          ),
          for (final p in r.problems)
            Text(p, style: t.bodySmall!.copyWith(color: AppColors.warning)),
        ],
      ),
    );
  }
}
