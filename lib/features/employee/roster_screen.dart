import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import 'employee_common.dart';

/// Agenda-first schedule for the next 7 days.
class EmployeeRosterScreen extends ConsumerStatefulWidget {
  const EmployeeRosterScreen({super.key});

  @override
  ConsumerState<EmployeeRosterScreen> createState() =>
      _EmployeeRosterScreenState();
}

class _EmployeeRosterScreenState extends ConsumerState<EmployeeRosterScreen> {
  bool _week = true;
  int _dayIndex = 0;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final e = ref.watch(currentEmployeeProvider);
    if (e == null) return const Scaffold(body: LoadingState());
    final t = Theme.of(context).textTheme;
    final days = [
      for (var i = 0; i < 7; i++) data.today.add(Duration(days: i)),
    ];
    final trips = employeeTrips(data, e.id);
    final bookings = data
        .bookingsOf(e.id)
        .where((b) => b.status.isOpen)
        .toList();
    final notices = data
        .notificationsFor(UserRole.employee, e.id)
        .where(
          (n) =>
              n.category == NotificationCategory.serviceNotice ||
              n.category == NotificationCategory.routeChange,
        )
        .where((n) => data.now.difference(n.createdAt).inDays < 3)
        .toList();
    final shown = _week ? days : [days[_dayIndex]];

    return EmployeeSubPage(
      title: 'My schedule',
      children: [
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: true, label: Text('Week')),
            ButtonSegment(value: false, label: Text('Day')),
          ],
          selected: {_week},
          onSelectionChanged: (s) => setState(() => _week = s.first),
        ),
        const SizedBox(height: AppSpace.md),
        AppCard(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Row(
            children: [
              const IconTile(icon: Icons.badge_outlined, size: 40),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.shiftLabel, style: t.titleSmall),
                    Text(
                      'Usual pickup ${data.location(e.pickupLocationId)?.name ?? '—'} · arrive by ${Fmt.minutesOfDay(e.requiredArrivalMinutes)} at ${e.destinationId}',
                      style: AppText.muted(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!_week) ...[
          const SizedBox(height: AppSpace.md),
          SizedBox(
            height: 64,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (var i = 0; i < days.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpace.xs),
                    child: _DayChip(
                      day: days[i],
                      selected: i == _dayIndex,
                      hasItems: trips.any(
                        (v) => sameDay(v.trip.serviceDate, days[i]),
                      ),
                      onTap: () => setState(() => _dayIndex = i),
                    ),
                  ),
              ],
            ),
          ),
        ],
        for (final n in notices) ...[
          const SizedBox(height: AppSpace.md),
          InlineBanner(
            tone: StatusTone.warning,
            title: n.title,
            message: n.body,
            icon: Icons.campaign_outlined,
          ),
        ],
        for (final day in shown) ...[
          const SizedBox(height: AppSpace.lg),
          Text(
            Fmt.dayLabel(day, data.now) == Fmt.weekday(day)
                ? Fmt.weekday(day)
                : '${Fmt.dayLabel(day, data.now)} · ${Fmt.weekday(day)}',
            style: t.titleSmall!.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpace.xs),
          ..._dayItems(context, data, day, trips, bookings),
        ],
      ],
    );
  }

  List<Widget> _dayItems(
    BuildContext context,
    DataView data,
    DateTime day,
    List<EmployeeTripView> trips,
    List<Booking> bookings,
  ) {
    final t = Theme.of(context).textTheme;
    final dayTrips = trips
        .where((v) => sameDay(v.trip.serviceDate, day))
        .toList();
    final dayBookings = bookings
        .where((b) => sameDay(b.requestedDate, day))
        .toList();
    if (dayTrips.isEmpty && dayBookings.isEmpty) {
      return [
        AppCard(
          padding: const EdgeInsets.all(AppSpace.md),
          color: AppColors.surfaceAlt,
          child: Row(
            children: [
              const Icon(
                Icons.event_busy_outlined,
                size: 18,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: Text(
                  'No transport scheduled',
                  style: t.bodyMedium!.copyWith(color: AppColors.textSecondary),
                ),
              ),
              TextButton(
                onPressed: () => context.go('/employee/book'),
                child: const Text('Request'),
              ),
            ],
          ),
        ),
      ];
    }
    return [
      for (final v in dayTrips)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: AppCard(
            padding: const EdgeInsets.all(AppSpace.md),
            onTap: () => context.push('/employee/trip/${v.trip.id}'),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 70,
                  child: Text(
                    Fmt.time(v.pickupTime),
                    style: t.titleSmall!.copyWith(
                      fontFeatures: AppText.tabular,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${v.pickupLocation?.name ?? '—'} → ${v.dropLocation?.name ?? '—'}',
                        style: t.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        v.vehicle == null
                            ? '${v.trip.tripCode} · awaiting vehicle'
                            : '${v.trip.tripCode} · Vehicle ${v.vehicle!.vehicleCode} (${v.vehicle!.type.label}) · ${v.driver?.name ?? ''}',
                        style: AppText.muted(context),
                      ),
                      const SizedBox(height: 6),
                      TripStatusBadge(v.trip.status, dense: true),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      for (final b in dayBookings)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: AppCard(
            padding: const EdgeInsets.all(AppSpace.md),
            onTap: () => context.push('/employee/booking/${b.id}'),
            child: Row(
              children: [
                SizedBox(
                  width: 70,
                  child: Text(
                    'by ${Fmt.minutesOfDay(b.requestedArrivalMinutes)}',
                    style: t.labelMedium,
                  ),
                ),
                Expanded(
                  child: Text(
                    'Request ${b.reference} · ${b.requestedDestinationId}',
                    style: t.bodyMedium,
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
    ];
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.day,
    required this.selected,
    required this.hasItems,
    required this.onTap,
  });
  final DateTime day;
  final bool selected;
  final bool hasItems;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      selected: selected,
      button: true,
      label: Fmt.weekday(day),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.mdAll,
        child: Container(
          width: 52,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.white,
            borderRadius: AppRadius.mdAll,
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                Fmt.weekday(day).substring(0, 3),
                style: t.labelSmall!.copyWith(
                  color: selected ? Colors.white70 : AppColors.textMuted,
                ),
              ),
              Text(
                '${day.day}',
                style: t.titleMedium!.copyWith(
                  color: selected ? Colors.white : AppColors.textPrimary,
                ),
              ),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: hasItems
                      ? (selected ? Colors.white : AppColors.primary)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
