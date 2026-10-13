import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import 'employer_common.dart';

/// Pickup points and offices used by the employer's roster.
class LocationsPage extends ConsumerStatefulWidget {
  const LocationsPage({super.key});

  @override
  ConsumerState<LocationsPage> createState() => _LocationsPageState();
}

class _LocationsPageState extends ConsumerState<LocationsPage> {
  String? _selected;

  Future<void> _edit(Location? existing) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => _LocationDialog(existing: existing),
    );
    if (saved == true && mounted) {
      showToast(
        context,
        existing == null ? 'Pickup point added' : 'Location saved',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final employer = data.primaryEmployer;
    final emps = data
        .employeesOf(employer.id)
        .where((e) => e.isActive)
        .toList();
    final locs =
        data
            .locationsOfType({
              LocationType.pickup,
              LocationType.intermediateStop,
              LocationType.office,
              LocationType.destination,
            })
            .where((l) => l.employerId == null || l.employerId == employer.id)
            .toList()
          ..sort((a, b) {
            final ta =
                a.type == LocationType.office ||
                    a.type == LocationType.destination
                ? 1
                : 0;
            final tb =
                b.type == LocationType.office ||
                    b.type == LocationType.destination
                ? 1
                : 0;
            return ta != tb ? ta.compareTo(tb) : a.code.compareTo(b.code);
          });
    int pickups(Location l) =>
        emps.where((e) => e.pickupLocationId == l.id).length;
    int drops(Location l) => emps.where((e) => e.destinationId == l.id).length;
    bool isOffice(Location l) =>
        l.type == LocationType.office || l.type == LocationType.destination;
    final t = Theme.of(context).textTheme;

    return AdminPage(
      title: 'Pickup Locations',
      subtitle:
          '${locs.where((l) => !isOffice(l)).length} pickup points and ${locs.where(isOffice).length} offices for ${employer.code}. Coordinates are fictional demo values.',
      actions: [
        FilledButton.icon(
          onPressed: () => _edit(null),
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('Add pickup point'),
        ),
      ],
      children: [
        ResponsiveColumns(
          leftFlex: 2,
          rightFlex: 3,
          left: PanelCard(
            title: 'Schematic map',
            subtitle: 'Circles: pickups · squares: offices',
            child: SchematicMap(
              height: 340,
              points: [
                for (final l in locs.where((l) => l.active))
                  MapPoint(
                    x: l.demoX,
                    y: l.demoY,
                    label: l.code,
                    kind: l.type,
                    emphasis: l.id == _selected,
                  ),
              ],
            ),
          ),
          right: AdaptiveTable<Location>(
            rows: locs,
            breakpoint: 640,
            selectedPredicate: (l) => l.id == _selected,
            onRowTap: (l) => setState(() => _selected = l.id),
            columns: [
              TableCol(
                'Code',
                (l) => Text(
                  l.code,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              TableCol(
                'Name',
                (l) => Text(l.name, overflow: TextOverflow.ellipsis),
                flex: 3,
              ),
              TableCol('Type', (l) => Text(l.type.label)),
              TableCol(
                'Employees',
                (l) => Text(
                  isOffice(l) ? '${drops(l)} drop' : '${pickups(l)} pickup',
                ),
                numeric: true,
              ),
              TableCol(
                'Status',
                (l) => StatusBadge(
                  l.active ? 'Active' : 'Inactive',
                  tone: l.active ? StatusTone.success : StatusTone.neutral,
                  dense: true,
                ),
              ),
              TableCol(
                '',
                (l) => isOffice(l)
                    ? const Tooltip(
                        message: 'Offices are managed by the Fleet Manager',
                        child: Icon(
                          Icons.lock_outline_rounded,
                          size: 18,
                          color: AppColors.textMuted,
                        ),
                      )
                    : IconButton(
                        tooltip: 'Edit ${l.code}',
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () => _edit(l),
                      ),
                numeric: true,
              ),
            ],
            mobileCard: (l) => Row(
              children: [
                IconTile(
                  icon: isOffice(l)
                      ? Icons.apartment_outlined
                      : Icons.place_outlined,
                  size: 36,
                  color: isOffice(l) ? AppColors.deepNavy : AppColors.primary,
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${l.code} · ${l.name}', style: t.titleSmall),
                      Text(
                        '${l.type.label} · ${isOffice(l) ? '${drops(l)} employees' : '${pickups(l)} employees'}${l.active ? '' : ' · inactive'}',
                        style: AppText.muted(context),
                      ),
                    ],
                  ),
                ),
                if (!isOffice(l))
                  IconButton(
                    tooltip: 'Edit ${l.code}',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _edit(l),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        const SimulatedNote(DemoLabels.schematicMap, icon: Icons.map_outlined),
      ],
    );
  }
}

class _LocationDialog extends ConsumerStatefulWidget {
  const _LocationDialog({this.existing});
  final Location? existing;

  @override
  ConsumerState<_LocationDialog> createState() => _LocationDialogState();
}

class _LocationDialogState extends ConsumerState<_LocationDialog> {
  final _form = GlobalKey<FormState>();
  late final _code = TextEditingController(text: widget.existing?.code);
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _address = TextEditingController(text: widget.existing?.address);
  late final _x = TextEditingController(
    text: widget.existing?.demoX.toStringAsFixed(1) ?? '10.0',
  );
  late final _y = TextEditingController(
    text: widget.existing?.demoY.toStringAsFixed(1) ?? '10.0',
  );
  late final _geo = TextEditingController(
    text: '${widget.existing?.geofenceRadiusM ?? 150}',
  );
  late bool _active = widget.existing?.active ?? true;
  List<String> _errors = const [];
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_code, _name, _address, _x, _y, _geo]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final ex = widget.existing;
    final code = _code.text.trim().toUpperCase();
    final loc = ex == null
        ? Location(
            id: code,
            code: code,
            name: _name.text.trim(),
            type: LocationType.pickup,
            address: _address.text.trim(),
            demoX: double.parse(_x.text),
            demoY: double.parse(_y.text),
            geofenceRadiusM: int.tryParse(_geo.text),
            employerId: ref.read(dataProvider).primaryEmployer.id,
            active: _active,
          )
        : ex.copyWith(
            name: _name.text.trim(),
            address: _address.text.trim(),
            demoX: double.parse(_x.text),
            demoY: double.parse(_y.text),
            geofenceRadiusM: int.tryParse(_geo.text),
            active: _active,
          );
    setState(() => _busy = true);
    final r = await ref
        .read(servicesProvider)
        .fleet
        .saveLocation(loc, isNew: ex == null, actor: Actor.employerAdmin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _errors = r.errors;
    });
    if (r.isOk) Navigator.pop(context, true);
  }

  String? _coord(String? v) {
    final n = double.tryParse(v?.trim() ?? '');
    if (n == null) return 'Number';
    if (n < 0 || n > 40) return '0–40';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    return AlertDialog(
      title: Text(isNew ? 'Add pickup point' : 'Edit ${widget.existing!.code}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, minWidth: 280),
        child: Form(
          key: _form,
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
                TextFormField(
                  controller: _code,
                  enabled: isNew,
                  decoration: const InputDecoration(
                    labelText: 'Code',
                    hintText: 'e.g. PK13',
                  ),
                  validator: (v) => Validators.required(v, 'Code'),
                ),
                const SizedBox(height: AppSpace.sm),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) => Validators.minLength(v, 3, 'Name'),
                ),
                const SizedBox(height: AppSpace.sm),
                TextFormField(
                  controller: _address,
                  decoration: const InputDecoration(
                    labelText: 'Address (fictional)',
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _x,
                        decoration: const InputDecoration(
                          labelText: 'Demo X (km)',
                        ),
                        validator: _coord,
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: TextFormField(
                        controller: _y,
                        decoration: const InputDecoration(
                          labelText: 'Demo Y (km)',
                        ),
                        validator: _coord,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
                TextFormField(
                  controller: _geo,
                  decoration: const InputDecoration(
                    labelText: 'Geofence radius',
                    suffixText: 'm',
                  ),
                  validator: (v) => Validators.intRange(v, 25, 1000, 'Radius'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                  title: const Text('Active'),
                ),
                const SimulatedNote(
                  'Coordinates place the point on the schematic demo plane only — they are not GPS positions.',
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(isNew ? 'Add' : 'Save'),
        ),
      ],
    );
  }
}
