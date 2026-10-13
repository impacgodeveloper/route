import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../domain/models/models.dart';
import '../../widgets/fleet_common.dart';

/// Fleet safety policy editor (alcohol, speed/geofence, SOS chain,
/// ad-hoc matching, analytics assumptions). Saves are confirmed + audited.
class SafetyPolicyTab extends ConsumerStatefulWidget {
  const SafetyPolicyTab({super.key});

  @override
  ConsumerState<SafetyPolicyTab> createState() => _SafetyPolicyTabState();
}

class _SafetyPolicyTabState extends ConsumerState<SafetyPolicyTab> {
  late FleetPolicy _p;
  late final _threshold = TextEditingController();
  late final _speed = TextEditingController();
  late final _corridor = TextEditingController();
  late final _detour = TextEditingController();
  late final _credit = TextEditingController();
  late final _co2 = TextEditingController();
  late final _baseSpeed = TextEditingController();
  late final _baseCost = TextEditingController();
  List<String> _errors = const [];
  bool _dirty = false;
  int _version = 0;

  @override
  void initState() {
    super.initState();
    _load(ref.read(dataProvider).policy);
  }

  void _load(FleetPolicy p) {
    _p = p;
    String n(num v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
    _threshold.text = n(p.alcoholThresholdMg);
    _speed.text = '${p.speedLimitKmh}';
    _corridor.text = n(p.routeCorridorKm);
    _detour.text = '${p.maxAddedDetourMinutes}';
    _credit.text = n(p.carbonCreditPricePerTonne);
    _co2.text = n(p.baselineCo2GramsPerKm);
    _baseSpeed.text = n(p.baselineSpeedKmh);
    _baseCost.text = n(p.baselineCostPerKm);
    _dirty = false;
    _version++;
  }

  @override
  void dispose() {
    for (final c in [
      _threshold,
      _speed,
      _corridor,
      _detour,
      _credit,
      _co2,
      _baseSpeed,
      _baseCost,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  FleetPolicy _draft() {
    double d(TextEditingController c) => double.tryParse(c.text.trim()) ?? -1;
    int i(TextEditingController c) => int.tryParse(c.text.trim()) ?? -1;
    return _p.copyWith(
      alcoholThresholdMg: d(_threshold),
      speedLimitKmh: i(_speed),
      routeCorridorKm: d(_corridor),
      maxAddedDetourMinutes: i(_detour),
      carbonCreditPricePerTonne: d(_credit),
      baselineCo2GramsPerKm: d(_co2),
      baselineSpeedKmh: d(_baseSpeed),
      baselineCostPerKm: d(_baseCost),
    );
  }

  void _set(FleetPolicy p) => setState(() {
    _p = p;
    _dirty = true;
  });

  Future<void> _save() async {
    final draft = _draft();
    final svc = ref.read(servicesProvider).policy;
    final errors = svc.validate(draft);
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    final ok = await showConfirmDialog(
      context,
      title: 'Save fleet safety policy?',
      message:
          'Changes apply to new alcohol tests, telematics alerts, SOS escalations and ad-hoc matching from now on. The change is recorded in the audit trail.',
      confirmLabel: 'Save policy',
    );
    if (!ok || !mounted) return;
    final r = await svc.save(draft);
    if (!mounted) return;
    setState(() {
      _errors = r.errors;
      if (r.isOk) _load(r.valueOrNull!);
    });
    if (r.isOk) showToast(context, 'Safety policy saved');
  }

  Widget _num(
    TextEditingController c,
    String label, {
    String? helper,
    String? suffix,
  }) => TextField(
    controller: c,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: label,
      helperText: helper,
      suffixText: suffix,
    ),
    onChanged: (_) => setState(() => _dirty = true),
  );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = _p;
    final alcohol = PanelCard(
      title: 'Alcohol monitoring',
      subtitle: 'Simulated breathalyzer · configurable per client policy',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: p.alcoholMonitoringEnabled,
            onChanged: (v) => _set(p.copyWith(alcoholMonitoringEnabled: v)),
            title: const Text('Alcohol monitoring'),
            subtitle: const Text(
              'Drivers must pass a test before the check point to start trips.',
            ),
          ),
          FormRow(
            children: [
              _num(
                _threshold,
                'Threshold',
                helper: '0 = zero tolerance',
                suffix: 'mg/100 ml',
              ),
              DropdownButtonFormField<AlcoholCheckPoint>(
                key: ValueKey('cp-$_version'),
                isExpanded: true,
                initialValue: p.alcoholCheckPoint,
                decoration: const InputDecoration(labelText: 'Check point'),
                items: [
                  for (final c in AlcoholCheckPoint.values)
                    DropdownMenuItem(value: c, child: Text(c.label)),
                ],
                onChanged: (v) => _set(p.copyWith(alcoholCheckPoint: v)),
              ),
            ],
          ),
        ],
      ),
    );
    final telematics = PanelCard(
      title: 'Speed & geofence',
      subtitle: 'Alerts from simulated telematics',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormRow(
            children: [
              _num(_speed, 'Speed limit', suffix: 'km/h'),
              _num(
                _corridor,
                'Route corridor',
                helper:
                    'Distance from the planned route before a deviation alert',
                suffix: 'km',
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: p.speedAlertsEnabled,
            onChanged: (v) => _set(p.copyWith(speedAlertsEnabled: v)),
            title: const Text('Speed alerts'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: p.geofenceAlertsEnabled,
            onChanged: (v) => _set(p.copyWith(geofenceAlertsEnabled: v)),
            title: const Text('Geofence alerts'),
          ),
        ],
      ),
    );
    final sos = PanelCard(
      title: 'SOS escalation chain',
      subtitle: 'Recipients alerted, in order, when an SOS is raised',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: [
              for (final r in SosRecipient.values)
                FilterChip(
                  label: Text(
                    r == SosRecipient.fleetManager
                        ? '${r.label} (mandatory)'
                        : r.label,
                  ),
                  selected: p.sosRecipients.contains(r),
                  onSelected: (sel) {
                    final next = [...p.sosRecipients];
                    sel ? next.add(r) : next.remove(r);
                    next.sort((a, b) => a.index.compareTo(b.index));
                    _set(p.copyWith(sosRecipients: next));
                  },
                ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          const SimulatedNote(
            'In-app recipients get a local alert. Police and personal contacts are never contacted automatically — shown as "integration required".',
          ),
        ],
      ),
    );
    final matching = PanelCard(
      title: 'Dynamic seat matching',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: p.autoMatchAdhoc,
            onChanged: (v) => _set(p.copyWith(autoMatchAdhoc: v)),
            title: const Text('Auto-match ad-hoc requests'),
            subtitle: const Text(
              'Place same-day requests into a feasible existing trip automatically.',
            ),
          ),
          _num(_detour, 'Max added detour per trip', suffix: 'min'),
        ],
      ),
    );
    final analytics = PanelCard(
      title: 'Analytics assumptions',
      subtitle:
          'Used for employer savings & indicative carbon credits (estimates, not certified)',
      child: Column(
        children: [
          FormRow(
            children: [
              _num(_credit, 'Carbon credit price', suffix: '₹/tCO₂'),
              _num(_co2, 'Baseline CO₂', suffix: 'g/km'),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          FormRow(
            children: [
              _num(_baseSpeed, 'Baseline speed', suffix: 'km/h'),
              _num(_baseCost, 'Baseline cost', suffix: '₹/km'),
            ],
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_errors.isNotEmpty) ...[
          InlineBanner(
            tone: StatusTone.danger,
            title: 'Policy not saved',
            messages: _errors,
          ),
          const SizedBox(height: AppSpace.md),
        ],
        ResponsiveSplit(
          left: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              alcohol,
              const SizedBox(height: AppSpace.md),
              telematics,
              const SizedBox(height: AppSpace.md),
              matching,
            ],
          ),
          right: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              sos,
              const SizedBox(height: AppSpace.md),
              analytics,
            ],
          ),
          leftFlex: 1,
          rightFlex: 1,
        ),
        const SizedBox(height: AppSpace.md),
        Row(
          children: [
            Expanded(
              child: Text(
                'Last updated ${Fmt.dateTime(ref.watch(dataProvider).policy.updatedAt)}',
                style: t.bodySmall!.copyWith(color: AppColors.textMuted),
              ),
            ),
            if (_dirty)
              TextButton(
                onPressed: () => setState(() {
                  _errors = const [];
                  _load(ref.read(dataProvider).policy);
                }),
                child: const Text('Discard'),
              ),
            const SizedBox(width: AppSpace.xs),
            FilledButton.icon(
              onPressed: _dirty ? _save : null,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save policy'),
            ),
          ],
        ),
      ],
    );
  }
}
