import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/widgets/widgets.dart';
import '../../widgets/fleet_common.dart';

/// Opens the seat-match sheet for an open booking request.
Future<void> showSeatMatchSheet(BuildContext context, String bookingId) =>
    showAppSheet<void>(
      context,
      title: 'Find a seat for $bookingId',
      expand: true,
      builder: (c) => SeatMatchPanel(bookingId: bookingId),
    );

/// Existing trips that could absorb a request, feasible first. Every
/// assignment still goes through the validated assignment service.
class SeatMatchPanel extends ConsumerStatefulWidget {
  const SeatMatchPanel({super.key, required this.bookingId});
  final String bookingId;

  @override
  ConsumerState<SeatMatchPanel> createState() => _SeatMatchPanelState();
}

class _SeatMatchPanelState extends ConsumerState<SeatMatchPanel> {
  bool _busy = false;
  List<String> _errors = const [];

  Future<void> _do(Future<Result> action, String done) async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final r = await action;
    if (!mounted) return;
    setState(() {
      _busy = false;
      _errors = r.errors;
    });
    if (r.isOk) {
      nav.pop();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final svc = ref.read(servicesProvider);
    final t = Theme.of(context).textTheme;
    final b = data.booking(widget.bookingId);
    if (b == null || !b.status.isOpen) {
      return const EmptyState(
        icon: Icons.inbox_outlined,
        title: 'Request no longer open',
        message: 'It may already be assigned.',
        compact: true,
      );
    }
    final e = data.employee(b.employeeId);
    final matches = svc.matching.suggestions(b.id)
      ..sort((x, y) {
        if (x.feasible != y.feasible) return x.feasible ? -1 : 1;
        return x.addedMinutes.compareTo(y.addedMinutes);
      });
    final feasible = matches.where((m) => m.feasible).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${e?.employeeCode ?? b.employeeId} ${e?.name ?? ''} · ${Fmt.weekday(b.requestedDate)} · ${b.requestedPickupLocationId} → ${b.requestedDestinationId} by ${Fmt.minutesOfDay(b.requestedArrivalMinutes)}',
          style: t.bodyMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Max added detour ${data.policy.maxAddedDetourMinutes} min (policy). Existing passengers\' deadlines and capacity are hard limits.',
          style: AppText.muted(context),
        ),
        const SizedBox(height: AppSpace.md),
        if (_errors.isNotEmpty) ...[
          InlineBanner(
            tone: StatusTone.danger,
            title: 'Not assigned',
            messages: _errors,
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        if (matches.isEmpty)
          const EmptyState(
            icon: Icons.event_seat_outlined,
            title: 'No trips that day',
            message: 'Create a new trip or run the optimizer for this request.',
            compact: true,
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  '$feasible of ${matches.length} trips can take this passenger',
                  style: t.titleSmall,
                ),
              ),
              FilledButton.icon(
                onPressed: _busy || feasible == 0
                    ? null
                    : () => _do(
                        svc.matching.matchBest(b.id),
                        '${b.reference} matched to the best trip',
                      ),
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('Best match'),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          for (final m in matches)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: AppCard(
                padding: const EdgeInsets.all(AppSpace.md),
                borderColor: m.feasible
                    ? AppColors.success.withValues(alpha: 0.4)
                    : AppColors.border,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${m.trip.tripCode} · ${driverShort(data.driver(m.trip.assignedDriverId))} · Vehicle ${m.trip.assignedVehicleId ?? '—'}',
                            style: t.titleSmall,
                          ),
                        ),
                        StatusBadge(
                          m.feasible ? 'Feasible' : 'Not feasible',
                          tone: m.feasible
                              ? StatusTone.success
                              : StatusTone.neutral,
                          dense: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    StatStrip(
                      stats: [
                        ('added time', '+${m.addedMinutes} min'),
                        (
                          'added distance',
                          '+${m.addedKm.toStringAsFixed(1)} km',
                        ),
                        ('seats after', '${m.seatsAfter}/${m.capacity} left'),
                        ('departs', Fmt.time(m.trip.scheduledStart)),
                      ],
                    ),
                    for (final r in m.reasons)
                      Text(
                        r,
                        style: t.bodySmall!.copyWith(
                          color: m.feasible
                              ? AppColors.textSecondary
                              : AppColors.warning,
                        ),
                      ),
                    if (m.feasible) ...[
                      const SizedBox(height: AppSpace.xs),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton(
                          key: ValueKey('assign-${m.trip.id}'),
                          onPressed: _busy
                              ? null
                              : () => _do(
                                  svc.bookings.assignToTrip(b.id, m.trip.id),
                                  '${b.reference} added to ${m.trip.tripCode}',
                                ),
                          child: const Text('Assign to this trip'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}
