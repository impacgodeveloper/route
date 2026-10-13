import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../shared/traffic_board.dart';
import 'employer_common.dart';

/// Read-only traffic & movement view for the employer's trips.
/// Scenario changes and schedule revisions are Fleet Manager operations.
class EmployerTrafficPage extends ConsumerWidget {
  const EmployerTrafficPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employer = ref.watch(dataProvider).primaryEmployer;
    return AdminPage(
      title: 'Traffic & Movement',
      subtitle:
          'Route status for ${employer.code} trips. ${DemoLabels.trafficSimulated}.',
      children: [
        const InlineBanner(
          tone: StatusTone.info,
          icon: Icons.lock_outline_rounded,
          title: 'Read-only for employer admins',
          message:
              'Traffic scenarios and schedule changes are reviewed and applied by the Fleet Manager. Updates appear here immediately.',
        ),
        const SizedBox(height: AppSpace.md),
        TrafficBoard(
          readOnly: true,
          companyId: employer.id,
          onOpenTrip: (trip) => context.go(EmployerPaths.trip(trip.id)),
        ),
      ],
    );
  }
}
