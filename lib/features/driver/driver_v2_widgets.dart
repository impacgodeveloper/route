import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import '../../domain/rules/capacity_rules.dart';

/// Pickup/drop tolerance (minutes) for one employee.
int employeeTolerance(DataView data, Employee e) =>
    e.toleranceMinutes(data.employer(e.employerId));

/// Tolerance for a stop = the strictest (minimum) across its passengers.
int stopTolerance(DataView data, RouteStop s) {
  final ids = s.kind == StopKind.pickup
      ? s.boardingEmployeeIds
      : s.alightingEmployeeIds;
  final tols = [
    for (final id in ids)
      if (data.employee(id) case final e?) employeeTolerance(data, e),
  ];
  if (tols.isEmpty) return ToleranceRules.clientReferenceDefault;
  return tols.reduce((a, b) => a < b ? a : b);
}

/// "7:03 AM – 7:17 AM (±7)".
String windowLabel(DateTime planned, int tol) {
  final (from, to) = ToleranceRules.window(planned, tol);
  return '${Fmt.time(from)} – ${Fmt.time(to)} (±$tol)';
}

/// Badge describing actual vs planned arrival against the tolerance.
class ToleranceBadge extends StatelessWidget {
  const ToleranceBadge({
    super.key,
    required this.actual,
    required this.planned,
    required this.tolerance,
  });
  final DateTime actual;
  final DateTime planned;
  final int tolerance;

  @override
  Widget build(BuildContext context) {
    final ok = ToleranceRules.within(actual, planned, tolerance);
    return StatusBadge(
      ToleranceRules.describe(actual, planned, tolerance),
      tone: ok ? StatusTone.success : StatusTone.danger,
      icon: ok ? Icons.timer_outlined : Icons.warning_amber_rounded,
      dense: true,
    );
  }
}

/// Planned vs actual arrival with tolerance, for one stop.
class StopTimingPanel extends ConsumerWidget {
  const StopTimingPanel({super.key, required this.stop});
  final RouteStop stop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final tol = stopTolerance(data, stop);
    final t = Theme.of(context).textTheme;
    final actual = stop.actualArrival;
    final outside =
        actual != null &&
        !ToleranceRules.within(actual, stop.plannedArrival, tol);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyValueRow(
          label: 'Planned',
          value: Fmt.time(stop.plannedArrival),
          dense: true,
        ),
        KeyValueRow(
          label: 'Tolerance window',
          value: windowLabel(stop.plannedArrival, tol),
          dense: true,
        ),
        KeyValueRow(
          label: 'Actual arrival',
          value: Fmt.time(actual),
          dense: true,
        ),
        if (actual != null) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: ToleranceBadge(
              actual: actual,
              planned: stop.plannedArrival,
              tolerance: tol,
            ),
          ),
          if (outside) ...[
            const SizedBox(height: 4),
            Text(
              'Outside ±$tol min — recorded for the Fleet Manager. The office deadline still applies.',
              style: t.bodySmall!.copyWith(color: AppColors.danger),
            ),
          ],
        ],
      ],
    );
  }
}

/// Simulated traffic status + pending schedule-change proposal for a trip.
class TripTrafficPanel extends ConsumerWidget {
  const TripTrafficPanel({super.key, required this.trip, this.compact = false});
  final Trip trip;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final status = ref.read(servicesProvider).traffic.statusOf(trip);
    final revision = data.openRevision(trip.id);
    final t = Theme.of(context).textTheme;
    final next = status.nextStop;
    final eta = next == null ? null : status.proposedTimes[next.id];

    final StatusTone tone;
    if (!status.available) {
      tone = StatusTone.neutral;
    } else if (!status.feasible) {
      tone = StatusTone.danger;
    } else if (status.delayMinutes >= 3 || status.earlierDepartureMinutes > 0) {
      tone = StatusTone.warning;
    } else {
      tone = StatusTone.success;
    }

    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      semanticLabel: 'Traffic: ${status.statusLabel}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                status.available
                    ? Icons.traffic_outlined
                    : Icons.cloud_off_outlined,
                color: tone.foreground,
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(
                  status.available ? 'Traffic' : 'Traffic data unavailable',
                  style: t.titleSmall,
                ),
              ),
              StatusBadge(status.statusLabel, tone: tone, dense: true),
            ],
          ),
          if (status.available) ...[
            const SizedBox(height: AppSpace.xs),
            KeyValueRow(
              label: 'Estimated delay',
              value: status.delayMinutes <= 0
                  ? 'None'
                  : '~${status.delayMinutes} min',
              dense: true,
            ),
            if (next != null && eta != null)
              KeyValueRow(
                label: 'Next stop ETA',
                value:
                    '${Fmt.time(eta)} (planned ${Fmt.time(next.plannedArrival)})',
                dense: true,
              ),
            if (!compact || tone != StatusTone.success) ...[
              const SizedBox(height: 4),
              Text(
                status.recommendation,
                style: t.bodySmall!.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ] else ...[
            const SizedBox(height: 4),
            Text(
              status.recommendation,
              style: t.bodySmall!.copyWith(color: AppColors.textSecondary),
            ),
          ],
          if (revision != null) ...[
            const SizedBox(height: AppSpace.sm),
            InlineBanner(
              tone: StatusTone.warning,
              title: 'Schedule change pending Fleet Manager decision',
              message:
                  '${revision.reason} Proposed: ${revision.delayMinutes >= 0 ? '+' : ''}${revision.delayMinutes} min at the final stop'
                  '${revision.proposedDeparture != revision.previousDeparture ? ', depart ${Fmt.time(revision.proposedDeparture)}' : ''}. '
                  'Keep following the current plan until it is applied.',
            ),
          ],
          const SizedBox(height: AppSpace.xs),
          SimulatedNote(
            '${DemoLabels.trafficSimulated} · updated ${Fmt.time(status.lastUpdate)}',
            icon: Icons.traffic_outlined,
          ),
        ],
      ),
    );
  }
}

/// Security guard requirement + seat breakdown for a trip's vehicle.
class GuardSeatsPanel extends ConsumerWidget {
  const GuardSeatsPanel({super.key, required this.trip});
  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final v = data.vehicle(trip.assignedVehicleId);
    final guard = trip.guardRequired || (v?.requiresSecurityGuard ?? false);
    final seats = v == null
        ? null
        : CapacityRules.breakdown(v, guardRequired: trip.guardRequired);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyValueRow(
          label: 'Security guard',
          valueWidget: guard
              ? StatusBadge(
                  trip.guardReference == null || trip.guardReference!.isEmpty
                      ? 'Required · ${v?.securityGuardAssigned == true ? 'vehicle guard' : 'not named'}'
                      : 'Guard: ${trip.guardReference}',
                  tone: StatusTone.info,
                  icon: Icons.shield_outlined,
                  dense: true,
                )
              : const StatusBadge(
                  'Not required',
                  tone: StatusTone.neutral,
                  dense: true,
                ),
          dense: true,
        ),
        if (seats != null)
          KeyValueRow(
            label: 'Seats',
            value:
                '${trip.employeeIds.length} of ${seats.passengerCapacity} employee seats · ${seats.totalSeats} total − ${seats.driverSeats} driver − ${seats.guardSeats} guard',
            dense: true,
          ),
      ],
    );
  }
}

/// Clean, de-duplicated list of reasons a trip cannot start, including
/// contract / fleet-allocation / licence rules from assignment validation.
class StartBlockersBanner extends StatelessWidget {
  const StartBlockersBanner({super.key, required this.blockers});
  final List<String> blockers;

  @override
  Widget build(BuildContext context) {
    final unique = <String>[];
    for (final b in blockers) {
      final s = b.trim();
      if (s.isNotEmpty && !unique.contains(s)) unique.add(s);
    }
    final commercial = unique.any((b) {
      final l = b.toLowerCase();
      return l.contains('contract') ||
          l.contains('allocated') ||
          l.contains('licence');
    });
    return InlineBanner(
      tone: StatusTone.warning,
      title: unique.length == 1
          ? 'Cannot start yet'
          : 'Cannot start yet · ${unique.length} issues',
      messages: unique,
      message: commercial
          ? 'Contract, allocation or licence issues must be resolved by the Fleet Manager.'
          : null,
    );
  }
}

/// Opens the record a driver notification refers to.
void openDriverNotification(
  BuildContext context,
  DataView data,
  AppNotification n,
) {
  final id = n.relatedEntityId;
  switch (n.relatedEntityType) {
    case 'trip' when id != null:
      final t = data.trips.byId(id);
      final active = t != null && t.status.isActive && t.actualStart != null;
      context.push(active ? '/driver/trip/$id/active' : '/driver/trip/$id');
    case 'shift':
      context.push('/driver/attendance');
    case 'vehicle':
      context.push('/driver/shift-summary');
    case 'driver':
      context.push('/driver/alcohol');
    case 'incident' when id != null:
      final inc = data.incident(id);
      if (inc?.tripId != null) context.push('/driver/trip/${inc!.tripId}');
    default:
      break;
  }
}

/// Simulated live speed + open telematics alerts for the trip's vehicle.
/// Read-only: stays visible while the vehicle is moving.
class TelematicsPanel extends ConsumerWidget {
  const TelematicsPanel({super.key, required this.trip});
  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final v = data.vehicle(trip.assignedVehicleId);
    if (v == null) return const SizedBox.shrink();
    final snap = ref.read(servicesProvider).telematics.snapshot(v);
    final policy = data.policy;
    final t = Theme.of(context).textTheme;
    final open = data
        .vehicleEventsOf(v.id)
        .where((e) => e.open && (e.tripId == null || e.tripId == trip.id))
        .toList();
    final speeding = open.where((e) => e.type == VehicleEventType.speeding);
    final offRoute = open.where(
      (e) =>
          e.type == VehicleEventType.routeDeviation ||
          e.type == VehicleEventType.geofenceExit,
    );
    final over = snap.speedKmh > policy.speedLimitKmh;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (speeding.isNotEmpty) ...[
          InlineBanner(
            tone: StatusTone.warning,
            icon: Icons.speed_rounded,
            title: 'Slow down',
            message:
                'Speed alert: ${speeding.first.description}. Limit ${policy.speedLimitKmh} km/h.',
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        if (offRoute.isNotEmpty) ...[
          InlineBanner(
            tone: StatusTone.warning,
            icon: Icons.alt_route_rounded,
            title: 'Off planned route',
            message:
                '${offRoute.first.description} Return to the planned route when safe.',
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        AppCard(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Row(
            children: [
              Text(
                snap.speedKmh.toStringAsFixed(0),
                style: t.headlineMedium!.copyWith(
                  fontFeatures: AppText.tabular,
                  color: over ? AppColors.warning : AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 4),
              Text('km/h', style: AppText.secondary(context)),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Limit ${policy.speedLimitKmh} km/h · ${snap.status}',
                      style: t.bodySmall,
                    ),
                    Text(
                      'Simulated telemetry · updated ${Fmt.time(snap.lastUpdate)}',
                      style: t.bodySmall!.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Diagnostic trouble codes (simulated) for a vehicle.
class DiagnosticsRow extends StatelessWidget {
  const DiagnosticsRow({super.key, required this.vehicle});
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) => KeyValueRow(
    label: 'Diagnostics (simulated)',
    valueWidget: vehicle.diagnosticCodes.isEmpty
        ? const StatusBadge('No codes', tone: StatusTone.success, dense: true)
        : Wrap(
            alignment: WrapAlignment.end,
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final c in vehicle.diagnosticCodes)
                StatusBadge(c, tone: StatusTone.warning, dense: true),
            ],
          ),
    dense: true,
  );
}

/// SOS escalation chain with honest per-recipient status.
class SosChainList extends ConsumerWidget {
  const SosChainList({super.key, required this.incidentId});
  final String incidentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chain = ref.watch(dataProvider).sosDispatchesOf(incidentId);
    if (chain.isEmpty) return const SizedBox.shrink();
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.md,
              AppSpace.md,
              AppSpace.md,
              0,
            ),
            child: Text(
              'Escalation chain',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          for (final d in chain)
            ListTile(
              title: Text(d.recipient.label),
              subtitle: Text(
                d.note.isNotEmpty ? d.note : d.channel,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: StatusBadge(
                d.status.label,
                tone: switch (d.status) {
                  SosDispatchStatus.acknowledged => StatusTone.success,
                  SosDispatchStatus.alertedInApp => StatusTone.info,
                  SosDispatchStatus.integrationRequired => StatusTone.warning,
                  SosDispatchStatus.disabled => StatusTone.neutral,
                },
                dense: true,
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpace.md,
              0,
              AppSpace.md,
              AppSpace.md,
            ),
            child: SimulatedNote(DemoLabels.sosDemo),
          ),
        ],
      ),
    );
  }
}
