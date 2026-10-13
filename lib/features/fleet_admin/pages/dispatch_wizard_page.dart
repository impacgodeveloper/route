import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/widgets.dart';
import '../../../domain/models/models.dart';
import '../../../domain/rules/capacity_rules.dart';
import '../widgets/fleet_common.dart';
import '../widgets/plan_preview.dart';

/// Create-trip wizard with live validation (capacity, availability, time
/// windows, policy) and a planned route preview.
class DispatchWizardPage extends ConsumerStatefulWidget {
  const DispatchWizardPage({
    super.key,
    this.employeeIds = const [],
    this.bookingIds = const [],
    this.date,
  });

  final List<String> employeeIds;
  final List<String> bookingIds;
  final DateTime? date;

  @override
  ConsumerState<DispatchWizardPage> createState() => _DispatchWizardPageState();
}

class _DispatchWizardPageState extends ConsumerState<DispatchWizardPage> {
  late String _employerId;
  late DateTime _date;
  late final Set<String> _employees = {...widget.employeeIds};
  int? _startMinutes;
  bool _guard = false;
  RouteVariant _variant = RouteVariant.internalRoads;
  String? _driverId;
  String? _vehicleId;
  bool _override = false;
  final _overrideReason = TextEditingController();
  final _guardRef = TextEditingController();
  final _instructions = TextEditingController();
  String _search = '';
  bool _busy = false;
  List<String> _saveErrors = const [];

  @override
  void initState() {
    super.initState();
    final data = ref.read(dataProvider);
    _employerId = data.primaryEmployer.id;
    _date = widget.date ?? data.today.add(const Duration(days: 1));
  }

  @override
  void dispose() {
    _overrideReason.dispose();
    _guardRef.dispose();
    _instructions.dispose();
    super.dispose();
  }

  AssignmentRequest _request() => AssignmentRequest(
    employerId: _employerId,
    serviceDate: _date,
    employeeIds: _employees.toList(),
    scheduledStart: _startMinutes == null
        ? null
        : atMinutes(_date, _startMinutes!),
    driverId: _driverId,
    vehicleId: _vehicleId,
    guardRequired: _guard,
    variant: _variant,
    instructions: _instructions.text.trim(),
    allowDriverOverride: _override,
    overrideReason: _override ? _overrideReason.text : null,
    bookingIds: widget.bookingIds,
    guardReference: _guardRef.text,
  );

  Future<void> _save() async {
    setState(() => _busy = true);
    final r = await ref.read(servicesProvider).assignments.commit(_request());
    if (!mounted) return;
    setState(() {
      _busy = false;
      _saveErrors = r.errors;
    });
    if (r.isOk) {
      await showResult(
        context,
        r,
        successMessage: '${r.valueOrNull!.tripCode} saved',
      );
      if (mounted) context.go('/fleet/dispatch/trip/${r.valueOrNull!.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final s = ref.read(servicesProvider).assignments;
    final t = Theme.of(context).textTheme;
    final req = _request();
    final validation = _employees.isEmpty ? null : s.validate(req);
    final vehicleOpts = _employees.isEmpty
        ? <(Vehicle, List<String>)>[]
        : s.vehicleOptions(req);
    final driverOpts = _employees.isEmpty
        ? <(Driver, List<String>)>[]
        : s.driverOptions(req);
    final capacityProblem =
        validation?.errors.any((e) => e.startsWith('Over capacity')) ?? false;
    final suggestions = capacityProblem
        ? vehicleOpts
              .where(
                (o) =>
                    o.$2.isEmpty &&
                    CapacityRules.passengerCapacity(
                          o.$1,
                          guardRequired: _guard,
                        ) >=
                        _employees.length,
              )
              .map((o) => o.$1)
              .toList()
        : <Vehicle>[];
    final selectedDriver = data.driver(_driverId);
    final needsOverride =
        selectedDriver != null &&
        (selectedDriver.status == DriverStatus.offDuty ||
            selectedDriver.status == DriverStatus.unavailable);

    final employees =
        data
            .employeesOf(_employerId)
            .where((e) => e.isActive)
            .where(
              (e) =>
                  _search.isEmpty ||
                  e.employeeCode.toLowerCase() == _search.toLowerCase() ||
                  e.name.toLowerCase().contains(_search.toLowerCase()) ||
                  e.pickupLocationId.toLowerCase() == _search.toLowerCase() ||
                  e.destinationId.toLowerCase() == _search.toLowerCase(),
            )
            .toList()
          ..sort((a, b) {
            final sa = _employees.contains(a.id) ? 0 : 1;
            final sb = _employees.contains(b.id) ? 0 : 1;
            if (sa != sb) return sa - sb;
            return int.parse(
              a.employeeCode.replaceAll(RegExp(r'\D'), '').padLeft(1, '0'),
            ).compareTo(
              int.parse(
                b.employeeCode.replaceAll(RegExp(r'\D'), '').padLeft(1, '0'),
              ),
            );
          });

    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelCard(
          title: '1 · When & who',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FormRow(
                children: [
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _employerId,
                    decoration: const InputDecoration(labelText: 'Employer'),
                    items: [
                      for (final e in data.employers)
                        DropdownMenuItem(value: e.id, child: Text(e.name)),
                    ],
                    onChanged: (v) => setState(() {
                      _employerId = v ?? _employerId;
                      _employees.clear();
                    }),
                  ),
                  DateField(
                    label: 'Service date',
                    value: _date,
                    firstDate: data.today,
                    lastDate: data.today.add(const Duration(days: 30)),
                    onChanged: (d) => setState(() => _date = d),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Employees (${_employees.length} selected)',
                      style: t.titleSmall,
                    ),
                  ),
                  if (_employees.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(_employees.clear),
                      child: const Text('Clear'),
                    ),
                ],
              ),
              if (_employees.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final id in _employees)
                      InputChip(
                        label: Text(id),
                        onDeleted: () => setState(() => _employees.remove(id)),
                      ),
                  ],
                ),
              const SizedBox(height: AppSpace.xs),
              AppSearchField(
                hint: 'Search by ID, name, pickup (PK01) or office (G1)',
                onChanged: (v) => setState(() => _search = v.trim()),
              ),
              const SizedBox(height: AppSpace.xs),
              Container(
                height: 260,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: AppRadius.mdAll,
                ),
                child: employees.isEmpty
                    ? const EmptyState(
                        icon: Icons.person_search_outlined,
                        title: 'No matching employees',
                        message: 'Only active employees can be scheduled.',
                        compact: true,
                      )
                    : ListView.builder(
                        itemCount: employees.length,
                        itemBuilder: (c, i) {
                          final e = employees[i];
                          return CheckboxListTile(
                            dense: true,
                            value: _employees.contains(e.id),
                            onChanged: (v) => setState(
                              () => v == true
                                  ? _employees.add(e.id)
                                  : _employees.remove(e.id),
                            ),
                            title: Text('${e.employeeCode} · ${e.name}'),
                            subtitle: Text(
                              '${e.pickupLocationId} → ${e.destinationId} · arrive by ${Fmt.minutesOfDay(e.requiredArrivalMinutes)}',
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        PanelCard(
          title: '2 · Schedule & policy',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FormRow(
                children: [
                  TimeOfDayField(
                    label: 'Start time (optional)',
                    minutes: _startMinutes,
                    helper: _startMinutes == null
                        ? 'Auto: planned backwards from arrival deadlines'
                        : null,
                    onChanged: (m) => setState(() => _startMinutes = m),
                  ),
                  DropdownButtonFormField<RouteVariant>(
                    isExpanded: true,
                    initialValue: _variant,
                    decoration: const InputDecoration(labelText: 'Route'),
                    items: [
                      for (final v in RouteVariant.values)
                        DropdownMenuItem(value: v, child: Text(v.label)),
                    ],
                    onChanged: (v) => setState(() => _variant = v ?? _variant),
                  ),
                ],
              ),
              if (_startMinutes != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() => _startMinutes = null),
                    child: const Text('Use automatic start time'),
                  ),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _guard,
                onChanged: (v) => setState(() => _guard = v),
                title: const Text('Security guard required'),
                subtitle: const Text(
                  'Explicit policy only — reserves one seat, reducing employee capacity.',
                ),
              ),
              if (_guard ||
                  (data.vehicle(_vehicleId)?.requiresSecurityGuard ??
                      false)) ...[
                TextField(
                  controller: _guardRef,
                  decoration: InputDecoration(
                    labelText: 'Security guard reference',
                    helperText:
                        data.vehicle(_vehicleId)?.securityGuardAssigned ?? false
                        ? 'Vehicle already has an assigned guard — optional.'
                        : 'Required: guard name or ID (hard rule).',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpace.sm),
              ],
              TextField(
                controller: _instructions,
                decoration: const InputDecoration(
                  labelText: 'Driver instructions (optional)',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        PanelCard(
          title: '3 · Driver & vehicle',
          subtitle:
              'Blocked options show why. Without both, the trip is saved as planned.',
          child: _employees.isEmpty
              ? const EmptyState(
                  icon: Icons.groups_outlined,
                  title: 'Select employees first',
                  message:
                      'Availability is checked against the planned time window.',
                  compact: true,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Vehicle', style: t.labelMedium),
                    const SizedBox(height: AppSpace.xs),
                    for (final (v, errs) in vehicleOpts)
                      _OptionTile(
                        selected: _vehicleId == v.id,
                        title: vehicleShort(v),
                        subtitle:
                            '${CapacityRules.breakdown(v, guardRequired: _guard)} · ${v.status.label}',
                        problems: errs,
                        onTap: () => setState(
                          () => _vehicleId = _vehicleId == v.id ? null : v.id,
                        ),
                      ),
                    const SizedBox(height: AppSpace.sm),
                    Text('Driver', style: t.labelMedium),
                    const SizedBox(height: AppSpace.xs),
                    for (final (d, errs) in driverOpts)
                      _OptionTile(
                        selected: _driverId == d.id,
                        title: driverShort(d),
                        subtitle:
                            '${d.status.label} · shift ${Fmt.minutesOfDay(d.shiftStartMinutes)}–${Fmt.minutesOfDay(d.shiftEndMinutes)}',
                        problems: errs,
                        onTap: () => setState(
                          () => _driverId = _driverId == d.id ? null : d.id,
                        ),
                      ),
                    if (needsOverride) ...[
                      const SizedBox(height: AppSpace.sm),
                      InlineBanner(
                        tone: StatusTone.warning,
                        title:
                            '${selectedDriver.driverCode} is ${selectedDriver.status.label.toLowerCase()}',
                        message:
                            'Off-duty or unavailable drivers can only be assigned with an explicit, reasoned override.',
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _override,
                        onChanged: (v) =>
                            setState(() => _override = v ?? false),
                        title: const Text('Override with reason'),
                      ),
                      if (_override)
                        TextField(
                          controller: _overrideReason,
                          decoration: const InputDecoration(
                            labelText: 'Override reason (min 5 characters)',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );

    final side = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelCard(
          title: 'Validation',
          child: validation == null
              ? Text(
                  'Select employees to validate the assignment.',
                  style: AppText.muted(context),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (validation.ok)
                      const InlineBanner(
                        tone: StatusTone.success,
                        title: 'All hard constraints pass',
                      )
                    else
                      InlineBanner(
                        tone: StatusTone.danger,
                        title:
                            '${validation.errors.length} issue${validation.errors.length == 1 ? '' : 's'} to fix',
                        messages: validation.errors,
                      ),
                    if (suggestions.isNotEmpty) ...[
                      const SizedBox(height: AppSpace.xs),
                      InlineBanner(
                        tone: StatusTone.info,
                        title:
                            'Vehicles that fit ${_employees.length} employees',
                        actions: [
                          for (final v in suggestions)
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 40),
                              ),
                              onPressed: () =>
                                  setState(() => _vehicleId = v.id),
                              child: Text(
                                'Use Vehicle ${v.vehicleCode} (${CapacityRules.passengerCapacity(v, guardRequired: _guard)} seats)',
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (validation.warnings.isNotEmpty) ...[
                      const SizedBox(height: AppSpace.xs),
                      InlineBanner(
                        tone: StatusTone.warning,
                        title: 'Warnings',
                        messages: validation.warnings,
                      ),
                    ],
                    if (validation.seats != null) ...[
                      const SizedBox(height: AppSpace.sm),
                      KeyValueRow(
                        label: 'Seats',
                        value: validation.seats.toString(),
                      ),
                    ],
                  ],
                ),
        ),
        if (validation?.plan != null) ...[
          const SizedBox(height: AppSpace.md),
          PanelCard(
            title: 'Planned route',
            subtitle:
                '${Fmt.km(validation!.plan!.distanceKm)} · ${Fmt.duration(validation.plan!.durationMinutes)} · ${validation.plan!.variant.label}',
            child: PlanPreview(stops: validation.plan!.stops),
          ),
        ],
        if (_saveErrors.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          InlineBanner(
            tone: StatusTone.danger,
            title: 'Not saved',
            messages: _saveErrors,
          ),
        ],
        const SizedBox(height: AppSpace.md),
        FilledButton.icon(
          onPressed: _busy || validation == null || !validation.ok
              ? null
              : _save,
          icon: const Icon(Icons.check_rounded),
          label: Text(
            _driverId != null && _vehicleId != null
                ? 'Save & assign trip'
                : 'Save as planned trip',
          ),
        ),
      ],
    );

    return AdminPage(
      title: 'New trip',
      subtitle: widget.bookingIds.isEmpty
          ? 'Group employees into a trip and assign a driver and vehicle.'
          : 'Fulfils request${widget.bookingIds.length == 1 ? '' : 's'} ${widget.bookingIds.join(', ')} (requested pickup/destination/arrival are used).',
      actions: [
        TextButton.icon(
          onPressed: () => context.go('/fleet/dispatch'),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Back to dispatch'),
        ),
      ],
      children: [
        ResponsiveSplit(left: form, right: side, leftFlex: 3, rightFlex: 2),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.problems,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final List<String> problems;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final blocked = problems.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpace.sm),
        borderColor: selected ? AppColors.primary : AppColors.border,
        color: selected ? AppColors.softBlue : AppColors.white,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected ? AppColors.primary : AppColors.textMuted,
              size: 20,
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.titleSmall),
                  Text(
                    subtitle,
                    style: t.bodySmall!.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  for (final p in problems)
                    Text(
                      p,
                      style: t.bodySmall!.copyWith(color: AppColors.danger),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.xs),
            StatusBadge(
              blocked ? 'Blocked' : 'Available',
              tone: blocked ? StatusTone.danger : StatusTone.success,
              dense: true,
            ),
          ],
        ),
      ),
    );
  }
}
