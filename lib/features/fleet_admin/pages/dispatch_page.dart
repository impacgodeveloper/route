import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/widgets.dart';
import '../../../domain/models/models.dart';
import '../widgets/fleet_common.dart';
import 'v3/seat_match_sheet.dart';

enum _TripFilter { all, upcoming, active, completed, cancelled }

class DispatchPage extends ConsumerStatefulWidget {
  const DispatchPage({super.key, this.highlightBookingId});
  final String? highlightBookingId;

  @override
  ConsumerState<DispatchPage> createState() => _DispatchPageState();
}

class _DispatchPageState extends ConsumerState<DispatchPage> {
  final Set<String> _selected = {};
  DateTime? _day;
  _TripFilter _filter = _TripFilter.all;
  String _query = '';
  int _searchVersion = 0;

  AppServices get _s => ref.read(servicesProvider);

  Future<void> _reject(Booking b) async {
    final r = await showReasonDialog(
      context,
      title: 'Reject ${b.reference}?',
      message: 'The employee is notified with your reason.',
      confirmLabel: 'Reject',
      destructive: true,
    );
    if (r == null || !mounted) return;
    await runAndShow(context, _s.bookings.reject(b.id, r.reason));
  }

  Future<void> _waitlist(Booking b) async {
    final r = await showReasonDialog(
      context,
      title: 'Waitlist ${b.reference}',
      initial: 'No vehicle has a free window at the requested time.',
      confirmLabel: 'Waitlist',
    );
    if (r == null || !mounted) return;
    await runAndShow(context, _s.bookings.waitlist(b.id, r.reason));
  }

  Future<void> _assignExisting(Booking b) async {
    final data = ref.read(dataProvider);
    final candidates = data.trips
        .onDay(b.requestedDate)
        .where(
          (t) =>
              t.actualStart == null &&
              t.status != TripStatus.cancelled &&
              t.status != TripStatus.completed,
        )
        .toList();
    final tripId = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Add ${b.employeeId} to an existing trip'),
        content: SizedBox(
          width: 460,
          child: candidates.isEmpty
              ? const EmptyState(
                  icon: Icons.event_busy_outlined,
                  title: 'No open trips that day',
                  message:
                      'Create a new trip for this request instead. Started, completed and cancelled trips are excluded.',
                  compact: true,
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final t in candidates)
                      TripRowTile(trip: t, onTap: () => Navigator.pop(c, t.id)),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (tripId == null || !mounted) return;
    await runAndShow(
      context,
      _s.bookings.assignToTrip(b.id, tripId),
      failureTitle: 'Could not add to trip',
    );
  }

  void _createTrip(
    List<Booking> bookings, {
    String base = '/fleet/dispatch/new',
  }) {
    if (bookings.isEmpty) return;
    final date = bookings.first.requestedDate;
    if (bookings.any((b) => !sameDay(b.requestedDate, date))) {
      showToast(context, 'Select requests for the same date', error: true);
      return;
    }
    context.go(
      '$base?employees=${bookings.map((b) => b.employeeId).join(',')}'
      '&bookings=${bookings.map((b) => b.id).join(',')}'
      '&date=${dateOnly(date).toIso8601String().substring(0, 10)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final t = Theme.of(context).textTheme;
    final day = _day ?? data.today;
    final queue = data.openBookings;
    final trips = data.trips.onDay(day).where((x) {
      final ok = switch (_filter) {
        _TripFilter.all => true,
        _TripFilter.upcoming => x.status.isUpcoming,
        _TripFilter.active => x.status.isActive,
        _TripFilter.completed => x.status == TripStatus.completed,
        _TripFilter.cancelled => x.status == TripStatus.cancelled,
      };
      if (!ok) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return x.tripCode.toLowerCase().contains(q) ||
          (x.assignedDriverId ?? '').toLowerCase().contains(q) ||
          (x.assignedVehicleId ?? '').toLowerCase().contains(q) ||
          x.employeeIds.any((e) => e.toLowerCase() == q);
    }).toList();
    final selectedBookings = queue
        .where((b) => _selected.contains(b.id))
        .toList();

    return AdminPage(
      title: 'Trips & dispatch',
      subtitle:
          'Review requests, assign drivers and vehicles, and manage trips. Every save is validated for capacity, availability and time windows.',
      actions: [
        FilledButton.icon(
          onPressed: () => context.go('/fleet/dispatch/new'),
          icon: const Icon(Icons.add_rounded),
          label: const Text('New trip'),
        ),
      ],
      children: [
        PanelCard(
          title: 'Request queue',
          subtitle:
              '${queue.length} open request${queue.length == 1 ? '' : 's'} · a request is not a trip until assigned',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (selectedBookings.isNotEmpty) ...[
                Wrap(
                  spacing: AppSpace.xs,
                  runSpacing: AppSpace.xs,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _createTrip(
                        selectedBookings,
                        base: '/fleet/optimization',
                      ),
                      icon: const Icon(Icons.auto_graph_outlined),
                      label: Text(
                        'Optimize selected (${selectedBookings.length})',
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: () => _createTrip(selectedBookings),
                      child: Text('Create trip (${selectedBookings.length})'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
              ],
              queue.isEmpty
                  ? const EmptyState(
                      icon: Icons.inbox_outlined,
                      title: 'Queue is clear',
                      message:
                          'New employee booking requests will appear here.',
                      compact: true,
                    )
                  : AdaptiveTable<Booking>(
                      rows: queue,
                      selectedPredicate: (b) =>
                          b.id == widget.highlightBookingId,
                      columns: [
                        TableCol(
                          '',
                          (b) => Checkbox(
                            value: _selected.contains(b.id),
                            onChanged: (v) => setState(
                              () => v == true
                                  ? _selected.add(b.id)
                                  : _selected.remove(b.id),
                            ),
                          ),
                          flex: 1,
                        ),
                        TableCol(
                          'Request',
                          (b) => _bookingTitle(b, data, t),
                          flex: 5,
                        ),
                        TableCol(
                          'Date · arrive by',
                          (b) => Text(
                            '${Fmt.dateShort(b.requestedDate)} · ${Fmt.minutesOfDay(b.requestedArrivalMinutes)}',
                          ),
                          flex: 3,
                        ),
                        TableCol(
                          'Route',
                          (b) => Text(
                            '${b.requestedPickupLocationId} → ${b.requestedDestinationId}',
                          ),
                          flex: 3,
                        ),
                        TableCol(
                          'Status',
                          (b) => StatusBadge(
                            b.status.label,
                            tone: Tones.booking(b.status),
                            dense: true,
                          ),
                          flex: 2,
                        ),
                        TableCol(
                          '',
                          (b) => _actions(b),
                          flex: 2,
                          numeric: true,
                        ),
                      ],
                      mobileCard: (b) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Checkbox(
                                value: _selected.contains(b.id),
                                onChanged: (v) => setState(
                                  () => v == true
                                      ? _selected.add(b.id)
                                      : _selected.remove(b.id),
                                ),
                              ),
                              Expanded(child: _bookingTitle(b, data, t)),
                              _actions(b),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 48),
                            child: Wrap(
                              spacing: AppSpace.xs,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                StatusBadge(
                                  b.status.label,
                                  tone: Tones.booking(b.status),
                                  dense: true,
                                ),
                                Text(
                                  '${Fmt.dateShort(b.requestedDate)} · by ${Fmt.minutesOfDay(b.requestedArrivalMinutes)} · ${b.requestedPickupLocationId} → ${b.requestedDestinationId}',
                                  style: t.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        _SeatUtilizationPanel(day: day),
        const SizedBox(height: AppSpace.md),
        PanelCard(
          title: 'Trips',
          subtitle: Fmt.weekdayLong(day),
          trailing: IconButton(
            tooltip: 'Pick date',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: day,
                firstDate: data.today.subtract(const Duration(days: 60)),
                lastDate: data.today.add(const Duration(days: 60)),
              );
              if (picked != null) setState(() => _day = picked);
            },
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilterChipBar<int>(
                options: const [-1, 0, 1, 2],
                selected: day.difference(data.today).inDays,
                onSelected: (o) =>
                    setState(() => _day = data.today.add(Duration(days: o))),
                labelOf: (o) =>
                    Fmt.dayLabel(data.today.add(Duration(days: o)), data.now),
                countOf: (o) =>
                    data.trips.onDay(data.today.add(Duration(days: o))).length,
              ),
              const SizedBox(height: AppSpace.sm),
              LayoutBuilder(
                builder: (context, c) {
                  final search = AppSearchField(
                    key: ValueKey(_searchVersion),
                    hint: 'Trip, driver, vehicle or employee ID',
                    onChanged: (v) => setState(() => _query = v.trim()),
                  );
                  final chips = FilterChipBar<_TripFilter>(
                    options: _TripFilter.values,
                    selected: _filter,
                    onSelected: (f) => setState(() => _filter = f),
                    labelOf: (f) =>
                        f.name[0].toUpperCase() + f.name.substring(1),
                  );
                  if (c.maxWidth < 760) {
                    return Column(
                      children: [
                        search,
                        const SizedBox(height: AppSpace.sm),
                        chips,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      SizedBox(width: 320, child: search),
                      const SizedBox(width: AppSpace.md),
                      Expanded(child: chips),
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpace.sm),
              AdaptiveTable<Trip>(
                rows: trips,
                onRowTap: (x) => context.go('/fleet/dispatch/trip/${x.id}'),
                empty: EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No trips match',
                  message: 'Try another date or clear the filters.',
                  actionLabel: 'Clear filters',
                  onAction: () => setState(() {
                    _filter = _TripFilter.all;
                    _query = '';
                    _searchVersion++;
                  }),
                  compact: true,
                ),
                columns: [
                  TableCol(
                    'Trip',
                    (x) => Text(x.tripCode, style: t.titleSmall),
                    flex: 2,
                  ),
                  TableCol(
                    'Window',
                    (x) => Text(
                      '${Fmt.time(x.scheduledStart)}–${Fmt.time(x.scheduledArrival)}',
                    ),
                    flex: 3,
                  ),
                  TableCol(
                    'Driver',
                    (x) => Text(driverShort(data.driver(x.assignedDriverId))),
                    flex: 3,
                  ),
                  TableCol(
                    'Vehicle',
                    (x) => Text(
                      x.assignedVehicleId == null
                          ? '—'
                          : 'Vehicle ${x.assignedVehicleId}',
                    ),
                    flex: 2,
                  ),
                  TableCol(
                    'Pax',
                    (x) => Text('${x.employeeIds.length}'),
                    flex: 1,
                    numeric: true,
                  ),
                  TableCol(
                    'Status',
                    (x) => TripStatusBadge(x.status, dense: true),
                    flex: 2,
                    numeric: true,
                  ),
                ],
                mobileCard: (x) => TripRowTile(trip: x),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bookingTitle(Booking b, DataView data, TextTheme t) {
    final e = data.employee(b.employeeId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${b.reference} · ${e?.employeeCode ?? b.employeeId} ${e?.name ?? ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.titleSmall,
        ),
        if (b.notes.isNotEmpty || b.decisionReason != null)
          Text(
            b.notes.isNotEmpty ? b.notes : b.decisionReason!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.bodySmall!.copyWith(color: AppColors.textSecondary),
          ),
      ],
    );
  }

  Widget _actions(Booking b) => PopupMenuButton<String>(
    tooltip: 'Actions for ${b.reference}',
    icon: const Icon(Icons.more_horiz_rounded),
    onSelected: (v) async {
      switch (v) {
        case 'approve':
          await runAndShow(context, _s.bookings.approve(b.id));
        case 'reject':
          await _reject(b);
        case 'waitlist':
          await _waitlist(b);
        case 'existing':
          await _assignExisting(b);
        case 'seat':
          await showSeatMatchSheet(context, b.id);
        case 'new':
          _createTrip([b]);
      }
    },
    itemBuilder: (c) => [
      if (b.status != BookingStatus.approved)
        const PopupMenuItem(value: 'approve', child: Text('Approve')),
      const PopupMenuItem(
        value: 'seat',
        child: Text('Find seat in existing trip…'),
      ),
      const PopupMenuItem(value: 'new', child: Text('Create trip…')),
      const PopupMenuItem(
        value: 'existing',
        child: Text('Add to existing trip…'),
      ),
      if (b.status != BookingStatus.waitlisted)
        const PopupMenuItem(value: 'waitlist', child: Text('Waitlist…')),
      const PopupMenuItem(value: 'reject', child: Text('Reject…')),
    ],
  );
}

/// Seat utilization for the selected day: seats released by absences,
/// seats re-used by dynamic matching, and free seats on not-started trips.
class _SeatUtilizationPanel extends ConsumerWidget {
  const _SeatUtilizationPanel({required this.day});
  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final u = ref.read(servicesProvider).matching.utilization(day);
    final released = data.trips
        .onDay(day)
        .where(
          (t) =>
              t.absentEmployeeIds.isNotEmpty &&
              t.status != TripStatus.cancelled,
        )
        .toList();
    return PanelCard(
      title: 'Seat utilization · ${Fmt.dayLabel(day, data.now)}',
      subtitle:
          'Released seats can be re-used via "Find seat in existing trip" on a request',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StatStrip(
            stats: [
              ('seats released (absences)', '${u.released}'),
              ('seats re-used by matching', '${u.reused}'),
              ('free seats on not-started trips', '${u.freeSeats}'),
            ],
          ),
          if (released.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            for (final t in released)
              TripRowTile(
                trip: t,
                onTap: () => context.go('/fleet/dispatch/trip/${t.id}'),
                trailing: Padding(
                  padding: const EdgeInsets.only(left: AppSpace.xs),
                  child: StatusBadge(
                    '${t.absentEmployeeIds.length} released',
                    tone: StatusTone.teal,
                    dense: true,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
