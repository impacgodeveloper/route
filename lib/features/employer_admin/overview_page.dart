import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import 'employer_common.dart';
import 'overview_cards.dart';
import 'sos_widgets.dart';

class EmployerOverviewPage extends ConsumerWidget {
  const EmployerOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final metrics = ref.watch(metricsProvider);
    final employer = data.primaryEmployer;
    final today = data.today;
    final trips = employerTrips(data);
    final todayTrips = trips
        .where((t) => sameDay(t.serviceDate, today))
        .toList();
    final upcoming = trips
        .where((t) => t.status.isUpcoming && !t.serviceDate.isBefore(today))
        .length;
    final week = DateRange.lastDays(today, 7);
    final completedWeek = trips
        .where(
          (t) =>
              t.status == TripStatus.completed && week.contains(t.serviceDate),
        )
        .length;
    final month = DateRange(DateTime(today.year, today.month, 1), today);
    final charges = metrics.charges(employer.id, month);
    final requests = employerOpenBookings(data);
    final alerts = employerAlerts(data);
    final services = ref.read(servicesProvider);
    final period = services.billingCycles.currentPeriod(employer);
    final running = services.billingCycles.preview(employer.id, period);
    final dueCycles = services.billingCycles.dueCycles(employer.id);
    final traffic = services.traffic
        .board()
        .where((s) => s.trip.employerId == employer.id)
        .toList();
    final delayed = traffic
        .where((s) => s.available && s.delayMinutes > 0)
        .toList();
    final infeasible = traffic.where((s) => s.available && !s.feasible).length;
    final ev = ref
        .read(servicesProvider)
        .optimization
        .evTarget(employer.id, today);
    final activeEmployees = data
        .employeesOf(employer.id)
        .where((e) => e.isActive)
        .length;
    final recentBilling = data.billingOf(employer.id).take(5).toList();
    final t = Theme.of(context).textTheme;

    return AdminPage(
      title: 'Good day, ${employer.code} admin',
      subtitle: '${Fmt.weekdayLong(today)} · ${employer.name}',
      actions: [
        OutlinedButton.icon(
          onPressed: () => context.go(EmployerPaths.import),
          icon: const Icon(Icons.upload_file_outlined),
          label: const Text('Import roster'),
        ),
        FilledButton.icon(
          onPressed: () => context.go(EmployerPaths.assignments),
          icon: const Icon(Icons.directions_car_outlined),
          label: const Text('Today\'s assignments'),
        ),
      ],
      children: [
        MetricGrid(
          minTileWidth: 190,
          children: [
            MetricTile(
              label: 'Active employees',
              value: '$activeEmployees',
              caption: '${data.employeesOf(employer.id).length} on roster',
              icon: Icons.groups_outlined,
              onTap: () => context.go(EmployerPaths.employees),
            ),
            MetricTile(
              label: 'Trips today',
              value:
                  '${todayTrips.where((x) => x.status != TripStatus.cancelled).length}',
              caption:
                  '${todayTrips.where((x) => x.status == TripStatus.cancelled).length} cancelled',
              icon: Icons.today_outlined,
              onTap: () => context.go(EmployerPaths.assignments),
            ),
            MetricTile(
              label: 'Upcoming trips',
              value: '$upcoming',
              caption: 'Planned or assigned',
              icon: Icons.event_outlined,
              tone: StatusTone.teal,
            ),
            MetricTile(
              label: 'Completed (7 days)',
              value: '$completedWeek',
              caption: 'Recorded completions',
              icon: Icons.task_alt_outlined,
              tone: StatusTone.success,
            ),
            MetricTile(
              label: 'Charges this month',
              value: Fmt.inr0(charges),
              caption: 'From generated billing lines',
              icon: Icons.currency_rupee_rounded,
              tone: StatusTone.teal,
              onTap: () => context.go(EmployerPaths.billing),
            ),
            MetricTile(
              label: 'Requests to review',
              value: '${requests.length}',
              caption: 'Open booking requests',
              icon: Icons.inbox_outlined,
              tone: requests.isEmpty ? StatusTone.success : StatusTone.warning,
            ),
            MetricTile(
              label: 'Service alerts',
              value: '${alerts.trips.length + alerts.incidents.length}',
              caption:
                  '${alerts.trips.length} trips · ${alerts.incidents.length} open incidents',
              icon: Icons.warning_amber_rounded,
              tone: alerts.trips.isEmpty && alerts.incidents.isEmpty
                  ? StatusTone.success
                  : StatusTone.warning,
            ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        const SosAlertsCard(),
        const SizedBox(height: AppSpace.lg),
        if (alerts.trips.isNotEmpty || alerts.incidents.isNotEmpty) ...[
          InlineBanner(
            tone: StatusTone.warning,
            title: 'Service alerts',
            messages: [
              for (final tr in alerts.trips)
                '${tr.tripCode} · ${tr.status.label}${tr.delayReason != null ? ': ${tr.delayReason}' : ''}',
              for (final i in alerts.incidents)
                '${i.reference} · ${i.type.label} on ${i.tripId}: ${i.description}',
            ],
          ),
          const SizedBox(height: AppSpace.lg),
        ],
        ResponsiveColumns(
          left: PanelCard(
            title: 'Today\'s trips',
            subtitle:
                '${todayTrips.length} trip${todayTrips.length == 1 ? '' : 's'} on ${Fmt.dateShort(today)}',
            trailing: TextButton(
              onPressed: () => context.go(EmployerPaths.assignments),
              child: const Text('View all'),
            ),
            child: DividedList(
              empty: const EmptyState(
                icon: Icons.event_busy_outlined,
                title: 'No trips today',
                message:
                    'Assignments made by the Fleet Manager will appear here.',
                compact: true,
              ),
              children: [
                for (final tr in todayTrips)
                  ListRow(
                    onTap: () => context.go(EmployerPaths.trip(tr.id)),
                    leading: IconTile(
                      icon: Icons.route_outlined,
                      size: 36,
                      color: Tones.trip(tr.status).foreground,
                      background: Tones.trip(tr.status).background,
                    ),
                    title: '${tr.tripCode} · ${Fmt.time(tr.scheduledStart)}',
                    subtitle:
                        '${tr.employeeIds.length} employees · ${data.driver(tr.assignedDriverId)?.name ?? 'No driver yet'} · ${tr.assignedVehicleId != null ? 'Vehicle ${tr.assignedVehicleId}' : 'No vehicle yet'}',
                    trailing: TripStatusBadge(tr.status, dense: true),
                  ),
              ],
            ),
          ),
          right: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BillingCycleCard(
                periodLabel: period.label,
                running:
                    running.total +
                    running.existingInvoices.fold<double>(
                      0,
                      (s, i) => s + i.total,
                    ),
                eligible: running.eligible.length,
                invoiced: running.existingInvoices
                    .map((i) => i.reference)
                    .toList(),
                due: dueCycles,
                active: employer.billingActive,
                cycleLabel: employer.billingCycle.label,
                nextBoundary: period.nextBoundary,
              ),
              const SizedBox(height: AppSpace.md),
              TrafficSummaryCard(
                tripsTracked: traffic.where((s) => s.available).length,
                delayed: delayed,
                infeasible: infeasible,
                level: data.traffic.label,
              ),
              const SizedBox(height: AppSpace.md),
              AnalyticsSummaryCard(
                summary: services.analytics.summary(
                  employer.id,
                  DateRange.lastDays(today, 30),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              UtilizationCard(usage: services.matching.utilization(today)),
              const SizedBox(height: AppSpace.md),
              PanelCard(
                title: 'EV allocation',
                subtitle: 'Target vs actual for today',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ProgressStat(
                      label:
                          '${ev.evTrips} of ${ev.totalTrips} assigned trips on EVs',
                      value: ev.actualPct / 100,
                      valueLabel:
                          '${ev.actualPct.toStringAsFixed(0)}% / ${ev.targetPct}% target',
                      target: ev.targetPct / 100,
                      color: AppColors.teal,
                    ),
                    const SizedBox(height: AppSpace.sm),
                    StatusBadge(
                      ev.feasible
                          ? (ev.actualPct + 0.01 >= ev.targetPct
                                ? 'Target met'
                                : 'Achievable')
                          : 'Not achievable today',
                      tone: ev.feasible
                          ? (ev.actualPct + 0.01 >= ev.targetPct
                                ? StatusTone.success
                                : StatusTone.info)
                          : StatusTone.warning,
                    ),
                    const SizedBox(height: AppSpace.xs),
                    for (final line in ev.explanation)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          line,
                          style: t.bodySmall!.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),
              PanelCard(
                title: 'Requests needing review',
                subtitle: 'The Fleet Manager approves and assigns requests',
                child: DividedList(
                  empty: const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpace.sm),
                    child: Text('No open requests.'),
                  ),
                  children: [
                    for (final b in requests.take(6))
                      ListRow(
                        title:
                            '${b.reference} · ${data.employeeLabel(b.employeeId)}',
                        subtitle:
                            '${Fmt.dayLabel(b.requestedDate, data.now)} · arrive by ${Fmt.minutesOfDay(b.requestedArrivalMinutes)} · ${b.requestedPickupLocationId} → ${b.requestedDestinationId}',
                        trailing: StatusBadge(
                          b.status.label,
                          tone: Tones.booking(b.status),
                          dense: true,
                        ),
                        onTap: () =>
                            context.go(EmployerPaths.employee(b.employeeId)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),
              PanelCard(
                title: 'Recent billing',
                trailing: TextButton(
                  onPressed: () => context.go(EmployerPaths.billing),
                  child: const Text('Billing'),
                ),
                child: DividedList(
                  empty: const Text('No billing lines yet.'),
                  children: [
                    for (final b in recentBilling)
                      ListRow(
                        title: '${b.tripCode} · ${Fmt.inr(b.totalAmount)}',
                        subtitle:
                            '${Fmt.dateShort(b.completedAt)} · ${b.billableDistanceKm.toStringAsFixed(1)} km',
                        trailing: StatusBadge(
                          b.status.label,
                          tone: Tones.billing(b.status),
                          dense: true,
                        ),
                        onTap: () => context.go(EmployerPaths.bill(b.id)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
