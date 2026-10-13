import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/widgets.dart';
import '../../../domain/models/models.dart';
import '../driver_common.dart';
import '../driver_v2_widgets.dart';

enum _Seg { upcoming, active, completed }

/// Schedule from shift start (6:00 AM): upcoming / active / completed.
class DriverTripsScreen extends ConsumerStatefulWidget {
  const DriverTripsScreen({super.key});

  @override
  ConsumerState<DriverTripsScreen> createState() => _DriverTripsScreenState();
}

class _DriverTripsScreenState extends ConsumerState<DriverTripsScreen> {
  _Seg _seg = _Seg.upcoming;

  @override
  Widget build(BuildContext context) {
    final day = ref.watch(driverDayProvider);
    if (day == null) return const LoadingState();
    final all = day.allTrips;
    final active = all
        .where((t) => t.status.isActive && t.actualStart != null)
        .toList();
    final upcoming = all
        .where(
          (t) =>
              t.actualStart == null &&
              !t.status.isTerminal &&
              !t.serviceDate.isBefore(day.data.today),
        )
        .toList();
    final completed = all
        .where((t) => t.status.isTerminal)
        .toList()
        .reversed
        .toList();
    final list = switch (_seg) {
      _Seg.upcoming => upcoming,
      _Seg.active => active,
      _Seg.completed => completed,
    };
    final shiftStart = atMinutes(day.data.today, day.driver.shiftStartMinutes);
    return Scaffold(
      appBar: AppBar(title: const Text('Trips')),
      body: MobilePage(
        children: [
          AppCard(
            color: AppColors.surfaceAlt,
            padding: const EdgeInsets.all(AppSpace.md),
            child: Row(
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                    'Schedule from ${Fmt.time(shiftStart)} · shift ends ${Fmt.minutesOfDay(day.driver.shiftEndMinutes)}',
                    style: AppText.secondary(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          SegmentedButton<_Seg>(
            segments: [
              ButtonSegment(
                value: _Seg.upcoming,
                label: Text('Upcoming (${upcoming.length})'),
              ),
              ButtonSegment(
                value: _Seg.active,
                label: Text('Active (${active.length})'),
              ),
              ButtonSegment(
                value: _Seg.completed,
                label: Text('Done (${completed.length})'),
              ),
            ],
            selected: {_seg},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _seg = s.first),
          ),
          const SizedBox(height: AppSpace.md),
          if (list.isEmpty)
            EmptyState(
              icon: Icons.event_busy_outlined,
              title: switch (_seg) {
                _Seg.upcoming => 'No upcoming trips',
                _Seg.active => 'No active trip',
                _Seg.completed => 'No completed trips yet',
              },
              message: _seg == _Seg.upcoming
                  ? 'New assignments from the Fleet Manager appear here automatically.'
                  : 'Trips you run will be listed here.',
              actionLabel: _seg == _Seg.upcoming ? null : 'Show upcoming',
              onAction: _seg == _Seg.upcoming
                  ? null
                  : () => setState(() => _seg = _Seg.upcoming),
            )
          else
            for (final trip in list) ...[
              DriverTripCard(
                trip: trip,
                showInstructions: _seg == _Seg.upcoming,
                onTap: () => context.push(
                  trip.status.isActive && trip.actualStart != null
                      ? '/driver/trip/${trip.id}/active'
                      : '/driver/trip/${trip.id}',
                ),
              ),
              const SizedBox(height: AppSpace.sm),
            ],
        ],
      ),
    );
  }
}

/// Trip preview/details: route, stops, passengers, deadline, start action.
class DriverTripDetailScreen extends ConsumerStatefulWidget {
  const DriverTripDetailScreen({super.key, required this.tripId});
  final String tripId;

  @override
  ConsumerState<DriverTripDetailScreen> createState() =>
      _DriverTripDetailScreenState();
}

class _DriverTripDetailScreenState
    extends ConsumerState<DriverTripDetailScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final driverId = data.auth.currentDriverId ?? '';
    final trip = data.trips.byId(widget.tripId);
    if (trip == null) {
      return Scaffold(
        appBar: driverAppBar(context, 'Trip'),
        body: EmptyState(
          icon: Icons.search_off_rounded,
          title: 'Trip not found',
          message: 'It may have been removed or reset.',
          actionLabel: 'Back to trips',
          onAction: () => context.go('/driver/trips'),
        ),
      );
    }
    final ops = ref.read(servicesProvider).driverOps;
    final stops = data.trips.stopsOf(trip);
    final v = data.vehicle(trip.assignedVehicleId);
    final mine = trip.assignedDriverId == driverId;
    final blockers = mine && !trip.status.isTerminal && trip.actualStart == null
        ? ops.startBlockers(trip.id, driverId)
        : const <String>[];
    final route = data.trips.routeOf(trip);
    final active = trip.status.isActive && trip.actualStart != null;
    return Scaffold(
      appBar: driverAppBar(context, trip.tripCode, fallback: '/driver/trips'),
      body: MobilePage(
        children: [
          DriverTripCard(trip: trip, showInstructions: true),
          const SizedBox(height: AppSpace.md),
          if (!mine)
            const InlineBanner(
              tone: StatusTone.warning,
              title: 'Not assigned to you',
              message:
                  'This trip was reassigned. It cannot be started from your app.',
            )
          else if (trip.status == TripStatus.cancelled)
            InlineBanner(
              tone: StatusTone.danger,
              title: 'Trip cancelled',
              message:
                  trip.cancellationReason ?? 'Cancelled by the Fleet Manager.',
            )
          else if (trip.status == TripStatus.completed)
            InlineBanner(
              tone: StatusTone.success,
              title: 'Completed ${Fmt.time(trip.actualArrival)}',
              message: trip.distanceKm == null
                  ? 'Distance missing — billing is blocked until it is recorded.'
                  : '${Fmt.km(trip.distanceKm)} recorded.',
            )
          else if (!active && blockers.isNotEmpty)
            StartBlockersBanner(blockers: blockers),
          const SizedBox(height: AppSpace.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Overline('Vehicle & route'),
                KeyValueRow(
                  label: 'Vehicle',
                  value: v == null
                      ? 'Not assigned'
                      : 'Vehicle ${v.vehicleCode} · ${v.fictionalRegistration}',
                  dense: true,
                ),
                KeyValueRow(
                  label: 'Route',
                  value: route == null
                      ? '—'
                      : '${route.routeCode} · ${route.variant.label}',
                  dense: true,
                ),
                KeyValueRow(
                  label: 'Estimate',
                  value: route == null
                      ? '—'
                      : '${Fmt.km(route.estimatedDistanceKm)} · ${Fmt.duration(route.estimatedDurationMinutes)}',
                  dense: true,
                ),
                KeyValueRow(
                  label: 'Start',
                  value: Fmt.dateTime(trip.scheduledStart),
                  dense: true,
                ),
                GuardSeatsPanel(trip: trip),
                if (v != null) DiagnosticsRow(vehicle: v),
                if (trip.absentEmployeeIds.isNotEmpty)
                  KeyValueRow(
                    label: 'Not travelling (reported)',
                    value: trip.absentEmployeeIds.join(', '),
                    dense: true,
                  ),
              ],
            ),
          ),
          if (!trip.status.isTerminal &&
              trip.isAssigned &&
              sameDay(trip.serviceDate, data.today)) ...[
            const SizedBox(height: AppSpace.md),
            TripTrafficPanel(trip: trip),
          ],
          const SizedBox(height: AppSpace.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Overline('Stops'),
                RouteTimeline(
                  stops: [
                    for (final s in stops)
                      TimelineStop(
                        title: stopTitle(data, s),
                        subtitle: s.kind == StopKind.pickup
                            ? 'Pickup · ${s.boardingEmployeeIds.join(', ')}'
                            : 'Drop · ${s.alightingEmployeeIds.join(', ')}',
                        kind: s.kind,
                        status: s.status,
                        planned: s.plannedArrival,
                        actual: s.actualArrival,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          if (mine && active)
            BigButton(
              label: 'Open active trip',
              icon: Icons.navigation_outlined,
              color: AppColors.driverAccent,
              onPressed: () => context.push('/driver/trip/${trip.id}/active'),
            )
          else if (mine && !trip.status.isTerminal)
            BigButton(
              label: 'Start trip',
              icon: Icons.play_arrow_rounded,
              color: AppColors.driverAccent,
              busy: _busy,
              onPressed: blockers.isNotEmpty
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      final r = await ops.startTrip(trip.id, driverId);
                      if (!context.mounted) return;
                      setState(() => _busy = false);
                      if (r.isOk) {
                        context.pushReplacement(
                          '/driver/trip/${trip.id}/active',
                        );
                      } else {
                        await showResult(context, r);
                      }
                    },
            ),
        ],
      ),
    );
  }
}
