import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import '../../domain/rules/geo_rules.dart';
import 'employee_common.dart';

class EmployeeProfileScreen extends ConsumerStatefulWidget {
  const EmployeeProfileScreen({super.key});

  @override
  ConsumerState<EmployeeProfileScreen> createState() =>
      _EmployeeProfileScreenState();
}

class _EmployeeProfileScreenState extends ConsumerState<EmployeeProfileScreen> {
  String? _pickup;
  TransportPreference? _pref;
  bool _saving = false;

  Future<void> _savePreferences(Employee e) async {
    setState(() => _saving = true);
    final r = await ref
        .read(servicesProvider)
        .employees
        .updatePickupPreference(
          e.id,
          _pickup ?? e.pickupLocationId,
          _pref ?? e.transportPreference,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (await showResult(context, r)) {
      setState(() {
        _pickup = null;
        _pref = null;
      });
    }
  }

  Future<void> _toggle(UserSettings s) async {
    final r = await ref.read(servicesProvider).settings.save(s);
    if (!r.isOk && mounted) await showResult(context, r);
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final e = ref.watch(currentEmployeeProvider);
    if (e == null) return const LoadingState();
    final t = Theme.of(context).textTheme;
    final employer = data.employer(e.employerId);
    final settings = data.settingsFor('employee:${e.id}');
    final pickup = _pickup ?? e.pickupLocationId;
    final pref = _pref ?? e.transportPreference;
    final dirty = pickup != e.pickupLocationId || pref != e.transportPreference;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: MobilePage(
        children: [
          AppCard(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(
              children: [
                Row(
                  children: [
                    InitialsAvatar(initials: e.initials, size: 56),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.name, style: t.titleLarge),
                          Text(
                            '${e.employeeCode} · ${employer?.name ?? e.employerId}',
                            style: AppText.secondary(context),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.md),
                KeyValueRow(
                  icon: Icons.mail_outline_rounded,
                  label: 'Email',
                  value: e.fictionalEmail,
                  dense: true,
                ),
                KeyValueRow(
                  icon: Icons.phone_outlined,
                  label: 'Phone',
                  value: e.fictionalPhone,
                  dense: true,
                ),
                KeyValueRow(
                  icon: Icons.apartment_outlined,
                  label: 'Office',
                  value: data.locationLabel(e.destinationId),
                  dense: true,
                ),
                const SizedBox(height: AppSpace.xs),
                const SimulatedNote('Fictional demo contact details.'),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.sectionGap),
          const SectionHeader(
            title: 'My schedule',
            subtitle: 'Set by your employer. Contact HR/admin to change it.',
          ),
          const SizedBox(height: AppSpace.sm),
          _ScheduleCard(employee: e, data: data),
          const SizedBox(height: AppSpace.md),
          _TravelPreferencesTile(employee: e),
          const SizedBox(height: AppSpace.md),
          _GenderCard(employee: e),
          const SizedBox(height: AppSpace.sectionGap),
          const SectionHeader(
            title: 'Pickup & preferences',
            subtitle:
                'Applies to future trips. Arrival time is set by your employer.',
          ),
          const SizedBox(height: AppSpace.sm),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  key: ValueKey('pickup-${e.pickupLocationId}'),
                  initialValue: pickup,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Default pickup point',
                  ),
                  items: [
                    for (final l in data.pickupLocations)
                      DropdownMenuItem(
                        value: l.id,
                        child: Text(
                          '${l.code} · ${l.name}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _pickup = v),
                ),
                const SizedBox(height: AppSpace.sm),
                DropdownButtonFormField<TransportPreference>(
                  key: ValueKey('pref-${e.transportPreference.name}'),
                  initialValue: pref,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Transport preference',
                  ),
                  items: [
                    for (final p in TransportPreference.values)
                      DropdownMenuItem(value: p, child: Text(p.label)),
                  ],
                  onChanged: (v) => setState(() => _pref = v),
                ),
                const SizedBox(height: AppSpace.md),
                FilledButton(
                  onPressed: !dirty || _saving
                      ? null
                      : () => _savePreferences(e),
                  child: Text(_saving ? 'Saving…' : 'Save preferences'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.sectionGap),
          const SectionHeader(title: 'Privacy & notifications'),
          const SizedBox(height: AppSpace.sm),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Show simulated vehicle position'),
                  subtitle: const Text(
                    'Displays the demo position on trip tracking.',
                  ),
                  value: settings.shareSimulatedLocation,
                  onChanged: (v) =>
                      _toggle(settings.copyWith(shareSimulatedLocation: v)),
                ),
                SwitchListTile(
                  title: const Text('Pickup reminders'),
                  value: settings.pickupReminders,
                  onChanged: (v) =>
                      _toggle(settings.copyWith(pickupReminders: v)),
                ),
                SwitchListTile(
                  title: const Text('Delay alerts'),
                  value: settings.delayAlerts,
                  onChanged: (v) => _toggle(settings.copyWith(delayAlerts: v)),
                ),
                SwitchListTile(
                  title: const Text('Service notices'),
                  value: settings.serviceNotices,
                  onChanged: (v) =>
                      _toggle(settings.copyWith(serviceNotices: v)),
                ),
                SwitchListTile(
                  title: const Text('Larger text'),
                  subtitle: const Text('Increases text size in this app.'),
                  value: settings.largeText,
                  onChanged: (v) => _toggle(settings.copyWith(largeText: v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          const SimulatedNote(
            'Preferences are stored locally. Notifications are in-app only for this prototype.',
          ),
          const SizedBox(height: AppSpace.sectionGap),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.health_and_safety_outlined),
                  title: const Text('Safety centre'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/employee/safety'),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.support_agent_outlined),
                  title: const Text('Contact support'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/employee/support/new'),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.switch_account_outlined),
                  title: const Text('Switch demo employee'),
                  onTap: () async {
                    await ref.read(servicesProvider).session.signOutEmployee();
                    if (context.mounted) context.go('/employee/login');
                  },
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.logout_rounded),
                  title: const Text('Sign out'),
                  onTap: () async {
                    await ref.read(servicesProvider).session.signOutEmployee();
                    if (context.mounted) context.go('/');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Read-only schedule & tolerance summary (employer-managed).
class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.employee, required this.data});
  final Employee employee;
  final DataView data;

  @override
  Widget build(BuildContext context) {
    final e = employee;
    final employer = data.employer(e.employerId);
    final deadline = effectiveDeadlineMinutes(e, employer);
    final tol = e.toleranceMinutes(employer);
    final pickup = data.location(e.pickupLocationId);
    final latLng = pickup == null ? null : GeoRules.latLngOf(pickup);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeyValueRow(
            icon: Icons.schedule_rounded,
            label: 'Shift',
            value: shiftText(e),
            dense: true,
          ),
          KeyValueRow(
            icon: Icons.flag_outlined,
            label: 'Office arrival',
            value: Fmt.minutesOfDay(e.requiredArrivalMinutes),
            dense: true,
          ),
          KeyValueRow(
            icon: Icons.alarm_on_outlined,
            label: 'Arrival deadline',
            value: Fmt.minutesOfDay(deadline),
            dense: true,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 30, bottom: 4),
            child: Text(
              'Earliest of office arrival, shift start'
              '${employer == null ? '' : ' and company maximum ${Fmt.minutesOfDay(employer.maximumArrivalMinutes)}'}.',
              style: AppText.muted(context),
            ),
          ),
          KeyValueRow(
            icon: Icons.timelapse_rounded,
            label: 'Pickup tolerance',
            value:
                '±$tol min · ${e.pickupToleranceMinutes != null ? 'your setting' : 'company default'}',
            dense: true,
          ),
          KeyValueRow(
            icon: Icons.trip_origin_rounded,
            label: 'Pickup point',
            value: pickup?.label ?? e.pickupLocationId,
            dense: true,
          ),
          if (latLng != null)
            KeyValueRow(
              icon: Icons.my_location_outlined,
              label: 'Coordinates',
              value:
                  '${latLng.$1.toStringAsFixed(5)}, ${latLng.$2.toStringAsFixed(5)}',
              dense: true,
            ),
          const SizedBox(height: AppSpace.xs),
          const SimulatedNote(
            DemoLabels.fictionalCoordinates,
            icon: Icons.location_off_outlined,
          ),
          const SizedBox(height: 4),
          const SimulatedNote(
            'Tolerance is the allowed early/late pickup window. It never excuses a missed office deadline.',
            icon: Icons.info_outline_rounded,
          ),
        ],
      ),
    );
  }
}

class _TravelPreferencesTile extends StatelessWidget {
  const _TravelPreferencesTile({required this.employee});
  final Employee employee;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final set = TravelPreferenceKeys.active
        .where((k) => employee.preference(k) > 0)
        .map(
          (k) =>
              '${TravelPreferenceKeys.label(k)}: ${TravelPreferenceKeys.levels[employee.preference(k)]}',
        )
        .toList();
    return AppCard(
      onTap: () => context.push('/employee/preferences'),
      semanticLabel: 'Travel preferences',
      child: Row(
        children: [
          const IconTile(icon: Icons.tune_rounded, size: 40),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Travel preferences', style: t.titleSmall),
                const SizedBox(height: 2),
                Text(
                  set.isEmpty ? 'No preferences set' : set.join(' · '),
                  style: AppText.muted(context),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

/// Optional self-declared gender. Never used by any algorithm.
class _GenderCard extends ConsumerWidget {
  const _GenderCard({required this.employee});
  final Employee employee;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    var choice = employee.gender;
    final picked = await showDialog<SelfDeclaredGender>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: const Text('Self-declared gender'),
          content: RadioGroup<SelfDeclaredGender>(
            groupValue: choice,
            onChanged: (v) => setLocal(() => choice = v ?? choice),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final g in SelfDeclaredGender.values)
                  RadioListTile<SelfDeclaredGender>(
                    value: g,
                    title: Text(g.label),
                    contentPadding: EdgeInsets.zero,
                  ),
                const SizedBox(height: AppSpace.xs),
                const SimulatedNote(
                  'Optional. Not used by any matching, pooling or scoring algorithm.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, choice),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (picked == null || picked == employee.gender || !context.mounted) {
      return;
    }
    // Apply only the gender change to the latest stored record.
    final latest = ref.read(dataProvider).employee(employee.id) ?? employee;
    final r = await ref
        .read(servicesProvider)
        .employees
        .save(
          latest.copyWith(gender: picked),
          actor: Actor.employee(employee.id),
        );
    if (context.mounted) await showResult(context, r, successMessage: 'Saved');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Self-declared gender (optional)', style: t.titleSmall),
                const SizedBox(height: 2),
                Text(employee.gender.label, style: AppText.secondary(context)),
                const SizedBox(height: 2),
                Text(
                  'Not used by any algorithm.',
                  style: AppText.muted(context),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _edit(context, ref),
            child: const Text('Edit'),
          ),
        ],
      ),
    );
  }
}
