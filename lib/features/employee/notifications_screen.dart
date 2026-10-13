import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import '../shared/notifications_view.dart';
import 'employee_common.dart';

class EmployeeNotificationsScreen extends ConsumerWidget {
  const EmployeeNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = ref.watch(currentEmployeeProvider);
    if (e == null) return const Scaffold(body: LoadingState());
    return EmployeeTextScale(
      child: Scaffold(
        appBar: AppBar(title: const Text('Notifications')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: NotificationsList(
              role: UserRole.employee,
              recipientId: e.id,
              onOpen: (n) => openEmployeeEntity(
                context,
                n.relatedEntityType,
                n.relatedEntityId,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
