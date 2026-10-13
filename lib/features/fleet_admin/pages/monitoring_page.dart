import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/widgets.dart';
import '../../../domain/models/models.dart';
import '../widgets/fleet_common.dart';
import 'v3/safety_sos.dart';

enum _Tab { live, incidents, tickets }

enum _IncFilter { open, all, resolved }

class MonitoringPage extends ConsumerStatefulWidget {
  const MonitoringPage({super.key, this.initialTab});
  final String? initialTab;

  @override
  ConsumerState<MonitoringPage> createState() => _MonitoringPageState();
}

class _MonitoringPageState extends ConsumerState<MonitoringPage> {
  late _Tab _tab = _Tab.values.firstWhere(
    (t) => t.name == widget.initialTab,
    orElse: () => _Tab.live,
  );
  _IncFilter _incFilter = _IncFilter.open;
  IncidentType? _type;

  @override
  void didUpdateWidget(covariant MonitoringPage old) {
    super.didUpdateWidget(old);
    if (old.initialTab != widget.initialTab && widget.initialTab != null) {
      _tab = _Tab.values.firstWhere(
        (t) => t.name == widget.initialTab,
        orElse: () => _tab,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    return AdminPage(
      title: 'Monitoring & incidents',
      subtitle:
          'Simulated live status of today\'s trips, the incident queue and support tickets. ${DemoLabels.incidentDemo}',
      children: [
        FilterChipBar<_Tab>(
          options: _Tab.values,
          selected: _tab,
          onSelected: (t) => setState(() => _tab = t),
          labelOf: (t) => switch (t) {
            _Tab.live => 'Live board',
            _Tab.incidents => 'Incidents',
            _Tab.tickets => 'Support tickets',
          },
          countOf: (t) => switch (t) {
            _Tab.live =>
              data.trips
                  .onDay(data.today)
                  .where((x) => x.status.isActive)
                  .length,
            _Tab.incidents => data.openIncidents.length,
            _Tab.tickets =>
              data.tickets
                  .where(
                    (x) =>
                        x.status == TicketStatus.open ||
                        x.status == TicketStatus.inProgress,
                  )
                  .length,
          },
        ),
        const SizedBox(height: AppSpace.md),
        switch (_tab) {
          _Tab.live => _live(data),
          _Tab.incidents => _incidents(data),
          _Tab.tickets => _tickets(data),
        },
      ],
    );
  }

  Widget _live(DataView data) {
    final loc = ref.watch(locationServiceProvider);
    final trips =
        data.trips
            .onDay(data.today)
            .where(
              (x) => !x.status.isTerminal || x.status == TripStatus.completed,
            )
            .toList()
          ..sort((a, b) {
            int rank(Trip x) => x.status == TripStatus.needsAttention
                ? 0
                : x.status == TripStatus.delayed
                ? 1
                : x.status.isActive
                ? 2
                : x.status.isUpcoming
                ? 3
                : 4;
            final r = rank(a) - rank(b);
            return r != 0 ? r : a.scheduledStart.compareTo(b.scheduledStart);
          });
    final out = data.vehicles
        .where(
          (v) =>
              v.status == VehicleStatus.maintenance ||
              v.status == VehicleStatus.unavailable,
        )
        .toList();
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InlineBanner(
          tone: data.traffic.normal ? StatusTone.neutral : StatusTone.warning,
          icon: Icons.traffic_outlined,
          title: 'Traffic: ${data.traffic.label}',
          message:
              '${DemoLabels.trafficSimulated} ${data.routeRevisions.where((r) => r.status == RevisionStatus.proposed).length} revision proposal(s) open.',
          actions: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: () => context.go('/fleet/traffic'),
              child: const Text('Traffic & Movement'),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        if (out.isNotEmpty) ...[
          InlineBanner(
            tone: StatusTone.warning,
            title:
                '${out.length} vehicle${out.length == 1 ? '' : 's'} out of service',
            messages: [
              for (final v in out)
                'Vehicle ${v.vehicleCode}: ${v.status.label}${v.notes.isNotEmpty ? ' — ${v.notes}' : ''}',
            ],
          ),
          const SizedBox(height: AppSpace.md),
        ],
        if (trips.isEmpty)
          const AppCard(
            child: EmptyState(
              icon: Icons.event_busy_outlined,
              title: 'No trips today',
              message: 'Nothing to monitor yet.',
              compact: true,
            ),
          )
        else
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 1100 ? 3 : (c.maxWidth >= 700 ? 2 : 1);
              final w = (c.maxWidth - (cols - 1) * AppSpace.sm) / cols;
              return Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final trip in trips)
                    SizedBox(
                      width: w,
                      child: AppCard(
                        onTap: () =>
                            context.go('/fleet/dispatch/trip/${trip.id}'),
                        padding: const EdgeInsets.all(AppSpace.md),
                        borderColor: trip.status == TripStatus.needsAttention
                            ? AppColors.danger.withValues(alpha: 0.5)
                            : trip.status == TripStatus.delayed
                            ? AppColors.warning.withValues(alpha: 0.5)
                            : AppColors.border,
                        child: _liveCard(data, trip, loc.positionOf(trip), t),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _liveCard(
    DataView data,
    Trip trip,
    SimulatedPosition pos,
    TextTheme t,
  ) {
    final stops = data.trips.stopsOf(trip);
    final done = stops.where((s) => s.isDone).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(trip.tripCode, style: t.titleSmall)),
            TripStatusBadge(trip.status, dense: true),
          ],
        ),
        Text(
          '${driverShort(data.driver(trip.assignedDriverId))} · ${trip.assignedVehicleId == null ? 'No vehicle' : 'Vehicle ${trip.assignedVehicleId}'}',
          style: AppText.muted(context),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpace.sm),
        ProgressStat(
          label:
              'Stops ${Fmt.time(trip.actualStart ?? trip.scheduledStart)} → ${Fmt.time(trip.scheduledArrival)}',
          value: stops.isEmpty ? 0 : done / stops.length,
          valueLabel: '$done/${stops.length}',
          color: AppColors.teal,
        ),
        const SizedBox(height: AppSpace.xs),
        Text(
          'Passengers: ${trip.boardedPassengerIds.length} boarded · ${trip.alightedPassengerIds.length} dropped · ${trip.noShowPassengerIds.length} no-show of ${trip.employeeIds.length}',
          style: t.bodySmall,
        ),
        if (pos.available) ...[
          const SizedBox(height: AppSpace.xs),
          Row(
            children: [
              Icon(
                pos.isStale
                    ? Icons.gps_not_fixed_rounded
                    : Icons.my_location_outlined,
                size: 14,
                color: pos.isStale ? AppColors.warning : AppColors.textMuted,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${pos.label} · demo update ${Fmt.time(pos.lastUpdate)}${pos.isStale ? ' · may be outdated' : ''}',
                  style: t.bodySmall!.copyWith(
                    color: pos.isStale
                        ? AppColors.warning
                        : AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ] else if (trip.status.isUpcoming)
          Text(
            'Not started · no simulated position yet',
            style: AppText.muted(context),
          ),
        if (trip.delayReason != null &&
            (trip.status == TripStatus.delayed ||
                trip.status == TripStatus.needsAttention)) ...[
          const SizedBox(height: AppSpace.xs),
          Text(
            trip.delayReason!,
            style: t.bodySmall!.copyWith(color: AppColors.warning),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (trip.isAssigned && !trip.status.isTerminal)
          Builder(
            builder: (context) {
              final ts = ref.read(servicesProvider).traffic.statusOf(trip);
              if (!ts.available) {
                return Text('Traffic: no data', style: AppText.muted(context));
              }
              final late = ts.delayMinutes > 0;
              return Padding(
                padding: const EdgeInsets.only(top: AppSpace.xs),
                child: Row(
                  children: [
                    Icon(
                      Icons.traffic_outlined,
                      size: 14,
                      color: late ? AppColors.warning : AppColors.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Traffic (simulated): ${ts.statusLabel}${ts.delayMinutes != 0 ? ' · ${late ? '+' : ''}${ts.delayMinutes} min' : ''} · ETA ${Fmt.time(ts.estimatedFinal)}',
                        style: t.bodySmall!.copyWith(
                          color: late ? AppColors.warning : AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _incidents(DataView data) {
    final t = Theme.of(context).textTheme;
    final list =
        data.incidents.where((i) {
          final f = switch (_incFilter) {
            _IncFilter.open => i.status.isOpen,
            _IncFilter.all => true,
            _IncFilter.resolved => i.status == IncidentStatus.resolvedDemo,
          };
          return f && (_type == null || i.type == _type);
        }).toList()..sort((a, b) {
          if (a.isSos != b.isSos) return a.isSos ? -1 : 1;
          if (a.status.isOpen != b.status.isOpen) {
            return a.status.isOpen ? -1 : 1;
          }
          return b.createdAt.compareTo(a.createdAt);
        });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpace.md,
          runSpacing: AppSpace.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterChipBar<_IncFilter>(
              options: _IncFilter.values,
              selected: _incFilter,
              onSelected: (f) => setState(() => _incFilter = f),
              labelOf: (f) => f.name[0].toUpperCase() + f.name.substring(1),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<IncidentType?>(
                isExpanded: true,
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All types')),
                  for (final x in IncidentType.values)
                    DropdownMenuItem(value: x, child: Text(x.label)),
                ],
                onChanged: (v) => setState(() => _type = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        AdaptiveTable<Incident>(
          rows: list,
          onRowTap: (i) => context.go('/fleet/monitoring/incident/${i.id}'),
          empty: EmptyState(
            icon: Icons.verified_outlined,
            title: 'No incidents match',
            message: 'Driver reports, breakdowns and SOS records appear here.',
            actionLabel: 'Show all',
            onAction: () => setState(() {
              _incFilter = _IncFilter.all;
              _type = null;
            }),
            compact: true,
          ),
          columns: [
            TableCol(
              'Ref',
              (i) => Row(
                children: [
                  if (i.isSos)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(
                        Icons.sos_rounded,
                        color: AppColors.danger,
                        size: 18,
                      ),
                    ),
                  Flexible(child: Text(i.reference, style: t.titleSmall)),
                ],
              ),
              flex: 2,
            ),
            TableCol('Type', (i) => Text(i.type.label), flex: 2),
            TableCol(
              'Description',
              (i) => Text(
                i.isSos && data.sosDispatchesOf(i.id).isNotEmpty
                    ? '${i.description} · chain ${data.sosDispatchesOf(i.id).where((d) => d.status == SosDispatchStatus.acknowledged).length}/${data.sosDispatchesOf(i.id).length} acknowledged'
                    : i.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              flex: 5,
            ),
            TableCol('Trip', (i) => Text(i.tripId ?? '—'), flex: 2),
            TableCol(
              'Reported',
              (i) => Text(Fmt.ago(i.createdAt, data.now)),
              flex: 2,
            ),
            TableCol(
              'Severity',
              (i) => StatusBadge(
                i.severity.label,
                tone: Tones.severity(i.severity),
                dense: true,
              ),
              flex: 2,
            ),
            TableCol(
              'Status',
              (i) => StatusBadge(
                i.status.label,
                tone: Tones.incident(i.status),
                dense: true,
              ),
              flex: 3,
              numeric: true,
            ),
          ],
          mobileCard: (i) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (i.isSos)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(
                        Icons.sos_rounded,
                        color: AppColors.danger,
                        size: 18,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      '${i.reference} · ${i.type.label}',
                      style: t.titleSmall,
                    ),
                  ),
                  StatusBadge(
                    i.status.label,
                    tone: Tones.incident(i.status),
                    dense: true,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                i.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.bodySmall,
              ),
              Text(
                '${i.severity.label} · ${Fmt.ago(i.createdAt, data.now)}${i.tripId != null ? ' · ${i.tripId}' : ''}',
                style: AppText.muted(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tickets(DataView data) {
    final t = Theme.of(context).textTheme;
    final s = ref.read(servicesProvider).support;
    Future<void> setStatus(SupportTicket k, TicketStatus st) async {
      String? response;
      if (st == TicketStatus.resolved) {
        final r = await showReasonDialog(
          context,
          title: 'Resolve ${k.reference}',
          label: 'Response to ${k.createdById}',
          confirmLabel: 'Resolve',
        );
        if (r == null) return;
        response = r.reason;
      }
      final res = await s.updateStatus(k.id, st, response: response);
      if (mounted) {
        await showResult(
          context,
          res,
          successMessage: '${k.reference} ${st.label.toLowerCase()}',
        );
      }
    }

    return AdaptiveTable<SupportTicket>(
      rows: data.tickets,
      empty: const EmptyState(
        icon: Icons.support_agent_outlined,
        title: 'No tickets',
        message: 'Employee and driver support tickets appear here.',
        compact: true,
      ),
      columns: [
        TableCol('Ref', (k) => Text(k.reference, style: t.titleSmall), flex: 2),
        TableCol(
          'From',
          (k) => Text('${k.createdByRole.label} ${k.createdById}'),
          flex: 3,
        ),
        TableCol(
          'Subject',
          (k) => Text(k.subject, maxLines: 1, overflow: TextOverflow.ellipsis),
          flex: 5,
        ),
        TableCol('Category', (k) => Text(k.category.label), flex: 2),
        TableCol(
          'Status',
          (k) => StatusBadge(
            k.status.label,
            tone: Tones.ticket(k.status),
            dense: true,
          ),
          flex: 2,
        ),
        TableCol('', (k) => _ticketMenu(k, setStatus), flex: 1, numeric: true),
      ],
      mobileCard: (k) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${k.reference} · ${k.subject}', style: t.titleSmall),
                Text(
                  '${k.createdByRole.label} ${k.createdById} · ${k.category.label}',
                  style: AppText.muted(context),
                ),
                const SizedBox(height: 4),
                StatusBadge(
                  k.status.label,
                  tone: Tones.ticket(k.status),
                  dense: true,
                ),
              ],
            ),
          ),
          _ticketMenu(k, setStatus),
        ],
      ),
    );
  }

  Widget _ticketMenu(
    SupportTicket k,
    Future<void> Function(SupportTicket, TicketStatus) setStatus,
  ) => PopupMenuButton<TicketStatus>(
    tooltip: 'Update ${k.reference}',
    icon: const Icon(Icons.more_horiz_rounded),
    onSelected: (st) => setStatus(k, st),
    itemBuilder: (c) => [
      for (final st in TicketStatus.values)
        if (st != k.status)
          PopupMenuItem(
            value: st,
            child: Text('Mark ${st.label.toLowerCase()}'),
          ),
    ],
  );
}

class IncidentDetailPage extends ConsumerWidget {
  const IncidentDetailPage({super.key, required this.incidentId});
  final String incidentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final inc = data.incident(incidentId);
    if (inc == null) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Incident not found',
        message: 'It may have been removed by a demo reset.',
        actionLabel: 'Incident queue',
        onAction: () => context.go('/fleet/monitoring?tab=incidents'),
      );
    }
    final t = Theme.of(context).textTheme;
    final trip = data.trips.byId(inc.tripId);
    final vehicle = data.vehicle(inc.vehicleId);
    final s = ref.read(servicesProvider).incidents;

    Future<void> resolve() async {
      final res = await showDialog<(String, bool)>(
        context: context,
        builder: (c) => _ResolveDialog(incident: inc, vehicle: vehicle),
      );
      if (res == null || !context.mounted) return;
      await runAndShow(
        context,
        s.setStatus(
          inc.id,
          IncidentStatus.resolvedDemo,
          notes: res.$1,
          restoreVehicle: res.$2,
        ),
      );
    }

    return AdminPage(
      title: '${inc.isSos ? 'SOS · ' : ''}${inc.reference} · ${inc.type.label}',
      subtitle:
          'Reported ${Fmt.dateTime(inc.createdAt)} by ${inc.reportedByRole.label} ${inc.reportedById ?? ''}',
      actions: [
        TextButton.icon(
          onPressed: () => context.go('/fleet/monitoring?tab=incidents'),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Queue'),
        ),
        if (inc.status == IncidentStatus.submittedDemo)
          OutlinedButton.icon(
            onPressed: () async => runAndShow(
              context,
              s.setStatus(
                inc.id,
                IncidentStatus.acknowledgedDemo,
                notes: 'Acknowledged by Fleet Manager (demo).',
              ),
            ),
            icon: const Icon(Icons.done_rounded),
            label: const Text('Acknowledge'),
          ),
        if (inc.status.isOpen)
          FilledButton.icon(
            onPressed: resolve,
            icon: const Icon(Icons.task_alt_rounded),
            label: const Text('Resolve'),
          ),
      ],
      children: [
        InlineBanner(
          tone: inc.isSos ? StatusTone.danger : StatusTone.info,
          title: inc.isSos ? 'SOS record (demo only)' : 'Local demo record',
          message: inc.isSos
              ? '${DemoLabels.sosDemo} ${DemoLabels.sosAlternative}'
              : DemoLabels.incidentDemo,
        ),
        const SizedBox(height: AppSpace.md),
        ResponsiveSplit(
          left: PanelCard(
            title: 'Details',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    StatusBadge(
                      inc.status.label,
                      tone: Tones.incident(inc.status),
                    ),
                    StatusBadge(
                      'Severity: ${inc.severity.label}',
                      tone: Tones.severity(inc.severity),
                    ),
                    if (inc.replacementRequested)
                      const StatusBadge(
                        'Replacement requested',
                        tone: StatusTone.warning,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
                Text(inc.description, style: t.bodyLarge),
                const SizedBox(height: AppSpace.sm),
                KeyValueRow(
                  label: 'Location (simulated)',
                  value: inc.demoLocationLabel ?? '—',
                ),
                KeyValueRow(
                  label: 'Driver',
                  value: driverShort(data.driver(inc.driverId)),
                ),
                KeyValueRow(
                  label: 'Vehicle',
                  value: vehicle == null
                      ? '—'
                      : '${vehicleShort(vehicle)} · ${vehicle.status.label}',
                ),
                KeyValueRow(
                  label: 'Updated',
                  value: Fmt.dateTime(inc.updatedAt),
                ),
                if (inc.resolutionNotes != null)
                  KeyValueRow(label: 'Notes', value: inc.resolutionNotes),
              ],
            ),
          ),
          right: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (inc.isSos) ...[
                PanelCard(
                  title: 'SOS escalation chain',
                  subtitle:
                      'Acknowledge in-app alerts; external services are never contacted',
                  child: SosChainView(incidentId: inc.id),
                ),
                const SizedBox(height: AppSpace.md),
              ],
              PanelCard(
                title: 'Linked trip',
                child: trip == null
                    ? Text(
                        'Not linked to a trip.',
                        style: AppText.muted(context),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TripRowTile(
                            trip: trip,
                            onTap: () =>
                                context.go('/fleet/dispatch/trip/${trip.id}'),
                          ),
                          if (trip.status.isUpcoming ||
                              trip.status == TripStatus.needsAttention ||
                              trip.status.isActive) ...[
                            const SizedBox(height: AppSpace.sm),
                            FilledButton.icon(
                              onPressed: () => context.go(
                                '/fleet/dispatch/trip/${trip.id}?reassign=1',
                              ),
                              icon: const Icon(Icons.swap_horiz_rounded),
                              label: const Text('Reassign vehicle / driver'),
                            ),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: AppSpace.md),
              PanelCard(
                title: 'Audit',
                child: Column(
                  children: [
                    for (final a in data.auditFor('incident', inc.id))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(a.summary),
                        subtitle: Text(
                          '${Fmt.dateTime(a.timestamp)} · ${a.actorRole.label}',
                        ),
                      ),
                    if (data.auditFor('incident', inc.id).isEmpty)
                      Text('No audit events.', style: AppText.muted(context)),
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

class _ResolveDialog extends StatefulWidget {
  const _ResolveDialog({required this.incident, this.vehicle});
  final Incident incident;
  final Vehicle? vehicle;

  @override
  State<_ResolveDialog> createState() => _ResolveDialogState();
}

class _ResolveDialogState extends State<_ResolveDialog> {
  final _notes = TextEditingController();
  late bool _restore = widget.vehicle?.status == VehicleStatus.maintenance;
  String? _error;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vehicle;
    return AlertDialog(
      title: Text('Resolve ${widget.incident.reference}'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 4,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Resolution notes',
                errorText: _error,
                alignLabelWithHint: true,
              ),
            ),
            if (v != null && v.status == VehicleStatus.maintenance)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _restore,
                onChanged: (x) => setState(() => _restore = x ?? false),
                title: Text('Return Vehicle ${v.vehicleCode} to service'),
                subtitle: const Text('Only if the defect is fixed.'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_notes.text.trim().length < 5) {
              setState(() => _error = 'Enter at least 5 characters');
              return;
            }
            Navigator.pop(context, (_notes.text.trim(), _restore));
          },
          child: const Text('Resolve'),
        ),
      ],
    );
  }
}
