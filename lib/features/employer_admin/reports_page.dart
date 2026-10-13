import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import 'billing_page.dart';
import 'employer_common.dart';

/// Reports computed only from local records.
class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  int _days = 7;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final m = ref.watch(metricsProvider);
    final employer = data.primaryEmployer;
    // Include tomorrow's planned trips only in volume; ranges end today.
    final range = DateRange.lastDays(data.today, _days);
    final trips = m.tripsIn(range, employerId: employer.id);
    final nonCancelled = trips
        .where((t) => t.status != TripStatus.cancelled)
        .toList();
    final completed = trips
        .where((t) => t.status == TripStatus.completed)
        .toList();
    final completion = nonCancelled.isEmpty
        ? 0.0
        : 100 * completed.length / nonCancelled.length;
    final distance = m.recordedDistance(trips);
    final charges = m.charges(employer.id, range);
    final onTime = m.onTime(trips);
    final tripDays = m.tripsByDay(range, employerId: employer.id);
    final chargeDays = m.chargesByDay(employer.id, range);
    final assigned = trips
        .where((t) => t.isAssigned && t.status != TripStatus.cancelled)
        .toList();
    final evTrips = assigned
        .where((t) => data.vehicle(t.assignedVehicleId)?.isEv ?? false)
        .length;
    final perVehicle = <String, int>{};
    for (final t in assigned) {
      perVehicle[t.assignedVehicleId!] =
          (perVehicle[t.assignedVehicleId!] ?? 0) + 1;
    }
    final utilization = m.utilization(assigned);
    String label(DateTime d) =>
        _days <= 7 ? Fmt.weekday(d).split(',').first : '${d.day}';

    const header = [
      'Date',
      'Trips',
      'Completed',
      'Cancelled',
      'Recorded km',
      'Charges ₹',
    ];
    List<List<Object?>> rows() => [
      for (var i = 0; i < range.days; i++)
        () {
          final d = range.start.add(Duration(days: i));
          final ts = trips.where((t) => sameDay(t.serviceDate, d)).toList();
          return [
            Fmt.date(d),
            ts.length,
            ts.where((t) => t.status == TripStatus.completed).length,
            ts.where((t) => t.status == TripStatus.cancelled).length,
            m.recordedDistance(ts).toStringAsFixed(1),
            chargeDays[i].value.toStringAsFixed(2),
          ];
        }(),
    ];

    return AdminPage(
      title: 'Reports',
      subtitle:
          '${Fmt.date(range.start)} – ${Fmt.date(range.end)} · calculated from local records only',
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
            'report_${employer.code}_${_days}d.csv',
            header,
            rows(),
          ),
          icon: const Icon(Icons.download_outlined),
          label: const Text('Export CSV'),
        ),
      ],
      children: [
        MetricGrid(
          minTileWidth: 180,
          children: [
            MetricTile(
              label: 'Trips',
              value: '${nonCancelled.length}',
              caption: '${trips.length - nonCancelled.length} cancelled',
              icon: Icons.route_outlined,
            ),
            MetricTile(
              label: 'Completion rate',
              value: Fmt.percent(completion),
              caption: '${completed.length} completed',
              icon: Icons.task_alt_outlined,
              tone: StatusTone.success,
            ),
            MetricTile(
              label: 'Recorded distance',
              value: Fmt.km(distance),
              caption: 'Completed trips with distance',
              icon: Icons.straighten_rounded,
            ),
            MetricTile(
              label: 'Charges',
              value: Fmt.inr0(charges),
              caption: 'Billing lines in range',
              icon: Icons.currency_rupee_rounded,
              tone: StatusTone.teal,
            ),
            MetricTile(
              label: 'On-time arrival',
              value: onTime.measured == 0
                  ? '—'
                  : Fmt.percent(100 * onTime.onTime / onTime.measured),
              caption: onTime.measured == 0
                  ? 'No trips with timestamps yet'
                  : '${onTime.onTime} of ${onTime.measured} measured trips',
              icon: Icons.schedule_outlined,
              tone: StatusTone.info,
            ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        ResponsiveColumns(
          leftFlex: 1,
          rightFlex: 1,
          breakpoint: 900,
          left: PanelCard(
            title: 'Trip volume per day',
            subtitle: 'All non-draft trips by service date',
            child: SimpleBarChart(
              values: [for (final d in tripDays) (label(d.day), d.value)],
              color: AppColors.employerAccent,
            ),
          ),
          right: PanelCard(
            title: 'Charges per day',
            subtitle: 'By billing completion date',
            child: SimpleBarChart(
              values: [for (final d in chargeDays) (label(d.day), d.value)],
              color: AppColors.teal,
              format: (v) => Fmt.inr0(v),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        PanelCard(
          title: 'Allocation',
          subtitle: '${assigned.length} assigned trips in range',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProgressStat(
                label: 'EV share of assigned trips',
                value: assigned.isEmpty ? 0 : evTrips / assigned.length,
                valueLabel:
                    '$evTrips EV · ${assigned.length - evTrips} ICE/hybrid · target ${employer.preferredEvPercentage}%',
                target: employer.preferredEvPercentage / 100,
                color: AppColors.teal,
              ),
              const SizedBox(height: AppSpace.md),
              ProgressStat(
                label: 'Seat utilization',
                value: utilization / 100,
                valueLabel: Fmt.percent(utilization),
              ),
              const SizedBox(height: AppSpace.md),
              Text(
                'Trips per vehicle',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpace.xs),
              if (perVehicle.isEmpty)
                Text(
                  'No assigned trips in range.',
                  style: AppText.muted(context),
                ),
              for (final e in perVehicle.entries)
                ListRow(
                  leading: PropulsionBadge(data.vehicle(e.key)),
                  title:
                      'Vehicle ${e.key} · ${data.vehicle(e.key)?.type.label ?? ''}',
                  trailing: Text('${e.value} trip${e.value == 1 ? '' : 's'}'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
