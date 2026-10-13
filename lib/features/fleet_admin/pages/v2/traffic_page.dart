import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../domain/models/models.dart';
import '../../../shared/traffic_board.dart';

/// Traffic & movement: simulated scenario, trip impact, revision proposals
/// (shared board) and the full revision history.
class TrafficPage extends ConsumerStatefulWidget {
  const TrafficPage({super.key});

  @override
  ConsumerState<TrafficPage> createState() => _TrafficPageState();
}

class _TrafficPageState extends ConsumerState<TrafficPage> {
  RevisionStatus? _status;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final t = Theme.of(context).textTheme;
    final revisions =
        data.routeRevisions
            .where((r) => _status == null || r.status == _status)
            .toList()
          ..sort((a, b) {
            final c = b.createdAt.compareTo(a.createdAt);
            return c != 0 ? c : b.id.compareTo(a.id);
          });
    return AdminPage(
      title: 'Traffic & movement',
      subtitle:
          'Demo traffic scenario → schedule impact → reviewed revisions. Completed stops and boarding events are never changed.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => context.go('/fleet/monitoring'),
          icon: const Icon(Icons.monitor_heart_outlined),
          label: const Text('Live board'),
        ),
      ],
      children: [
        TrafficBoard(
          onOpenTrip: (trip) => context.go('/fleet/dispatch/trip/${trip.id}'),
        ),
        const SizedBox(height: AppSpace.xl),
        AppCard(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                title: 'Revision history',
                subtitle:
                    '${data.routeRevisions.length} revision${data.routeRevisions.length == 1 ? '' : 's'} · completed stops are never changed',
              ),
              const SizedBox(height: AppSpace.sm),
              FilterChipBar<RevisionStatus?>(
                options: [null, ...RevisionStatus.values],
                selected: _status,
                onSelected: (s) => setState(() => _status = s),
                labelOf: (s) => s?.label ?? 'All',
                countOf: (s) => s == null
                    ? data.routeRevisions.length
                    : data.routeRevisions.where((r) => r.status == s).length,
              ),
              const SizedBox(height: AppSpace.sm),
              AdaptiveTable<RouteRevision>(
                rows: revisions,
                onRowTap: (r) => context.go('/fleet/dispatch/trip/${r.tripId}'),
                empty: const EmptyState(
                  icon: Icons.history_toggle_off_rounded,
                  title: 'No revisions',
                  message:
                      'Change the simulated traffic scenario to generate schedule proposals for affected trips.',
                  compact: true,
                ),
                columns: [
                  TableCol(
                    'Revision',
                    (r) => Text(r.id, style: t.titleSmall),
                    flex: 2,
                  ),
                  TableCol(
                    'Trip',
                    (r) =>
                        Text(data.trips.byId(r.tripId)?.tripCode ?? r.tripId),
                    flex: 2,
                  ),
                  TableCol(
                    'Scenario',
                    (r) => Text(
                      r.scenarioLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    flex: 3,
                  ),
                  TableCol(
                    'Departure',
                    (r) => Text(
                      '${Fmt.time(r.previousDeparture)} → ${Fmt.time(r.proposedDeparture)}',
                    ),
                    flex: 3,
                  ),
                  TableCol(
                    'Delay',
                    (r) => Text(
                      '${r.delayMinutes > 0 ? '+' : ''}${r.delayMinutes} min',
                    ),
                    flex: 1,
                    numeric: true,
                  ),
                  TableCol(
                    'Feasible',
                    (r) => Text(r.feasible ? 'Yes' : 'No'),
                    flex: 1,
                  ),
                  TableCol(
                    'Created',
                    (r) => Text(Fmt.dateTime(r.createdAt)),
                    flex: 3,
                  ),
                  TableCol(
                    'Status',
                    (r) => StatusBadge(
                      r.status.label,
                      tone: _tone(r.status),
                      dense: true,
                    ),
                    flex: 2,
                    numeric: true,
                  ),
                ],
                mobileCard: (r) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${r.id} · ${data.trips.byId(r.tripId)?.tripCode ?? r.tripId}',
                            style: t.titleSmall,
                          ),
                        ),
                        StatusBadge(
                          r.status.label,
                          tone: _tone(r.status),
                          dense: true,
                        ),
                      ],
                    ),
                    Text(
                      '${r.scenarioLabel} · depart ${Fmt.time(r.previousDeparture)} → ${Fmt.time(r.proposedDeparture)} · ${r.delayMinutes} min',
                      style: t.bodySmall,
                    ),
                    if (r.violations.isNotEmpty)
                      Text(
                        r.violations.join(' · '),
                        style: t.bodySmall!.copyWith(color: AppColors.danger),
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

  static StatusTone _tone(RevisionStatus s) => switch (s) {
    RevisionStatus.proposed => StatusTone.info,
    RevisionStatus.applied => StatusTone.success,
    RevisionStatus.dismissed => StatusTone.neutral,
    RevisionStatus.superseded => StatusTone.warning,
  };
}
