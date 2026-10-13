import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/widgets.dart';
import '../../../domain/models/models.dart';
import '../widgets/fleet_common.dart';

class FleetOverviewPage extends ConsumerWidget {
  const FleetOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final metrics = ref.watch(metricsProvider);
    final t = Theme.of(context).textTheme;
    final today = data.today;
    final todays = data.trips.onDay(today);
    final counts = metrics.tripStatusCounts(todays);
    int c(TripStatus s) => counts[s] ?? 0;
    final vStatus = metrics.vehicleStatusCounts();
    final dStatus = metrics.driverStatusCounts();
    final onDuty = data.drivers
        .where(
          (d) =>
              d.status != DriverStatus.offDuty &&
              d.status != DriverStatus.unavailable,
        )
        .length;
    final sosOpen = data.openIncidents.where((i) => i.isSos).length;
    final ev = ref
        .read(servicesProvider)
        .optimization
        .evTarget(data.primaryEmployer.id, today);
    final attention = data.trips
        .all()
        .where(
          (x) =>
              (x.status == TripStatus.needsAttention ||
                  x.status == TripStatus.delayed) &&
              !x.serviceDate.isBefore(today),
        )
        .toList();
    final blockedVehicles = data.vehicles
        .where(
          (v) =>
              v.status == VehicleStatus.maintenance ||
              v.status == VehicleStatus.unavailable,
        )
        .toList();

    return AdminPage(
      title: 'Fleet overview',
      subtitle:
          '${Fmt.weekdayLong(today)} · computed from local records across all workspaces',
      actions: [
        OutlinedButton.icon(
          onPressed: () => context.go('/fleet/optimization'),
          icon: const Icon(Icons.auto_graph_outlined),
          label: const Text('Optimize'),
        ),
        FilledButton.icon(
          onPressed: () => context.go('/fleet/dispatch/new'),
          icon: const Icon(Icons.add_rounded),
          label: const Text('New trip'),
        ),
      ],
      children: [
        MetricGrid(
          children: [
            MetricTile(
              label: 'Vehicles available',
              value:
                  '${vStatus[VehicleStatus.available]} / ${data.vehicles.length}',
              caption:
                  '${vStatus[VehicleStatus.assigned]} assigned · ${vStatus[VehicleStatus.onTrip]} on trip · ${vStatus[VehicleStatus.maintenance]! + vStatus[VehicleStatus.unavailable]!} out of service',
              icon: Icons.directions_car_outlined,
              tone: StatusTone.success,
              onTap: () => context.go('/fleet/vehicles'),
            ),
            MetricTile(
              label: 'Drivers on duty',
              value: '$onDuty / ${data.drivers.length}',
              caption:
                  '${dStatus[DriverStatus.onTrip]} on trip · ${dStatus[DriverStatus.offDuty]} off duty',
              icon: Icons.badge_outlined,
              tone: StatusTone.teal,
              onTap: () => context.go('/fleet/drivers'),
            ),
            MetricTile(
              label: 'Trips today',
              value:
                  '${todays.where((x) => x.status != TripStatus.cancelled).length}',
              caption:
                  '${c(TripStatus.planned) + c(TripStatus.assigned) + c(TripStatus.driverAccepted)} planned · ${c(TripStatus.inProgress)} in progress · ${c(TripStatus.delayed)} delayed · ${c(TripStatus.completed)} done',
              icon: Icons.alt_route_outlined,
              onTap: () => context.go('/fleet/dispatch'),
            ),
            MetricTile(
              label: 'Unassigned requests',
              value: '${data.openBookings.length}',
              caption: 'Requested, approved or waitlisted',
              icon: Icons.inbox_outlined,
              tone: data.openBookings.isEmpty
                  ? StatusTone.neutral
                  : StatusTone.warning,
              onTap: () => context.go('/fleet/dispatch'),
            ),
            MetricTile(
              label: 'Open incidents',
              value: '${data.openIncidents.length}',
              caption: sosOpen > 0 ? '$sosOpen SOS (demo)' : 'No open SOS',
              icon: Icons.report_gmailerrorred_outlined,
              tone: sosOpen > 0
                  ? StatusTone.danger
                  : (data.openIncidents.isEmpty
                        ? StatusTone.neutral
                        : StatusTone.warning),
              onTap: () => context.go('/fleet/monitoring?tab=incidents'),
            ),
            MetricTile(
              label: 'Alcohol blocks',
              value: '${data.alcoholTests.where((a) => a.blocking).length}',
              caption: data.policy.alcoholMonitoringEnabled
                  ? 'Drivers blocked from trips (simulated device)'
                  : 'Alcohol monitoring is off',
              icon: Icons.no_drinks_outlined,
              tone: data.alcoholTests.any((a) => a.blocking)
                  ? StatusTone.danger
                  : StatusTone.neutral,
              onTap: () => context.go('/fleet/safety?tab=alcohol'),
            ),
            MetricTile(
              label: 'Open SOS',
              value:
                  '${data.incidents.where((i) => i.isSos && i.status.isOpen).length}',
              caption: 'Escalation chain (demo only)',
              icon: Icons.sos_rounded,
              tone: data.incidents.any((i) => i.isSos && i.status.isOpen)
                  ? StatusTone.danger
                  : StatusTone.neutral,
              onTap: () => context.go('/fleet/safety?tab=sos'),
            ),
            MetricTile(
              label: 'Telematics events',
              value: '${data.openVehicleEvents.length}',
              caption: 'Open speed, geofence & diagnostic alerts (simulated)',
              icon: Icons.sensors_outlined,
              tone: data.openVehicleEvents.isEmpty
                  ? StatusTone.neutral
                  : StatusTone.warning,
              onTap: () => context.go('/fleet/telematics'),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        ResponsiveSplit(
          left: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PanelCard(
                title: 'Needs attention',
                subtitle: 'Delayed or blocked trips from today onward',
                child: attention.isEmpty && blockedVehicles.isEmpty
                    ? const EmptyState(
                        icon: Icons.task_alt_rounded,
                        title: 'Nothing needs attention',
                        message:
                            'Delays, defects and blocked assignments will appear here.',
                        compact: true,
                      )
                    : Column(
                        children: [
                          for (final trip in attention)
                            _AttentionRow(trip: trip),
                          for (final v in blockedVehicles)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const IconTile(
                                icon: Icons.build_outlined,
                                color: AppColors.warning,
                                size: 36,
                              ),
                              title: Text(
                                'Vehicle ${v.vehicleCode} ${v.status.label.toLowerCase()}',
                              ),
                              subtitle: Text(
                                v.notes.isEmpty
                                    ? 'Cannot be assigned'
                                    : v.notes,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: TextButton(
                                onPressed: () =>
                                    context.go('/fleet/vehicles/${v.id}'),
                                child: const Text('Open'),
                              ),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: AppSpace.md),
              PanelCard(
                title: 'Today\'s trips',
                trailing: TextButton(
                  onPressed: () => context.go('/fleet/dispatch'),
                  child: const Text('All trips'),
                ),
                child: todays.isEmpty
                    ? EmptyState(
                        icon: Icons.event_busy_outlined,
                        title: 'No trips today',
                        message: 'Create a trip or run the optimizer.',
                        actionLabel: 'New trip',
                        onAction: () => context.go('/fleet/dispatch/new'),
                        compact: true,
                      )
                    : Column(
                        children: [
                          for (final trip in todays)
                            TripRowTile(
                              trip: trip,
                              onTap: () =>
                                  context.go('/fleet/dispatch/trip/${trip.id}'),
                            ),
                        ],
                      ),
              ),
            ],
          ),
          right: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PanelCard(
                title: 'EV target vs actual',
                subtitle: data.primaryEmployer.name,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ProgressStat(
                      label: 'EV share of assigned trips today',
                      value: ev.actualPct / 100,
                      valueLabel:
                          '${ev.actualPct.toStringAsFixed(0)}% · target ${ev.targetPct}%',
                      target: ev.targetPct / 100,
                      color: AppColors.teal,
                    ),
                    const SizedBox(height: AppSpace.sm),
                    StatusBadge(
                      ev.feasible
                          ? (ev.actualPct + 0.01 >= ev.targetPct
                                ? 'Target met'
                                : 'Achievable')
                          : 'Not achievable today',
                      tone: ev.feasible
                          ? (ev.actualPct + 0.01 >= ev.targetPct
                                ? StatusTone.success
                                : StatusTone.info)
                          : StatusTone.warning,
                    ),
                    const SizedBox(height: AppSpace.sm),
                    for (final line in ev.explanation)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          line,
                          style: t.bodySmall!.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),
              PanelCard(
                title: 'Drivers',
                child: Column(
                  children: [
                    for (final d in data.drivers)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: InitialsAvatar(
                          initials: d.initials,
                          size: 36,
                          color: AppColors.teal,
                        ),
                        title: Text('${d.driverCode} · ${d.name}'),
                        subtitle: Text(
                          '${d.attendanceStatus.label} · ${d.assignedVehicleId == null ? 'No default vehicle' : 'Vehicle ${d.assignedVehicleId}'}',
                        ),
                        trailing: StatusBadge(
                          d.status.label,
                          tone: Tones.driver(d.status),
                          dense: true,
                        ),
                        onTap: () => context.go('/fleet/drivers/${d.id}'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),
              PanelCard(
                title: 'Vehicles',
                child: Column(
                  children: [
                    for (final v in data.vehicles)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: IconTile(
                          icon: v.isEv
                              ? Icons.electric_car_outlined
                              : Icons.directions_car_outlined,
                          color: v.isEv ? AppColors.teal : AppColors.deepNavy,
                          size: 36,
                        ),
                        title: Text(vehicleShort(v)),
                        subtitle: Text(
                          '${data.capacityOf(v)} employee seats · ${v.batteryOrFuelPercent ?? '—'}% ${v.isEv ? 'battery' : 'fuel'}',
                        ),
                        trailing: StatusBadge(
                          v.status.label,
                          tone: Tones.vehicle(v.status),
                          dense: true,
                        ),
                        onTap: () => context.go('/fleet/vehicles/${v.id}'),
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

class _AttentionRow extends ConsumerWidget {
  const _AttentionRow({required this.trip});
  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: InlineBanner(
        tone: trip.status == TripStatus.needsAttention
            ? StatusTone.danger
            : StatusTone.warning,
        title:
            '${trip.tripCode} · ${trip.status.label} · ${Fmt.dayLabel(trip.serviceDate, ref.read(dataProvider).now)} ${Fmt.time(trip.scheduledStart)}',
        message: trip.delayReason ?? 'Review this trip.',
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: () => context.go('/fleet/dispatch/trip/${trip.id}'),
            child: Text('Open', style: t.labelMedium),
          ),
          if (trip.actualStart == null ||
              trip.status == TripStatus.needsAttention)
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: () =>
                  context.go('/fleet/dispatch/trip/${trip.id}?reassign=1'),
              child: const Text('Reassign'),
            ),
        ],
      ),
    );
  }
}
