import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/widgets.dart';
import '../../../domain/models/models.dart';
import '../../../domain/rules/parameter_catalog.dart';
import '../widgets/fleet_common.dart';
import '../widgets/profile_editor.dart';
import '../../shared/audit_trail_view.dart';

class FleetSettingsPage extends ConsumerStatefulWidget {
  const FleetSettingsPage({super.key});

  @override
  ConsumerState<FleetSettingsPage> createState() => _FleetSettingsPageState();
}

class _FleetSettingsPageState extends ConsumerState<FleetSettingsPage> {
  OptimizationConfig? _config;
  List<String> _errors = const [];
  int _editorVersion = 0;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final saved = data.optimizationConfigs.firstOrNull;
    final cfg = _config ?? saved;

    final profile = PanelCard(
      title: 'Default optimization profile',
      subtitle: cfg == null
          ? null
          : '${cfg.name} · updated ${Fmt.dateTime(cfg.updatedAt)}',
      trailing: TextButton(
        onPressed: () => context.go('/fleet/optimization/parameters'),
        child: Text('${ParameterCatalog.count} parameters'),
      ),
      child: cfg == null
          ? const Text('No profile available.')
          : Column(
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
                ProfileEditor(
                  key: ValueKey(_editorVersion),
                  config: cfg,
                  onChanged: (c) => setState(() => _config = c),
                ),
                const SizedBox(height: AppSpace.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_config != null)
                      TextButton(
                        onPressed: () => setState(() {
                          _config = null;
                          _editorVersion++;
                        }),
                        child: const Text('Discard'),
                      ),
                    const SizedBox(width: AppSpace.xs),
                    FilledButton.icon(
                      onPressed: _config == null
                          ? null
                          : () async {
                              final r = await ref
                                  .read(servicesProvider)
                                  .optimization
                                  .saveConfig(_config!);
                              if (!mounted) return;
                              setState(() {
                                _errors = r.errors;
                                if (r.isOk) {
                                  _config = null;
                                  _editorVersion++;
                                }
                              });
                              if (context.mounted) await showResult(context, r);
                            },
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save profile'),
                    ),
                  ],
                ),
              ],
            ),
    );

    final about = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelCard(
          title: 'Workspace',
          child: Column(
            children: [
              KeyValueRow(
                label: 'Role',
                value: 'Fleet Manager (demo identity)',
              ),
              KeyValueRow(
                label: 'Employers served',
                value: data.employers.map((e) => e.code).join(', '),
              ),
              KeyValueRow(
                label: 'Fleet',
                value:
                    '${data.vehicles.length} vehicles · ${data.drivers.length} drivers',
              ),
              KeyValueRow(
                label: 'Unread notifications',
                value: '${data.unreadCount(UserRole.fleetManager)}',
              ),
              const SizedBox(height: AppSpace.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => context.go('/fleet/notifications'),
                  icon: const Icon(Icons.notifications_none_rounded),
                  label: const Text('Open notifications'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        const InlineBanner(
          tone: StatusTone.warning,
          title: 'Prototype limits',
          messages: [
            DemoLabels.optimizer,
            'Live GPS, traffic, dispatch messaging and emergency services are not connected.',
            DemoLabels.launcherNotAuth,
          ],
        ),
      ],
    );

    return AdminPage(
      title: 'Settings',
      subtitle:
          'Optimization defaults and the audit trail of every consequential change.',
      children: [
        ResponsiveSplit(left: profile, right: about),
        const SizedBox(height: AppSpace.md),
        PanelCard(
          title: 'Audit trail',
          subtitle:
              '${data.auditTrail.length} events · newest first · tap an event for before/after and the related record',
          trailing: TextButton.icon(
            onPressed: () => exportCsv(
              context,
              ref,
              fileName: 'audit_trail.csv',
              header: [
                'timestamp',
                'actor_role',
                'actor',
                'action',
                'entity_type',
                'entity_id',
                'outcome',
                'summary',
                'changes',
                'reason',
              ],
              rows: [
                for (final a in data.auditTrail)
                  [
                    a.timestamp.toIso8601String(),
                    a.actorRole.label,
                    a.actorId,
                    a.action,
                    a.entityType,
                    a.entityId,
                    a.outcome.label,
                    a.summary,
                    a.changes,
                    a.reason,
                  ],
              ],
            ),
            icon: const Icon(Icons.download_outlined),
            label: const Text('CSV'),
          ),
          child: AuditTrailView(
            onOpenEntity: (type, id) {
              final path = fleetEntityPath(data, type, id);
              if (path != null) context.go(path);
            },
          ),
        ),
      ],
    );
  }
}
