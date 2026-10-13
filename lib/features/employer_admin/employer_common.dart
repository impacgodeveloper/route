import 'package:flutter/material.dart';

import '../../core/widgets/widgets.dart';
import '../../data/repositories/repositories.dart';
import '../../domain/models/models.dart';

/// Shared helpers for the Employer Admin console.
abstract final class EmployerPaths {
  static const overview = '/employer/overview';
  static const employees = '/employer/employees';
  static const policies = '/employer/policies';
  static const import = '/employer/policies/import';
  static const locations = '/employer/locations';
  static const assignments = '/employer/assignments';
  static const billing = '/employer/billing';
  static const reports = '/employer/reports';
  static const settings = '/employer/settings';
  static const notifications = '/employer/notifications';
  static const traffic = '/employer/traffic';
  static const analytics = '/employer/analytics';
  static String sos(String incidentId) => '/employer/sos/$incidentId';

  /// Billing tabs: cycles (default), lines, config.
  static String billingTab(String tab) => '$billing?tab=$tab';
  static String invoice(String id) => '$billing/invoices/$id';

  static String employee(String id) => '$employees/$id';
  static String trip(String id) => '$assignments/$id';
  static String bill(String id) => '$billing/$id';
}

/// Trips of the console's employer.
List<Trip> employerTrips(DataView d) {
  final id = d.primaryEmployer.id;
  return d.trips.all().where((t) => t.employerId == id).toList();
}

/// Open booking requests from the employer's employees.
List<Booking> employerOpenBookings(DataView d) {
  final id = d.primaryEmployer.id;
  return d.openBookings
      .where((b) => d.employee(b.employeeId)?.employerId == id)
      .toList();
}

/// Service alerts: delayed / needs-attention trips and open incidents on
/// employer trips.
({List<Trip> trips, List<Incident> incidents}) employerAlerts(DataView d) {
  final trips = employerTrips(d);
  final ids = trips.map((t) => t.id).toSet();
  return (
    trips: trips
        .where(
          (t) =>
              t.status == TripStatus.delayed ||
              t.status == TripStatus.needsAttention,
        )
        .toList(),
    incidents: d.openIncidents
        .where((i) => i.tripId != null && ids.contains(i.tripId))
        .toList(),
  );
}

/// Small EV / ICE pill for vehicles.
class PropulsionBadge extends StatelessWidget {
  const PropulsionBadge(this.vehicle, {super.key});
  final Vehicle? vehicle;

  @override
  Widget build(BuildContext context) {
    final v = vehicle;
    if (v == null) return const StatusBadge('Unassigned', dense: true);
    return StatusBadge(
      v.propulsion.label,
      dense: true,
      tone: v.isEv ? StatusTone.teal : StatusTone.neutral,
      icon: v.isEv ? Icons.bolt_rounded : Icons.local_gas_station_outlined,
    );
  }
}

/// Section card with a title row.
class PanelCard extends StatelessWidget {
  const PanelCard({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.padding,
  });
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: padding ?? const EdgeInsets.all(AppSpace.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: title, subtitle: subtitle, trailing: trailing),
        const SizedBox(height: AppSpace.md),
        child,
      ],
    ),
  );
}

/// Two columns on wide screens, stacked on narrow.
class ResponsiveColumns extends StatelessWidget {
  const ResponsiveColumns({
    super.key,
    required this.left,
    required this.right,
    this.breakpoint = 1000,
    this.leftFlex = 3,
    this.rightFlex = 2,
  });
  final Widget left;
  final Widget right;
  final double breakpoint;
  final int leftFlex;
  final int rightFlex;

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

/// Row in a compact list (title / subtitle / trailing).
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.mdAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: AppSpace.sm),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: t.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: t.bodySmall!.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpace.sm),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Divided list of rows with an empty fallback.
class DividedList extends StatelessWidget {
  const DividedList({super.key, required this.children, this.empty});
  final List<Widget> children;
  final Widget? empty;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return empty ?? const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          children[i],
        ],
      ],
    );
  }
}
