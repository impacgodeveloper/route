import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import 'employee_common.dart';

/// Employee self-service time/distance preferences (0–3 importance).
/// Saved preferences are read by the NEXT local optimizer run only.
class EmployeeTravelPreferencesScreen extends ConsumerStatefulWidget {
  const EmployeeTravelPreferencesScreen({super.key});

  @override
  ConsumerState<EmployeeTravelPreferencesScreen> createState() =>
      _EmployeeTravelPreferencesScreenState();
}

class _EmployeeTravelPreferencesScreenState
    extends ConsumerState<EmployeeTravelPreferencesScreen> {
  Map<String, int>? _draft;
  bool _saving = false;
  bool _saved = false;
  List<String> _errors = const [];

  static String describe(String key) => switch (key) {
    TravelPreferenceKeys.travelTime =>
      'Less time in the vehicle, even if the route is a little longer.',
    TravelPreferenceKeys.distance => 'Fewer kilometres travelled overall.',
    TravelPreferenceKeys.detour =>
      'Fewer extra kilometres for other riders before your drop.',
    TravelPreferenceKeys.reliability =>
      'More buffer before your office arrival deadline.',
    _ => '',
  };

  Map<String, int> _current(Employee e) => {
    for (final k in TravelPreferenceKeys.active) k: e.preference(k),
  };

  Future<void> _save(Employee e) async {
    setState(() {
      _saving = true;
      _errors = const [];
    });
    final r = await ref
        .read(servicesProvider)
        .employees
        .updateTravelPreferences(e.id, _draft ?? _current(e));
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = r.isOk;
      _errors = r.errors;
      if (r.isOk) _draft = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final e = ref.watch(currentEmployeeProvider);
    if (e == null) return const Scaffold(body: LoadingState());
    final t = Theme.of(context).textTheme;
    final current = _current(e);
    final draft = _draft ?? current;
    final dirty = TravelPreferenceKeys.active.any(
      (k) => draft[k] != current[k],
    );

    return EmployeeSubPage(
      title: 'Travel preferences',
      children: [
        Text(
          'Tell the planner what matters most on your commute.',
          style: t.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Preferences are weighed against other riders and company policy. '
          'They never override capacity, safety or your arrival deadline.',
          style: t.bodyMedium!.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpace.lg),
        for (final k in TravelPreferenceKeys.active) ...[
          _PreferenceCard(
            label: TravelPreferenceKeys.label(k),
            description: describe(k),
            value: draft[k] ?? 0,
            onChanged: (v) => setState(() {
              _saved = false;
              _draft = {...draft, k: v};
            }),
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        _PreferenceCard(
          label: TravelPreferenceKeys.label(TravelPreferenceKeys.proximity),
          description:
              'Configurable — no effect while pickups are at your registered point.',
          value: 0,
          onChanged: null,
        ),
        const SizedBox(height: AppSpace.lg),
        if (_saved && !dirty) ...[
          const InlineBanner(
            tone: StatusTone.success,
            title: 'Preferences saved',
            message:
                'They apply to the NEXT optimization run. Your existing trips are not changed — '
                'any new proposal is reviewed by the Fleet Manager before it is applied.',
          ),
          const SizedBox(height: AppSpace.md),
        ],
        if (_errors.isNotEmpty) ...[
          InlineBanner(
            tone: StatusTone.danger,
            title: 'Not saved',
            messages: _errors,
          ),
          const SizedBox(height: AppSpace.md),
        ],
        FilledButton(
          onPressed: !dirty || _saving ? null : () => _save(e),
          child: Text(_saving ? 'Saving…' : 'Save preferences'),
        ),
        if (dirty) ...[
          const SizedBox(height: AppSpace.xs),
          OutlinedButton(
            onPressed: _saving ? null : () => setState(() => _draft = null),
            child: const Text('Discard changes'),
          ),
        ],
        const SizedBox(height: AppSpace.md),
        const SimulatedNote(
          'Used by the local demo optimizer only. Changes are recorded in the audit trail.',
        ),
      ],
    );
  }
}

class _PreferenceCard extends StatelessWidget {
  const _PreferenceCard({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String description;
  final int value;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final enabled = onChanged != null;
    final levelLabel = TravelPreferenceKeys.levels[value.clamp(0, 3)];
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.md,
          AppSpace.md,
          AppSpace.md,
          AppSpace.xs,
        ),
        color: enabled ? AppColors.white : AppColors.surfaceAlt,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(label, style: t.titleSmall)),
                const SizedBox(width: AppSpace.xs),
                StatusBadge(
                  enabled ? levelLabel : 'Not active',
                  tone: !enabled
                      ? StatusTone.neutral
                      : value == 0
                      ? StatusTone.neutral
                      : value == 3
                      ? StatusTone.info
                      : StatusTone.teal,
                  dense: true,
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(description, style: AppText.muted(context)),
            Slider(
              value: value.toDouble(),
              max: 3,
              divisions: 3,
              label: levelLabel,
              semanticFormatterCallback: (v) =>
                  '$label: ${TravelPreferenceKeys.levels[v.round()]}',
              onChanged: onChanged == null
                  ? null
                  : (v) => onChanged!(v.round()),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Not important', style: AppText.muted(context)),
                  Text('Very important', style: AppText.muted(context)),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.xs),
          ],
        ),
      ),
    );
  }
}
