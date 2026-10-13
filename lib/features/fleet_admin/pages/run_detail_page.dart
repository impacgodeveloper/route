import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/widgets.dart';
import '../../../domain/models/models.dart';
import '../widgets/fleet_common.dart';
import '../widgets/run_views.dart';
import 'v2/mapping_table.dart';

class RunDetailPage extends ConsumerStatefulWidget {
  const RunDetailPage({super.key, required this.runId});
  final String runId;

  @override
  ConsumerState<RunDetailPage> createState() => _RunDetailPageState();
}

class _RunDetailPageState extends ConsumerState<RunDetailPage> {
  bool _busy = false;

  Future<void> _apply(OptimizationRun run) async {
    final guards = await showDialog<Map<String, String>>(
      context: context,
      builder: (c) => _ApplyDialog(run: run),
    );
    if (guards == null || !mounted) return;
    setState(() => _busy = true);
    final r = await ref
        .read(servicesProvider)
        .optimization
        .applyRun(run.id, guardReferences: guards);
    if (!mounted) return;
    setState(() => _busy = false);
    await showResult(context, r, failureTitle: 'Proposal not applied');
  }

  Future<void> _reject(OptimizationRun run) async {
    final r = await showReasonDialog(
      context,
      title: 'Reject ${run.reference}?',
      message:
          'The proposal is kept in history as rejected and cannot be applied afterwards.',
      confirmLabel: 'Reject run',
      destructive: true,
    );
    if (r == null || !mounted) return;
    await runAndShow(
      context,
      ref.read(servicesProvider).optimization.rejectRun(run.id, r.reason),
      successMessage: '${run.reference} rejected',
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final run = data.optimizationRun(widget.runId);
    if (run == null) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Run not found',
        message: 'It may have been removed by a demo reset.',
        actionLabel: 'Back to optimization',
        onAction: () => context.go('/fleet/optimization'),
      );
    }
    final t = Theme.of(context).textTheme;
    final config = data.optimizationConfig(run.configurationId);
    return AdminPage(
      title: 'Run ${run.reference}',
      subtitle:
          '${Fmt.dateTime(run.createdAt)} · for ${Fmt.weekdayLong(run.serviceDate)} · ${config?.name ?? run.configurationId}',
      actions: [
        TextButton.icon(
          onPressed: () => context.go('/fleet/optimization'),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Optimization'),
        ),
        if (run.appliedAt == null && !run.isRejected)
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _reject(run),
            icon: const Icon(Icons.block_rounded),
            label: const Text('Reject'),
          ),
        if (run.isFeasible && run.appliedAt == null && !run.isRejected)
          FilledButton.icon(
            onPressed: _busy ? null : () => _apply(run),
            icon: const Icon(Icons.check_rounded),
            label: const Text('Apply proposal'),
          ),
      ],
      children: [
        const SimulatedNote(DemoLabels.optimizer, icon: Icons.memory_outlined),
        const SizedBox(height: AppSpace.md),
        if (run.appliedAt != null) ...[
          InlineBanner(
            tone: StatusTone.success,
            title: 'Applied ${Fmt.dateTime(run.appliedAt)}',
            message: 'Trips created from this proposal:',
            actions: [
              for (final id in run.appliedTripIds)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 40),
                  ),
                  onPressed: () => context.go('/fleet/dispatch/trip/$id'),
                  child: Text(data.trips.byId(id)?.tripCode ?? id),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
        ],
        if (run.isRejected) ...[
          InlineBanner(
            tone: StatusTone.neutral,
            title: 'Rejected ${Fmt.dateTime(run.rejectedAt)}',
            message: run.rejectionReason ?? '',
          ),
          const SizedBox(height: AppSpace.md),
        ],
        if (run.isFeasible) ...[
          PanelCard(
            title: 'Mapping preview',
            subtitle:
                'Car-to-employee mappings this proposal would create (validated again on apply)',
            child: MappingTable(rows: MappingRow.fromRun(data, run)),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        ResponsiveSplit(
          left: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PanelCard(
                title: 'Result',
                child: RunSummary(run: run),
              ),
              const SizedBox(height: AppSpace.md),
              if (run.preferenceSummary.isNotEmpty) ...[
                PanelCard(
                  title: 'Preferences & weights',
                  subtitle: 'How saved employee preferences affected scoring',
                  child: _Lines(run.preferenceSummary),
                ),
                const SizedBox(height: AppSpace.md),
              ],
              if (run.isFeasible)
                for (final p in run.plans) ...[
                  VehiclePlanCard(plan: p),
                  const SizedBox(height: AppSpace.md),
                ],
              PanelCard(
                title: 'Explanation',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final line in run.explanation)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 3, right: 8),
                              child: Icon(
                                Icons.chevron_right_rounded,
                                size: 16,
                                color: AppColors.textMuted,
                              ),
                            ),
                            Expanded(child: Text(line, style: t.bodyMedium)),
                          ],
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
              if (run.isFeasible) ...[
                PanelCard(
                  title: 'Score breakdown',
                  child: ScoreBreakdownTable(run: run),
                ),
                const SizedBox(height: AppSpace.md),
              ],
              if (run.alternatives.isNotEmpty) ...[
                PanelCard(
                  title: 'Alternatives evaluated',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final a in run.alternatives)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(a, style: t.bodySmall),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.md),
              ],
              if (run.constraintsEvaluated.isNotEmpty) ...[
                PanelCard(
                  title: 'Constraints evaluated',
                  subtitle:
                      'Hard constraints are filters, never traded for score',
                  child: _Lines(
                    run.constraintsEvaluated,
                    icon: Icons.rule_rounded,
                  ),
                ),
                const SizedBox(height: AppSpace.md),
              ],
              PanelCard(
                title: 'Candidates',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Vehicles',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final v in run.candidateVehicleIds)
                          StatusBadge(
                            'Vehicle $v',
                            tone: run.plans.any((p) => p.vehicleId == v)
                                ? StatusTone.success
                                : StatusTone.neutral,
                            dense: true,
                          ),
                        if (run.candidateVehicleIds.isEmpty)
                          Text('None recorded', style: AppText.muted(context)),
                      ],
                    ),
                    const SizedBox(height: AppSpace.sm),
                    Text(
                      'Drivers',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final d in run.candidateDriverIds)
                          StatusBadge(
                            d,
                            tone: run.plans.any((p) => p.driverId == d)
                                ? StatusTone.success
                                : StatusTone.neutral,
                            dense: true,
                          ),
                        if (run.candidateDriverIds.isEmpty)
                          Text('None recorded', style: AppText.muted(context)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Green = used in the proposal.',
                      style: AppText.muted(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),
              PanelCard(
                title: 'Inputs & assumptions',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(run.inputSummary, style: t.bodySmall),
                    const SizedBox(height: AppSpace.sm),
                    for (final e in run.weightsSnapshot.entries)
                      KeyValueRow(
                        label: 'Weight · ${e.key}',
                        value: e.value.toStringAsFixed(1),
                        dense: true,
                      ),
                    const SizedBox(height: AppSpace.sm),
                    const SimulatedNote(
                      'Distances use fictional schematic coordinates with a demo traffic model (peaks 8–10 AM, 5–8 PM). Not live traffic.',
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

class _Lines extends StatelessWidget {
  const _Lines(this.lines, {this.icon = Icons.chevron_right_rounded});
  final List<String> lines;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final l in lines)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3, right: 8),
                child: Icon(icon, size: 16, color: AppColors.textMuted),
              ),
              Expanded(
                child: Text(l, style: Theme.of(context).textTheme.bodySmall),
              ),
            ],
          ),
        ),
    ],
  );
}

/// Confirms applying a run; collects a guard name for every plan that
/// draws its guard from the pool (hard rule — cannot apply without it).
class _ApplyDialog extends StatefulWidget {
  const _ApplyDialog({required this.run});
  final OptimizationRun run;

  @override
  State<_ApplyDialog> createState() => _ApplyDialogState();
}

class _ApplyDialogState extends State<_ApplyDialog> {
  late final Map<String, TextEditingController> _names = {
    for (final p in widget.run.plans)
      if (p.guardSource == 'pool') p.vehicleId: TextEditingController(),
  };

  @override
  void dispose() {
    for (final c in _names.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _complete => _names.values.every((c) => c.text.trim().length >= 2);

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    return AlertDialog(
      title: Text('Apply ${run.reference}?'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'This creates ${run.plans.length} assigned trip${run.plans.length == 1 ? '' : 's'} for ${Fmt.weekday(run.serviceDate)}: '
                '${run.plans.map((p) => 'Vehicle ${p.vehicleId} + ${p.driverId} (${p.employeeIds.join(', ')})').join('; ')}. '
                'Every trip is re-validated; if any fails nothing is created. Employees, drivers and the employer are notified locally.',
              ),
              if (_names.isNotEmpty) ...[
                const SizedBox(height: AppSpace.md),
                const InlineBanner(
                  tone: StatusTone.warning,
                  title: 'Security guard names required',
                  message:
                      'These vehicles have no assigned guard; name the pool guard for each (hard rule).',
                ),
                for (final e in _names.entries) ...[
                  const SizedBox(height: AppSpace.sm),
                  TextField(
                    controller: e.value,
                    decoration: InputDecoration(
                      labelText: 'Guard for Vehicle ${e.key}',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ],
              const SizedBox(height: AppSpace.sm),
              const SimulatedNote(DemoLabels.optimizer),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _complete
              ? () => Navigator.pop(context, {
                  for (final e in _names.entries) e.key: e.value.text.trim(),
                })
              : null,
          child: const Text('Apply proposal'),
        ),
      ],
    );
  }
}
