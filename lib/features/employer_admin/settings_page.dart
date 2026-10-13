import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import '../shared/audit_trail_view.dart';
import 'employer_common.dart';

/// Where an audit/notification entity opens in the Employer console
/// (null = no employer-visible record).
String? employerPathFor(DataView data, String entityType, String id) =>
    switch (entityType) {
      'trip' => EmployerPaths.trip(id),
      'billing' => EmployerPaths.bill(id),
      'invoice' => EmployerPaths.invoice(id),
      'employee' => EmployerPaths.employee(id),
      'employer' => EmployerPaths.policies,
      'location' => EmployerPaths.locations,
      'traffic' => EmployerPaths.traffic,
      'booking' =>
        data.booking(id) == null
            ? null
            : EmployerPaths.employee(data.booking(id)!.employeeId),
      'incident' when data.incident(id)?.isSos ?? false => EmployerPaths.sos(
        id,
      ),
      'incident' =>
        data.incident(id)?.tripId == null
            ? null
            : EmployerPaths.trip(data.incident(id)!.tripId!),
      _ => null,
    };

/// Company settings and the audit trail.
class EmployerSettingsPage extends ConsumerStatefulWidget {
  const EmployerSettingsPage({super.key});

  @override
  ConsumerState<EmployerSettingsPage> createState() =>
      _EmployerSettingsPageState();
}

class _EmployerSettingsPageState extends ConsumerState<EmployerSettingsPage> {
  final _name = TextEditingController();
  final _rate = TextEditingController();
  bool _loaded = false;
  List<String> _errors = const [];

  @override
  void dispose() {
    _name.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<void> _save(Employer e) async {
    final rate = double.tryParse(_rate.text.trim());
    if (rate == null) {
      setState(() => _errors = ['Rate must be a number.']);
      return;
    }
    final next = e.copyWith(name: _name.text.trim(), defaultDistanceRate: rate);
    if (rate != e.defaultDistanceRate || next.name != e.name) {
      final ok = await showConfirmDialog(
        context,
        title: 'Save company settings?',
        message: rate != e.defaultDistanceRate
            ? 'The billing rate changes from ${Fmt.inr(e.defaultDistanceRate)} to ${Fmt.inr(rate)} per km for bills generated from now on. Existing bills keep their rate.'
            : 'Company name will be updated across all workspaces.',
        confirmLabel: 'Save',
      );
      if (!ok || !mounted) return;
    }
    final r = await ref.read(servicesProvider).employers.update(next);
    if (!mounted) return;
    setState(() => _errors = r.errors);
    if (r.isOk) showToast(context, 'Company settings saved');
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final e = data.primaryEmployer;
    if (!_loaded) {
      _loaded = true;
      _name.text = e.name;
      _rate.text = e.defaultDistanceRate.toStringAsFixed(2);
    }
    final t = Theme.of(context).textTheme;

    final profile = PanelCard(
      title: 'Company profile',
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
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Company name'),
          ),
          const SizedBox(height: AppSpace.sm),
          FormRow(
            children: [
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Employer code',
                  enabled: false,
                ),
                child: Text(e.code),
              ),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Currency',
                  enabled: false,
                ),
                child: Text('${e.currency} (₹)'),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          TextField(
            controller: _rate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Billing rate',
              prefixText: '₹ ',
              suffixText: '/ km',
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => _save(e),
              child: const Text('Save settings'),
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          KeyValueRow(
            label: 'Last updated',
            value: Fmt.dateTime(e.updatedAt),
            dense: true,
          ),
          KeyValueRow(
            label: 'Policies',
            valueWidget: TextButton(
              onPressed: () => context.go(EmployerPaths.policies),
              child: const Text('Rosters & Policies'),
            ),
            dense: true,
          ),
          KeyValueRow(
            label: 'Billing configuration',
            valueWidget: TextButton(
              onPressed: () => context.go(EmployerPaths.billingTab('config')),
              child: const Text('Billing'),
            ),
            dense: true,
          ),
        ],
      ),
    );

    final demo = PanelCard(
      title: 'Demo environment',
      trailing: const DemoBadge(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(DemoLabels.localOnly, style: t.bodyMedium),
          const SizedBox(height: AppSpace.xs),
          Text(
            'Production authentication, authorization, encryption, retention and backend validation are not provided by this prototype.',
            style: AppText.secondary(context),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            'To restore the baseline dataset, use "Reset demo data" in Demo tools on the sign-in screen (requires confirmation).',
            style: AppText.muted(context),
          ),
          const SizedBox(height: AppSpace.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => context.go('/'),
              icon: const Icon(Icons.swap_horiz_rounded),
              label: const Text('Back to sign-in'),
            ),
          ),
        ],
      ),
    );

    return AdminPage(
      title: 'Settings',
      subtitle: 'Company profile, billing rate and audit trail.',
      children: [
        ResponsiveColumns(
          left: profile,
          right: demo,
          leftFlex: 1,
          rightFlex: 1,
          breakpoint: 900,
        ),
        const SizedBox(height: AppSpace.md),
        PanelCard(
          title: 'Audit trail',
          subtitle: 'Events concerning ${e.code}, from every workspace',
          child: AuditTrailView(
            companyId: e.id,
            onOpenEntity: (type, id) {
              final path = employerPathFor(ref.read(dataProvider), type, id);
              if (path != null) {
                context.go(path);
              } else {
                showToast(context, 'No employer view for this $type record');
              }
            },
          ),
        ),
      ],
    );
  }
}
