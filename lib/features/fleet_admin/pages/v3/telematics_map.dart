import 'package:flutter/material.dart';

import '../../../../core/widgets/widgets.dart';
import '../../../../domain/models/models.dart';

/// One vehicle marker on the telematics map.
class VehicleMarker {
  const VehicleMarker({
    required this.code,
    required this.x,
    required this.y,
    required this.moving,
    required this.alert,
  });
  final String code;
  final double x;
  final double y;
  final bool moving;
  final bool alert;
}

/// Schematic fleet map: geofence circles, active-trip route corridors and
/// simulated vehicle positions on the fictional demo plane (km).
class TelematicsMap extends StatelessWidget {
  const TelematicsMap({
    super.key,
    required this.vehicles,
    required this.geofences,
    required this.corridors,
    required this.corridorKm,
    this.height = 380,
  });

  final List<VehicleMarker> vehicles;
  final List<Geofence> geofences;

  /// Polylines (stop coordinates) of active trips.
  final List<List<Offset>> corridors;
  final double corridorKm;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          image: true,
          label:
              'Schematic fleet map with ${vehicles.length} vehicles and ${geofences.length} geofences. Simulated positions.',
          child: ClipRRect(
            borderRadius: AppRadius.mdAll,
            child: Container(
              height: height,
              width: double.infinity,
              color: const Color(0xFFF2F6FB),
              child: CustomPaint(
                painter: _Painter(
                  vehicles,
                  geofences,
                  corridors,
                  corridorKm,
                  Theme.of(context).textTheme.labelSmall!,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: AppSpace.md,
          runSpacing: 4,
          children: const [
            _Legend(color: AppColors.teal, label: 'Moving'),
            _Legend(color: AppColors.deepNavy, label: 'Stopped / parked'),
            _Legend(color: AppColors.danger, label: 'Open alert'),
            _Legend(color: AppColors.primary, label: 'Service area'),
            _Legend(color: AppColors.warning, label: 'Restricted zone'),
          ],
        ),
        const SizedBox(height: 4),
        const SimulatedNote(
          '${DemoLabels.fictionalCoordinates} · schematic, not a real map',
          icon: Icons.map_outlined,
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(label, style: AppText.muted(context)),
    ],
  );
}

class _Painter extends CustomPainter {
  _Painter(
    this.vehicles,
    this.geofences,
    this.corridors,
    this.corridorKm,
    this.labelStyle,
  );
  final List<VehicleMarker> vehicles;
  final List<Geofence> geofences;
  final List<List<Offset>> corridors;
  final double corridorKm;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFFE3EAF3)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    // Fit the demo plane 0–40 km (plus any geofence extent).
    var minX = 0.0, maxX = 40.0, minY = 0.0, maxY = 32.0;
    for (final g in geofences.where(
      (g) => g.kind != GeofenceKind.routeCorridor,
    )) {
      minX = minX < g.centerX - g.radiusKm ? minX : g.centerX - g.radiusKm;
      maxX = maxX > g.centerX + g.radiusKm ? maxX : g.centerX + g.radiusKm;
      minY = minY < g.centerY - g.radiusKm ? minY : g.centerY - g.radiusKm;
      maxY = maxY > g.centerY + g.radiusKm ? maxY : g.centerY + g.radiusKm;
    }
    const pad = 16.0;
    final s = [
      (size.width - pad * 2) / (maxX - minX),
      (size.height - pad * 2) / (maxY - minY),
    ].reduce((a, b) => a < b ? a : b);
    final ox = (size.width - (maxX - minX) * s) / 2;
    final oy = (size.height - (maxY - minY) * s) / 2;
    Offset map(double x, double y) =>
        Offset(ox + (x - minX) * s, size.height - (oy + (y - minY) * s));

    for (final g in geofences.where(
      (g) => g.active && g.kind != GeofenceKind.routeCorridor,
    )) {
      final c = g.kind == GeofenceKind.restrictedZone
          ? AppColors.warning
          : AppColors.primary;
      final center = map(g.centerX, g.centerY);
      canvas.drawCircle(
        center,
        g.radiusKm * s,
        Paint()..color = c.withValues(alpha: 0.07),
      );
      canvas.drawCircle(
        center,
        g.radiusKm * s,
        Paint()
          ..color = c.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      _label(
        canvas,
        size,
        g.name,
        center + Offset(-20, -g.radiusKm * s - 14),
        c,
      );
    }
    // Route corridors: wide translucent band + centre line.
    for (final line in corridors.where((l) => l.length > 1)) {
      final p = Path()
        ..moveTo(
          map(line.first.dx, line.first.dy).dx,
          map(line.first.dx, line.first.dy).dy,
        );
      for (final o in line.skip(1)) {
        final m = map(o.dx, o.dy);
        p.lineTo(m.dx, m.dy);
      }
      canvas.drawPath(
        p,
        Paint()
          ..color = AppColors.teal.withValues(alpha: 0.12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = (corridorKm * 2 * s).clamp(4, 60)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawPath(
        p,
        Paint()
          ..color = AppColors.teal.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    for (final v in vehicles) {
      final o = map(v.x, v.y);
      final c = v.alert
          ? AppColors.danger
          : (v.moving ? AppColors.teal : AppColors.deepNavy);
      canvas.drawCircle(o, 12, Paint()..color = c.withValues(alpha: 0.18));
      canvas.drawCircle(o, 7, Paint()..color = Colors.white);
      canvas.drawCircle(o, 5.5, Paint()..color = c);
      _label(canvas, size, 'Vehicle ${v.code}', o + const Offset(10, -16), c);
    }
  }

  void _label(Canvas canvas, Size size, String text, Offset at, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: labelStyle.copyWith(color: color, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 120);
    final dx = at.dx.clamp(0.0, size.width - tp.width - 2);
    final dy = at.dy.clamp(0.0, size.height - tp.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(dx - 3, dy - 1, tp.width + 6, tp.height + 2),
        const Radius.circular(4),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(covariant _Painter old) => true;
}
