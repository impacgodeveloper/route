import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import 'employer_common.dart';
import 'policy_widgets.dart';

/// Arrival-time and transport policies for the employer.
class PoliciesPage extends ConsumerStatefulWidget {
  const PoliciesPage({super.key});

  @override
  ConsumerState<PoliciesPage> createState() => _PoliciesPageState();
}

class _PoliciesPageState extends ConsumerState<PoliciesPage> {
  Employer? _draft;
  final _rate = TextEditingController();
  List<String> _errors = const [];
  bool _busy = false;

  @override
  void dispose() {
    _rate.dispose();
    super.dispose();
  }

  void _reset(Employer e) {
    _draft = e;
    _rate.text = e.defaultDistanceRate.toStringAsFixed(2);
    _errors = const [];
  }

  Future<void> _save(Employer original) async {
    final rate = double.tryParse(_rate.text.trim());
    if (rate == null) {
      setState(() => _errors = ['Rate must be a number (₹ per km).']);
      return;
    }
    final next = _draft!.copyWith(defaultDistanceRate: rate);
    final consequential = <String>[
      if (original.defaultDistanceRate != next.defaultDistanceRate)
        'Billing rate ${Fmt.inr(original.defaultDistanceRate)} → ${Fmt.inr(next.defaultDistanceRate)} per km (applies to bills generated from now on).',
      if (original.maximumArrivalMinutes != next.maximumArrivalMinutes)
        'Maximum arrival ${Fmt.minutesOfDay(original.maximumArrivalMinutes)} → ${Fmt.minutesOfDay(next.maximumArrivalMinutes)} (new requests later than this are rejected).',
      if (original.securityGuardPolicyEnabled !=
          next.securityGuardPolicyEnabled)
        'Security guard policy ${next.securityGuardPolicyEnabled ? 'ON — flagged trips lose one passenger seat' : 'OFF'}.',
      if (original.pickupToleranceMinutes != next.pickupToleranceMinutes)
        'Pickup/drop tolerance ±${original.pickupToleranceMinutes} → ±${next.pickupToleranceMinutes} min for employees without an override.',
      ...shiftChanges(original, next),
    ];
    if (consequential.isNotEmpty) {
      final ok = await showConfirmDialog(
        context,
        title: 'Apply policy changes?',
        message: 'These changes affect scheduling or billing:',
        confirmLabel: 'Apply changes',
        extra: InlineBanner(
          tone: StatusTone.warning,
          title: 'Consequential changes',
          messages: consequential,
        ),
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    final r = await ref.read(servicesProvider).employers.update(next);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _errors = r.errors;
      if (r.isOk) _reset(r.valueOrNull!);
    });
    if (r.isOk) showToast(context, 'Policies saved');
  }

  /// Human-readable consequential shift-window changes (removed/edited
  /// windows still used by employees).
  List<String> shiftChanges(Employer a, Employer b) {
    final emps = ref
        .read(dataProvider)
        .employeesOf(a.id)
        .where((e) => e.isActive);
    int users(ShiftWindow s) => emps
        .where(
          (e) =>
              e.shiftStartMinutes == s.startMinutes &&
              e.shiftEndMinutes == s.endMinutes,
        )
        .length;
    final out = <String>[];
    for (final s in a.shifts) {
      final now = b.shifts.where((x) => x.id == s.id).firstOrNull;
      final n = users(s);
      if (now == null) {
        out.add(
          'Shift ${s.label} removed${n > 0 ? ' — $n employee(s) keep their current times as custom shifts' : ''}.',
        );
      } else if (now.startMinutes != s.startMinutes ||
          now.endMinutes != s.endMinutes) {
        out.add(
          'Shift ${s.label} times changed${n > 0 ? ' — $n employee(s) keep their saved times until edited' : ''}.',
        );
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final employer = data.primaryEmployer;
    if (_draft == null) _reset(employer);
    final d = _draft!;
    final t = Theme.of(context).textTheme;
    final emps = data
        .employeesOf(employer.id)
        .where((e) => e.isActive)
        .toList();
    final byArrival = <int, int>{};
    for (final e in emps) {
      byArrival[e.requiredArrivalMinutes] =
          (byArrival[e.requiredArrivalMinutes] ?? 0) + 1;
    }
    final arrivalKeys = byArrival.keys.toList()..sort();
    final overMax = emps
        .where((e) => e.requiredArrivalMinutes > d.maximumArrivalMinutes)
        .length;
    final dirty =
        d != employer ||
        _rate.text.trim() != employer.defaultDistanceRate.toStringAsFixed(2);

    void set(Employer e) => setState(() => _draft = e);

    return AdminPage(
      title: 'Rosters & Policies',
      subtitle:
          'Arrival-time, transport and customer policies for ${employer.code}. Hard limits are enforced by every workspace.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => context.go(EmployerPaths.import),
          icon: const Icon(Icons.upload_file_outlined),
          label: const Text('Import roster CSV'),
        ),
        OutlinedButton.icon(
          onPressed: () => context.go(EmployerPaths.employees),
          icon: const Icon(Icons.edit_calendar_outlined),
          label: const Text('Per-employee requirements'),
        ),
      ],
      children: [
        if (_errors.isNotEmpty) ...[
          InlineBanner(
            tone: StatusTone.danger,
            title: 'Policies not saved',
            messages: _errors,
          ),
          const SizedBox(height: AppSpace.md),
        ],
        ResponsiveColumns(
          left: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PanelCard(
                title: 'Arrival & billing',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FormRow(
                      children: [
                        TimeOfDayField(
                          label: 'Maximum permitted arrival',
                          minutes: d.maximumArrivalMinutes,
                          helper: overMax == 0
                              ? 'All active employees fit'
                              : '$overMax employee(s) currently require a later time',
                          onChanged: (m) =>
                              set(d.copyWith(maximumArrivalMinutes: m)),
                        ),
                        TextField(
                          controller: _rate,
                          onChanged: (_) => setState(() {}),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Distance rate',
                            prefixText: '₹ ',
                            suffixText: '/ km',
                            helperText:
                                'Used for billing after trip completion',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),
              ToleranceCard(
                value: d.pickupToleranceMinutes,
                onChanged: (v) => set(d.copyWith(pickupToleranceMinutes: v)),
              ),
              const SizedBox(height: AppSpace.md),
              ShiftEditor(
                shifts: d.shifts,
                employees: emps,
                onChanged: (s) => set(d.copyWith(shifts: s)),
              ),
              const SizedBox(height: AppSpace.md),
              PanelCard(
                title: 'Vehicle & EV preferences',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Allowed / preferred vehicle types',
                      style: t.titleSmall,
                    ),
                    const SizedBox(height: AppSpace.xs),
                    Wrap(
                      spacing: AppSpace.xs,
                      runSpacing: AppSpace.xs,
                      children: [
                        for (final vt in VehicleType.values)
                          FilterChip(
                            showCheckmark: true,
                            label: Text(vt.label),
                            selected: d.vehicleTypePreferences.contains(vt),
                            onSelected: (on) => set(
                              d.copyWith(
                                vehicleTypePreferences: on
                                    ? [...d.vehicleTypePreferences, vt]
                                    : d.vehicleTypePreferences
                                          .where((x) => x != vt)
                                          .toList(),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.md),
                    Text('Luxury class', style: t.titleSmall),
                    const SizedBox(height: AppSpace.xs),
                    SegmentedButton<LuxuryClass>(
                      segments: [
                        for (final l in LuxuryClass.values)
                          ButtonSegment(value: l, label: Text(l.label)),
                      ],
                      selected: {d.luxuryPreference},
                      onSelectionChanged: (s) =>
                          set(d.copyWith(luxuryPreference: s.first)),
                    ),
                    const SizedBox(height: AppSpace.md),
                    WeightSlider(
                      label: 'EV allocation target (%)',
                      description:
                          'A soft preference. It never overrides capacity, deadlines or availability.',
                      value: d.preferredEvPercentage.toDouble(),
                      max: 100,
                      divisions: 20,
                      onChanged: (v) =>
                          set(d.copyWith(preferredEvPercentage: v.round())),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),
              PanelCard(
                title: 'Optimization priorities',
                subtitle:
                    'Seed the Fleet Manager\'s cost vs punctuality trade-off.',
                child: Column(
                  children: [
                    WeightSlider(
                      label: 'Cost priority',
                      value: d.costPriority.toDouble(),
                      max: 100,
                      divisions: 20,
                      onChanged: (v) =>
                          set(d.copyWith(costPriority: v.round())),
                    ),
                    WeightSlider(
                      label: 'Punctuality priority',
                      value: d.punctualityPriority.toDouble(),
                      max: 100,
                      divisions: 20,
                      onChanged: (v) =>
                          set(d.copyWith(punctualityPriority: v.round())),
                    ),
                  ],
                ),
              ),
            ],
          ),
          right: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PanelCard(
                title: 'Safety & pooling',
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: d.securityGuardPolicyEnabled,
                      onChanged: (v) =>
                          set(d.copyWith(securityGuardPolicyEnabled: v)),
                      title: const Text('Security guard policy'),
                      subtitle: const Text(
                        'When a trip is explicitly flagged, one seat is reserved for a guard, reducing employee capacity. Never inferred from employee data.',
                      ),
                    ),
                    const Divider(),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: d.allowSharedPooling,
                      onChanged: (v) => set(d.copyWith(allowSharedPooling: v)),
                      title: const Text('Allow shared pooling'),
                      subtitle: const Text(
                        'Employees may share cabs when feasible.',
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: d.allowCrossEmployerPooling,
                      onChanged: (v) =>
                          set(d.copyWith(allowCrossEmployerPooling: v)),
                      title: const Text('Allow cross-employer pooling'),
                      subtitle: const Text(
                        'Pool with other companies\' employees only if they allow it too.',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),
              PanelCard(
                title: 'Required arrival distribution',
                subtitle: '${emps.length} active employees',
                child: SimpleBarChart(
                  values: [
                    for (final k in arrivalKeys)
                      (
                        Fmt.minutesOfDay(
                          k,
                        ).replaceAll(' AM', 'a').replaceAll(' PM', 'p'),
                        byArrival[k]!.toDouble(),
                      ),
                  ],
                  color: AppColors.employerAccent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: dirty ? () => setState(() => _reset(employer)) : null,
              child: const Text('Discard'),
            ),
            const SizedBox(width: AppSpace.xs),
            FilledButton(
              onPressed: _busy || !dirty ? null : () => _save(employer),
              child: const Text('Save policies'),
            ),
          ],
        ),
      ],
    );
  }
}
