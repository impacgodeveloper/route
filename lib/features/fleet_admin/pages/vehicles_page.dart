import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/widgets.dart';
import '../../../domain/models/models.dart';
import '../../../domain/rules/capacity_rules.dart';
import '../widgets/fleet_common.dart';
import 'registry/registry_common.dart';

class VehiclesPage extends ConsumerStatefulWidget {
  const VehiclesPage({super.key});

  @override
  ConsumerState<VehiclesPage> createState() => _VehiclesPageState();
}

class _VehiclesPageState extends ConsumerState<VehiclesPage> {
  String _q = '';
  VehicleStatus? _status;
  Propulsion? _prop;
  FuelType? _fuel;
  int? _minSeats;
  String? _driver;
  bool? _active = true;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final t = Theme.of(context).textTheme;
    final rows = data.vehicles.where((v) {
      if (_status != null && v.status != _status) return false;
      if (_prop != null && v.propulsion != _prop) return false;
      if (_fuel != null && v.effectiveFuelType != _fuel) return false;
      if (_minSeats != null &&
          CapacityRules.passengerCapacity(v) < _minSeats!) {
        return false;
      }
      if (_driver != null && v.assignedDriverId != _driver) return false;
      if (_active != null && v.active != _active) return false;
      if (_q.isEmpty) return true;
      final q = _q.toLowerCase();
      return v.vehicleCode.toLowerCase().contains(q) ||
          v.fictionalRegistration.toLowerCase().contains(q) ||
          v.rcNumber.toLowerCase().contains(q) ||
          v.engineNumber.toLowerCase().contains(q) ||
          v.model.toLowerCase().contains(q) ||
          v.type.label.toLowerCase().contains(q);
    }).toList();
    return AdminPage(
      title: 'Vehicles',
      subtitle:
          'Shared, non-dedicated pool. Seat convention: total seats include the driver; employee capacity = total − driver − guard seats.',
      actions: [
        FilledButton.icon(
          onPressed: () => context.go('/fleet/vehicles/new'),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add vehicle'),
        ),
      ],
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final search = AppSearchField(
              hint: 'Search ID, registration, model',
              onChanged: (v) => setState(() => _q = v.trim()),
            );
            final filters = Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<VehicleStatus?>(
                    isExpanded: true,
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Any status'),
                      ),
                      for (final s in VehicleStatus.values)
                        DropdownMenuItem(value: s, child: Text(s.label)),
                    ],
                    onChanged: (v) => setState(() => _status = v),
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<Propulsion?>(
                    isExpanded: true,
                    initialValue: _prop,
                    decoration: const InputDecoration(labelText: 'Propulsion'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Any')),
                      for (final p in Propulsion.values)
                        DropdownMenuItem(value: p, child: Text(p.label)),
                    ],
                    onChanged: (v) => setState(() => _prop = v),
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<FuelType?>(
                    isExpanded: true,
                    initialValue: _fuel,
                    decoration: const InputDecoration(labelText: 'Fuel type'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Any')),
                      for (final f in FuelType.values)
                        DropdownMenuItem(value: f, child: Text(f.label)),
                    ],
                    onChanged: (v) => setState(() => _fuel = v),
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<int?>(
                    isExpanded: true,
                    initialValue: _minSeats,
                    decoration: const InputDecoration(
                      labelText: 'Employee seats',
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Any')),
                      for (final n in [3, 4, 5, 6])
                        DropdownMenuItem(value: n, child: Text('$n or more')),
                    ],
                    onChanged: (v) => setState(() => _minSeats = v),
                  ),
                ),
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue: _driver,
                    decoration: const InputDecoration(
                      labelText: 'Assigned driver',
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Any')),
                      for (final d in data.drivers)
                        DropdownMenuItem(
                          value: d.id,
                          child: Text(
                            '${d.driverCode} ${d.name}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _driver = v),
                  ),
                ),
                SizedBox(
                  width: 160,
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
              ],
            );
            if (c.maxWidth < 760) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  search,
                  const SizedBox(height: AppSpace.sm),
                  filters,
                ],
              );
            }
            return Row(
              children: [
                SizedBox(width: 320, child: search),
                const SizedBox(width: AppSpace.md),
                Expanded(child: filters),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpace.md),
        AdaptiveTable<Vehicle>(
          rows: rows,
          onRowTap: (v) => context.go('/fleet/vehicles/${v.id}'),
          empty: EmptyState(
            icon: Icons.search_off_rounded,
            title: 'No vehicles match',
            message: 'Clear filters to see the whole fleet.',
            actionLabel: 'Clear filters',
            onAction: () => setState(() {
              _status = null;
              _prop = null;
              _fuel = null;
              _minSeats = null;
              _driver = null;
              _active = null;
            }),
          ),
          columns: [
            TableCol(
              'Vehicle',
              (v) => Text('Vehicle ${v.vehicleCode}', style: t.titleSmall),
              flex: 2,
            ),
            TableCol(
              'Type',
              (v) => Text(
                '${v.effectiveFuelType.label} ${v.type.label} · ${v.luxuryClass.label}',
              ),
              flex: 3,
            ),
            TableCol(
              'Registration',
              (v) => Text(v.fictionalRegistration),
              flex: 3,
            ),
            TableCol(
              'Seats',
              (v) => Text(
                '${v.totalSeats} / ${CapacityRules.passengerCapacity(v)} emp.',
              ),
              flex: 2,
            ),
            TableCol(
              'Energy',
              (v) => Text(
                v.batteryOrFuelPercent == null
                    ? '—'
                    : '${v.batteryOrFuelPercent}%',
              ),
              flex: 1,
              numeric: true,
            ),
            TableCol(
              'Odometer',
              (v) => Text('${Fmt.number(v.odometerKm.round())} km'),
              flex: 2,
              numeric: true,
            ),
            TableCol(
              'Status',
              (v) => v.active
                  ? StatusBadge(
                      v.status.label,
                      tone: Tones.vehicle(v.status),
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
          mobileCard: (v) => Row(
            children: [
              IconTile(
                icon: v.isEv
                    ? Icons.electric_car_outlined
                    : Icons.directions_car_outlined,
                color: v.isEv ? AppColors.teal : AppColors.deepNavy,
                size: 36,
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(vehicleShort(v), style: t.titleSmall),
                    Text(
                      '${v.fictionalRegistration} · ${CapacityRules.passengerCapacity(v)} employee seats',
                      style: AppText.muted(context),
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
        ),
      ],
    );
  }
}

class VehicleEditPage extends ConsumerStatefulWidget {
  const VehicleEditPage({super.key, this.vehicleId});
  final String? vehicleId;

  @override
  ConsumerState<VehicleEditPage> createState() => _VehicleEditPageState();
}

class _VehicleEditPageState extends ConsumerState<VehicleEditPage> {
  late Vehicle _v;
  late final bool _isNew;
  bool _missing = false;
  final _code = TextEditingController();
  final _reg = TextEditingController();
  final _model = TextEditingController();
  final _odo = TextEditingController();
  final _energy = TextEditingController();
  final _notes = TextEditingController();
  final _rc = TextEditingController();
  final _engine = TextEditingController();
  final _color = TextEditingController();
  List<String> _errors = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final existing = ref.read(dataProvider).vehicle(widget.vehicleId);
    _isNew = widget.vehicleId == null;
    if (!_isNew && existing == null) _missing = true;
    _v =
        existing ??
        const Vehicle(
          id: '',
          vehicleCode: '',
          fictionalRegistration: '',
          type: VehicleType.sedan,
          propulsion: Propulsion.ev,
          totalSeats: 4,
          luxuryClass: LuxuryClass.standard,
          status: VehicleStatus.available,
          odometerKm: 0,
          batteryOrFuelPercent: 100,
          homeParkingId: 'P1',
        );
    _code.text = _v.vehicleCode;
    _reg.text = _v.fictionalRegistration;
    _model.text = _v.model;
    _odo.text = _v.odometerKm.toStringAsFixed(0);
    _energy.text = _v.batteryOrFuelPercent?.toString() ?? '';
    _notes.text = _v.notes;
    _rc.text = _v.rcNumber;
    _engine.text = _v.engineNumber;
    _color.text = _v.color;
  }

  @override
  void dispose() {
    for (final c in [
      _code,
      _reg,
      _model,
      _odo,
      _energy,
      _notes,
      _rc,
      _engine,
      _color,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Vehicle _draft() {
    final code = _code.text.trim().toUpperCase();
    final base = _isNew
        ? Vehicle(
            id: code,
            vehicleCode: code,
            fictionalRegistration: _v.fictionalRegistration,
            type: _v.type,
            propulsion: _v.propulsion,
            totalSeats: _v.totalSeats,
            luxuryClass: _v.luxuryClass,
            status: _v.status,
            odometerKm: _v.odometerKm,
            batteryOrFuelPercent: _v.batteryOrFuelPercent,
            assignedEmployerId: _v.assignedEmployerId,
            requiresSecurityGuard: _v.requiresSecurityGuard,
            securityGuardAssigned: _v.securityGuardAssigned,
            homeParkingId: _v.homeParkingId,
            fuelType: _v.fuelType,
            active: _v.active,
          )
        : _v;
    return base.copyWith(
      rcNumber: _rc.text.trim(),
      engineNumber: _engine.text.trim(),
      color: _color.text.trim(),
      fictionalRegistration: _reg.text.trim(),
      model: _model.text.trim(),
      odometerKm: double.tryParse(_odo.text.trim()) ?? -1,
      batteryOrFuelPercent: () => int.tryParse(_energy.text.trim()),
      notes: _notes.text.trim(),
    );
  }

  Future<void> _save() async {
    final draft = _draft();
    final prev = ref.read(dataProvider).vehicle(draft.id);
    final upcoming = ref
        .read(dataProvider)
        .trips
        .all()
        .where(
          (t) =>
              t.assignedVehicleId == draft.id &&
              t.actualStart == null &&
              t.status.isUpcoming,
        )
        .toList();
    if (!_isNew &&
        prev != null &&
        prev.status != draft.status &&
        (draft.status == VehicleStatus.maintenance ||
            draft.status == VehicleStatus.unavailable) &&
        upcoming.isNotEmpty) {
      final ok = await showConfirmDialog(
        context,
        title: 'Take Vehicle ${draft.vehicleCode} out of service?',
        message:
            '${upcoming.map((t) => t.tripCode).join(', ')} will be flagged "needs attention" and must be reassigned.',
        confirmLabel: 'Set ${draft.status.label.toLowerCase()}',
        destructive: true,
      );
      if (!ok) return;
    }
    setState(() => _busy = true);
    final r = await ref
        .read(servicesProvider)
        .fleet
        .saveVehicle(draft, isNew: _isNew);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _errors = r.errors;
    });
    if (r.isOk) {
      showToast(context, r.message);
      if (_isNew) context.go('/fleet/vehicles/${draft.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    if (_missing) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Vehicle not found',
        message: 'It may have been removed by a demo reset.',
        actionLabel: 'All vehicles',
        onAction: () => context.go('/fleet/vehicles'),
      );
    }
    final seats = CapacityRules.breakdown(_v, guardRequired: false);
    final inspections = _isNew
        ? <Inspection>[]
        : data.inspectionsOfVehicle(_v.id);
    final trips = _isNew
        ? <Trip>[]
        : data.trips
              .all()
              .where(
                (x) =>
                    x.assignedVehicleId == _v.id &&
                    !x.serviceDate.isBefore(data.today) &&
                    !x.status.isTerminal,
              )
              .toList();

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
                  labelText: 'Vehicle ID',
                  helperText: 'e.g. C4 · cannot change later',
                ),
              ),
              TextField(
                controller: _reg,
                decoration: const InputDecoration(
                  labelText: 'Registration (fictional)',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          FormRow(
            children: [
              TextField(
                controller: _rc,
                decoration: const InputDecoration(
                  labelText: 'RC number (synthetic)',
                ),
              ),
              TextField(
                controller: _engine,
                decoration: const InputDecoration(
                  labelText: 'Engine number (synthetic)',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          FormRow(
            children: [
              TextField(
                controller: _color,
                decoration: const InputDecoration(labelText: 'Colour'),
              ),
              DropdownButtonFormField<FuelType?>(
                isExpanded: true,
                initialValue: _v.fuelType,
                decoration: InputDecoration(
                  labelText: 'Fuel type',
                  helperText: _v.fuelType == null
                      ? 'Derived: ${_v.effectiveFuelType.label}'
                      : null,
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('From propulsion'),
                  ),
                  for (final x in FuelType.values)
                    DropdownMenuItem(value: x, child: Text(x.label)),
                ],
                onChanged: (x) =>
                    setState(() => _v = _v.copyWith(fuelType: () => x)),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          FormRow(
            children: [
              TextField(
                controller: _model,
                decoration: const InputDecoration(labelText: 'Model'),
              ),
              DropdownButtonFormField<VehicleType>(
                isExpanded: true,
                initialValue: _v.type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [
                  for (final x in VehicleType.values)
                    DropdownMenuItem(value: x, child: Text(x.label)),
                ],
                onChanged: (x) => setState(() => _v = _v.copyWith(type: x)),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          FormRow(
            children: [
              DropdownButtonFormField<Propulsion>(
                isExpanded: true,
                initialValue: _v.propulsion,
                decoration: const InputDecoration(labelText: 'Propulsion'),
                items: [
                  for (final x in Propulsion.values)
                    DropdownMenuItem(value: x, child: Text(x.label)),
                ],
                onChanged: (x) =>
                    setState(() => _v = _v.copyWith(propulsion: x)),
              ),
              DropdownButtonFormField<LuxuryClass>(
                isExpanded: true,
                initialValue: _v.luxuryClass,
                decoration: const InputDecoration(labelText: 'Luxury class'),
                items: [
                  for (final x in LuxuryClass.values)
                    DropdownMenuItem(value: x, child: Text(x.label)),
                ],
                onChanged: (x) =>
                    setState(() => _v = _v.copyWith(luxuryClass: x)),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          FormRow(
            children: [
              DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: _v.totalSeats,
                decoration: const InputDecoration(
                  labelText: 'Total seats (incl. driver)',
                ),
                items: [
                  for (var i = 2; i <= 30; i++)
                    DropdownMenuItem(value: i, child: Text('$i')),
                ],
                onChanged: (x) =>
                    setState(() => _v = _v.copyWith(totalSeats: x)),
              ),
              DropdownButtonFormField<VehicleStatus>(
                isExpanded: true,
                initialValue: _v.status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [
                  for (final x in VehicleStatus.values)
                    DropdownMenuItem(value: x, child: Text(x.label)),
                ],
                onChanged: (x) => setState(() => _v = _v.copyWith(status: x)),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          InlineBanner(
            tone: StatusTone.info,
            title: 'Employee capacity: ${seats.passengerCapacity}',
            message:
                '$seats${_v.requiresSecurityGuard ? ' (guard required by vehicle policy)' : ''}',
          ),
          if (_v.status == VehicleStatus.maintenance ||
              _v.status == VehicleStatus.unavailable) ...[
            const SizedBox(height: AppSpace.xs),
            const InlineBanner(
              tone: StatusTone.warning,
              title: 'Out of service',
              message:
                  'This vehicle cannot be assigned. Not-yet-started trips on it are flagged for reassignment when you save.',
            ),
          ],
          const SizedBox(height: AppSpace.sm),
          FormRow(
            children: [
              TextField(
                controller: _odo,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Odometer (km)'),
              ),
              TextField(
                controller: _energy,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _v.isEv ? 'Battery %' : 'Fuel %',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          FormRow(
            children: [
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _v.assignedEmployerId,
                decoration: const InputDecoration(
                  labelText: 'Dedicated employer',
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Shared pool (default)'),
                  ),
                  for (final e in data.employers)
                    DropdownMenuItem(value: e.id, child: Text(e.name)),
                ],
                onChanged: (x) => setState(
                  () => _v = _v.copyWith(assignedEmployerId: () => x),
                ),
              ),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _v.homeParkingId,
                decoration: const InputDecoration(labelText: 'Home parking'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('None')),
                  for (final p in data.parkingLocations)
                    DropdownMenuItem(
                      value: p.id,
                      child: Text(p.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (x) =>
                    setState(() => _v = _v.copyWith(homeParkingId: () => x)),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _v.requiresSecurityGuard,
            onChanged: (x) =>
                setState(() => _v = _v.copyWith(requiresSecurityGuard: x)),
            title: const Text('Requires security guard'),
            subtitle: const Text(
              'Explicit vehicle policy; deducts one seat from employee capacity.',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _v.securityGuardAssigned,
            onChanged: (x) =>
                setState(() => _v = _v.copyWith(securityGuardAssigned: x)),
            title: const Text('Guard assigned'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _v.active,
            onChanged: _isNew
                ? null
                : (x) => setState(() => _v = _v.copyWith(active: x)),
            title: const Text('Active record'),
            subtitle: const Text(
              'Deactivated vehicles keep their trip and billing history but cannot be assigned.',
            ),
          ),
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
        if (!_isNew) ...[
          _blockersPanel(context, data),
          const SizedBox(height: AppSpace.md),
          _diagnosticsPanel(context, data),
          const SizedBox(height: AppSpace.md),
          ResourceAllocationsPanel(
            type: ResourceType.vehicle,
            resourceId: _v.id,
          ),
          const SizedBox(height: AppSpace.md),
        ],
        PanelCard(
          title: 'Upcoming trips',
          child: trips.isEmpty
              ? Text(
                  'No upcoming trips assigned.',
                  style: AppText.muted(context),
                )
              : Column(
                  children: [
                    for (final x in trips)
                      TripRowTile(
                        trip: x,
                        onTap: () => context.go('/fleet/dispatch/trip/${x.id}'),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: AppSpace.md),
        PanelCard(
          title: 'Inspections',
          subtitle: _v.lastInspectionAt == null
              ? 'Never inspected'
              : 'Last ${Fmt.dateTime(_v.lastInspectionAt)}',
          child: inspections.isEmpty
              ? Text('No inspections recorded.', style: AppText.muted(context))
              : Column(
                  children: [
                    for (final i in inspections.take(8))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${Fmt.dateTime(i.submittedAt)} · ${i.driverId}',
                        ),
                        subtitle: Text(
                          i.failures.isEmpty
                              ? (i.notes.isEmpty ? 'All items passed' : i.notes)
                              : 'Failed: ${i.failures.map((f) => f.label).join(', ')}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: StatusBadge(
                          i.overallStatus.label,
                          tone: Tones.inspection(i.overallStatus),
                          dense: true,
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );

    return AdminPage(
      title: _isNew ? 'Add vehicle' : 'Vehicle ${_v.vehicleCode}',
      subtitle: _isNew
          ? 'All registrations and details are fictional demo data.'
          : '${_v.propulsion.label} ${_v.type.label} · ${_v.fictionalRegistration}',
      actions: [
        TextButton.icon(
          onPressed: () => context.go('/fleet/vehicles'),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Vehicles'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(_isNew ? 'Add vehicle' : 'Save changes'),
        ),
        if (!_isNew)
          StatusBadge(_v.status.label, tone: Tones.vehicle(_v.status)),
      ],
      children: [ResponsiveSplit(left: form, right: side)],
    );
  }
}

extension on _VehicleEditPageState {
  /// Assignment blockers + current assignment, computed from records.
  Widget _blockersPanel(BuildContext context, DataView data) {
    final v = data.vehicle(_v.id) ?? _v;
    final today = data.todayInspection(v.id);
    final level = v.batteryOrFuelPercent;
    final blockers = <String>[
      if (!v.active) 'Deactivated — cannot be assigned.',
      if (v.status == VehicleStatus.maintenance)
        'In maintenance${v.notes.isEmpty ? '' : ' (${v.notes})'}.',
      if (v.status == VehicleStatus.unavailable) 'Marked unavailable.',
      if (today != null && today.overallStatus == InspectionOutcome.failed)
        'Failed today\'s inspection (${today.criticalFailures.map((i) => i.label).join(', ')}).',
      if (level != null && level < 30)
        '${v.isEv ? 'Battery' : 'Fuel'} low ($level%).',
      if (v.requiresSecurityGuard && !v.securityGuardAssigned)
        'Requires a guard but none is assigned — trips need a guard reference.',
    ];
    final current = data.trips
        .all()
        .where((t) => t.assignedVehicleId == v.id && t.status.isActive)
        .firstOrNull;
    return PanelCard(
      title: 'Availability',
      subtitle: current == null
          ? 'Not on a trip right now'
          : 'On ${current.tripCode} (${current.status.label.toLowerCase()})',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (blockers.isEmpty)
            const InlineBanner(
              tone: StatusTone.success,
              title: 'No assignment blockers',
              message:
                  'Subject to time-window, capacity, contract and allocation checks at assignment.',
            )
          else
            InlineBanner(
              tone: StatusTone.warning,
              title: 'Assignment blockers',
              messages: blockers,
            ),
          if (current != null) ...[
            const SizedBox(height: AppSpace.xs),
            TripRowTile(
              trip: current,
              onTap: () => context.go('/fleet/dispatch/trip/${current.id}'),
            ),
          ],
        ],
      ),
    );
  }

  /// Simulated telemetry, diagnostic trouble codes and recent events.
  Widget _diagnosticsPanel(BuildContext context, DataView data) {
    final v = data.vehicle(_v.id) ?? _v;
    final snap = ref.read(servicesProvider).telematics.snapshot(v);
    final events = data.vehicleEventsOf(v.id).take(5).toList();
    final t = Theme.of(context).textTheme;
    return PanelCard(
      title: 'Telemetry & diagnostics',
      subtitle: 'Simulated telematics — no GPS/OBD hardware connected',
      trailing: TextButton(
        onPressed: () => context.go('/fleet/telematics'),
        child: const Text('Telematics'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeyValueRow(label: 'Status', value: snap.status, dense: true),
          KeyValueRow(
            label: 'Speed',
            value:
                '${snap.speedKmh.round()} km/h (limit ${data.policy.speedLimitKmh})',
            dense: true,
          ),
          KeyValueRow(
            label: 'Position',
            value: snap.positionLabel,
            dense: true,
          ),
          KeyValueRow(
            label: 'Last update',
            value: Fmt.ago(snap.lastUpdate, data.now),
            dense: true,
          ),
          const SizedBox(height: AppSpace.sm),
          Text('Diagnostic trouble codes', style: t.titleSmall),
          const SizedBox(height: AppSpace.xs),
          if (v.diagnosticCodes.isEmpty)
            Text('No active codes.', style: AppText.muted(context))
          else
            for (final code in v.diagnosticCodes)
              Row(
                children: [
                  const Icon(
                    Icons.build_circle_outlined,
                    size: 18,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(child: Text(code)),
                  TextButton(
                    onPressed: () => runAndShow(
                      context,
                      ref
                          .read(servicesProvider)
                          .telematics
                          .clearDiagnostic(v.id, code),
                      successMessage: 'Cleared $code',
                    ),
                    child: const Text('Clear code'),
                  ),
                ],
              ),
          const SizedBox(height: AppSpace.sm),
          Text('Recent events', style: t.titleSmall),
          const SizedBox(height: AppSpace.xs),
          if (events.isEmpty)
            Text('No telematics events.', style: AppText.muted(context))
          else
            for (final e in events)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${e.type.label} · ${Fmt.ago(e.occurredAt, data.now)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    StatusBadge(
                      e.open ? 'Open' : 'Acknowledged',
                      tone: e.open ? StatusTone.danger : StatusTone.success,
                      dense: true,
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
