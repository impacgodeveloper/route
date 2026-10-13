import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import '../../domain/rules/capacity_rules.dart';
import 'employer_common.dart';

enum _TripFilter { all, upcoming, active, completed, cancelled }

/// Read-only view of fleet assignments for the employer's trips.
class AssignmentsPage extends ConsumerStatefulWidget {
  const AssignmentsPage({super.key});

  @override
  ConsumerState<AssignmentsPage> createState() => _AssignmentsPageState();
}

class _AssignmentsPageState extends ConsumerState<AssignmentsPage> {
  DateTime? _day;
  _TripFilter _filter = _TripFilter.all;

  static bool _matches(Trip t, _TripFilter f) => switch (f) {
    _TripFilter.all => true,
    _TripFilter.upcoming => t.status.isUpcoming,
    _TripFilter.active => t.status.isActive,
    _TripFilter.completed => t.status == TripStatus.completed,
    _TripFilter.cancelled => t.status == TripStatus.cancelled,
  };

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final day = _day ?? data.today;
    final dayTrips = employerTrips(
      data,
    ).where((t) => sameDay(t.serviceDate, day)).toList();
    final trips = dayTrips.where((x) => _matches(x, _filter)).toList();
    final t = Theme.of(context).textTheme;

    int cap(Trip tr) {
      final v = data.vehicle(tr.assignedVehicleId);
      return v == null
          ? 0
          : CapacityRules.passengerCapacity(v, guardRequired: tr.guardRequired);
    }

    return AdminPage(
      title: 'Fleet Assignments',
      subtitle:
          'Driver, vehicle and route allocations for ${data.primaryEmployer.code} employees.',
      children: [
        const InlineBanner(
          tone: StatusTone.info,
          title: 'Read-only for employer admins',
          message:
              'Assignment, reassignment and cancellation are Fleet Manager operations. Changes they make appear here immediately.',
          icon: Icons.lock_outline_rounded,
        ),
        const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Previous day',
                    onPressed: () => setState(
                      () => _day = day.subtract(const Duration(days: 1)),
                    ),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  InkWell(
                    borderRadius: AppRadius.smAll,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: day,
                        firstDate: data.today.subtract(
                          const Duration(days: 60),
                        ),
                        lastDate: data.today.add(const Duration(days: 60)),
                      );
                      if (picked != null) setState(() => _day = picked);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      child: Text(
                        '${Fmt.dayLabel(day, data.now)} · ${Fmt.date(day)}',
                        style: t.titleSmall,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next day',
                    onPressed: () =>
                        setState(() => _day = day.add(const Duration(days: 1))),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ),
            if (!sameDay(day, data.today))
              TextButton(
                onPressed: () => setState(() => _day = null),
                child: const Text('Today'),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        FilterChipBar<_TripFilter>(
          options: _TripFilter.values,
          selected: _filter,
          onSelected: (f) => setState(() => _filter = f),
          labelOf: (f) => switch (f) {
            _TripFilter.all => 'All',
            _TripFilter.upcoming => 'Upcoming',
            _TripFilter.active => 'In progress',
            _TripFilter.completed => 'Completed',
            _TripFilter.cancelled => 'Cancelled',
          },
          countOf: (f) => dayTrips.where((x) => _matches(x, f)).length,
        ),
        const SizedBox(height: AppSpace.md),
        AdaptiveTable<Trip>(
          rows: trips,
          onRowTap: (tr) => context.go(EmployerPaths.trip(tr.id)),
          empty: EmptyState(
            icon: Icons.event_busy_outlined,
            title: 'No trips for this day',
            message: _filter == _TripFilter.all
                ? 'No assignments exist for ${Fmt.date(day)}.'
                : 'No trips match this filter.',
            actionLabel: _filter == _TripFilter.all ? null : 'Show all',
            onAction: _filter == _TripFilter.all
                ? null
                : () => setState(() => _filter = _TripFilter.all),
          ),
          columns: [
            TableCol(
              'Trip',
              (tr) => Text(
                tr.tripCode,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            TableCol('Start', (tr) => Text(Fmt.time(tr.scheduledStart))),
            TableCol(
              'Driver',
              (tr) => Text(
                data.driver(tr.assignedDriverId)?.name ?? '—',
                overflow: TextOverflow.ellipsis,
              ),
              flex: 2,
            ),
            TableCol(
              'Vehicle',
              (tr) => Row(
                children: [
                  Text(tr.assignedVehicleId ?? '—'),
                  const SizedBox(width: 6),
                  if (tr.assignedVehicleId != null)
                    Flexible(
                      child: PropulsionBadge(
                        data.vehicle(tr.assignedVehicleId),
                      ),
                    ),
                ],
              ),
              flex: 2,
            ),
            TableCol(
              'Route',
              (tr) => Text(
                data.trips.routeOf(tr)?.name ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              flex: 3,
            ),
            TableCol(
              'Stops',
              (tr) => Text('${tr.orderedStopIds.length}'),
              numeric: true,
            ),
            TableCol(
              'Pax / seats',
              (tr) => Text(
                '${tr.employeeIds.length} / ${cap(tr) == 0 ? '—' : cap(tr)}${tr.absentEmployeeIds.isEmpty ? '' : ' · ${tr.absentEmployeeIds.length} not travelling'}',
              ),
              numeric: true,
            ),
            TableCol(
              'Distance',
              (tr) => Text(
                Fmt.km(
                  tr.distanceKm ?? data.trips.routeOf(tr)?.estimatedDistanceKm,
                ),
              ),
              numeric: true,
            ),
            TableCol(
              'Status',
              (tr) => TripStatusBadge(tr.status, dense: true),
              flex: 2,
            ),
          ],
          mobileCard: (tr) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${tr.tripCode} · ${Fmt.time(tr.scheduledStart)}',
                      style: t.titleSmall,
                    ),
                  ),
                  TripStatusBadge(tr.status, dense: true),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${data.driver(tr.assignedDriverId)?.name ?? 'No driver'} · ${tr.assignedVehicleId != null ? 'Vehicle ${tr.assignedVehicleId}' : 'No vehicle'} · ${tr.employeeIds.length} pax · ${Fmt.km(tr.distanceKm ?? data.trips.routeOf(tr)?.estimatedDistanceKm)}',
                style: AppText.muted(context),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Trip detail (read-only) with route, passengers and assignment history.
class EmployerTripDetailPage extends ConsumerWidget {
  const EmployerTripDetailPage({super.key, required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final trip = data.trips.byId(tripId);
    if (trip == null) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Trip not found',
        message: 'No trip with ID "$tripId".',
        actionLabel: 'Back to assignments',
        onAction: () => context.go(EmployerPaths.assignments),
      );
    }
    final t = Theme.of(context).textTheme;
    final vehicle = data.vehicle(trip.assignedVehicleId);
    final driver = data.driver(trip.assignedDriverId);
    final route = data.trips.routeOf(trip);
    final stops = data.trips.stopsOf(trip);
    final locs = data.locationMap;
    final pos = ref.watch(locationServiceProvider).positionOf(trip);
    final billing = data.billingForTrip(trip.id);
    final incidents = data.incidentsOfTrip(trip.id);
    final seats = vehicle == null
        ? null
        : CapacityRules.breakdown(vehicle, guardRequired: trip.guardRequired);
    final current = data.trips.currentStop(trip);

    final points = [
      for (final s in stops)
        MapPoint(
          x: locs[s.locationId]!.demoX,
          y: locs[s.locationId]!.demoY,
          label: s.locationId,
          kind: s.kind == StopKind.drop
              ? LocationType.office
              : LocationType.pickup,
          done: s.isDone,
          emphasis: current?.id == s.id,
        ),
    ];

    return AdminPage(
      title: 'Trip ${trip.tripCode}',
      subtitle: '${Fmt.weekdayLong(trip.serviceDate)} · ${route?.name ?? ''}',
      actions: [
        TextButton.icon(
          onPressed: () => context.go(EmployerPaths.assignments),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Assignments'),
        ),
        TripStatusBadge(trip.status),
      ],
      children: [
        if (trip.status == TripStatus.cancelled)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: InlineBanner(
              tone: StatusTone.danger,
              title: 'Cancelled',
              message:
                  trip.cancellationReason ?? 'Cancelled by the Fleet Manager.',
            ),
          ),
        if (trip.delayReason != null &&
            trip.status != TripStatus.completed &&
            trip.status != TripStatus.cancelled)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: InlineBanner(
              tone: StatusTone.warning,
              title: trip.status.label,
              message: trip.delayReason,
            ),
          ),
        ResponsiveColumns(
          left: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PanelCard(
                title: 'Route',
                subtitle:
                    '${stops.length} stops · ${Fmt.km(route?.estimatedDistanceKm)} estimated · ${route?.variant.label ?? ''}',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SchematicMap(
                      points: points,
                      path: [for (var i = 0; i < points.length; i++) i],
                      vehicle: pos.available ? Offset(pos.x, pos.y) : null,
                      vehicleStale: pos.isStale,
                    ),
                    if (pos.available) ...[
                      const SizedBox(height: 4),
                      SimulatedNote(
                        '${DemoLabels.simulatedLocation} · ${pos.label} · last update ${Fmt.time(pos.lastUpdate)}${pos.isStale ? ' (may be outdated)' : ''}',
                      ),
                    ],
                    const SizedBox(height: AppSpace.md),
                    RouteTimeline(
                      stops: [
                        for (final s in stops)
                          TimelineStop(
                            title: locs[s.locationId]?.name ?? s.locationId,
                            subtitle:
                                '${s.kind == StopKind.pickup ? 'Pickup' : 'Drop'} · ${(s.kind == StopKind.pickup ? s.boardingEmployeeIds : s.alightingEmployeeIds).join(', ')}',
                            kind: s.kind,
                            status: s.status,
                            planned: s.plannedArrival,
                            actual: s.actualArrival,
                            highlight: current?.id == s.id,
                            note: s.skipReason ?? s.issueNote,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),
              PanelCard(
                title: 'Passengers',
                subtitle:
                    '${trip.boardedPassengerIds.length} boarded · ${trip.alightedPassengerIds.length} dropped · ${trip.noShowPassengerIds.length} no-show${trip.absentEmployeeIds.isEmpty ? '' : ' · ${trip.absentEmployeeIds.length} not travelling'}',
                child: DividedList(
                  children: [
                    for (final id in trip.employeeIds)
                      ListRow(
                        onTap: () => context.go(EmployerPaths.employee(id)),
                        leading: InitialsAvatar(
                          initials: data.employee(id)?.initials ?? '?',
                          size: 34,
                          color: AppColors.employerAccent,
                        ),
                        title: data.employeeLabel(id),
                        subtitle:
                            '${data.location(data.trips.pickupStopFor(trip, id)?.locationId)?.name ?? '—'} → ${data.location(data.trips.dropStopFor(trip, id)?.locationId)?.name ?? '—'}',
                        trailing: () {
                          final s = data.trips.passengerState(trip, id);
                          return StatusBadge(
                            s.label,
                            tone: Tones.passenger(s),
                            dense: true,
                          );
                        }(),
                      ),
                    for (final id in trip.absentEmployeeIds)
                      ListRow(
                        key: Key('absent-$id'),
                        onTap: () => context.go(EmployerPaths.employee(id)),
                        leading: InitialsAvatar(
                          initials: data.employee(id)?.initials ?? '?',
                          size: 34,
                          color: AppColors.textMuted,
                        ),
                        title: data.employeeLabel(id),
                        subtitle: 'Reported absence · seat released for reuse',
                        trailing: const StatusBadge(
                          'Not travelling',
                          tone: StatusTone.neutral,
                          dense: true,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          right: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PanelCard(
                title: 'Assignment',
                child: Column(
                  children: [
                    KeyValueRow(
                      label: 'Driver',
                      value: driver == null
                          ? 'Not assigned'
                          : '${driver.driverCode} · ${driver.name}',
                    ),
                    KeyValueRow(
                      label: 'Vehicle',
                      valueWidget: vehicle == null
                          ? const Text('Not assigned')
                          : Wrap(
                              spacing: 6,
                              alignment: WrapAlignment.end,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  '${vehicle.vehicleCode} · ${vehicle.type.label}',
                                  style: t.bodyMedium!.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                PropulsionBadge(vehicle),
                              ],
                            ),
                    ),
                    if (vehicle != null)
                      KeyValueRow(
                        label: 'Registration',
                        value: '${vehicle.fictionalRegistration} (fictional)',
                      ),
                    if (seats != null)
                      KeyValueRow(label: 'Seats', value: seats.toString()),
                    KeyValueRow(
                      label: 'Passengers',
                      value:
                          '${trip.employeeIds.length}${seats != null ? ' of ${seats.passengerCapacity}' : ''}',
                    ),
                    KeyValueRow(
                      label: 'Scheduled',
                      value:
                          '${Fmt.time(trip.scheduledStart)} – ${Fmt.time(trip.scheduledArrival)}',
                    ),
                    KeyValueRow(
                      label: 'Actual',
                      value: trip.actualStart == null
                          ? '—'
                          : '${Fmt.time(trip.actualStart)} – ${Fmt.time(trip.actualArrival)}',
                    ),
                    KeyValueRow(
                      label: 'Distance',
                      value: trip.distanceKm != null
                          ? '${Fmt.km(trip.distanceKm)} recorded'
                          : '${Fmt.km(route?.estimatedDistanceKm)} estimated',
                    ),
                    KeyValueRow(
                      label: 'Billing',
                      valueWidget: StatusBadge(
                        trip.billableStatus.label,
                        tone: Tones.billable(trip.billableStatus),
                        dense: true,
                      ),
                    ),
                    if (billing != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () =>
                              context.go(EmployerPaths.bill(billing.id)),
                          child: Text('View billing ${billing.id}'),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),
              PanelCard(
                title: 'Assignment history',
                child: DividedList(
                  empty: const Text('Not yet assigned.'),
                  children: [
                    for (final h in trip.assignmentHistory.reversed)
                      ListRow(
                        leading: const IconTile(
                          icon: Icons.history_rounded,
                          size: 32,
                        ),
                        title:
                            '${h.driverId ?? '—'} + Vehicle ${h.vehicleId ?? '—'}',
                        subtitle:
                            '${Fmt.dateTime(h.at)} · ${h.actorRole.label} · ${h.reason}',
                      ),
                  ],
                ),
              ),
              if (incidents.isNotEmpty) ...[
                const SizedBox(height: AppSpace.md),
                PanelCard(
                  title: 'Incidents',
                  child: DividedList(
                    children: [
                      for (final i in incidents)
                        ListRow(
                          title: '${i.reference} · ${i.type.label}',
                          subtitle: i.description,
                          trailing: StatusBadge(
                            i.status.label,
                            tone: Tones.incident(i.status),
                            dense: true,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (trip.instructions.isNotEmpty) ...[
                const SizedBox(height: AppSpace.md),
                PanelCard(
                  title: 'Instructions',
                  child: Text(trip.instructions, style: t.bodyMedium),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
