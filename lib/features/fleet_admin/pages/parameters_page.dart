import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/widgets.dart';
import '../../../domain/models/models.dart';
import '../../../domain/rules/parameter_catalog.dart';

enum _ParamFilter { all, live, catalog, hard }

class ParametersPage extends ConsumerStatefulWidget {
  const ParametersPage({super.key});

  @override
  ConsumerState<ParametersPage> createState() => _ParametersPageState();
}

class _ParametersPageState extends ConsumerState<ParametersPage> {
  String _query = '';
  _ParamFilter _filter = _ParamFilter.all;
  final Map<String, double> _values = {};
  final Map<String, bool> _active = {};
  List<String> _errors = const [];

  bool get _dirty => _values.isNotEmpty || _active.isNotEmpty;

  Future<void> _save(OptimizationConfig cfg) async {
    final next = cfg.copyWith(
      additionalParameters: {...cfg.additionalParameters, ..._values},
      activeParameters: {...cfg.activeParameters, ..._active},
    );
    final r = await ref.read(servicesProvider).optimization.saveConfig(next);
    if (!mounted) return;
    setState(() {
      _errors = r.errors;
      if (r.isOk) {
        _values.clear();
        _active.clear();
      }
    });
    await showResult(context, r);
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final cfg = data.optimizationConfigs.firstOrNull;
    final t = Theme.of(context).textTheme;
    if (cfg == null) {
      return const EmptyState(
        icon: Icons.tune_outlined,
        title: 'No profile',
        message: 'Reset demo data to restore the default profile.',
      );
    }
    final q = _query.toLowerCase();
    final list = ParameterCatalog.all.where((p) {
      final f = switch (_filter) {
        _ParamFilter.all => true,
        _ParamFilter.live => p.usedByDemoOptimizer,
        _ParamFilter.catalog => !p.usedByDemoOptimizer,
        _ParamFilter.hard => p.hardConstraint,
      };
      return f &&
          (q.isEmpty ||
              p.name.toLowerCase().contains(q) ||
              p.key.contains(q) ||
              p.description.toLowerCase().contains(q) ||
              p.category.label.toLowerCase().contains(q));
    }).toList();
    final groups = <ParameterCategory, List<ParameterDefinition>>{};
    for (final p in list) {
      groups.putIfAbsent(p.category, () => []).add(p);
    }

    return AdminPage(
      title: 'Optimization parameter catalog',
      subtitle:
          '${ParameterCatalog.count} parameters · ${ParameterCatalog.liveCount} active in demo. Catalog-only entries are definitions for future integrations — they are not connected to live data.',
      actions: [
        TextButton.icon(
          onPressed: () => context.go('/fleet/optimization'),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Optimization'),
        ),
        FilledButton.icon(
          onPressed: _dirty ? () => _save(cfg) : null,
          icon: const Icon(Icons.save_outlined),
          label: Text(
            _dirty
                ? 'Save changes (${_values.length + _active.length})'
                : 'Saved',
          ),
        ),
      ],
      children: [
        if (_errors.isNotEmpty) ...[
          InlineBanner(
            tone: StatusTone.danger,
            title: 'Not saved',
            messages: _errors,
          ),
          const SizedBox(height: AppSpace.md),
        ],
        LayoutBuilder(
          builder: (context, c) {
            final search = AppSearchField(
              hint: 'Search parameters',
              onChanged: (v) => setState(() => _query = v.trim()),
            );
            final chips = FilterChipBar<_ParamFilter>(
              options: _ParamFilter.values,
              selected: _filter,
              onSelected: (f) => setState(() => _filter = f),
              labelOf: (f) => switch (f) {
                _ParamFilter.all => 'All',
                _ParamFilter.live => 'Used by demo optimizer',
                _ParamFilter.catalog => 'Catalog only',
                _ParamFilter.hard => 'Hard constraints',
              },
              countOf: (f) => switch (f) {
                _ParamFilter.all => ParameterCatalog.count,
                _ParamFilter.live => ParameterCatalog.liveCount,
                _ParamFilter.catalog =>
                  ParameterCatalog.count - ParameterCatalog.liveCount,
                _ParamFilter.hard =>
                  ParameterCatalog.all.where((p) => p.hardConstraint).length,
              },
            );
            if (c.maxWidth < 820) {
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
        const SizedBox(height: AppSpace.md),
        if (groups.isEmpty)
          EmptyState(
            icon: Icons.search_off_rounded,
            title: 'No parameters match',
            message: 'Try a different search or filter.',
            actionLabel: 'Show all',
            onAction: () => setState(() => _filter = _ParamFilter.all),
          ),
        for (final g in groups.entries) ...[
          AppCard(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              initiallyExpanded:
                  q.isNotEmpty ||
                  _filter != _ParamFilter.all ||
                  g.key == ParameterCategory.timeWindows,
              tilePadding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
              title: Text(g.key.label, style: t.titleSmall),
              subtitle: Text(
                '${g.value.length} parameters · ${g.value.where((p) => p.usedByDemoOptimizer).length} used by demo',
                style: AppText.muted(context),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(
                AppSpace.md,
                0,
                AppSpace.md,
                AppSpace.sm,
              ),
              children: [
                for (final p in g.value)
                  _ParamRow(
                    def: p,
                    value: _values[p.key] ?? ParameterCatalog.value(cfg, p.key),
                    active:
                        _active[p.key] ?? ParameterCatalog.isActive(cfg, p.key),
                    onValue: (v) => setState(() => _values[p.key] = v),
                    onActive: (v) => setState(() => _active[p.key] = v),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.sm),
        ],
      ],
    );
  }
}

class _ParamRow extends StatelessWidget {
  const _ParamRow({
    required this.def,
    required this.value,
    required this.active,
    required this.onValue,
    required this.onActive,
  });
  final ParameterDefinition def;
  final double value;
  final bool active;
  final ValueChanged<double> onValue;
  final ValueChanged<bool> onActive;

  String _n(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final editable = def.isEditable && def.min < def.max;
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(def.name, style: t.titleSmall),
            if (def.usedByDemoOptimizer)
              const StatusBadge(
                'Used by demo optimizer',
                tone: StatusTone.teal,
                dense: true,
              )
            else
              const StatusBadge(
                'Catalog only (not connected)',
                tone: StatusTone.neutral,
                dense: true,
              ),
            StatusBadge(
              def.hardConstraint ? 'Hard' : 'Soft',
              tone: def.hardConstraint ? StatusTone.danger : StatusTone.info,
              dense: true,
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          def.description,
          style: t.bodySmall!.copyWith(color: AppColors.textSecondary),
        ),
        Text(
          '${def.key} · default ${_n(def.defaultValue)} ${def.unit} · range ${_n(def.min)}–${_n(def.max)} · source: ${def.dataSource}',
          style: AppText.muted(context),
        ),
      ],
    );
    final control = editable
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 110,
                child: TextFormField(
                  key: ValueKey('param-${def.key}'),
                  initialValue: _n(value),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    suffixText: def.unit.length <= 6 ? def.unit : null,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 12,
                    ),
                  ),
                  onFieldSubmitted: (s) {
                    final v = double.tryParse(s.trim());
                    if (v != null) onValue(v);
                  },
                  onChanged: (s) {
                    final v = double.tryParse(s.trim());
                    if (v != null) onValue(v);
                  },
                ),
              ),
              const SizedBox(width: AppSpace.xs),
              Tooltip(
                message: def.hardConstraint
                    ? 'Hard constraints always apply'
                    : 'Active in scoring',
                child: Switch(
                  value: def.hardConstraint ? true : active,
                  onChanged: def.hardConstraint ? null : onActive,
                ),
              ),
            ],
          )
        : Text('${_n(value)} ${def.unit}', style: t.labelMedium);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: LayoutBuilder(
        builder: (context, c) => c.maxWidth < 620
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  info,
                  const SizedBox(height: AppSpace.xs),
                  control,
                ],
              )
            : Row(
                children: [
                  Expanded(child: info),
                  const SizedBox(width: AppSpace.md),
                  control,
                ],
              ),
      ),
    );
  }
}
