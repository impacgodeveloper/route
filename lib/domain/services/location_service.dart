import '../../data/repositories/repositories.dart';
import '../models/models.dart';

/// Simulated vehicle position derived from stop progress. NEVER a real GPS
/// fix; every consumer must show [DemoLabels.simulatedLocation].
class SimulatedPosition {
  const SimulatedPosition({
    required this.x,
    required this.y,
    required this.lastUpdate,
    required this.isStale,
    required this.available,
    required this.label,
    this.progressStopIndex = 0,
  });

  final double x;
  final double y;
  final DateTime? lastUpdate;
  final bool isStale;
  final bool available;
  final String label;
  final int progressStopIndex;

  static const unavailable = SimulatedPosition(
    x: 0,
    y: 0,
    lastUpdate: null,
    isStale: false,
    available: false,
    label: 'Position not available',
  );
}

/// Future integration point for a real map/tracking provider.
abstract interface class LocationService {
  SimulatedPosition positionOf(Trip trip);
}

/// Demo implementation: positions the vehicle between the last completed
/// stop and the next one according to elapsed time.
class DemoLocationService implements LocationService {
  DemoLocationService(
    this.view, {
    this.staleAfter = const Duration(minutes: 10),
  });
  final DataView view;
  final Duration staleAfter;

  @override
  SimulatedPosition positionOf(Trip trip) {
    if (!trip.status.isActive || trip.actualStart == null) {
      return SimulatedPosition.unavailable;
    }
    final stops = view.trips.stopsOf(trip);
    if (stops.isEmpty) return SimulatedPosition.unavailable;
    final locs = view.locationMap;
    final doneIdx = stops.lastIndexWhere(
      (s) => s.isDone || s.status == StopStatus.arrived,
    );
    final now = view.now;
    if (doneIdx < 0) {
      // Between depot and first stop.
      final first = locs[stops.first.locationId]!;
      return SimulatedPosition(
        x: first.demoX - 1.5,
        y: first.demoY - 1.0,
        lastUpdate: trip.actualStart,
        label: 'Heading to ${first.name}',
        isStale: now.difference(trip.actualStart!) > staleAfter,
        available: true,
        progressStopIndex: 0,
      );
    }
    final last = stops[doneIdx];
    final lastLoc = locs[last.locationId]!;
    final lastTime = last.departedAt ?? last.actualArrival ?? trip.actualStart!;
    if (last.status == StopStatus.arrived || doneIdx == stops.length - 1) {
      return SimulatedPosition(
        x: lastLoc.demoX,
        y: lastLoc.demoY,
        lastUpdate: lastTime,
        label: 'At ${lastLoc.name}',
        isStale: now.difference(lastTime) > staleAfter,
        available: true,
        progressStopIndex: doneIdx,
      );
    }
    final next = stops[doneIdx + 1];
    final nextLoc = locs[next.locationId]!;
    final legMinutes = next.plannedArrival
        .difference(last.plannedArrival)
        .inMinutes
        .clamp(1, 240);
    final f = (now.difference(lastTime).inMinutes / legMinutes).clamp(0.0, 0.9);
    return SimulatedPosition(
      x: lastLoc.demoX + (nextLoc.demoX - lastLoc.demoX) * f,
      y: lastLoc.demoY + (nextLoc.demoY - lastLoc.demoY) * f,
      lastUpdate: lastTime,
      label: 'Between ${lastLoc.code} and ${nextLoc.code}',
      isStale: now.difference(lastTime) > staleAfter,
      available: true,
      progressStopIndex: doneIdx,
    );
  }
}

/// Map adapter interface. The prototype renders a schematic route; a real
/// provider (e.g. Google Maps) would implement this with live tiles.
abstract interface class MapService {
  String get providerLabel;
  bool get isRealMap;
}

class SchematicMapService implements MapService {
  const SchematicMapService();
  @override
  String get providerLabel => 'Schematic (demo coordinates)';
  @override
  bool get isRealMap => false;
}
