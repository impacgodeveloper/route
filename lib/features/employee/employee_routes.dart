import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import 'activity_screen.dart';
import 'book_screen.dart';
import 'booking_detail_screen.dart';
import 'employee_common.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';
import 'pass_screen.dart';
import 'profile_screen.dart';
import 'roster_screen.dart';
import 'safety_screen.dart';
import 'support_screen.dart';
import 'trip_detail_screen.dart';
import 'travel_preferences_screen.dart';
import 'trips_screen.dart';

String? _requireIdentity(BuildContext context, GoRouterState state) {
  final container = ProviderScope.containerOf(context, listen: false);
  final id = container.read(currentEmployeeIdProvider);
  final emp = container.read(dataProvider).employee(id);
  final atLogin = state.matchedLocation == '/employee/login';
  if ((id == null || emp == null || !emp.isActive) && !atLogin) {
    return '/employee/login';
  }
  if (state.matchedLocation == '/employee') return '/employee/home';
  return null;
}

/// Route subtree for the Employee / Passenger workspace.
List<RouteBase> employeeRoutes(GlobalKey<NavigatorState> rootKey) => [
  GoRoute(path: '/employee', redirect: _requireIdentity),
  GoRoute(
    path: '/employee/login',
    builder: (context, state) => const EmployeeLoginScreen(),
  ),
  StatefulShellRoute.indexedStack(
    redirect: _requireIdentity,
    builder: (context, state, shell) => EmployeeShell(shell: shell),
    branches: [
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: '/employee/home',
            builder: (c, s) => const EmployeeHomeScreen(),
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: '/employee/trips',
            builder: (c, s) => const EmployeeTripsScreen(),
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: '/employee/book',
            builder: (c, s) => const EmployeeBookScreen(),
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: '/employee/activity',
            builder: (c, s) => const EmployeeActivityScreen(),
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: '/employee/profile',
            builder: (c, s) => const EmployeeProfileScreen(),
          ),
        ],
      ),
    ],
  ),
  GoRoute(
    path: '/employee/trip/:id',
    parentNavigatorKey: rootKey,
    redirect: _requireIdentity,
    builder: (c, s) =>
        EmployeeTripDetailScreen(tripId: s.pathParameters['id']!),
    routes: [
      GoRoute(
        path: 'pass',
        parentNavigatorKey: rootKey,
        builder: (c, s) => EmployeePassScreen(tripId: s.pathParameters['id']!),
      ),
    ],
  ),
  GoRoute(
    path: '/employee/notifications',
    parentNavigatorKey: rootKey,
    redirect: _requireIdentity,
    builder: (c, s) => const EmployeeNotificationsScreen(),
  ),
  GoRoute(
    path: '/employee/booking/:id',
    parentNavigatorKey: rootKey,
    redirect: _requireIdentity,
    builder: (c, s) =>
        EmployeeBookingDetailScreen(bookingId: s.pathParameters['id']!),
  ),
  GoRoute(
    path: '/employee/support/new',
    parentNavigatorKey: rootKey,
    redirect: _requireIdentity,
    builder: (c, s) =>
        EmployeeSupportScreen(tripId: s.uri.queryParameters['trip']),
  ),
  GoRoute(
    path: '/employee/safety',
    parentNavigatorKey: rootKey,
    redirect: _requireIdentity,
    builder: (c, s) => const EmployeeSafetyScreen(),
  ),
  GoRoute(
    path: '/employee/roster',
    parentNavigatorKey: rootKey,
    redirect: _requireIdentity,
    builder: (c, s) => const EmployeeRosterScreen(),
  ),
  GoRoute(
    path: '/employee/preferences',
    parentNavigatorKey: rootKey,
    redirect: _requireIdentity,
    builder: (c, s) => const EmployeeTravelPreferencesScreen(),
  ),
];

class EmployeeShell extends ConsumerWidget {
  const EmployeeShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(currentEmployeeIdProvider);
    final unread = id == null
        ? 0
        : ref.watch(dataProvider).unreadCount(UserRole.employee, id);
    return EmployeeTextScale(
      child: MobileNavShell(
        navigationShell: shell,
        destinations: [
          const MobileDestination(
            label: 'Home',
            icon: Icons.home_outlined,
            selectedIcon: Icons.home_rounded,
          ),
          const MobileDestination(
            label: 'My Trips',
            icon: Icons.route_outlined,
            selectedIcon: Icons.route_rounded,
          ),
          const MobileDestination(
            label: 'Book',
            icon: Icons.add_circle_outline_rounded,
            selectedIcon: Icons.add_circle_rounded,
          ),
          MobileDestination(
            label: 'Activity',
            icon: Icons.history_rounded,
            selectedIcon: Icons.history_rounded,
            badge: unread,
          ),
          const MobileDestination(
            label: 'Profile',
            icon: Icons.person_outline_rounded,
            selectedIcon: Icons.person_rounded,
          ),
        ],
      ),
    );
  }
}
