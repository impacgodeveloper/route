import 'package:flutter/material.dart';

import '../../domain/models/models.dart';
import '../theme/app_colors.dart';

enum StatusTone {
  neutral(Color(0xFF526579), Color(0xFFF0F3F8)),
  info(AppColors.info, AppColors.infoBg),
  success(AppColors.success, AppColors.successBg),
  warning(AppColors.warning, AppColors.warningBg),
  danger(AppColors.danger, AppColors.dangerBg),
  teal(AppColors.teal, AppColors.softTeal);

  const StatusTone(this.foreground, this.background);
  final Color foreground;
  final Color background;
}

/// Compact status pill. Text always accompanies colour (accessibility).
class StatusBadge extends StatelessWidget {
  const StatusBadge(
    this.label, {
    super.key,
    this.tone = StatusTone.neutral,
    this.icon,
    this.dense = false,
  });

  final String label;
  final StatusTone tone;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Status: $label',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 6 : 8,
          vertical: dense ? 2 : 4,
        ),
        decoration: BoxDecoration(
          color: tone.background,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: dense ? 12 : 14, color: tone.foreground),
              const SizedBox(width: 4),
            ] else ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: tone.foreground,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tone.foreground,
                  fontSize: dense ? 11 : 12,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Status → tone mappings shared by every workspace.
abstract final class Tones {
  static StatusTone trip(TripStatus s) => switch (s) {
    TripStatus.draft || TripStatus.planned => StatusTone.neutral,
    TripStatus.assigned ||
    TripStatus.driverAccepted ||
    TripStatus.ready => StatusTone.info,
    TripStatus.inProgress => StatusTone.teal,
    TripStatus.delayed || TripStatus.needsAttention => StatusTone.warning,
    TripStatus.completed => StatusTone.success,
    TripStatus.cancelled => StatusTone.danger,
  };

  static StatusTone booking(BookingStatus s) => switch (s) {
    BookingStatus.requested => StatusTone.info,
    BookingStatus.approved => StatusTone.teal,
    BookingStatus.assigned || BookingStatus.completed => StatusTone.success,
    BookingStatus.waitlisted => StatusTone.warning,
    BookingStatus.rejected || BookingStatus.cancelled => StatusTone.danger,
  };

  static StatusTone vehicle(VehicleStatus s) => switch (s) {
    VehicleStatus.available => StatusTone.success,
    VehicleStatus.assigned => StatusTone.info,
    VehicleStatus.onTrip => StatusTone.teal,
    VehicleStatus.maintenance => StatusTone.warning,
    VehicleStatus.unavailable => StatusTone.danger,
  };

  static StatusTone driver(DriverStatus s) => switch (s) {
    DriverStatus.available => StatusTone.success,
    DriverStatus.assigned => StatusTone.info,
    DriverStatus.onTrip => StatusTone.teal,
    DriverStatus.offDuty => StatusTone.neutral,
    DriverStatus.unavailable => StatusTone.danger,
  };

  static StatusTone incident(IncidentStatus s) => switch (s) {
    IncidentStatus.draft => StatusTone.neutral,
    IncidentStatus.submittedDemo => StatusTone.warning,
    IncidentStatus.acknowledgedDemo => StatusTone.info,
    IncidentStatus.resolvedDemo => StatusTone.success,
    IncidentStatus.failedDemo => StatusTone.danger,
  };

  static StatusTone severity(IncidentSeverity s) => switch (s) {
    IncidentSeverity.low => StatusTone.neutral,
    IncidentSeverity.medium => StatusTone.info,
    IncidentSeverity.high => StatusTone.warning,
    IncidentSeverity.critical => StatusTone.danger,
  };

  static StatusTone billing(BillingStatus s) => switch (s) {
    BillingStatus.draft => StatusTone.neutral,
    BillingStatus.generated => StatusTone.info,
    BillingStatus.reviewed => StatusTone.teal,
    BillingStatus.paidDemo => StatusTone.success,
    BillingStatus.disputed => StatusTone.danger,
  };

  static StatusTone stop(StopStatus s) => switch (s) {
    StopStatus.upcoming => StatusTone.neutral,
    StopStatus.arrived => StatusTone.info,
    StopStatus.completed => StatusTone.success,
    StopStatus.skipped => StatusTone.warning,
    StopStatus.issue => StatusTone.danger,
  };

  static StatusTone passenger(PassengerState s) => switch (s) {
    PassengerState.awaiting => StatusTone.neutral,
    PassengerState.boarded => StatusTone.teal,
    PassengerState.alighted => StatusTone.success,
    PassengerState.noShow => StatusTone.warning,
  };

  static StatusTone inspection(InspectionOutcome s) => switch (s) {
    InspectionOutcome.passed => StatusTone.success,
    InspectionOutcome.needsReview => StatusTone.warning,
    InspectionOutcome.failed => StatusTone.danger,
  };

  static StatusTone shift(ShiftStatus s) => switch (s) {
    ShiftStatus.scheduled => StatusTone.neutral,
    ShiftStatus.checkedIn => StatusTone.success,
    ShiftStatus.late => StatusTone.warning,
    ShiftStatus.regularizationPending => StatusTone.warning,
    ShiftStatus.completed => StatusTone.info,
  };

  static StatusTone ticket(TicketStatus s) => switch (s) {
    TicketStatus.open => StatusTone.warning,
    TicketStatus.inProgress => StatusTone.info,
    TicketStatus.resolved => StatusTone.success,
    TicketStatus.closed => StatusTone.neutral,
  };

  static StatusTone billable(BillableStatus s) => switch (s) {
    BillableStatus.notYetBillable => StatusTone.neutral,
    BillableStatus.missingDistance => StatusTone.danger,
    BillableStatus.billed => StatusTone.success,
    BillableStatus.excluded => StatusTone.neutral,
  };
}

class TripStatusBadge extends StatelessWidget {
  const TripStatusBadge(this.status, {super.key, this.dense = false});
  final TripStatus status;
  final bool dense;
  @override
  Widget build(BuildContext context) =>
      StatusBadge(status.label, tone: Tones.trip(status), dense: dense);
}
