import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../data/seed/seed_data.dart';
import '../../domain/models/models.dart';
import 'demo_tools_sheet.dart';

/// The four sign-in roles and where each one lands.
enum SignInRole {
  employee(
    'Employee',
    'Commuting employee · mobile app',
    Icons.person_outline_rounded,
    AppColors.employeeAccent,
    '/employee/home',
  ),
  driver(
    'Driver',
    'On-duty driver · mobile app',
    Icons.drive_eta_outlined,
    AppColors.driverAccent,
    '/driver/home',
  ),
  employer(
    'Employer Admin',
    'Company transport admin · web console',
    Icons.business_outlined,
    AppColors.employerAccent,
    '/employer/overview',
  ),
  fleet(
    'Fleet Manager',
    'Fleet operations · web console',
    Icons.hub_outlined,
    AppColors.fleetAccent,
    '/fleet/overview',
  );

  const SignInRole(this.label, this.caption, this.icon, this.accent, this.home);
  final String label;
  final String caption;
  final IconData icon;
  final Color accent;
  final String home;

  /// Key stored as "last workspace" (matches previous launcher keys).
  String get key => switch (this) {
    SignInRole.employee => 'employee',
    SignInRole.driver => 'driver',
    SignInRole.employer => 'employer',
    SignInRole.fleet => 'fleet',
  };

  static SignInRole fromKey(String? k) =>
      SignInRole.values.where((r) => r.key == k).firstOrNull ??
      SignInRole.employee;
}

/// Demo sign-in. Picks a role, then an identity for that role, and opens
/// the matching application. This is NOT real authentication.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  SignInRole? _role;
  String? _employeeId;
  String? _driverId;
  String? _employerId;
  final _password = TextEditingController();
  final _employeeSearch = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _employeeSearch.dispose();
    super.dispose();
  }

  bool _needsPassword(DataView d, SignInRole role) => switch (role) {
    SignInRole.employee =>
      d.employee(_employeeId)?.optionalDemoPasswordEnabled ?? false,
    SignInRole.driver => false,
    SignInRole.employer || SignInRole.fleet => true,
  };

  Future<void> _signIn() async {
    final role = _role!;
    final data = ref.read(dataProvider);
    final services = ref.read(servicesProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    switch (role) {
      case SignInRole.employee:
        if (_employeeId == null) {
          error = 'Select an employee to continue.';
          break;
        }
        final r = await services.session.signInEmployee(
          _employeeId!,
          password: _needsPassword(data, role) ? _password.text : null,
        );
        if (!r.isOk) error = r.message;
      case SignInRole.driver:
        if (_driverId == null) {
          error = 'Select a driver to continue.';
          break;
        }
        final r = await services.session.signInDriver(_driverId!);
        if (!r.isOk) error = r.message;
      case SignInRole.employer:
        if (_employerId == null) {
          error = 'Select a company to continue.';
        } else if (_password.text != demoEmployeePassword) {
          error = _password.text.isEmpty
              ? 'Enter the password.'
              : 'Incorrect demo password.';
        }
      case SignInRole.fleet:
        if (_password.text != demoEmployeePassword) {
          error = _password.text.isEmpty
              ? 'Enter the password.'
              : 'Incorrect demo password.';
        }
    }
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _busy = false;
        _error = error;
      });
      return;
    }
    await services.session.rememberWorkspace(role.key);
    if (!mounted) return;
    setState(() => _busy = false);
    context.go(role.home);
  }

  void _selectRole(SignInRole? r) {
    if (r == null) return;
    setState(() {
      _role = r;
      _error = null;
      _password.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    // Defaults: last used role, then sensible demo identities.
    _role ??= SignInRole.fromKey(data.auth.lastWorkspace);
    _employeeId ??= data.auth.currentEmployeeId ?? 'E1';
    _driverId ??= data.auth.currentDriverId ?? 'DR1';
    _employerId ??= data.primaryEmployer.id;

    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 960;
    final form = _LoginCard(child: _form(context, data, compact: !wide));

    return Scaffold(
      backgroundColor: wide ? AppColors.white : AppColors.background,
      body: SafeArea(
        child: wide
            ? Row(
                children: [
                  Expanded(flex: 5, child: _BrandPanel(data: data)),
                  Expanded(
                    flex: 6,
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpace.xxl),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: form,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.gutter,
                    AppSpace.xl,
                    AppSpace.gutter,
                    AppSpace.xl,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(
                      children: [
                        const _BrandMark(),
                        const SizedBox(height: AppSpace.xl),
                        AppCard(
                          shadow: true,
                          radius: AppRadius.xl,
                          padding: const EdgeInsets.all(AppSpace.lg),
                          child: form,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _form(BuildContext context, DataView data, {required bool compact}) {
    final t = Theme.of(context).textTheme;
    final role = _role!;
    final needsPassword = _needsPassword(data, role);
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Sign in',
                  style: compact ? t.headlineSmall : t.headlineMedium,
                ),
              ),
              const DemoBadge(),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Choose your role to open the right application.',
            style: t.bodyMedium!.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpace.xl),

          // ---- Role
          DropdownButtonFormField<SignInRole>(
            key: const Key('roleDropdown'),
            initialValue: role,
            isExpanded: true,
            itemHeight: null,
            decoration: const InputDecoration(labelText: 'Sign in as'),
            selectedItemBuilder: (context) => [
              for (final r in SignInRole.values)
                Row(
                  children: [
                    Icon(r.icon, size: 20, color: r.accent),
                    const SizedBox(width: AppSpace.sm),
                    Flexible(
                      child: Text(r.label, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
            ],
            items: [
              for (final r in SignInRole.values)
                DropdownMenuItem(
                  value: r,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        IconTile(icon: r.icon, color: r.accent, size: 36),
                        const SizedBox(width: AppSpace.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(r.label, style: t.titleSmall),
                              Text(
                                r.caption,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.bodySmall!.copyWith(
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            onChanged: _selectRole,
          ),
          const SizedBox(height: AppSpace.md),

          // ---- Identity for the role
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: KeyedSubtree(
              key: ValueKey(role),
              child: _identityField(context, data, role),
            ),
          ),

          // ---- Password (only where configured)
          if (needsPassword) ...[
            const SizedBox(height: AppSpace.md),
            TextField(
              key: const Key('passwordField'),
              controller: _password,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _busy ? null : _signIn(),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            Row(
              children: [
                const Icon(
                  Icons.key_outlined,
                  size: 16,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Demo password: $demoEmployeePassword',
                    style: AppText.muted(context),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _password.text = demoEmployeePassword;
                    _error = null;
                  }),
                  child: const Text('Use demo password'),
                ),
              ],
            ),
          ],

          if (_error != null) ...[
            const SizedBox(height: AppSpace.md),
            InlineBanner(
              tone: StatusTone.danger,
              title: 'Could not sign in',
              message: _error,
            ),
          ],
          const SizedBox(height: AppSpace.xl),
          FilledButton(
            key: const Key('signInButton'),
            style: FilledButton.styleFrom(
              backgroundColor: role.accent,
              minimumSize: const Size.fromHeight(56),
            ),
            onPressed: _busy ? null : _signIn,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : Text('Sign in as ${role.label}'),
          ),
          const SizedBox(height: AppSpace.lg),
          const Divider(),
          const SizedBox(height: AppSpace.sm),
          Row(
            children: [
              const Expanded(
                child: SimulatedNote(
                  'Demo sign-in · not real authentication',
                  icon: Icons.lock_open_outlined,
                ),
              ),
              TextButton.icon(
                onPressed: () => showDemoToolsSheet(context),
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Demo tools'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _identityField(BuildContext context, DataView data, SignInRole role) {
    switch (role) {
      case SignInRole.employee:
        final employees = data.employees.where((e) => e.isActive).toList()
          ..sort((a, b) => _num(a.id).compareTo(_num(b.id)));
        return LayoutBuilder(
          builder: (context, c) => DropdownMenu<String>(
            key: const Key('employeeDropdown'),
            width: c.maxWidth,
            menuHeight: 320,
            initialSelection: employees.any((e) => e.id == _employeeId)
                ? _employeeId
                : null,
            controller: _employeeSearch,
            enableFilter: true,
            requestFocusOnTap: true,
            label: const Text('Employee'),
            hintText: 'Search by name or ID',
            leadingIcon: const Icon(Icons.badge_outlined),
            helperText: 'E1–E4 are the core demo route passengers',
            dropdownMenuEntries: [
              for (final e in employees)
                DropdownMenuEntry(
                  value: e.id,
                  label: '${e.employeeCode} · ${e.name}',
                ),
            ],
            onSelected: (v) => setState(() {
              _employeeId = v;
              _error = null;
              _password.clear();
            }),
          ),
        );
      case SignInRole.driver:
        final drivers = data.drivers;
        return DropdownButtonFormField<String>(
          key: const Key('driverDropdown'),
          initialValue: drivers.any((d) => d.id == _driverId)
              ? _driverId
              : drivers.firstOrNull?.id,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Driver',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
          items: [
            for (final d in drivers)
              DropdownMenuItem(
                value: d.id,
                child: Text(
                  '${d.driverCode} · ${d.name}'
                  '${d.assignedVehicleId != null ? ' · Vehicle ${d.assignedVehicleId}' : ''}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) => setState(() {
            _driverId = v;
            _error = null;
          }),
        );
      case SignInRole.employer:
        return DropdownButtonFormField<String>(
          key: const Key('employerDropdown'),
          initialValue: _employerId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Company',
            prefixIcon: Icon(Icons.apartment_outlined),
          ),
          items: [
            for (final e in data.employers)
              DropdownMenuItem(
                value: e.id,
                child: Text(
                  '${e.code} · ${e.name}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) => setState(() {
            _employerId = v;
            _error = null;
          }),
        );
      case SignInRole.fleet:
        return TextFormField(
          key: const Key('operatorField'),
          initialValue: 'FM-01 · Fleet Operations (shared pool)',
          readOnly: true,
          decoration: const InputDecoration(
            labelText: 'Operator',
            prefixIcon: Icon(Icons.hub_outlined),
            suffixIcon: Icon(Icons.lock_outline_rounded, size: 18),
          ),
        );
    }
  }

  static int _num(String id) =>
      int.tryParse(id.replaceAll(RegExp(r'\D'), '')) ?? 0;
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.onDark = false});
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: onDark ? Colors.white : AppColors.midnightNavy,
            borderRadius: AppRadius.mdAll,
          ),
          child: Icon(
            Icons.route_rounded,
            color: onDark ? AppColors.midnightNavy : Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Executive Fleet Mobility',
                style: t.titleMedium!.copyWith(
                  color: onDark ? Colors.white : AppColors.textPrimary,
                ),
              ),
              Text(
                'Corporate transport platform',
                style: t.bodySmall!.copyWith(
                  color: onDark ? Colors.white70 : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Left panel on wide screens: brand, the four applications, live facts.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel({required this.data});
  final DataView data;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final todayTrips = data.trips
        .onDay(data.today)
        .where((x) => x.status != TripStatus.cancelled)
        .length;
    return Container(
      color: AppColors.midnightNavy,
      padding: const EdgeInsets.fromLTRB(56, 48, 56, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _BrandMark(onDark: true),
          const Spacer(),
          Text(
            'Corporate mobility,\nconnected end to end.',
            style: t.displaySmall!.copyWith(color: Colors.white, height: 1.2),
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            'Employees, drivers, employers and fleet operations work from one shared, live dataset.',
            style: t.bodyLarge!.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: AppSpace.xxl),
          for (final r in SignInRole.values)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: AppRadius.mdAll,
                    ),
                    child: Icon(r.icon, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.label,
                          style: t.titleSmall!.copyWith(color: Colors.white),
                        ),
                        Text(
                          r.caption,
                          style: t.bodySmall!.copyWith(color: Colors.white60),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const Spacer(),
          Wrap(
            spacing: AppSpace.lg,
            runSpacing: AppSpace.xs,
            children: [
              _Fact(
                '${data.employees.where((e) => e.isActive).length} employees',
              ),
              _Fact('${data.vehicles.length} vehicles'),
              _Fact('${data.drivers.length} drivers'),
              _Fact('$todayTrips trips today'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: Theme.of(
      context,
    ).textTheme.bodySmall!.copyWith(color: Colors.white70),
  );
}
