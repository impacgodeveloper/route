import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/widgets.dart';
import '../../../domain/rules/capacity_rules.dart';
import '../driver_common.dart';
import '../driver_v2_widgets.dart';

class DriverProfileScreen extends ConsumerWidget {
  const DriverProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(driverDayProvider);
    if (day == null) return const LoadingState();
    final d = day.driver;
    final v = day.data.vehicle(d.assignedVehicleId);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: MobilePage(
        children: [
          AppCard(
            child: Row(
              children: [
                InitialsAvatar(
                  initials: d.initials,
                  color: AppColors.driverAccent,
                  size: 60,
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.name, style: t.titleLarge),
                      Text(
                        '${d.driverCode} · ${d.completedTripCount} trips completed',
                        style: AppText.secondary(context),
                      ),
                      const SizedBox(height: 6),
                      StatusBadge(
                        d.status.label,
                        tone: Tones.driver(d.status),
                        dense: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Overline('Details'),
                KeyValueRow(
                  label: 'Phone (fictional)',
                  value: d.fictionalContact,
                  dense: true,
                ),
                KeyValueRow(
                  label: 'Email (fictional)',
                  value: d.email.isEmpty ? '—' : d.email,
                  dense: true,
                ),
                KeyValueRow(
                  label: 'Address (fictional)',
                  value: d.address.isEmpty ? '—' : d.address,
                  dense: true,
                ),
                KeyValueRow(
                  label: 'Gender (self-declared)',
                  value: d.gender.label,
                  dense: true,
                ),
                KeyValueRow(
                  label: 'Licence class',
                  value: d.licenceClass,
                  dense: true,
                ),
                KeyValueRow(
                  label: 'Licence number',
                  value: d.licenceNumber.isEmpty
                      ? 'Not recorded'
                      : d.licenceNumber,
                  dense: true,
                ),
                KeyValueRow(
                  label: 'Licence expiry',
                  value: Fmt.date(d.licenceExpiry),
                  dense: true,
                ),
                ..._licenceWarning(d.licenceExpiry, day.data.today),
                KeyValueRow(
                  label: 'Default shift',
                  value:
                      '${Fmt.minutesOfDay(d.shiftStartMinutes)} – ${Fmt.minutesOfDay(d.shiftEndMinutes)}',
                  dense: true,
                ),
                KeyValueRow(
                  label: 'Safety checklist',
                  value: d.safetyChecklistStatus.label,
                  dense: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Overline('Assigned vehicle'),
                if (v == null)
                  Text(
                    'No default vehicle — trips may use any pool vehicle.',
                    style: AppText.secondary(context),
                  )
                else ...[
                  KeyValueRow(
                    label: 'Vehicle',
                    value: 'Vehicle ${v.vehicleCode} · ${v.model}',
                    dense: true,
                  ),
                  KeyValueRow(
                    label: 'Registration (fictional)',
                    value: v.fictionalRegistration,
                    dense: true,
                  ),
                  KeyValueRow(
                    label: 'Type',
                    value:
                        '${v.propulsion.label} ${v.type.label} · ${v.luxuryClass.label}',
                    dense: true,
                  ),
                  KeyValueRow(
                    label: 'Employee seats',
                    value:
                        '${CapacityRules.breakdown(v).passengerCapacity} of ${v.totalSeats}',
                    dense: true,
                  ),
                  DiagnosticsRow(vehicle: v),
                  const SizedBox(height: AppSpace.sm),
                  OutlinedButton.icon(
                    onPressed: () =>
                        context.push('/driver/inspection?vehicle=${v.id}'),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Vehicle inspection'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('Attendance'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/driver/attendance'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.summarize_outlined),
                  title: const Text('Shift summary'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/driver/shift-summary'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.support_agent_rounded),
                  title: const Text('Support'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/driver/support'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          BigButton(
            label: 'Switch driver',
            icon: Icons.switch_account_outlined,
            outlined: true,
            onPressed: () async {
              await ref.read(servicesProvider).session.signOutDriver();
              if (context.mounted) context.go('/driver/login');
            },
          ),
          const SizedBox(height: AppSpace.sm),
          TextButton.icon(
            onPressed: () async {
              await ref.read(servicesProvider).session.signOutDriver();
              if (context.mounted) context.go('/');
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
          ),
          const SizedBox(height: AppSpace.sm),
          const SimulatedNote(
            'Identity numbers and age are not collected in this prototype. Gender is optional, self-declared and never used for assignments.',
            icon: Icons.privacy_tip_outlined,
          ),
          const SizedBox(height: AppSpace.xs),
          const SimulatedNote(
            DemoLabels.localOnly,
            icon: Icons.storage_outlined,
          ),
        ],
      ),
    );
  }
}

/// Licence status banner: expired (blocks assignment) or expiring ≤ 30 days.
List<Widget> _licenceWarning(DateTime? expiry, DateTime today) {
  if (expiry == null) return const [];
  final days = DateTime(
    expiry.year,
    expiry.month,
    expiry.day,
  ).difference(today).inDays;
  if (days < 0) {
    return [
      const SizedBox(height: AppSpace.xs),
      InlineBanner(
        tone: StatusTone.danger,
        title: 'Licence expired',
        message:
            'Expired ${Fmt.date(expiry)}. You cannot be assigned trips until it is renewed and updated by the Fleet Manager.',
      ),
    ];
  }
  if (days <= 30) {
    return [
      const SizedBox(height: AppSpace.xs),
      InlineBanner(
        tone: StatusTone.warning,
        title: 'Licence expires in $days day${days == 1 ? '' : 's'}',
        message:
            'Renew before ${Fmt.date(expiry)} — after that, trip assignment is blocked.',
      ),
    ];
  }
  return const [];
}
