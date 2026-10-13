import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../domain/models/models.dart';
import '../../../../domain/rules/trip_state_machine.dart';
import 'mapping_table.dart';

enum _GuardFilter { any, yes, no }

/// Car-to-employee mapping: a validated view over trips (no duplicate
/// table). Edits go through the existing assignment workflow only.
class VehicleMappingPage extends ConsumerStatefulWidget {
  const VehicleMappingPage({super.key});

  @override
  ConsumerState<VehicleMappingPage> createState() => _VehicleMappingPageState();
}

class _VehicleMappingPageState extends ConsumerState<VehicleMappingPage> {
  int? _dayOffset = 0; // null = all dates
  String? _company;
  String? _vehicle;
  TripStatus? _status;
  _GuardFilter _guard = _GuardFilter.any;
  String _q = '';
  int _searchVersion = 0;

  void _reset() => setState(() {
    _dayOffset = null;
    _company = null;
    _vehicle = null;
    _status = null;
    _guard = _GuardFilter.any;
    _q = '';
    _searchVersion++;
  });

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final today = data.today;
    var trips = data.trips.all();
    if (_dayOffset != null) {
      final d = today.add(Duration(days: _dayOffset!));
      trips = trips.where((x) => sameDay(x.serviceDate, d)).toList();
    }
    var rows = MappingRow.fromTrips(data, trips).where((r) {
      if (_company != null && r.companyId != _company) return false;
      if (_vehicle != null && r.vehicleId != _vehicle) return false;
      if (_status != null && r.tripStatus != _status) return false;
      if (_guard == _GuardFilter.yes && !r.guardRequired) return false;
      if (_guard == _GuardFilter.no && r.guardRequired) return false;
      if (_q.isNotEmpty) {
        final q = _q.toLowerCase();
        return (r.tripId ?? '').toLowerCase().contains(q) ||
            r.employeeIds.any((e) => e.toLowerCase() == q) ||
            (r.driverId ?? '').toLowerCase() == q ||
            r.vehicleId.toLowerCase() == q;
      }
      return true;
    }).toList();
    rows.sort((a, b) => a.start.compareTo(b.start));
    final issues = rows.where((r) => !r.feasible).length;

    return AdminPage(
      title: 'Vehicle mapping',
      subtitle:
          'Car-to-employee mappings derived from trips. Seats: total includes driver; employee capacity = total − driver − guard. Changes go through validated assignment only.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => context.go('/fleet/optimization'),
          icon: const Icon(Icons.auto_graph_outlined),
          label: const Text('Propose with optimizer'),
        ),
        FilledButton.icon(
          onPressed: () => context.go('/fleet/dispatch/new'),
          icon: const Icon(Icons.add_rounded),
          label: const Text('New mapping (trip)'),
        ),
      ],
      children: [
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterChipBar<int?>(
              options: const [null, -1, 0, 1],
              selected: _dayOffset,
              onSelected: (o) => setState(() => _dayOffset = o),
              labelOf: (o) => o == null
                  ? 'All dates'
                  : Fmt.dayLabel(today.add(Duration(days: o)), data.now),
            ),
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _company,
                decoration: const InputDecoration(labelText: 'Company'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All')),
                  for (final e in data.employers)
                    DropdownMenuItem(value: e.id, child: Text(e.code)),
                ],
                onChanged: (v) => setState(() => _company = v),
              ),
            ),
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _vehicle,
                decoration: const InputDecoration(labelText: 'Vehicle'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All')),
                  for (final v in data.vehicles)
                    DropdownMenuItem(value: v.id, child: Text(v.vehicleCode)),
                ],
                onChanged: (v) => setState(() => _vehicle = v),
              ),
            ),
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<TripStatus?>(
                isExpanded: true,
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All')),
                  for (final s in TripStatus.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (v) => setState(() => _status = v),
              ),
            ),
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<_GuardFilter>(
                isExpanded: true,
                initialValue: _guard,
                decoration: const InputDecoration(labelText: 'Guard'),
                items: const [
                  DropdownMenuItem(value: _GuardFilter.any, child: Text('Any')),
                  DropdownMenuItem(
                    value: _GuardFilter.yes,
                    child: Text('Required'),
                  ),
                  DropdownMenuItem(
                    value: _GuardFilter.no,
                    child: Text('Not required'),
                  ),
                ],
                onChanged: (v) =>
                    setState(() => _guard = v ?? _GuardFilter.any),
              ),
            ),
            SizedBox(
              width: 260,
              child: AppSearchField(
                key: ValueKey(_searchVersion),
                hint: 'Trip, employee, driver or vehicle ID',
                onChanged: (v) => setState(() => _q = v.trim()),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        Text(
          '${rows.length} mapping${rows.length == 1 ? '' : 's'}${issues > 0 ? ' · $issues need attention' : ''}',
          style: AppText.secondary(context),
        ),
        const SizedBox(height: AppSpace.sm),
        MappingTable(
          rows: rows,
          empty: EmptyState(
            icon: Icons.table_rows_outlined,
            title: 'No mappings match',
            message: 'Mappings exist once a trip has a vehicle assigned.',
            actionLabel: 'Clear filters',
            onAction: _reset,
            compact: true,
          ),
          actions: (r) => _RowActions(row: r),
        ),
        const SizedBox(height: AppSpace.sm),
        const SimulatedNote(
          'The handwritten example (vehicle C1 with four employees) would exceed C1\'s 3 employee seats; the validator rejects it.',
        ),
      ],
    );
  }
}

class _RowActions extends ConsumerWidget {
  const _RowActions({required this.row});
  final MappingRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.read(dataProvider).trips.byId(row.tripId);
    final canReassign = trip != null && TripStateMachine.canAssign(trip.status);
    return PopupMenuButton<String>(
      tooltip: 'Actions for ${row.tripId}',
      icon: const Icon(Icons.more_horiz_rounded),
      onSelected: (v) {
        switch (v) {
          case 'view':
            context.go('/fleet/dispatch/trip/${row.tripId}');
          case 'reassign':
            context.go('/fleet/dispatch/trip/${row.tripId}?reassign=1');
          case 'audit':
            showAppSheet<void>(
              context,
              title: 'Audit · ${row.tripId}',
              builder: (c) => _TripAudit(tripId: row.tripId!),
            );
        }
      },
      itemBuilder: (c) => [
        const PopupMenuItem(value: 'view', child: Text('View trip')),
        PopupMenuItem(
          value: 'reassign',
          enabled: canReassign,
          child: const Text('Reassign…'),
        ),
        const PopupMenuItem(value: 'audit', child: Text('Audit history')),
      ],
    );
  }
}

class _TripAudit extends ConsumerWidget {
  const _TripAudit({required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final events = data.auditTrail
        .where(
          (a) =>
              (a.entityType == 'trip' && a.entityId == tripId) ||
              a.related.values.contains(tripId),
        )
        .toList();
    final t = Theme.of(context).textTheme;
    if (events.isEmpty) {
      return const EmptyState(
        icon: Icons.history_rounded,
        title: 'No audit events',
        message: 'Changes to this mapping will be recorded here.',
        compact: true,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final a in events)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(a.summary, style: t.titleSmall)),
                    StatusBadge(
                      a.outcome.label,
                      tone: a.outcome == AuditOutcome.success
                          ? StatusTone.success
                          : StatusTone.danger,
                      dense: true,
                    ),
                  ],
                ),
                Text(
                  '${Fmt.dateTime(a.timestamp)} · ${a.actorRole.label} ${a.actorId} · ${a.action}',
                  style: AppText.muted(context),
                ),
                if (a.changes.isNotEmpty) Text(a.changes, style: t.bodySmall),
                if (a.reason != null)
                  Text('Reason: ${a.reason}', style: t.bodySmall),
              ],
            ),
          ),
        const SimulatedNote(DemoLabels.auditNotTamperProof),
      ],
    );
  }
}
