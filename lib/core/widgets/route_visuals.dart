import 'package:flutter/material.dart';

import '../../domain/models/models.dart';
import '../demo/demo_labels.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../utils/formatters.dart';
import 'states.dart';
import 'status_badge.dart';

/// Data for one row of [RouteTimeline].
class TimelineStop {
  const TimelineStop({
    required this.title,
    required this.subtitle,
    required this.kind,
    required this.status,
    required this.planned,
    this.actual,
    this.highlight = false,
    this.trailing,
    this.note,
  });

  final String title;
  final String subtitle;
  final StopKind kind;
  final StopStatus status;
  final DateTime planned;
  final DateTime? actual;
  final bool highlight;
  final Widget? trailing;
  final String? note;
}

/// Vertical stop timeline with planned/actual times.
class RouteTimeline extends StatelessWidget {
  const RouteTimeline({super.key, required this.stops, this.onTap});
  final List<TimelineStop> stops;
  final void Function(int index)? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      children: [
        for (var i = 0; i < stops.length; i++)
          _row(
            context,
            t,
            i,
            stops[i],
            first: i == 0,
            last: i == stops.length - 1,
          ),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    TextTheme t,
    int i,
    TimelineStop s, {
    required bool first,
    required bool last,
  }) {
    final done =
        s.status == StopStatus.completed || s.status == StopStatus.skipped;
    final color = switch (s.status) {
      StopStatus.completed => AppColors.success,
      StopStatus.arrived => AppColors.primary,
      StopStatus.skipped => AppColors.warning,
      StopStatus.issue => AppColors.danger,
      StopStatus.upcoming =>
        s.highlight ? AppColors.primary : const Color(0xFFB8C4D3),
    };
    return Semantics(
      label:
          'Stop ${i + 1}: ${s.title}, ${s.kind.label}, ${s.status.label}, planned ${Fmt.time(s.planned)}',
      child: InkWell(
        onTap: onTap == null ? null : () => onTap!(i),
        borderRadius: AppRadius.mdAll,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 28,
                child: Column(
                  children: [
                    Container(
                      width: 2,
                      height: 10,
                      color: first
                          ? Colors.transparent
                          : (done ? AppColors.success : AppColors.divider),
                    ),
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: done ? color : AppColors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: color, width: 2),
                      ),
                      child: done
                          ? Icon(
                              s.status == StopStatus.skipped
                                  ? Icons.redo_rounded
                                  : Icons.check_rounded,
                              size: 11,
                              color: Colors.white,
                            )
                          : (s.highlight
                                ? Center(
                                    child: Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  )
                                : null),
                    ),
                    Expanded(
                      child: Container(
                        width: 2,
                        color: last
                            ? Colors.transparent
                            : (done ? AppColors.success : AppColors.divider),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: AppSpace.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            s.kind == StopKind.pickup
                                ? Icons.person_pin_circle_outlined
                                : Icons.apartment_outlined,
                            size: 16,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              s.title,
                              style: t.titleSmall!.copyWith(
                                color: s.highlight ? AppColors.primary : null,
                              ),
                            ),
                          ),
                          Text(
                            Fmt.time(s.actual ?? s.planned),
                            style: t.labelMedium!.copyWith(
                              fontFeatures: AppText.tabular,
                              color: s.actual != null
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.subtitle,
                              style: t.bodySmall!.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          if (s.actual != null)
                            Text(
                              'planned ${Fmt.time(s.planned)}',
                              style: t.bodySmall!.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                        ],
                      ),
                      if (s.status != StopStatus.upcoming ||
                          s.trailing != null) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (s.status != StopStatus.upcoming)
                              StatusBadge(
                                s.status.label,
                                tone: Tones.stop(s.status),
                                dense: true,
                              ),
                            ?s.trailing,
                          ],
                        ),
                      ],
                      if (s.note != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          s.note!,
                          style: t.bodySmall!.copyWith(
                            color: AppColors.warning,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A point on the schematic map.
class MapPoint {
  const MapPoint({
    required this.x,
    required this.y,
    required this.label,
    this.kind = LocationType.pickup,
    this.emphasis = false,
    this.done = false,
  });
  final double x;
  final double y;
  final String label;
  final LocationType kind;
  final bool emphasis;
  final bool done;
}

/// Schematic route drawing on the fictional demo plane. Always labelled as
/// NOT a real map; positions are fictional demo coordinates.
class SchematicMap extends StatelessWidget {
  const SchematicMap({
    super.key,
    required this.points,
    this.path = const [],
    this.vehicle,
    this.vehicleStale = false,
    this.height = 220,
    this.showLabels = true,
    this.caption = DemoLabels.schematicMap,
  });

  final List<MapPoint> points;

  /// Ordered indices into [points] forming the route polyline.
  final List<int> path;
  final Offset? vehicle;
  final bool vehicleStale;
  final double height;
  final bool showLabels;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label:
              'Schematic route with ${points.length} points. ${DemoLabels.schematicMap}',
          image: true,
          child: ClipRRect(
            borderRadius: AppRadius.mdAll,
            child: Container(
              height: height,
              width: double.infinity,
              color: const Color(0xFFF2F6FB),
              child: CustomPaint(
                painter: _MapPainter(
                  points,
                  path,
                  vehicle,
                  vehicleStale,
                  showLabels,
                  Theme.of(context).textTheme.labelSmall!,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SimulatedNote(caption, icon: Icons.map_outlined),
      ],
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter(
    this.points,
    this.path,
    this.vehicle,
    this.stale,
    this.showLabels,
    this.labelStyle,
  );
  final List<MapPoint> points;
  final List<int> path;
  final Offset? vehicle;
  final bool stale;
  final bool showLabels;
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
    if (points.isEmpty) return;
    var minX = points.map((p) => p.x).reduce((a, b) => a < b ? a : b);
    var maxX = points.map((p) => p.x).reduce((a, b) => a > b ? a : b);
    var minY = points.map((p) => p.y).reduce((a, b) => a < b ? a : b);
    var maxY = points.map((p) => p.y).reduce((a, b) => a > b ? a : b);
    if (vehicle != null) {
      minX = minX < vehicle!.dx ? minX : vehicle!.dx;
      maxX = maxX > vehicle!.dx ? maxX : vehicle!.dx;
      minY = minY < vehicle!.dy ? minY : vehicle!.dy;
      maxY = maxY > vehicle!.dy ? maxY : vehicle!.dy;
    }
    final spanX = (maxX - minX).abs() < 1 ? 1.0 : maxX - minX;
    final spanY = (maxY - minY).abs() < 1 ? 1.0 : maxY - minY;
    const pad = 34.0;
    final sx = (size.width - pad * 2) / spanX;
    final sy = (size.height - pad * 2) / spanY;
    final s = sx < sy ? sx : sy;
    final ox = (size.width - spanX * s) / 2;
    final oy = (size.height - spanY * s) / 2;
    Offset map(double x, double y) =>
        Offset(ox + (x - minX) * s, size.height - (oy + (y - minY) * s));

    if (path.length > 1) {
      final line = Paint()
        ..color = AppColors.primary.withValues(alpha: 0.75)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final p = Path();
      final first = points[path.first];
      p.moveTo(map(first.x, first.y).dx, map(first.x, first.y).dy);
      for (final i in path.skip(1)) {
        final o = map(points[i].x, points[i].y);
        p.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(p, line);
    }
    for (final pt in points) {
      final o = map(pt.x, pt.y);
      final color = switch (pt.kind) {
        LocationType.office || LocationType.destination => AppColors.deepNavy,
        LocationType.parking || LocationType.depot => AppColors.textMuted,
        _ => pt.done ? AppColors.success : AppColors.primary,
      };
      final r = pt.emphasis ? 8.0 : 6.0;
      if (pt.kind == LocationType.office ||
          pt.kind == LocationType.destination) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: o, width: r * 2.2, height: r * 2.2),
            const Radius.circular(3),
          ),
          Paint()..color = color,
        );
      } else if (pt.kind == LocationType.parking ||
          pt.kind == LocationType.depot) {
        canvas.drawRect(
          Rect.fromCenter(center: o, width: r * 1.8, height: r * 1.8),
          Paint()..color = color.withValues(alpha: 0.6),
        );
      } else {
        canvas.drawCircle(o, r + 2, Paint()..color = Colors.white);
        canvas.drawCircle(o, r, Paint()..color = color);
      }
      if (showLabels) {
        final tp = TextPainter(
          text: TextSpan(
            text: pt.label,
            style: labelStyle.copyWith(
              color: AppColors.textPrimary,
              fontSize: 10,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 90);
        final dx = (o.dx + 9).clamp(0.0, size.width - tp.width - 2);
        final dy = (o.dy - tp.height - 4).clamp(0.0, size.height - tp.height);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(dx - 3, dy - 1, tp.width + 6, tp.height + 2),
            const Radius.circular(4),
          ),
          Paint()..color = Colors.white.withValues(alpha: 0.85),
        );
        tp.paint(canvas, Offset(dx, dy));
      }
    }
    if (vehicle != null) {
      final o = map(vehicle!.dx, vehicle!.dy);
      final c = stale ? AppColors.warning : AppColors.teal;
      canvas.drawCircle(o, 14, Paint()..color = c.withValues(alpha: 0.18));
      canvas.drawCircle(o, 8, Paint()..color = Colors.white);
      canvas.drawCircle(o, 6, Paint()..color = c);
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) =>
      old.points != points ||
      old.path != path ||
      old.vehicle != vehicle ||
      old.stale != stale;
}
