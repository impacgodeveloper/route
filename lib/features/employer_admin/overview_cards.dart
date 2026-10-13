import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/widgets.dart';
import '../../domain/services/app_services.dart';
import 'employer_common.dart';

/// Overview: current billing period running total and due cycles.
class BillingCycleCard extends StatelessWidget {
  const BillingCycleCard({
    super.key,
    required this.periodLabel,
    required this.running,
    required this.eligible,
    required this.invoiced,
    required this.due,
    required this.active,
    required this.cycleLabel,
    required this.nextBoundary,
  });

  final String periodLabel;
  final double running;
  final int eligible;
  final List<String> invoiced;
  final List<CyclePreview> due;
  final bool active;
  final String cycleLabel;
  final DateTime nextBoundary;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return PanelCard(
      title: 'Billing cycle',
      subtitle:
          '$cycleLabel · ${active ? 'next boundary ${Fmt.weekday(nextBoundary)}' : 'paused'}',
      trailing: TextButton(
        onPressed: () => context.go(EmployerPaths.billing),
        child: const Text('Billing'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            periodLabel,
            style: t.bodySmall!.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            Fmt.inr(running),
            key: const Key('overview-cycle-running'),
            style: t.headlineSmall!.copyWith(fontFeatures: AppText.tabular),
          ),
          Text(
            'Running total · $eligible line${eligible == 1 ? '' : 's'} not yet invoiced${invoiced.isEmpty ? '' : ' · invoiced: ${invoiced.join(', ')}'}',
            style: AppText.muted(context),
          ),
          const SizedBox(height: AppSpace.sm),
          if (due.isEmpty)
            const StatusBadge(
              'No cycles due',
              tone: StatusTone.success,
              dense: true,
            )
          else
            InlineBanner(
              tone: StatusTone.warning,
              title: '${due.length} cycle${due.length == 1 ? '' : 's'} due',
              messages: [
                for (final d in due) '${d.period.label} · ${Fmt.inr(d.total)}',
              ],
            ),
        ],
      ),
    );
  }
}

/// Overview: simulated traffic summary for the employer's trips.
class TrafficSummaryCard extends StatelessWidget {
  const TrafficSummaryCard({
    super.key,
    required this.tripsTracked,
    required this.delayed,
    required this.infeasible,
    required this.level,
  });
  final int tripsTracked;
  final List<TrafficTripStatus> delayed;
  final int infeasible;
  final String level;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      title: 'Traffic & movement',
      subtitle: '$level · simulated',
      trailing: TextButton(
        onPressed: () => context.go(EmployerPaths.traffic),
        child: const Text('Open'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: [
              StatusBadge(
                '$tripsTracked tracked',
                tone: StatusTone.info,
                dense: true,
              ),
              StatusBadge(
                '${delayed.length} delayed',
                key: const Key('overview-traffic-delayed'),
                tone: delayed.isEmpty ? StatusTone.success : StatusTone.warning,
                dense: true,
              ),
              if (infeasible > 0)
                StatusBadge(
                  '$infeasible at risk of missing deadline',
                  tone: StatusTone.danger,
                  dense: true,
                ),
            ],
          ),
          for (final s in delayed.take(3))
            ListRow(
              onTap: () => context.go(EmployerPaths.trip(s.trip.id)),
              title: '${s.trip.tripCode} · +${s.delayMinutes} min',
              subtitle: s.statusLabel,
            ),
          const SizedBox(height: AppSpace.xs),
          const SimulatedNote(
            DemoLabels.trafficSimulated,
            icon: Icons.traffic_outlined,
          ),
        ],
      ),
    );
  }
}

/// Overview: 30-day savings and indicative carbon credits.
class AnalyticsSummaryCard extends StatelessWidget {
  const AnalyticsSummaryCard({super.key, required this.summary});
  final AnalyticsSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return PanelCard(
      title: 'Savings & carbon · 30 days',
      subtitle: 'vs single-occupancy baseline',
      trailing: TextButton(
        onPressed: () => context.go(EmployerPaths.analytics),
        child: const Text('Analytics'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeyValueRow(
            dense: true,
            label: 'CO2 avoided',
            value:
                '${s.co2SavedKg.toStringAsFixed(1)} kg (${s.co2ReductionPct.toStringAsFixed(0)}%)',
          ),
          KeyValueRow(
            dense: true,
            label: 'Time saved',
            value: '${(s.minutesSaved / 60).toStringAsFixed(1)} vehicle-h',
          ),
          KeyValueRow(
            dense: true,
            label: 'Savings',
            value: Fmt.inr0(s.costSaved),
          ),
          KeyValueRow(
            dense: true,
            label: 'Indicative credits',
            value: '${s.creditTonnes.toStringAsFixed(3)} t',
          ),
          const SizedBox(height: AppSpace.xs),
          const SimulatedNote(
            'Indicative, not issued credits — certification required.',
            icon: Icons.gpp_maybe_outlined,
          ),
        ],
      ),
    );
  }
}

/// Overview: dynamic seat matching utilization for today.
class UtilizationCard extends StatelessWidget {
  const UtilizationCard({super.key, required this.usage});
  final ({int released, int reused, int freeSeats}) usage;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      title: 'Seat utilization · today',
      subtitle: 'Absences release seats that ad-hoc bookings can reuse',
      child: Wrap(
        spacing: AppSpace.xs,
        runSpacing: AppSpace.xs,
        children: [
          StatusBadge(
            '${usage.released} released',
            key: const Key('util-released'),
            tone: StatusTone.warning,
            dense: true,
          ),
          StatusBadge(
            '${usage.reused} reused',
            key: const Key('util-reused'),
            tone: StatusTone.success,
            dense: true,
          ),
          StatusBadge(
            '${usage.freeSeats} free seats',
            key: const Key('util-free'),
            tone: StatusTone.info,
            dense: true,
          ),
        ],
      ),
    );
  }
}
