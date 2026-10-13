import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/persistence/migrations.dart';
import '../../core/widgets/widgets.dart';
import '../../data/seed/seed_data.dart';
import '../../domain/rules/parameter_catalog.dart';

Future<void> showDemoToolsSheet(BuildContext context) => showAppSheet<void>(
  context,
  title: 'Demo tools',
  builder: (c) => const _DemoTools(),
);

class _DemoTools extends ConsumerStatefulWidget {
  const _DemoTools();

  @override
  ConsumerState<_DemoTools> createState() => _DemoToolsState();
}

class _DemoToolsState extends ConsumerState<_DemoTools> {
  bool _resetting = false;

  Future<void> _reset() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Reset demo data?',
      message:
          'This removes ALL local edits in every workspace — bookings, assignments, trips run, billing, incidents and settings — and restores the baseline dataset (C1, E1–E100, vehicles C1–C3, DR1–DR3). Demo sign-ins are cleared.',
      confirmLabel: 'Reset everything',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _resetting = true);
    await ref.read(servicesProvider).seed.reset();
    if (!mounted) return;
    setState(() => _resetting = false);
    Navigator.of(context).pop();
    GoRouter.of(context).go('/');
    showToast(context, 'Demo data restored to baseline');
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final db = data.db;
    final offline = ref
        .read(servicesProvider)
        .session
        .flag(IncidentService.simulateOfflineKey);
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const InlineBanner(
          tone: StatusTone.warning,
          title: 'Prototype',
          message:
              'No production backend, authentication, GPS, payments, SMS/push or emergency integration. All data is fictional and stored locally.',
        ),
        const SizedBox(height: AppSpace.md),
        AppCard(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Local data', style: t.titleSmall),
              KeyValueRow(
                label: 'Storage',
                value: db.storage.description,
                dense: true,
              ),
              KeyValueRow(
                label: 'Schema version',
                value: 'v$currentSchemaVersion',
                dense: true,
              ),
              KeyValueRow(
                label: 'Seed version',
                value: db.seedVersion ?? seedVersion,
                dense: true,
              ),
              KeyValueRow(
                label: 'Seeded',
                value: Fmt.dateTime(db.seededAt),
                dense: true,
              ),
              KeyValueRow(
                label: 'Demo day anchor',
                value: Fmt.date(db.seedAnchorDate),
                dense: true,
              ),
              KeyValueRow(
                label: 'Optimization parameters',
                value:
                    '${ParameterCatalog.count} defined · ${ParameterCatalog.liveCount} used by demo optimizer',
                dense: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        AppCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.xs,
            vertical: AppSpace.xxs,
          ),
          child: SwitchListTile(
            value: offline,
            onChanged: (v) async {
              await ref
                  .read(servicesProvider)
                  .session
                  .setFlag(IncidentService.simulateOfflineKey, v);
              setState(() {});
            },
            title: const Text('Simulate failed submissions'),
            subtitle: const Text(
              'Incident/breakdown reports fail as if offline, to demo retry with preserved input.',
            ),
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: _resetting ? null : _reset,
          icon: _resetting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.restart_alt_rounded),
          label: const Text('Reset demo data'),
        ),
        const SizedBox(height: AppSpace.xs),
        Text(
          'Seed data is inserted only on first run or after this reset. Your edits are never silently overwritten.',
          style: AppText.muted(context),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
