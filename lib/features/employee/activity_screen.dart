import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import 'book_screen.dart';
import 'employee_common.dart';

class EmployeeActivityScreen extends ConsumerStatefulWidget {
  const EmployeeActivityScreen({super.key});

  @override
  ConsumerState<EmployeeActivityScreen> createState() =>
      _EmployeeActivityScreenState();
}

class _EmployeeActivityScreenState
    extends ConsumerState<EmployeeActivityScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final e = ref.watch(currentEmployeeProvider);
    if (e == null) return const LoadingState();
    final t = Theme.of(context).textTheme;
    final unread = data.unreadCount(UserRole.employee, e.id);
    final bookings = data.bookingsOf(e.id);
    final past =
        employeeTrips(
          data,
          e.id,
        ).where((v) => v.trip.status.isTerminal || v.isAbsent).toList()..sort(
          (a, b) => b.trip.scheduledStart.compareTo(a.trip.scheduledStart),
        );
    final tickets = data.ticketsBy(UserRole.employee, e.id);

    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      floatingActionButton: _tab == 2
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/employee/support/new'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New ticket'),
            )
          : null,
      body: MobilePage(
        children: [
          AppCard(
            padding: const EdgeInsets.all(AppSpace.md),
            onTap: () => context.push('/employee/notifications'),
            child: Row(
              children: [
                const IconTile(
                  icon: Icons.notifications_none_rounded,
                  size: 40,
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Notifications', style: t.titleSmall),
                      Text(
                        unread == 0 ? 'All caught up' : '$unread unread',
                        style: AppText.muted(context),
                      ),
                    ],
                  ),
                ),
                if (unread > 0) Badge(label: Text('$unread')),
                const SizedBox(width: AppSpace.xs),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          FilterChipBar<int>(
            options: const [0, 1, 2],
            selected: _tab,
            onSelected: (v) => setState(() => _tab = v),
            labelOf: (v) => const ['Requests', 'Trip history', 'Support'][v],
            countOf: (v) => [bookings.length, past.length, tickets.length][v],
          ),
          const SizedBox(height: AppSpace.md),
          if (_tab == 0)
            if (bookings.isEmpty)
              EmptyState(
                icon: Icons.event_note_outlined,
                title: 'No requests yet',
                message: 'Booking requests and their decisions appear here.',
                actionLabel: 'Request transport',
                onAction: () => context.go('/employee/book'),
              )
            else
              for (final b in bookings)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.xs),
                  child: BookingTile(booking: b),
                ),
          if (_tab == 1)
            if (past.isEmpty)
              const EmptyState(
                icon: Icons.history_rounded,
                title: 'No past trips',
                message: 'Completed and cancelled trips are kept here.',
              )
            else
              for (final v in past)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.xs),
                  child: EmployeeTripTile(view: v),
                ),
          if (_tab == 2) ...[
            if (tickets.isEmpty)
              EmptyState(
                icon: Icons.support_agent_outlined,
                title: 'No support tickets',
                message:
                    'Raise a ticket about a trip, booking, vehicle or the app.',
                actionLabel: 'New ticket',
                onAction: () => context.push('/employee/support/new'),
              )
            else
              for (final tk in tickets)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.xs),
                  child: AppCard(
                    padding: const EdgeInsets.all(AppSpace.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(tk.subject, style: t.titleSmall),
                            ),
                            StatusBadge(
                              tk.status.label,
                              tone: Tones.ticket(tk.status),
                              dense: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${tk.reference} · ${tk.category.label}${tk.relatedTripId != null ? ' · ${tk.relatedTripId}' : ''} · ${Fmt.ago(tk.createdAt, data.now)}',
                          style: AppText.muted(context),
                        ),
                        if (tk.response != null) ...[
                          const SizedBox(height: AppSpace.xs),
                          Text(
                            tk.response!,
                            style: t.bodySmall!.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: 80),
          ],
        ],
      ),
    );
  }
}
