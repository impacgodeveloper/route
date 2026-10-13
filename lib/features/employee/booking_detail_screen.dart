import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import 'book_screen.dart';
import 'employee_common.dart';

class EmployeeBookingDetailScreen extends ConsumerWidget {
  const EmployeeBookingDetailScreen({super.key, required this.bookingId});
  final String bookingId;

  static const _flow = [
    BookingStatus.requested,
    BookingStatus.approved,
    BookingStatus.assigned,
    BookingStatus.completed,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final e = ref.watch(currentEmployeeProvider);
    final b = data.booking(bookingId);
    final t = Theme.of(context).textTheme;
    if (e == null) return const Scaffold(body: LoadingState());
    if (b == null || b.employeeId != e.id) {
      return EmployeeSubPage(
        title: 'Request',
        children: [
          EmptyState(
            icon: Icons.event_note_outlined,
            title: 'Request not found',
            message: 'It may belong to another employee.',
            actionLabel: 'Back',
            onAction: () => context.pop(),
          ),
        ],
      );
    }
    final trip = data.trips.byId(b.tripId);
    final terminalBad =
        b.status == BookingStatus.rejected ||
        b.status == BookingStatus.cancelled;
    final stepIndex = b.status == BookingStatus.waitlisted
        ? 0
        : _flow.indexOf(b.status);

    return EmployeeSubPage(
      title: b.reference,
      children: [
        Row(
          children: [
            StatusBadge(b.status.label, tone: Tones.booking(b.status)),
            const Spacer(),
            Text(
              'Requested ${Fmt.ago(b.createdAt, data.now)}',
              style: AppText.muted(context),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        if (data
                .auditFor('booking', b.id)
                .where((a) => a.action == 'booking.seatMatch')
                .firstOrNull
            case final m? when !terminalBad) ...[
          InlineBanner(
            tone: StatusTone.success,
            icon: Icons.bolt_rounded,
            title: 'Matched to a free seat on an existing trip',
            message: m.summary,
          ),
          const SizedBox(height: AppSpace.md),
        ],
        if (terminalBad)
          InlineBanner(
            tone: StatusTone.danger,
            title: b.status == BookingStatus.rejected
                ? 'Request rejected'
                : 'Request cancelled',
            message: b.decisionReason ?? 'No reason recorded.',
          )
        else if (b.status == BookingStatus.waitlisted)
          InlineBanner(
            tone: StatusTone.warning,
            title: 'Waitlisted',
            message: b.decisionReason ?? 'Awaiting a free vehicle.',
          )
        else
          AppCard(
            child: Column(
              children: [
                for (var i = 0; i < _flow.length; i++)
                  _StepRow(
                    label: switch (_flow[i]) {
                      BookingStatus.requested => 'Request received',
                      BookingStatus.approved => 'Approved by Fleet Manager',
                      BookingStatus.assigned => 'Driver & vehicle assigned',
                      _ => 'Trip completed',
                    },
                    done: i <= stepIndex,
                    current: i == stepIndex,
                    last: i == _flow.length - 1,
                  ),
              ],
            ),
          ),
        const SizedBox(height: AppSpace.md),
        AppCard(
          child: Column(
            children: [
              KeyValueRow(label: 'Date', value: Fmt.weekday(b.requestedDate)),
              KeyValueRow(
                label: 'Pickup',
                value: data.locationLabel(b.requestedPickupLocationId),
              ),
              KeyValueRow(
                label: 'Destination',
                value: data.locationLabel(b.requestedDestinationId),
              ),
              KeyValueRow(
                label: 'Arrive by',
                value: Fmt.minutesOfDay(b.requestedArrivalMinutes),
              ),
              KeyValueRow(label: 'Preference', value: b.preference.label),
              if (b.notes.isNotEmpty)
                KeyValueRow(label: 'Notes', value: b.notes),
              if (b.decisionReason != null && !terminalBad)
                KeyValueRow(label: 'Update', value: b.decisionReason),
            ],
          ),
        ),
        if (trip != null) ...[
          const SizedBox(height: AppSpace.sectionGap),
          const SectionHeader(title: 'Linked trip'),
          const SizedBox(height: AppSpace.sm),
          EmployeeTripTile(view: EmployeeTripView(data, trip, e.id)),
        ],
        if (b.status.isOpen) ...[
          const SizedBox(height: AppSpace.xl),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => cancelBookingFlow(context, ref, b),
            icon: const Icon(Icons.close_rounded),
            label: const Text('Cancel request'),
          ),
        ],
        const SizedBox(height: AppSpace.md),
        Text(
          'A request is not a confirmed trip until it is assigned.',
          style: t.bodySmall!.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    required this.done,
    required this.current,
    required this.last,
  });
  final String label;
  final bool done;
  final bool current;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final color = done ? AppColors.success : AppColors.border;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: done ? color : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2),
                ),
                child: done
                    ? const Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: Colors.white,
                      )
                    : null,
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 2,
                    color: color,
                    constraints: const BoxConstraints(minHeight: 18),
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 1, bottom: last ? 0 : AppSpace.md),
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleSmall!.copyWith(
                  color: done ? AppColors.textPrimary : AppColors.textMuted,
                  fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
