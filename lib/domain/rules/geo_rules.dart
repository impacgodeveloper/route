import 'dart:math' as math;

import '../models/models.dart';

/// Distance/time model on the fictional schematic plane.
///
/// Locations carry demo coordinates in km. Road distance is approximated
/// as straight-line × a road factor. Speeds differ for ring roads (longer,
/// faster) vs internal roads (shorter, slower). This is a transparent demo
/// model — NOT live traffic or a real map service.
abstract final class GeoRules {
  static const roadFactor = 1.25;
  static const ringRoadDistanceFactor = 1.18;
  static const ringRoadSpeedKmh = 45.0;
  static const internalSpeedKmh = 30.0;
  static const boardingMinutesPerStop = 3;

  /// EV vs ICE operating cost (₹/km, demo assumptions).
  static const evCostPerKm = 7.5;
  static const iceCostPerKm = 13.0;
  static const hybridCostPerKm = 10.0;
  static const fixedCostPerVehicle = 250.0;

  static double straightKm(Location a, Location b) => math.sqrt(
    math.pow(a.demoX - b.demoX, 2) + math.pow(a.demoY - b.demoY, 2),
  );

  static double roadKm(Location a, Location b, RouteVariant v) {
    final base = straightKm(a, b) * roadFactor;
    return v == RouteVariant.ringRoad ? base * ringRoadDistanceFactor : base;
  }

  /// Demo traffic multiplier by hour (peak 8–10 and 17–20).
  static double trafficFactor(DateTime at, RouteVariant v) {
    final h = at.hour;
    final peak = (h >= 8 && h < 10) || (h >= 17 && h < 20);
    if (!peak) return 1.0;
    return v == RouteVariant.ringRoad ? 1.1 : 1.3;
  }

  /// [scenarioFactor] = simulated traffic multiplier (1.0 = baseline).
  static int travelMinutes(
    double km,
    RouteVariant v,
    DateTime at, {
    double scenarioFactor = 1.0,
  }) {
    final speed = v == RouteVariant.ringRoad
        ? ringRoadSpeedKmh
        : internalSpeedKmh;
    return (km / speed * 60 * trafficFactor(at, v) * scenarioFactor).ceil();
  }

  // ---- Fictional demo lat/lng <-> schematic plane (km) ----
  /// Origin of the fictional demo plane. Coordinates derived from it are
  /// demo values only and must always be labelled as fictional.
  static const originLat = 12.85;
  static const originLng = 77.50;
  static const kmPerDegLat = 110.57;
  static const kmPerDegLng = 108.5;

  static double latFromY(double y) =>
      double.parse((originLat + y / kmPerDegLat).toStringAsFixed(6));
  static double lngFromX(double x) =>
      double.parse((originLng + x / kmPerDegLng).toStringAsFixed(6));
  static double yFromLat(double lat) => (lat - originLat) * kmPerDegLat;
  static double xFromLng(double lng) => (lng - originLng) * kmPerDegLng;

  static bool validLat(double? v) => v != null && v >= -90 && v <= 90;
  static bool validLng(double? v) => v != null && v >= -180 && v <= 180;

  /// Effective fictional coordinates of a location.
  static (double lat, double lng) latLngOf(Location l) =>
      (l.latitude ?? latFromY(l.demoY), l.longitude ?? lngFromX(l.demoX));

  static double costPerKm(Propulsion p) => switch (p) {
    Propulsion.ev => evCostPerKm,
    Propulsion.ice => iceCostPerKm,
    Propulsion.hybrid => hybridCostPerKm,
  };

  static double pathKm(List<Location> path, RouteVariant v) {
    var total = 0.0;
    for (var i = 1; i < path.length; i++) {
      total += roadKm(path[i - 1], path[i], v);
    }
    return total;
  }
}
