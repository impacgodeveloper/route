import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import '../shared/notifications_view.dart';
import 'analytics_page.dart';
import 'assignments_page.dart';
import 'billing_cycles.dart';
import 'billing_page.dart';
import 'employee_detail_page.dart';
import 'employees_page.dart';
import 'employer_common.dart';
import 'locations_page.dart';
import 'overview_page.dart';
import 'policies_page.dart';
import 'reports_page.dart';
import 'roster_import_page.dart';
import 'settings_page.dart';
import 'sos_widgets.dart';
import 'traffic_page.dart';

Page<void> _page(GoRouterState s, Widget child) =>
    NoTransitionPage<void>(key: s.pageKey, child: child);

/// Route subtree for the Employer Admin console (web/tablet first).
List<RouteBase> employerRoutes(GlobalKey<NavigatorState> rootKey) => [
  GoRoute(path: '/employer', redirect: (c, s) => EmployerPaths.overview),
  ShellRoute(
    builder: (context, state, child) =>
        EmployerShell(location: state.uri.path, child: child),
    routes: [
      GoRoute(
        path: EmployerPaths.overview,
        pageBuilder: (c, s) => _page(s, const EmployerOverviewPage()),
      ),
      GoRoute(
        path: EmployerPaths.employees,
        pageBuilder: (c, s) => _page(s, const EmployeesPage()),
        routes: [
          GoRoute(
            path: 'new',
            pageBuilder: (c, s) =>
                _page(s, const EmployeeDetailPage(employeeId: null)),
          ),
          GoRoute(
            path: ':id',
            pageBuilder: (c, s) => _page(
              s,
              EmployeeDetailPage(employeeId: s.pathParameters['id']),
            ),
          ),
        ],
      ),
      GoRoute(
        path: EmployerPaths.policies,
        pageBuilder: (c, s) => _page(s, const PoliciesPage()),
        routes: [
          GoRoute(
            path: 'import',
            pageBuilder: (c, s) => _page(s, const RosterImportPage()),
          ),
        ],
      ),
      GoRoute(
        path: EmployerPaths.locations,
        pageBuilder: (c, s) => _page(s, const LocationsPage()),
      ),
      GoRoute(
        path: EmployerPaths.assignments,
        pageBuilder: (c, s) => _page(s, const AssignmentsPage()),
        routes: [
          GoRoute(
            path: ':tripId',
            pageBuilder: (c, s) => _page(
              s,
              EmployerTripDetailPage(tripId: s.pathParameters['tripId']!),
            ),
          ),
        ],
      ),
      GoRoute(
        path: EmployerPaths.billing,
        pageBuilder: (c, s) =>
            _page(s, BillingPage(initialTab: s.uri.queryParameters['tab'])),
        routes: [
          GoRoute(
            path: 'invoices/:invoiceId',
            pageBuilder: (c, s) => _page(
              s,
              InvoiceDetailPage(invoiceId: s.pathParameters['invoiceId']!),
            ),
          ),
          GoRoute(
            path: ':id',
            pageBuilder: (c, s) =>
                _page(s, BillingDetailPage(billingId: s.pathParameters['id']!)),
          ),
        ],
      ),
      GoRoute(
        path: EmployerPaths.traffic,
        pageBuilder: (c, s) => _page(s, const EmployerTrafficPage()),
      ),
      GoRoute(
        path: EmployerPaths.analytics,
        pageBuilder: (c, s) => _page(s, const AnalyticsPage()),
      ),
      GoRoute(
        path: '/employer/sos/:incidentId',
        pageBuilder: (c, s) => _page(
          s,
          SosDetailPage(incidentId: s.pathParameters['incidentId']!),
        ),
      ),
      GoRoute(
        path: EmployerPaths.reports,
        pageBuilder: (c, s) => _page(s, const ReportsPage()),
      ),
      GoRoute(
        path: EmployerPaths.settings,
        pageBuilder: (c, s) => _page(s, const EmployerSettingsPage()),
      ),
      GoRoute(
        path: EmployerPaths.notifications,
        pageBuilder: (c, s) => _page(s, const _EmployerNotificationsPage()),
      ),
    ],
  ),
];

/// Admin frame with computed sidebar badges.
class EmployerShell extends ConsumerWidget {
  const EmployerShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final employerId = data.primaryEmployer.id;
    final requests = employerOpenBookings(data).length;
    final billing =
        data
            .billingOf(employerId)
            .where(
              (b) =>
                  b.status == BillingStatus.generated ||
                  b.status == BillingStatus.disputed,
            )
            .length +
        employerTrips(data)
            .where(
              (t) =>
                  t.status == TripStatus.completed &&
                  t.billableStatus == BillableStatus.missingDistance,
            )
            .length;
    final alerts = employerAlerts(data);
    final due = ref
        .read(servicesProvider)
        .billingCycles
        .dueCycles(employerId)
        .length;
    return AdminShell(
      workspaceName: 'Employer Admin',
      organizationLabel: data.primaryEmployer.name,
      accent: AppColors.employerAccent,
      icon: Icons.business_outlined,
      currentPath: location,
      notificationCount: data.unreadCount(UserRole.employerAdmin),
      onNotifications: () => context.go(EmployerPaths.notifications),
      destinations: [
        AdminDestination(
          label: 'Overview',
          icon: Icons.space_dashboard_outlined,
          selectedIcon: Icons.space_dashboard_rounded,
          path: EmployerPaths.overview,
          badge: requests,
        ),
        const AdminDestination(
          label: 'Employees',
          icon: Icons.groups_outlined,
          selectedIcon: Icons.groups_rounded,
          path: EmployerPaths.employees,
        ),
        const AdminDestination(
          label: 'Rosters & Policies',
          icon: Icons.rule_outlined,
          selectedIcon: Icons.rule_rounded,
          path: EmployerPaths.policies,
        ),
        const AdminDestination(
          label: 'Pickup Locations',
          icon: Icons.place_outlined,
          selectedIcon: Icons.place_rounded,
          path: EmployerPaths.locations,
        ),
        AdminDestination(
          label: 'Fleet Assignments',
          icon: Icons.directions_car_outlined,
          selectedIcon: Icons.directions_car_rounded,
          path: EmployerPaths.assignments,
          badge: alerts.trips.length,
        ),
        const AdminDestination(
          label: 'Traffic & Movement',
          icon: Icons.traffic_outlined,
          selectedIcon: Icons.traffic_rounded,
          path: EmployerPaths.traffic,
        ),
        AdminDestination(
          label: 'Billing',
          icon: Icons.receipt_long_outlined,
          selectedIcon: Icons.receipt_long_rounded,
          path: EmployerPaths.billing,
          badge: billing + due,
        ),
        const AdminDestination(
          label: 'Reports',
          icon: Icons.insights_outlined,
          selectedIcon: Icons.insights_rounded,
          path: EmployerPaths.reports,
        ),
        const AdminDestination(
          label: 'Analytics & Carbon',
          icon: Icons.eco_outlined,
          selectedIcon: Icons.eco_rounded,
          path: EmployerPaths.analytics,
        ),
        const AdminDestination(
          label: 'Settings',
          icon: Icons.settings_outlined,
          selectedIcon: Icons.settings_rounded,
          path: EmployerPaths.settings,
        ),
      ],
      child: child,
    );
  }
}

class _EmployerNotificationsPage extends StatelessWidget {
  const _EmployerNotificationsPage();

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.sizeOf(context).width < 720
        ? AppSpace.md
        : AppSpace.xl;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: NotificationsList(
          role: UserRole.employerAdmin,
          padding: EdgeInsets.fromLTRB(pad, pad, pad, AppSpace.xxxl),
          onOpen: (n) {
            final id = n.relatedEntityId;
            if (id == null) return;
            switch (n.relatedEntityType) {
              case 'trip':
                context.go(EmployerPaths.trip(id));
              case 'billing':
                context.go(EmployerPaths.bill(id));
              case 'employee':
                context.go(EmployerPaths.employee(id));
              case 'booking':
                final b = ProviderScope.containerOf(
                  context,
                  listen: false,
                ).read(dataProvider).booking(id);
                context.go(
                  b == null
                      ? EmployerPaths.overview
                      : EmployerPaths.employee(b.employeeId),
                );
              case 'employer':
                context.go(EmployerPaths.policies);
              case 'invoice':
                context.go(EmployerPaths.invoice(id));
              case 'traffic':
                context.go(EmployerPaths.traffic);
              case 'contract':
                context.go(EmployerPaths.settings);
              case 'incident':
                final inc = ProviderScope.containerOf(
                  context,
                  listen: false,
                ).read(dataProvider).incident(id);
                if (inc != null && inc.isSos) {
                  context.go(EmployerPaths.sos(id));
                  return;
                }
                final tripId = ProviderScope.containerOf(
                  context,
                  listen: false,
                ).read(dataProvider).incident(id)?.tripId;
                context.go(
                  tripId == null
                      ? EmployerPaths.assignments
                      : EmployerPaths.trip(tripId),
                );
            }
          },
        ),
      ),
    );
  }
}
