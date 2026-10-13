import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import 'driver_common.dart';
import 'screens/driver_active_trip_screen.dart';
import 'screens/driver_activity_screen.dart';
import 'screens/driver_alcohol_screen.dart';
import 'screens/driver_attendance_screen.dart';
import 'screens/driver_complete_screen.dart';
import 'screens/driver_home_screen.dart';
import 'screens/driver_inspection_screen.dart';
import 'screens/driver_login_screen.dart';
import 'screens/driver_profile_screen.dart';
import 'screens/driver_report_screen.dart';
import 'screens/driver_shift_summary_screen.dart';
import 'screens/driver_stop_screen.dart';
import 'screens/driver_trips_screen.dart';

/// Requires a selected demo driver identity.
String? _guard(BuildContext context, GoRouterState state) {
  final id = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(currentDriverIdProvider);
  return id == null ? '/driver/login' : null;
}

/// Route subtree for the Driver workspace.
List<RouteBase> driverRoutes(GlobalKey<NavigatorState> rootKey) => [
  GoRoute(
    path: '/driver',
    redirect: (context, state) => _guard(context, state) ?? '/driver/home',
  ),
  GoRoute(
    path: '/driver/login',
    builder: (context, state) => const DriverLoginScreen(),
  ),
  StatefulShellRoute.indexedStack(
    redirect: _guard,
    builder: (context, state, shell) => _DriverShell(shell: shell),
    branches: [
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: '/driver/home',
            builder: (c, s) => const DriverHomeScreen(),
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: '/driver/trips',
            builder: (c, s) => const DriverTripsScreen(),
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: '/driver/activity',
            builder: (c, s) => const DriverActivityScreen(),
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: '/driver/profile',
            builder: (c, s) => const DriverProfileScreen(),
          ),
        ],
      ),
    ],
  ),
  GoRoute(
    path: '/driver/trip/:id',
    redirect: _guard,
    builder: (c, s) => DriverTripDetailScreen(tripId: s.pathParameters['id']!),
    routes: [
      GoRoute(
        path: 'active',
        builder: (c, s) =>
            DriverActiveTripScreen(tripId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: 'stop/:stopId',
        builder: (c, s) => DriverStopScreen(
          tripId: s.pathParameters['id']!,
          stopId: s.pathParameters['stopId']!,
        ),
      ),
      GoRoute(
        path: 'complete',
        builder: (c, s) =>
            DriverCompleteTripScreen(tripId: s.pathParameters['id']!),
      ),
    ],
  ),
  GoRoute(
    path: '/driver/inspection',
    redirect: _guard,
    builder: (c, s) =>
        DriverInspectionScreen(vehicleId: s.uri.queryParameters['vehicle']),
  ),
  GoRoute(
    path: '/driver/alcohol',
    redirect: _guard,
    builder: (c, s) =>
        DriverAlcoholScreen(tripId: s.uri.queryParameters['trip']),
  ),
  GoRoute(
    path: '/driver/attendance',
    redirect: _guard,
    builder: (c, s) => const DriverAttendanceScreen(),
  ),
  GoRoute(
    path: '/driver/report',
    redirect: _guard,
    builder: (c, s) => DriverReportScreen(
      initialType: _incidentType(s.uri.queryParameters["type"]),
      tripId: s.uri.queryParameters['trip'],
    ),
  ),
  GoRoute(
    path: '/driver/sos',
    redirect: _guard,
    builder: (c, s) => DriverSosScreen(tripId: s.uri.queryParameters['trip']),
  ),
  GoRoute(
    path: '/driver/shift-summary',
    redirect: _guard,
    builder: (c, s) => const DriverShiftSummaryScreen(),
  ),
  GoRoute(
    path: '/driver/notifications',
    redirect: _guard,
    builder: (c, s) => const DriverNotificationsScreen(),
  ),
  GoRoute(
    path: '/driver/support',
    redirect: _guard,
    builder: (c, s) => const DriverSupportScreen(),
  ),
];

class _DriverShell extends ConsumerWidget {
  const _DriverShell({required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(driverDayProvider);
    final active = day?.activeTrip;
    final unread = day == null
        ? 0
        : day.data.unreadCount(UserRole.driver, day.driver.id);
    Widget? accessory;
    if (active != null) {
      final stop = day!.data.trips.currentStop(active);
      accessory = Material(
        color: AppColors.midnightNavy,
        child: SafeArea(
          top: false,
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.md,
              AppSpace.xs,
              AppSpace.xs,
              AppSpace.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: AppRadius.mdAll,
                    onTap: () =>
                        context.push('/driver/trip/${active.id}/active'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.navigation_outlined,
                            color: Colors.white,
                          ),
                          const SizedBox(width: AppSpace.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Active trip ${active.tripCode}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  stop == null
                                      ? 'All stops done · complete trip'
                                      : 'Next: ${stopTitle(day.data, stop)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    minimumSize: const Size(88, 48),
                  ),
                  onPressed: () =>
                      context.push('/driver/sos?trip=${active.id}'),
                  icon: const Icon(Icons.sos_rounded),
                  label: const Text('SOS'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return MobileNavShell(
      navigationShell: shell,
      accessory: accessory,
      destinations: [
        const MobileDestination(
          label: 'Home',
          icon: Icons.home_outlined,
          selectedIcon: Icons.home_rounded,
        ),
        const MobileDestination(
          label: 'Trips',
          icon: Icons.route_outlined,
          selectedIcon: Icons.route_rounded,
        ),
        MobileDestination(
          label: 'Activity',
          icon: Icons.history_outlined,
          selectedIcon: Icons.history_rounded,
          badge: unread,
        ),
        const MobileDestination(
          label: 'Profile',
          icon: Icons.person_outline_rounded,
          selectedIcon: Icons.person_rounded,
        ),
      ],
    );
  }
}

IncidentType? _incidentType(String? name) {
  for (final t in IncidentType.values) {
    if (t.name == name) return t;
  }
  return null;
}
