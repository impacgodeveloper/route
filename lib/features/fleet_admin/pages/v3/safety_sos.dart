import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../domain/models/models.dart';
import '../../widgets/fleet_common.dart';

StatusTone sosTone(SosDispatchStatus s) => switch (s) {
  SosDispatchStatus.alertedInApp => StatusTone.warning,
  SosDispatchStatus.acknowledged => StatusTone.success,
  SosDispatchStatus.integrationRequired => StatusTone.danger,
  SosDispatchStatus.disabled => StatusTone.neutral,
};

/// SOS escalation chain for one incident, with in-app acknowledgement.
/// External recipients (police) are never contacted by this prototype.
class SosChainView extends ConsumerWidget {
  const SosChainView({super.key, required this.incidentId, this.dense = false});
  final String incidentId;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final t = Theme.of(context).textTheme;
    final chain = data.sosDispatchesOf(incidentId);
    if (chain.isEmpty) {
      return Text(
        'No escalation chain recorded for this incident.',
        style: AppText.muted(context),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < chain.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: dense ? 4 : AppSpace.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: sosTone(chain[i].status).background,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: t.labelSmall!.copyWith(
                      color: sosTone(chain[i].status).foreground,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(chain[i].recipient.label, style: t.titleSmall),
                      if (!dense)
                        Text(
                          [
                            chain[i].channel,
                            if (chain[i].acknowledgedAt != null)
                              'acknowledged ${Fmt.time(chain[i].acknowledgedAt)} by ${chain[i].acknowledgedBy ?? '—'}',
                            if (chain[i].note.isNotEmpty) chain[i].note,
                          ].join(' · '),
                          style: AppText.muted(context),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.xs),
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: chain[i].status == SosDispatchStatus.alertedInApp
                        ? OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 40),
                            ),
                            onPressed: () => runAndShow(
                              context,
                              ref
                                  .read(servicesProvider)
                                  .incidents
                                  .acknowledgeSos(chain[i].id),
                              successMessage:
                                  '${chain[i].recipient.label} acknowledged',
                            ),
                            child: Text(
                              'Acknowledge',
                              key: ValueKey('ack-${chain[i].id}'),
                            ),
                          )
                        : StatusBadge(
                            chain[i].status.label,
                            tone: sosTone(chain[i].status),
                            dense: true,
                          ),
                  ),
                ),
              ],
            ),
          ),
        if (!dense) ...[
          const SizedBox(height: AppSpace.xs),
          const SimulatedNote(DemoLabels.sosDemo),
        ],
      ],
    );
  }
}

/// SOS tab: open SOS incidents with their chain, plus history.
class SafetySosTab extends ConsumerWidget {
  const SafetySosTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final t = Theme.of(context).textTheme;
    final sos = data.incidents.where((i) => i.isSos).toList();
    final open = sos.where((i) => i.status.isOpen).toList();
    final closed = sos.where((i) => !i.status.isOpen).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const InlineBanner(
          tone: StatusTone.warning,
          title: 'Demo escalation only',
          message:
              '${DemoLabels.sosDemo} Police (112) is shown as "Not contacted — integration required"; no telephony integration exists in this prototype.',
        ),
        const SizedBox(height: AppSpace.md),
        if (open.isEmpty)
          const AppCard(
            child: EmptyState(
              icon: Icons.verified_user_outlined,
              title: 'No open SOS',
              message:
                  'SOS raised from the Employee or Driver app appears here with its escalation chain.',
              compact: true,
            ),
          ),
        for (final i in open) ...[
          PanelCard(
            title: 'SOS ${i.reference} · ${i.severity.label}',
            subtitle:
                '${Fmt.dateTime(i.createdAt)} · ${i.reportedByRole.label} ${i.reportedById ?? ''}${i.tripId != null ? ' · ${i.tripId}' : ''}',
            trailing: TextButton(
              onPressed: () => context.go('/fleet/monitoring/incident/${i.id}'),
              child: const Text('Open incident'),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(i.description, style: t.bodyMedium),
                if (i.demoLocationLabel != null)
                  Text(
                    'Location: ${i.demoLocationLabel}',
                    style: AppText.muted(context),
                  ),
                const SizedBox(height: AppSpace.sm),
                SosChainView(incidentId: i.id),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        PanelCard(
          title: 'SOS history',
          subtitle: '${closed.length} resolved or closed',
          child: closed.isEmpty
              ? Text('No closed SOS records.', style: AppText.muted(context))
              : Column(
                  children: [
                    for (final i in closed)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.sos_rounded,
                          color: AppColors.textMuted,
                        ),
                        title: Text(
                          '${i.reference} · ${Fmt.dateTime(i.createdAt)}',
                        ),
                        subtitle: Text(
                          '${i.status.label} · ${data.sosDispatchesOf(i.id).where((d) => d.status == SosDispatchStatus.acknowledged).length}/${data.sosDispatchesOf(i.id).length} acknowledged${i.resolutionNotes != null ? ' · ${i.resolutionNotes}' : ''}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () =>
                            context.go('/fleet/monitoring/incident/${i.id}'),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
