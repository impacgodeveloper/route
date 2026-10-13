import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../domain/models/models.dart';

Future<void> showGeofenceEditor(BuildContext context, {Geofence? geofence}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _GeofenceEditor(geofence: geofence),
    );

class _GeofenceEditor extends ConsumerStatefulWidget {
  const _GeofenceEditor({this.geofence});
  final Geofence? geofence;

  @override
  ConsumerState<_GeofenceEditor> createState() => _GeofenceEditorState();
}

class _GeofenceEditorState extends ConsumerState<_GeofenceEditor> {
  late final bool _isNew = widget.geofence == null;
  late final _name = TextEditingController(text: widget.geofence?.name ?? '');
  late final _x = TextEditingController(
    text: (widget.geofence?.centerX ?? 18).toString(),
  );
  late final _y = TextEditingController(
    text: (widget.geofence?.centerY ?? 14).toString(),
  );
  late final _r = TextEditingController(
    text: (widget.geofence?.radiusKm ?? 4).toString(),
  );
  late final _notes = TextEditingController(text: widget.geofence?.notes ?? '');
  late GeofenceKind _kind = widget.geofence?.kind ?? GeofenceKind.serviceArea;
  late final Set<String> _vehicles = {...?widget.geofence?.vehicleIds};
  late bool _active = widget.geofence?.active ?? true;
  List<String> _errors = const [];

  bool get _corridor => _kind == GeofenceKind.routeCorridor;

  @override
  void dispose() {
    for (final c in [_name, _x, _y, _r, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final x = double.tryParse(_x.text.trim());
    final y = double.tryParse(_y.text.trim());
    final r = double.tryParse(_r.text.trim());
    if (!_corridor && (x == null || y == null || r == null)) {
      setState(() => _errors = ['Centre and radius must be numbers.']);
      return;
    }
    final now = ref.read(dataProvider).now;
    final g = Geofence(
      id: widget.geofence?.id ?? 'new',
      name: _name.text.trim(),
      kind: _kind,
      centerX: _corridor ? 0 : x!,
      centerY: _corridor ? 0 : y!,
      radiusKm: _corridor ? 0 : r!,
      vehicleIds: _vehicles.toList()..sort(),
      active: _active,
      notes: _notes.text.trim(),
      createdAt: widget.geofence?.createdAt ?? now,
    );
    final res = await ref
        .read(servicesProvider)
        .geofences
        .save(g, isNew: _isNew);
    if (!mounted) return;
    setState(() => _errors = res.errors);
    if (res.isOk) {
      Navigator.pop(context);
      showToast(context, res.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    return AlertDialog(
      title: Text(_isNew ? 'New geofence' : 'Edit ${widget.geofence!.name}'),
      content: SizedBox(
        width: 500,
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
              TextField(
                key: const Key('geofenceName'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: AppSpace.sm),
              DropdownButtonFormField<GeofenceKind>(
                isExpanded: true,
                initialValue: _kind,
                decoration: const InputDecoration(labelText: 'Kind'),
                items: [
                  for (final k in GeofenceKind.values)
                    DropdownMenuItem(value: k, child: Text(k.label)),
                ],
                onChanged: (k) => setState(() => _kind = k ?? _kind),
              ),
              const SizedBox(height: AppSpace.sm),
              if (_corridor)
                InlineBanner(
                  tone: StatusTone.info,
                  title: 'Route corridor',
                  message:
                      'Applies along every active trip\'s planned route. Width comes from the fleet policy (±${data.policy.routeCorridorKm.toStringAsFixed(1)} km); no centre or radius needed.',
                )
              else ...[
                FormRow(
                  children: [
                    TextField(
                      key: const Key('geofenceX'),
                      controller: _x,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Centre X (demo km)',
                      ),
                    ),
                    TextField(
                      key: const Key('geofenceY'),
                      controller: _y,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Centre Y (demo km)',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
                TextField(
                  key: const Key('geofenceRadius'),
                  controller: _r,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Radius (km)',
                    helperText: '0.1–60 km',
                  ),
                ),
              ],
              const SizedBox(height: AppSpace.md),
              Text(
                'Vehicles (none selected = all vehicles)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpace.xs),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final v in data.vehicles)
                    FilterChip(
                      label: Text('Vehicle ${v.vehicleCode}'),
                      selected: _vehicles.contains(v.id),
                      onSelected: (s) => setState(
                        () => s ? _vehicles.add(v.id) : _vehicles.remove(v.id),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              TextField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                title: const Text('Active'),
              ),
              const SimulatedNote(
                'Positions are simulated on the fictional demo plane — geofence checks run against simulated telemetry only.',
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
          key: const Key('saveGeofence'),
          onPressed: _save,
          child: Text(_isNew ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}
