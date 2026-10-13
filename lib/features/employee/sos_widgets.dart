import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';

IconData _recipientIcon(SosRecipient r) => switch (r) {
  SosRecipient.fleetManager => Icons.hub_outlined,
  SosRecipient.companyAdmin => Icons.business_outlined,
  SosRecipient.supportTeam => Icons.support_agent_outlined,
  SosRecipient.police => Icons.local_police_outlined,
  SosRecipient.driver => Icons.drive_eta_outlined,
  SosRecipient.emergencyContact => Icons.contact_phone_outlined,
};

StatusTone _statusTone(SosDispatchStatus s) => switch (s) {
  SosDispatchStatus.alertedInApp => StatusTone.info,
  SosDispatchStatus.acknowledged => StatusTone.success,
  SosDispatchStatus.integrationRequired => StatusTone.warning,
  SosDispatchStatus.disabled => StatusTone.neutral,
};

/// Live SOS escalation chain for [incidentId]. Rebuilds as recipients
/// acknowledge. Every channel is local/demo; police is never contacted.
class SosChainList extends ConsumerWidget {
  const SosChainList({super.key, required this.incidentId});
  final String incidentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final t = Theme.of(context).textTheme;
    final chain = [...data.sosDispatchesOf(incidentId)]
      ..sort((a, b) => a.recipient.index.compareTo(b.recipient.index));
    if (chain.isEmpty) {
      return Text(
        'No escalation recipients are configured. ${DemoLabels.sosAlternative}',
        style: AppText.muted(context),
      );
    }
    final acknowledged = chain
        .where((d) => d.status == SosDispatchStatus.acknowledged)
        .length;
    final alerted = chain
        .where(
          (d) =>
              d.status == SosDispatchStatus.alertedInApp ||
              d.status == SosDispatchStatus.acknowledged,
        )
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('ESCALATION', style: AppText.overline(context)),
        const SizedBox(height: 2),
        Text(
          '$acknowledged of $alerted in-app recipients acknowledged',
          style: t.bodySmall!.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpace.xs),
        Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: AppRadius.mdAll,
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              for (var i = 0; i < chain.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 52),
                _row(context, t, chain[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, TextTheme t, SosDispatch d) {
    final tone = _statusTone(d.status);
    final label =
        d.status == SosDispatchStatus.acknowledged && d.acknowledgedAt != null
        ? 'Acknowledged ${Fmt.time(d.acknowledgedAt)}'
        : d.status.label;
    return Semantics(
      label: '${d.recipient.label}: $label',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.sm,
          vertical: 10,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconTile(
              icon: _recipientIcon(d.recipient),
              color: tone.foreground,
              background: tone.background,
              size: 32,
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.recipient.label, style: t.titleSmall),
                  const SizedBox(height: 4),
                  StatusBadge(label, tone: tone, dense: true),
                  if (d.note.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(d.note, style: AppText.muted(context)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
