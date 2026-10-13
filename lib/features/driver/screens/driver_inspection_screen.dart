import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/widgets.dart';
import '../../../domain/models/models.dart';
import '../../../domain/rules/capacity_rules.dart';
import '../../../domain/rules/inspection_rules.dart';
import '../driver_common.dart';

/// Vehicle info + pre-trip checklist. Critical failures block trip start.
class DriverInspectionScreen extends ConsumerStatefulWidget {
  const DriverInspectionScreen({super.key, this.vehicleId});
  final String? vehicleId;

  @override
  ConsumerState<DriverInspectionScreen> createState() =>
      _DriverInspectionScreenState();
}

class _DriverInspectionScreenState
    extends ConsumerState<DriverInspectionScreen> {
  List<InspectionItem> _items = InspectionRules.blankChecklist();
  final Map<String, TextEditingController> _notes = {};
  final _general = TextEditingController();
  String? _photo;
  bool _busy = false;
  List<String> _errors = const [];
  Inspection? _submitted;
  bool _newInspection = false;

  @override
  void dispose() {
    for (final c in _notes.values) {
      c.dispose();
    }
    _general.dispose();
    super.dispose();
  }

  TextEditingController _note(String key) =>
      _notes.putIfAbsent(key, TextEditingController.new);

  Future<void> _submit(String driverId, Vehicle v) async {
    final items = [
      for (final i in _items)
        i.copyWith(note: _notes[i.key]?.text.trim() ?? ''),
    ];
    final critical = items
        .where((i) => i.critical && i.result == CheckResult.fail)
        .toList();
    if (critical.isNotEmpty) {
      final ok = await showConfirmDialog(
        context,
        title: 'Submit failed inspection?',
        message:
            'Critical item(s) failed: ${critical.map((i) => i.label).join(', ')}. Vehicle ${v.vehicleCode} will be set to maintenance, trip start will be blocked and a defect report is created for the Fleet Manager.',
        confirmLabel: 'Submit & report defect',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    final r = await ref
        .read(servicesProvider)
        .driverOps
        .submitInspection(
          driverId: driverId,
          vehicleId: v.id,
          items: items,
          notes: _general.text,
          photoPath: _photo,
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _errors = r.errors;
      _submitted = r.valueOrNull;
    });
  }

  @override
  Widget build(BuildContext context) {
    final day = ref.watch(driverDayProvider);
    if (day == null) return const LoadingState();
    final data = day.data;
    final v = data.vehicle(widget.vehicleId) ?? day.vehicle;
    final t = Theme.of(context).textTheme;
    if (v == null) {
      return Scaffold(
        appBar: driverAppBar(context, 'Inspection'),
        body: const EmptyState(
          icon: Icons.directions_car_outlined,
          title: 'No vehicle assigned',
          message:
              'Ask the Fleet Manager to assign a vehicle before inspecting.',
        ),
      );
    }
    final today = data.todayInspection(v.id);
    final submitted =
        _submitted ??
        (!_newInspection && today?.driverId == day.driver.id ? today : null);
    final seats = CapacityRules.breakdown(v);

    return Scaffold(
      appBar: driverAppBar(context, 'Vehicle ${v.vehicleCode}'),
      body: MobilePage(
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconTile(
                      icon: v.isEv
                          ? Icons.electric_car_outlined
                          : Icons.directions_car_outlined,
                      color: AppColors.driverAccent,
                      size: 48,
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Vehicle ${v.vehicleCode}', style: t.titleLarge),
                          Text(
                            '${v.fictionalRegistration} · ${v.propulsion.label} ${v.type.label}',
                            style: AppText.secondary(context),
                          ),
                        ],
                      ),
                    ),
                    StatusBadge(
                      v.status.label,
                      tone: Tones.vehicle(v.status),
                      dense: true,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
                KeyValueRow(
                  label: 'Employee seats',
                  value:
                      '${seats.passengerCapacity} of ${seats.totalSeats} (1 driver · ${seats.guardSeats} guard)',
                  dense: true,
                ),
                KeyValueRow(
                  label: v.isEv ? 'Battery' : 'Fuel',
                  value: v.batteryOrFuelPercent == null
                      ? '—'
                      : '${v.batteryOrFuelPercent}%',
                  dense: true,
                ),
                KeyValueRow(
                  label: 'Odometer',
                  value: '${Fmt.number(v.odometerKm.round())} km',
                  dense: true,
                ),
                KeyValueRow(
                  label: 'Last inspection',
                  value: Fmt.dateTime(v.lastInspectionAt),
                  dense: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          if (submitted != null)
            ..._outcome(context, day, v, submitted)
          else
            ..._form(context, day, v),
        ],
      ),
    );
  }

  List<Widget> _outcome(
    BuildContext context,
    DriverDay day,
    Vehicle v,
    Inspection i,
  ) {
    final inc = day.data.incident(i.defectIncidentId);
    return [
      if (i.overallStatus == InspectionOutcome.failed) ...[
        InlineBanner(
          tone: StatusTone.danger,
          title: 'Trip start blocked',
          message:
              'Critical failure: ${i.criticalFailures.map((x) => x.label).join(', ')}. Vehicle ${v.vehicleCode} is now in maintenance.'
              '${inc != null ? ' Defect report ${inc.reference} is visible to the Fleet Manager (local demo).' : ''}',
        ),
        const SizedBox(height: AppSpace.md),
        if (inc != null && !inc.replacementRequested)
          BigButton(
            label: 'Request replacement vehicle',
            icon: Icons.swap_horiz_rounded,
            color: AppColors.danger,
            busy: _busy,
            onPressed: () async {
              setState(() => _busy = true);
              final r = await ref
                  .read(servicesProvider)
                  .incidents
                  .requestReplacement(inc.id, Actor.driver(day.driver.id));
              if (!mounted) return;
              setState(() => _busy = false);
              await showResult(this.context, r);
            },
          )
        else if (inc != null)
          const InlineBanner(
            tone: StatusTone.info,
            title: 'Replacement requested',
            message: 'The Fleet Manager will reassign your trip.',
          ),
      ] else if (i.overallStatus == InspectionOutcome.needsReview)
        InlineBanner(
          tone: StatusTone.warning,
          title: 'Passed with notes',
          message:
              'Non-critical: ${i.failures.map((x) => x.label).join(', ')}. You can start trips; the Fleet Manager will review.',
        )
      else
        InlineBanner(
          tone: StatusTone.success,
          title: 'Inspection passed',
          message:
              'Submitted ${Fmt.time(i.submittedAt)}. You can start eligible trips.',
        ),
      const SizedBox(height: AppSpace.md),
      BigButton(
        label: 'Back to Home',
        icon: Icons.home_outlined,
        outlined: true,
        onPressed: () => context.go('/driver/home'),
      ),
      if (i.overallStatus != InspectionOutcome.passed &&
          v.status != VehicleStatus.maintenance) ...[
        const SizedBox(height: AppSpace.sm),
        TextButton.icon(
          onPressed: () => setState(() {
            _submitted = null;
            _newInspection = true;
            _items = InspectionRules.blankChecklist();
          }),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Start a new inspection'),
        ),
      ],
    ];
  }

  List<Widget> _form(BuildContext context, DriverDay day, Vehicle v) {
    final t = Theme.of(context).textTheme;
    final fails = _items.where((i) => i.result == CheckResult.fail).length;
    return [
      if (!day.checkedIn) ...[
        const InlineBanner(
          tone: StatusTone.warning,
          title: 'Check in first',
          message: 'Start your shift before submitting an inspection.',
        ),
        const SizedBox(height: AppSpace.md),
      ],
      if (_errors.isNotEmpty) ...[
        InlineBanner(
          tone: StatusTone.danger,
          title: 'Inspection not submitted',
          messages: _errors,
        ),
        const SizedBox(height: AppSpace.md),
      ],
      const Overline('Safety checklist'),
      for (var idx = 0; idx < _items.length; idx++) ...[
        AppCard(
          padding: const EdgeInsets.all(AppSpace.md),
          borderColor: _items[idx].result == CheckResult.fail
              ? AppColors.danger.withValues(alpha: 0.5)
              : AppColors.border,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(_items[idx].label, style: t.titleSmall)),
                  if (_items[idx].critical)
                    const StatusBadge(
                      'Critical',
                      tone: StatusTone.danger,
                      dense: true,
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              SegmentedButton<CheckResult>(
                segments: const [
                  ButtonSegment(
                    value: CheckResult.pass,
                    label: Text('Pass'),
                    icon: Icon(Icons.check_rounded),
                  ),
                  ButtonSegment(
                    value: CheckResult.fail,
                    label: Text('Fail'),
                    icon: Icon(Icons.close_rounded),
                  ),
                  ButtonSegment(
                    value: CheckResult.notApplicable,
                    label: Text('N/A'),
                  ),
                ],
                selected: {_items[idx].result},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(
                  () =>
                      _items = [..._items]
                        ..[idx] = _items[idx].copyWith(result: s.first),
                ),
              ),
              if (_items[idx].result == CheckResult.fail) ...[
                const SizedBox(height: AppSpace.sm),
                TextField(
                  controller: _note(_items[idx].key),
                  decoration: const InputDecoration(
                    labelText: 'What is wrong? (required)',
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpace.xs),
      ],
      const SizedBox(height: AppSpace.sm),
      TextField(
        controller: _general,
        minLines: 2,
        maxLines: 4,
        decoration: const InputDecoration(
          labelText: 'General notes (optional)',
          alignLabelWithHint: true,
        ),
      ),
      const SizedBox(height: AppSpace.sm),
      OutlinedButton.icon(
        onPressed: () => setState(
          () => _photo = _photo == null
              ? 'local-demo://inspection-photo-${DateTime.now().millisecondsSinceEpoch}.jpg'
              : null,
        ),
        icon: Icon(
          _photo == null
              ? Icons.add_a_photo_outlined
              : Icons.check_circle_outline_rounded,
        ),
        label: Text(
          _photo == null
              ? 'Attach photo (demo)'
              : 'Photo attached (demo) · tap to remove',
        ),
      ),
      const SizedBox(height: 4),
      const SimulatedNote(
        'Photo is a local placeholder only; nothing is uploaded.',
      ),
      const SizedBox(height: AppSpace.lg),
      // Repeat the outcome next to the button so it is visible after tapping.
      if (_errors.isNotEmpty) ...[
        InlineBanner(
          tone: StatusTone.danger,
          title: 'Fix before submitting',
          messages: _errors,
        ),
        const SizedBox(height: AppSpace.md),
      ],
      BigButton(
        label: fails == 0
            ? 'Submit inspection'
            : 'Submit with $fails failure${fails == 1 ? '' : 's'}',
        icon: Icons.send_rounded,
        color: fails == 0 ? AppColors.driverAccent : AppColors.warning,
        busy: _busy,
        onPressed: !day.checkedIn ? null : () => _submit(day.driver.id, v),
      ),
    ];
  }
}
