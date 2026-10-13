import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/widgets.dart';
import '../features/driver/driver_routes.dart';
import '../features/employee/employee_routes.dart';
import '../features/employer_admin/employer_routes.dart';
import '../features/fleet_admin/fleet_routes.dart';
import '../features/launcher/login_screen.dart';

/// Root navigator key (dialogs above shells).
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Declarative routing for the four workspaces. Each workspace owns its
/// route subtree so it can later be built and deployed separately.
GoRouter buildRouter({String initialLocation = '/'}) => GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: initialLocation,
  routes: [
    GoRoute(path: '/', builder: (context, state) => const LoginScreen()),
    ...employeeRoutes(rootNavigatorKey),
    ...driverRoutes(rootNavigatorKey),
    ...employerRoutes(rootNavigatorKey),
    ...fleetRoutes(rootNavigatorKey),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: EmptyState(
      icon: Icons.link_off_rounded,
      title: 'Page not found',
      message: 'No screen exists at "${state.uri}".',
      actionLabel: 'Back to sign-in',
      onAction: () => context.go('/'),
    ),
  ),
);

final routerProvider = Provider<GoRouter>((ref) => buildRouter());
