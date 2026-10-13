import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import 'employer_common.dart';

/// SOS incidents concerning [employerId] (its trips or its employees).
bool sosConcernsEmployer(DataView d, Incident i, String employerId) {
  if (!i.isSos) return false;
  if (d.trips.byId(i.tripId)?.employerId == employerId) return true;
  return i.reportedByRole == UserRole.employee &&
      d.employee(i.reportedById)?.employerId == employerId;
}

List<Incident> openEmployerSos(DataView d) => d.openIncidents
    .where((i) => sosConcernsEmployer(d, i, d.primaryEmployer.id))
    .toList();

StatusTone sosDispatchTone(SosDispatchStatus s) => switch (s) {
  SosDispatchStatus.alertedInApp => StatusTone.warning,
  SosDispatchStatus.acknowledged => StatusTone.success,
  SosDispatchStatus.integrationRequired => StatusTone.neutral,
  SosDispatchStatus.disabled => StatusTone.neutral,
};

String sosReporter(DataView d, Incident i) => switch (i.reportedByRole) {
  UserRole.employee => d.employeeLabel(i.reportedById ?? ''),
  UserRole.driver =>
    'Driver ${d.driver(i.reportedById)?.name ?? i.reportedById}',
  _ => i.reportedByRole.label,
};

Future<void> acknowledgeCompanySos(
  BuildContext context,
  WidgetRef ref,
  SosDispatch dispatch,
) async {
  final ok = await showConfirmDialog(
    context,
    title: 'Acknowledge SOS escalation?',
    message:
        'Records that the company administrator has seen this alert. ${DemoLabels.sosDemo}',
    confirmLabel: 'Acknowledge',
  );
  if (!ok || !context.mounted) return;
  final r = await ref
      .read(servicesProvider)
      .incidents
      .acknowledgeSos(dispatch.id, actor: Actor.employerAdmin);
  if (context.mounted) {
    await showResult(context, r, successMessage: 'Acknowledged (local demo)');
  }
}

/// Escalation chain rows with the company-admin acknowledge action.
class SosChain extends ConsumerWidget {
  const SosChain({super.key, required this.incident, this.dense = false});
  final Incident incident;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final chain = data.sosDispatchesOf(incident.id);
    final t = Theme.of(context).textTheme;
    if (chain.isEmpty) {
      return Text(
        'No escalation chain recorded.',
        style: AppText.muted(context),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < chain.length; i++)
          Padding(
            padding: EdgeInsets.symmetric(vertical: dense ? 3 : 6),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '${i + 1}.',
                    style: t.labelMedium!.copyWith(color: AppColors.textMuted),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(chain[i].recipient.label, style: t.titleSmall),
                      if (!dense || chain[i].acknowledgedAt != null)
                        Text(
                          chain[i].acknowledgedAt != null
                              ? 'Acknowledged ${Fmt.time(chain[i].acknowledgedAt)}${chain[i].acknowledgedBy != null ? ' by ${chain[i].acknowledgedBy}' : ''}'
                              : '${chain[i].channel}${chain[i].note.isNotEmpty ? ' · ${chain[i].note}' : ''}',
                          style: AppText.muted(context),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.xs),
                if (chain[i].recipient == SosRecipient.companyAdmin &&
                    chain[i].status == SosDispatchStatus.alertedInApp)
                  FilledButton(
                    key: Key('ack-${chain[i].id}'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    onPressed: () =>
                        acknowledgeCompanySos(context, ref, chain[i]),
                    child: const Text('Acknowledge'),
                  )
                else
                  Flexible(
                    child: StatusBadge(
                      chain[i].status.label,
                      tone: sosDispatchTone(chain[i].status),
                      dense: true,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Overview card listing open SOS alerts for the employer.
class SosAlertsCard extends ConsumerWidget {
  const SosAlertsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final open = openEmployerSos(data);
    final t = Theme.of(context).textTheme;
    return AppCard(
      key: const Key('sos-card'),
      borderColor: open.isEmpty
          ? AppColors.border
          : AppColors.danger.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Open SOS alerts',
            subtitle: open.isEmpty
                ? 'No open alerts for ${data.primaryEmployer.code}'
                : '${open.length} open · escalation chain shown',
            trailing: open.isEmpty
                ? const StatusBadge(
                    'All clear',
                    tone: StatusTone.success,
                    dense: true,
                  )
                : StatusBadge(
                    '${open.length} open',
                    tone: StatusTone.danger,
                    dense: true,
                  ),
          ),
          for (final i in open) ...[
            const Divider(height: AppSpace.lg),
            Row(
              children: [
                const Icon(Icons.sos_rounded, color: AppColors.danger),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${i.reference} · ${sosReporter(data, i)}',
                        style: t.titleSmall,
                      ),
                      Text(
                        '${Fmt.ago(i.createdAt, data.now)}${i.tripId != null ? ' · ${i.tripId}' : ''} · ${i.status.label}',
                        style: AppText.muted(context),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => context.go(EmployerPaths.sos(i.id)),
                  child: const Text('Details'),
                ),
              ],
            ),
            SosChain(incident: i, dense: true),
          ],
          const SizedBox(height: AppSpace.xs),
          const SimulatedNote(
            DemoLabels.sosDemo,
            icon: Icons.info_outline_rounded,
          ),
        ],
      ),
    );
  }
}

/// SOS detail with escalation chain (opened from notifications).
class SosDetailPage extends ConsumerWidget {
  const SosDetailPage({super.key, required this.incidentId});
  final String incidentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final i = data.incident(incidentId);
    if (i == null || !sosConcernsEmployer(data, i, data.primaryEmployer.id)) {
      return EmptyState(
        icon: Icons.sos_outlined,
        title: 'SOS alert not available',
        message:
            'This alert does not exist or does not concern ${data.primaryEmployer.code}.',
        actionLabel: 'Back to overview',
        onAction: () => context.go(EmployerPaths.overview),
      );
    }
    final trip = data.trips.byId(i.tripId);
    return AdminPage(
      title: 'SOS ${i.reference}',
      subtitle: '${sosReporter(data, i)} · ${Fmt.dateTime(i.createdAt)}',
      actions: [
        TextButton.icon(
          onPressed: () => context.go(EmployerPaths.overview),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Overview'),
        ),
        StatusBadge(i.status.label, tone: Tones.incident(i.status)),
      ],
      children: [
        const InlineBanner(
          tone: StatusTone.danger,
          icon: Icons.sos_rounded,
          title: 'Demo SOS',
          message: '${DemoLabels.sosDemo} ${DemoLabels.sosAlternative}',
        ),
        const SizedBox(height: AppSpace.md),
        ResponsiveColumns(
          left: PanelCard(
            title: 'Escalation chain',
            subtitle:
                'Recipients in order; only in-app alerts are delivered in this prototype',
            child: SosChain(incident: i),
          ),
          right: PanelCard(
            title: 'Alert',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KeyValueRow(
                  label: 'Severity',
                  valueWidget: StatusBadge(
                    i.severity.label,
                    tone: Tones.severity(i.severity),
                    dense: true,
                  ),
                ),
                KeyValueRow(label: 'Raised by', value: sosReporter(data, i)),
                KeyValueRow(
                  label: 'Location',
                  value: i.demoLocationLabel ?? 'Unknown (simulated)',
                ),
                if (trip != null)
                  KeyValueRow(
                    label: 'Trip',
                    valueWidget: TextButton(
                      onPressed: () => context.go(EmployerPaths.trip(trip.id)),
                      child: Text(trip.tripCode),
                    ),
                  ),
                const SizedBox(height: AppSpace.xs),
                Text(i.description, style: AppText.secondary(context)),
                if (i.resolutionNotes != null) ...[
                  const SizedBox(height: AppSpace.sm),
                  InlineBanner(
                    tone: StatusTone.success,
                    title: 'Resolution',
                    message: i.resolutionNotes,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
