import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/widgets.dart';
import '../../../domain/models/models.dart';
import '../widgets/fleet_common.dart';
import 'registry/registry_common.dart';

/// Licence validity badge (expired / expiring within 30 days / valid).
Widget licenceBadge(Driver d, DateTime today) {
  if (d.licenceNumber.trim().isEmpty) {
    return const StatusBadge(
      'No licence',
      tone: StatusTone.danger,
      dense: true,
    );
  }
  if (!d.licenceValidOn(today)) {
    return const StatusBadge(
      'Licence expired',
      tone: StatusTone.danger,
      dense: true,
    );
  }
  final exp = d.licenceExpiry;
  if (exp != null && exp.difference(today).inDays <= 30) {
    return StatusBadge(
      'Expires ${Fmt.dateShort(exp)}',
      tone: StatusTone.warning,
      dense: true,
    );
  }
  return const StatusBadge(
    'Licence valid',
    tone: StatusTone.success,
    dense: true,
  );
}

class DriversPage extends ConsumerStatefulWidget {
  const DriversPage({super.key});

  @override
  ConsumerState<DriversPage> createState() => _DriversPageState();
}

class _DriversPageState extends ConsumerState<DriversPage> {
  String _q = '';
  DriverStatus? _status;
  bool? _active = true;
  String? _vehicle;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final t = Theme.of(context).textTheme;
    final pendingReg = data.db.shifts
        .where((s) => s.regularizationStatus == RegularizationStatus.pending)
        .toList();
    final rows = data.drivers.where((d) {
      if (_status != null && d.status != _status) return false;
      if (_active != null && d.active != _active) return false;
      if (_vehicle != null && d.assignedVehicleId != _vehicle) return false;
      final q = _q.toLowerCase();
      return q.isEmpty ||
          d.driverCode.toLowerCase().contains(q) ||
          d.licenceNumber.toLowerCase().contains(q) ||
          d.name.toLowerCase().contains(q);
    }).toList();
    return AdminPage(
      title: 'Drivers',
      subtitle:
          'Duty status, shifts and assignments. Off-duty or unavailable drivers cannot be assigned without an explicit override.',
      actions: [
        FilledButton.icon(
          onPressed: () => context.go('/fleet/drivers/new'),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add driver'),
        ),
      ],
      children: [
        if (pendingReg.isNotEmpty) ...[
          for (final s in pendingReg)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: _RegularizationBanner(shift: s),
            ),
          const SizedBox(height: AppSpace.sm),
        ],
        LayoutBuilder(
          builder: (context, c) {
            final search = AppSearchField(
              hint: 'Search ID, name or licence',
              onChanged: (v) => setState(() => _q = v.trim()),
            );
            final extra = Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<bool?>(
                    isExpanded: true,
                    initialValue: _active,
                    decoration: const InputDecoration(labelText: 'Record'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('All')),
                      DropdownMenuItem(value: true, child: Text('Active')),
                      DropdownMenuItem(
                        value: false,
                        child: Text('Deactivated'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _active = v),
                  ),
                ),
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue: _vehicle,
                    decoration: const InputDecoration(
                      labelText: 'Default vehicle',
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Any')),
                      for (final v in data.vehicles)
                        DropdownMenuItem(
                          value: v.id,
                          child: Text('Vehicle ${v.vehicleCode}'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _vehicle = v),
                  ),
                ),
              ],
            );
            final chips = FilterChipBar<DriverStatus?>(
              options: [null, ...DriverStatus.values],
              selected: _status,
              onSelected: (s) => setState(() => _status = s),
              labelOf: (s) => s?.label ?? 'All',
              countOf: (s) => s == null
                  ? data.drivers.length
                  : data.drivers.where((d) => d.status == s).length,
            );
            if (c.maxWidth < 760) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  search,
                  const SizedBox(height: AppSpace.sm),
                  chips,
                  const SizedBox(height: AppSpace.sm),
                  extra,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SizedBox(width: 300, child: search),
                    const SizedBox(width: AppSpace.md),
                    Expanded(child: chips),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
                extra,
              ],
            );
          },
        ),
        const SizedBox(height: AppSpace.md),
        AdaptiveTable<Driver>(
          rows: rows,
          onRowTap: (d) => context.go('/fleet/drivers/${d.id}'),
          columns: [
            TableCol(
              'Driver',
              (d) => Text('${d.driverCode} · ${d.name}', style: t.titleSmall),
              flex: 3,
            ),
            TableCol(
              'Shift',
              (d) => Text(
                '${Fmt.minutesOfDay(d.shiftStartMinutes)}–${Fmt.minutesOfDay(d.shiftEndMinutes)}',
              ),
              flex: 3,
            ),
            TableCol(
              'Attendance',
              (d) => Text(d.attendanceStatus.label),
              flex: 2,
            ),
            TableCol(
              'Vehicle',
              (d) => Text(
                d.assignedVehicleId == null
                    ? '—'
                    : 'Vehicle ${d.assignedVehicleId}',
              ),
              flex: 2,
            ),
            TableCol('Licence', (d) => licenceBadge(d, data.today), flex: 2),
            TableCol(
              'Trips',
              (d) => Text('${d.completedTripCount}'),
              flex: 1,
              numeric: true,
            ),
            TableCol(
              'Status',
              (d) => d.active
                  ? StatusBadge(
                      d.status.label,
                      tone: Tones.driver(d.status),
                      dense: true,
                    )
                  : const StatusBadge(
                      'Deactivated',
                      tone: StatusTone.neutral,
                      dense: true,
                    ),
              flex: 2,
              numeric: true,
            ),
          ],
          mobileCard: (d) => Row(
            children: [
              InitialsAvatar(
                initials: d.initials,
                size: 38,
                color: AppColors.teal,
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${d.driverCode} · ${d.name}', style: t.titleSmall),
                    Text(
                      '${d.attendanceStatus.label} · ${d.assignedVehicleId == null ? 'No vehicle' : 'Vehicle ${d.assignedVehicleId}'}',
                      style: AppText.muted(context),
                    ),
                  ],
                ),
              ),
              StatusBadge(
                d.status.label,
                tone: Tones.driver(d.status),
                dense: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RegularizationBanner extends ConsumerWidget {
  const _RegularizationBanner({required this.shift});
  final Shift shift;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> decide(bool approve) async {
      final r = await ref
          .read(servicesProvider)
          .driverOps
          .decideRegularization(shift.id, approve);
      if (context.mounted) {
        await showResult(
          context,
          r,
          successMessage: approve
              ? 'Regularization approved'
              : 'Regularization rejected',
        );
      }
    }

    return InlineBanner(
      tone: StatusTone.warning,
      title:
          'Attendance regularization · ${shift.driverId} · ${Fmt.date(shift.shiftDate)}',
      message:
          'Checked in ${Fmt.time(shift.actualCheckIn)} (scheduled ${Fmt.time(shift.scheduledStart)}). Reason: ${shift.regularizationReason ?? '—'}',
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: () => decide(true),
          child: const Text('Approve'),
        ),
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: () => decide(false),
          child: const Text('Reject'),
        ),
      ],
    );
  }
}

class DriverEditPage extends ConsumerStatefulWidget {
  const DriverEditPage({super.key, this.driverId});
  final String? driverId;

  @override
  ConsumerState<DriverEditPage> createState() => _DriverEditPageState();
}

class _DriverEditPageState extends ConsumerState<DriverEditPage> {
  late Driver _d;
  late final bool _isNew = widget.driverId == null;
  bool _missing = false;
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _contact = TextEditingController();
  final _licence = TextEditingController();
  final _notes = TextEditingController();
  final _licNo = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  List<String> _errors = const [];

  @override
  void initState() {
    super.initState();
    final existing = ref.read(dataProvider).driver(widget.driverId);
    if (!_isNew && existing == null) _missing = true;
    _d =
        existing ??
        const Driver(
          id: '',
          driverCode: '',
          name: '',
          fictionalContact: '',
          status: DriverStatus.offDuty,
          shiftStartMinutes: 360,
          shiftEndMinutes: 840,
          attendanceStatus: AttendanceStatus.notCheckedIn,
          completedTripCount: 0,
          safetyChecklistStatus: SafetyChecklistStatus.pending,
        );
    _code.text = _d.driverCode;
    _name.text = _d.name;
    _contact.text = _d.fictionalContact;
    _licence.text = _d.licenceClass;
    _notes.text = _d.notes;
    _licNo.text = _d.licenceNumber;
    _email.text = _d.email;
    _address.text = _d.address;
  }

  @override
  void dispose() {
    for (final c in [
      _code,
      _name,
      _contact,
      _licence,
      _notes,
      _licNo,
      _email,
      _address,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final code = _code.text.trim().toUpperCase();
    final base = _isNew
        ? Driver(
            id: code,
            driverCode: code,
            name: '',
            fictionalContact: '',
            status: _d.status,
            assignedVehicleId: _d.assignedVehicleId,
            shiftStartMinutes: _d.shiftStartMinutes,
            shiftEndMinutes: _d.shiftEndMinutes,
            attendanceStatus: AttendanceStatus.notCheckedIn,
            completedTripCount: 0,
            safetyChecklistStatus: SafetyChecklistStatus.pending,
            licenceExpiry: _d.licenceExpiry,
            gender: _d.gender,
          )
        : _d;
    final draft = base.copyWith(
      licenceNumber: _licNo.text.trim().toUpperCase(),
      email: _email.text.trim(),
      address: _address.text.trim(),
      name: _name.text.trim(),
      fictionalContact: _contact.text.trim(),
      licenceClass: _licence.text.trim(),
      notes: _notes.text.trim(),
    );
    final prev = ref.read(dataProvider).driver(draft.id);
    if (!_isNew &&
        prev != null &&
        prev.status != draft.status &&
        (draft.status == DriverStatus.offDuty ||
            draft.status == DriverStatus.unavailable)) {
      final upcoming = ref
          .read(dataProvider)
          .trips
          .forDriver(draft.id)
          .where((t) => t.actualStart == null && t.status.isUpcoming)
          .toList();
      if (upcoming.isNotEmpty) {
        final ok = await showConfirmDialog(
          context,
          title: 'Set ${draft.driverCode} ${draft.status.label.toLowerCase()}?',
          message:
              '${upcoming.map((t) => t.tripCode).join(', ')} will be flagged "needs attention" for reassignment.',
          confirmLabel: 'Confirm',
          destructive: true,
        );
        if (!ok) return;
      }
    }
    final r = await ref
        .read(servicesProvider)
        .fleet
        .saveDriver(draft, isNew: _isNew);
    if (!mounted) return;
    setState(() => _errors = r.errors);
    if (r.isOk) {
      showToast(context, r.message);
      if (_isNew) context.go('/fleet/drivers/${draft.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    if (_missing) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Driver not found',
        message: 'It may have been removed by a demo reset.',
        actionLabel: 'All drivers',
        onAction: () => context.go('/fleet/drivers'),
      );
    }
    final shift = _isNew ? null : data.todayShift(_d.id);
    final trips = _isNew
        ? <Trip>[]
        : data.trips
              .forDriver(_d.id)
              .where((t) => !t.serviceDate.isBefore(data.today))
              .toList();
    final shifts = _isNew ? <Shift>[] : data.shiftsOf(_d.id);
    final form = PanelCard(
      title: 'Details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_errors.isNotEmpty) ...[
            InlineBanner(
              tone: StatusTone.danger,
              title: 'Not saved',
              messages: _errors,
            ),
            const SizedBox(height: AppSpace.md),
          ],
          FormRow(
            children: [
              TextField(
                controller: _code,
                enabled: _isNew,
                decoration: const InputDecoration(
                  labelText: 'Driver ID',
                  helperText: 'e.g. DR4',
                ),
              ),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Name (fictional)',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          FormRow(
            children: [
              TextField(
                controller: _contact,
                decoration: const InputDecoration(
                  labelText: 'Contact (fictional)',
                ),
              ),
              TextField(
                controller: _licence,
                decoration: const InputDecoration(labelText: 'Licence class'),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          FormRow(
            children: [
              TextField(
                controller: _licNo,
                decoration: const InputDecoration(
                  labelText: 'Licence number (fictional, required)',
                ),
              ),
              DateField(
                label: 'Licence valid until',
                value: _d.licenceExpiry,
                firstDate: DateTime(2020),
                lastDate: DateTime(2045),
                helper: _d.licenceExpiry == null
                    ? 'Optional'
                    : (_d.licenceValidOn(data.today)
                          ? null
                          : 'Expired — this driver cannot be assigned'),
                onChanged: (v) =>
                    setState(() => _d = _d.copyWith(licenceExpiry: () => v)),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          FormRow(
            children: [
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email (fictional)',
                ),
              ),
              DropdownButtonFormField<SelfDeclaredGender>(
                isExpanded: true,
                initialValue: _d.gender,
                decoration: const InputDecoration(
                  labelText: 'Gender (optional, self-declared)',
                  helperText: 'Not used for assignment',
                ),
                items: [
                  for (final g in SelfDeclaredGender.values)
                    DropdownMenuItem(value: g, child: Text(g.label)),
                ],
                onChanged: (g) => setState(() => _d = _d.copyWith(gender: g)),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          TextField(
            controller: _address,
            decoration: const InputDecoration(labelText: 'Address (fictional)'),
          ),
          const SizedBox(height: AppSpace.xs),
          const SimulatedNote(
            'Privacy: national ID (Aadhaar) and age are not collected in this prototype — they are not needed for any workflow.',
            icon: Icons.privacy_tip_outlined,
          ),
          const SizedBox(height: AppSpace.sm),
          FormRow(
            children: [
              DropdownButtonFormField<DriverStatus>(
                isExpanded: true,
                initialValue: _d.status,
                decoration: const InputDecoration(labelText: 'Duty status'),
                items: [
                  for (final s in DriverStatus.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (s) => setState(() => _d = _d.copyWith(status: s)),
              ),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _d.assignedVehicleId,
                decoration: const InputDecoration(labelText: 'Default vehicle'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('None (any pool vehicle)'),
                  ),
                  for (final v in data.vehicles)
                    DropdownMenuItem(
                      value: v.id,
                      child: Text('Vehicle ${v.vehicleCode}'),
                    ),
                ],
                onChanged: (v) => setState(
                  () => _d = _d.copyWith(assignedVehicleId: () => v),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          FormRow(
            children: [
              TimeOfDayField(
                label: 'Shift start',
                minutes: _d.shiftStartMinutes,
                onChanged: (m) =>
                    setState(() => _d = _d.copyWith(shiftStartMinutes: m)),
              ),
              TimeOfDayField(
                label: 'Shift end',
                minutes: _d.shiftEndMinutes,
                onChanged: (m) =>
                    setState(() => _d = _d.copyWith(shiftEndMinutes: m)),
              ),
            ],
          ),
          if (_d.status == DriverStatus.offDuty ||
              _d.status == DriverStatus.unavailable) ...[
            const SizedBox(height: AppSpace.sm),
            const InlineBanner(
              tone: StatusTone.warning,
              title: 'Not assignable',
              message:
                  'Dispatch blocks this driver unless an explicit override with a reason is recorded.',
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _d.active,
            onChanged: _isNew
                ? null
                : (x) => setState(() => _d = _d.copyWith(active: x)),
            title: const Text('Active record'),
            subtitle: const Text(
              'Deactivated drivers keep attendance and trip history but cannot be assigned.',
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          TextField(
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
    final side = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_isNew)
          PanelCard(
            title: 'Today',
            child: Column(
              children: [
                KeyValueRow(
                  label: 'Attendance',
                  value: _d.attendanceStatus.label,
                ),
                KeyValueRow(
                  label: 'Shift status',
                  valueWidget: shift == null
                      ? const Text('No shift record')
                      : StatusBadge(
                          shift.status.label,
                          tone: Tones.shift(shift.status),
                          dense: true,
                        ),
                ),
                KeyValueRow(
                  label: 'Checked in',
                  value: Fmt.time(shift?.actualCheckIn),
                ),
                if (shift?.checkInDeltaMinutes != null)
                  KeyValueRow(
                    label: 'Versus schedule',
                    value: shift!.checkInDeltaMinutes! > 0
                        ? '${shift.checkInDeltaMinutes} min late'
                        : '${-shift.checkInDeltaMinutes!} min early',
                  ),
                KeyValueRow(
                  label: 'Checked out',
                  value: Fmt.time(shift?.actualCheckOut),
                ),
                KeyValueRow(
                  label: 'Safety checklist',
                  value: _d.safetyChecklistStatus.label,
                ),
                KeyValueRow(
                  label: 'Completed trips (lifetime)',
                  value: '${_d.completedTripCount}',
                ),
                if (shift?.regularizationStatus ==
                    RegularizationStatus.pending) ...[
                  const SizedBox(height: AppSpace.xs),
                  _RegularizationBanner(shift: shift!),
                ],
              ],
            ),
          ),
        if (!_isNew) ...[
          const SizedBox(height: AppSpace.md),
          PanelCard(
            title: 'Licence',
            child: Column(
              children: [
                KeyValueRow(
                  label: 'Number',
                  value: _d.licenceNumber.isEmpty ? '—' : _d.licenceNumber,
                ),
                KeyValueRow(
                  label: 'Valid until',
                  value: Fmt.date(_d.licenceExpiry),
                ),
                KeyValueRow(
                  label: 'Status',
                  valueWidget: licenceBadge(_d, data.today),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          ResourceAllocationsPanel(
            type: ResourceType.driver,
            resourceId: _d.id,
          ),
        ],
        const SizedBox(height: AppSpace.md),
        PanelCard(
          title: 'Assigned trips',
          child: trips.isEmpty
              ? Text(
                  'No current or upcoming trips.',
                  style: AppText.muted(context),
                )
              : Column(
                  children: [
                    for (final t in trips)
                      TripRowTile(
                        trip: t,
                        onTap: () => context.go('/fleet/dispatch/trip/${t.id}'),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: AppSpace.md),
        PanelCard(
          title: 'Shift history',
          child: shifts.isEmpty
              ? Text('No shifts recorded.', style: AppText.muted(context))
              : Column(
                  children: [
                    for (final s in shifts.take(7))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(Fmt.weekday(s.shiftDate)),
                        subtitle: Text(
                          '${Fmt.time(s.actualCheckIn)} – ${Fmt.time(s.actualCheckOut)}${s.endException != null ? ' · exception' : ''}',
                        ),
                        trailing: StatusBadge(
                          s.status.label,
                          tone: Tones.shift(s.status),
                          dense: true,
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
    return AdminPage(
      title: _isNew ? 'Add driver' : '${_d.driverCode} · ${_d.name}',
      subtitle: _isNew
          ? 'All contact details are fictional demo data.'
          : 'Default shift ${Fmt.minutesOfDay(_d.shiftStartMinutes)}–${Fmt.minutesOfDay(_d.shiftEndMinutes)}',
      actions: [
        TextButton.icon(
          onPressed: () => context.go('/fleet/drivers'),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Drivers'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(_isNew ? 'Add driver' : 'Save changes'),
        ),
      ],
      children: [ResponsiveSplit(left: form, right: side)],
    );
  }
}
