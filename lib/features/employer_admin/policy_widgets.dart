import 'package:flutter/material.dart';

import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import '../../domain/rules/tolerance_rules.dart';
import 'employer_common.dart';

/// Company default pickup/drop tolerance (client reference ±7 min).
class ToleranceCard extends StatelessWidget {
  const ToleranceCard({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      title: 'Pickup/drop tolerance',
      subtitle: 'Company default; employees may have an individual override.',
      trailing: value == ToleranceRules.clientReferenceDefault
          ? const StatusBadge(
              'Client reference',
              tone: StatusTone.info,
              dense: true,
            )
          : TextButton(
              onPressed: () => onChanged(ToleranceRules.clientReferenceDefault),
              child: const Text('Use ±7 reference'),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WeightSlider(
            key: const Key('company-tolerance'),
            label: 'Default tolerance (± minutes)',
            value: value.toDouble(),
            max: ToleranceRules.maxMinutes.toDouble(),
            divisions: ToleranceRules.maxMinutes,
            onChanged: (v) => onChanged(v.round()),
          ),
          const SimulatedNote(
            'Tolerance is the ± window communicated around each planned pickup/drop time. '
            'It is different from vehicle waiting time at a stop and from the route safety buffer before the office deadline, '
            'and it never excuses a missed office arrival deadline.',
            icon: Icons.info_outline_rounded,
          ),
        ],
      ),
    );
  }
}

/// Add / edit / remove company shift windows (overnight allowed).
class ShiftEditor extends StatelessWidget {
  const ShiftEditor({
    super.key,
    required this.shifts,
    required this.employees,
    required this.onChanged,
  });
  final List<ShiftWindow> shifts;
  final List<Employee> employees;
  final ValueChanged<List<ShiftWindow>> onChanged;

  int _users(ShiftWindow s) => employees
      .where(
        (e) =>
            e.shiftStartMinutes == s.startMinutes &&
            e.shiftEndMinutes == s.endMinutes,
      )
      .length;

  Future<void> _edit(BuildContext context, ShiftWindow? existing) async {
    final result = await showDialog<ShiftWindow>(
      context: context,
      builder: (c) => ShiftDialog(
        existing: existing,
        others: shifts.where((s) => s.id != existing?.id).toList(),
      ),
    );
    if (result == null) return;
    onChanged(
      existing == null
          ? [...shifts, result]
          : [for (final s in shifts) s.id == result.id ? result : s],
    );
  }

  Future<void> _remove(BuildContext context, ShiftWindow s) async {
    final n = _users(s);
    final ok = await showConfirmDialog(
      context,
      title: 'Remove ${s.label}?',
      message: n == 0
          ? 'No active employee uses this shift. The removal is saved with the other policy changes.'
          : '$n active employee(s) use these times. They keep their saved times as custom shifts.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (ok) onChanged(shifts.where((x) => x.id != s.id).toList());
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final sorted = [...shifts]
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    return PanelCard(
      title: 'Company shift windows',
      subtitle:
          '${shifts.length} configured · offered as "Use company shift" on the employee form',
      trailing: TextButton.icon(
        onPressed: () => _edit(context, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add shift'),
      ),
      child: DividedList(
        empty: const Text(
          'No company shifts yet. Employees can still have custom shift times.',
        ),
        children: [
          for (final s in sorted)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  IconTile(
                    icon: s.overnight
                        ? Icons.nightlight_outlined
                        : Icons.schedule_outlined,
                    size: 34,
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.label, style: t.titleSmall),
                        Text(
                          '${Fmt.minutesOfDay(s.startMinutes)} – ${Fmt.minutesOfDay(s.endMinutes)}${s.overnight ? ' (next day)' : ''} · ${Fmt.duration(s.durationMinutes)} · ${_users(s)} employees',
                          style: AppText.muted(context),
                        ),
                        if (s.overnight) ...[
                          const SizedBox(height: 4),
                          const StatusBadge(
                            'Overnight',
                            tone: StatusTone.info,
                            dense: true,
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit ${s.label}',
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: () => _edit(context, s),
                  ),
                  IconButton(
                    tooltip: 'Remove ${s.label}',
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    onPressed: () => _remove(context, s),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class ShiftDialog extends StatefulWidget {
  const ShiftDialog({super.key, this.existing, required this.others});
  final ShiftWindow? existing;
  final List<ShiftWindow> others;

  @override
  State<ShiftDialog> createState() => _ShiftDialogState();
}

class _ShiftDialogState extends State<ShiftDialog> {
  late final _label = TextEditingController(text: widget.existing?.label ?? '');
  late int _start = widget.existing?.startMinutes ?? 540;
  late int _end = widget.existing?.endMinutes ?? 1080;
  List<String> _errors = const [];

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  void _save() {
    final label = _label.text.trim();
    final duration = _end < _start ? 1440 - _start + _end : _end - _start;
    final errors = <String>[
      if (label.isEmpty) 'Enter a label.',
      if (widget.others.any(
        (s) => s.label.toLowerCase() == label.toLowerCase(),
      ))
        'Another shift already uses this label.',
      if (_start == _end) 'Start and end cannot be equal.',
      if (_start != _end && duration > 16 * 60)
        'A shift cannot be longer than 16 hours.',
    ];
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    var id = widget.existing?.id;
    if (id == null) {
      final ids = widget.others.map((s) => s.id).toSet();
      var n = widget.others.length + 1;
      while (ids.contains('S$n')) {
        n++;
      }
      id = 'S$n';
    }
    Navigator.pop(
      context,
      ShiftWindow(id: id, label: label, startMinutes: _start, endMinutes: _end),
    );
  }

  @override
  Widget build(BuildContext context) {
    final overnight = _end < _start;
    return AlertDialog(
      title: Text(
        widget.existing == null
            ? 'Add shift window'
            : 'Edit ${widget.existing!.label}',
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, minWidth: 280),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_errors.isNotEmpty) ...[
                InlineBanner(
                  tone: StatusTone.danger,
                  title: 'Check the shift',
                  messages: _errors,
                ),
                const SizedBox(height: AppSpace.sm),
              ],
              TextField(
                key: const Key('shift-label'),
                controller: _label,
                decoration: const InputDecoration(
                  labelText: 'Label',
                  hintText: 'e.g. S5 · Night',
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              TimeOfDayField(
                label: 'Start',
                minutes: _start,
                onChanged: (m) => setState(() => _start = m),
              ),
              const SizedBox(height: AppSpace.sm),
              TimeOfDayField(
                label: 'End',
                minutes: _end,
                helper: overnight ? 'Overnight — ends the next day' : null,
                onChanged: (m) => setState(() => _end = m),
              ),
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
          onPressed: _save,
          child: Text(widget.existing == null ? 'Add' : 'Done'),
        ),
      ],
    );
  }
}
