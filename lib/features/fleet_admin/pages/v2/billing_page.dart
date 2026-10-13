import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../domain/models/models.dart';
import '../../../../domain/rules/parameter_catalog.dart';
import '../../widgets/fleet_common.dart';

/// Fleet billing summaries: cycle status per company, invoices (read-only),
/// distance/cost assumptions and contract context. Distance billing remains
/// the source of truth; contract cost per car is informational.
class FleetBillingPage extends ConsumerStatefulWidget {
  const FleetBillingPage({super.key});

  @override
  ConsumerState<FleetBillingPage> createState() => _FleetBillingPageState();
}

class _FleetBillingPageState extends ConsumerState<FleetBillingPage> {
  String? _companyId;

  Future<void> _runCycle(Employer e, BillingPeriod period) async {
    final svc = ref.read(servicesProvider).billingCycles;
    final pv = svc.preview(e.id, period);
    final ok = await showConfirmDialog(
      context,
      title: 'Run ${e.billingCycle.name} cycle for ${e.code}?',
      message:
          '${period.label}: ${pv.eligible.length} eligible trip line${pv.eligible.length == 1 ? '' : 's'}, ${Fmt.inr(pv.total)} total'
          '${pv.excluded.isEmpty ? '' : ', ${pv.excluded.length} excluded'}. Lines already invoiced are never billed twice.',
      confirmLabel: 'Run billing cycle (demo)',
      extra: const InlineBanner(
        tone: StatusTone.warning,
        title: 'Demo only',
        message: DemoLabels.invoiceDemo,
      ),
    );
    if (!ok || !mounted) return;
    await runAndShow(
      context,
      svc.runCycle(e.id, period, actor: Actor.fleetManager),
      failureTitle: 'Billing cycle not run',
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final svc = ref.read(servicesProvider).billingCycles;
    final t = Theme.of(context).textTheme;
    final companies = data.employers;
    final company = data.employer(_companyId) ?? companies.first;
    final period = svc.currentPeriod(company);
    final current = svc.preview(company.id, period);
    final due = svc.dueCycles(company.id);
    final invoices = data.invoicesOf(company.id).toList()
      ..sort((a, b) => b.generatedAt.compareTo(a.generatedAt));
    final contract = data.activeContract(company.id, data.today);
    final cfg = data.optimizationConfigs.firstOrNull;
    double costPerKm(FuelType f) {
      final key = switch (f) {
        FuelType.electric => 'ev_cost_per_km',
        FuelType.hybrid => 'hybrid_cost_per_km',
        _ => 'ice_cost_per_km',
      };
      return cfg == null
          ? (ParameterCatalog.byKey(key)?.defaultValue ?? 0)
          : ParameterCatalog.value(cfg, key);
    }

    final completed =
        data.trips
            .all()
            .where(
              (x) =>
                  x.employerId == company.id &&
                  x.status == TripStatus.completed,
            )
            .toList()
          ..sort((a, b) => b.serviceDate.compareTo(a.serviceDate));
    final usedCars = data.trips
        .onDay(data.today)
        .where(
          (x) =>
              x.employerId == company.id &&
              x.assignedVehicleId != null &&
              x.status != TripStatus.cancelled,
        )
        .map((x) => x.assignedVehicleId)
        .toSet()
        .length;

    final status = PanelCard(
      title: 'Billing cycle · ${company.code}',
      subtitle:
          '${company.billingCycle.name[0].toUpperCase()}${company.billingCycle.name.substring(1)} cycle · ${company.billingActive ? 'billing active' : 'billing paused'} · rate ${Fmt.inr(company.defaultDistanceRate)}/km',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StatStrip(
            stats: [
              ('current period', period.label),
              ('eligible lines', '${current.eligible.length}'),
              ('running eligible total', Fmt.inr(current.total)),
              ('excluded', '${current.excluded.length}'),
              ('due cycles', '${due.length}'),
            ],
          ),
          if (current.blockers.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            InlineBanner(
              tone: StatusTone.warning,
              title: 'Current period cannot be run yet',
              messages: current.blockers,
            ),
          ],
          const SizedBox(height: AppSpace.md),
          if (due.isEmpty)
            Text(
              'No completed periods are waiting to be billed.',
              style: AppText.muted(context),
            )
          else
            for (final d in due)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const IconTile(
                  icon: Icons.event_repeat_outlined,
                  color: AppColors.warning,
                  size: 36,
                ),
                title: Text('Due: ${d.period.label}'),
                subtitle: Text(
                  '${d.eligible.length} eligible · ${Fmt.inr(d.total)}${d.existingInvoices.isNotEmpty ? ' · ${d.existingInvoices.length} invoice(s) exist' : ''}',
                ),
                trailing: FilledButton.tonal(
                  onPressed: d.canRun
                      ? () => _runCycle(company, d.period)
                      : null,
                  child: const Text('Run'),
                ),
              ),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: [
              FilledButton.icon(
                onPressed: current.canRun
                    ? () => _runCycle(company, period)
                    : null,
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Run billing cycle (demo)'),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          const SimulatedNote(DemoLabels.invoiceDemo),
        ],
      ),
    );

    final contractCard = PanelCard(
      title: 'Contract context',
      subtitle:
          'Informational — invoices are based on trip distance, not cost per car',
      child: contract == null
          ? const InlineBanner(
              tone: StatusTone.warning,
              title: 'No active contract today',
              message:
                  'Assignments for this company are blocked until a contract is active.',
            )
          : Column(
              children: [
                KeyValueRow(
                  label: 'Contract',
                  value: '${contract.contractCode} · ${contract.documentRef}',
                ),
                KeyValueRow(
                  label: 'Validity',
                  value:
                      '${Fmt.date(contract.validFrom)} – ${Fmt.date(contract.validUntil)}',
                ),
                KeyValueRow(
                  label: 'Agreed cars',
                  value:
                      '${contract.agreedVehicleCount} (in use today: $usedCars)',
                ),
                KeyValueRow(
                  label: 'Cost per car',
                  value: Fmt.inr(contract.costPerVehicle),
                ),
                KeyValueRow(
                  label: 'Contracted fleet cost',
                  value: Fmt.inr(
                    contract.costPerVehicle * contract.agreedVehicleCount,
                  ),
                ),
              ],
            ),
    );

    return AdminPage(
      title: 'Fleet billing',
      subtitle:
          'Cycle status, invoices and the distance/cost assumptions behind every line. Employer Admin reviews and disputes invoices.',
      actions: [
        SizedBox(
          width: 240,
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: company.id,
            decoration: const InputDecoration(labelText: 'Company'),
            items: [
              for (final e in companies)
                DropdownMenuItem(
                  value: e.id,
                  child: Text(
                    '${e.code} · ${e.name}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _companyId = v),
          ),
        ),
      ],
      children: [
        ResponsiveSplit(left: status, right: contractCard),
        const SizedBox(height: AppSpace.md),
        PanelCard(
          title: 'Invoices',
          subtitle:
              'Read-only here · ${invoices.length} invoice${invoices.length == 1 ? '' : 's'}',
          child: AdaptiveTable<Invoice>(
            rows: invoices,
            empty: const EmptyState(
              icon: Icons.receipt_outlined,
              title: 'No invoices yet',
              message:
                  'Run a billing cycle to group completed trip lines into an invoice.',
              compact: true,
            ),
            columns: [
              TableCol(
                'Invoice',
                (i) => Text(i.reference, style: t.titleSmall),
                flex: 3,
              ),
              TableCol(
                'Period',
                (i) => Text(
                  '${Fmt.date(i.periodStart)} – ${Fmt.date(i.periodEnd)}',
                ),
                flex: 4,
              ),
              TableCol(
                'Trips',
                (i) => Text('${i.tripIds.length}'),
                flex: 1,
                numeric: true,
              ),
              TableCol(
                'Distance',
                (i) => Text(Fmt.km(i.distanceKm)),
                flex: 2,
                numeric: true,
              ),
              TableCol(
                'Total',
                (i) => Text(Fmt.inr(i.total)),
                flex: 2,
                numeric: true,
              ),
              TableCol(
                'Status',
                (i) => StatusBadge(
                  i.status.label,
                  tone: _invTone(i.status),
                  dense: true,
                ),
                flex: 2,
                numeric: true,
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
                        '${Fmt.date(i.periodStart)} – ${Fmt.date(i.periodEnd)} · ${i.tripIds.length} trips · ${Fmt.inr(i.total)}',
                        style: AppText.muted(context),
                      ),
                    ],
                  ),
                ),
                StatusBadge(
                  i.status.label,
                  tone: _invTone(i.status),
                  dense: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        PanelCard(
          title: 'Trip distance & cost assumptions',
          subtitle:
              'Billed = actual distance × employer rate. Internal cost uses the catalog ₹/km by fuel type (demo assumptions).',
          child: AdaptiveTable<Trip>(
            rows: completed.take(15).toList(),
            onRowTap: (x) => context.go('/fleet/dispatch/trip/${x.id}'),
            empty: const EmptyState(
              icon: Icons.straighten_rounded,
              title: 'No completed trips',
              message:
                  'Completed trips appear here with their distance and cost basis.',
              compact: true,
            ),
            columns: [
              TableCol(
                'Trip',
                (x) => Text(x.tripCode, style: t.titleSmall),
                flex: 2,
              ),
              TableCol(
                'Date',
                (x) => Text(Fmt.dateShort(x.serviceDate)),
                flex: 2,
              ),
              TableCol(
                'Est. km',
                (x) => Text(Fmt.km(data.trips.routeOf(x)?.estimatedDistanceKm)),
                flex: 2,
                numeric: true,
              ),
              TableCol(
                'Actual km',
                (x) => Text(
                  x.distanceKm == null ? 'Missing' : Fmt.km(x.distanceKm),
                ),
                flex: 2,
                numeric: true,
              ),
              TableCol(
                'Fuel',
                (x) => Text(
                  data.vehicle(x.assignedVehicleId)?.effectiveFuelType.label ??
                      '—',
                ),
                flex: 2,
              ),
              TableCol(
                'Internal ₹/km',
                (x) {
                  final v = data.vehicle(x.assignedVehicleId);
                  return Text(
                    v == null ? '—' : Fmt.inr(costPerKm(v.effectiveFuelType)),
                  );
                },
                flex: 2,
                numeric: true,
              ),
              TableCol(
                'Internal cost',
                (x) {
                  final v = data.vehicle(x.assignedVehicleId);
                  return Text(
                    v == null || x.distanceKm == null
                        ? '—'
                        : Fmt.inr0(
                            x.distanceKm! * costPerKm(v.effectiveFuelType),
                          ),
                  );
                },
                flex: 2,
                numeric: true,
              ),
              TableCol(
                'Billed',
                (x) {
                  final b = data.billingForTrip(x.id);
                  return Text(
                    b == null ? x.billableStatus.label : Fmt.inr(b.totalAmount),
                  );
                },
                flex: 2,
                numeric: true,
              ),
            ],
            mobileCard: (x) {
              final v = data.vehicle(x.assignedVehicleId);
              final b = data.billingForTrip(x.id);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${x.tripCode} · ${Fmt.dateShort(x.serviceDate)}',
                    style: t.titleSmall,
                  ),
                  Text(
                    'Est ${Fmt.km(data.trips.routeOf(x)?.estimatedDistanceKm)} · actual ${x.distanceKm == null ? 'missing' : Fmt.km(x.distanceKm)} · ${v?.effectiveFuelType.label ?? '—'} @ ${v == null ? '—' : Fmt.inr(costPerKm(v.effectiveFuelType))}/km',
                    style: AppText.muted(context),
                  ),
                  Text(
                    b == null
                        ? x.billableStatus.label
                        : 'Billed ${Fmt.inr(b.totalAmount)} (${b.calculationNotes})',
                    style: t.bodySmall,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  static StatusTone _invTone(InvoiceStatus s) => switch (s) {
    InvoiceStatus.generated => StatusTone.info,
    InvoiceStatus.reviewed => StatusTone.teal,
    InvoiceStatus.paidDemo => StatusTone.success,
    InvoiceStatus.disputed => StatusTone.danger,
  };
}
