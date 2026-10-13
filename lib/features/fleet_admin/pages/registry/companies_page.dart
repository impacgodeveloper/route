import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../domain/models/models.dart';
import 'registry_common.dart';

/// Registered companies with metadata derived from linked records.
class CompaniesPage extends ConsumerStatefulWidget {
  const CompaniesPage({super.key});

  @override
  ConsumerState<CompaniesPage> createState() => _CompaniesPageState();
}

class _CompaniesPageState extends ConsumerState<CompaniesPage> {
  String _q = '';
  RecordStatus? _status;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final t = Theme.of(context).textTheme;
    final today = data.today;
    final q = _q.toLowerCase();
    final rows = data.employers.where((e) {
      if (_status != null && e.status != _status) return false;
      return q.isEmpty ||
          e.code.toLowerCase().contains(q) ||
          e.name.toLowerCase().contains(q);
    }).toList();

    Widget contractBadge(Employer e) {
      final contracts = data.contractsOf(e.id);
      if (contracts.isEmpty) {
        return const StatusBadge('No contract', dense: true);
      }
      final active = data.activeContract(e.id, today);
      final shown = active ?? contracts.first;
      final v = shown.validityOn(today);
      return StatusBadge(
        '${shown.contractCode} · ${v.label}',
        tone: contractTone(v),
        dense: true,
      );
    }

    int allocationCount(Employer e) =>
        data.allocationsOf(e.id).where((a) => a.active).length;

    return AdminPage(
      title: 'Companies & contracts',
      subtitle:
          'Registered client companies. Counts are derived from linked employee, shift and location records. Company IDs (e.g. company C1) are separate from vehicle IDs (e.g. Vehicle C1).',
      actions: [
        FilledButton.icon(
          onPressed: () => context.go('/fleet/companies/new'),
          icon: const Icon(Icons.add_business_outlined),
          label: const Text('Register company'),
        ),
      ],
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final search = AppSearchField(
              hint: 'Search company ID or name',
              onChanged: (v) => setState(() => _q = v.trim()),
            );
            final chips = FilterChipBar<RecordStatus?>(
              options: const [null, RecordStatus.active, RecordStatus.inactive],
              selected: _status,
              onSelected: (s) => setState(() => _status = s),
              labelOf: (s) => s?.label ?? 'All',
              countOf: (s) => s == null
                  ? data.employers.length
                  : data.employers.where((e) => e.status == s).length,
            );
            if (c.maxWidth < 760) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  search,
                  const SizedBox(height: AppSpace.sm),
                  chips,
                ],
              );
            }
            return Row(
              children: [
                SizedBox(width: 320, child: search),
                const SizedBox(width: AppSpace.md),
                Expanded(child: chips),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpace.md),
        AdaptiveTable<Employer>(
          rows: rows,
          onRowTap: (e) => context.go('/fleet/companies/${e.id}'),
          empty: EmptyState(
            icon: Icons.search_off_rounded,
            title: 'No companies match',
            message: 'Clear the search or filter.',
            actionLabel: 'Clear filters',
            onAction: () => setState(() {
              _q = '';
              _status = null;
            }),
          ),
          columns: [
            TableCol(
              'Company',
              (e) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Company ${e.code}', style: t.titleSmall),
                  Text(
                    e.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.muted(context),
                  ),
                ],
              ),
              flex: 4,
            ),
            TableCol('Contract', contractBadge, flex: 4),
            TableCol(
              'Billing · pooling',
              (e) => Text(
                '${e.billingCycle == BillingCycle.weekly ? 'Weekly' : 'Monthly'} · ${e.allowSharedPooling ? (e.allowCrossEmployerPooling ? 'Cross-company' : 'Shared') : 'No pooling'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              flex: 3,
            ),
            TableCol(
              'Employees',
              (e) => Text('${data.companyEmployeeCount(e.id)}'),
              flex: 2,
              numeric: true,
            ),
            TableCol(
              'Shifts',
              (e) => Text('${data.companyShiftCount(e.id)}'),
              flex: 1,
              numeric: true,
            ),
            TableCol(
              'Sites',
              (e) => Text('${data.companyLocationCount(e.id)}'),
              flex: 1,
              numeric: true,
            ),
            TableCol(
              'Allocations',
              (e) => Text('${allocationCount(e)}'),
              flex: 2,
              numeric: true,
            ),
            TableCol(
              'Status',
              (e) => StatusBadge(
                e.status.label,
                tone: e.isActive ? StatusTone.success : StatusTone.neutral,
                dense: true,
              ),
              flex: 2,
              numeric: true,
            ),
          ],
          mobileCard: (e) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Company ${e.code} · ${e.name}',
                      style: t.titleSmall,
                    ),
                  ),
                  StatusBadge(
                    e.status.label,
                    tone: e.isActive ? StatusTone.success : StatusTone.neutral,
                    dense: true,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${data.companyEmployeeCount(e.id)} employees · ${data.companyShiftCount(e.id)} shifts · ${data.companyLocationCount(e.id)} locations · ${allocationCount(e)} allocations',
                style: AppText.muted(context),
              ),
              const SizedBox(height: 6),
              contractBadge(e),
            ],
          ),
        ),
      ],
    );
  }
}

/// Register a new company (Fleet Manager).
class RegisterCompanyPage extends ConsumerStatefulWidget {
  const RegisterCompanyPage({super.key});

  @override
  ConsumerState<RegisterCompanyPage> createState() =>
      _RegisterCompanyPageState();
}

class _RegisterCompanyPageState extends ConsumerState<RegisterCompanyPage> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _contact = TextEditingController();
  final _email = TextEditingController();
  final _rate = TextEditingController(text: '18');
  final _tolerance = TextEditingController(text: '7');
  int _maxArrival = 570;
  BillingCycle _cycle = BillingCycle.weekly;
  bool _guard = false;
  bool _pooling = true;
  bool _cross = false;
  List<String> _errors = const [];
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_code, _name, _contact, _email, _rate, _tolerance]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final now = ref.read(dataProvider).now;
    final code = _code.text.trim().toUpperCase();
    final rate = double.tryParse(_rate.text.trim());
    final tol = int.tryParse(_tolerance.text.trim());
    final pre = <String>[
      if (rate == null) 'Rate must be a number.',
      if (tol == null) 'Tolerance must be a whole number of minutes.',
    ];
    if (pre.isNotEmpty) {
      setState(() => _errors = pre);
      return;
    }
    final e = Employer(
      id: code,
      code: code,
      name: _name.text.trim(),
      status: RecordStatus.active,
      currency: 'INR',
      maximumArrivalMinutes: _maxArrival,
      defaultDistanceRate: rate!,
      preferredEvPercentage: 50,
      vehicleTypePreferences: VehicleType.values,
      luxuryPreference: LuxuryClass.standard,
      costPriority: 50,
      punctualityPriority: 50,
      securityGuardPolicyEnabled: _guard,
      allowSharedPooling: _pooling,
      allowCrossEmployerPooling: _pooling && _cross,
      pickupToleranceMinutes: tol!,
      billingCycle: _cycle,
      contactName: _contact.text.trim(),
      contactEmail: _email.text.trim(),
      createdAt: now,
      updatedAt: now,
    );
    setState(() => _busy = true);
    final r = await ref.read(servicesProvider).employers.register(e);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _errors = r.errors;
    });
    if (r.isOk) {
      showToast(context, 'Company $code registered');
      context.go('/fleet/companies/$code');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      title: 'Register company',
      subtitle:
          'Fictional demo company. Employees, shifts and locations are added by the company\'s Employer Admin; contracts and fleet allocations are managed here.',
      actions: [
        TextButton.icon(
          onPressed: () => context.go('/fleet/companies'),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Companies'),
        ),
      ],
      maxWidth: 820,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_errors.isNotEmpty) ...[
                InlineBanner(
                  tone: StatusTone.danger,
                  title: 'Not registered',
                  messages: _errors,
                ),
                const SizedBox(height: AppSpace.md),
              ],
              FormRow(
                children: [
                  TextField(
                    key: const Key('companyCode'),
                    controller: _code,
                    decoration: const InputDecoration(
                      labelText: 'Company ID',
                      helperText: 'Unique, e.g. C2 — not a vehicle ID',
                    ),
                  ),
                  TextField(
                    key: const Key('companyName'),
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'Company name (fictional)',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              FormRow(
                children: [
                  TextField(
                    controller: _contact,
                    decoration: const InputDecoration(
                      labelText: 'Contact name (fictional)',
                    ),
                  ),
                  TextField(
                    controller: _email,
                    decoration: const InputDecoration(
                      labelText: 'Contact email (fictional)',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              FormRow(
                children: [
                  TimeOfDayField(
                    label: 'Maximum office arrival',
                    minutes: _maxArrival,
                    onChanged: (m) => setState(() => _maxArrival = m),
                  ),
                  TextField(
                    controller: _rate,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Distance rate (₹/km)',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              FormRow(
                children: [
                  TextField(
                    controller: _tolerance,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Pickup tolerance (± min)',
                      helperText: 'Client reference default: ±7 min',
                    ),
                  ),
                  DropdownButtonFormField<BillingCycle>(
                    isExpanded: true,
                    initialValue: _cycle,
                    decoration: const InputDecoration(
                      labelText: 'Billing cycle',
                    ),
                    items: [
                      for (final c in BillingCycle.values)
                        DropdownMenuItem(value: c, child: Text(c.label)),
                    ],
                    onChanged: (c) => setState(() => _cycle = c ?? _cycle),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _guard,
                onChanged: (v) => setState(() => _guard = v),
                title: const Text('Security guard policy'),
                subtitle: const Text(
                  'Explicit policy only; a guard seat is deducted from employee capacity where required.',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _pooling,
                onChanged: (v) => setState(() => _pooling = v),
                title: const Text('Allow shared pooling'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _cross,
                onChanged: _pooling ? (v) => setState(() => _cross = v) : null,
                title: const Text('Allow cross-company pooling'),
                subtitle: const Text(
                  'Only when every pooled company also allows it.',
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: const Key('registerCompany'),
                  onPressed: _busy ? null : _save,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Register'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
