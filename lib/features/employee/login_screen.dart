import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../data/seed/seed_data.dart';
import '../../domain/models/models.dart';

/// Demo identity picker. Not real authentication.
class EmployeeLoginScreen extends ConsumerStatefulWidget {
  const EmployeeLoginScreen({super.key});

  @override
  ConsumerState<EmployeeLoginScreen> createState() =>
      _EmployeeLoginScreenState();
}

class _EmployeeLoginScreenState extends ConsumerState<EmployeeLoginScreen> {
  String _query = '';
  bool _busy = false;

  Future<void> _signIn(Employee e) async {
    String? password;
    if (e.optionalDemoPasswordEnabled) {
      password = await _askPassword(e);
      if (password == null) return;
    }
    setState(() => _busy = true);
    final r = await ref
        .read(servicesProvider)
        .session
        .signInEmployee(e.id, password: password);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.isOk) {
      context.go('/employee/home');
    } else {
      await showResult(context, r, failureTitle: 'Could not sign in');
    }
  }

  Future<String?> _askPassword(Employee e) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Password for ${e.employeeCode}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This demo profile is configured with an optional password.',
            ),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: c,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Demo password'),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              'Demo hint: $demoEmployeePassword (fictional, not a real credential)',
              style: AppText.muted(ctx),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final t = Theme.of(context).textTheme;
    final featured = [
      'E1',
      'E2',
      'E3',
      'E4',
    ].map(data.employee).whereType<Employee>().toList();
    final q = _query.trim().toLowerCase();
    final others = q.isEmpty
        ? <Employee>[]
        : data.employees
              .where(
                (e) =>
                    e.isActive &&
                    (e.employeeCode.toLowerCase().contains(q) ||
                        e.name.toLowerCase().contains(q)),
              )
              .take(20)
              .toList();

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
      body: Center(
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
              const Align(
                alignment: Alignment.centerLeft,
                child: IconTile(icon: Icons.person_outline_rounded, size: 52),
              ),
              const SizedBox(height: AppSpace.md),
              Text('Welcome', style: t.headlineMedium),
              const SizedBox(height: 4),
              Text(
                'Choose a demo employee to continue.',
                style: t.bodyLarge!.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpace.xl),
              Text('DEMO IDENTITIES', style: AppText.overline(context)),
              const SizedBox(height: AppSpace.xs),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < featured.length; i++) ...[
                      if (i > 0) const Divider(height: 1, indent: 72),
                      _IdentityTile(
                        employee: featured[i],
                        data: data,
                        onTap: _busy ? null : () => _signIn(featured[i]),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.xl),
              Text('ANY ACTIVE EMPLOYEE', style: AppText.overline(context)),
              const SizedBox(height: AppSpace.xs),
              AppSearchField(
                hint: 'Search by ID or name (e.g. E27)',
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: AppSpace.xs),
              if (q.isNotEmpty && others.isEmpty)
                EmptyState(
                  icon: Icons.person_search_outlined,
                  title: 'No active employee found',
                  message:
                      'Try another ID or name. Deactivated employees cannot sign in.',
                  compact: true,
                ),
              if (others.isNotEmpty)
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < others.length; i++) ...[
                        if (i > 0) const Divider(height: 1, indent: 72),
                        _IdentityTile(
                          employee: others[i],
                          data: data,
                          onTap: _busy ? null : () => _signIn(others[i]),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: AppSpace.xl),
              const SimulatedNote(
                'Demo sign-in only — no real authentication. All profiles and contacts are fictional.',
                icon: Icons.lock_open_outlined,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IdentityTile extends StatelessWidget {
  const _IdentityTile({
    required this.employee,
    required this.data,
    required this.onTap,
  });
  final Employee employee;
  final DataView data;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final e = employee;
    return ListTile(
      onTap: onTap,
      minVerticalPadding: 14,
      leading: InitialsAvatar(initials: e.initials, size: 44),
      title: Text(e.name),
      subtitle: Text(
        '${e.employeeCode} · ${data.location(e.pickupLocationId)?.name ?? '—'} → ${e.destinationId}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (e.optionalDemoPasswordEnabled)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Tooltip(
                message: 'Password configured (demo)',
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 18,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        ],
      ),
    );
  }
}
