import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import '../../domain/rules/trip_state_machine.dart';

/// Simulated "vehicle moving" state. While true, detailed interactions are
/// locked so the driver is not encouraged to use the phone while driving.
final drivingModeProvider = StateProvider<bool>((ref) => false);

/// Whether the one-time "don't use the phone while driving" notice was seen.
final drivingWarningSeenProvider = StateProvider<bool>((ref) => false);

/// Duty state used by the stateful Home.
enum DutyState {
  beforeShift,
  alcoholTest,
  alcoholBlocked,
  needsInspection,
  inspectionFailed,
  readyForTrip,
  tripActive,
  allDone,
  shiftEnded,
}

/// Everything the driver screens need about "today", computed from records.
class DriverDay {
  DriverDay(this.data, this.driver, {this.alcoholBlockers = const []});

  final DataView data;
  final Driver driver;

  /// Alcohol-policy reasons blocking the next step (empty = OK or disabled).
  final List<String> alcoholBlockers;

  bool get alcoholEnabled => data.policy.alcoholMonitoringEnabled;

  /// Uncleared failed test today (Fleet Manager review required).
  AlcoholTest? get alcoholFail {
    final b = data.blockingAlcoholTest(driver.id);
    return b?.result == AlcoholResult.fail ? b : null;
  }

  /// Latest test today is a failure the Fleet Manager has cleared.
  bool get alcoholBlockLifted {
    final latest = data
        .alcoholTestsOf(driver.id)
        .where((a) => sameDay(a.testedAt, data.now))
        .firstOrNull;
    return latest != null &&
        latest.result == AlcoholResult.fail &&
        latest.clearedAt != null;
  }

  Shift? get shift => data.todayShift(driver.id);
  bool get checkedIn => shift?.actualCheckIn != null;
  bool get shiftEnded => shift?.status == ShiftStatus.completed;

  List<Trip> get allTrips => data.trips.forDriver(driver.id);
  List<Trip> get todayTrips =>
      allTrips.where((t) => sameDay(t.serviceDate, data.today)).toList();

  Trip? get activeTrip => allTrips
      .where((t) => t.status.isActive && t.actualStart != null)
      .firstOrNull;

  /// Not-yet-started trips today that still occupy a window.
  List<Trip> get pendingToday => todayTrips
      .where(
        (t) =>
            t.actualStart == null && TripStateMachine.occupiesWindow(t.status),
      )
      .toList();
  Trip? get nextTrip => pendingToday.firstOrNull;

  /// Vehicle the driver should inspect: next/active trip's vehicle, else default.
  Vehicle? get vehicle => data.vehicle(
    activeTrip?.assignedVehicleId ??
        nextTrip?.assignedVehicleId ??
        driver.assignedVehicleId,
  );

  Inspection? get todayInspection {
    final v = vehicle;
    if (v == null) return null;
    return data.todayInspection(v.id);
  }

  DutyState get state {
    if (shiftEnded) return DutyState.shiftEnded;
    if (!checkedIn) return DutyState.beforeShift;
    if (activeTrip != null) return DutyState.tripActive;
    if (alcoholFail != null) return DutyState.alcoholBlocked;
    if (alcoholBlockers.isNotEmpty) return DutyState.alcoholTest;
    final insp = todayInspection;
    if (vehicle != null && nextTrip != null) {
      if (insp == null) return DutyState.needsInspection;
      if (insp.overallStatus == InspectionOutcome.failed) {
        return DutyState.inspectionFailed;
      }
    }
    if (nextTrip != null) return DutyState.readyForTrip;
    if (vehicle != null && insp == null && todayTrips.isEmpty) {
      return DutyState.needsInspection;
    }
    return DutyState.allDone;
  }
}

final driverDayProvider = Provider<DriverDay?>((ref) {
  final data = ref.watch(dataProvider);
  final id = data.auth.currentDriverId;
  final d = data.driver(id);
  if (d == null) return null;
  final base = DriverDay(data, d);
  var blockers = const <String>[];
  if (base.checkedIn && !base.shiftEnded && base.alcoholEnabled) {
    final everyTrip =
        data.policy.alcoholCheckPoint == AlcoholCheckPoint.everyTrip;
    if (!everyTrip || base.nextTrip != null) {
      blockers = ref
          .read(servicesProvider)
          .alcohol
          .blockers(d.id, trip: base.nextTrip);
    }
  }
  return DriverDay(data, d, alcoholBlockers: blockers);
});

/// Large 56px primary button used for the single main action on a screen.
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
    this.busy = false,
    this.outlined = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;
  final bool busy;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: Colors.white,
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 22),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          );
    final size = const Size(double.infinity, 58);
    if (outlined) {
      return OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: size,
          foregroundColor: color ?? AppColors.textPrimary,
        ),
        onPressed: busy ? null : onPressed,
        child: child,
      );
    }
    return FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: size,
        backgroundColor: color ?? AppColors.primary,
      ),
      onPressed: busy ? null : onPressed,
      child: child,
    );
  }
}

/// App bar for full-screen driver pages.
PreferredSizeWidget driverAppBar(
  BuildContext context,
  String title, {
  List<Widget> actions = const [],
  String fallback = '/driver/home',
}) {
  return AppBar(
    title: Text(title),
    leading: IconButton(
      tooltip: 'Back',
      icon: const Icon(Icons.arrow_back_rounded),
      onPressed: () => context.canPop() ? context.pop() : context.go(fallback),
    ),
    actions: actions,
  );
}

/// Section label in caps used across driver screens.
class Overline extends StatelessWidget {
  const Overline(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpace.xs, top: AppSpace.xxs),
    child: Text(text.toUpperCase(), style: AppText.overline(context)),
  );
}

/// Compact trip card used in Home/Trips lists.
class DriverTripCard extends ConsumerWidget {
  const DriverTripCard({
    super.key,
    required this.trip,
    this.onTap,
    this.showInstructions = false,
  });
  final Trip trip;
  final VoidCallback? onTap;
  final bool showInstructions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final t = Theme.of(context).textTheme;
    final stops = data.trips.stopsOf(trip);
    final v = data.vehicle(trip.assignedVehicleId);
    final first = data.location(trip.originLocationId);
    final last = data.location(trip.destinationLocationId);
    final deadline = MetricsService(data).deadlineOf(trip);
    return AppCard(
      onTap: onTap,
      semanticLabel: 'Trip ${trip.tripCode}, ${trip.status.label}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(trip.tripCode, style: t.titleMedium),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TripStatusBadge(trip.status, dense: true),
                ),
              ),
              const SizedBox(width: AppSpace.xs),
              Text(
                Fmt.time(trip.actualStart ?? trip.scheduledStart),
                style: t.titleMedium!.copyWith(fontFeatures: AppText.tabular),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            Fmt.dayLabel(trip.serviceDate, data.now),
            style: t.bodySmall!.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            '${first?.name ?? '—'}  →  ${last?.name ?? '—'}',
            style: t.bodyMedium!.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.md,
            runSpacing: 6,
            children: [
              _Meta(icon: Icons.place_outlined, text: '${stops.length} stops'),
              _Meta(
                icon: Icons.groups_outlined,
                text: '${trip.employeeIds.length} passengers',
              ),
              _Meta(
                icon: Icons.flag_outlined,
                text: 'Arrive by ${Fmt.time(deadline)}',
              ),
              _Meta(
                icon: Icons.directions_car_outlined,
                text: v == null ? 'No vehicle' : 'Vehicle ${v.vehicleCode}',
              ),
            ],
          ),
          if (trip.status == TripStatus.cancelled &&
              trip.cancellationReason != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              'Cancelled: ${trip.cancellationReason}',
              style: t.bodySmall!.copyWith(color: AppColors.danger),
            ),
          ],
          if (trip.status == TripStatus.needsAttention &&
              trip.delayReason != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              trip.delayReason!,
              style: t.bodySmall!.copyWith(color: AppColors.warning),
            ),
          ],
          if (showInstructions && trip.instructions.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              trip.instructions,
              style: t.bodySmall!.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: AppColors.textMuted),
      const SizedBox(width: 4),
      Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.bodySmall!.copyWith(color: AppColors.textSecondary),
      ),
    ],
  );
}

/// Locks detailed controls while the (simulated) vehicle is moving.
class DrivingLock extends ConsumerWidget {
  const DrivingLock({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moving = ref.watch(drivingModeProvider);
    if (!moving) return child;
    return Stack(
      children: [
        IgnorePointer(
          child: Opacity(opacity: 0.25, child: ExcludeSemantics(child: child)),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: AppCard(
                shadow: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.pan_tool_outlined,
                      size: 36,
                      color: AppColors.warning,
                    ),
                    const SizedBox(height: AppSpace.sm),
                    Text(
                      'Stop safely before interacting',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      'Detailed controls are locked while the vehicle is moving (simulated). Only Arrived and SOS stay available.',
                      textAlign: TextAlign.center,
                      style: AppText.secondary(context),
                    ),
                    const SizedBox(height: AppSpace.md),
                    BigButton(
                      label: 'I have stopped the vehicle',
                      icon: Icons.local_parking_rounded,
                      outlined: true,
                      onPressed: () =>
                          ref.read(drivingModeProvider.notifier).state = false,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Small helper to label a stop.
String stopTitle(DataView data, RouteStop s) =>
    data.location(s.locationId)?.name ?? s.locationId;
