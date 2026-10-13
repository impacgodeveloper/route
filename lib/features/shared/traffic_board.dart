import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';

/// Traffic & movement board.
/// * Fleet Manager: full control (scenario, apply/dismiss revisions).
/// * Employer Admin: read-only, scoped to [companyId].
/// All traffic is SIMULATED and labelled as such.
class TrafficBoard extends ConsumerStatefulWidget {
  const TrafficBoard({
    super.key,
    this.readOnly = false,
    this.companyId,
    this.onOpenTrip,
  });

  final bool readOnly;
  final String? companyId;
  final void Function(Trip trip)? onOpenTrip;

  @override
  ConsumerState<TrafficBoard> createState() => _TrafficBoardState();
}

class _TrafficBoardState extends ConsumerState<TrafficBoard> {
  TrafficLevel? _internal;
  TrafficLevel? _ring;
  bool _busy = false;

  Future<void> _apply({TrafficSource source = TrafficSource.simulated}) async {
    final state = ref.read(dataProvider).traffic;
    setState(() => _busy = true);
    final r = await ref
        .read(servicesProvider)
        .traffic
        .setScenario(
          internalRoads: _internal ?? state.internalRoads,
          ringRoad: _ring ?? state.ringRoad,
          source: source,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    final n = r.valueOrNull?.length ?? 0;
    await showResult(
      context,
      r,
      successMessage: source == TrafficSource.unavailable
          ? 'Traffic marked unavailable — planned schedule shown'
          : n == 0
          ? 'Scenario saved — no new schedule changes needed'
          : '$n trip(s) need review — proposals created',
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final services = ref.read(servicesProvider);
    final state = data.traffic;
    var board = services.traffic.board();
    if (widget.companyId != null) {
      board = board
          .where((s) => s.trip.employerId == widget.companyId)
          .toList();
    }
    final revisions = data.routeRevisions.where((r) {
      if (widget.companyId == null) return true;
      return data.trips.byId(r.tripId)?.employerId == widget.companyId;
    }).toList();
    final open = revisions
        .where((r) => r.status == RevisionStatus.proposed)
        .toList();
    final history = revisions
        .where((r) => r.status != RevisionStatus.proposed)
        .take(10)
        .toList();
    final t = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconTile(
                    icon: Icons.traffic_outlined,
                    color: state.available
                        ? (state.normal ? AppColors.success : AppColors.warning)
                        : AppColors.textMuted,
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(state.label, style: t.titleMedium),
                        Text(
                          'Source: ${state.source.label} · updated ${Fmt.ago(state.updatedAt, data.now)}',
                          style: AppText.muted(context),
                        ),
                      ],
                    ),
                  ),
                  StatusBadge(
                    state.available ? 'Simulated' : 'Unavailable',
                    tone: state.available
                        ? StatusTone.info
                        : StatusTone.neutral,
                  ),
                ],
              ),
              if (!widget.readOnly) ...[
                const SizedBox(height: AppSpace.md),
                const Divider(),
                const SizedBox(height: AppSpace.sm),
                Text('Demo traffic scenario', style: t.titleSmall),
                const SizedBox(height: AppSpace.xs),
                Wrap(
                  spacing: AppSpace.md,
                  runSpacing: AppSpace.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _levelPicker(
                      'Internal roads',
                      _internal ?? state.internalRoads,
                      (v) => setState(() => _internal = v),
                    ),
                    _levelPicker(
                      'Ring road',
                      _ring ?? state.ringRoad,
                      (v) => setState(() => _ring = v),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
                Wrap(
                  spacing: AppSpace.xs,
                  runSpacing: AppSpace.xs,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : () => _apply(),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Apply scenario & recalculate'),
                    ),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () {
                              setState(() {
                                _internal = TrafficLevel.free;
                                _ring = TrafficLevel.free;
                              });
                              _apply();
                            },
                      child: const Text('Reset to free-flowing'),
                    ),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _apply(source: TrafficSource.unavailable),
                      child: const Text('Simulate provider outage'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpace.sm),
              const SimulatedNote(
                DemoLabels.trafficSimulated,
                icon: Icons.science_outlined,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        SectionHeader(
          title: 'Trips on the road today',
          subtitle: '${board.length} assigned trip(s) not yet completed',
        ),
        const SizedBox(height: AppSpace.sm),
        if (board.isEmpty)
          const EmptyState(
            icon: Icons.directions_car_outlined,
            title: 'No active or upcoming trips today',
            message:
                'Assigned trips for today appear here with their traffic status.',
            compact: true,
          )
        else
          for (final s in board)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: _tripCard(context, data, s),
            ),
        const SizedBox(height: AppSpace.lg),
        SectionHeader(
          title: 'Proposed schedule changes',
          subtitle: widget.readOnly
              ? 'Decided by the Fleet Manager'
              : 'Review before applying — completed stops are never changed',
        ),
        const SizedBox(height: AppSpace.sm),
        if (open.isEmpty)
          const EmptyState(
            icon: Icons.check_circle_outline_rounded,
            title: 'No open proposals',
            message:
                'Traffic changes that affect schedules create proposals here.',
            compact: true,
          )
        else
          for (final r in open)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: _revisionCard(context, data, r),
            ),
        if (history.isNotEmpty) ...[
          const SizedBox(height: AppSpace.lg),
          const SectionHeader(title: 'Recent decisions'),
          const SizedBox(height: AppSpace.sm),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < history.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    title: Text(
                      '${history[i].id} · ${data.trips.byId(history[i].tripId)?.tripCode ?? history[i].tripId}',
                    ),
                    subtitle: Text(
                      '${history[i].scenarioLabel} · ${Fmt.dateTime(history[i].appliedAt ?? history[i].createdAt)}',
                    ),
                    trailing: StatusBadge(
                      history[i].status.label,
                      tone: history[i].status == RevisionStatus.applied
                          ? StatusTone.success
                          : StatusTone.neutral,
                      dense: true,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _levelPicker(
    String label,
    TrafficLevel value,
    ValueChanged<TrafficLevel> onChanged,
  ) => SizedBox(
    width: 220,
    child: DropdownButtonFormField<TrafficLevel>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: [
        for (final l in TrafficLevel.values)
          DropdownMenuItem(
            value: l,
            child: Text(
              '${l.label} (×${l.factor})',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (v) => v == null ? null : onChanged(v),
    ),
  );

  StatusTone _tone(TrafficTripStatus s) => !s.available
      ? StatusTone.neutral
      : !s.feasible
      ? StatusTone.danger
      : s.recalculationRecommended
      ? StatusTone.warning
      : StatusTone.success;

  Widget _tripCard(BuildContext context, DataView data, TrafficTripStatus s) {
    final t = Theme.of(context).textTheme;
    final v = data.vehicle(s.trip.assignedVehicleId);
    final d = data.driver(s.trip.assignedDriverId);
    final next = s.nextStop;
    final pos = ref.read(locationServiceProvider).positionOf(s.trip);
    return AppCard(
      onTap: widget.onOpenTrip == null
          ? null
          : () => widget.onOpenTrip!(s.trip),
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${s.trip.tripCode} · ${data.trips.routeOf(s.trip)?.routeCode ?? '—'}',
                  style: t.titleSmall,
                ),
              ),
              StatusBadge(s.statusLabel, tone: _tone(s), dense: true),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Vehicle ${v?.vehicleCode ?? '—'} · ${d?.name ?? '—'} · ${s.started ? 'on the road' : 'departs ${Fmt.time(s.trip.scheduledStart)}'}',
            style: AppText.secondary(context),
          ),
          const SizedBox(height: AppSpace.xs),
          Wrap(
            spacing: AppSpace.lg,
            runSpacing: 4,
            children: [
              _kv(
                context,
                'Next stop',
                next == null
                    ? '—'
                    : '${data.location(next.locationId)?.code} · ${Fmt.time(s.proposedTimes[next.id] ?? next.plannedArrival)}',
              ),
              _kv(context, 'Planned arrival', Fmt.time(s.plannedFinal)),
              _kv(context, 'Estimated arrival', Fmt.time(s.estimatedFinal)),
              _kv(
                context,
                'Delay',
                s.available
                    ? '${s.delayMinutes >= 0 ? '+' : ''}${s.delayMinutes} min'
                    : '—',
              ),
              _kv(context, 'Affected stops', '${s.affectedStopIds.length}'),
              _kv(
                context,
                'Position',
                pos.available
                    ? '${pos.label} (simulated, ${Fmt.ago(pos.lastUpdate ?? data.now, data.now)})'
                    : 'Not started',
              ),
            ],
          ),
          if (s.violations.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            InlineBanner(
              tone: StatusTone.danger,
              title: 'Hard deadline at risk',
              messages: s.violations,
            ),
          ],
          const SizedBox(height: AppSpace.xs),
          Text(
            s.recommendation,
            style: t.bodySmall!.copyWith(color: AppColors.textSecondary),
          ),
          if (pos.available && pos.isStale)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: SimulatedNote(
                'Last simulated position update may be outdated.',
                icon: Icons.schedule_rounded,
              ),
            ),
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(k, style: AppText.muted(context)),
      Text(v, style: Theme.of(context).textTheme.labelMedium),
    ],
  );

  Widget _revisionCard(BuildContext context, DataView data, RouteRevision r) {
    final t = Theme.of(context).textTheme;
    final trip = data.trips.byId(r.tripId);
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      borderColor: r.feasible
          ? AppColors.border
          : AppColors.danger.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${r.id} · ${trip?.tripCode ?? r.tripId}',
                  style: t.titleSmall,
                ),
              ),
              StatusBadge(
                r.feasible ? 'Feasible' : 'Infeasible',
                tone: r.feasible ? StatusTone.success : StatusTone.danger,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${r.reason} ${r.recommendation}',
            style: AppText.secondary(context),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            'Departure ${Fmt.time(r.previousDeparture)} → ${Fmt.time(r.proposedDeparture)} · arrival change ${r.delayMinutes >= 0 ? '+' : ''}${r.delayMinutes} min',
            style: t.labelMedium,
          ),
          const SizedBox(height: AppSpace.xs),
          for (final s in r.stops)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      data.location(s.locationId)?.code ?? s.locationId,
                      style: t.bodySmall,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      s.locked
                          ? '${Fmt.time(s.previous)} (done — unchanged)'
                          : '${Fmt.time(s.previous)} → ${Fmt.time(s.proposed)}  (${s.shiftMinutes >= 0 ? '+' : ''}${s.shiftMinutes} min)',
                      style: t.bodySmall!.copyWith(
                        color: s.locked
                            ? AppColors.textMuted
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (r.outsideToleranceEmployeeIds.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            InlineBanner(
              tone: StatusTone.warning,
              title: 'Outside pickup tolerance',
              message:
                  '${r.outsideToleranceEmployeeIds.join(', ')} — pickup moves beyond their ± window; they will be notified on apply.',
            ),
          ],
          if (r.violations.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            InlineBanner(
              tone: StatusTone.danger,
              title: 'Deadline violations',
              messages: r.violations,
            ),
          ],
          if (!widget.readOnly) ...[
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.xs,
              runSpacing: AppSpace.xs,
              children: [
                FilledButton(
                  onPressed: () async {
                    final ok = await showConfirmDialog(
                      context,
                      title: 'Apply schedule change?',
                      message:
                          'Updates planned times for ${trip?.tripCode} (completed stops stay unchanged) and notifies the driver and passengers locally.',
                      confirmLabel: 'Apply',
                    );
                    if (!ok || !context.mounted) return;
                    final res = await ref
                        .read(servicesProvider)
                        .traffic
                        .applyRevision(r.id);
                    if (context.mounted) await showResult(context, res);
                  },
                  child: const Text('Apply'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    final reason = await showReasonDialog(
                      context,
                      title: 'Dismiss proposal',
                      confirmLabel: 'Dismiss',
                    );
                    if (reason == null || !context.mounted) return;
                    final res = await ref
                        .read(servicesProvider)
                        .traffic
                        .dismissRevision(r.id, reason.reason);
                    if (context.mounted) await showResult(context, res);
                  },
                  child: const Text('Dismiss'),
                ),
                if (trip != null && widget.onOpenTrip != null)
                  TextButton(
                    onPressed: () => widget.onOpenTrip!(trip),
                    child: const Text('Open trip / reassign'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
