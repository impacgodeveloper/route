import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../domain/models/models.dart';
import '../../../shared/audit_trail_view.dart';
import '../../widgets/fleet_common.dart';
import 'registry_common.dart';
import 'registry_editors.dart';

enum CompanyTab {
  overview('Overview'),
  contracts('Contracts'),
  allocations('Fleet allocations'),
  audit('Audit');

  const CompanyTab(this.label);
  final String label;

  static CompanyTab parse(String? s) =>
      CompanyTab.values.where((t) => t.name == s).firstOrNull ??
      CompanyTab.overview;
}

class CompanyDetailPage extends ConsumerStatefulWidget {
  const CompanyDetailPage({
    super.key,
    required this.companyId,
    this.initialTab,
  });
  final String companyId;
  final String? initialTab;

  @override
  ConsumerState<CompanyDetailPage> createState() => _CompanyDetailPageState();
}

class _CompanyDetailPageState extends ConsumerState<CompanyDetailPage> {
  late CompanyTab _tab = CompanyTab.parse(widget.initialTab);

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final e = data.employer(widget.companyId);
    if (e == null) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Company not found',
        message: 'It may have been removed by a demo reset.',
        actionLabel: 'All companies',
        onAction: () => context.go('/fleet/companies'),
      );
    }
    return AdminPage(
      title: 'Company ${e.code} · ${e.name}',
      subtitle:
          'Registered ${Fmt.date(e.createdAt)} · ${e.contactName.isEmpty ? 'no contact' : e.contactName}${e.contactEmail.isEmpty ? '' : ' (${e.contactEmail})'}',
      actions: [
        TextButton.icon(
          onPressed: () => context.go('/fleet/companies'),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Companies'),
        ),
        StatusBadge(
          e.status.label,
          tone: e.isActive ? StatusTone.success : StatusTone.neutral,
        ),
      ],
      children: [
        FilterChipBar<CompanyTab>(
          options: CompanyTab.values,
          selected: _tab,
          onSelected: (t) => setState(() => _tab = t),
          labelOf: (t) => t.label,
        ),
        const SizedBox(height: AppSpace.md),
        switch (_tab) {
          CompanyTab.overview => _Overview(company: e),
          CompanyTab.contracts => _Contracts(company: e),
          CompanyTab.allocations => _Allocations(company: e),
          CompanyTab.audit => AuditTrailView(
            companyId: e.id,
            onOpenEntity: (type, id) {
              final path = switch (type) {
                'trip' => '/fleet/dispatch/trip/$id',
                'vehicle' => '/fleet/vehicles/$id',
                'driver' => '/fleet/drivers/$id',
                'incident' => '/fleet/monitoring/incident/$id',
                _ => null,
              };
              if (path != null) context.go(path);
            },
          ),
        },
      ],
    );
  }
}

class _Overview extends ConsumerWidget {
  const _Overview({required this.company});
  final Employer company;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final e = company;
    final usage = ref.read(servicesProvider).contracts.usage(e.id, data.today);
    final upcoming = data.trips
        .all()
        .where((t) => t.employerId == e.id && t.status.isUpcoming)
        .length;

    Future<void> toggle() async {
      final reason = await showReasonDialog(
        context,
        title: e.isActive
            ? 'Deactivate company ${e.code}?'
            : 'Reactivate company ${e.code}?',
        message: e.isActive
            ? 'History (trips, billing, audit) is preserved. Blocked while upcoming trips exist.'
            : 'The company can be scheduled again.',
        confirmLabel: e.isActive ? 'Deactivate' : 'Reactivate',
        destructive: e.isActive,
      );
      if (reason == null || !context.mounted) return;
      await runAndShow(
        context,
        ref
            .read(servicesProvider)
            .employers
            .setActive(e.id, !e.isActive, reason: reason.reason),
      );
    }

    final counts = PanelCard(
      title: 'Company metadata',
      subtitle: 'Derived from linked records',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StatStrip(
            stats: [
              ('Active employees', '${data.companyEmployeeCount(e.id)}'),
              ('Configured shifts', '${data.companyShiftCount(e.id)}'),
              ('Active locations', '${data.companyLocationCount(e.id)}'),
              ('Upcoming trips', '$upcoming'),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          KeyValueRow(
            label: 'Max office arrival',
            value: Fmt.minutesOfDay(e.maximumArrivalMinutes),
          ),
          KeyValueRow(
            label: 'Pickup tolerance',
            value: '±${e.pickupToleranceMinutes} min',
          ),
          KeyValueRow(
            label: 'Billing',
            value:
                '${e.billingCycle.label} · ${Fmt.inr(e.defaultDistanceRate)}/km${e.billingActive ? '' : ' · paused'}',
          ),
          KeyValueRow(
            label: 'Pooling',
            value: e.allowSharedPooling
                ? (e.allowCrossEmployerPooling
                      ? 'Shared, cross-company allowed'
                      : 'Shared within company')
                : 'Not allowed',
          ),
          KeyValueRow(
            label: 'Guard policy',
            value: e.securityGuardPolicyEnabled ? 'Enabled' : 'Disabled',
          ),
          KeyValueRow(
            label: 'Contract today',
            value: usage.contract == null
                ? 'No active contract'
                : '${usage.contract!.contractCode} · ${usage.used}/${usage.allowed} cars used',
          ),
          const SizedBox(height: AppSpace.md),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: toggle,
              icon: Icon(
                e.isActive
                    ? Icons.block_outlined
                    : Icons.check_circle_outline_rounded,
              ),
              label: Text(e.isActive ? 'Deactivate company' : 'Reactivate'),
            ),
          ),
        ],
      ),
    );

    final shifts = PanelCard(
      title: 'Shifts',
      subtitle: 'Configured by the company\'s Employer Admin (read-only here)',
      child: e.shifts.isEmpty
          ? Text('No shifts configured yet.', style: AppText.muted(context))
          : Column(
              children: [
                for (final s in e.shifts)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule_rounded),
                    title: Text(s.label),
                    subtitle: Text(
                      '${windowLabel(s.startMinutes, s.endMinutes)} · ${data.employeesOf(e.id).where((x) => x.isActive && x.shiftStartMinutes == s.startMinutes).length} employees',
                    ),
                  ),
              ],
            ),
    );
    return ResponsiveSplit(left: counts, right: shifts);
  }
}

class _Contracts extends ConsumerWidget {
  const _Contracts({required this.company});
  final Employer company;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final today = data.today;
    final contracts = data.contractsOf(company.id);
    final usage = ref.read(servicesProvider).contracts.usage(company.id, today);
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                usage.contract == null
                    ? 'No active contract today — assignments for ${company.code} are blocked.'
                    : 'Today: ${usage.used} of ${usage.allowed} contracted car(s) in use under ${usage.contract!.contractCode}.',
                style: t.bodyMedium!.copyWith(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            FilledButton.icon(
              onPressed: () => showContractEditor(context, company: company),
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('New contract'),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        if (contracts.isEmpty)
          const EmptyState(
            icon: Icons.description_outlined,
            title: 'No contracts',
            message:
                'Without contract records the company is not restricted by a car limit. Create one to enforce validity and agreed cars.',
            compact: true,
          )
        else
          for (final c in contracts)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: _ContractCard(contract: c),
            ),
        const SimulatedNote(
          'Agreed cost per car is informational for fleet cost views — trip billing stays distance-based. Document references are metadata only; no file is uploaded.',
          icon: Icons.info_outline_rounded,
        ),
      ],
    );
  }
}

class _ContractCard extends ConsumerWidget {
  const _ContractCard({required this.contract});
  final Contract contract;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final c = contract;
    final v = c.validityOn(data.today);
    final t = Theme.of(context).textTheme;
    final warnings = ref.read(servicesProvider).contracts.warnings(c);

    Future<void> setStatus(ContractStatus s) async {
      final reason = await showReasonDialog(
        context,
        title: '${s.label} ${c.contractCode}?',
        confirmLabel: s.label,
        destructive: s == ContractStatus.terminated,
      );
      if (reason == null || !context.mounted) return;
      await runAndShow(
        context,
        ref
            .read(servicesProvider)
            .contracts
            .setStatus(c.id, s, reason: reason.reason),
      );
    }

    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(c.contractCode, style: t.titleSmall)),
              StatusBadge(v.label, tone: contractTone(v), dense: true),
              PopupMenuButton<String>(
                tooltip: 'Actions for ${c.contractCode}',
                onSelected: (a) {
                  switch (a) {
                    case 'edit':
                      showContractEditor(
                        context,
                        company: data.employer(c.employerId)!,
                        contract: c,
                      );
                    case 'activate':
                      setStatus(ContractStatus.active);
                    case 'suspend':
                      setStatus(ContractStatus.suspended);
                    case 'terminate':
                      setStatus(ContractStatus.terminated);
                  }
                },
                itemBuilder: (_) => [
                  if (c.status != ContractStatus.terminated)
                    const PopupMenuItem(value: 'edit', child: Text('Edit…')),
                  if (c.status == ContractStatus.draft ||
                      c.status == ContractStatus.suspended)
                    const PopupMenuItem(
                      value: 'activate',
                      child: Text('Activate…'),
                    ),
                  if (c.status == ContractStatus.active)
                    const PopupMenuItem(
                      value: 'suspend',
                      child: Text('Suspend…'),
                    ),
                  if (c.status != ContractStatus.terminated)
                    const PopupMenuItem(
                      value: 'terminate',
                      child: Text('Terminate…'),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: AppSpace.lg,
            runSpacing: 4,
            children: [
              Text(
                'Valid ${Fmt.date(c.validFrom)} – ${Fmt.date(c.validUntil)}',
                style: t.bodySmall,
              ),
              Text(
                '${c.agreedVehicleCount} car(s) · ${c.hardVehicleLimit ? 'hard' : 'soft'} limit',
                style: t.bodySmall,
              ),
              Text(
                '${Fmt.inr0(c.costPerVehicle)} per car / ${c.costPeriod}',
                style: t.bodySmall,
              ),
              Text('Doc: ${c.documentRef}', style: t.bodySmall),
              if (c.contactName.isNotEmpty)
                Text(
                  'Contact: ${c.contactName}${c.contactId.isEmpty ? '' : ' (${c.contactId})'}',
                  style: t.bodySmall,
                ),
            ],
          ),
          if (c.notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(c.notes, style: AppText.muted(context)),
          ],
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            InlineBanner(
              tone: StatusTone.warning,
              title: 'Attention',
              messages: warnings,
            ),
          ],
        ],
      ),
    );
  }
}

class _Allocations extends ConsumerWidget {
  const _Allocations({required this.company});
  final Employer company;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final t = Theme.of(context).textTheme;
    final active = data.allocationsOf(company.id).where((a) => a.active);
    // Group by window (client view: car array / driver array / shift window).
    final groups = <(int, int, String), List<FleetAllocation>>{};
    for (final a in active) {
      groups
          .putIfAbsent((
            a.windowStartMinutes,
            a.windowEndMinutes,
            a.label,
          ), () => [])
          .add(a);
    }
    final keys = groups.keys.toList()..sort((a, b) => a.$1.compareTo(b.$1));

    Widget chip(FleetAllocation a) => InputChip(
      key: Key('alloc-${a.id}'),
      label: Text(
        a.resourceType == ResourceType.vehicle
            ? 'Vehicle ${a.resourceId}'
            : a.resourceId,
      ),
      onPressed: () =>
          showAllocationEditor(context, company: company, allocation: a),
      deleteButtonTooltipMessage: 'Remove ${a.resourceId}',
      onDeleted: () async {
        final ok = await showConfirmDialog(
          context,
          title: 'Remove ${a.resourceId} from ${company.code}?',
          message:
              'The allocation is deactivated (kept for audit history). Future assignments in this window will be blocked.',
          confirmLabel: 'Remove',
          destructive: true,
        );
        if (!ok || !context.mounted) return;
        await runAndShow(
          context,
          ref.read(servicesProvider).allocations.remove(a.id),
          successMessage: 'Allocation removed',
        );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Vehicles and drivers eligible to serve ${company.code}, by daily window. Vehicles can be shared with other companies in non-overlapping windows; an allocation never bypasses status, inspection, capacity or availability rules.',
                style: t.bodyMedium!.copyWith(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            FilledButton.icon(
              onPressed: () => showAllocationEditor(context, company: company),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add allocation'),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        if (keys.isEmpty)
          const EmptyState(
            icon: Icons.event_busy_outlined,
            title: 'No fleet allocations',
            message:
                'Without allocation records, pool vehicles and drivers are unrestricted for this company.',
            compact: true,
          )
        else
          for (final k in keys)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: AppCard(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${k.$3.isEmpty ? 'Window' : k.$3} · ${windowLabel(k.$1, k.$2)}',
                      style: t.titleSmall,
                    ),
                    const SizedBox(height: AppSpace.xs),
                    Text('Car IDs', style: AppText.muted(context)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final a in groups[k]!.where(
                          (a) => a.resourceType == ResourceType.vehicle,
                        ))
                          chip(a),
                      ],
                    ),
                    const SizedBox(height: AppSpace.xs),
                    Text('Driver IDs', style: AppText.muted(context)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final a in groups[k]!.where(
                          (a) => a.resourceType == ResourceType.driver,
                        ))
                          chip(a),
                      ],
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
