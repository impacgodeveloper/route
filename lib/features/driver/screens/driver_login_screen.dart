import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/widgets.dart';
import '../../../domain/models/models.dart';

/// Demo identity picker for DR1–DR3. Not real authentication.
class DriverLoginScreen extends ConsumerStatefulWidget {
  const DriverLoginScreen({super.key});

  @override
  ConsumerState<DriverLoginScreen> createState() => _DriverLoginScreenState();
}

class _DriverLoginScreenState extends ConsumerState<DriverLoginScreen> {
  String? _busy;

  Future<void> _signIn(String id) async {
    setState(() => _busy = id);
    final r = await ref.read(servicesProvider).session.signInDriver(id);
    if (!mounted) return;
    setState(() => _busy = null);
    if (r.isOk) {
      context.go('/driver/home');
    } else {
      await showResult(context, r);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to sign-in',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/'),
        ),
        actions: const [
          Center(child: DemoBadge()),
          SizedBox(width: AppSpace.md),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.gutter,
                AppSpace.xs,
                AppSpace.gutter,
                AppSpace.xxxl,
              ),
              children: [
                const IconTile(
                  icon: Icons.drive_eta_outlined,
                  color: AppColors.driverAccent,
                  size: 56,
                ),
                const SizedBox(height: AppSpace.md),
                Text('Driver sign-in', style: t.headlineMedium),
                const SizedBox(height: AppSpace.xs),
                Text(
                  'Choose a demo driver to continue.',
                  style: t.bodyLarge!.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpace.xl),
                for (final d in data.drivers) ...[
                  Builder(
                    builder: (context) {
                      final shift = data.todayShift(d.id);
                      final v = data.vehicle(d.assignedVehicleId);
                      final shiftLabel = shift == null
                          ? 'No shift record today'
                          : shift.actualCheckIn == null
                          ? 'Shift ${Fmt.time(shift.scheduledStart)}–${Fmt.time(shift.scheduledEnd)} · not checked in'
                          : shift.status == ShiftStatus.completed
                          ? 'Shift completed'
                          : 'Checked in ${Fmt.time(shift.actualCheckIn)}';
                      return AppCard(
                        onTap: _busy == null ? () => _signIn(d.id) : null,
                        semanticLabel: 'Sign in as ${d.driverCode} ${d.name}',
                        child: Row(
                          children: [
                            InitialsAvatar(
                              initials: d.initials,
                              color: AppColors.driverAccent,
                              size: 48,
                            ),
                            const SizedBox(width: AppSpace.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${d.driverCode} · ${d.name}',
                                    style: t.titleMedium,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    v == null
                                        ? 'No default vehicle'
                                        : 'Vehicle ${v.vehicleCode} · ${v.propulsion.label} ${v.type.label}',
                                    style: t.bodySmall!.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  Text(
                                    shiftLabel,
                                    style: t.bodySmall!.copyWith(
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_busy == d.id)
                              const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            else
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: AppColors.textMuted,
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpace.sm),
                ],
                const SizedBox(height: AppSpace.md),
                const SimulatedNote(
                  'Demo identities only. Production sign-in and authorization are not part of this prototype.',
                  icon: Icons.lock_open_outlined,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
