import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import 'employee_common.dart';

class EmployeeTripDetailScreen extends ConsumerWidget {
  const EmployeeTripDetailScreen({super.key, required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final e = ref.watch(currentEmployeeProvider);
    final trip = data.trips.byId(tripId);
    if (e == null) return const Scaffold(body: LoadingState());
    if (trip == null || !employeeCanSee(trip, e.id)) {
      return EmployeeSubPage(
        title: 'Trip',
        children: [
          EmptyState(
            icon: Icons.search_off_rounded,
            title: 'Trip not available',
            message:
                'This trip does not exist or you are no longer on it. It may have been reassigned.',
            actionLabel: 'Back to my trips',
            onAction: () => context.go('/employee/trips'),
          ),
        ],
      );
    }
    final view = EmployeeTripView(data, trip, e.id);
    final t = Theme.of(context).textTheme;
    final now = data.now;
    final stops = data.trips.stopsOf(trip);
    final position = ref.watch(locationServiceProvider).positionOf(trip);
    final share = data.settingsFor('employee:${e.id}').shareSimulatedLocation;
    final locs = data.locationMap;
    final points = [
      for (final s in stops)
        MapPoint(
          x: locs[s.locationId]?.demoX ?? 0,
          y: locs[s.locationId]?.demoY ?? 0,
          label: locs[s.locationId]?.code ?? s.locationId,
          kind: locs[s.locationId]?.type ?? LocationType.pickup,
          emphasis: s.id == view.pickup?.id || s.id == view.drop?.id,
          done: s.isDone,
        ),
    ];
    final coRiders = trip.employeeIds.length - 1;
    final cancelled = trip.status == TripStatus.cancelled;
    final employer = data.employer(trip.employerId);
    final tol = e.toleranceMinutes(employer);
    final deadline = effectiveDeadlineMinutes(e, employer);
    final showTraffic =
        sameDay(trip.serviceDate, data.today) &&
        trip.isAssigned &&
        !trip.status.isTerminal &&
        !view.isAbsent;
    final traffic = showTraffic
        ? ref.read(servicesProvider).traffic.statusOf(trip)
        : null;
    final applied = data
        .revisionsOf(trip.id)
        .where((r) => r.status == RevisionStatus.applied)
        .toList();
    final pending = data.openRevision(trip.id);
    final canShowPass =
        !cancelled && !view.isAbsent && trip.status != TripStatus.completed;

    return EmployeeSubPage(
      title: trip.tripCode,
      actions: [
        IconButton(
          tooltip: 'Report an issue',
          onPressed: () =>
              context.push('/employee/support/new?trip=${trip.id}'),
          icon: const Icon(Icons.support_agent_outlined),
        ),
      ],
      bottom: canShowPass
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.gutter,
                  AppSpace.xs,
                  AppSpace.gutter,
                  AppSpace.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () =>
                            context.push('/employee/trip/${trip.id}/pass'),
                        icon: const Icon(Icons.qr_code_2_rounded),
                        label: const Text('Show e-pass'),
                      ),
                    ),
                    const SizedBox(width: AppSpace.xs),
                    Tooltip(
                      message: 'Safety & SOS',
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger),
                        ),
                        onPressed: () => context.push('/employee/safety'),
                        child: const Icon(Icons.sos_outlined),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      children: [
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: AppSpace.xs,
                runSpacing: AppSpace.xs,
                children: [
                  TripStatusBadge(trip.status),
                  if (!cancelled)
                    StatusBadge(
                      passengerStateLabel(view.state),
                      tone: Tones.passenger(view.state),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.xs),
            Text(
              Fmt.weekday(trip.serviceDate),
              style: t.bodySmall!.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        if (view.isAbsent) ...[
          const InlineBanner(
            tone: StatusTone.neutral,
            icon: Icons.event_busy_outlined,
            title: 'You marked yourself absent — seat released',
            message:
                'You are no longer on this trip. Your seat may be offered to a colleague.',
          ),
          const SizedBox(height: AppSpace.md),
        ],
        if (cancelled) ...[
          InlineBanner(
            tone: StatusTone.danger,
            title: 'This trip was cancelled',
            message: trip.cancellationReason ?? 'No reason recorded.',
            actions: [
              OutlinedButton(
                onPressed: () => context.go('/employee/book'),
                child: const Text('Request transport'),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
        ],
        if (tripAlertText(data, trip) != null) ...[
          InlineBanner(
            tone: StatusTone.warning,
            title: trip.status == TripStatus.needsAttention
                ? 'Trip under review'
                : 'Delay reported',
            message: tripAlertText(data, trip),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TimeRow(
                label: 'Pickup',
                place: view.pickupLocation?.name ?? '—',
                planned: view.pickupTime,
                actual: view.pickup?.actualArrival,
                detail: view.pickup?.actualArrival == null
                    ? 'Pickup window ${pickupWindowText(view.pickupTime, tol)}'
                    : ToleranceRules.describe(
                        view.pickup!.actualArrival!,
                        view.pickupTime,
                        tol,
                      ),
                detailTone: view.pickup?.actualArrival == null
                    ? null
                    : ToleranceRules.within(
                        view.pickup!.actualArrival!,
                        view.pickupTime,
                        tol,
                      )
                    ? StatusTone.success
                    : StatusTone.warning,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpace.sm),
                child: Divider(),
              ),
              _TimeRow(
                label: 'Drop',
                place: view.dropLocation?.name ?? '—',
                planned: view.dropTime ?? trip.scheduledStart,
                actual: view.drop?.actualArrival,
                detail:
                    view.drop?.actualArrival == null || view.dropTime == null
                    ? null
                    : ToleranceRules.describe(
                        view.drop!.actualArrival!,
                        view.dropTime!,
                        tol,
                      ),
                detailTone: view.drop?.actualArrival == null
                    ? null
                    : StatusTone.neutral,
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                'Arrival deadline ${Fmt.minutesOfDay(deadline)} · ${coRiders <= 0 ? 'Solo ride' : 'Shared with $coRiders colleague${coRiders == 1 ? '' : 's'}'}',
                style: AppText.muted(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        _DriverVehicleCard(view: view),
        if (applied.isNotEmpty && !trip.status.isTerminal) ...[
          const SizedBox(height: AppSpace.md),
          _ScheduleChangeBanner(
            revision: applied.first,
            pickupStopId: view.pickup?.id,
            tolerance: tol,
          ),
        ],
        if (traffic != null) ...[
          const SizedBox(height: AppSpace.sectionGap),
          _TrafficCard(
            status: traffic,
            pickupStopId: view.pickup?.id,
            underReview: pending != null,
            now: data.now,
          ),
        ],
        const SizedBox(height: AppSpace.sectionGap),
        const SectionHeader(
          title: 'Live position',
          subtitle: DemoLabels.simulatedLocation,
        ),
        const SizedBox(height: AppSpace.sm),
        AppCard(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SchematicMap(
                points: points,
                path: [for (var i = 0; i < points.length; i++) i],
                vehicle: position.available && share
                    ? Offset(position.x, position.y)
                    : null,
                vehicleStale: position.isStale,
                height: 200,
              ),
              const SizedBox(height: AppSpace.sm),
              if (!share)
                const InlineBanner(
                  tone: StatusTone.neutral,
                  title: 'Location view is off',
                  message:
                      'Turn on "Show simulated vehicle position" in Profile › Privacy to see it.',
                )
              else if (!position.available)
                InlineBanner(
                  tone: StatusTone.neutral,
                  title: 'Position not available',
                  message: trip.status == TripStatus.completed
                      ? 'This trip has finished.'
                      : cancelled
                      ? 'Trip cancelled.'
                      : 'The simulated position appears once your driver starts the trip.',
                )
              else ...[
                Row(
                  children: [
                    const Icon(
                      Icons.navigation_outlined,
                      size: 18,
                      color: AppColors.teal,
                    ),
                    const SizedBox(width: AppSpace.xs),
                    Expanded(child: Text(position.label, style: t.titleSmall)),
                    Text(
                      'Updated ${position.lastUpdate == null ? '—' : Fmt.ago(position.lastUpdate!, now)}',
                      style: AppText.muted(context),
                    ),
                  ],
                ),
                if (position.isStale) ...[
                  const SizedBox(height: AppSpace.sm),
                  InlineBanner(
                    tone: StatusTone.warning,
                    title: 'Position may be outdated',
                    message:
                        'Last demo update ${Fmt.time(position.lastUpdate)}. The vehicle may have moved since.',
                  ),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpace.sectionGap),
        SectionHeader(
          title: 'Stops',
          subtitle: '${stops.length} stops · co-riders shown only as counts',
        ),
        const SizedBox(height: AppSpace.sm),
        AppCard(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.md,
            AppSpace.md,
            AppSpace.md,
            0,
          ),
          child: stops.isEmpty
              ? const Padding(
                  padding: EdgeInsets.only(bottom: AppSpace.md),
                  child: Text('Route not planned yet.'),
                )
              : RouteTimeline(
                  stops: [
                    for (final s in stops)
                      TimelineStop(
                        title: locs[s.locationId]?.name ?? s.locationId,
                        subtitle: s.id == view.pickup?.id
                            ? 'Your pickup'
                            : s.id == view.drop?.id
                            ? 'Your drop'
                            : '${s.kind == StopKind.pickup ? s.expectedBoardingCount : s.expectedAlightingCount} ${s.kind == StopKind.pickup ? 'boarding' : 'alighting'}',
                        kind: s.kind,
                        status: s.status,
                        planned: s.plannedArrival,
                        actual: s.actualArrival,
                        highlight:
                            s.id == view.pickup?.id || s.id == view.drop?.id,
                      ),
                  ],
                ),
        ),
        if (trip.status == TripStatus.completed) ...[
          const SizedBox(height: AppSpace.md),
          AppCard(
            child: Column(
              children: [
                KeyValueRow(
                  label: 'Started',
                  value: Fmt.time(trip.actualStart),
                ),
                KeyValueRow(
                  label: 'Completed',
                  value: Fmt.time(trip.actualArrival),
                ),
                KeyValueRow(label: 'Distance', value: Fmt.km(trip.distanceKm)),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpace.md),
        TextButton.icon(
          onPressed: () =>
              context.push('/employee/support/new?trip=${trip.id}'),
          icon: const Icon(Icons.flag_outlined),
          label: const Text('Report an issue with this trip'),
        ),
        if (view.canReportAbsence)
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => reportAbsenceFlow(context, ref, trip, e.id),
            icon: const Icon(Icons.event_busy_outlined),
            label: const Text("I'm not travelling"),
          ),
      ],
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.label,
    required this.place,
    required this.planned,
    this.actual,
    this.detail,
    this.detailTone,
  });
  final String label;
  final String place;
  final DateTime planned;
  final DateTime? actual;

  /// Window or deviation line; shown as a badge when [detailTone] is set.
  final String? detail;
  final StatusTone? detailTone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        SizedBox(
          width: 76,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Fmt.time(actual ?? planned),
                style: t.titleMedium!.copyWith(fontFeatures: AppText.tabular),
              ),
              Text(
                actual != null ? 'actual' : 'planned',
                style: AppText.muted(context),
              ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(), style: AppText.overline(context)),
              Text(place, style: t.titleSmall),
              if (detail != null) ...[
                const SizedBox(height: 4),
                if (detailTone != null)
                  StatusBadge(detail!, tone: detailTone!, dense: true)
                else
                  Text(detail!, style: AppText.muted(context)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DriverVehicleCard extends StatelessWidget {
  const _DriverVehicleCard({required this.view});
  final EmployeeTripView view;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final d = view.driver;
    final v = view.vehicle;
    if (d == null || v == null) {
      return const InlineBanner(
        tone: StatusTone.info,
        title: 'Awaiting assignment',
        message:
            'A driver and vehicle will be shown here once the Fleet Manager assigns them.',
      );
    }
    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              InitialsAvatar(
                initials: d.initials,
                color: AppColors.teal,
                size: 44,
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.name, style: t.titleMedium),
                    Text(
                      'Driver ${d.driverCode} · contact ${d.fictionalContact} (fictional)',
                      style: t.bodySmall!.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpace.sm),
            child: Divider(),
          ),
          Row(
            children: [
              IconTile(
                icon: vehicleIcon(v),
                color: v.isEv ? AppColors.teal : AppColors.primary,
                size: 44,
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vehicle ${v.vehicleCode} · ${v.fictionalRegistration}',
                      style: t.titleSmall,
                    ),
                    Text(
                      '${v.model.isEmpty ? v.type.label : v.model} · ${v.luxuryClass.label}',
                      style: t.bodySmall!.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              StatusBadge(
                v.propulsion.label,
                tone: v.isEv ? StatusTone.teal : StatusTone.neutral,
                dense: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shown when the Fleet Manager applied a traffic-driven schedule change.
class _ScheduleChangeBanner extends StatelessWidget {
  const _ScheduleChangeBanner({
    required this.revision,
    required this.pickupStopId,
    required this.tolerance,
  });
  final RouteRevision revision;
  final String? pickupStopId;
  final int tolerance;

  @override
  Widget build(BuildContext context) {
    final mine = revision.stops
        .where((s) => s.stopId == pickupStopId)
        .firstOrNull;
    final moved = mine != null && mine.shiftMinutes != 0;
    return InlineBanner(
      tone: StatusTone.info,
      icon: Icons.update_rounded,
      title: moved
          ? 'Pickup time updated for traffic'
          : 'Schedule updated for traffic',
      message: moved
          ? 'New pickup ${Fmt.time(mine.proposed)} (was ${Fmt.time(mine.previous)}). '
                '${mine.shiftMinutes.abs() > tolerance ? 'This is outside your ±$tolerance min window. ' : ''}'
                'Reason: ${revision.reason}'
          : 'Your pickup time is unchanged. ${revision.reason}',
      messages: const ['Simulated traffic — applied by the Fleet Manager.'],
    );
  }
}

/// Today's traffic status for this trip (simulated provider).
class _TrafficCard extends StatelessWidget {
  const _TrafficCard({
    required this.status,
    required this.pickupStopId,
    required this.underReview,
    required this.now,
  });
  final TrafficTripStatus status;
  final String? pickupStopId;
  final bool underReview;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (!status.available) {
      return const InlineBanner(
        tone: StatusTone.neutral,
        icon: Icons.traffic_outlined,
        title: 'Traffic data unavailable',
        message:
            'Showing your planned schedule. No live or simulated traffic is being applied.',
      );
    }
    // Not-started trips are re-timed from a recommended earlier departure,
    // so the impact shows as "leave earlier" rather than a positive delay.
    final earlier = status.earlierDepartureMinutes;
    final delayed = status.delayMinutes >= 3 || !status.feasible || earlier > 0;
    final tone = !status.feasible
        ? StatusTone.danger
        : delayed
        ? StatusTone.warning
        : StatusTone.success;
    final proposedPickup = pickupStopId == null
        ? null
        : status.proposedTimes[pickupStopId];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconTile(
                icon: Icons.traffic_outlined,
                color: tone.foreground,
                background: tone.background,
                size: 40,
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Traffic', style: t.titleSmall),
                    Text('Simulated traffic', style: AppText.muted(context)),
                  ],
                ),
              ),
              Flexible(child: StatusBadge(status.statusLabel, tone: tone)),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          KeyValueRow(
            label: 'Estimated delay',
            value: earlier > 0
                ? '~$earlier min if leaving as planned'
                : status.delayMinutes <= 0
                ? 'None'
                : '~${status.delayMinutes} min',
            dense: true,
          ),
          if (earlier > 0)
            KeyValueRow(
              label: 'Suggested departure',
              value:
                  '${Fmt.time(status.proposedDeparture)} ($earlier min earlier)',
              dense: true,
            ),
          KeyValueRow(
            label: earlier > 0 ? 'Final drop if leaving earlier' : 'Final drop',
            value:
                '${Fmt.time(status.estimatedFinal)} est. · planned ${Fmt.time(status.plannedFinal)}',
            dense: true,
          ),
          if (proposedPickup != null && delayed)
            KeyValueRow(
              label: 'Possible new pickup',
              value: Fmt.time(proposedPickup),
              dense: true,
            ),
          if (underReview) ...[
            const SizedBox(height: AppSpace.xs),
            const InlineBanner(
              tone: StatusTone.info,
              title: 'Schedule under review',
              message:
                  'The Fleet Manager is reviewing a traffic adjustment. You will be notified if your pickup time changes.',
            ),
          ],
          const SizedBox(height: AppSpace.xs),
          SimulatedNote(
            '${DemoLabels.trafficSimulated} · updated ${Fmt.ago(status.lastUpdate, now)}',
          ),
        ],
      ),
    );
  }
}
