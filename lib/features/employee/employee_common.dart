import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';

/// The signed-in demo employee (null when none / deactivated).
final currentEmployeeProvider = Provider<Employee?>((ref) {
  final id = ref.watch(currentEmployeeIdProvider);
  return ref.watch(dataProvider).employee(id);
});

/// Everything an employee screen needs about one of their trips.
class EmployeeTripView {
  EmployeeTripView(this.data, this.trip, this.employeeId);

  final DataView data;
  final Trip trip;
  final String employeeId;

  RouteStop? get pickup => data.trips.pickupStopFor(trip, employeeId);
  RouteStop? get drop => data.trips.dropStopFor(trip, employeeId);
  Location? get pickupLocation =>
      data.location(pickup?.locationId ?? trip.originLocationId);
  Location? get dropLocation =>
      data.location(drop?.locationId ?? trip.destinationLocationId);
  Driver? get driver => data.driver(trip.assignedDriverId);
  Vehicle? get vehicle => data.vehicle(trip.assignedVehicleId);
  PassengerState get state => data.trips.passengerState(trip, employeeId);
  DateTime get pickupTime => pickup?.plannedArrival ?? trip.scheduledStart;
  DateTime? get dropTime => drop?.plannedArrival ?? trip.scheduledArrival;

  /// The employee reported "not travelling"; their seat was released.
  bool get isAbsent =>
      trip.absentEmployeeIds.contains(employeeId) &&
      !trip.employeeIds.contains(employeeId);
  bool get isActive =>
      !isAbsent && trip.status.isActive && trip.actualStart != null;
  bool get isUpcoming =>
      !isAbsent &&
      (trip.status.isUpcoming ||
          (trip.status == TripStatus.needsAttention &&
              trip.actualStart == null));

  /// "I'm not travelling" is allowed until the trip starts.
  bool get canReportAbsence =>
      !isAbsent && trip.actualStart == null && !trip.status.isTerminal;
}

List<EmployeeTripView> employeeTrips(DataView data, String employeeId) => [
  for (final t in data.trips.all().where(
    (t) =>
        t.employeeIds.contains(employeeId) ||
        t.absentEmployeeIds.contains(employeeId),
  ))
    EmployeeTripView(data, t, employeeId),
];

/// Next relevant trip: active first, then the earliest upcoming one.
EmployeeTripView? nextTrip(DataView data, String employeeId) {
  final all = employeeTrips(data, employeeId);
  final active = all.where((v) => v.isActive);
  if (active.isNotEmpty) return active.first;
  final upcoming =
      all
          .where(
            (v) =>
                v.isUpcoming &&
                !dateOnly(v.trip.serviceDate).isBefore(data.today),
          )
          .toList()
        ..sort(
          (a, b) => a.trip.scheduledStart.compareTo(b.trip.scheduledStart),
        );
  return upcoming.firstOrNull;
}

String passengerStateLabel(PassengerState s) => switch (s) {
  PassengerState.awaiting => 'Awaiting pickup',
  PassengerState.boarded => 'On board',
  PassengerState.alighted => 'Dropped off',
  PassengerState.noShow => 'Marked no-show',
};

IconData vehicleIcon(Vehicle? v) => switch (v?.type) {
  VehicleType.van || VehicleType.minibus => Icons.airport_shuttle_outlined,
  _ => Icons.directions_car_outlined,
};

/// Opens the record a notification refers to.
void openEmployeeEntity(BuildContext context, String? type, String? id) {
  if (id == null) return;
  switch (type) {
    case 'trip':
      context.push('/employee/trip/$id');
    case 'booking':
      context.push('/employee/booking/$id');
    case 'traffic':
      context.go('/employee/trips');
    case 'incident':
      context.push('/employee/safety');
    default:
      break;
  }
}

/// Compact trip row used in lists.
class EmployeeTripTile extends StatelessWidget {
  const EmployeeTripTile({
    super.key,
    required this.view,
    this.showDate = false,
  });
  final EmployeeTripView view;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final trip = view.trip;
    final now = view.data.now;
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      onTap: () => context.push('/employee/trip/${trip.id}'),
      semanticLabel:
          'Trip ${trip.tripCode}, ${trip.status.label}, ${Fmt.dayLabel(trip.serviceDate, now)} pickup ${Fmt.time(view.pickupTime)}',
      child: Row(
        children: [
          Container(
            width: 56,
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: AppRadius.mdAll,
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              children: [
                Text(
                  Fmt.dateShort(trip.serviceDate).split(' ').last.toUpperCase(),
                  style: t.labelSmall!.copyWith(color: AppColors.textMuted),
                ),
                Text(
                  '${trip.serviceDate.day}',
                  style: t.titleLarge!.copyWith(fontFeatures: AppText.tabular),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${Fmt.time(view.pickupTime)} · ${view.dropLocation?.name ?? trip.destinationLocationId}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleSmall!.copyWith(
                          fontFeatures: AppText.tabular,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${trip.tripCode} · from ${view.pickupLocation?.name ?? '—'}${showDate ? ' · ${Fmt.dayLabel(trip.serviceDate, now)}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall!.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 6),
                view.isAbsent
                    ? const StatusBadge(
                        'You were absent · seat released',
                        tone: StatusTone.neutral,
                        dense: true,
                      )
                    : TripStatusBadge(trip.status, dense: true),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

/// Plain screen frame for full-screen employee routes.
class EmployeeSubPage extends StatelessWidget {
  const EmployeeSubPage({
    super.key,
    required this.title,
    required this.children,
    this.actions = const [],
    this.bottom,
  });
  final String title;
  final List<Widget> children;
  final List<Widget> actions;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) => EmployeeTextScale(
    child: Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: MobilePage(children: children),
        ),
      ),
      bottomNavigationBar: bottom,
    ),
  );
}

/// Applies the employee "Larger text" preference.
class EmployeeTextScale extends ConsumerWidget {
  const EmployeeTextScale({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(currentEmployeeIdProvider);
    if (id == null) return child;
    final large = ref.watch(dataProvider).settingsFor('employee:$id').largeText;
    if (!large) return child;
    final mq = MediaQuery.of(context);
    final base = mq.textScaler.scale(1);
    return MediaQuery(
      data: mq.copyWith(
        textScaler: TextScaler.linear((base * 1.2).clamp(1.0, 1.6)),
      ),
      child: child,
    );
  }
}

/// Delay/route/breakdown note to show passengers. Uses the trip's delay
/// reason, or the latest open operational incident on the trip (a delay
/// reported before departure is not stored on the trip itself).
String? tripAlertText(DataView data, Trip trip) {
  if (trip.status.isTerminal) return null;
  if (trip.delayReason != null) return trip.delayReason;
  const types = {
    IncidentType.delay,
    IncidentType.routeDeviation,
    IncidentType.breakdown,
  };
  final inc = data
      .incidentsOfTrip(trip.id)
      .where((i) => i.status.isOpen && types.contains(i.type))
      .firstOrNull;
  return inc?.description;
}

/// Effective office arrival deadline: earliest of required arrival, shift
/// start and the employer maximum (same rule the assignment service uses).
int effectiveDeadlineMinutes(Employee e, Employer? employer) {
  var m = e.arrivalDeadlineMinutes;
  if (employer != null && employer.maximumArrivalMinutes < m) {
    m = employer.maximumArrivalMinutes;
  }
  return m;
}

/// "7:03 – 7:17 AM (±7 min)" for a planned pickup.
String pickupWindowText(DateTime planned, int tolerance) {
  final (from, to) = ToleranceRules.window(planned, tolerance);
  return '${Fmt.time(from)} – ${Fmt.time(to)} (±$tolerance min)';
}

/// "9:15 AM – 6:15 PM" (+ "overnight").
String shiftText(Employee e) {
  if (e.shiftStartMinutes == null || e.shiftEndMinutes == null) {
    return e.shiftLabel.isEmpty ? 'Not set' : e.shiftLabel;
  }
  return '${Fmt.minutesOfDay(e.shiftStartMinutes!)} – ${Fmt.minutesOfDay(e.shiftEndMinutes!)}${e.overnightShift ? ' (overnight)' : ''}';
}

/// Latest open SOS raised by this employee, if any.
Incident? openSosOf(DataView data, String employeeId) => data.incidents
    .where(
      (i) =>
          i.isSos &&
          i.reportedByRole == UserRole.employee &&
          i.reportedById == employeeId &&
          i.status.isOpen,
    )
    .firstOrNull;

/// Whether [employeeId] may view [trip] (on it, or released their seat).
bool employeeCanSee(Trip trip, String employeeId) =>
    trip.employeeIds.contains(employeeId) ||
    trip.absentEmployeeIds.contains(employeeId);

/// "I'm not travelling": reason dialog → seat released via matching.
Future<void> reportAbsenceFlow(
  BuildContext context,
  WidgetRef ref,
  Trip trip,
  String employeeId,
) async {
  final input = await showReasonDialog(
    context,
    title: 'Not travelling on ${trip.tripCode}?',
    message:
        'Your seat will be released so a colleague can use it. The driver and Fleet Manager are notified. This cannot be undone here.',
    label: 'Reason (e.g. working from home)',
    confirmLabel: 'Release my seat',
    minLength: 3,
    destructive: true,
  );
  if (input == null || !context.mounted) return;
  final r = await ref
      .read(servicesProvider)
      .matching
      .reportAbsence(trip.id, employeeId, input.reason);
  if (context.mounted) await showResult(context, r);
}
