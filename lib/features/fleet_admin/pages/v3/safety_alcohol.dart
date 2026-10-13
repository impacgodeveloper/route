import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../domain/models/models.dart';
import '../../widgets/fleet_common.dart';

enum _Range { all, today, week }

StatusTone alcoholTone(AlcoholResult r) => switch (r) {
  AlcoholResult.pass => StatusTone.success,
  AlcoholResult.fail => StatusTone.danger,
  AlcoholResult.inconclusive => StatusTone.warning,
};

/// Breathalyzer log (simulated device), blocked drivers and review clears.
class SafetyAlcoholTab extends ConsumerStatefulWidget {
  const SafetyAlcoholTab({super.key});

  @override
  ConsumerState<SafetyAlcoholTab> createState() => _SafetyAlcoholTabState();
}

class _SafetyAlcoholTabState extends ConsumerState<SafetyAlcoholTab> {
  String? _driver;
  AlcoholResult? _result;
  _Range _range = _Range.all;

  Future<void> _clear(AlcoholTest a) async {
    final r = await showReasonDialog(
      context,
      title: 'Clear block for ${a.driverId}?',
      message:
          'Only clear after a supervised re-test or documented review. The driver can start trips again once a passing test exists for the check point.',
      label: 'Review note',
      confirmLabel: 'Clear block',
    );
    if (r == null || !mounted) return;
    await runAndShow(
      context,
      ref.read(servicesProvider).alcohol.clear(a.id, r.reason),
      successMessage: 'Block cleared for ${a.driverId}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final t = Theme.of(context).textTheme;
    final policy = data.policy;
    final now = data.now;
    final blocked = data.alcoholTests.where((a) => a.blocking).toList();
    final rows =
        data.alcoholTests.where((a) {
          if (_driver != null && a.driverId != _driver) return false;
          if (_result != null && a.result != _result) return false;
          return switch (_range) {
            _Range.all => true,
            _Range.today => sameDay(a.testedAt, now),
            _Range.week => now.difference(a.testedAt).inDays < 7,
          };
        }).toList()..sort((a, b) {
          if (a.blocking != b.blocking) return a.blocking ? -1 : 1;
          return b.testedAt.compareTo(a.testedAt);
        });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InlineBanner(
          tone: StatusTone.info,
          icon: Icons.science_outlined,
          title: policy.alcoholMonitoringEnabled
              ? 'Monitoring on · ${policy.alcoholThresholdMg == 0 ? 'zero tolerance' : 'threshold ${policy.alcoholThresholdMg} mg/100 ml'} · ${policy.alcoholCheckPoint.label.toLowerCase()}'
              : 'Alcohol monitoring is off',
          message:
              'Readings come from a SIMULATED breathalyzer device or supervisor entry — no real device is connected. A failed or inconclusive test blocks trip start until a pass or a reviewed clear.',
        ),
        const SizedBox(height: AppSpace.md),
        if (blocked.isNotEmpty) ...[
          PanelCard(
            title: 'Blocked drivers (${blocked.length})',
            subtitle: 'Cannot start trips until cleared or re-tested',
            child: Column(
              children: [
                for (final a in blocked)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const IconTile(
                      icon: Icons.block_rounded,
                      color: AppColors.danger,
                      size: 36,
                    ),
                    title: Text(
                      '${driverShort(data.driver(a.driverId))} · ${a.result.label}',
                    ),
                    subtitle: Text(
                      '${Fmt.dateTime(a.testedAt)} · ${a.readingMg.toStringAsFixed(1)} mg (limit ${a.thresholdMg.toStringAsFixed(1)})${a.incidentId != null ? ' · ${a.incidentId}' : ''}',
                    ),
                    trailing: FilledButton.tonal(
                      key: ValueKey('clear-${a.id}'),
                      onPressed: () => _clear(a),
                      child: const Text('Clear block'),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterChipBar<_Range>(
              options: _Range.values,
              selected: _range,
              onSelected: (r) => setState(() => _range = r),
              labelOf: (r) => switch (r) {
                _Range.all => 'All dates',
                _Range.today => 'Today',
                _Range.week => 'Last 7 days',
              },
            ),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _driver,
                decoration: const InputDecoration(labelText: 'Driver'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All drivers'),
                  ),
                  for (final d in data.drivers)
                    DropdownMenuItem(
                      value: d.id,
                      child: Text(
                        '${d.driverCode} · ${d.name}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _driver = v),
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<AlcoholResult?>(
                isExpanded: true,
                initialValue: _result,
                decoration: const InputDecoration(labelText: 'Result'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All results'),
                  ),
                  for (final r in AlcoholResult.values)
                    DropdownMenuItem(
                      value: r,
                      child: Text(r.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _result = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        AdaptiveTable<AlcoholTest>(
          rows: rows,
          empty: const EmptyState(
            icon: Icons.science_outlined,
            title: 'No tests match',
            message: 'Driver breathalyzer tests (simulated) appear here.',
            compact: true,
          ),
          columns: [
            TableCol('Tested', (a) => Text(Fmt.dateTime(a.testedAt)), flex: 3),
            TableCol(
              'Driver',
              (a) => Text(
                driverShort(data.driver(a.driverId)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              flex: 3,
            ),
            TableCol(
              'Reading',
              (a) => Text(
                '${a.readingMg.toStringAsFixed(1)} / ${a.thresholdMg.toStringAsFixed(1)} mg',
              ),
              flex: 2,
            ),
            TableCol(
              'Method',
              (a) =>
                  Text(a.method, maxLines: 1, overflow: TextOverflow.ellipsis),
              flex: 2,
            ),
            TableCol('Trip', (a) => Text(a.tripId ?? '—'), flex: 2),
            TableCol(
              'Incident',
              (a) => a.incidentId == null
                  ? const Text('—')
                  : TextButton(
                      onPressed: () => context.go(
                        '/fleet/monitoring/incident/${a.incidentId}',
                      ),
                      child: Text(a.incidentId!),
                    ),
              flex: 2,
            ),
            TableCol(
              'Result',
              (a) => StatusBadge(
                a.clearedAt != null
                    ? '${a.result.label} · cleared'
                    : a.result.label,
                tone: a.clearedAt != null
                    ? StatusTone.neutral
                    : alcoholTone(a.result),
                dense: true,
              ),
              flex: 3,
              numeric: true,
            ),
          ],
          mobileCard: (a) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      driverShort(data.driver(a.driverId)),
                      style: t.titleSmall,
                    ),
                  ),
                  StatusBadge(
                    a.clearedAt != null
                        ? '${a.result.label} · cleared'
                        : a.result.label,
                    tone: a.clearedAt != null
                        ? StatusTone.neutral
                        : alcoholTone(a.result),
                    dense: true,
                  ),
                ],
              ),
              Text(
                '${Fmt.dateTime(a.testedAt)} · ${a.readingMg.toStringAsFixed(1)} / ${a.thresholdMg.toStringAsFixed(1)} mg · ${a.method}',
                style: AppText.muted(context),
              ),
              if (a.clearedAt != null)
                Text(
                  'Cleared ${Fmt.dateTime(a.clearedAt)} by ${a.clearedBy}: ${a.note}',
                  style: t.bodySmall,
                ),
              if (a.incidentId != null)
                TextButton(
                  onPressed: () =>
                      context.go('/fleet/monitoring/incident/${a.incidentId}'),
                  child: Text('Incident ${a.incidentId}'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
