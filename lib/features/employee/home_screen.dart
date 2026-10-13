import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import '../shared/notifications_view.dart';
import 'employee_common.dart';

class EmployeeHomeScreen extends ConsumerWidget {
  const EmployeeHomeScreen({super.key});

  String _greeting(DateTime now) => now.hour < 12
      ? 'Good morning'
      : now.hour < 17
      ? 'Good afternoon'
      : 'Good evening';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final e = ref.watch(currentEmployeeProvider);
    if (e == null) return const LoadingState();
    final t = Theme.of(context).textTheme;
    final now = data.now;
    final next = nextTrip(data, e.id);
    final upcoming = employeeTrips(data, e.id)
        .where(
          (v) =>
              v.isUpcoming &&
              v.trip.id != next?.trip.id &&
              !dateOnly(v.trip.serviceDate).isBefore(data.today),
        )
        .take(3)
        .toList();
    final unread = data.unreadCount(UserRole.employee, e.id);
    final alerts = data
        .notificationsFor(UserRole.employee, e.id)
        .where(
          (n) =>
              {
                NotificationCategory.delay,
                NotificationCategory.routeChange,
                NotificationCategory.serviceNotice,
              }.contains(n.category) &&
              now.difference(n.createdAt).inHours < 48,
        )
        .take(3)
        .toList();
    final openRequests = data
        .bookingsOf(e.id)
        .where((b) => b.status.isOpen)
        .toList();

    return SafeArea(
      bottom: false,
      child: MobilePage(
        children: [
          const SizedBox(height: AppSpace.sm),
          Row(
            children: [
              InitialsAvatar(initials: e.initials, size: 44),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_greeting(now)}, ${e.firstName}',
                      style: t.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${Fmt.weekdayLong(now)} · ${e.employeeCode}',
                      style: t.bodySmall!.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: unread > 0
                    ? 'Notifications, $unread unread'
                    : 'Notifications',
                onPressed: () => context.push('/employee/notifications'),
                icon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text('$unread'),
                  child: const Icon(Icons.notifications_none_rounded),
                ),
              ),
            ],
          ),
          if (openSosOf(data, e.id) case final sos?) ...[
            const SizedBox(height: AppSpace.md),
            InlineBanner(
              tone: StatusTone.danger,
              icon: Icons.sos_outlined,
              title: 'SOS active (${sos.reference})',
              message: 'Escalation in progress. ${DemoLabels.sosDemo}',
              actions: [
                OutlinedButton(
                  onPressed: () => context.push('/employee/safety'),
                  child: const Text('View escalation'),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpace.lg),
          if (next != null)
            _NextTripCard(view: next)
          else
            _NoTripCard(hasRequests: openRequests.isNotEmpty),
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              Expanded(
                child: _QuickAction(
                  icon: Icons.calendar_view_week_outlined,
                  label: 'Schedule',
                  onTap: () => context.push('/employee/roster'),
                ),
              ),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: _QuickAction(
                  icon: Icons.add_road_rounded,
                  label: 'Request',
                  onTap: () => context.go('/employee/book'),
                ),
              ),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: _QuickAction(
                  icon: Icons.health_and_safety_outlined,
                  label: 'Safety',
                  onTap: () => context.push('/employee/safety'),
                ),
              ),
            ],
          ),
          if (alerts.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sectionGap),
            const SectionHeader(title: 'Service alerts'),
            const SizedBox(height: AppSpace.sm),
            for (final n in alerts)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.xs),
                child: AppCard(
                  padding: const EdgeInsets.all(AppSpace.md),
                  onTap: () async {
                    await ref
                        .read(servicesProvider)
                        .notifications
                        .markRead(n.id);
                    if (context.mounted) {
                      openEmployeeEntity(
                        context,
                        n.relatedEntityType,
                        n.relatedEntityId,
                      );
                    }
                  },
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconTile(
                        icon: notificationIcon(n.category),
                        color: notificationTone(n.category).foreground,
                        background: notificationTone(n.category).background,
                        size: 36,
                      ),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(n.title, style: t.titleSmall),
                            const SizedBox(height: 2),
                            Text(
                              n.body,
                              style: t.bodySmall!.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        Fmt.ago(n.createdAt, now),
                        style: AppText.muted(context),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: AppSpace.sectionGap),
          SectionHeader(
            title: 'Upcoming',
            trailing: TextButton(
              onPressed: () => context.go('/employee/trips'),
              child: const Text('All trips'),
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          if (upcoming.isEmpty && openRequests.isEmpty)
            AppCard(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Text(
                'No other trips scheduled. Assigned trips and request updates appear here automatically.',
                style: t.bodyMedium!.copyWith(color: AppColors.textSecondary),
              ),
            ),
          for (final v in upcoming)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: EmployeeTripTile(view: v),
            ),
          for (final b in openRequests)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: AppCard(
                padding: const EdgeInsets.all(AppSpace.md),
                onTap: () => context.push('/employee/booking/${b.id}'),
                child: Row(
                  children: [
                    const IconTile(
                      icon: Icons.event_note_outlined,
                      color: AppColors.teal,
                      size: 40,
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Request ${b.reference}', style: t.titleSmall),
                          Text(
                            '${Fmt.dayLabel(b.requestedDate, now)} · arrive by ${Fmt.minutesOfDay(b.requestedArrivalMinutes)} · ${b.requestedDestinationId}',
                            style: t.bodySmall!.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    StatusBadge(
                      b.status.label,
                      tone: Tones.booking(b.status),
                      dense: true,
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppSpace.lg),
          const SimulatedNote(
            DemoLabels.localOnly,
            icon: Icons.info_outline_rounded,
          ),
        ],
      ),
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
    padding: const EdgeInsets.symmetric(
      vertical: AppSpace.md,
      horizontal: AppSpace.xs,
    ),
    onTap: onTap,
    semanticLabel: label,
    child: Column(
      children: [
        Icon(icon, color: AppColors.primary),
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    ),
  );
}

class _NoTripCard extends StatelessWidget {
  const _NoTripCard({required this.hasRequests});
  final bool hasRequests;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const IconTile(icon: Icons.event_busy_outlined, size: 44),
          const SizedBox(height: AppSpace.md),
          Text('No upcoming trip assigned', style: t.titleMedium),
          const SizedBox(height: 4),
          Text(
            hasRequests
                ? 'Your request is with the Fleet Manager. You will see the driver and vehicle here once it is assigned.'
                : 'Request transport for a date and arrival time. The Fleet Manager reviews and assigns a vehicle.',
            style: t.bodyMedium!.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpace.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.go('/employee/book'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Request transport'),
            ),
          ),
        ],
      ),
    );
  }
}

class _NextTripCard extends ConsumerWidget {
  const _NextTripCard({required this.view});
  final EmployeeTripView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final trip = view.trip;
    final now = view.data.now;
    final v = view.vehicle;
    final d = view.driver;
    final active = view.isActive;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: AppRadius.xlAll,
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.subtle,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.lg,
              AppSpace.lg,
              AppSpace.md,
            ),
            decoration: const BoxDecoration(
              color: AppColors.midnightNavy,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppRadius.xl),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        active
                            ? 'TRIP IN PROGRESS'
                            : 'NEXT TRIP · ${Fmt.dayLabel(trip.serviceDate, now).toUpperCase()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.labelSmall!.copyWith(
                          color: Colors.white70,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpace.xs),
                    Text(
                      trip.tripCode,
                      style: t.labelSmall!.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        Fmt.time(view.pickupTime),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.displaySmall!.copyWith(
                          color: Colors.white,
                          fontFeatures: AppText.tabular,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpace.xs),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        'pickup · ±${view.data.employee(view.employeeId)?.toleranceMinutes(view.data.employer(trip.employerId)) ?? 7} min',
                        style: t.bodyMedium!.copyWith(color: Colors.white70),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
                _Leg(
                  icon: Icons.trip_origin_rounded,
                  text: view.pickupLocation?.name ?? '—',
                  light: true,
                ),
                const SizedBox(height: 6),
                _Leg(
                  icon: Icons.location_on_outlined,
                  text:
                      '${view.dropLocation?.name ?? '—'}${view.dropTime != null ? ' · ${Fmt.time(view.dropTime)}' : ''}',
                  light: true,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: AppSpace.xs,
                  runSpacing: AppSpace.xs,
                  children: [
                    TripStatusBadge(trip.status),
                    if (active)
                      StatusBadge(
                        passengerStateLabel(view.state),
                        tone: Tones.passenger(view.state),
                      ),
                  ],
                ),
                if (tripAlertText(view.data, trip) != null) ...[
                  const SizedBox(height: AppSpace.sm),
                  InlineBanner(
                    tone: StatusTone.warning,
                    title: 'Running late',
                    message: tripAlertText(view.data, trip),
                  ),
                ],
                const SizedBox(height: AppSpace.md),
                if (d != null && v != null)
                  Row(
                    children: [
                      InitialsAvatar(
                        initials: d.initials,
                        color: AppColors.teal,
                        size: 40,
                      ),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(
                        flex: 4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d.name, style: t.titleSmall),
                            Text(
                              'Driver · ${d.driverCode}',
                              style: t.bodySmall!.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpace.xs),
                      Expanded(
                        flex: 6,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  vehicleIcon(v),
                                  size: 16,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    'Vehicle ${v.vehicleCode}',
                                    overflow: TextOverflow.ellipsis,
                                    style: t.titleSmall,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '${v.propulsion.label} ${v.type.label}',
                              textAlign: TextAlign.right,
                              style: t.bodySmall!.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            Text(
                              v.fictionalRegistration,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: t.bodySmall!.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    'Driver and vehicle will appear once the Fleet Manager assigns this trip.',
                    style: t.bodyMedium!.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                const SizedBox(height: AppSpace.md),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => context.push(
                          active
                              ? '/employee/trip/${trip.id}'
                              : '/employee/trip/${trip.id}/pass',
                        ),
                        icon: Icon(
                          active
                              ? Icons.near_me_outlined
                              : Icons.qr_code_2_rounded,
                        ),
                        label: Text(active ? 'Track trip' : 'Show e-pass'),
                      ),
                    ),
                    const SizedBox(width: AppSpace.xs),
                    OutlinedButton(
                      onPressed: () =>
                          context.push('/employee/trip/${trip.id}'),
                      child: const Text('Details'),
                    ),
                  ],
                ),
                if (view.canReportAbsence) ...[
                  const SizedBox(height: AppSpace.xs),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => reportAbsenceFlow(
                        context,
                        ref,
                        trip,
                        view.employeeId,
                      ),
                      icon: const Icon(Icons.event_busy_outlined, size: 18),
                      label: const Text("I'm not travelling"),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Leg extends StatelessWidget {
  const _Leg({required this.icon, required this.text, this.light = false});
  final IconData icon;
  final String text;
  final bool light;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 16, color: light ? Colors.white70 : AppColors.textMuted),
      const SizedBox(width: AppSpace.xs),
      Expanded(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium!.copyWith(
            color: light ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    ],
  );
}
