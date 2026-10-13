import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import '../shared/notifications_view.dart';
import 'pages/dispatch_page.dart';
import 'pages/dispatch_wizard_page.dart';
import 'pages/drivers_page.dart';
import 'pages/monitoring_page.dart';
import 'pages/optimization_page.dart';
import 'pages/overview_page.dart';
import 'pages/parameters_page.dart';
import 'pages/parking_page.dart';
import 'pages/pooling_page.dart';
import 'pages/registry/registry_routes.dart';
import 'pages/reports_page.dart';
import 'pages/run_detail_page.dart';
import 'pages/settings_page.dart';
import 'pages/trip_detail_page.dart';
import 'pages/v2/v2_routes.dart';
import 'pages/v3/v3_routes.dart';
import 'pages/vehicles_page.dart';

Page<void> _page(GoRouterState s, Widget child) =>
    NoTransitionPage(key: s.pageKey, child: child);

/// Route subtree for the Fleet Manager Admin console.
List<RouteBase> fleetRoutes(GlobalKey<NavigatorState> rootKey) => [
  GoRoute(path: '/fleet', redirect: (c, s) => '/fleet/overview'),
  ShellRoute(
    builder: (context, state, child) =>
        FleetShell(location: state.uri.path, child: child),
    routes: [
      GoRoute(
        path: '/fleet/overview',
        pageBuilder: (c, s) => _page(s, const FleetOverviewPage()),
      ),
      GoRoute(
        path: '/fleet/dispatch',
        pageBuilder: (c, s) => _page(
          s,
          DispatchPage(highlightBookingId: s.uri.queryParameters['booking']),
        ),
        routes: [
          GoRoute(
            path: 'new',
            pageBuilder: (c, s) => _page(
              s,
              DispatchWizardPage(
                employeeIds: _csv(s.uri.queryParameters['employees']),
                bookingIds: _csv(s.uri.queryParameters['bookings']),
                date: DateTime.tryParse(s.uri.queryParameters['date'] ?? ''),
              ),
            ),
          ),
          GoRoute(
            path: 'trip/:id',
            pageBuilder: (c, s) => _page(
              s,
              TripDetailPage(
                key: ValueKey('trip-${s.pathParameters['id']}'),
                tripId: s.pathParameters['id']!,
                openReassign: s.uri.queryParameters['reassign'] == '1',
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/fleet/optimization',
        pageBuilder: (c, s) => _page(s, const OptimizationPage()),
        routes: [
          GoRoute(
            path: 'parameters',
            pageBuilder: (c, s) => _page(s, const ParametersPage()),
          ),
          GoRoute(
            path: 'run/:id',
            pageBuilder: (c, s) => _page(
              s,
              RunDetailPage(
                key: ValueKey('run-${s.pathParameters['id']}'),
                runId: s.pathParameters['id']!,
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/fleet/pooling',
        pageBuilder: (c, s) => _page(s, const PoolingPage()),
      ),
      GoRoute(
        path: '/fleet/vehicles',
        pageBuilder: (c, s) => _page(s, const VehiclesPage()),
        routes: [
          GoRoute(
            path: 'new',
            pageBuilder: (c, s) => _page(s, const VehicleEditPage()),
          ),
          GoRoute(
            path: ':id',
            pageBuilder: (c, s) => _page(
              s,
              VehicleEditPage(
                key: ValueKey('veh-${s.pathParameters['id']}'),
                vehicleId: s.pathParameters['id'],
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/fleet/drivers',
        pageBuilder: (c, s) => _page(s, const DriversPage()),
        routes: [
          GoRoute(
            path: 'new',
            pageBuilder: (c, s) => _page(s, const DriverEditPage()),
          ),
          GoRoute(
            path: ':id',
            pageBuilder: (c, s) => _page(
              s,
              DriverEditPage(
                key: ValueKey('drv-${s.pathParameters['id']}'),
                driverId: s.pathParameters['id'],
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/fleet/parking',
        pageBuilder: (c, s) => _page(s, const ParkingPage()),
      ),
      GoRoute(
        path: '/fleet/monitoring',
        pageBuilder: (c, s) =>
            _page(s, MonitoringPage(initialTab: s.uri.queryParameters['tab'])),
        routes: [
          GoRoute(
            path: 'incident/:id',
            pageBuilder: (c, s) => _page(
              s,
              IncidentDetailPage(
                key: ValueKey('inc-${s.pathParameters['id']}'),
                incidentId: s.pathParameters['id']!,
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/fleet/reports',
        pageBuilder: (c, s) => _page(s, const FleetReportsPage()),
      ),
      GoRoute(
        path: '/fleet/settings',
        pageBuilder: (c, s) => _page(s, const FleetSettingsPage()),
      ),
      ...registryRoutes(_page),
      ...v2Routes(_page),
      ...v3Routes(_page),
      GoRoute(
        path: '/fleet/notifications',
        pageBuilder: (c, s) => _page(s, const _FleetNotificationsPage()),
      ),
    ],
  ),
];

List<String> _csv(String? v) => v == null || v.trim().isEmpty
    ? const []
    : v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

/// Where a notification's related record lives in this console.
String? fleetPathFor(DataView data, AppNotification n) {
  final id = n.relatedEntityId;
  if (id == null) return null;
  return switch (n.relatedEntityType) {
    'trip' => '/fleet/dispatch/trip/$id',
    'booking' => '/fleet/dispatch?booking=$id',
    'incident' => '/fleet/monitoring/incident/$id',
    'vehicle' => '/fleet/vehicles/$id',
    'billing' =>
      data.billingRecord(id) == null
          ? null
          : '/fleet/dispatch/trip/${data.billingRecord(id)!.tripId}',
    'ticket' => '/fleet/monitoring?tab=tickets',
    'shift' =>
      data.db.shifts[id] == null
          ? null
          : '/fleet/drivers/${data.db.shifts[id]!.driverId}',
    'optimizationRun' => '/fleet/optimization/run/$id',
    'employer' => '/fleet/companies/$id',
    'contract' => '/fleet/companies',
    'invoice' => '/fleet/billing',
    'traffic' => '/fleet/traffic',
    'fleetPolicy' => '/fleet/safety',
    'geofence' => '/fleet/telematics',
    _ => null,
  };
}

class FleetShell extends ConsumerWidget {
  const FleetShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final openRequests = data.openBookings.length;
    final openIncidents = data.openIncidents.length;
    final openVehicleEvents = data.openVehicleEvents.length;
    final alcoholBlocks = data.drivers
        .where((d) => data.blockingAlcoholTest(d.id) != null)
        .length;
    final openSos = data.openIncidents.where((i) => i.isSos).length;
    final openRevisions = data.routeRevisions
        .where((r) => r.status == RevisionStatus.proposed)
        .length;
    final attention = data.trips
        .all()
        .where((t) => t.status == TripStatus.needsAttention)
        .length;
    return AdminShell(
      workspaceName: 'Fleet Manager',
      organizationLabel: 'Shared fleet pool',
      accent: AppColors.fleetAccent,
      icon: Icons.hub_outlined,
      currentPath: location,
      notificationCount: data.unreadCount(UserRole.fleetManager),
      onNotifications: () => context.go('/fleet/notifications'),
      destinations: [
        const AdminDestination(
          label: 'Overview',
          icon: Icons.space_dashboard_outlined,
          selectedIcon: Icons.space_dashboard_rounded,
          path: '/fleet/overview',
        ),
        AdminDestination(
          label: 'Trips & Dispatch',
          icon: Icons.alt_route_outlined,
          selectedIcon: Icons.alt_route_rounded,
          path: '/fleet/dispatch',
          badge: openRequests + attention,
        ),
        const AdminDestination(
          label: 'Route Optimization',
          icon: Icons.auto_graph_outlined,
          selectedIcon: Icons.auto_graph_rounded,
          path: '/fleet/optimization',
        ),
        const AdminDestination(
          label: 'Employee Pooling',
          icon: Icons.groups_outlined,
          selectedIcon: Icons.groups_rounded,
          path: '/fleet/pooling',
        ),
        const AdminDestination(
          label: 'Vehicle Mapping',
          icon: Icons.table_view_outlined,
          selectedIcon: Icons.table_view_rounded,
          path: '/fleet/mapping',
        ),
        const AdminDestination(
          label: 'Companies & Contracts',
          icon: Icons.apartment_outlined,
          selectedIcon: Icons.apartment_rounded,
          path: '/fleet/companies',
        ),
        const AdminDestination(
          label: 'Vehicles',
          icon: Icons.directions_car_outlined,
          selectedIcon: Icons.directions_car_rounded,
          path: '/fleet/vehicles',
        ),
        const AdminDestination(
          label: 'Drivers',
          icon: Icons.badge_outlined,
          selectedIcon: Icons.badge_rounded,
          path: '/fleet/drivers',
        ),
        const AdminDestination(
          label: 'Parking & Stops',
          icon: Icons.local_parking_outlined,
          selectedIcon: Icons.local_parking_rounded,
          path: '/fleet/parking',
        ),
        AdminDestination(
          label: 'Monitoring & Incidents',
          icon: Icons.monitor_heart_outlined,
          selectedIcon: Icons.monitor_heart_rounded,
          path: '/fleet/monitoring',
          badge: openIncidents,
        ),
        AdminDestination(
          label: 'Telematics & Geofences',
          icon: Icons.satellite_alt_outlined,
          selectedIcon: Icons.satellite_alt_rounded,
          path: '/fleet/telematics',
          badge: openVehicleEvents,
        ),
        AdminDestination(
          label: 'Safety & SOS',
          icon: Icons.health_and_safety_outlined,
          selectedIcon: Icons.health_and_safety_rounded,
          path: '/fleet/safety',
          badge: alcoholBlocks + openSos,
        ),
        AdminDestination(
          label: 'Traffic & Movement',
          icon: Icons.traffic_outlined,
          selectedIcon: Icons.traffic_rounded,
          path: '/fleet/traffic',
          badge: openRevisions,
        ),
        const AdminDestination(
          label: 'Billing',
          icon: Icons.receipt_long_outlined,
          selectedIcon: Icons.receipt_long_rounded,
          path: '/fleet/billing',
        ),
        const AdminDestination(
          label: 'Reports',
          icon: Icons.insert_chart_outlined_rounded,
          selectedIcon: Icons.insert_chart_rounded,
          path: '/fleet/reports',
        ),
        const AdminDestination(
          label: 'Settings',
          icon: Icons.settings_outlined,
          selectedIcon: Icons.settings_rounded,
          path: '/fleet/settings',
        ),
      ],
      child: child,
    );
  }
}

class _FleetNotificationsPage extends ConsumerWidget {
  const _FleetNotificationsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = MediaQuery.sizeOf(context).width;
    final pad = w < 720 ? AppSpace.md : AppSpace.xl;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: NotificationsList(
          role: UserRole.fleetManager,
          padding: EdgeInsets.fromLTRB(pad, pad, pad, AppSpace.xxxl),
          onOpen: (n) {
            final path = fleetPathFor(ref.read(dataProvider), n);
            if (path != null) context.go(path);
          },
        ),
      ),
    );
  }
}
