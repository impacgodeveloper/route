import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../shared/support_ticket_form.dart';
import 'employee_common.dart';

class EmployeeSupportScreen extends ConsumerWidget {
  const EmployeeSupportScreen({super.key, this.tripId});
  final String? tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final e = ref.watch(currentEmployeeProvider);
    if (e == null) return const Scaffold(body: LoadingState());
    final trips = data.trips.forEmployee(e.id).reversed.take(15).toList();
    final initial = trips.any((t) => t.id == tripId) ? tripId : null;
    return EmployeeSubPage(
      title: 'New support ticket',
      children: [
        Text(
          'Tell us what happened. Include the trip if it relates to a ride.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium!.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpace.lg),
        SupportTicketForm(
          actor: Actor.employee(e.id),
          tripOptions: trips,
          initialTripId: initial,
          onSubmitted: (_) => context.pop(),
        ),
      ],
    );
  }
}
