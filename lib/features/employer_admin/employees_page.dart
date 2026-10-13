import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import 'employer_common.dart';

enum _StatusFilter { all, active, inactive }

enum _Sort {
  code('Employee ID'),
  name('Name'),
  arrival('Arrival time');

  const _Sort(this.label);
  final String label;
}

/// Searchable, filterable roster (E1–E100 and any imported employees).
class EmployeesPage extends ConsumerStatefulWidget {
  const EmployeesPage({super.key});

  @override
  ConsumerState<EmployeesPage> createState() => _EmployeesPageState();
}

class _EmployeesPageState extends ConsumerState<EmployeesPage> {
  static const _pageSize = 25;
  String _query = '';
  _StatusFilter _status = _StatusFilter.all;
  String? _destination;
  String? _pickup;
  int? _arrival;

  /// Company shift id, "_custom" (times not matching a company shift) or
  /// "_none" (no shift times).
  String? _shift;
  _Sort _sort = _Sort.code;
  int _visible = _pageSize;
  int _resets = 0;

  int _codeNum(String code) =>
      int.tryParse(code.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1 << 20;

  bool get _filtered =>
      _query.isNotEmpty ||
      _status != _StatusFilter.all ||
      _destination != null ||
      _pickup != null ||
      _arrival != null ||
      _shift != null;

  void _clear() => setState(() {
    _resets++;
    _query = '';
    _status = _StatusFilter.all;
    _destination = _pickup = null;
    _arrival = null;
    _shift = null;
    _visible = _pageSize;
  });

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final employer = data.primaryEmployer;
    String shiftKey(Employee e) {
      if (e.shiftStartMinutes == null || e.shiftEndMinutes == null) {
        return '_none';
      }
      return employer.shifts
              .where(
                (s) =>
                    s.startMinutes == e.shiftStartMinutes &&
                    s.endMinutes == e.shiftEndMinutes,
              )
              .firstOrNull
              ?.id ??
          '_custom';
    }

    String shiftText(Employee e) {
      if (e.shiftStartMinutes == null || e.shiftEndMinutes == null) return '—';
      final s = employer.shifts.where((x) => x.id == shiftKey(e)).firstOrNull;
      final times =
          '${Fmt.minutesOfDay(e.shiftStartMinutes!)}–${Fmt.minutesOfDay(e.shiftEndMinutes!)}${e.overnightShift ? ' (overnight)' : ''}';
      return s == null ? times : '${s.label.split(' · ').first} · $times';
    }

    final all = data.employeesOf(employer.id);
    final q = _query.trim().toLowerCase();
    final rows =
        all.where((e) {
          if (q.isNotEmpty &&
              !e.employeeCode.toLowerCase().contains(q) &&
              !e.name.toLowerCase().contains(q)) {
            return false;
          }
          if (_status == _StatusFilter.active && !e.isActive) return false;
          if (_status == _StatusFilter.inactive && e.isActive) return false;
          if (_destination != null && e.destinationId != _destination) {
            return false;
          }
          if (_pickup != null && e.pickupLocationId != _pickup) return false;
          if (_arrival != null && e.requiredArrivalMinutes != _arrival) {
            return false;
          }
          if (_shift != null && shiftKey(e) != _shift) return false;
          return true;
        }).toList()..sort(
          (a, b) => switch (_sort) {
            _Sort.code => _codeNum(
              a.employeeCode,
            ).compareTo(_codeNum(b.employeeCode)),
            _Sort.name => a.name.compareTo(b.name),
            _Sort.arrival =>
              a.requiredArrivalMinutes != b.requiredArrivalMinutes
                  ? a.requiredArrivalMinutes.compareTo(b.requiredArrivalMinutes)
                  : _codeNum(
                      a.employeeCode,
                    ).compareTo(_codeNum(b.employeeCode)),
          },
        );
    final shown = rows.take(_visible).toList();
    final arrivals = all.map((e) => e.requiredArrivalMinutes).toSet().toList()
      ..sort();
    final today = data.today;

    String? nextTrip(Employee e) {
      final next = data.trips
          .forEmployee(e.id)
          .where((t) => !t.serviceDate.isBefore(today) && !t.status.isTerminal)
          .firstOrNull;
      return next == null
          ? null
          : '${next.tripCode} · ${Fmt.dayLabel(next.serviceDate, data.now)}';
    }

    return AdminPage(
      title: 'Employees',
      subtitle:
          '${all.where((e) => e.isActive).length} active of ${all.length} · ${employer.name}',
      actions: [
        OutlinedButton.icon(
          onPressed: () => context.go(EmployerPaths.import),
          icon: const Icon(Icons.upload_file_outlined),
          label: const Text('Import CSV'),
        ),
        FilledButton.icon(
          onPressed: () => context.go('${EmployerPaths.employees}/new'),
          icon: const Icon(Icons.person_add_alt_outlined),
          label: const Text('Add employee'),
        ),
      ],
      children: [
        AppCard(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppSearchField(
                key: ValueKey('search-$_resets'),
                hint: 'Search by employee ID or name',
                initial: _query,
                onChanged: (v) => setState(() {
                  _query = v;
                  _visible = _pageSize;
                }),
              ),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _filterBox<_StatusFilter>(
                    label: 'Status',
                    value: _status,
                    items: {
                      for (final s in _StatusFilter.values)
                        s: s == _StatusFilter.all
                            ? 'All statuses'
                            : (s == _StatusFilter.active
                                  ? 'Active'
                                  : 'Inactive'),
                    },
                    onChanged: (v) =>
                        setState(() => _status = v ?? _StatusFilter.all),
                  ),
                  _filterBox<String?>(
                    label: 'Destination',
                    value: _destination,
                    items: {
                      null: 'All destinations',
                      for (final l in data.destinations) l.id: l.label,
                    },
                    onChanged: (v) => setState(() => _destination = v),
                  ),
                  _filterBox<String?>(
                    label: 'Pickup',
                    value: _pickup,
                    items: {
                      null: 'All pickups',
                      for (final l in data.pickupLocations) l.id: l.label,
                    },
                    onChanged: (v) => setState(() => _pickup = v),
                  ),
                  _filterBox<int?>(
                    label: 'Arrive by',
                    value: _arrival,
                    items: {
                      null: 'Any time',
                      for (final m in arrivals) m: Fmt.minutesOfDay(m),
                    },
                    onChanged: (v) => setState(() => _arrival = v),
                  ),
                  _filterBox<String?>(
                    label: 'Shift',
                    value: _shift,
                    items: {
                      null: 'All shifts',
                      for (final s in employer.shifts) s.id: s.label,
                      '_custom': 'Custom times',
                      '_none': 'No shift set',
                    },
                    onChanged: (v) => setState(() => _shift = v),
                  ),
                  _filterBox<_Sort>(
                    label: 'Sort by',
                    value: _sort,
                    items: {for (final s in _Sort.values) s: s.label},
                    onChanged: (v) => setState(() => _sort = v ?? _Sort.code),
                  ),
                  if (_filtered)
                    TextButton.icon(
                      onPressed: _clear,
                      icon: const Icon(Icons.filter_alt_off_outlined),
                      label: const Text('Clear filters'),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Text(
          '${rows.length} result${rows.length == 1 ? '' : 's'}',
          style: AppText.muted(context),
        ),
        const SizedBox(height: AppSpace.xs),
        AdaptiveTable<Employee>(
          rows: shown,
          onRowTap: (e) => context.go(EmployerPaths.employee(e.id)),
          empty: EmptyState(
            icon: Icons.person_search_outlined,
            title: 'No employees match',
            message: 'Try a different search or clear the filters.',
            actionLabel: _filtered ? 'Clear filters' : null,
            onAction: _filtered ? _clear : null,
          ),
          columns: [
            TableCol(
              'ID',
              (e) => Text(
                e.employeeCode,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            TableCol(
              'Name',
              (e) => Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              flex: 2,
            ),
            TableCol(
              'Pickup',
              (e) => Text(
                data.location(e.pickupLocationId)?.code ?? e.pickupLocationId,
              ),
            ),
            TableCol(
              'Destination',
              (e) =>
                  Text(data.location(e.destinationId)?.code ?? e.destinationId),
            ),
            TableCol(
              'Arrive by',
              (e) => Text(Fmt.minutesOfDay(e.requiredArrivalMinutes)),
            ),
            TableCol(
              'Shift',
              (e) => Text(
                shiftText(e),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              flex: 2,
            ),
            TableCol(
              'Next trip',
              (e) => Text(
                nextTrip(e) ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              flex: 2,
            ),
            TableCol(
              'Status',
              (e) => StatusBadge(
                e.status.label,
                tone: e.isActive ? StatusTone.success : StatusTone.neutral,
                dense: true,
              ),
            ),
          ],
          mobileCard: (e) => Row(
            children: [
              InitialsAvatar(
                initials: e.initials,
                size: 38,
                color: e.isActive
                    ? AppColors.employerAccent
                    : AppColors.textMuted,
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${e.employeeCode} · ${e.name}',
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${e.pickupLocationId} → ${e.destinationId} · by ${Fmt.minutesOfDay(e.requiredArrivalMinutes)}',
                      style: AppText.muted(context),
                    ),
                  ],
                ),
              ),
              StatusBadge(
                e.status.label,
                tone: e.isActive ? StatusTone.success : StatusTone.neutral,
                dense: true,
              ),
            ],
          ),
        ),
        if (rows.length > shown.length) ...[
          const SizedBox(height: AppSpace.md),
          Center(
            child: OutlinedButton(
              onPressed: () => setState(() => _visible += _pageSize),
              child: Text(
                'Show more (${rows.length - shown.length} remaining)',
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _filterBox<T>({
    required String label,
    required T value,
    required Map<T, String> items,
    required ValueChanged<T?> onChanged,
  }) {
    return SizedBox(
      width: 200,
      child: DropdownButtonFormField<T>(
        key: ValueKey('$label-$value-$_resets'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
        ),
        items: [
          for (final e in items.entries)
            DropdownMenuItem<T>(
              value: e.key,
              child: Text(e.value, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) => onChanged(v),
      ),
    );
  }
}
