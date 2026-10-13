import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import '../../domain/rules/geo_rules.dart';
import 'employer_common.dart';

/// Effective office deadline: min(required arrival, shift start, company max),
/// with a short explanation of which limit binds.
(int minutes, String reason) effectiveDeadline({
  required int arrival,
  required int? shiftStart,
  required int companyMax,
}) {
  var m = arrival;
  var why = 'required arrival';
  if (shiftStart != null && shiftStart < m) {
    m = shiftStart;
    why = 'shift start';
  }
  if (companyMax < m) {
    m = companyMax;
    why = 'company maximum arrival';
  }
  return (m, why);
}

/// View/edit an employee, or create one when [employeeId] is null.
class EmployeeDetailPage extends ConsumerStatefulWidget {
  const EmployeeDetailPage({super.key, required this.employeeId});
  final String? employeeId;

  @override
  ConsumerState<EmployeeDetailPage> createState() => _EmployeeDetailPageState();
}

class _EmployeeDetailPageState extends ConsumerState<EmployeeDetailPage> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _shift = TextEditingController();
  final _notes = TextEditingController();
  final _tolerance = TextEditingController();
  String? _pickup;
  String? _destination;
  int _arrival = 540;
  int? _shiftStart;
  int? _shiftEnd;
  TransportPreference _pref = TransportPreference.noPreference;
  SelfDeclaredGender _gender = SelfDeclaredGender.notSpecified;
  bool _guard = false;
  bool _loaded = false;
  bool _busy = false;
  bool _attempted = false;
  List<String> _errors = const [];

  bool get _isNew => widget.employeeId == null;

  @override
  void dispose() {
    for (final c in [
      _code,
      _name,
      _email,
      _phone,
      _shift,
      _notes,
      _tolerance,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _load(Employee? e, Employer employer) {
    if (_loaded) return;
    _loaded = true;
    if (e == null) {
      final data = ref.read(dataProvider);
      _pickup = data.pickupLocations.firstOrNull?.id;
      _destination = data.destinations.firstOrNull?.id;
      final first = employer.shifts.firstOrNull;
      if (first != null) {
        _shiftStart = first.startMinutes;
        _shiftEnd = first.endMinutes;
        _shift.text = first.label;
        _arrival = (first.startMinutes - 15).clamp(
          0,
          employer.maximumArrivalMinutes,
        );
      }
      return;
    }
    _code.text = e.employeeCode;
    _name.text = e.name;
    _email.text = e.fictionalEmail;
    _phone.text = e.fictionalPhone;
    _shift.text = e.shiftLabel;
    _notes.text = e.notes;
    _pickup = e.pickupLocationId;
    _destination = e.destinationId;
    _arrival = e.requiredArrivalMinutes;
    _shiftStart = e.shiftStartMinutes;
    _shiftEnd = e.shiftEndMinutes;
    _tolerance.text = e.pickupToleranceMinutes?.toString() ?? '';
    _pref = e.transportPreference;
    _gender = e.gender;
    _guard = e.guardEscortRequired;
  }

  /// Parsed tolerance: null = company default; throws FormatException text.
  (int? value, String? error) _parseTolerance() {
    final s = _tolerance.text.trim();
    if (s.isEmpty) return (null, null);
    final n = int.tryParse(s);
    if (n == null) return (null, 'Whole minutes only');
    return (n, ToleranceRules.validate(n));
  }

  Employee _draft(Employee? existing, Employer employer) {
    final code = _code.text.trim();
    final shiftLabel = _shift.text.trim().isEmpty
        ? (_shiftStart == null
              ? 'Arrive by ${Fmt.minutesOfDay(_arrival)}'
              : 'Shift ${Fmt.minutesOfDay(_shiftStart!)}')
        : _shift.text.trim();
    final tol = _parseTolerance().$1;
    if (existing == null) {
      return Employee(
        id: code,
        employeeCode: code,
        employerId: employer.id,
        name: _name.text.trim(),
        fictionalEmail: _email.text.trim(),
        fictionalPhone: _phone.text.trim(),
        pickupLocationId: _pickup ?? '',
        destinationId: _destination ?? '',
        requiredArrivalMinutes: _arrival,
        shiftLabel: shiftLabel,
        transportPreference: _pref,
        status: RecordStatus.active,
        optionalDemoPasswordEnabled: false,
        guardEscortRequired: _guard,
        notes: _notes.text.trim(),
        shiftStartMinutes: _shiftStart,
        shiftEndMinutes: _shiftEnd,
        pickupToleranceMinutes: tol,
        gender: _gender,
      );
    }
    return existing.copyWith(
      name: _name.text.trim(),
      fictionalEmail: _email.text.trim(),
      fictionalPhone: _phone.text.trim(),
      pickupLocationId: _pickup,
      destinationId: _destination,
      requiredArrivalMinutes: _arrival,
      shiftLabel: shiftLabel,
      transportPreference: _pref,
      guardEscortRequired: _guard,
      notes: _notes.text.trim(),
      shiftStartMinutes: () => _shiftStart,
      shiftEndMinutes: () => _shiftEnd,
      pickupToleranceMinutes: () => tol,
      gender: _gender,
    );
  }

  Future<void> _save(Employee? existing, Employer employer) async {
    setState(() => _attempted = true);
    if (!_form.currentState!.validate()) return;
    if (_parseTolerance().$2 != null) return;
    final next = _draft(existing, employer);
    setState(() => _busy = true);
    final r = await ref
        .read(servicesProvider)
        .employees
        .save(next, isNew: existing == null);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _errors = r.errors;
    });
    if (r.isOk) {
      showToast(context, r.message);
      if (existing == null) context.go(EmployerPaths.employee(next.id));
    }
  }

  Future<void> _toggleActive(Employee e) async {
    if (e.isActive) {
      final input = await showReasonDialog(
        context,
        title: 'Deactivate ${e.employeeCode}?',
        message:
            '${e.name} will no longer be scheduled and open booking requests will be cancelled. Trip and billing history is preserved.',
        label: 'Reason for deactivation',
        confirmLabel: 'Deactivate',
        destructive: true,
      );
      if (input == null || !mounted) return;
      final r = await ref
          .read(servicesProvider)
          .employees
          .setActive(e.id, false, reason: input.reason);
      if (mounted) await showResult(context, r);
    } else {
      final ok = await showConfirmDialog(
        context,
        title: 'Reactivate ${e.employeeCode}?',
        message: '${e.name} can be scheduled again.',
        confirmLabel: 'Reactivate',
      );
      if (!ok || !mounted) return;
      final r = await ref
          .read(servicesProvider)
          .employees
          .setActive(e.id, true);
      if (mounted) await showResult(context, r);
    }
  }

  ShiftWindow? _matchingShift(Employer employer) => employer.shifts
      .where((s) => s.startMinutes == _shiftStart && s.endMinutes == _shiftEnd)
      .firstOrNull;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final services = ref.read(servicesProvider);
    final employer = data.primaryEmployer;
    final existing = _isNew ? null : data.employee(widget.employeeId);
    if (!_isNew && existing == null) {
      return EmptyState(
        icon: Icons.person_off_outlined,
        title: 'Employee not found',
        message: 'No employee with ID "${widget.employeeId}".',
        actionLabel: 'Back to employees',
        onAction: () => context.go(EmployerPaths.employees),
      );
    }
    _load(existing, employer);
    final t = Theme.of(context).textTheme;
    final arrivalError = _arrival > employer.maximumArrivalMinutes
        ? 'After the company maximum ${Fmt.minutesOfDay(employer.maximumArrivalMinutes)}'
        : null;
    final tolParse = _parseTolerance();
    // Live, domain-sourced validation for schedule/tolerance fields.
    final liveErrors = services.employees
        .validate(_draft(existing, employer), isNew: _isNew)
        .where(
          (e) => RegExp(
            'shift|arrival|tolerance',
            caseSensitive: false,
          ).hasMatch(e),
        )
        .toList();
    final deadline = effectiveDeadline(
      arrival: _arrival,
      shiftStart: _shiftStart,
      companyMax: employer.maximumArrivalMinutes,
    );
    final overnight =
        _shiftStart != null && _shiftEnd != null && _shiftEnd! < _shiftStart!;
    final matching = _matchingShift(employer);
    final pickupLoc = data.location(_pickup);
    final defaultTol = employer.pickupToleranceMinutes;
    final effectiveTol = tolParse.$1 ?? defaultTol;

    final profile = PanelCard(
      title: _isNew ? 'New employee' : 'Profile',
      subtitle: 'Contact details are fictional demo data.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormRow(
            children: [
              TextFormField(
                controller: _code,
                enabled: _isNew,
                decoration: InputDecoration(
                  labelText: 'Employee ID',
                  helperText: _isNew
                      ? 'Unique, e.g. E101'
                      : 'IDs are permanent',
                ),
                validator: (v) => Validators.required(v, 'Employee ID'),
              ),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (v) => Validators.minLength(v, 2, 'Name'),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          FormRow(
            children: [
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(
                  labelText: 'Email (fictional)',
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              TextFormField(
                controller: _phone,
                decoration: const InputDecoration(
                  labelText: 'Phone (fictional)',
                ),
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          FormRow(
            children: [
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Company ID',
                  enabled: false,
                ),
                child: Text(
                  '${employer.code} · ${employer.name}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              DropdownButtonFormField<SelfDeclaredGender>(
                initialValue: _gender,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Gender (optional, self-declared)',
                  helperText: 'Not used by any algorithm',
                ),
                items: [
                  for (final g in SelfDeclaredGender.values)
                    DropdownMenuItem(value: g, child: Text(g.label)),
                ],
                onChanged: (v) => setState(() => _gender = v ?? _gender),
              ),
            ],
          ),
        ],
      ),
    );

    final route = PanelCard(
      title: 'Source & destination',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormRow(
            children: [
              DropdownButtonFormField<String>(
                initialValue: _pickup,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Source / pickup point',
                ),
                items: [
                  for (final l in data.pickupLocations)
                    DropdownMenuItem(
                      value: l.id,
                      child: Text(l.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _pickup = v),
                validator: (v) => v == null ? 'Choose a pickup' : null,
              ),
              DropdownButtonFormField<String>(
                initialValue: _destination,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Destination / office',
                ),
                items: [
                  for (final l in data.destinations)
                    DropdownMenuItem(
                      value: l.id,
                      child: Text(l.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _destination = v),
                validator: (v) => v == null ? 'Choose a destination' : null,
              ),
            ],
          ),
          if (pickupLoc != null) ...[
            const SizedBox(height: AppSpace.sm),
            Container(
              padding: const EdgeInsets.all(AppSpace.sm),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: AppRadius.mdAll,
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.my_location_rounded,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          () {
                            final (lat, lng) = GeoRules.latLngOf(pickupLoc);
                            return 'Source coordinates: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
                          }(),
                          key: const Key('source-coordinates'),
                          style: t.bodySmall!.copyWith(
                            fontFeatures: AppText.tabular,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          DemoLabels.fictionalCoordinates,
                          style: AppText.muted(context),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    final schedule = PanelCard(
      title: 'Shift, arrival & tolerance',
      subtitle: 'Shift times are separate from the office arrival deadline.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String?>(
            key: ValueKey('company-shift-${matching?.id}'),
            initialValue: matching?.id,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Use company shift',
              helperText: employer.shifts.isEmpty
                  ? 'No company shifts configured — enter times below'
                  : 'Or enter custom times below',
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Custom times'),
              ),
              for (final s in employer.shifts)
                DropdownMenuItem<String?>(
                  value: s.id,
                  child: Text(
                    '${s.label} · ${Fmt.minutesOfDay(s.startMinutes)}–${Fmt.minutesOfDay(s.endMinutes)}${s.overnight ? ' (overnight)' : ''}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (id) {
              final s = employer.shifts.where((x) => x.id == id).firstOrNull;
              if (s == null) return;
              setState(() {
                _shiftStart = s.startMinutes;
                _shiftEnd = s.endMinutes;
                _shift.text = s.label;
              });
            },
          ),
          const SizedBox(height: AppSpace.sm),
          FormRow(
            children: [
              TimeOfDayField(
                label: 'Shift start',
                minutes: _shiftStart,
                onChanged: (m) => setState(() => _shiftStart = m),
              ),
              TimeOfDayField(
                label: 'Shift end',
                minutes: _shiftEnd,
                helper: overnight ? 'Overnight — ends the next day' : null,
                onChanged: (m) => setState(() => _shiftEnd = m),
              ),
            ],
          ),
          Row(
            children: [
              if (overnight)
                const StatusBadge(
                  'Overnight shift',
                  tone: StatusTone.info,
                  icon: Icons.nightlight_outlined,
                  dense: true,
                ),
              const Spacer(),
              if (_shiftStart != null || _shiftEnd != null)
                TextButton(
                  onPressed: () => setState(() {
                    _shiftStart = null;
                    _shiftEnd = null;
                  }),
                  child: const Text('Clear shift'),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          FormRow(
            children: [
              TimeOfDayField(
                label: 'Required office arrival',
                minutes: _arrival,
                helper:
                    'Company maximum ${Fmt.minutesOfDay(employer.maximumArrivalMinutes)}',
                errorText: arrivalError,
                onChanged: (m) => setState(() => _arrival = m),
              ),
              TextFormField(
                controller: _shift,
                decoration: const InputDecoration(
                  labelText: 'Shift label',
                  hintText: 'e.g. S2 · General',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Container(
            key: const Key('effective-deadline'),
            padding: const EdgeInsets.all(AppSpace.sm),
            decoration: BoxDecoration(
              color: AppColors.softBlue,
              borderRadius: AppRadius.mdAll,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.flag_outlined,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: Text(
                    'Effective office deadline: ${Fmt.minutesOfDay(deadline.$1)} (${deadline.$2})',
                    style: t.bodySmall!.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          TextFormField(
            key: const Key('tolerance-field'),
            controller: _tolerance,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Pickup/drop tolerance override',
              hintText: 'Blank = company default ±$defaultTol',
              suffixText: 'min',
              helperText:
                  'Applied as ±$effectiveTol min around the planned pickup/drop. Never excuses a missed office deadline.',
              errorText: tolParse.$2,
            ),
          ),
          if (liveErrors.isNotEmpty && (_attempted || _shiftStart != null)) ...[
            const SizedBox(height: AppSpace.sm),
            InlineBanner(
              key: const Key('schedule-errors'),
              tone: StatusTone.danger,
              title: 'Fix the schedule',
              messages: liveErrors,
            ),
          ],
        ],
      ),
    );

    final preferences = PanelCard(
      title: 'Transport preferences',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<TransportPreference>(
            initialValue: _pref,
            decoration: const InputDecoration(labelText: 'Vehicle preference'),
            items: [
              for (final p in TransportPreference.values)
                DropdownMenuItem(value: p, child: Text(p.label)),
            ],
            onChanged: (v) => setState(() => _pref = v ?? _pref),
          ),
          const SizedBox(height: AppSpace.xs),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _guard,
            onChanged: (v) => setState(() => _guard = v),
            title: const Text('Security guard escort required'),
            subtitle: Text(
              employer.securityGuardPolicyEnabled
                  ? 'Explicit admin setting. Reserves a guard seat on this employee\'s trips.'
                  : 'Explicit admin setting. Only applied when the company guard policy is enabled (currently off).',
            ),
          ),
          TextFormField(
            controller: _notes,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Notes',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );

    final saveRow = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_errors.isNotEmpty) ...[
          InlineBanner(
            tone: StatusTone.danger,
            title: 'Not saved',
            messages: _errors,
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => context.go(EmployerPaths.employees),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: AppSpace.xs),
            FilledButton(
              onPressed: _busy ? null : () => _save(existing, employer),
              child: Text(_isNew ? 'Create employee' : 'Save changes'),
            ),
          ],
        ),
      ],
    );

    final form = Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          profile,
          const SizedBox(height: AppSpace.md),
          route,
          const SizedBox(height: AppSpace.md),
          schedule,
          const SizedBox(height: AppSpace.md),
          preferences,
          const SizedBox(height: AppSpace.md),
          saveRow,
        ],
      ),
    );

    if (_isNew) {
      return AdminPage(
        title: 'Add employee',
        subtitle:
            'Creates a single roster record. Use CSV import for bulk changes.',
        actions: [
          TextButton.icon(
            onPressed: () => context.go(EmployerPaths.employees),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Employees'),
          ),
        ],
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: form,
            ),
          ),
        ],
      );
    }

    final e = existing!;
    final trips = data.trips.forEmployee(e.id).reversed.toList();
    final today = data.today;
    final upcoming = trips
        .where((t) => !t.status.isTerminal && !t.serviceDate.isBefore(today))
        .toList()
        .reversed
        .toList();
    final history = trips
        .where((t) => t.status.isTerminal || t.serviceDate.isBefore(today))
        .toList();
    final bookings = data.bookingsOf(e.id);

    return AdminPage(
      title: '${e.employeeCode} · ${e.name}',
      subtitle:
          '${e.shiftLabel} · ${data.locationLabel(e.pickupLocationId)} → ${data.locationLabel(e.destinationId)}',
      actions: [
        TextButton.icon(
          onPressed: () => context.go(EmployerPaths.employees),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Employees'),
        ),
        OutlinedButton.icon(
          style: e.isActive
              ? OutlinedButton.styleFrom(foregroundColor: AppColors.danger)
              : null,
          onPressed: () => _toggleActive(e),
          icon: Icon(
            e.isActive
                ? Icons.person_off_outlined
                : Icons.person_outline_rounded,
          ),
          label: Text(e.isActive ? 'Deactivate' : 'Reactivate'),
        ),
      ],
      children: [
        if (!e.isActive) ...[
          const InlineBanner(
            tone: StatusTone.warning,
            title: 'Inactive employee',
            message:
                'Not schedulable. Historical trips and billing remain intact.',
          ),
          const SizedBox(height: AppSpace.md),
        ],
        ResponsiveColumns(
          left: form,
          right: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PanelCard(
                title: 'Travel preferences',
                subtitle:
                    'Set by the employee in the Employee app · read-only here',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final k in TravelPreferenceKeys.all)
                      KeyValueRow(
                        dense: true,
                        label: TravelPreferenceKeys.label(k),
                        valueWidget: Wrap(
                          spacing: 6,
                          alignment: WrapAlignment.end,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              TravelPreferenceKeys.levels[e
                                  .preference(k)
                                  .clamp(0, 3)],
                              style: t.bodyMedium!.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (!TravelPreferenceKeys.active.contains(k))
                              const StatusBadge('Not active', dense: true),
                          ],
                        ),
                      ),
                    const SizedBox(height: AppSpace.xs),
                    const SimulatedNote(
                      'Soft preferences influence route scoring only; they never override capacity, safety or arrival deadlines. "Pickup point closer to me" has no effect while pickups are at the registered source point.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),
              PanelCard(
                title: 'Current & upcoming assignment',
                child: DividedList(
                  empty: const Text(
                    'No upcoming trips. Requests are assigned by the Fleet Manager.',
                  ),
                  children: [
                    for (final t in upcoming)
                      ListRow(
                        onTap: () => context.go(EmployerPaths.trip(t.id)),
                        title:
                            '${t.tripCode} · ${Fmt.dayLabel(t.serviceDate, data.now)} ${Fmt.time(t.scheduledStart)}',
                        subtitle: t.isAssigned
                            ? '${data.driver(t.assignedDriverId)?.name} · Vehicle ${t.assignedVehicleId}'
                            : 'Awaiting driver & vehicle',
                        trailing: TripStatusBadge(t.status, dense: true),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),
              PanelCard(
                title: 'Booking requests',
                child: DividedList(
                  empty: const Text('No booking requests.'),
                  children: [
                    for (final b in bookings.take(5))
                      ListRow(
                        title:
                            '${b.reference} · ${Fmt.dateShort(b.requestedDate)}',
                        subtitle:
                            'Arrive by ${Fmt.minutesOfDay(b.requestedArrivalMinutes)}${b.decisionReason != null ? ' · ${b.decisionReason}' : ''}',
                        trailing: StatusBadge(
                          b.status.label,
                          tone: Tones.booking(b.status),
                          dense: true,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),
              PanelCard(
                title: 'Trip history',
                subtitle:
                    '${history.length} past trip${history.length == 1 ? '' : 's'} (kept after deactivation)',
                child: DividedList(
                  empty: const Text('No past trips.'),
                  children: [
                    for (final t in history.take(8))
                      ListRow(
                        onTap: () => context.go(EmployerPaths.trip(t.id)),
                        title: '${t.tripCode} · ${Fmt.date(t.serviceDate)}',
                        subtitle:
                            '${data.trips.passengerState(t, e.id).label}${t.distanceKm != null ? ' · ${Fmt.km(t.distanceKm)}' : ''}',
                        trailing: TripStatusBadge(t.status, dense: true),
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
