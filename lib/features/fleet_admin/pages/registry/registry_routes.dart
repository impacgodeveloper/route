import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'companies_page.dart';
import 'company_detail_page.dart';

/// Companies, contracts and fleet-company allocations.
List<RouteBase> registryRoutes(
  Page<void> Function(GoRouterState s, Widget child) page,
) => [
  GoRoute(
    path: '/fleet/companies',
    pageBuilder: (c, s) => page(s, const CompaniesPage()),
    routes: [
      GoRoute(
        path: 'new',
        pageBuilder: (c, s) => page(s, const RegisterCompanyPage()),
      ),
      GoRoute(
        path: ':id',
        pageBuilder: (c, s) => page(
          s,
          CompanyDetailPage(
            key: ValueKey(
              'company-${s.pathParameters['id']}-${s.uri.queryParameters['tab']}',
            ),
            companyId: s.pathParameters['id']!,
            initialTab: s.uri.queryParameters['tab'],
          ),
        ),
      ),
    ],
  ),
];
