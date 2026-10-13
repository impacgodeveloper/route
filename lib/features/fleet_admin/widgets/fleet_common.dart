import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/widgets.dart';
import '../../../domain/models/models.dart';

/// Two columns on wide screens, stacked on narrow ones.
class ResponsiveSplit extends StatelessWidget {
  const ResponsiveSplit({
    super.key,
    required this.left,
    required this.right,
    this.leftFlex = 3,
    this.rightFlex = 2,
    this.breakpoint = 980,
  });

  final Widget left;
  final Widget right;
  final int leftFlex;
  final int rightFlex;
  final double breakpoint;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      if (c.maxWidth < breakpoint) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            left,
            const SizedBox(height: AppSpace.md),
            right,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: leftFlex, child: left),
          const SizedBox(width: AppSpace.md),
          Expanded(flex: rightFlex, child: right),
        ],
      );
    },
  );
}

/// Card with a header row and body.
class PanelCard extends StatelessWidget {
  const PanelCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.all(AppSpace.md),
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: padding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: title, subtitle: subtitle, trailing: trailing),
        const SizedBox(height: AppSpace.sm),
        child,
      ],
    ),
  );
}

String vehicleShort(Vehicle? v) => v == null
    ? 'No vehicle'
    : 'Vehicle ${v.vehicleCode} · ${v.propulsion.label} ${v.type.label}';

String driverShort(Driver? d) =>
    d == null ? 'No driver' : '${d.driverCode} ${d.name}';

/// Compact tappable trip row used across the console.
class TripRowTile extends ConsumerWidget {
  const TripRowTile({super.key, required this.trip, this.onTap, this.trailing});
  final Trip trip;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final t = Theme.of(context).textTheme;
    final d = data.driver(trip.assignedDriverId);
    final v = data.vehicle(trip.assignedVehicleId);
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.mdAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpace.sm,
          horizontal: AppSpace.xs,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Fmt.time(trip.scheduledStart),
                    style: t.labelMedium!.copyWith(
                      fontFeatures: AppText.tabular,
                    ),
                  ),
                  Text(
                    Fmt.dateShort(trip.serviceDate),
                    style: t.bodySmall!.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(trip.tripCode, style: t.titleSmall),
                  Text(
                    '${trip.employeeIds.length} pax · ${d?.driverCode ?? 'No driver'} · ${v == null ? 'No vehicle' : 'Vehicle ${v.vehicleCode}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall!.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.xs),
            TripStatusBadge(trip.status, dense: true),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// Saves a CSV file (download on web / file on native) with a clipboard
/// fallback, and reports the outcome.
Future<void> exportCsv(
  BuildContext context,
  WidgetRef ref, {
  required String fileName,
  required List<String> header,
  required List<List<Object?>> rows,
}) async {
  final export = ref.read(servicesProvider).export;
  final csv = export.toCsv(header, rows);
  try {
    final where = await export.saveCsv(fileName, csv);
    if (context.mounted) showToast(context, where);
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: csv));
    if (context.mounted) {
      showToast(context, 'File export unavailable — CSV copied to clipboard');
    }
  }
}

/// Map points for a list of planned/route stops.
List<MapPoint> stopPoints(
  DataView data,
  List<String> locationIds, {
  Set<int> done = const {},
}) {
  return [
    for (var i = 0; i < locationIds.length; i++)
      if (data.location(locationIds[i]) case final l?)
        MapPoint(
          x: l.demoX,
          y: l.demoY,
          label: l.code,
          kind: l.type,
          done: done.contains(i),
        ),
  ];
}

/// Small horizontal stat label: value + caption.
class InlineStat extends StatelessWidget {
  const InlineStat({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: t.titleMedium!.copyWith(fontFeatures: AppText.tabular),
        ),
        Text(label, style: t.bodySmall!.copyWith(color: AppColors.textMuted)),
      ],
    );
  }
}

/// Wrap of [InlineStat]s with consistent spacing.
class StatStrip extends StatelessWidget {
  const StatStrip({super.key, required this.stats});
  final List<(String, String)> stats;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpace.xl,
    runSpacing: AppSpace.sm,
    children: [for (final s in stats) InlineStat(label: s.$1, value: s.$2)],
  );
}

/// Awaits [action] and shows its result only if [context] is still mounted.
Future<bool> runAndShow(
  BuildContext context,
  Future<Result> action, {
  String? successMessage,
  String failureTitle = 'Action not completed',
}) async {
  final r = await action;
  if (!context.mounted) return r.isOk;
  return showResult(
    context,
    r,
    successMessage: successMessage,
    failureTitle: failureTitle,
  );
}

/// Console path for an audited/notified record, or null if none.
String? fleetEntityPath(DataView data, String type, String id) =>
    switch (type) {
      'trip' => '/fleet/dispatch/trip/$id',
      'booking' => '/fleet/dispatch?booking=$id',
      'vehicle' => '/fleet/vehicles/$id',
      'driver' => '/fleet/drivers/$id',
      'employer' || 'company' => '/fleet/companies/$id',
      'contract' || 'allocation' => '/fleet/companies',
      'incident' => '/fleet/monitoring/incident/$id',
      'optimizationRun' => '/fleet/optimization/run/$id',
      'optimizationConfig' => '/fleet/optimization/parameters',
      'invoice' || 'billing' => '/fleet/billing',
      'location' || 'parking' => '/fleet/parking',
      'ticket' => '/fleet/monitoring?tab=tickets',
      'routeRevision' || 'traffic' => '/fleet/traffic',
      'shift' =>
        data.db.shifts[id] == null
            ? null
            : '/fleet/drivers/${data.db.shifts[id]!.driverId}',
      _ => null,
    };
