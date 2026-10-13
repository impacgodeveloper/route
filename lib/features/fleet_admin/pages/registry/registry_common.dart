import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../domain/models/models.dart';
import '../../widgets/fleet_common.dart';

/// "08:45" style label for a daily window (overnight marked).
String windowLabel(int start, int end) =>
    '${Fmt.hhmm(start)}–${Fmt.hhmm(end)}${end < start ? ' (overnight)' : ''}';

StatusTone contractTone(ContractValidity v) => switch (v) {
  ContractValidity.active => StatusTone.success,
  ContractValidity.notYetValid => StatusTone.info,
  ContractValidity.draft => StatusTone.neutral,
  ContractValidity.expired => StatusTone.warning,
  ContractValidity.suspended => StatusTone.warning,
  ContractValidity.terminated => StatusTone.danger,
};

/// Read-only list of company allocations for one vehicle or driver.
class ResourceAllocationsPanel extends ConsumerWidget {
  const ResourceAllocationsPanel({
    super.key,
    required this.type,
    required this.resourceId,
  });

  final ResourceType type;
  final String resourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final rows =
        data.allocationsFor(type, resourceId).where((a) => a.active).toList()
          ..sort(
            (a, b) => a.windowStartMinutes.compareTo(b.windowStartMinutes),
          );
    return PanelCard(
      title: 'Company allocations',
      subtitle:
          'Which companies may use this ${type.label.toLowerCase()} and when',
      child: rows.isEmpty
          ? Text(
              'No allocation records — treated as an unrestricted shared-pool resource.',
              style: AppText.muted(context),
            )
          : Column(
              children: [
                for (final a in rows)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule_rounded),
                    title: Text(
                      '${data.employer(a.employerId)?.code ?? a.employerId} · ${data.employer(a.employerId)?.name ?? ''}',
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${windowLabel(a.windowStartMinutes, a.windowEndMinutes)}${a.label.isEmpty ? '' : ' · ${a.label}'}',
                    ),
                    trailing: TextButton(
                      onPressed: () => context.go(
                        '/fleet/companies/${a.employerId}?tab=allocations',
                      ),
                      child: const Text('Manage'),
                    ),
                  ),
              ],
            ),
    );
  }
}
