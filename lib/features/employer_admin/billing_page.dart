import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import 'employer_common.dart';

enum LinePeriod {
  week('Last 7 days'),
  month('This month'),
  all('All time'),
  custom('Custom');

  const LinePeriod(this.label);
  final String label;
}

/// Shared CSV export with clipboard fallback.
Future<void> exportCsv(
  BuildContext context,
  WidgetRef ref,
  String fileName,
  List<String> header,
  List<List<Object?>> rows,
) async {
  final export = ref.read(servicesProvider).export;
  final csv = export.toCsv(header, rows);
  try {
    final where = await export.saveCsv(fileName, csv);
    if (context.mounted) showToast(context, where);
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: csv));
    if (context.mounted) {
      showToast(context, 'File export unavailable — CSV copied to clipboard');
    }
  }
}

Future<void> copyCsv(
  BuildContext context,
  WidgetRef ref,
  List<String> header,
  List<List<Object?>> rows,
) async {
  await Clipboard.setData(
    ClipboardData(text: ref.read(servicesProvider).export.toCsv(header, rows)),
  );
  if (context.mounted) showToast(context, 'CSV copied to clipboard');
}

/// Distance-based billing for completed trips.
class TripLinesSection extends ConsumerStatefulWidget {
  const TripLinesSection({super.key});

  @override
  ConsumerState<TripLinesSection> createState() => _TripLinesSectionState();
}

class _TripLinesSectionState extends ConsumerState<TripLinesSection> {
  LinePeriod _period = LinePeriod.month;
  DateTimeRange? _custom;
  BillingStatus? _status;

  DateRange? _range(DateTime today) => switch (_period) {
    LinePeriod.week => DateRange.lastDays(today, 7),
    LinePeriod.month => DateRange(DateTime(today.year, today.month, 1), today),
    LinePeriod.all => null,
    LinePeriod.custom =>
      _custom == null ? null : DateRange(_custom!.start, _custom!.end),
  };

  Future<void> _recordDistance(Trip trip) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => _DistanceDialog(trip: trip),
    );
    if (saved == true && mounted) {
      showToast(
        context,
        'Distance recorded — billing generated for ${trip.tripCode}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final employer = data.primaryEmployer;
    final range = _range(data.today);
    final inPeriod = data
        .billingOf(employer.id)
        .where((b) => range == null || range.contains(b.completedAt))
        .toList();
    final rows = inPeriod
        .where((b) => _status == null || b.status == _status)
        .toList();
    final total = rows.fold<double>(0, (s, b) => s + b.totalAmount);
    final km = rows.fold<double>(0, (s, b) => s + b.billableDistanceKm);
    final byStatus = <BillingStatus, double>{};
    for (final b in inPeriod) {
      byStatus[b.status] = (byStatus[b.status] ?? 0) + b.totalAmount;
    }
    final trips = employerTrips(data);
    final missing = trips
        .where(
          (t) =>
              t.status == TripStatus.completed &&
              t.billableStatus == BillableStatus.missingDistance &&
              data.billingForTrip(t.id) == null,
        )
        .toList();
    final excludedCancelled = trips
        .where(
          (t) =>
              t.status == TripStatus.cancelled &&
              (range == null || range.contains(t.serviceDate)),
        )
        .length;
    final notCompleted = trips
        .where(
          (t) =>
              !t.status.isTerminal &&
              (range == null || range.contains(t.serviceDate)),
        )
        .length;
    final t = Theme.of(context).textTheme;

    const header = [
      'Billing ID',
      'Trip',
      'Completed',
      'Distance km',
      'Rate ₹/km',
      'Additional ₹',
      'Adjustment ₹',
      'Total ₹',
      'Status',
      'Calculation',
    ];
    List<List<Object?>> csvRows() => [
      for (final b in rows)
        [
          b.id,
          b.tripCode,
          Fmt.dateTime(b.completedAt),
          b.billableDistanceKm.toStringAsFixed(1),
          b.ratePerKm.toStringAsFixed(2),
          b.additionalCharges.toStringAsFixed(2),
          b.adjustment.toStringAsFixed(2),
          b.totalAmount.toStringAsFixed(2),
          b.status.label,
          b.calculationNotes,
        ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AppSpace.xs,
          runSpacing: AppSpace.xs,
          children: [
            OutlinedButton.icon(
              onPressed: rows.isEmpty
                  ? null
                  : () => copyCsv(context, ref, header, csvRows()),
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy CSV'),
            ),
            FilledButton.icon(
              onPressed: rows.isEmpty
                  ? null
                  : () => exportCsv(
                      context,
                      ref,
                      'billing_${employer.code}.csv',
                      header,
                      csvRows(),
                    ),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Export CSV'),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        if (missing.isNotEmpty) ...[
          AppCard(
            borderColor: AppColors.danger.withValues(alpha: 0.35),
            color: AppColors.dangerBg,
            padding: const EdgeInsets.all(AppSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.block_rounded,
                      color: AppColors.danger,
                      size: 20,
                    ),
                    const SizedBox(width: AppSpace.xs),
                    Expanded(
                      child: Text(
                        'Blocked: missing distance (${missing.length})',
                        style: t.titleSmall!.copyWith(color: AppColors.danger),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'These completed trips have no valid recorded distance, so automatic billing was not generated.',
                  style: t.bodySmall,
                ),
                const SizedBox(height: AppSpace.xs),
                for (final tr in missing)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.xs),
                    child: AppCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.md,
                        vertical: AppSpace.xs,
                      ),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpace.sm,
                        runSpacing: AppSpace.xs,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${tr.tripCode} · ${Fmt.date(tr.serviceDate)}',
                                  style: t.titleSmall,
                                ),
                                Text(
                                  'Completed ${Fmt.time(tr.actualArrival)} · est. ${Fmt.km(data.trips.routeOf(tr)?.estimatedDistanceKm)} (estimate not billable)',
                                  style: AppText.muted(context),
                                ),
                              ],
                            ),
                          ),
                          FilledButton.tonal(
                            onPressed: () => _recordDistance(tr),
                            child: const Text('Record distance & bill'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterChipBar<LinePeriod>(
              options: LinePeriod.values,
              selected: _period,
              labelOf: (p) => p == LinePeriod.custom && _custom != null
                  ? '${Fmt.dateShort(_custom!.start)} – ${Fmt.dateShort(_custom!.end)}'
                  : p.label,
              onSelected: (p) async {
                if (p == LinePeriod.custom) {
                  final r = await showDateRangePicker(
                    context: context,
                    firstDate: data.today.subtract(const Duration(days: 365)),
                    lastDate: data.today,
                    initialDateRange: _custom,
                  );
                  if (r == null) return;
                  setState(() => _custom = r);
                }
                setState(() => _period = p);
              },
            ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        FilterChipBar<BillingStatus?>(
          options: [null, ...BillingStatus.values],
          selected: _status,
          labelOf: (s) => s?.label ?? 'All statuses',
          countOf: (s) =>
              inPeriod.where((b) => s == null || b.status == s).length,
          onSelected: (s) => setState(() => _status = s),
        ),
        const SizedBox(height: AppSpace.md),
        MetricGrid(
          minTileWidth: 180,
          children: [
            MetricTile(
              key: const Key('billing-total'),
              label: 'Total (filtered)',
              value: Fmt.inr(total),
              caption: '${rows.length} line${rows.length == 1 ? '' : 's'}',
              icon: Icons.currency_rupee_rounded,
              tone: StatusTone.teal,
            ),
            MetricTile(
              label: 'Billed distance',
              value: Fmt.km(km),
              caption: 'Recorded on completed trips',
              icon: Icons.straighten_rounded,
            ),
            MetricTile(
              label: 'Awaiting review',
              value: Fmt.inr0(byStatus[BillingStatus.generated] ?? 0),
              caption: 'Generated, not reviewed',
              icon: Icons.pending_actions_outlined,
              tone: StatusTone.info,
            ),
            MetricTile(
              label: 'Paid (demo)',
              value: Fmt.inr0(byStatus[BillingStatus.paidDemo] ?? 0),
              caption: 'Label only — no payment processed',
              icon: Icons.task_alt_outlined,
              tone: StatusTone.success,
            ),
            MetricTile(
              label: 'Disputed',
              value: Fmt.inr0(byStatus[BillingStatus.disputed] ?? 0),
              icon: Icons.report_outlined,
              tone: StatusTone.danger,
            ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        AdaptiveTable<BillingRecord>(
          rows: rows,
          onRowTap: (b) => context.go(EmployerPaths.bill(b.id)),
          empty: EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No billing lines',
            message:
                'Billing is generated automatically when a trip is completed with a valid distance.',
            actionLabel: _status != null || _period != LinePeriod.all
                ? 'Show all'
                : null,
            onAction: () => setState(() {
              _status = null;
              _period = LinePeriod.all;
            }),
          ),
          columns: [
            TableCol(
              'Trip',
              (b) => Text(
                b.tripCode,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            TableCol(
              'Completed',
              (b) => Text(
                Fmt.dateTime(b.completedAt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              flex: 2,
            ),
            TableCol(
              'Status',
              (b) => StatusBadge(
                b.status.label,
                tone: Tones.billing(b.status),
                dense: true,
              ),
              flex: 2,
            ),
            TableCol(
              'Distance',
              (b) => Text(Fmt.km(b.billableDistanceKm)),
              numeric: true,
            ),
            TableCol('Rate', (b) => Text(Fmt.inr(b.ratePerKm)), numeric: true),
            TableCol(
              'Additional',
              (b) => Text(Fmt.inr(b.additionalCharges)),
              numeric: true,
            ),
            TableCol(
              'Adjustment',
              (b) => Text(Fmt.inr(b.adjustment)),
              numeric: true,
            ),
            TableCol(
              'Total',
              (b) => Text(
                Fmt.inr(b.totalAmount),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              numeric: true,
            ),
          ],
          mobileCard: (b) => Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${b.tripCode} · ${Fmt.inr(b.totalAmount)}',
                      style: t.titleSmall,
                    ),
                    Text(
                      '${Fmt.dateShort(b.completedAt)} · ${Fmt.km(b.billableDistanceKm)} × ${Fmt.inr(b.ratePerKm)}',
                      style: AppText.muted(context),
                    ),
                  ],
                ),
              ),
              StatusBadge(
                b.status.label,
                tone: Tones.billing(b.status),
                dense: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        SimulatedNote(
          'Excluded from billing in this period: $excludedCancelled cancelled trip${excludedCancelled == 1 ? '' : 's'} and $notCompleted not-yet-completed trip${notCompleted == 1 ? '' : 's'}. ${DemoLabels.paymentDemo}.',
          icon: Icons.info_outline_rounded,
        ),
      ],
    );
  }
}

class _DistanceDialog extends ConsumerStatefulWidget {
  const _DistanceDialog({required this.trip});
  final Trip trip;

  @override
  ConsumerState<_DistanceDialog> createState() => _DistanceDialogState();
}

class _DistanceDialogState extends ConsumerState<_DistanceDialog> {
  final _form = GlobalKey<FormState>();
  final _km = TextEditingController();
  final _note = TextEditingController();
  List<String> _errors = const [];
  bool _busy = false;

  @override
  void dispose() {
    _km.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final r = await ref
        .read(servicesProvider)
        .billing
        .recordDistanceAndBill(
          widget.trip.id,
          double.parse(_km.text.trim()),
          _note.text.trim(),
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _errors = r.errors;
    });
    if (r.isOk) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final rate = ref.watch(dataProvider).primaryEmployer.defaultDistanceRate;
    final km = double.tryParse(_km.text.trim());
    return AlertDialog(
      title: Text('Record distance · ${widget.trip.tripCode}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, minWidth: 280),
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_errors.isNotEmpty) ...[
                  InlineBanner(
                    tone: StatusTone.danger,
                    title: 'Not billed',
                    messages: _errors,
                  ),
                  const SizedBox(height: AppSpace.sm),
                ],
                TextFormField(
                  key: const Key('distance-km'),
                  controller: _km,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Verified distance',
                    suffixText: 'km',
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (v) => Validators.nonNegativeNumber(v, 'Distance'),
                ),
                const SizedBox(height: AppSpace.sm),
                TextFormField(
                  key: const Key('distance-note'),
                  controller: _note,
                  decoration: const InputDecoration(
                    labelText: 'Source of the distance',
                    hintText: 'e.g. Odometer photo from driver',
                  ),
                  validator: (v) => Validators.minLength(v, 5, 'Source'),
                ),
                const SizedBox(height: AppSpace.md),
                Text(
                  km == null || km < 0
                      ? 'Billing will use ${Fmt.inr(rate)}/km and is generated once.'
                      : BillingService.calculate(
                          distanceKm: km,
                          ratePerKm: rate,
                        ).explanation,
                  style: AppText.secondary(context),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Record & bill'),
        ),
      ],
    );
  }
}

/// Transparent billing line detail with review / dispute / paid (demo).
class BillingDetailPage extends ConsumerWidget {
  const BillingDetailPage({super.key, required this.billingId});
  final String billingId;

  Future<void> _set(
    BuildContext context,
    WidgetRef ref,
    BillingRecord b,
    BillingStatus to,
  ) async {
    String? reason;
    if (to == BillingStatus.disputed) {
      final input = await showReasonDialog(
        context,
        title: 'Dispute ${b.tripCode}',
        message: 'The Fleet Manager will be notified.',
        label: 'Dispute reason',
        confirmLabel: 'Dispute',
        destructive: true,
      );
      if (input == null) return;
      reason = input.reason;
    } else if (to == BillingStatus.paidDemo) {
      final ok = await showConfirmDialog(
        context,
        title: 'Mark as paid (demo)?',
        message:
            '${DemoLabels.paymentDemo}. This only changes the status label.',
        confirmLabel: 'Mark paid (demo)',
      );
      if (!ok) return;
    }
    if (!context.mounted) return;
    final r = await ref
        .read(servicesProvider)
        .billing
        .setStatus(b.id, to, reason: reason);
    if (context.mounted) await showResult(context, r);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final b = data.billingRecord(billingId);
    if (b == null) {
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'Billing line not found',
        message: 'No billing record "$billingId".',
        actionLabel: 'Back to billing',
        onAction: () => context.go(EmployerPaths.billing),
      );
    }
    final t = Theme.of(context).textTheme;
    final trip = data.trips.byId(b.tripId);
    final calc = BillingService.calculate(
      distanceKm: b.billableDistanceKm,
      ratePerKm: b.ratePerKm,
      additionalCharges: b.additionalCharges,
      adjustment: b.adjustment,
    );
    final actions = <Widget>[
      if (b.status == BillingStatus.generated ||
          b.status == BillingStatus.disputed)
        FilledButton.icon(
          onPressed: () => _set(context, ref, b, BillingStatus.reviewed),
          icon: const Icon(Icons.fact_check_outlined),
          label: Text(
            b.status == BillingStatus.disputed
                ? 'Resolve & mark reviewed'
                : 'Mark reviewed',
          ),
        ),
      if (b.status == BillingStatus.reviewed)
        FilledButton.icon(
          onPressed: () => _set(context, ref, b, BillingStatus.paidDemo),
          icon: const Icon(Icons.task_alt_outlined),
          label: const Text('Mark paid (demo)'),
        ),
      if (b.status == BillingStatus.generated ||
          b.status == BillingStatus.reviewed)
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
          onPressed: () => _set(context, ref, b, BillingStatus.disputed),
          icon: const Icon(Icons.report_outlined),
          label: const Text('Dispute'),
        ),
    ];
    return AdminPage(
      title: 'Billing ${b.id}',
      subtitle: 'Trip ${b.tripCode} · completed ${Fmt.dateTime(b.completedAt)}',
      actions: [
        TextButton.icon(
          onPressed: () => context.go(EmployerPaths.billing),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Billing'),
        ),
        StatusBadge(b.status.label, tone: Tones.billing(b.status)),
      ],
      children: [
        ResponsiveColumns(
          left: PanelCard(
            title: 'Calculation',
            subtitle: 'distanceKm × ratePerKm + additionalCharges + adjustment',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KeyValueRow(
                  label: 'Billable distance',
                  value: Fmt.km(b.billableDistanceKm),
                ),
                KeyValueRow(label: 'Rate per km', value: Fmt.inr(b.ratePerKm)),
                KeyValueRow(
                  label: 'Distance charge',
                  value: Fmt.inr(calc.distanceCharge),
                ),
                KeyValueRow(
                  label: 'Additional charges',
                  value: Fmt.inr(b.additionalCharges),
                ),
                KeyValueRow(label: 'Adjustment', value: Fmt.inr(b.adjustment)),
                const Divider(height: AppSpace.lg),
                Row(
                  children: [
                    Expanded(child: Text('Total', style: t.titleMedium)),
                    Text(
                      Fmt.inr(b.totalAmount),
                      style: t.headlineSmall!.copyWith(
                        fontFeatures: AppText.tabular,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
                Container(
                  padding: const EdgeInsets.all(AppSpace.sm),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: AppRadius.smAll,
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Text(
                    b.calculationNotes,
                    style: t.bodySmall!.copyWith(fontFeatures: AppText.tabular),
                  ),
                ),
                if ((calc.total - b.totalAmount).abs() > 0.01) ...[
                  const SizedBox(height: AppSpace.sm),
                  const InlineBanner(
                    tone: StatusTone.warning,
                    title: 'Stored total differs from recomputed formula',
                  ),
                ],
                if (b.disputeReason != null) ...[
                  const SizedBox(height: AppSpace.sm),
                  InlineBanner(
                    tone: StatusTone.danger,
                    title: 'Dispute reason',
                    message: b.disputeReason,
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
                const SizedBox(height: AppSpace.sm),
                const SimulatedNote(DemoLabels.paymentDemo),
              ],
            ),
          ),
          right: PanelCard(
            title: 'Trip',
            child: trip == null
                ? const Text('Trip record not found.')
                : Column(
                    children: [
                      KeyValueRow(label: 'Trip', value: trip.tripCode),
                      KeyValueRow(
                        label: 'Service date',
                        value: Fmt.date(trip.serviceDate),
                      ),
                      KeyValueRow(
                        label: 'Actual times',
                        value:
                            '${Fmt.time(trip.actualStart)} – ${Fmt.time(trip.actualArrival)}',
                      ),
                      KeyValueRow(
                        label: 'Passengers dropped',
                        value:
                            '${trip.alightedPassengerIds.length} of ${trip.employeeIds.length}',
                      ),
                      KeyValueRow(
                        label: 'Vehicle',
                        value: trip.assignedVehicleId == null
                            ? '—'
                            : 'Vehicle ${trip.assignedVehicleId}',
                      ),
                      KeyValueRow(
                        label: 'Odometer',
                        value: trip.startOdometerKm == null
                            ? '—'
                            : '${trip.startOdometerKm?.toStringAsFixed(1)} → ${trip.endOdometerKm?.toStringAsFixed(1) ?? '—'}',
                      ),
                      KeyValueRow(
                        label: 'Generated',
                        value: Fmt.dateTime(b.createdAt),
                      ),
                      KeyValueRow(
                        label: 'Reviewed',
                        value: Fmt.dateTime(b.reviewedAt),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () =>
                              context.go(EmployerPaths.trip(trip.id)),
                          child: const Text('Open trip'),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
