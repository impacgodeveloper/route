import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import 'billing_page.dart';
import 'employer_common.dart';

enum BillingTab {
  cycles('Cycles & invoices'),
  lines('Trip lines'),
  config('Configuration');

  const BillingTab(this.label);
  final String label;

  static BillingTab parse(String? s) =>
      BillingTab.values.where((t) => t.name == s).firstOrNull ??
      BillingTab.cycles;
}

StatusTone invoiceTone(InvoiceStatus s) => switch (s) {
  InvoiceStatus.generated => StatusTone.info,
  InvoiceStatus.reviewed => StatusTone.teal,
  InvoiceStatus.paidDemo => StatusTone.success,
  InvoiceStatus.disputed => StatusTone.danger,
};

/// Billing: weekly/monthly cycles & invoices, per-trip lines, configuration.
class BillingPage extends ConsumerStatefulWidget {
  const BillingPage({super.key, this.initialTab});
  final String? initialTab;

  @override
  ConsumerState<BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends ConsumerState<BillingPage> {
  late BillingTab _tab = BillingTab.parse(widget.initialTab);
  BillingPeriod? _period;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final cycles = ref.read(servicesProvider).billingCycles;
    final employer = data.primaryEmployer;
    final current = cycles.currentPeriod(employer);
    final due = cycles.dueCycles(employer.id);
    return AdminPage(
      title: 'Billing',
      subtitle:
          'totalAmount = distanceKm × ratePerKm + additionalCharges + adjustment · ${employer.billingCycle.label} · '
          '${employer.billingActive ? 'next boundary ${Fmt.weekday(current.nextBoundary)}' : 'billing paused'}',
      children: [
        if (due.isNotEmpty) ...[
          InlineBanner(
            key: const Key('due-cycles'),
            tone: StatusTone.warning,
            icon: Icons.event_repeat_outlined,
            title:
                '${due.length} billing cycle${due.length == 1 ? '' : 's'} due',
            messages: [
              for (final p in due)
                '${p.period.label}: ${p.eligible.length} eligible trip${p.eligible.length == 1 ? '' : 's'} · ${Fmt.inr(p.total)}',
              'Checked when the app opens — there is no background scheduler in this prototype.',
            ],
            actions: [
              TextButton(
                onPressed: () => setState(() {
                  _tab = BillingTab.cycles;
                  _period = due.first.period;
                }),
                child: const Text('Review due cycle'),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<BillingTab>(
              showSelectedIcon: false,
              segments: [
                for (final t in BillingTab.values)
                  ButtonSegment(value: t, label: Text(t.label)),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        switch (_tab) {
          BillingTab.cycles => CyclesSection(
            period: _period ?? (due.isNotEmpty ? due.first.period : current),
            onPeriodChanged: (p) => setState(() => _period = p),
            onShowLines: () => setState(() => _tab = BillingTab.lines),
          ),
          BillingTab.lines => const TripLinesSection(),
          BillingTab.config => const BillingConfigSection(),
        },
      ],
    );
  }
}

/// Period preview, cycle processing and invoice history.
class CyclesSection extends ConsumerWidget {
  const CyclesSection({
    super.key,
    required this.period,
    required this.onPeriodChanged,
    required this.onShowLines,
  });
  final BillingPeriod period;
  final ValueChanged<BillingPeriod> onPeriodChanged;
  final VoidCallback onShowLines;

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    CyclePreview pv,
  ) async {
    final services = ref.read(servicesProvider);
    final employer = ref.read(dataProvider).primaryEmployer;
    if (pv.eligible.isNotEmpty) {
      final ok = await showConfirmDialog(
        context,
        title: 'Run billing cycle (demo)?',
        message:
            '${pv.period.label}: ${pv.eligible.length} trip line${pv.eligible.length == 1 ? '' : 's'}, ${Fmt.km(pv.distanceKm)}, total ${Fmt.inr(pv.total)}. '
            '${pv.excluded.length} trip${pv.excluded.length == 1 ? ' is' : 's are'} excluded.',
        confirmLabel: 'Generate invoice',
        extra: const SimulatedNote(
          DemoLabels.invoiceDemo,
          icon: Icons.receipt_long_outlined,
        ),
      );
      if (!ok || !context.mounted) return;
    }
    final r = await services.billingCycles.runCycle(employer.id, pv.period);
    if (!context.mounted) return;
    if (!r.isOk) {
      await showResult(context, r, failureTitle: 'Billing cycle not processed');
      return;
    }
    final inv = r.valueOrNull!;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Invoice ${inv.reference} generated'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: InlineBanner(
            tone: StatusTone.success,
            title:
                '${inv.tripIds.length} trip line${inv.tripIds.length == 1 ? '' : 's'} · ${Fmt.inr(inv.total)}',
            message: DemoLabels.invoiceDemo,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(c);
              context.go(EmployerPaths.invoice(inv.id));
            },
            child: const Text('Open invoice'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final cycles = ref.read(servicesProvider).billingCycles;
    final employer = data.primaryEmployer;
    final current = cycles.currentPeriod(employer);
    final options = <BillingPeriod>[current];
    for (var i = 0; i < 4; i++) {
      options.add(options.last.previous);
    }
    if (!options.contains(period)) options.add(period);
    final pv = cycles.preview(employer.id, period);
    final invoices = data.invoicesOf(employer.id);
    final t = Theme.of(context).textTheme;
    String chip(BillingPeriod p) {
      final tag = p == current
          ? 'Current'
          : (p == current.previous ? 'Previous' : null);
      final short = p.cycle == BillingCycle.weekly
          ? '${Fmt.dateShort(p.start)} – ${Fmt.dateShort(p.end)}'
          : p.label;
      return tag == null ? short : '$tag · $short';
    }

    const invHeader = [
      'Invoice',
      'Period start',
      'Period end',
      'Trips',
      'Distance km',
      'Total ₹',
      'Status',
      'Generated',
    ];
    List<List<Object?>> invRows() => [
      for (final i in invoices)
        [
          i.reference,
          Fmt.date(i.periodStart),
          Fmt.date(i.periodEnd),
          i.tripIds.length,
          i.distanceKm.toStringAsFixed(1),
          i.total.toStringAsFixed(2),
          i.status.label,
          Fmt.dateTime(i.generatedAt),
        ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilterChipBar<BillingPeriod>(
          options: options,
          selected: period,
          labelOf: chip,
          onSelected: onPeriodChanged,
        ),
        const SizedBox(height: AppSpace.md),
        PanelCard(
          title: period.label,
          subtitle:
              '${period.cycle.label} · ${Fmt.date(period.start)} – ${Fmt.date(period.end)} (local dates)',
          trailing: pv.existingInvoices.isEmpty
              ? const StatusBadge('Not invoiced', dense: true)
              : Wrap(
                  spacing: 4,
                  children: [
                    for (final i in pv.existingInvoices)
                      StatusBadge(
                        i.reference,
                        tone: invoiceTone(i.status),
                        dense: true,
                      ),
                  ],
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MetricGrid(
                minTileWidth: 160,
                children: [
                  MetricTile(
                    key: const Key('cycle-eligible'),
                    label: 'Eligible lines',
                    value: '${pv.eligible.length}',
                    icon: Icons.task_alt_outlined,
                    tone: StatusTone.success,
                  ),
                  MetricTile(
                    label: 'Excluded trips',
                    value: '${pv.excluded.length}',
                    icon: Icons.block_outlined,
                    tone: pv.excluded.isEmpty
                        ? StatusTone.neutral
                        : StatusTone.warning,
                  ),
                  MetricTile(
                    label: 'Distance',
                    value: Fmt.km(pv.distanceKm),
                    icon: Icons.straighten_rounded,
                  ),
                  MetricTile(
                    key: const Key('cycle-total'),
                    label: 'Total to invoice',
                    value: Fmt.inr(pv.total),
                    icon: Icons.currency_rupee_rounded,
                    tone: StatusTone.teal,
                  ),
                ],
              ),
              if (pv.blockers.isNotEmpty) ...[
                const SizedBox(height: AppSpace.sm),
                InlineBanner(
                  tone: StatusTone.danger,
                  title: 'Cannot run this cycle',
                  messages: pv.blockers,
                ),
              ],
              const SizedBox(height: AppSpace.md),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    key: const Key('run-cycle'),
                    onPressed: pv.blockers.isEmpty
                        ? () => _run(context, ref, pv)
                        : null,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Run billing cycle (demo)'),
                  ),
                  Text(
                    pv.eligible.isEmpty
                        ? (pv.existingInvoices.isEmpty
                              ? 'No eligible lines yet.'
                              : 'Everything eligible is already invoiced.')
                        : 'Generates one invoice for the eligible lines; running again never duplicates.',
                    style: AppText.muted(context),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.xs),
              const SimulatedNote(
                DemoLabels.invoiceDemo,
                icon: Icons.receipt_long_outlined,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        PanelCard(
          title: 'Eligible lines',
          subtitle:
              'Completed trips with valid actual distance, not yet invoiced',
          child: AdaptiveTable<CycleLine>(
            rows: pv.eligible,
            breakpoint: 640,
            empty: const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpace.sm),
              child: Text('No eligible lines in this period.'),
            ),
            columns: [
              TableCol(
                'Trip',
                (l) => Text(
                  l.trip.tripCode,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              TableCol(
                'Completed',
                (l) => Text(
                  Fmt.dateTime(l.trip.actualArrival),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                flex: 2,
              ),
              TableCol(
                'Calculation',
                (l) => Text(
                  l.record?.calculationNotes ??
                      l.calculation?.explanation ??
                      '—',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                flex: 4,
              ),
              TableCol(
                'Line',
                (l) => Text(l.record == null ? 'Created on run' : l.record!.id),
              ),
              TableCol(
                'Total',
                (l) => Text(
                  Fmt.inr(l.total),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                numeric: true,
              ),
            ],
            mobileCard: (l) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${l.trip.tripCode} · ${Fmt.inr(l.total)}',
                  style: t.titleSmall,
                ),
                Text(
                  l.record?.calculationNotes ??
                      l.calculation?.explanation ??
                      '',
                  style: AppText.muted(context),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        PanelCard(
          title: 'Excluded trips',
          subtitle: 'Never billed automatically — reason shown per trip',
          trailing: TextButton(
            onPressed: onShowLines,
            child: const Text('Trip lines'),
          ),
          child: AdaptiveTable<CycleLine>(
            rows: pv.excluded,
            breakpoint: 640,
            empty: const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpace.sm),
              child: Text('No excluded trips in this period.'),
            ),
            onRowTap: (l) => context.go(EmployerPaths.trip(l.trip.id)),
            columns: [
              TableCol(
                'Trip',
                (l) => Text(
                  l.trip.tripCode,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              TableCol('Date', (l) => Text(Fmt.date(l.trip.serviceDate))),
              TableCol(
                'Status',
                (l) => TripStatusBadge(l.trip.status, dense: true),
                flex: 2,
              ),
              TableCol(
                'Reason',
                (l) => Text(
                  l.exclusion!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                flex: 4,
              ),
            ],
            mobileCard: (l) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(l.trip.tripCode, style: t.titleSmall)),
                    TripStatusBadge(l.trip.status, dense: true),
                  ],
                ),
                Text(l.exclusion!, style: AppText.muted(context)),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        PanelCard(
          title: 'Invoice history',
          subtitle:
              '${invoices.length} invoice${invoices.length == 1 ? '' : 's'} for ${employer.code}',
          trailing: invoices.isEmpty
              ? null
              : TextButton.icon(
                  onPressed: () => exportCsv(
                    context,
                    ref,
                    'invoices_${employer.code}.csv',
                    invHeader,
                    invRows(),
                  ),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Export invoices'),
                ),
          child: AdaptiveTable<Invoice>(
            rows: invoices,
            breakpoint: 640,
            onRowTap: (i) => context.go(EmployerPaths.invoice(i.id)),
            empty: const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No invoices yet',
              message:
                  'Run a billing cycle to group eligible trip lines into an invoice.',
              compact: true,
            ),
            columns: [
              TableCol(
                'Invoice',
                (i) => Text(
                  i.reference,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                flex: 3,
              ),
              TableCol(
                'Period',
                (i) => Text(
                  '${Fmt.dateShort(i.periodStart)} – ${Fmt.dateShort(i.periodEnd)}',
                ),
                flex: 2,
              ),
              TableCol(
                'Trips',
                (i) => Text('${i.tripIds.length}'),
                numeric: true,
              ),
              TableCol(
                'Total',
                (i) => Text(
                  Fmt.inr(i.total),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                numeric: true,
                flex: 2,
              ),
              TableCol(
                'Status',
                (i) => Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: StatusBadge(
                    i.status.label,
                    tone: invoiceTone(i.status),
                    dense: true,
                  ),
                ),
                flex: 2,
              ),
            ],
            mobileCard: (i) => Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(i.reference, style: t.titleSmall),
                      Text(
                        '${Fmt.dateShort(i.periodStart)} – ${Fmt.dateShort(i.periodEnd)} · ${i.tripIds.length} trips · ${Fmt.inr(i.total)}',
                        style: AppText.muted(context),
                      ),
                    ],
                  ),
                ),
                StatusBadge(
                  i.status.label,
                  tone: invoiceTone(i.status),
                  dense: true,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Billing configuration: cycle, active state, rate and per-trip charge.
class BillingConfigSection extends ConsumerStatefulWidget {
  const BillingConfigSection({super.key});

  @override
  ConsumerState<BillingConfigSection> createState() =>
      _BillingConfigSectionState();
}

class _BillingConfigSectionState extends ConsumerState<BillingConfigSection> {
  final _rate = TextEditingController();
  final _additional = TextEditingController();
  BillingCycle? _cycle;
  bool? _active;
  List<String> _errors = const [];
  bool _busy = false;

  @override
  void dispose() {
    _rate.dispose();
    _additional.dispose();
    super.dispose();
  }

  void _load(Employer e) {
    _cycle = e.billingCycle;
    _active = e.billingActive;
    _rate.text = e.defaultDistanceRate.toStringAsFixed(2);
    _additional.text = e.additionalChargePerTrip.toStringAsFixed(2);
  }

  Future<void> _save(Employer e) async {
    final rate = double.tryParse(_rate.text.trim());
    final add = double.tryParse(_additional.text.trim());
    if (rate == null || add == null) {
      setState(() => _errors = ['Rate and additional charge must be numbers.']);
      return;
    }
    final next = e.copyWith(
      billingCycle: _cycle,
      billingActive: _active,
      defaultDistanceRate: rate,
      additionalChargePerTrip: add,
    );
    final changes = <String>[
      if (e.billingCycle != next.billingCycle)
        'Cycle ${e.billingCycle.label} → ${next.billingCycle.label}.',
      if (e.billingActive != next.billingActive)
        'Billing ${next.billingActive ? 'activated' : 'paused — cycles cannot be run'}.',
      if (e.defaultDistanceRate != next.defaultDistanceRate)
        'Rate ${Fmt.inr(e.defaultDistanceRate)} → ${Fmt.inr(next.defaultDistanceRate)}/km (new lines only).',
      if (e.additionalChargePerTrip != next.additionalChargePerTrip)
        'Additional charge per trip ${Fmt.inr(e.additionalChargePerTrip)} → ${Fmt.inr(next.additionalChargePerTrip)} (new lines only).',
    ];
    if (changes.isEmpty) {
      showToast(context, 'No changes to save');
      return;
    }
    final ok = await showConfirmDialog(
      context,
      title: 'Save billing configuration?',
      message: 'Existing billing lines and invoices are not changed.',
      confirmLabel: 'Save configuration',
      extra: InlineBanner(
        tone: StatusTone.warning,
        title: 'Changes',
        messages: changes,
      ),
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final r = await ref.read(servicesProvider).employers.update(next);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _errors = r.errors;
    });
    if (r.isOk) showToast(context, 'Billing configuration saved');
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final e = data.primaryEmployer;
    if (_cycle == null) _load(e);
    final next = BillingPeriod.of(_cycle!, data.now);
    final history = data.auditFor('employer', e.id).take(6).toList();
    final t = Theme.of(context).textTheme;
    return ResponsiveColumns(
      left: PanelCard(
        title: 'Billing configuration',
        subtitle:
            'Weeks run Monday–Sunday; months are calendar months (local business dates).',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_errors.isNotEmpty) ...[
              InlineBanner(
                tone: StatusTone.danger,
                title: 'Not saved',
                messages: _errors,
              ),
              const SizedBox(height: AppSpace.sm),
            ],
            Text('Billing cycle', style: t.titleSmall),
            const SizedBox(height: AppSpace.xs),
            SegmentedButton<BillingCycle>(
              segments: [
                for (final c in BillingCycle.values)
                  ButtonSegment(
                    value: c,
                    label: Text(
                      c == BillingCycle.weekly ? 'Weekly' : 'Monthly',
                    ),
                  ),
              ],
              selected: {_cycle!},
              onSelectionChanged: (s) => setState(() => _cycle = s.first),
            ),
            const SizedBox(height: AppSpace.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active!,
              onChanged: (v) => setState(() => _active = v),
              title: const Text('Billing active'),
              subtitle: const Text(
                'When paused, billing cycles cannot be processed.',
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            FormRow(
              children: [
                TextField(
                  key: const Key('config-rate'),
                  controller: _rate,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Distance rate',
                    prefixText: '₹ ',
                    suffixText: '/ km',
                  ),
                ),
                TextField(
                  key: const Key('config-additional'),
                  controller: _additional,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Additional charge per trip',
                    prefixText: '₹ ',
                    helperText: 'Added to each new line',
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            Container(
              padding: const EdgeInsets.all(AppSpace.sm),
              decoration: BoxDecoration(
                color: AppColors.softBlue,
                borderRadius: AppRadius.mdAll,
              ),
              child: Text(
                'Current period ${next.label} · next boundary ${Fmt.weekdayLong(next.nextBoundary)}',
                key: const Key('next-boundary'),
                style: t.bodySmall!.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _busy ? null : () => _save(e),
                child: const Text('Save configuration'),
              ),
            ),
          ],
        ),
      ),
      right: PanelCard(
        title: 'Configuration history',
        subtitle: 'From the audit trail',
        child: DividedList(
          empty: const Text('No changes recorded yet.'),
          children: [
            for (final a in history)
              ListRow(
                title: a.summary,
                subtitle:
                    '${Fmt.dateTime(a.timestamp)} · ${a.actorRole.label}${a.changes.isNotEmpty ? ' · ${a.changes}' : ''}',
              ),
          ],
        ),
      ),
    );
  }
}

/// Invoice detail: line items, calculations, included trips, status flow.
class InvoiceDetailPage extends ConsumerWidget {
  const InvoiceDetailPage({super.key, required this.invoiceId});
  final String invoiceId;

  Future<void> _set(
    BuildContext context,
    WidgetRef ref,
    Invoice inv,
    InvoiceStatus to,
  ) async {
    String? reason;
    if (to == InvoiceStatus.disputed) {
      final input = await showReasonDialog(
        context,
        title: 'Dispute ${inv.reference}',
        message: 'The Fleet Manager will be notified.',
        label: 'Dispute reason',
        confirmLabel: 'Dispute',
        destructive: true,
      );
      if (input == null) return;
      reason = input.reason;
    } else if (to == InvoiceStatus.paidDemo) {
      final ok = await showConfirmDialog(
        context,
        title: 'Mark invoice paid (demo)?',
        message: '${DemoLabels.paymentDemo}. Only the status label changes.',
        confirmLabel: 'Mark paid (demo)',
      );
      if (!ok) return;
    }
    if (!context.mounted) return;
    final r = await ref
        .read(servicesProvider)
        .billingCycles
        .setStatus(inv.id, to, reason: reason);
    if (context.mounted) await showResult(context, r);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final inv = data.invoice(invoiceId);
    if (inv == null) {
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'Invoice not found',
        message: 'No invoice "$invoiceId".',
        actionLabel: 'Back to billing',
        onAction: () => context.go(EmployerPaths.billing),
      );
    }
    final t = Theme.of(context).textTheme;
    final lines = inv.billingRecordIds
        .map(data.billingRecord)
        .whereType<BillingRecord>()
        .toList();
    const header = [
      'Line',
      'Trip',
      'Completed',
      'Distance km',
      'Rate ₹/km',
      'Additional ₹',
      'Adjustment ₹',
      'Total ₹',
      'Calculation',
    ];
    List<List<Object?>> rows() => [
      for (final b in lines)
        [
          b.id,
          b.tripCode,
          Fmt.dateTime(b.completedAt),
          b.billableDistanceKm.toStringAsFixed(1),
          b.ratePerKm.toStringAsFixed(2),
          b.additionalCharges.toStringAsFixed(2),
          b.adjustment.toStringAsFixed(2),
          b.totalAmount.toStringAsFixed(2),
          b.calculationNotes,
        ],
    ];
    final actions = <Widget>[
      if (inv.status == InvoiceStatus.generated ||
          inv.status == InvoiceStatus.disputed)
        FilledButton.icon(
          onPressed: () => _set(context, ref, inv, InvoiceStatus.reviewed),
          icon: const Icon(Icons.fact_check_outlined),
          label: Text(
            inv.status == InvoiceStatus.disputed
                ? 'Resolve & mark reviewed'
                : 'Mark invoice reviewed',
          ),
        ),
      if (inv.status == InvoiceStatus.reviewed)
        FilledButton.icon(
          onPressed: () => _set(context, ref, inv, InvoiceStatus.paidDemo),
          icon: const Icon(Icons.task_alt_outlined),
          label: const Text('Mark invoice paid (demo)'),
        ),
      if (inv.status == InvoiceStatus.generated ||
          inv.status == InvoiceStatus.reviewed)
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
          onPressed: () => _set(context, ref, inv, InvoiceStatus.disputed),
          icon: const Icon(Icons.report_outlined),
          label: const Text('Dispute invoice'),
        ),
    ];

    return AdminPage(
      title: 'Invoice ${inv.reference}',
      subtitle:
          '${inv.cycle.label} · ${Fmt.date(inv.periodStart)} – ${Fmt.date(inv.periodEnd)} · generated ${Fmt.dateTime(inv.generatedAt)}',
      actions: [
        TextButton.icon(
          onPressed: () => context.go(EmployerPaths.billing),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Billing'),
        ),
        OutlinedButton.icon(
          onPressed: () =>
              exportCsv(context, ref, '${inv.reference}.csv', header, rows()),
          icon: const Icon(Icons.download_outlined),
          label: const Text('Export CSV'),
        ),
        StatusBadge(inv.status.label, tone: invoiceTone(inv.status)),
      ],
      children: [
        const InlineBanner(
          tone: StatusTone.info,
          icon: Icons.receipt_long_outlined,
          title: 'Demo invoice',
          message: DemoLabels.invoiceDemo,
        ),
        const SizedBox(height: AppSpace.md),
        ResponsiveColumns(
          left: PanelCard(
            title: 'Line items',
            subtitle:
                '${lines.length} trip line${lines.length == 1 ? '' : 's'}',
            child: AdaptiveTable<BillingRecord>(
              rows: lines,
              breakpoint: 600,
              onRowTap: (b) => context.go(EmployerPaths.bill(b.id)),
              columns: [
                TableCol(
                  'Trip',
                  (b) => Text(
                    b.tripCode,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                TableCol(
                  'Calculation',
                  (b) => Text(
                    b.calculationNotes,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  flex: 4,
                ),
                TableCol(
                  'Total',
                  (b) => Text(
                    Fmt.inr(b.totalAmount),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  numeric: true,
                  flex: 2,
                ),
              ],
              mobileCard: (b) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${b.tripCode} · ${Fmt.inr(b.totalAmount)}',
                    style: t.titleSmall,
                  ),
                  Text(b.calculationNotes, style: AppText.muted(context)),
                ],
              ),
            ),
          ),
          right: PanelCard(
            title: 'Totals',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KeyValueRow(label: 'Distance', value: Fmt.km(inv.distanceKm)),
                KeyValueRow(
                  label: 'Distance charges',
                  value: Fmt.inr(inv.distanceCharges),
                ),
                KeyValueRow(
                  label: 'Additional charges',
                  value: Fmt.inr(inv.additionalCharges),
                ),
                KeyValueRow(
                  label: 'Adjustments',
                  value: Fmt.inr(inv.adjustments),
                ),
                const Divider(height: AppSpace.lg),
                Row(
                  children: [
                    Expanded(
                      child: Text('Invoice total', style: t.titleMedium),
                    ),
                    Text(
                      Fmt.inr(inv.total),
                      key: const Key('invoice-total'),
                      style: t.headlineSmall!.copyWith(
                        fontFeatures: AppText.tabular,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.md),
                Text('Included trips', style: t.titleSmall),
                const SizedBox(height: AppSpace.xs),
                Wrap(
                  spacing: AppSpace.xs,
                  runSpacing: AppSpace.xs,
                  children: [
                    for (final id in inv.tripIds)
                      ActionChip(
                        label: Text(id),
                        onPressed: () => context.go(EmployerPaths.trip(id)),
                      ),
                  ],
                ),
                if (inv.notes.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.sm),
                  Text(inv.notes, style: AppText.muted(context)),
                ],
                if (inv.disputeReason != null) ...[
                  const SizedBox(height: AppSpace.sm),
                  InlineBanner(
                    tone: StatusTone.danger,
                    title: 'Dispute reason',
                    message: inv.disputeReason,
                  ),
                ],
                const SizedBox(height: AppSpace.md),
                if (actions.isNotEmpty)
                  Wrap(
                    spacing: AppSpace.xs,
                    runSpacing: AppSpace.xs,
                    children: actions,
                  )
                else
                  const SimulatedNote(
                    'Paid (demo) is final in this prototype.',
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
