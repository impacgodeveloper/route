import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/widgets.dart';
import '../../../domain/models/models.dart';
import '../../../domain/rules/geo_rules.dart';
import '../widgets/fleet_common.dart';

enum _LocGroup {
  parking('Parking & depots', {LocationType.parking, LocationType.depot}),
  pickups('Pickup stops', {LocationType.pickup, LocationType.intermediateStop}),
  offices('Destinations', {LocationType.office, LocationType.destination}),
  all('All', {...LocationType.values});

  const _LocGroup(this.label, this.types);
  final String label;
  final Set<LocationType> types;
}

String _coord(Location l) {
  final (lat, lng) = GeoRules.latLngOf(l);
  return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
}

class ParkingPage extends ConsumerStatefulWidget {
  const ParkingPage({super.key});

  @override
  ConsumerState<ParkingPage> createState() => _ParkingPageState();
}

class _ParkingPageState extends ConsumerState<ParkingPage> {
  _LocGroup _group = _LocGroup.parking;
  String? _selectedId;
  String _q = '';
  bool _activeOnly = false;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final t = Theme.of(context).textTheme;
    final q = _q.toLowerCase();
    final rows = data.locationsOfType(_group.types).where((l) {
      if (_activeOnly && !l.active) return false;
      return q.isEmpty ||
          l.code.toLowerCase().contains(q) ||
          l.name.toLowerCase().contains(q) ||
          l.address.toLowerCase().contains(q);
    }).toList();
    final parked = <String, List<Vehicle>>{};
    for (final v in data.vehicles.where((v) => v.active)) {
      if (v.homeParkingId != null) {
        parked.putIfAbsent(v.homeParkingId!, () => []).add(v);
      }
    }
    final users = <String, int>{};
    for (final e in data.employees.where((e) => e.isActive)) {
      users[e.pickupLocationId] = (users[e.pickupLocationId] ?? 0) + 1;
      users[e.destinationId] = (users[e.destinationId] ?? 0) + 1;
    }
    final parking = data.parkingLocations.where((l) => l.active).toList();
    final totalSpots = parking.fold<int>(0, (s, l) => s + (l.capacity ?? 0));
    final usedSpots = parking.fold<int>(
      0,
      (s, l) => s + data.parkedVehicles(l.id),
    );

    final map = PanelCard(
      title: 'Schematic map',
      subtitle:
          'Circles = pickups · dark squares = offices · grey squares = parking',
      child: SchematicMap(
        height: 360,
        caption:
            '${DemoLabels.fictionalCoordinates} · schematic, not a real map',
        points: [
          for (final l in rows)
            MapPoint(
              x: l.demoX,
              y: l.demoY,
              label: l.code,
              kind: l.type,
              emphasis: l.id == _selectedId,
            ),
        ],
      ),
    );

    final list = PanelCard(
      title: _group.label,
      subtitle: '${rows.length} locations',
      padding: const EdgeInsets.fromLTRB(
        AppSpace.md,
        AppSpace.md,
        AppSpace.md,
        AppSpace.xs,
      ),
      child: rows.isEmpty
          ? EmptyState(
              icon: Icons.search_off_rounded,
              title: 'No locations match',
              message: 'Clear the search or filters.',
              compact: true,
              actionLabel: 'Clear',
              onAction: () => setState(() {
                _q = '';
                _activeOnly = false;
              }),
            )
          : Column(
              children: [
                for (final l in rows)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    selected: l.id == _selectedId,
                    selectedTileColor: AppColors.softBlue,
                    onTap: () => setState(() => _selectedId = l.id),
                    leading: IconTile(
                      icon: switch (l.type) {
                        LocationType.parking ||
                        LocationType.depot => Icons.local_parking_outlined,
                        LocationType.office ||
                        LocationType.destination => Icons.apartment_outlined,
                        _ => Icons.person_pin_circle_outlined,
                      },
                      color: l.active ? AppColors.primary : AppColors.textMuted,
                      size: 36,
                    ),
                    title: Text(l.label),
                    subtitle: Text(
                      [
                        l.type.label,
                        if (l.isParking && l.capacity != null)
                          '${data.parkedVehicles(l.id)}/${l.capacity} spots used · ${data.parkingAvailable(l.id)} free',
                        if ((parked[l.id] ?? []).isNotEmpty)
                          parked[l.id]!
                              .map((v) => 'Vehicle ${v.vehicleCode}')
                              .join(', '),
                        if (users[l.id] != null) '${users[l.id]} employees',
                        _coord(l),
                        if (l.notes.isNotEmpty) l.notes,
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (l.isParking && l.fleetOwned)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: StatusBadge(
                              'Fleet-owned',
                              tone: StatusTone.teal,
                              dense: true,
                            ),
                          ),
                        if (!l.active)
                          const StatusBadge('Inactive', dense: true),
                        IconButton(
                          tooltip: 'Edit ${l.code}',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () =>
                              showLocationEditor(context, location: l),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );

    return AdminPage(
      title: 'Parking & stops',
      subtitle:
          'Fleet-owned parking P1–P10, pickup stops and destinations G1–G4. Coordinates are fictional demo values.',
      actions: [
        FilledButton.icon(
          onPressed: () => showLocationEditor(context),
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('Add location'),
        ),
      ],
      children: [
        AppCard(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StatStrip(
                stats: [
                  ('Active parking sites', '${parking.length}'),
                  ('Parking spots', '$totalSpots'),
                  ('Spots used by vehicles', '$usedSpots'),
                  ('Spots free', '${totalSpots - usedSpots}'),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              const SimulatedNote(
                'Parking capacity counts vehicle spots — it is not passenger seating. Occupancy is derived from vehicles\' home parking. Any parking/depot can be chosen as a vehicle start point in Route Optimization.',
                icon: Icons.info_outline_rounded,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        LayoutBuilder(
          builder: (context, c) {
            final search = AppSearchField(
              hint: 'Search code, name or address',
              onChanged: (v) => setState(() => _q = v.trim()),
            );
            final active = FilterChip(
              label: const Text('Active only'),
              selected: _activeOnly,
              onSelected: (v) => setState(() => _activeOnly = v),
            );
            final chips = FilterChipBar<_LocGroup>(
              options: _LocGroup.values,
              selected: _group,
              onSelected: (g) => setState(() => _group = g),
              labelOf: (g) => g.label,
              countOf: (g) => data.locationsOfType(g.types).length,
            );
            if (c.maxWidth < 760) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  search,
                  const SizedBox(height: AppSpace.sm),
                  chips,
                  const SizedBox(height: AppSpace.xs),
                  Align(alignment: Alignment.centerLeft, child: active),
                ],
              );
            }
            return Row(
              children: [
                SizedBox(width: 300, child: search),
                const SizedBox(width: AppSpace.md),
                Expanded(child: chips),
                const SizedBox(width: AppSpace.sm),
                active,
              ],
            );
          },
        ),
        const SizedBox(height: AppSpace.md),
        ResponsiveSplit(left: list, right: map, leftFlex: 1, rightFlex: 1),
        const SizedBox(height: AppSpace.sm),
        Text(
          DemoLabels.schematicMap,
          style: t.bodySmall!.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: AppSpace.lg),
        const ParkingOptimizerCard(),
      ],
    );
  }
}

/// "Optimize parking placement": nearest parking to each vehicle's next
/// first pickup, within capacity (ParkingPlannerService).
class ParkingOptimizerCard extends ConsumerStatefulWidget {
  const ParkingOptimizerCard({super.key});

  @override
  ConsumerState<ParkingOptimizerCard> createState() =>
      _ParkingOptimizerCardState();
}

class _ParkingOptimizerCardState extends ConsumerState<ParkingOptimizerCard> {
  final _selected = <String>{};
  bool _busy = false;

  String _code(DataView data, String? id) =>
      id == null ? '—' : (data.location(id)?.code ?? id);

  Future<void> _apply(List<ParkingRecommendation> chosen) async {
    final data = ref.read(dataProvider);
    final ok = await showConfirmDialog(
      context,
      title: 'Apply ${chosen.length} parking change(s)?',
      message:
          'Updates each vehicle\'s home parking and notifies assigned drivers. Every change is recorded in the audit log.',
      confirmLabel: 'Apply',
      extra: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in chosen)
            Text(
              'Vehicle ${r.vehicle.vehicleCode}: ${_code(data, r.currentParkingId)} → ${_code(data, r.recommendedParkingId)} (saves ${r.savingKm.toStringAsFixed(1)} km)',
            ),
        ],
      ),
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final done = await runAndShow(
      context,
      ref.read(servicesProvider).parkingPlanner.apply([
        for (final r in chosen) r.vehicle.id,
      ]),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (done) _selected.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final t = Theme.of(context).textTheme;
    final recs = ref.read(servicesProvider).parkingPlanner.recommend();
    final changes = recs.where((r) => r.changes).toList();
    _selected.removeWhere((id) => !changes.any((r) => r.vehicle.id == id));
    final chosen = changes
        .where((r) => _selected.contains(r.vehicle.id))
        .toList();
    final totalSaving = changes.fold<double>(0, (s, r) => s + r.savingKm);

    // Capacity usage after applying the current selection.
    final after = <String, int>{};
    for (final v in data.vehicles.where((v) => v.active)) {
      final r = chosen.where((r) => r.vehicle.id == v.id).firstOrNull;
      final p = r?.recommendedParkingId ?? v.homeParkingId;
      if (p != null) after[p] = (after[p] ?? 0) + 1;
    }
    final parkings = data.parkingLocations
        .where((p) => p.active && (p.capacity ?? 0) > 0)
        .toList();

    Widget check(ParkingRecommendation r) => Checkbox(
      value: _selected.contains(r.vehicle.id),
      onChanged: r.changes
          ? (v) => setState(
              () => v == true
                  ? _selected.add(r.vehicle.id)
                  : _selected.remove(r.vehicle.id),
            )
          : null,
    );

    return PanelCard(
      title: 'Optimize parking placement',
      subtitle: changes.isEmpty
          ? 'Every vehicle already parks at its best spot'
          : '${changes.length} improvement(s) · up to ${totalSaving.toStringAsFixed(1)} empty km saved per first run',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Method: for each active vehicle, the target is the first pickup of its next scheduled trip (or its current base if none). Vehicle–parking pairs are ranked by empty (deadhead) road km and assigned greedily, nearest first, without exceeding any site\'s spot capacity. Deterministic — ties break by vehicle and parking ID.',
            style: AppText.secondary(context),
          ),
          const SizedBox(height: AppSpace.md),
          AdaptiveTable<ParkingRecommendation>(
            rows: recs,
            columns: [
              TableCol('', check, flex: 1),
              TableCol(
                'Vehicle',
                (r) => Text(
                  'Vehicle ${r.vehicle.vehicleCode}',
                  style: t.titleSmall,
                ),
                flex: 2,
              ),
              TableCol(
                'Current → recommended',
                (r) => Text(
                  r.changes
                      ? '${_code(data, r.currentParkingId)} → ${_code(data, r.recommendedParkingId)}'
                      : '${_code(data, r.currentParkingId)} (keep)',
                ),
                flex: 3,
              ),
              TableCol(
                'Target',
                (r) => Text(
                  r.targetLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                flex: 4,
              ),
              TableCol(
                'Empty km',
                (r) => Text(
                  '${r.currentDeadheadKm.toStringAsFixed(1)} → ${r.recommendedDeadheadKm.toStringAsFixed(1)}',
                ),
                flex: 2,
                numeric: true,
              ),
              TableCol(
                'Saving',
                (r) => Text(
                  r.changes ? '${r.savingKm.toStringAsFixed(1)} km' : '—',
                  style: TextStyle(
                    color: r.savingKm > 0 ? AppColors.success : null,
                    fontWeight: r.savingKm > 0 ? FontWeight.w700 : null,
                  ),
                ),
                flex: 2,
                numeric: true,
              ),
            ],
            mobileCard: (r) => Row(
              children: [
                check(r),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Vehicle ${r.vehicle.vehicleCode} · ${r.changes ? '${_code(data, r.currentParkingId)} → ${_code(data, r.recommendedParkingId)}' : 'keep ${_code(data, r.currentParkingId)}'}',
                        style: t.titleSmall,
                      ),
                      Text(r.targetLabel, style: AppText.muted(context)),
                      Text(
                        'Empty km ${r.currentDeadheadKm.toStringAsFixed(1)} → ${r.recommendedDeadheadKm.toStringAsFixed(1)}${r.changes ? ' · saves ${r.savingKm.toStringAsFixed(1)} km' : ''}',
                        style: AppText.secondary(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: [
              OutlinedButton(
                onPressed: changes.isEmpty
                    ? null
                    : () => setState(
                        () => _selected
                          ..clear()
                          ..addAll(changes.map((r) => r.vehicle.id)),
                      ),
                child: const Text('Select all changes'),
              ),
              FilledButton.icon(
                key: const Key('applyParking'),
                onPressed: chosen.isEmpty || _busy
                    ? null
                    : () => _apply(chosen),
                icon: const Icon(Icons.check_rounded),
                label: Text('Apply ${chosen.length} selected'),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            chosen.isEmpty
                ? 'Capacity usage (current)'
                : 'Capacity usage after applying the selection',
            style: t.titleSmall,
          ),
          const SizedBox(height: AppSpace.xs),
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: [
              for (final p in parkings)
                StatusBadge(
                  '${p.code} ${after[p.id] ?? 0}/${p.capacity}',
                  tone: (after[p.id] ?? 0) >= p.capacity!
                      ? StatusTone.warning
                      : StatusTone.neutral,
                  dense: true,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> showLocationEditor(BuildContext context, {Location? location}) =>
    showDialog<void>(
      context: context,
      builder: (c) => _LocationEditor(location: location),
    );

class _LocationEditor extends ConsumerStatefulWidget {
  const _LocationEditor({this.location});
  final Location? location;

  @override
  ConsumerState<_LocationEditor> createState() => _LocationEditorState();
}

class _LocationEditorState extends ConsumerState<_LocationEditor> {
  late final bool _isNew = widget.location == null;
  late final _code = TextEditingController(text: widget.location?.code ?? '');
  late final _name = TextEditingController(text: widget.location?.name ?? '');
  late final _address = TextEditingController(
    text: widget.location?.address ?? '',
  );
  late final (double, double) _initial = widget.location == null
      ? (GeoRules.latFromY(15), GeoRules.lngFromX(15))
      : GeoRules.latLngOf(widget.location!);
  late final _lat = TextEditingController(text: _initial.$1.toStringAsFixed(5));
  late final _lng = TextEditingController(text: _initial.$2.toStringAsFixed(5));
  late final _cap = TextEditingController(
    text: widget.location?.capacity?.toString() ?? '',
  );
  late final _notes = TextEditingController(text: widget.location?.notes ?? '');
  late LocationType _type = widget.location?.type ?? LocationType.parking;
  late bool _active = widget.location?.active ?? true;
  late bool _fleetOwned = widget.location?.fleetOwned ?? true;
  List<String> _errors = const [];

  bool get _isParking =>
      _type == LocationType.parking || _type == LocationType.depot;

  @override
  void dispose() {
    for (final c in [_code, _name, _address, _lat, _lng, _cap, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final code = _code.text.trim().toUpperCase();
    final lat = double.tryParse(_lat.text.trim());
    final lng = double.tryParse(_lng.text.trim());
    if (lat == null || lng == null) {
      setState(
        () => _errors = ['Latitude and longitude must be decimal numbers.'],
      );
      return;
    }
    final cap = int.tryParse(_cap.text.trim());
    final base = _isNew
        ? Location(
            id: code,
            code: code,
            name: _name.text.trim(),
            type: _type,
            address: _address.text.trim(),
            demoX: 0,
            demoY: 0,
            geofenceRadiusM: 150,
            active: _active,
            notes: _notes.text.trim(),
            capacity: _isParking ? cap : null,
            fleetOwned: _isParking && _fleetOwned,
          )
        : widget.location!.copyWith(
            name: _name.text.trim(),
            type: _type,
            address: _address.text.trim(),
            active: _active,
            notes: _notes.text.trim(),
            capacity: _isParking ? cap : null,
            fleetOwned: _isParking && _fleetOwned,
          );
    final loc = base.copyWith(latitude: () => lat, longitude: () => lng);
    final r = await ref
        .read(servicesProvider)
        .fleet
        .saveLocation(loc, isNew: _isNew);
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
    final parkedHere = _isNew ? 0 : data.parkedVehicles(widget.location!.id);
    return AlertDialog(
      title: Text(_isNew ? 'Add location' : 'Edit ${widget.location!.code}'),
      content: SizedBox(
        width: 480,
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
                    controller: _code,
                    enabled: _isNew,
                    decoration: const InputDecoration(labelText: 'Code'),
                  ),
                  DropdownButtonFormField<LocationType>(
                    isExpanded: true,
                    initialValue: _type,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: [
                      for (final x in LocationType.values)
                        DropdownMenuItem(value: x, child: Text(x.label)),
                    ],
                    onChanged: (x) => setState(() => _type = x ?? _type),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Name (fictional)',
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              TextField(
                controller: _address,
                decoration: const InputDecoration(
                  labelText: 'Address (fictional)',
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              FormRow(
                children: [
                  TextField(
                    controller: _lat,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Latitude (fictional)',
                    ),
                  ),
                  TextField(
                    controller: _lng,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Longitude (fictional)',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              if (_isParking) ...[
                TextField(
                  controller: _cap,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Parking spots (capacity)',
                    helperText: _isNew
                        ? 'Vehicle spots, not passenger seats'
                        : '$parkedHere vehicle(s) based here now',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _fleetOwned,
                  onChanged: (v) => setState(() => _fleetOwned = v),
                  title: const Text('Fleet-owned parking'),
                ),
              ],
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
                '${DemoLabels.fictionalCoordinates}. They are converted to the schematic routing plane on save.',
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
        FilledButton(onPressed: _save, child: Text(_isNew ? 'Add' : 'Save')),
      ],
    );
  }
}
