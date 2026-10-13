import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/widgets.dart';
import '../../../domain/models/models.dart';
import 'fleet_common.dart';

/// Timeline + schematic map for planned (not yet persisted) stops.
class PlanPreview extends ConsumerWidget {
  const PlanPreview({
    super.key,
    required this.stops,
    this.showMap = true,
    this.mapHeight = 180,
  });
  final List<PlannedStop> stops;
  final bool showMap;
  final double mapHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final points = stopPoints(data, stops.map((s) => s.locationId).toList());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showMap) ...[
          SchematicMap(
            points: points,
            path: [for (var i = 0; i < points.length; i++) i],
            height: mapHeight,
          ),
          const SizedBox(height: AppSpace.md),
        ],
        RouteTimeline(
          stops: [
            for (final s in stops)
              TimelineStop(
                title: data.location(s.locationId)?.label ?? s.locationId,
                subtitle:
                    '${s.kind == StopKind.pickup ? 'Pick up' : 'Drop'} ${s.employeeIds.join(', ')}',
                kind: s.kind,
                status: StopStatus.upcoming,
                planned: s.plannedArrival,
              ),
          ],
        ),
      ],
    );
  }
}

/// Timeline + map for a persisted trip route with live stop states.
class TripRoutePreview extends ConsumerWidget {
  const TripRoutePreview({super.key, required this.trip, this.mapHeight = 200});
  final Trip trip;
  final double mapHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final stops = data.trips.stopsOf(trip);
    if (stops.isEmpty) {
      return const EmptyState(
        icon: Icons.route_outlined,
        title: 'No route yet',
        message: 'Assign employees to generate a route.',
        compact: true,
      );
    }
    final done = {
      for (var i = 0; i < stops.length; i++)
        if (stops[i].isDone) i,
    };
    final points = stopPoints(
      data,
      stops.map((s) => s.locationId).toList(),
      done: done,
    );
    final pos = ref.watch(locationServiceProvider).positionOf(trip);
    final current = data.trips.currentStop(trip);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SchematicMap(
          points: points,
          path: [for (var i = 0; i < points.length; i++) i],
          vehicle: pos.available ? Offset(pos.x, pos.y) : null,
          vehicleStale: pos.isStale,
          height: mapHeight,
        ),
        if (pos.available) ...[
          const SizedBox(height: 4),
          SimulatedNote(
            '${pos.label} · last demo update ${Fmt.time(pos.lastUpdate)}${pos.isStale ? ' — may be outdated' : ''}. ${DemoLabels.simulatedLocation}',
            icon: Icons.my_location_outlined,
          ),
        ],
        const SizedBox(height: AppSpace.md),
        RouteTimeline(
          stops: [
            for (final s in stops)
              TimelineStop(
                title: data.location(s.locationId)?.label ?? s.locationId,
                subtitle:
                    '${s.kind == StopKind.pickup ? 'Pick up' : 'Drop'} ${(s.kind == StopKind.pickup ? s.boardingEmployeeIds : s.alightingEmployeeIds).join(', ')}',
                kind: s.kind,
                status: s.status,
                planned: s.plannedArrival,
                actual: s.actualArrival,
                highlight: trip.status.isActive && current?.id == s.id,
                note: s.skipReason != null
                    ? 'Skipped: ${s.skipReason} (${s.skipAuthorizedBy})'
                    : s.issueNote,
              ),
          ],
        ),
      ],
    );
  }
}
