import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/widgets.dart';
import '../../../domain/rules/capacity_rules.dart';
import '../widgets/fleet_common.dart';

class PoolingPage extends ConsumerStatefulWidget {
  const PoolingPage({super.key});

  @override
  ConsumerState<PoolingPage> createState() => _PoolingPageState();
}

class _PoolingPageState extends ConsumerState<PoolingPage> {
  late DateTime _date;
  final Set<String> _selected = {'E1', 'E2', 'E3', 'E4'};
  String? _destination;
  PoolingResult? _result;
  String? _pairA = 'E1';
  String? _pairB = 'E4';

  @override
  void initState() {
    super.initState();
    _date = ref.read(dataProvider).today.add(const Duration(days: 1));
  }

  void _quick(List<String> ids) => setState(() {
    _selected
      ..clear()
      ..addAll(ids);
    _result = null;
  });

  void _suggest() {
    final data = ref.read(dataProvider);
    final cfg = data.optimizationConfigs.first;
    setState(
      () => _result = ref
          .read(servicesProvider)
          .optimization
          .suggestPools(_selected.toList(), cfg, _date),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final t = Theme.of(context).textTheme;
    final cfg = data.optimizationConfigs.firstOrNull;
    final active = data.employees.where((e) => e.isActive).toList();
    final openForDate = data.openBookings
        .where((b) => sameDay(b.requestedDate, _date))
        .map((b) => b.employeeId)
        .toList();
    final filtered = active
        .where((e) => _destination == null || e.destinationId == _destination)
        .toList();
    final check =
        (cfg != null && _pairA != null && _pairB != null && _pairA != _pairB)
        ? ref
              .read(servicesProvider)
              .optimization
              .checkPair(data.employee(_pairA)!, data.employee(_pairB)!, cfg)
        : null;

    final selection = PanelCard(
      title: 'Select employees',
      subtitle: '${_selected.length} selected for ${Fmt.weekday(_date)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DateField(
            label: 'Service date',
            value: _date,
            firstDate: data.today,
            lastDate: data.today.add(const Duration(days: 30)),
            onChanged: (d) => setState(() {
              _date = d;
              _result = null;
            }),
          ),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ActionChip(
                label: const Text('E1–E4'),
                onPressed: () => _quick(['E1', 'E2', 'E3', 'E4']),
              ),
              ActionChip(
                label: const Text('E21–E40'),
                onPressed: () => _quick([for (var i = 21; i <= 40; i++) 'E$i']),
              ),
              ActionChip(
                label: Text('Open requests (${openForDate.length})'),
                onPressed: openForDate.isEmpty
                    ? null
                    : () => _quick(openForDate),
              ),
              ActionChip(
                label: const Text('Clear'),
                onPressed: () => _quick(const []),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: _destination,
            decoration: const InputDecoration(
              labelText: 'Filter list by destination',
            ),
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('All destinations'),
              ),
              for (final d in data.destinations)
                DropdownMenuItem(value: d.id, child: Text(d.label)),
            ],
            onChanged: (v) => setState(() => _destination = v),
          ),
          const SizedBox(height: AppSpace.sm),
          Container(
            height: 280,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: AppRadius.mdAll,
            ),
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (c, i) {
                final e = filtered[i];
                return CheckboxListTile(
                  dense: true,
                  value: _selected.contains(e.id),
                  onChanged: (v) => setState(() {
                    v == true ? _selected.add(e.id) : _selected.remove(e.id);
                    _result = null;
                  }),
                  title: Text('${e.employeeCode} · ${e.name}'),
                  subtitle: Text(
                    '${e.pickupLocationId} → ${e.destinationId} · by ${Fmt.minutesOfDay(e.requiredArrivalMinutes)}',
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpace.md),
          FilledButton.icon(
            onPressed: _selected.length < 2 || cfg == null ? null : _suggest,
            icon: const Icon(Icons.groups_outlined),
            label: const Text('Suggest pools'),
          ),
        ],
      ),
    );

    final result = _result;
    final results = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (result == null)
          const AppCard(
            child: EmptyState(
              icon: Icons.hub_outlined,
              title: 'Pool suggestions appear here',
              message:
                  'Select at least two employees and run "Suggest pools". Infeasible pools are never forced.',
              compact: true,
            ),
          )
        else ...[
          for (final n in result.notes) ...[
            InlineBanner(
              tone: StatusTone.info,
              title: 'Rules applied',
              message: n,
            ),
            const SizedBox(height: AppSpace.sm),
          ],
          if (result.groups.isEmpty)
            const InlineBanner(
              tone: StatusTone.warning,
              title: 'No feasible pools',
              message:
                  'No two selected employees satisfy every pooling limit. They would ride separately.',
            ),
          for (var i = 0; i < result.groups.length; i++) ...[
            _GroupCard(index: i + 1, group: result.groups[i], date: _date),
            const SizedBox(height: AppSpace.sm),
          ],
          if (result.unpooled.isNotEmpty)
            PanelCard(
              title: 'Not pooled (${result.unpooled.length})',
              child: Column(
                children: [
                  for (final e in result.unpooled.entries)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: InitialsAvatar(
                        initials: e.key.initials,
                        size: 34,
                        color: AppColors.warning,
                      ),
                      title: Text('${e.key.employeeCode} · ${e.key.name}'),
                      subtitle: Text(e.value.join(' · ')),
                    ),
                ],
              ),
            ),
        ],
        const SizedBox(height: AppSpace.md),
        PanelCard(
          title: 'Pairwise check',
          subtitle: 'Explain why two employees can or cannot share a vehicle',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FormRow(
                children: [
                  _empPicker(
                    data,
                    'Employee A',
                    _pairA,
                    (v) => setState(() => _pairA = v),
                  ),
                  _empPicker(
                    data,
                    'Employee B',
                    _pairB,
                    (v) => setState(() => _pairB = v),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              if (check != null)
                InlineBanner(
                  tone: check.feasible ? StatusTone.success : StatusTone.danger,
                  title: check.feasible ? 'Can be pooled' : 'Cannot be pooled',
                  messages: check.reasons,
                )
              else
                Text('Pick two different employees.', style: t.bodySmall),
            ],
          ),
        ),
      ],
    );

    return AdminPage(
      title: 'Employee pooling',
      subtitle:
          'Group employees into shared cabs only where pickup, destination, arrival time, capacity and policy allow.',
      children: [
        ResponsiveSplit(
          left: selection,
          right: results,
          leftFlex: 2,
          rightFlex: 3,
        ),
      ],
    );
  }

  Widget _empPicker(
    DataView data,
    String label,
    String? value,
    ValueChanged<String?> onChanged,
  ) => DropdownButtonFormField<String>(
    isExpanded: true,
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final e in data.employees.where((e) => e.isActive))
        DropdownMenuItem(
          value: e.id,
          child: Text(
            '${e.employeeCode} · ${e.name}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: onChanged,
  );
}

class _GroupCard extends ConsumerWidget {
  const _GroupCard({
    required this.index,
    required this.group,
    required this.date,
  });
  final int index;
  final PoolGroup group;
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = group.suggestedVehicle;
    return PanelCard(
      title: 'Pool $index · ${group.employees.length} employees',
      subtitle: v == null
          ? 'No single available vehicle fits this group'
          : 'Suggested: ${vehicleShort(v)} (${CapacityRules.passengerCapacity(v)} seats)',
      trailing: FilledButton.tonal(
        onPressed: () => context.go(
          '/fleet/dispatch/new?employees=${group.employees.map((e) => e.id).join(',')}&date=${date.toIso8601String().substring(0, 10)}',
        ),
        child: const Text('Create trip'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in group.employees)
                Chip(
                  label: Text(
                    '${e.employeeCode} · ${e.pickupLocationId}→${e.destinationId} · ${Fmt.minutesOfDay(e.requiredArrivalMinutes)}',
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          for (final r in group.reasons)
            Row(
              children: [
                const Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: AppColors.success,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(r, style: Theme.of(context).textTheme.bodySmall),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
