import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import 'employee_common.dart';

enum _TripTab {
  upcoming('Upcoming'),
  completed('Completed'),
  cancelled('Cancelled');

  const _TripTab(this.label);
  final String label;
}

class EmployeeTripsScreen extends ConsumerStatefulWidget {
  const EmployeeTripsScreen({super.key});

  @override
  ConsumerState<EmployeeTripsScreen> createState() =>
      _EmployeeTripsScreenState();
}

class _EmployeeTripsScreenState extends ConsumerState<EmployeeTripsScreen> {
  _TripTab _tab = _TripTab.upcoming;
  String _query = '';
  String? _destination;
  int _searchKey = 0;

  bool _inTab(EmployeeTripView v, [_TripTab? tab]) => switch (tab ?? _tab) {
    _TripTab.upcoming => v.isActive || v.isUpcoming,
    _TripTab.completed => v.trip.status == TripStatus.completed && !v.isAbsent,
    _TripTab.cancelled => v.trip.status == TripStatus.cancelled || v.isAbsent,
  };

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final e = ref.watch(currentEmployeeProvider);
    if (e == null) return const LoadingState();
    final all = employeeTrips(data, e.id);
    final inTab = all.where(_inTab).toList();
    if (_tab != _TripTab.upcoming) {
      inTab.sort(
        (a, b) => b.trip.scheduledStart.compareTo(a.trip.scheduledStart),
      );
    }
    final q = _query.trim().toLowerCase();
    final filtered = inTab.where((v) {
      if (_destination != null &&
          v.trip.employeeIds.isNotEmpty &&
          v.dropLocation?.id != _destination) {
        return false;
      }
      if (q.isEmpty) return true;
      return v.trip.tripCode.toLowerCase().contains(q) ||
          (v.dropLocation?.name.toLowerCase().contains(q) ?? false) ||
          (v.pickupLocation?.name.toLowerCase().contains(q) ?? false) ||
          (v.dropLocation?.code.toLowerCase().contains(q) ?? false);
    }).toList();
    final destinations = {
      for (final v in all)
        if (v.dropLocation != null) v.dropLocation!.id: v.dropLocation!,
    };
    final filtersActive = q.isNotEmpty || _destination != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My trips'),
        actions: [
          IconButton(
            tooltip: 'Weekly schedule',
            onPressed: () => context.push('/employee/roster'),
            icon: const Icon(Icons.calendar_view_week_outlined),
          ),
          const SizedBox(width: AppSpace.xs),
        ],
      ),
      body: MobilePage(
        children: [
          SegmentedButton<_TripTab>(
            showSelectedIcon: false,
            segments: [
              for (final tab in _TripTab.values)
                ButtonSegment(
                  value: tab,
                  label: Text(
                    '${tab.label} ${all.where((v) => _inTab(v, tab)).length}',
                  ),
                ),
            ],
            selected: {_tab},
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
          const SizedBox(height: AppSpace.md),
          AppSearchField(
            key: ValueKey(_searchKey),
            hint: 'Search trip code, pickup or office',
            initial: _query,
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: AppSpace.xs),
          if (destinations.length > 1)
            FilterChipBar<String?>(
              options: [null, ...destinations.keys],
              selected: _destination,
              onSelected: (v) => setState(() => _destination = v),
              labelOf: (v) => v == null ? 'All offices' : destinations[v]!.code,
            ),
          const SizedBox(height: AppSpace.md),
          if (filtered.isEmpty)
            filtersActive
                ? EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'No trips match',
                    message:
                        'Nothing in ${_tab.label.toLowerCase()} matches your search or filter.',
                    actionLabel: 'Clear filters',
                    onAction: () => setState(() {
                      _query = '';
                      _destination = null;
                      _searchKey++;
                    }),
                  )
                : EmptyState(
                    icon: _tab == _TripTab.upcoming
                        ? Icons.event_available_outlined
                        : Icons.history_rounded,
                    title: switch (_tab) {
                      _TripTab.upcoming => 'No upcoming trips',
                      _TripTab.completed => 'No completed trips yet',
                      _TripTab.cancelled => 'No cancelled trips',
                    },
                    message: _tab == _TripTab.upcoming
                        ? 'When the Fleet Manager assigns you a trip it appears here with driver and vehicle details.'
                        : 'Your trip history is kept here.',
                    actionLabel: _tab == _TripTab.upcoming
                        ? 'Request transport'
                        : null,
                    onAction: _tab == _TripTab.upcoming
                        ? () => context.go('/employee/book')
                        : null,
                  )
          else
            for (final v in filtered)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.xs),
                child: EmployeeTripTile(view: v),
              ),
        ],
      ),
    );
  }
}
