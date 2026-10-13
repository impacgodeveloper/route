import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/widgets.dart';
import '../../../domain/models/models.dart';
import 'fleet_common.dart';
import 'plan_preview.dart';

/// Score + headline numbers, or the infeasibility reasons.
class RunSummary extends StatelessWidget {
  const RunSummary({super.key, required this.run});
  final OptimizationRun run;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (!run.isFeasible) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InlineBanner(
            tone: StatusTone.danger,
            title: 'No feasible assignment',
            message: 'Hard constraints failed — no route was fabricated.',
            messages: run.hardConstraintViolations,
          ),
          if (run.remedies.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            InlineBanner(
              tone: StatusTone.info,
              icon: Icons.lightbulb_outline_rounded,
              title: 'Possible remedies',
              messages: run.remedies,
            ),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              run.score.toStringAsFixed(1),
              style: t.displaySmall!.copyWith(fontFeatures: AppText.tabular),
            ),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('/ 100 score', style: AppText.secondary(context)),
            ),
            const Spacer(),
            if (run.isRejected)
              const StatusBadge('Rejected', tone: StatusTone.neutral)
            else if (run.appliedAt != null)
              const StatusBadge('Applied', tone: StatusTone.success)
            else
              const StatusBadge('Proposal', tone: StatusTone.info),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        StatStrip(
          stats: [
            ('vehicles', '${run.plans.length}'),
            ('distance', Fmt.km(run.totalDistanceKm)),
            ('vehicle-minutes', '${run.estimatedMinutes}'),
            ('est. cost', Fmt.inr0(run.estimatedCost)),
            ('on-time score', '${run.onTimeScore.toStringAsFixed(0)}%'),
            (
              'seat utilization',
              '${run.vehicleUtilization.toStringAsFixed(0)}%',
            ),
            ('EV share', '${run.evAllocationPercentage.toStringAsFixed(0)}%'),
          ],
        ),
        if (run.warnings.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          InlineBanner(
            tone: StatusTone.warning,
            title: 'Warnings',
            messages: run.warnings,
          ),
        ],
      ],
    );
  }
}

/// Weighted score breakdown table.
class ScoreBreakdownTable extends StatelessWidget {
  const ScoreBreakdownTable({super.key, required this.run});
  final OptimizationRun run;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final wSum = run.scoreBreakdown.fold<double>(0, (s, c) => s + c.weight);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Score = 100 × (1 − Σ weight × penalty ÷ Σ weights). Penalties are 0 (ideal) to 1 (worst among evaluated alternatives).',
          style: AppText.muted(context),
        ),
        const SizedBox(height: AppSpace.sm),
        for (final c in run.scoreBreakdown)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(c.label, style: t.titleSmall)),
                    Text(
                      'w ${c.weight.toStringAsFixed(1)} × p ${c.normalizedPenalty.toStringAsFixed(2)} = ${_pts(wSum == 0 ? 0 : 100 * c.weight * c.normalizedPenalty / wSum)}',
                      style: t.labelMedium!.copyWith(
                        fontFeatures: AppText.tabular,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: c.normalizedPenalty.clamp(0, 1),
                    minHeight: 6,
                    color: c.normalizedPenalty > 0.5
                        ? AppColors.warning
                        : AppColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(c.detail, style: AppText.muted(context)),
              ],
            ),
          ),
      ],
    );
  }
}

/// One vehicle's plan.
class VehiclePlanCard extends ConsumerWidget {
  const VehiclePlanCard({super.key, required this.plan});
  final VehiclePlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final v = data.vehicle(plan.vehicleId);
    final d = data.driver(plan.driverId);
    final onTime = plan.onTime;
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconTile(
                icon: (v?.isEv ?? false)
                    ? Icons.electric_car_outlined
                    : Icons.directions_car_outlined,
                color: (v?.isEv ?? false) ? AppColors.teal : AppColors.deepNavy,
                size: 36,
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicleShort(v),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(driverShort(d), style: AppText.muted(context)),
                  ],
                ),
              ),
              StatusBadge(
                onTime ? 'On time' : 'Late',
                tone: onTime ? StatusTone.success : StatusTone.danger,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          StatStrip(
            stats: [
              (
                'employees',
                '${plan.employeeIds.length}/${plan.passengerCapacity}',
              ),
              ('distance', Fmt.km(plan.distanceKm)),
              ('duration', Fmt.duration(plan.durationMinutes)),
              ('cost', Fmt.inr0(plan.estimatedCost)),
              ('departs', Fmt.time(plan.departure)),
              (
                'first drop / deadline',
                '${Fmt.time(plan.latestArrival)} / ${Fmt.time(plan.deadline)}',
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            'Seats: ${plan.totalSeats > 0 ? plan.totalSeats : (v?.totalSeats ?? '—')} total − 1 driver − ${plan.guardSeats} guard = ${plan.passengerCapacity} employee seats · ${plan.variant.label}',
            style: AppText.muted(context),
          ),
          const SizedBox(height: 2),
          Builder(
            builder: (context) {
              final start = data.location(plan.startLocationId);
              return Text(
                'Starts from ${start?.label ?? 'vehicle position (no parking set)'} · deadhead ${Fmt.km(plan.deadheadKm)}'
                '${plan.guardSeats > 0 ? ' · guard: ${plan.guardSource == 'pool'
                          ? 'from guard pool (name needed on apply)'
                          : plan.guardSource == 'vehicle'
                          ? 'vehicle\'s assigned guard'
                          : 'required'}' : ''}',
                style: AppText.muted(context),
              );
            },
          ),
          const SizedBox(height: AppSpace.md),
          PlanPreview(stops: plan.stops, mapHeight: 150),
        ],
      ),
    );
  }
}

/// Side-by-side comparison of two runs.
class RunComparison extends StatelessWidget {
  const RunComparison({super.key, required this.a, required this.b});
  final OptimizationRun a;
  final OptimizationRun b;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    String f(OptimizationRun r, String k) {
      if (!r.isFeasible && k != 'status') return '—';
      return switch (k) {
        'status' => r.isFeasible ? 'Feasible' : 'No feasible solution',
        'score' => r.score.toStringAsFixed(1),
        'vehicles' => '${r.plans.length}',
        'km' => Fmt.km(r.totalDistanceKm),
        'cost' => Fmt.inr0(r.estimatedCost),
        'minutes' => '${r.estimatedMinutes}',
        'ontime' => '${r.onTimeScore.toStringAsFixed(0)}%',
        'util' => '${r.vehicleUtilization.toStringAsFixed(0)}%',
        'ev' => '${r.evAllocationPercentage.toStringAsFixed(0)}%',
        _ => '',
      };
    }

    const rows = [
      ('status', 'Status'),
      ('score', 'Score'),
      ('vehicles', 'Vehicles'),
      ('km', 'Distance'),
      ('cost', 'Est. cost'),
      ('minutes', 'Vehicle-minutes'),
      ('ontime', 'On-time score'),
      ('util', 'Seat utilization'),
      ('ev', 'EV share'),
    ];
    return Column(
      children: [
        Row(
          children: [
            const Expanded(flex: 3, child: SizedBox()),
            Expanded(
              flex: 3,
              child: Text(
                a.reference,
                style: t.titleSmall,
                textAlign: TextAlign.right,
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                b.reference,
                style: t.titleSmall,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
        const Divider(height: AppSpace.md),
        for (final (k, label) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(label, style: AppText.secondary(context)),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    f(a, k),
                    textAlign: TextAlign.right,
                    style: t.labelMedium,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    f(b, k),
                    textAlign: TextAlign.right,
                    style: t.labelMedium,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

String _pts(double v) => v < 0.05 ? '0 pts' : '−${v.toStringAsFixed(1)} pts';
