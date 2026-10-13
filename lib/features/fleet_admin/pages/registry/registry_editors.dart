import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../domain/models/models.dart';
import 'registry_common.dart';

Future<void> showContractEditor(
  BuildContext context, {
  required Employer company,
  Contract? contract,
}) => showDialog<void>(
  context: context,
  builder: (_) => _ContractEditor(company: company, contract: contract),
);

class _ContractEditor extends ConsumerStatefulWidget {
  const _ContractEditor({required this.company, this.contract});
  final Employer company;
  final Contract? contract;

  @override
  ConsumerState<_ContractEditor> createState() => _ContractEditorState();
}

class _ContractEditorState extends ConsumerState<_ContractEditor> {
  late final bool _isNew = widget.contract == null;
  late final _code = TextEditingController(
    text: widget.contract?.contractCode ?? '',
  );
  late final _doc = TextEditingController(
    text: widget.contract?.documentRef ?? '',
  );
  late final _cars = TextEditingController(
    text: '${widget.contract?.agreedVehicleCount ?? 3}',
  );
  late final _cost = TextEditingController(
    text: (widget.contract?.costPerVehicle ?? 55000).toStringAsFixed(0),
  );
  late final _contactId = TextEditingController(
    text: widget.contract?.contactId ?? '',
  );
  late final _contactName = TextEditingController(
    text: widget.contract?.contactName ?? '',
  );
  late final _notes = TextEditingController(text: widget.contract?.notes ?? '');
  late DateTime _from = widget.contract?.validFrom ?? _today;
  late DateTime _until =
      widget.contract?.validUntil ?? _today.add(const Duration(days: 364));
  late ContractStatus _status = widget.contract?.status ?? ContractStatus.draft;
  late bool _hard = widget.contract?.hardVehicleLimit ?? true;
  List<String> _errors = const [];

  DateTime get _today => ref.read(dataProvider).today;

  @override
  void dispose() {
    for (final c in [
      _code,
      _doc,
      _cars,
      _cost,
      _contactId,
      _contactName,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final cars = int.tryParse(_cars.text.trim());
    final cost = double.tryParse(_cost.text.trim());
    if (cars == null || cost == null) {
      setState(
        () => _errors = ['Agreed cars and cost per car must be numbers.'],
      );
      return;
    }
    final now = ref.read(dataProvider).now;
    final code = _code.text.trim().toUpperCase();
    final c = _isNew
        ? Contract(
            id: code,
            contractCode: code,
            employerId: widget.company.id,
            documentRef: _doc.text.trim(),
            validFrom: _from,
            validUntil: _until,
            status: _status,
            agreedVehicleCount: cars,
            costPerVehicle: cost,
            hardVehicleLimit: _hard,
            contactId: _contactId.text.trim(),
            contactName: _contactName.text.trim(),
            notes: _notes.text.trim(),
            createdAt: now,
            updatedAt: now,
          )
        : widget.contract!.copyWith(
            documentRef: _doc.text.trim(),
            validFrom: _from,
            validUntil: _until,
            status: _status,
            agreedVehicleCount: cars,
            costPerVehicle: cost,
            hardVehicleLimit: _hard,
            contactId: _contactId.text.trim(),
            contactName: _contactName.text.trim(),
            notes: _notes.text.trim(),
          );
    final r = await ref.read(servicesProvider).contracts.save(c, isNew: _isNew);
    if (!mounted) return;
    setState(() => _errors = r.errors);
    if (r.isOk) {
      Navigator.pop(context);
      await showResult(
        context,
        r,
        successMessage: _isNew ? 'Contract created' : 'Contract saved',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = Contract(
      id: 'x',
      contractCode: 'x',
      employerId: widget.company.id,
      documentRef: '',
      validFrom: _from,
      validUntil: _until,
      status: _status,
      agreedVehicleCount: 1,
      costPerVehicle: 0,
      createdAt: _from,
      updatedAt: _from,
    ).validityOn(ref.read(dataProvider).today);
    return AlertDialog(
      title: Text(
        _isNew
            ? 'New contract · Company ${widget.company.code}'
            : 'Edit ${widget.contract!.contractCode}',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
              FormRow(
                children: [
                  TextField(
                    key: const Key('contractCode'),
                    controller: _code,
                    enabled: _isNew,
                    decoration: const InputDecoration(
                      labelText: 'Contract ID',
                      helperText: 'e.g. CT-2027-01',
                    ),
                  ),
                  DropdownButtonFormField<ContractStatus>(
                    isExpanded: true,
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: [
                      for (final s in ContractStatus.values)
                        DropdownMenuItem(value: s, child: Text(s.label)),
                    ],
                    onChanged: (s) => setState(() => _status = s ?? _status),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              TextField(
                key: const Key('contractDoc'),
                controller: _doc,
                decoration: const InputDecoration(
                  labelText: 'Contract document reference',
                  helperText:
                      'Metadata only — no file is uploaded in this prototype',
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              FormRow(
                children: [
                  DateField(
                    label: 'Valid from',
                    value: _from,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2040),
                    onChanged: (d) => setState(() => _from = d),
                  ),
                  DateField(
                    label: 'Valid until',
                    value: _until,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2040),
                    onChanged: (d) => setState(() => _until = d),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.xs),
              Row(
                children: [
                  Text('Validity today: ', style: AppText.muted(context)),
                  StatusBadge(
                    preview.label,
                    tone: contractTone(preview),
                    dense: true,
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              FormRow(
                children: [
                  TextField(
                    key: const Key('contractCars'),
                    controller: _cars,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Agreed cars per day',
                    ),
                  ),
                  TextField(
                    controller: _cost,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Agreed cost per car (₹ / month)',
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _hard,
                onChanged: (v) => setState(() => _hard = v),
                title: const Text('Hard car limit'),
                subtitle: Text(
                  _hard
                      ? 'Assignments beyond the agreed cars are blocked.'
                      : 'Exceeding the agreed cars is allowed with a warning.',
                ),
              ),
              FormRow(
                children: [
                  TextField(
                    controller: _contactId,
                    decoration: const InputDecoration(labelText: 'Contact ID'),
                  ),
                  TextField(
                    controller: _contactName,
                    decoration: const InputDecoration(
                      labelText: 'Contact name (fictional)',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              TextField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'Notes'),
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
          key: const Key('saveContract'),
          onPressed: _save,
          child: Text(_isNew ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}

Future<void> showAllocationEditor(
  BuildContext context, {
  required Employer company,
  FleetAllocation? allocation,
}) => showDialog<void>(
  context: context,
  builder: (_) => _AllocationEditor(company: company, allocation: allocation),
);

class _AllocationEditor extends ConsumerStatefulWidget {
  const _AllocationEditor({required this.company, this.allocation});
  final Employer company;
  final FleetAllocation? allocation;

  @override
  ConsumerState<_AllocationEditor> createState() => _AllocationEditorState();
}

class _AllocationEditorState extends ConsumerState<_AllocationEditor> {
  late final bool _isNew = widget.allocation == null;
  late ResourceType _type =
      widget.allocation?.resourceType ?? ResourceType.vehicle;
  late String? _resource = widget.allocation?.resourceId;
  late int _start = widget.allocation?.windowStartMinutes ?? 300;
  late int _end = widget.allocation?.windowEndMinutes ?? 780;
  late final _label = TextEditingController(
    text: widget.allocation?.label ?? '',
  );
  List<String> _errors = const [];

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_resource == null) {
      setState(() => _errors = ['Select a ${_type.label.toLowerCase()}.']);
      return;
    }
    final now = ref.read(dataProvider).now;
    final a = _isNew
        ? FleetAllocation(
            id: 'new',
            employerId: widget.company.id,
            resourceType: _type,
            resourceId: _resource!,
            windowStartMinutes: _start,
            windowEndMinutes: _end,
            label: _label.text.trim(),
            createdAt: now,
          )
        : widget.allocation!.copyWith(
            windowStartMinutes: _start,
            windowEndMinutes: _end,
            label: _label.text.trim(),
          );
    final r = await ref
        .read(servicesProvider)
        .allocations
        .save(a, isNew: _isNew);
    if (!mounted) return;
    setState(() => _errors = r.errors);
    if (r.isOk) {
      Navigator.pop(context);
      showToast(context, r.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final options = _type == ResourceType.vehicle
        ? [
            for (final v in data.vehicles.where((v) => v.active))
              (v.id, 'Vehicle ${v.vehicleCode} · ${v.type.label}'),
          ]
        : [
            for (final d in data.drivers.where((d) => d.active))
              (d.id, '${d.driverCode} · ${d.name}'),
          ];
    return AlertDialog(
      title: Text(
        _isNew
            ? 'Add allocation · Company ${widget.company.code}'
            : 'Edit ${widget.allocation!.resourceId} window',
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
              if (_isNew) ...[
                SegmentedButton<ResourceType>(
                  segments: const [
                    ButtonSegment(
                      value: ResourceType.vehicle,
                      label: Text('Vehicle'),
                      icon: Icon(Icons.directions_car_outlined),
                    ),
                    ButtonSegment(
                      value: ResourceType.driver,
                      label: Text('Driver'),
                      icon: Icon(Icons.badge_outlined),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => setState(() {
                    _type = s.first;
                    _resource = null;
                  }),
                ),
                const SizedBox(height: AppSpace.sm),
                DropdownButtonFormField<String>(
                  key: ValueKey('res-$_type'),
                  isExpanded: true,
                  initialValue: _resource,
                  decoration: InputDecoration(labelText: _type.label),
                  items: [
                    for (final o in options)
                      DropdownMenuItem(
                        value: o.$1,
                        child: Text(o.$2, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _resource = v),
                ),
                const SizedBox(height: AppSpace.sm),
              ],
              FormRow(
                children: [
                  TimeOfDayField(
                    label: 'Window start',
                    minutes: _start,
                    onChanged: (m) => setState(() => _start = m),
                  ),
                  TimeOfDayField(
                    label: 'Window end',
                    minutes: _end,
                    helper: _end < _start ? 'Overnight window' : null,
                    onChanged: (m) => setState(() => _end = m),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              TextField(
                controller: _label,
                decoration: const InputDecoration(
                  labelText: 'Window label',
                  hintText: 'e.g. Morning operations',
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              const SimulatedNote(
                'The same vehicle or driver may serve other companies only in non-overlapping windows.',
                icon: Icons.info_outline_rounded,
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
          key: const Key('saveAllocation'),
          onPressed: _save,
          child: Text(_isNew ? 'Add' : 'Save'),
        ),
      ],
    );
  }
}
