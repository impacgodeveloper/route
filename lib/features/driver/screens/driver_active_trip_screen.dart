import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/widgets.dart';
import '../../../domain/models/models.dart';
import '../../../domain/rules/geo_rules.dart';
import '../driver_common.dart';
import '../driver_v2_widgets.dart';

/// Active trip: next stop hero, counts, schematic map, remaining stops.
class DriverActiveTripScreen extends ConsumerStatefulWidget {
  const DriverActiveTripScreen({super.key, required this.tripId});
  final String tripId;

  @override
  ConsumerState<DriverActiveTripScreen> createState() =>
      _DriverActiveTripScreenState();
}

class _DriverActiveTripScreenState
    extends ConsumerState<DriverActiveTripScreen> {
  bool _busy = false;

  Future<void> _toggleMoving(bool v) async {
    if (v && !ref.read(drivingWarningSeenProvider)) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          icon: const Icon(
            Icons.do_not_touch_outlined,
            color: AppColors.warning,
            size: 32,
          ),
          title: const Text('Eyes on the road'),
          content: const Text(
            'Do not use the phone while driving. While the vehicle is moving, the app locks detailed controls. Stop safely before verifying passengers or filling forms.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Understood'),
            ),
          ],
        ),
      );
      ref.read(drivingWarningSeenProvider.notifier).state = true;
    }
    ref.read(drivingModeProvider.notifier).state = v;
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final moving = ref.watch(drivingModeProvider);
    final trip = data.trips.byId(widget.tripId);
    final t = Theme.of(context).textTheme;
    if (trip == null) {
      return Scaffold(
        appBar: driverAppBar(context, 'Active trip'),
        body: const EmptyState(
          icon: Icons.search_off_rounded,
          title: 'Trip not found',
          message: 'It may have been reset.',
        ),
      );
    }
    if (!(trip.status.isActive && trip.actualStart != null)) {
      return Scaffold(
        appBar: driverAppBar(context, trip.tripCode),
        body: EmptyState(
          icon: trip.status == TripStatus.completed
              ? Icons.task_alt_rounded
              : Icons.info_outline_rounded,
          title: trip.status == TripStatus.completed
              ? 'Trip completed'
              : 'Trip is not in progress',
          message: trip.status == TripStatus.cancelled
              ? 'This trip was cancelled${trip.cancellationReason != null ? ': ${trip.cancellationReason}' : ''}.'
              : 'Status: ${trip.status.label}.',
          actionLabel: 'Back to Home',
          onAction: () => context.go('/driver/home'),
        ),
      );
    }
    final ops = ref.read(servicesProvider).driverOps;
    final stops = data.trips.stopsOf(trip);
    final current = data.trips.currentStop(trip);
    final rec = ops.reconcile(trip);
    final pos = ref.watch(locationServiceProvider).positionOf(trip);
    final locs = data.locationMap;
    final points = [
      for (final s in stops)
        MapPoint(
          x: locs[s.locationId]!.demoX,
          y: locs[s.locationId]!.demoY,
          label: locs[s.locationId]!.code,
          kind: locs[s.locationId]!.type,
          emphasis: s.id == current?.id,
          done: s.isDone,
        ),
    ];

    return Scaffold(
      appBar: driverAppBar(
        context,
        trip.tripCode,
        actions: [
          IconButton(
            tooltip: 'SOS',
            onPressed: () => context.push('/driver/sos?trip=${trip.id}'),
            icon: const Icon(Icons.sos_rounded, color: AppColors.danger),
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: moving ? AppColors.warningBg : AppColors.white,
            child: SwitchListTile(
              value: moving,
              onChanged: _toggleMoving,
              secondary: Icon(
                moving ? Icons.speed_rounded : Icons.local_parking_rounded,
                color: moving ? AppColors.warning : AppColors.textSecondary,
              ),
              title: Text(
                moving ? 'Vehicle moving (simulated)' : 'Vehicle stopped',
              ),
              subtitle: const Text('Controls lock while moving'),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: MobilePage(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.gutter,
                AppSpace.md,
                AppSpace.gutter,
                AppSpace.xxxl,
              ),
              children: [
                // Hero: always usable (Arrived) — large controls.
                AppCard(
                  color: AppColors.midnightNavy,
                  borderColor: AppColors.midnightNavy,
                  padding: const EdgeInsets.all(AppSpace.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            current == null
                                ? 'ALL STOPS DONE'
                                : 'STOP ${current.sequence} OF ${stops.length} · ${current.kind.label.toUpperCase()}',
                            style: t.labelSmall!.copyWith(
                              color: Colors.white70,
                              letterSpacing: 1,
                            ),
                          ),
                          const Spacer(),
                          if (trip.status == TripStatus.delayed)
                            const StatusBadge(
                              'Delayed',
                              tone: StatusTone.warning,
                              dense: true,
                            ),
                          if (trip.status == TripStatus.needsAttention)
                            const StatusBadge(
                              'Needs attention',
                              tone: StatusTone.warning,
                              dense: true,
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpace.sm),
                      Text(
                        current == null
                            ? 'Ready to complete'
                            : stopTitle(data, current),
                        style: t.headlineMedium!.copyWith(color: Colors.white),
                      ),
                      if (current != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${current.kind == StopKind.pickup ? 'Pick up ${current.expectedBoardingCount}' : 'Drop ${current.expectedAlightingCount}'} · planned ${Fmt.time(current.plannedArrival)}\nWindow ${windowLabel(current.plannedArrival, stopTolerance(data, current))}',
                          style: t.bodyLarge!.copyWith(color: Colors.white70),
                        ),
                      ],
                      const SizedBox(height: AppSpace.lg),
                      if (current == null)
                        BigButton(
                          label: 'Complete trip',
                          icon: Icons.flag_rounded,
                          color: AppColors.teal,
                          onPressed: moving
                              ? null
                              : () => context.push(
                                  '/driver/trip/${trip.id}/complete',
                                ),
                        )
                      else if (current.status == StopStatus.upcoming)
                        BigButton(
                          label: 'Arrived at stop',
                          icon: Icons.where_to_vote_outlined,
                          color: AppColors.teal,
                          busy: _busy,
                          onPressed: () async {
                            setState(() => _busy = true);
                            final r = await ops.arriveAtStop(current.id);
                            if (!context.mounted) return;
                            setState(() => _busy = false);
                            ref.read(drivingModeProvider.notifier).state =
                                false;
                            if (r.isOk) {
                              context.push(
                                '/driver/trip/${trip.id}/stop/${current.id}',
                              );
                            } else {
                              await showResult(context, r);
                            }
                          },
                        )
                      else
                        BigButton(
                          label: current.kind == StopKind.pickup
                              ? 'Open passenger manifest'
                              : 'Record drop-off',
                          icon: Icons.groups_outlined,
                          color: AppColors.teal,
                          onPressed: moving
                              ? null
                              : () => context.push(
                                  '/driver/trip/${trip.id}/stop/${current.id}',
                                ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                TelematicsPanel(trip: trip),
                const SizedBox(height: AppSpace.md),
                DrivingLock(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TripTrafficPanel(trip: trip),
                      const SizedBox(height: AppSpace.md),
                      AppCard(
                        padding: const EdgeInsets.all(AppSpace.md),
                        child: GuardSeatsPanel(trip: trip),
                      ),
                      const SizedBox(height: AppSpace.md),
                      Row(
                        children: [
                          Expanded(
                            child: MetricTile(
                              label: 'Expected',
                              value: '${rec.expected}',
                              tone: StatusTone.neutral,
                            ),
                          ),
                          const SizedBox(width: AppSpace.xs),
                          Expanded(
                            child: MetricTile(
                              label: 'On board',
                              value: '${rec.boarded - rec.alighted}',
                              tone: StatusTone.teal,
                            ),
                          ),
                          const SizedBox(width: AppSpace.xs),
                          Expanded(
                            child: MetricTile(
                              label: 'Dropped',
                              value: '${rec.alighted}',
                              tone: StatusTone.success,
                            ),
                          ),
                        ],
                      ),
                      if (rec.noShow > 0) ...[
                        const SizedBox(height: AppSpace.xs),
                        Text(
                          '${rec.noShow} no-show recorded',
                          style: t.bodySmall!.copyWith(
                            color: AppColors.warning,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpace.md),
                      AppCard(
                        padding: const EdgeInsets.all(AppSpace.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    pos.available
                                        ? pos.label
                                        : 'Position not available',
                                    style: t.titleSmall,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () => _showNavigation(
                                    context,
                                    data,
                                    stops,
                                    current,
                                  ),
                                  icon: const Icon(Icons.turn_right_rounded),
                                  label: const Text('Demo navigation'),
                                ),
                              ],
                            ),
                            if (pos.isStale)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppSpace.xs,
                                ),
                                child: InlineBanner(
                                  tone: StatusTone.warning,
                                  title: 'Location may be outdated',
                                  message:
                                      'Last demo update ${Fmt.time(pos.lastUpdate)}.',
                                ),
                              ),
                            SchematicMap(
                              points: points,
                              path: [for (var i = 0; i < points.length; i++) i],
                              vehicle: pos.available
                                  ? Offset(pos.x, pos.y)
                                  : null,
                              vehicleStale: pos.isStale,
                              height: 200,
                            ),
                            const SizedBox(height: 4),
                            SimulatedNote(
                              '${DemoLabels.simulatedLocation} · last update ${Fmt.time(pos.lastUpdate)}',
                              icon: Icons.my_location_outlined,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpace.md),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Overline('Stops'),
                            RouteTimeline(
                              onTap: (i) {
                                final s = stops[i];
                                if (s.status != StopStatus.upcoming ||
                                    s.id == current?.id) {
                                  context.push(
                                    '/driver/trip/${trip.id}/stop/${s.id}',
                                  );
                                }
                              },
                              stops: [
                                for (final s in stops)
                                  TimelineStop(
                                    title: stopTitle(data, s),
                                    subtitle: s.kind == StopKind.pickup
                                        ? 'Pickup · ${s.expectedBoardingCount} expected · ±${stopTolerance(data, s)} min'
                                        : 'Drop · ${s.expectedAlightingCount} expected · ±${stopTolerance(data, s)} min',
                                    kind: s.kind,
                                    status: s.status,
                                    planned: s.plannedArrival,
                                    actual: s.actualArrival,
                                    highlight: s.id == current?.id,
                                    trailing: s.actualArrival == null
                                        ? null
                                        : ToleranceBadge(
                                            actual: s.actualArrival!,
                                            planned: s.plannedArrival,
                                            tolerance: stopTolerance(data, s),
                                          ),
                                    note:
                                        s.issueNote ??
                                        (s.skipReason != null
                                            ? 'Skipped: ${s.skipReason}'
                                            : null),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpace.md),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => context.push(
                                '/driver/report?type=delay&trip=${trip.id}',
                              ),
                              icon: const Icon(Icons.schedule_outlined),
                              label: const Text('Report delay'),
                            ),
                          ),
                          const SizedBox(width: AppSpace.sm),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => context.push(
                                '/driver/report?trip=${trip.id}',
                              ),
                              icon: const Icon(Icons.report_outlined),
                              label: const Text('Report issue'),
                            ),
                          ),
                        ],
                      ),
                      if (current != null) ...[
                        const SizedBox(height: AppSpace.sm),
                        OutlinedButton(
                          onPressed: () =>
                              context.push('/driver/trip/${trip.id}/complete'),
                          child: const Text('Complete trip early (exception)'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showNavigation(
    BuildContext context,
    DataView data,
    List<RouteStop> stops,
    RouteStop? current,
  ) {
    final remaining = stops.where((s) => !s.isDone).toList();
    showAppSheet<void>(
      context,
      title: 'Demo navigation',
      builder: (c) {
        final t = Theme.of(c).textTheme;
        final items = <Widget>[];
        for (var i = 0; i < remaining.length; i++) {
          final s = remaining[i];
          final from = i == 0
              ? null
              : data.location(remaining[i - 1].locationId);
          final to = data.location(s.locationId)!;
          final km = from == null
              ? null
              : GeoRules.roadKm(from, to, RouteVariant.internalRoads);
          items.add(
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: IconTile(
                icon: i == 0
                    ? Icons.navigation_outlined
                    : Icons.turn_right_rounded,
                size: 36,
              ),
              title: Text('${i == 0 ? 'Head to' : 'Continue to'} ${to.name}'),
              subtitle: Text(
                '${km == null ? 'Current leg' : '~${km.toStringAsFixed(1)} km (schematic)'} · planned ${Fmt.time(s.plannedArrival)}',
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const InlineBanner(
              tone: StatusTone.info,
              title: 'Simulated directions',
              message:
                  'Generated from fictional demo coordinates. No real GPS, maps or live traffic are used — follow road signs and dispatcher instructions.',
            ),
            const SizedBox(height: AppSpace.sm),
            if (items.isEmpty)
              Text('No remaining stops.', style: t.bodyMedium)
            else
              ...items,
          ],
        );
      },
    );
  }
}
