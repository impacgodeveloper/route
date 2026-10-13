import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/widgets.dart';
import '../../../domain/models/models.dart';
import '../../../domain/rules/parameter_catalog.dart';
import '../widgets/fleet_common.dart';
import '../widgets/profile_editor.dart';
import '../widgets/run_views.dart';

class OptimizationPage extends ConsumerStatefulWidget {
  const OptimizationPage({super.key});

  @override
  ConsumerState<OptimizationPage> createState() => _OptimizationPageState();
}

class _OptimizationPageState extends ConsumerState<OptimizationPage> {
  OptimizationConfig? _config;
  late DateTime _date;
  final Set<String> _employees = {'E1', 'E2', 'E3', 'E4'};
  Set<String>? _vehicles;
  bool _guard = false;
  int _guardsAvailable = 1;
  String? _startParkingId;
  bool _readQuery = false;
  RouteVariant? _variant;
  String _search = '';
  bool _busy = false;
  final Set<String> _compare = {};
  List<String> _errors = const [];

  @override
  void initState() {
    super.initState();
    final data = ref.read(dataProvider);
    _date = data.today.add(const Duration(days: 1));
    _config = data.optimizationConfigs.firstOrNull;
  }

  /// Bookings this run was opened for ("Optimize selected" in dispatch).
  List<String> _bookingIds = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_readQuery) return;
    _readQuery = true;
    final q = GoRouterState.of(context).uri.queryParameters;
    final emps = (q['employees'] ?? '')
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (emps.isNotEmpty) {
      _employees
        ..clear()
        ..addAll(emps);
    }
    final d = DateTime.tryParse(q['date'] ?? '');
    if (d != null) _date = dateOnly(d);
    _bookingIds = (q['bookings'] ?? '')
        .split(',')
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<void> _run() async {
    final s = ref.read(servicesProvider).optimization;
    final cfg = _config!;
    setState(() {
      _busy = true;
      _errors = const [];
    });
    final input = s.buildInput(
      config: cfg,
      employeeIds: _employees.toList(),
      serviceDate: _date,
      vehicleIds: _vehicles?.toList(),
      guardRequired: _guard,
      variant: _variant,
      startParkingId: _startParkingId,
      guardsAvailable: _guard ? _guardsAvailable : 0,
    );
    final r = await s.runAndSave(input);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _errors = r.errors;
    });
    if (r.isOk) context.go('/fleet/optimization/run/${r.valueOrNull!.id}');
  }

  Future<void> _saveProfile() async {
    final r = await ref
        .read(servicesProvider)
        .optimization
        .saveConfig(_config!);
    if (mounted) await showResult(context, r);
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final t = Theme.of(context).textTheme;
    final cfg = _config;
    if (cfg == null) {
      return const EmptyState(
        icon: Icons.tune_outlined,
        title: 'No optimization profile',
        message: 'Reset demo data to restore the default profile.',
      );
    }
    final vehicles = _vehicles ?? data.vehicles.map((v) => v.id).toSet();
    final runs = data.optimizationRuns;
    final emps =
        data
            .employeesOf(cfg.employerId ?? data.primaryEmployer.id)
            .where((e) => e.isActive)
            .where(
              (e) =>
                  _search.isEmpty ||
                  e.employeeCode.toLowerCase() == _search.toLowerCase() ||
                  e.name.toLowerCase().contains(_search.toLowerCase()) ||
                  e.destinationId.toLowerCase() == _search.toLowerCase(),
            )
            .toList()
          ..sort((a, b) {
            final x =
                (_employees.contains(a.id) ? 0 : 1) -
                (_employees.contains(b.id) ? 0 : 1);
            return x != 0
                ? x
                : a.id.length != b.id.length
                ? a.id.length - b.id.length
                : a.id.compareTo(b.id);
          });

    final inputs = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelCard(
          title: 'Inputs',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DateField(
                label: 'Service date',
                value: _date,
                firstDate: data.today,
                lastDate: data.today.add(const Duration(days: 30)),
                onChanged: (d) => setState(() => _date = d),
              ),
              const SizedBox(height: AppSpace.md),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Employees (${_employees.length})',
                      style: t.titleSmall,
                    ),
                  ),
                  ActionChip(
                    label: const Text('E1–E4'),
                    onPressed: () => setState(() {
                      _employees
                        ..clear()
                        ..addAll(['E1', 'E2', 'E3', 'E4']);
                    }),
                  ),
                  const SizedBox(width: 6),
                  ActionChip(
                    label: const Text('Clear'),
                    onPressed: () => setState(_employees.clear),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.xs),
              AppSearchField(
                hint: 'Search ID, name or office',
                onChanged: (v) => setState(() => _search = v.trim()),
              ),
              const SizedBox(height: AppSpace.xs),
              Container(
                height: 220,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: AppRadius.mdAll,
                ),
                child: ListView.builder(
                  itemCount: emps.length,
                  itemBuilder: (c, i) {
                    final e = emps[i];
                    return CheckboxListTile(
                      dense: true,
                      value: _employees.contains(e.id),
                      onChanged: (v) => setState(
                        () => v == true
                            ? _employees.add(e.id)
                            : _employees.remove(e.id),
                      ),
                      title: Text('${e.employeeCode} · ${e.name}'),
                      subtitle: Text(
                        '${e.pickupLocationId} → ${e.destinationId} · by ${Fmt.minutesOfDay(e.requiredArrivalMinutes)}',
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Text('Candidate vehicles', style: t.titleSmall),
              for (final v in data.vehicles)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: vehicles.contains(v.id),
                  onChanged: (sel) => setState(() {
                    final next = {...vehicles};
                    sel == true ? next.add(v.id) : next.remove(v.id);
                    _vehicles = next;
                  }),
                  title: Text(vehicleShort(v)),
                  subtitle: Text(
                    '${data.capacityOf(v)} employee seats · ${v.status.label}',
                  ),
                ),
              const SizedBox(height: AppSpace.sm),
              DropdownButtonFormField<RouteVariant?>(
                isExpanded: true,
                initialValue: _variant,
                decoration: const InputDecoration(labelText: 'Route variant'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Auto — compare ring road vs internal roads'),
                  ),
                  for (final v in RouteVariant.values)
                    DropdownMenuItem(value: v, child: Text(v.label)),
                ],
                onChanged: (v) => setState(() => _variant = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _guard,
                onChanged: (v) => setState(() => _guard = v),
                title: const Text('Security guard required'),
                subtitle: const Text(
                  'Reserves one seat per vehicle before employee capacity.',
                ),
              ),
              if (_guard) ...[
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: _guardsAvailable,
                  decoration: const InputDecoration(
                    labelText: 'Guards available (pool)',
                    helperText:
                        'Vehicles without an assigned guard draw from this pool; a plan needing more is infeasible.',
                  ),
                  items: [
                    for (var i = 0; i <= 5; i++)
                      DropdownMenuItem(value: i, child: Text('$i')),
                  ],
                  onChanged: (v) => setState(() => _guardsAvailable = v ?? 0),
                ),
                const SizedBox(height: AppSpace.sm),
              ],
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _startParkingId,
                decoration: const InputDecoration(
                  labelText: 'Start parking / depot',
                  helperText: 'Deadhead distance is measured from here.',
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Each vehicle\'s home parking (default)'),
                  ),
                  for (final p in data.parkingLocations)
                    DropdownMenuItem(
                      value: p.id,
                      child: Text(p.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _startParkingId = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        PanelCard(
          title: 'Profile: ${cfg.name}',
          subtitle:
              '${ParameterCatalog.liveCount} of ${ParameterCatalog.count} catalog parameters active in the demo engine',
          trailing: TextButton(
            onPressed: () => context.go('/fleet/optimization/parameters'),
            child: const Text('Parameters'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProfileEditor(
                config: cfg,
                compactWeights: true,
                onChanged: (c) => setState(() => _config = c),
              ),
              const SizedBox(height: AppSpace.sm),
              OutlinedButton.icon(
                onPressed: _saveProfile,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save profile'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        if (_errors.isNotEmpty) ...[
          InlineBanner(
            tone: StatusTone.danger,
            title: 'Run failed',
            messages: _errors,
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        FilledButton.icon(
          onPressed: _busy || _employees.isEmpty || vehicles.isEmpty
              ? null
              : _run,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.play_arrow_rounded),
          label: const Text('Run local demo optimizer'),
        ),
        const SizedBox(height: AppSpace.xs),
        const SimulatedNote(DemoLabels.optimizer, icon: Icons.memory_outlined),
      ],
    );

    final compareRuns = runs.where((r) => _compare.contains(r.id)).toList();
    final results = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PreferenceSummaryPanel(employeeIds: _employees.toList()),
        const SizedBox(height: AppSpace.md),
        PanelCard(
          title: 'Saved runs',
          subtitle: 'Select two to compare',
          child: runs.isEmpty
              ? const EmptyState(
                  icon: Icons.auto_graph_outlined,
                  title: 'No runs yet',
                  message: 'Run the optimizer to create a proposal.',
                  compact: true,
                )
              : Column(
                  children: [
                    for (final r in runs)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Checkbox(
                          value: _compare.contains(r.id),
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              if (_compare.length >= 2) {
                                _compare.remove(_compare.first);
                              }
                              _compare.add(r.id);
                            } else {
                              _compare.remove(r.id);
                            }
                          }),
                        ),
                        title: Text(
                          '${r.reference} · ${r.isFeasible ? 'Score ${r.score.toStringAsFixed(1)}' : 'No feasible assignment'}',
                        ),
                        subtitle: Text(
                          '${Fmt.dateShort(r.serviceDate)} · ${r.employeeIds.join(', ')}${r.appliedAt != null ? ' · applied' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: StatusBadge(
                          r.isRejected
                              ? 'Rejected'
                              : r.appliedAt != null
                              ? 'Applied'
                              : r.status.label,
                          tone: r.isRejected
                              ? StatusTone.neutral
                              : r.isFeasible
                              ? StatusTone.success
                              : StatusTone.danger,
                          dense: true,
                        ),
                        onTap: () =>
                            context.go('/fleet/optimization/run/${r.id}'),
                      ),
                  ],
                ),
        ),
        if (compareRuns.length == 2) ...[
          const SizedBox(height: AppSpace.md),
          PanelCard(
            title: 'Comparison',
            child: RunComparison(a: compareRuns[0], b: compareRuns[1]),
          ),
        ],
        if (runs.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          PanelCard(
            title: 'Latest: ${runs.first.reference}',
            trailing: TextButton(
              onPressed: () =>
                  context.go('/fleet/optimization/run/${runs.first.id}'),
              child: const Text('Open'),
            ),
            child: RunSummary(run: runs.first),
          ),
        ],
      ],
    );

    return AdminPage(
      title: 'Route optimization',
      subtitle:
          'Configure weights and constraints, run the local demo optimizer, review the explainable proposal and apply it only after confirmation.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => context.go('/fleet/optimization/parameters'),
          icon: const Icon(Icons.list_alt_outlined),
          label: Text('Parameter catalog (${ParameterCatalog.count})'),
        ),
      ],
      children: [
        const InlineBanner(
          tone: StatusTone.info,
          title: DemoLabels.optimizer,
          message:
              'Not nearest-path routing: employees are clustered to vehicles by evaluating feasible assignments, then stops are ordered and scored. Live traffic, OR-Tools and predictive models are future integrations.',
        ),
        const SizedBox(height: AppSpace.md),
        if (_bookingIds.isNotEmpty) ...[
          InlineBanner(
            tone: StatusTone.teal,
            title:
                'Prefilled from ${_bookingIds.length} selected request${_bookingIds.length == 1 ? '' : 's'}',
            message:
                '${_bookingIds.join(', ')} · ${_employees.join(', ')} on ${Fmt.weekday(_date)}. Review the proposal and apply it only after confirmation.',
          ),
          const SizedBox(height: AppSpace.md),
        ],
        ResponsiveSplit(
          left: inputs,
          right: results,
          leftFlex: 2,
          rightFlex: 3,
          breakpoint: 1080,
        ),
      ],
    );
  }
}

/// Fleet Manager view of saved employee travel preferences (levels only —
/// no other personal data). Proximity is shown but not scored.
class PreferenceSummaryPanel extends ConsumerWidget {
  const PreferenceSummaryPanel({super.key, required this.employeeIds});
  final List<String> employeeIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final t = Theme.of(context).textTheme;
    final emps = employeeIds.map(data.employee).whereType<Employee>().toList();
    final withPrefs = emps
        .where((e) => e.travelPreferences.values.any((v) => v > 0))
        .toList();
    return PanelCard(
      title: 'Employee preferences',
      subtitle:
          '${withPrefs.length} of ${emps.length} selected employees have saved preferences · soft, never override hard constraints',
      child: withPrefs.isEmpty
          ? Text(
              'No saved travel preferences for the selected employees.',
              style: AppText.muted(context),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final e in withPrefs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${e.employeeCode} · ${e.name}',
                          style: t.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final k in TravelPreferenceKeys.all)
                              if ((e.travelPreferences[k] ?? 0) > 0)
                                StatusBadge(
                                  '${TravelPreferenceKeys.label(k)}: ${TravelPreferenceKeys.levels[(e.travelPreferences[k]!).clamp(0, 3)]}${TravelPreferenceKeys.active.contains(k) ? '' : ' (not scored)'}',
                                  tone: TravelPreferenceKeys.active.contains(k)
                                      ? StatusTone.info
                                      : StatusTone.neutral,
                                  dense: true,
                                ),
                          ],
                        ),
                      ],
                    ),
                  ),
                Text(
                  'Weighted by "Employee preferences" in the profile. Pickup proximity has no effect while pickups are at registered source points.',
                  style: AppText.muted(context),
                ),
              ],
            ),
    );
  }
}
