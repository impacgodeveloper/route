import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/widgets.dart';
import '../../../domain/models/models.dart';
import '../widgets/fleet_common.dart';

class FleetReportsPage extends ConsumerStatefulWidget {
  const FleetReportsPage({super.key});

  @override
  ConsumerState<FleetReportsPage> createState() => _FleetReportsPageState();
}

class _FleetReportsPageState extends ConsumerState<FleetReportsPage> {
  int _days = 7;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final m = ref.watch(metricsProvider);
    final t = Theme.of(context).textTheme;
    final range = DateRange.lastDays(
      data.today.add(const Duration(days: 1)),
      _days + 1,
    );
    final trips = m.tripsIn(range);
    final completed = trips
        .where((x) => x.status == TripStatus.completed)
        .toList();
    final counts = m.tripStatusCounts(trips);
    final onTime = m.onTime(trips);
    final distance = m.recordedDistance(trips);
    final util = m.utilization(trips);
    final assigned = trips
        .where((x) => x.isAssigned && x.status != TripStatus.cancelled)
        .toList();
    final evShare = assigned.isEmpty
        ? 0.0
        : 100 *
              assigned
                  .where(
                    (x) => data.vehicle(x.assignedVehicleId)?.isEv ?? false,
                  )
                  .length /
              assigned.length;
    final incidents = data.incidents
        .where((i) => range.contains(i.createdAt))
        .toList();
    final delays = incidents.where((i) => i.type == IncidentType.delay).length;
    final missingDistance = completed.where((x) => x.distanceKm == null).length;
    final usage = m.vehicleUsage(range);
    final perf = m.driverPerformance(range);
    final byDay = m.tripsByDay(range);
    final runs = data.optimizationRuns;
    final vStatus = m.vehicleStatusCounts();

    return AdminPage(
      title: 'Operational reports',
      subtitle:
          '${Fmt.date(range.start)} – ${Fmt.date(range.end)} (includes tomorrow\'s scheduled trips). Calculated from local records only.',
      actions: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 7, label: Text('7 days')),
            ButtonSegment(value: 14, label: Text('14 days')),
            ButtonSegment(value: 30, label: Text('30 days')),
          ],
          selected: {_days},
          onSelectionChanged: (s) => setState(() => _days = s.first),
        ),
        OutlinedButton.icon(
          onPressed: () => exportCsv(
            context,
            ref,
            fileName: 'fleet_trips_${_days}d.csv',
            header: [
              'trip',
              'date',
              'status',
              'driver',
              'vehicle',
              'employees',
              'distance_km',
              'scheduled_start',
              'actual_start',
              'actual_arrival',
            ],
            rows: [
              for (final x in trips)
                [
                  x.tripCode,
                  Fmt.date(x.serviceDate),
                  x.status.label,
                  x.assignedDriverId,
                  x.assignedVehicleId,
                  x.employeeIds.join(' '),
                  x.distanceKm,
                  Fmt.time(x.scheduledStart),
                  Fmt.time(x.actualStart),
                  Fmt.time(x.actualArrival),
                ],
            ],
          ),
          icon: const Icon(Icons.download_outlined),
          label: const Text('Export trips CSV'),
        ),
      ],
      children: [
        MetricGrid(
          children: [
            MetricTile(
              label: 'Trips',
              value:
                  '${trips.where((x) => x.status != TripStatus.cancelled).length}',
              caption:
                  '${completed.length} completed · ${counts[TripStatus.cancelled] ?? 0} cancelled',
              icon: Icons.alt_route_outlined,
            ),
            MetricTile(
              label: 'Recorded distance',
              value: Fmt.km(distance),
              caption: missingDistance == 0
                  ? 'All completed trips have distance'
                  : '$missingDistance completed trip(s) missing distance',
              icon: Icons.straighten_rounded,
              tone: missingDistance == 0 ? StatusTone.info : StatusTone.warning,
            ),
            MetricTile(
              label: 'Seat utilization',
              value: Fmt.percent(util),
              caption: 'Employees ÷ employee seats offered',
              icon: Icons.event_seat_outlined,
              tone: StatusTone.teal,
            ),
            MetricTile(
              label: 'On-time arrivals',
              value: onTime.measured == 0
                  ? '—'
                  : Fmt.percent(100 * onTime.onTime / onTime.measured),
              caption: onTime.measured == 0
                  ? 'No trips with recorded timestamps'
                  : '${onTime.onTime} of ${onTime.measured} trips with timestamps',
              icon: Icons.schedule_outlined,
              tone: StatusTone.success,
            ),
            MetricTile(
              label: 'EV share',
              value: Fmt.percent(evShare),
              caption:
                  'of ${assigned.length} assigned trips · target ${data.primaryEmployer.preferredEvPercentage}%',
              icon: Icons.electric_car_outlined,
              tone: StatusTone.teal,
            ),
            MetricTile(
              label: 'Incidents',
              value: '${incidents.length}',
              caption:
                  '$delays delay reports · ${incidents.where((i) => i.isSos).length} SOS (demo)',
              icon: Icons.report_gmailerrorred_outlined,
              tone: incidents.isEmpty ? StatusTone.neutral : StatusTone.warning,
            ),
            MetricTile(
              label: 'Unassigned requests',
              value: '${data.openBookings.length}',
              caption: 'Currently open',
              icon: Icons.inbox_outlined,
            ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        ResponsiveSplit(
          left: PanelCard(
            title: 'Trips per day',
            child: SimpleBarChart(
              values: [
                for (final d in byDay)
                  (Fmt.dateShort(d.day).split(' ').first, d.value),
              ],
              height: 180,
            ),
          ),
          right: PanelCard(
            title: 'Vehicle availability now',
            child: Column(
              children: [
                for (final s in VehicleStatus.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.sm),
                    child: ProgressStat(
                      label: s.label,
                      value: data.vehicles.isEmpty
                          ? 0
                          : vStatus[s]! / data.vehicles.length,
                      valueLabel: '${vStatus[s]} of ${data.vehicles.length}',
                      color: Tones.vehicle(s).foreground,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        PanelCard(
          title: 'Vehicle utilization',
          trailing: TextButton.icon(
            onPressed: () => exportCsv(
              context,
              ref,
              fileName: 'vehicle_usage_${_days}d.csv',
              header: [
                'vehicle',
                'propulsion',
                'completed_trips',
                'distance_km',
                'seat_utilization_pct',
              ],
              rows: [
                for (final u in usage)
                  [
                    u.vehicle.vehicleCode,
                    u.vehicle.propulsion.label,
                    u.trips,
                    u.km.toStringAsFixed(1),
                    u.utilization.toStringAsFixed(0),
                  ],
              ],
            ),
            icon: const Icon(Icons.download_outlined),
            label: const Text('CSV'),
          ),
          child:
              AdaptiveTable<
                ({Vehicle vehicle, int trips, double km, double utilization})
              >(
                rows: usage,
                columns: [
                  TableCol(
                    'Vehicle',
                    (u) => Text(vehicleShort(u.vehicle), style: t.titleSmall),
                    flex: 4,
                  ),
                  TableCol(
                    'Completed trips',
                    (u) => Text('${u.trips}'),
                    flex: 2,
                    numeric: true,
                  ),
                  TableCol(
                    'Distance',
                    (u) => Text(Fmt.km(u.km)),
                    flex: 2,
                    numeric: true,
                  ),
                  TableCol(
                    'Seat utilization',
                    (u) => Text(Fmt.percent(u.utilization)),
                    flex: 2,
                    numeric: true,
                  ),
                ],
                mobileCard: (u) => Row(
                  children: [
                    Expanded(
                      child: Text(vehicleShort(u.vehicle), style: t.titleSmall),
                    ),
                    Text(
                      '${u.trips} trips · ${Fmt.km(u.km)} · ${Fmt.percent(u.utilization)}',
                      style: t.bodySmall,
                    ),
                  ],
                ),
              ),
        ),
        const SizedBox(height: AppSpace.md),
        PanelCard(
          title: 'Driver duty & completion',
          trailing: TextButton.icon(
            onPressed: () => exportCsv(
              context,
              ref,
              fileName: 'driver_performance_${_days}d.csv',
              header: [
                'driver',
                'name',
                'status',
                'assigned',
                'completed',
                'incidents',
              ],
              rows: [
                for (final p in perf)
                  [
                    p.driver.driverCode,
                    p.driver.name,
                    p.driver.status.label,
                    p.assigned,
                    p.completed,
                    p.incidents,
                  ],
              ],
            ),
            icon: const Icon(Icons.download_outlined),
            label: const Text('CSV'),
          ),
          child:
              AdaptiveTable<
                ({Driver driver, int assigned, int completed, int incidents})
              >(
                rows: perf,
                columns: [
                  TableCol(
                    'Driver',
                    (p) => Text(
                      '${p.driver.driverCode} · ${p.driver.name}',
                      style: t.titleSmall,
                    ),
                    flex: 4,
                  ),
                  TableCol(
                    'Duty',
                    (p) => StatusBadge(
                      p.driver.status.label,
                      tone: Tones.driver(p.driver.status),
                      dense: true,
                    ),
                    flex: 2,
                  ),
                  TableCol(
                    'Assigned',
                    (p) => Text('${p.assigned}'),
                    flex: 2,
                    numeric: true,
                  ),
                  TableCol(
                    'Completed',
                    (p) => Text('${p.completed}'),
                    flex: 2,
                    numeric: true,
                  ),
                  TableCol(
                    'Incidents',
                    (p) => Text('${p.incidents}'),
                    flex: 2,
                    numeric: true,
                  ),
                ],
                mobileCard: (p) => Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${p.driver.driverCode} · ${p.driver.name}',
                        style: t.titleSmall,
                      ),
                    ),
                    Text(
                      '${p.completed}/${p.assigned} done · ${p.incidents} inc.',
                      style: t.bodySmall,
                    ),
                  ],
                ),
              ),
        ),
        const SizedBox(height: AppSpace.md),
        PanelCard(
          title: 'Optimization runs',
          subtitle: 'Local demo optimizer · saved runs',
          child: AdaptiveTable<OptimizationRun>(
            rows: runs,
            columns: [
              TableCol(
                'Run',
                (r) => Text(r.reference, style: t.titleSmall),
                flex: 2,
              ),
              TableCol(
                'Status',
                (r) => StatusBadge(
                  r.isFeasible ? 'Feasible' : 'No feasible solution',
                  tone: r.isFeasible ? StatusTone.success : StatusTone.danger,
                  dense: true,
                ),
                flex: 3,
              ),
              TableCol(
                'Score',
                (r) => Text(r.isFeasible ? r.score.toStringAsFixed(1) : '—'),
                flex: 1,
                numeric: true,
              ),
              TableCol(
                'Distance',
                (r) => Text(r.isFeasible ? Fmt.km(r.totalDistanceKm) : '—'),
                flex: 2,
                numeric: true,
              ),
              TableCol(
                'Cost',
                (r) => Text(r.isFeasible ? Fmt.inr0(r.estimatedCost) : '—'),
                flex: 2,
                numeric: true,
              ),
              TableCol(
                'EV',
                (r) => Text(
                  r.isFeasible ? Fmt.percent(r.evAllocationPercentage) : '—',
                ),
                flex: 1,
                numeric: true,
              ),
              TableCol(
                'Applied',
                (r) => Text(r.appliedAt == null ? 'No' : 'Yes'),
                flex: 1,
                numeric: true,
              ),
            ],
            mobileCard: (r) => Row(
              children: [
                Expanded(child: Text(r.reference, style: t.titleSmall)),
                Text(
                  r.isFeasible
                      ? '${r.score.toStringAsFixed(1)} · ${Fmt.km(r.totalDistanceKm)} · ${Fmt.inr0(r.estimatedCost)}'
                      : 'No feasible solution',
                  style: t.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
