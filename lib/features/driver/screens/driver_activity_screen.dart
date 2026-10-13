import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/widgets.dart';
import '../../../domain/models/models.dart';
import '../../shared/notifications_view.dart';
import '../../shared/support_ticket_form.dart';
import '../driver_common.dart';
import '../driver_v2_widgets.dart';
import 'driver_alcohol_screen.dart';

enum _Tab { trips, attendance, inspections, alcohol, incidents, tickets }

/// History: trips, attendance, inspections, incidents, tickets; support.
class DriverActivityScreen extends ConsumerStatefulWidget {
  const DriverActivityScreen({super.key});

  @override
  ConsumerState<DriverActivityScreen> createState() =>
      _DriverActivityScreenState();
}

class _DriverActivityScreenState extends ConsumerState<DriverActivityScreen> {
  _Tab _tab = _Tab.trips;

  @override
  Widget build(BuildContext context) {
    final day = ref.watch(driverDayProvider);
    if (day == null) return const LoadingState();
    final data = day.data;
    final id = day.driver.id;
    final unread = data.unreadCount(UserRole.driver, id);
    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: MobilePage(
        children: [
          Row(
            children: [
              Expanded(
                child: AppCard(
                  onTap: () => context.push('/driver/notifications'),
                  padding: const EdgeInsets.all(AppSpace.md),
                  child: Row(
                    children: [
                      Badge(
                        isLabelVisible: unread > 0,
                        label: Text('$unread'),
                        child: const Icon(Icons.notifications_none_rounded),
                      ),
                      const SizedBox(width: AppSpace.sm),
                      const Expanded(
                        child: Text(
                          'Notifications',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: AppCard(
                  onTap: () => context.push('/driver/support'),
                  padding: const EdgeInsets.all(AppSpace.md),
                  child: const Row(
                    children: [
                      Icon(Icons.support_agent_rounded),
                      SizedBox(width: AppSpace.sm),
                      Expanded(
                        child: Text('Support', overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          FilterChipBar<_Tab>(
            options: _Tab.values,
            selected: _tab,
            onSelected: (v) => setState(() => _tab = v),
            labelOf: (v) => switch (v) {
              _Tab.trips => 'Trips',
              _Tab.attendance => 'Attendance',
              _Tab.inspections => 'Inspections',
              _Tab.incidents => 'Incidents',
              _Tab.tickets => 'Tickets',
              _Tab.alcohol => 'Alcohol tests',
            },
          ),
          const SizedBox(height: AppSpace.md),
          ..._content(context, data, id),
        ],
      ),
    );
  }

  List<Widget> _content(BuildContext context, DataView data, String id) {
    Widget list(List<Widget> rows, {required String empty}) => rows.isEmpty
        ? EmptyState(
            icon: Icons.history_rounded,
            title: 'Nothing yet',
            message: empty,
            compact: true,
          )
        : AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  rows[i],
                ],
              ],
            ),
          );
    switch (_tab) {
      case _Tab.trips:
        final trips = data.trips.forDriver(id).reversed.toList();
        return [
          list([
            for (final t in trips)
              ListTile(
                onTap: () => context.push('/driver/trip/${t.id}'),
                title: Text(
                  '${t.tripCode} · ${Fmt.dayLabel(t.serviceDate, data.now)}',
                ),
                subtitle: Text(
                  '${t.employeeIds.length} passengers · ${t.distanceKm != null ? Fmt.km(t.distanceKm) : 'distance —'}',
                ),
                trailing: TripStatusBadge(t.status, dense: true),
              ),
          ], empty: 'Your trips appear here.'),
        ];
      case _Tab.attendance:
        return [
          list([
            for (final s in data.shiftsOf(id))
              ListTile(
                onTap: () => context.push('/driver/attendance'),
                title: Text(Fmt.weekday(s.shiftDate)),
                subtitle: Text(
                  'In ${Fmt.time(s.actualCheckIn)} · Out ${Fmt.time(s.actualCheckOut)}',
                ),
                trailing: StatusBadge(
                  s.status.label,
                  tone: Tones.shift(s.status),
                  dense: true,
                ),
              ),
          ], empty: 'Shift records appear here.'),
        ];
      case _Tab.inspections:
        return [
          list([
            for (final i in data.inspectionsByDriver(id))
              ListTile(
                title: Text(
                  'Vehicle ${i.vehicleId} · ${Fmt.dateTime(i.submittedAt)}',
                ),
                subtitle: Text(
                  i.failures.isEmpty
                      ? 'All items passed'
                      : 'Failed: ${i.failures.map((x) => x.label).join(', ')}',
                ),
                trailing: StatusBadge(
                  i.overallStatus.label,
                  tone: Tones.inspection(i.overallStatus),
                  dense: true,
                ),
              ),
          ], empty: 'Inspections you submit appear here.'),
        ];
      case _Tab.incidents:
        return [
          list([
            for (final i in data.incidentsByDriver(id))
              ListTile(
                title: Text('${i.reference} · ${i.type.label}'),
                subtitle: Text(
                  '${Fmt.dateTime(i.createdAt)} · ${i.description}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: StatusBadge(
                  i.status.label,
                  tone: Tones.incident(i.status),
                  dense: true,
                ),
              ),
          ], empty: 'Reports and SOS records appear here.'),
          const SizedBox(height: AppSpace.sm),
          const SimulatedNote(DemoLabels.incidentDemo),
        ];
      case _Tab.alcohol:
        return [
          list([
            for (final a in data.alcoholTestsOf(id)) AlcoholTestTile(test: a),
          ], empty: 'Breathalyzer results appear here.'),
          const SizedBox(height: AppSpace.sm),
          const SimulatedNote('Simulated breathalyzer readings.'),
        ];
      case _Tab.tickets:
        return [
          list([
            for (final t in data.ticketsBy(UserRole.driver, id))
              ListTile(
                title: Text('${t.reference} · ${t.subject}'),
                subtitle: Text(
                  t.response ??
                      '${t.category.label} · ${Fmt.dateTime(t.createdAt)}',
                ),
                trailing: StatusBadge(
                  t.status.label,
                  tone: Tones.ticket(t.status),
                  dense: true,
                ),
              ),
          ], empty: 'Support tickets you raise appear here.'),
        ];
    }
  }
}

class DriverNotificationsScreen extends ConsumerWidget {
  const DriverNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(currentDriverIdProvider);
    return Scaffold(
      appBar: driverAppBar(context, 'Notifications'),
      body: NotificationsList(
        role: UserRole.driver,
        recipientId: id,
        onOpen: (n) {
          openDriverNotification(context, ref.read(dataProvider), n);
        },
      ),
    );
  }
}

class DriverSupportScreen extends ConsumerWidget {
  const DriverSupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(driverDayProvider);
    if (day == null) return const LoadingState();
    return Scaffold(
      appBar: driverAppBar(context, 'Support'),
      body: MobilePage(
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Need to talk to the control room?',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  'Request a call-back. In this prototype the request is recorded for the Fleet Manager console only.',
                  style: AppText.secondary(context),
                ),
                const SizedBox(height: AppSpace.md),
                BigButton(
                  label: 'Request call-back (simulated)',
                  icon: Icons.support_agent_rounded,
                  outlined: true,
                  onPressed: () async {
                    final r = await ref
                        .read(servicesProvider)
                        .support
                        .requestControlRoomContact(
                          Actor.driver(day.driver.id),
                          tripId: day.activeTrip?.id,
                        );
                    if (context.mounted) await showResult(context, r);
                  },
                ),
                const SizedBox(height: AppSpace.xs),
                const SimulatedNote(DemoLabels.controlRoomDemo),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          const Overline('Create a support ticket'),
          SupportTicketForm(
            actor: Actor.driver(day.driver.id),
            tripOptions: day.allTrips.reversed.take(10).toList(),
            initialTripId: day.activeTrip?.id,
            onSubmitted: (_) => context.canPop()
                ? context.pop()
                : context.go('/driver/activity'),
          ),
        ],
      ),
    );
  }
}
