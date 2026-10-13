import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/widgets.dart';
import '../../../domain/models/models.dart';
import '../../../domain/rules/capacity_rules.dart';
import '../driver_common.dart';
import '../driver_v2_widgets.dart';

/// Stateful Home: exactly one primary action for the current duty state.
class DriverHomeScreen extends ConsumerStatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  ConsumerState<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends ConsumerState<DriverHomeScreen> {
  bool _busy = false;

  Future<void> _run(Future<Result> Function() action) async {
    setState(() => _busy = true);
    final r = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    await showResult(context, r);
  }

  @override
  Widget build(BuildContext context) {
    final day = ref.watch(driverDayProvider);
    if (day == null) return const LoadingState();
    final t = Theme.of(context).textTheme;
    final d = day.driver;
    final data = day.data;
    final state = day.state;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpace.gutter,
        title: Row(
          children: [
            InitialsAvatar(
              initials: d.initials,
              color: AppColors.driverAccent,
              size: 36,
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.name,
                    style: t.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${d.driverCode} · ${Fmt.weekday(data.now)}',
                    style: t.bodySmall!.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => context.push('/driver/notifications'),
            icon: Badge(
              isLabelVisible: data.unreadCount(UserRole.driver, d.id) > 0,
              label: Text('${data.unreadCount(UserRole.driver, d.id)}'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
          ),
          const SizedBox(width: AppSpace.xs),
        ],
      ),
      body: MobilePage(
        children: [
          _StatusStrip(day: day),
          const SizedBox(height: AppSpace.lg),
          ...switch (state) {
            DutyState.beforeShift => _beforeShift(context, day),
            DutyState.alcoholTest => _alcoholTest(context, day),
            DutyState.alcoholBlocked => _alcoholBlocked(context, day),
            DutyState.needsInspection => _needsInspection(context, day),
            DutyState.inspectionFailed => _inspectionFailed(context, day),
            DutyState.readyForTrip => _readyForTrip(context, day),
            DutyState.tripActive => _tripActive(context, day),
            DutyState.allDone => _allDone(context, day),
            DutyState.shiftEnded => _shiftEnded(context, day),
          },
          const SizedBox(height: AppSpace.xl),
          if (state != DutyState.tripActive && day.pendingToday.length > 1) ...[
            const Overline('Later today'),
            for (final trip in day.pendingToday.skip(1)) ...[
              DriverTripCard(
                trip: trip,
                onTap: () => context.push('/driver/trip/${trip.id}'),
              ),
              const SizedBox(height: AppSpace.sm),
            ],
          ],
          Row(
            children: [
              Expanded(
                child: _QuickAction(
                  icon: Icons.badge_outlined,
                  label: 'Attendance',
                  onTap: () => context.push('/driver/attendance'),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: _QuickAction(
                  icon: Icons.fact_check_outlined,
                  label: 'Inspection',
                  onTap: () => context.push('/driver/inspection'),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: _QuickAction(
                  icon: Icons.report_outlined,
                  label: 'Report issue',
                  onTap: () => context.push('/driver/report'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _hero(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String message,
    List<Widget> extra = const [],
  }) {
    final t = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(icon: icon, color: color, size: 52),
          const SizedBox(height: AppSpace.md),
          Text(title, style: t.headlineSmall),
          const SizedBox(height: AppSpace.xs),
          Text(
            message,
            style: t.bodyLarge!.copyWith(color: AppColors.textSecondary),
          ),
          ...extra,
        ],
      ),
    );
  }

  List<Widget> _beforeShift(BuildContext context, DriverDay day) {
    final shift = day.shift;
    final start =
        shift?.scheduledStart ??
        atMinutes(day.data.today, day.driver.shiftStartMinutes);
    final end =
        shift?.scheduledEnd ??
        atMinutes(day.data.today, day.driver.shiftEndMinutes);
    return [
      _hero(
        context,
        icon: Icons.wb_twilight_rounded,
        color: AppColors.driverAccent,
        title: 'Shift ${Fmt.time(start)} – ${Fmt.time(end)}',
        message:
            '${day.todayTrips.where((t) => t.status != TripStatus.cancelled).length} trip(s) scheduled today'
            '${day.vehicle != null ? ' · Vehicle ${day.vehicle!.vehicleCode}' : ''}. Check in when you reach the depot.',
      ),
      const SizedBox(height: AppSpace.md),
      BigButton(
        label: 'Start shift',
        icon: Icons.login_rounded,
        color: AppColors.driverAccent,
        busy: _busy,
        onPressed: () => _run(
          () => ref.read(servicesProvider).driverOps.checkIn(day.driver.id),
        ),
      ),
    ];
  }

  List<Widget> _alcoholTest(BuildContext context, DriverDay day) {
    final policy = day.data.policy;
    final trip = day.nextTrip;
    final everyTrip = policy.alcoholCheckPoint == AlcoholCheckPoint.everyTrip;
    return [
      if (day.alcoholBlockLifted) ...[
        const InlineBanner(
          tone: StatusTone.info,
          title: 'Block lifted — retest required',
          message:
              'The Fleet Manager reviewed your failed test. Take a new test before driving.',
        ),
        const SizedBox(height: AppSpace.md),
      ],
      _hero(
        context,
        icon: Icons.air_rounded,
        color: AppColors.primary,
        title: 'Alcohol test',
        message: everyTrip && trip != null
            ? 'Required before ${trip.tripCode}. Limit ${policy.alcoholThresholdMg.toStringAsFixed(0)} mg/100 ml.'
            : 'Required before your shift. Limit ${policy.alcoholThresholdMg.toStringAsFixed(0)} mg/100 ml.',
        extra: [
          const SizedBox(height: AppSpace.sm),
          for (final b in day.alcoholBlockers)
            Text(b, style: AppText.secondary(context)),
        ],
      ),
      const SizedBox(height: AppSpace.md),
      BigButton(
        label: 'Take alcohol test',
        icon: Icons.air_rounded,
        onPressed: () => context.push(
          '/driver/alcohol${everyTrip && trip != null ? '?trip=${trip.id}' : ''}',
        ),
      ),
      const SizedBox(height: AppSpace.xs),
      const SimulatedNote(
        'Readings come from a simulated breathalyzer · no hardware is connected.',
      ),
    ];
  }

  List<Widget> _alcoholBlocked(BuildContext context, DriverDay day) {
    final fail = day.alcoholFail!;
    return [
      InlineBanner(
        tone: StatusTone.danger,
        title: 'Fleet Manager review required',
        message:
            'Alcohol test at ${Fmt.time(fail.testedAt)} read ${fail.readingMg.toStringAsFixed(0)} mg/100 ml (limit ${fail.thresholdMg.toStringAsFixed(0)}). '
            'Your trips are on hold. Do not drive.',
      ),
      const SizedBox(height: AppSpace.md),
      if (day.nextTrip != null)
        DriverTripCard(
          trip: day.nextTrip!,
          onTap: () => context.push('/driver/trip/${day.nextTrip!.id}'),
        ),
      const SizedBox(height: AppSpace.md),
      BigButton(
        label: 'View test details',
        icon: Icons.air_rounded,
        outlined: true,
        onPressed: () => context.push('/driver/alcohol'),
      ),
    ];
  }

  List<Widget> _needsInspection(BuildContext context, DriverDay day) {
    final v = day.vehicle!;
    final seats = CapacityRules.breakdown(v);
    return [
      _hero(
        context,
        icon: Icons.fact_check_outlined,
        color: AppColors.primary,
        title: 'Inspect Vehicle ${v.vehicleCode}',
        message: 'Complete the pre-trip safety check before starting any trip.',
        extra: [
          const SizedBox(height: AppSpace.md),
          KeyValueRow(
            label: 'Registration',
            value: v.fictionalRegistration,
            dense: true,
          ),
          KeyValueRow(
            label: 'Type',
            value: '${v.propulsion.label} ${v.type.label}',
            dense: true,
          ),
          KeyValueRow(
            label: 'Employee seats',
            value: '${seats.passengerCapacity}',
            dense: true,
          ),
        ],
      ),
      const SizedBox(height: AppSpace.md),
      BigButton(
        label: 'Inspect Vehicle ${v.vehicleCode}',
        icon: Icons.checklist_rounded,
        onPressed: () => context.push('/driver/inspection?vehicle=${v.id}'),
      ),
    ];
  }

  List<Widget> _inspectionFailed(BuildContext context, DriverDay day) {
    final insp = day.todayInspection!;
    final v = day.vehicle!;
    final inc = day.data.incident(insp.defectIncidentId);
    return [
      InlineBanner(
        tone: StatusTone.danger,
        title: 'Trip start blocked',
        message:
            'Vehicle ${v.vehicleCode} failed a critical inspection item: ${insp.criticalFailures.map((i) => i.label).join(', ')}.'
            '${inc != null ? ' Defect ${inc.reference} was sent to the Fleet Manager console (local demo).' : ''}',
      ),
      const SizedBox(height: AppSpace.md),
      if (inc != null && !inc.replacementRequested)
        BigButton(
          label: 'Request replacement vehicle',
          icon: Icons.swap_horiz_rounded,
          color: AppColors.danger,
          busy: _busy,
          onPressed: () => _run(
            () => ref
                .read(servicesProvider)
                .incidents
                .requestReplacement(inc.id, Actor.driver(day.driver.id)),
          ),
        )
      else
        const InlineBanner(
          tone: StatusTone.info,
          title: 'Replacement requested',
          message:
              'Wait for the Fleet Manager to reassign your trip or vehicle. Your Home screen updates automatically.',
        ),
      const SizedBox(height: AppSpace.sm),
      if (day.nextTrip != null)
        DriverTripCard(
          trip: day.nextTrip!,
          onTap: () => context.push('/driver/trip/${day.nextTrip!.id}'),
        ),
    ];
  }

  List<Widget> _readyForTrip(BuildContext context, DriverDay day) {
    final trip = day.nextTrip!;
    final ops = ref.read(servicesProvider).driverOps;
    final blockers = ops.startBlockers(trip.id, day.driver.id);
    final firstStop = day.data.trips.stopsOf(trip).firstOrNull;
    return [
      const Overline('Next trip'),
      DriverTripCard(
        trip: trip,
        showInstructions: true,
        onTap: () => context.push('/driver/trip/${trip.id}'),
      ),
      const SizedBox(height: AppSpace.md),
      if (sameDay(trip.serviceDate, day.data.today) && trip.isAssigned) ...[
        TripTrafficPanel(trip: trip, compact: true),
        const SizedBox(height: AppSpace.md),
      ],
      if (blockers.isNotEmpty) ...[
        StartBlockersBanner(blockers: blockers),
        const SizedBox(height: AppSpace.md),
      ] else if (firstStop != null) ...[
        Text(
          'First pickup ${Fmt.time(firstStop.plannedArrival)} at ${stopTitle(day.data, firstStop)}',
          style: AppText.secondary(context),
        ),
        const SizedBox(height: AppSpace.md),
      ],
      BigButton(
        label: 'Start trip ${trip.tripCode}',
        icon: Icons.play_arrow_rounded,
        color: AppColors.driverAccent,
        busy: _busy,
        onPressed: blockers.isNotEmpty
            ? null
            : () async {
                setState(() => _busy = true);
                final r = await ops.startTrip(trip.id, day.driver.id);
                if (!mounted || !context.mounted) return;
                setState(() => _busy = false);
                if (r.isOk) {
                  showToast(context, 'Trip ${trip.tripCode} started');
                  context.push('/driver/trip/${trip.id}/active');
                } else {
                  await showResult(context, r);
                }
              },
      ),
      if (trip.status == TripStatus.assigned) ...[
        const SizedBox(height: AppSpace.sm),
        BigButton(
          label: 'Accept trip',
          icon: Icons.thumb_up_alt_outlined,
          outlined: true,
          onPressed: _busy
              ? null
              : () => _run(() => ops.acceptTrip(trip.id, day.driver.id)),
        ),
      ],
    ];
  }

  List<Widget> _tripActive(BuildContext context, DriverDay day) {
    final trip = day.activeTrip!;
    final data = day.data;
    final stop = data.trips.currentStop(trip);
    final rec = ref.read(servicesProvider).driverOps.reconcile(trip);
    final t = Theme.of(context).textTheme;
    return [
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
                  '${trip.tripCode} IN PROGRESS',
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
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              stop == null
                  ? 'All stops done'
                  : 'Next: ${stopTitle(data, stop)}',
              style: t.headlineSmall!.copyWith(color: Colors.white),
            ),
            if (stop != null) ...[
              const SizedBox(height: 4),
              Text(
                '${stop.kind == StopKind.pickup ? 'Pickup ${stop.expectedBoardingCount}' : 'Drop ${stop.expectedAlightingCount}'} · planned ${Fmt.time(stop.plannedArrival)}',
                style: t.bodyLarge!.copyWith(color: Colors.white70),
              ),
            ],
            const SizedBox(height: AppSpace.md),
            Text(
              'On board ${rec.boarded - rec.alighted} · Boarded ${rec.boarded}/${rec.expected} · Dropped ${rec.alighted}',
              style: t.bodyMedium!.copyWith(color: Colors.white),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpace.md),
      BigButton(
        label: 'Open active trip',
        icon: Icons.navigation_outlined,
        color: AppColors.driverAccent,
        onPressed: () => context.push('/driver/trip/${trip.id}/active'),
      ),
      const SizedBox(height: AppSpace.md),
      TripTrafficPanel(trip: trip, compact: true),
    ];
  }

  List<Widget> _allDone(BuildContext context, DriverDay day) {
    final s = ref.read(servicesProvider).driverOps.shiftSummary(day.driver.id);
    return [
      _hero(
        context,
        icon: Icons.task_alt_rounded,
        color: AppColors.success,
        title: day.todayTrips.isEmpty ? 'No trips assigned' : 'All trips done',
        message: day.todayTrips.isEmpty
            ? 'Nothing is assigned to you today yet. New assignments appear here automatically.'
            : '${s.completedTrips} trip(s) completed · ${s.passengersCarried} passengers · ${s.distanceKm.toStringAsFixed(1)} km recorded.',
      ),
      const SizedBox(height: AppSpace.md),
      BigButton(
        label: 'Review & end shift',
        icon: Icons.logout_rounded,
        onPressed: () => context.push('/driver/shift-summary'),
      ),
    ];
  }

  List<Widget> _shiftEnded(BuildContext context, DriverDay day) {
    final shift = day.shift!;
    return [
      _hero(
        context,
        icon: Icons.nightlight_round_outlined,
        color: AppColors.deepNavy,
        title: 'Shift complete',
        message:
            'Checked in ${Fmt.time(shift.actualCheckIn)} · checked out ${Fmt.time(shift.actualCheckOut)}.'
            '${shift.handoverParkingId != null ? ' Vehicle handed over at ${day.data.locationLabel(shift.handoverParkingId)}.' : ''}',
      ),
      const SizedBox(height: AppSpace.md),
      BigButton(
        label: 'View shift summary',
        icon: Icons.summarize_outlined,
        outlined: true,
        onPressed: () => context.push('/driver/shift-summary'),
      ),
    ];
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.day});
  final DriverDay day;

  @override
  Widget build(BuildContext context) {
    final shift = day.shift;
    final insp = day.todayInspection;
    final v = day.vehicle;
    return Wrap(
      spacing: AppSpace.xs,
      runSpacing: AppSpace.xs,
      children: [
        StatusBadge(
          shift == null || shift.actualCheckIn == null
              ? 'Not checked in'
              : shift.status.label,
          tone: shift == null || shift.actualCheckIn == null
              ? StatusTone.neutral
              : Tones.shift(shift.status),
          icon: Icons.badge_outlined,
        ),
        if (v != null)
          StatusBadge(
            insp == null
                ? 'Vehicle ${v.vehicleCode} · not inspected'
                : 'Vehicle ${v.vehicleCode} · ${insp.overallStatus.label}',
            tone: insp == null
                ? StatusTone.neutral
                : Tones.inspection(insp.overallStatus),
            icon: Icons.directions_car_outlined,
          ),
        StatusBadge(
          day.driver.status.label,
          tone: Tones.driver(day.driver.status),
          icon: Icons.person_outline_rounded,
        ),
        if (day.driver.licenceExpiry case final exp?)
          if (exp.difference(day.data.today).inDays case final days
              when days <= 30)
            StatusBadge(
              days < 0 ? 'Licence expired' : 'Licence expires in $days d',
              tone: days < 0 ? StatusTone.danger : StatusTone.warning,
              icon: Icons.badge_outlined,
            ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppCard(
    onTap: onTap,
    padding: const EdgeInsets.symmetric(
      vertical: AppSpace.md,
      horizontal: AppSpace.xs,
    ),
    semanticLabel: label,
    child: Column(
      children: [
        Icon(icon, color: AppColors.textSecondary),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    ),
  );
}
