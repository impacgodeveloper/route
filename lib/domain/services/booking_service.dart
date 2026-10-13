import '../../core/demo/clock.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/result.dart';
import '../models/models.dart';
import '../rules/capacity_rules.dart';
import '../rules/trip_state_machine.dart';
import 'assignment_service.dart';
import 'service_context.dart';

class BookingDraft {
  const BookingDraft({
    required this.employeeId,
    required this.pickupLocationId,
    required this.destinationId,
    required this.date,
    required this.arrivalMinutes,
    this.preference = TransportPreference.noPreference,
    this.notes = '',
  });

  final String employeeId;
  final String pickupLocationId;
  final String destinationId;
  final DateTime date;
  final int arrivalMinutes;
  final TransportPreference preference;
  final String notes;
}

/// Honest availability estimate shown before a request is submitted.
class AvailabilityCheck {
  const AvailabilityCheck({
    required this.available,
    required this.message,
    required this.freeVehicleCodes,
  });
  final bool available;
  final String message;
  final List<String> freeVehicleCodes;
}

/// Booking requests. A request is never an assignment until a Fleet
/// Manager approves/assigns it.
class BookingService {
  BookingService(this.ctx, this.assignments);
  final ServiceContext ctx;
  final AssignmentService assignments;

  List<String> validate(BookingDraft d) {
    final db = ctx.db;
    final errors = <String>[];
    final e = db.employees[d.employeeId];
    if (e == null) return ['Employee not found.'];
    if (!e.isActive) errors.add('Your profile is inactive.');
    final employer = db.employers[e.employerId]!;
    if (db.locations[d.pickupLocationId] == null) {
      errors.add('Choose a pickup location.');
    }
    if (db.locations[d.destinationId] == null) {
      errors.add('Choose a destination.');
    }
    if (d.pickupLocationId == d.destinationId) {
      errors.add('Pickup and destination must differ.');
    }
    final today = dateOnly(ctx.now);
    if (dateOnly(d.date).isBefore(today)) {
      errors.add('Date cannot be in the past.');
    }
    if (dateOnly(d.date).difference(today).inDays > 30) {
      errors.add('Bookings can be requested up to 30 days ahead.');
    }
    if (d.arrivalMinutes > employer.maximumArrivalMinutes) {
      errors.add(
        'Arrival ${Fmt.minutesOfDay(d.arrivalMinutes)} is after ${employer.code}\'s maximum permitted arrival ${Fmt.minutesOfDay(employer.maximumArrivalMinutes)}.',
      );
    }
    if (d.arrivalMinutes < 300) errors.add('Arrival must be after 5:00 AM.');
    if (sameDay(d.date, today) &&
        atMinutes(
          d.date,
          d.arrivalMinutes,
        ).isBefore(ctx.now.add(const Duration(minutes: 60)))) {
      errors.add(
        'Same-day requests need at least 60 minutes before the arrival time.',
      );
    }
    final dup = db.bookings.where(
      (b) =>
          b.employeeId == d.employeeId &&
          sameDay(b.requestedDate, d.date) &&
          (b.status.isOpen || b.status == BookingStatus.assigned),
    );
    if (dup.isNotEmpty) {
      errors.add(
        'You already have ${dup.first.reference} (${dup.first.status.label.toLowerCase()}) for that date.',
      );
    }
    final onTrip = db.trips.where(
      (t) =>
          t.employeeIds.contains(d.employeeId) &&
          sameDay(t.serviceDate, d.date) &&
          TripStateMachine.occupiesWindow(t.status),
    );
    if (onTrip.isNotEmpty) {
      errors.add(
        'You are already scheduled on ${onTrip.first.tripCode} that day.',
      );
    }
    return errors;
  }

  /// Simple, explainable estimate: vehicles not in maintenance with no
  /// overlapping trip between (arrival − 90 min) and arrival.
  AvailabilityCheck checkAvailability(BookingDraft d) {
    final arrival = atMinutes(d.date, d.arrivalMinutes);
    final start = arrival.subtract(const Duration(minutes: 90));
    final free = <String>[];
    for (final v in ctx.db.vehicles.values) {
      if (v.status == VehicleStatus.maintenance ||
          v.status == VehicleStatus.unavailable) {
        continue;
      }
      final busy = ctx.db.trips.any(
        (t) =>
            t.assignedVehicleId == v.id &&
            TripStateMachine.occupiesWindow(t.status) &&
            t.scheduledStart.isBefore(arrival) &&
            t.windowEnd.isAfter(start),
      );
      if (!busy && CapacityRules.passengerCapacity(v) > 0) {
        free.add(v.vehicleCode);
      }
    }
    return free.isEmpty
        ? const AvailabilityCheck(
            available: false,
            freeVehicleCodes: [],
            message:
                'No vehicle currently has a free window for that time. You can still submit; the request will be waitlisted for the Fleet Manager.',
          )
        : AvailabilityCheck(
            available: true,
            freeVehicleCodes: free,
            message:
                '${free.length} vehicle${free.length == 1 ? '' : 's'} (${free.map((c) => 'Vehicle $c').join(', ')}) currently free in that window. This is an estimate, not a confirmation.',
          );
  }

  Future<Result<Booking>> submit(BookingDraft d) {
    final errors = validate(d);
    if (errors.isNotEmpty) return Future.value(Err(errors));
    final avail = checkAvailability(d);
    return ctx.run(
      (tx) {
        final db = ctx.db;
        final e = db.employees[d.employeeId]!;
        final id = tx.newId(db.bookings, 'BK-');
        final b = Booking(
          id: id,
          reference: id,
          employeeId: e.id,
          requestedPickupLocationId: d.pickupLocationId,
          requestedDestinationId: d.destinationId,
          requestedDate: dateOnly(d.date),
          requestedArrivalMinutes: d.arrivalMinutes,
          status: avail.available
              ? BookingStatus.requested
              : BookingStatus.waitlisted,
          notes: d.notes.trim(),
          preference: d.preference,
          decisionReason: avail.available
              ? null
              : 'No vehicle had a free window at submission time.',
          createdAt: ctx.now,
          updatedAt: ctx.now,
        );
        tx.insert(db.bookings, b);
        final summary =
            '${e.employeeCode} ${e.name} · ${Fmt.dateShort(d.date)} arrive by ${Fmt.minutesOfDay(d.arrivalMinutes)} · ${d.pickupLocationId} → ${d.destinationId}';
        ctx.notify(
          tx,
          role: UserRole.fleetManager,
          title: 'New booking request $id',
          body: summary,
          category: NotificationCategory.bookingUpdate,
          entityType: 'booking',
          entityId: id,
        );
        ctx.notify(
          tx,
          role: UserRole.employerAdmin,
          title: 'Booking request $id',
          body: summary,
          category: NotificationCategory.bookingUpdate,
          entityType: 'booking',
          entityId: id,
        );
        ctx.notify(
          tx,
          role: UserRole.employee,
          recipientId: e.id,
          title: 'Request $id received',
          body: avail.available
              ? 'Awaiting Fleet Manager review. This is not yet a confirmed trip.'
              : 'Waitlisted — no vehicle was free at that time.',
          category: NotificationCategory.bookingUpdate,
          entityType: 'booking',
          entityId: id,
        );
        ctx.audit(
          tx,
          Actor.employee(e.id),
          'booking.create',
          'booking',
          id,
          'Requested transport: $summary.',
        );
        return b;
      },
      info: avail.available
          ? 'Request submitted — awaiting review'
          : 'Request waitlisted — no vehicle free yet',
    );
  }

  Future<Result<Booking>> _transition(
    String id,
    BookingStatus to,
    String? reason,
    Actor actor, {
    String? title,
  }) {
    return ctx.run((tx) {
      final b = ctx.db.bookings[id];
      if (b == null) throw ValidationFailure(['Booking not found.']);
      final allowed = switch (b.status) {
        BookingStatus.requested => {
          BookingStatus.approved,
          BookingStatus.rejected,
          BookingStatus.waitlisted,
          BookingStatus.cancelled,
        },
        BookingStatus.waitlisted => {
          BookingStatus.approved,
          BookingStatus.rejected,
          BookingStatus.cancelled,
        },
        BookingStatus.approved => {
          BookingStatus.cancelled,
          BookingStatus.waitlisted,
          BookingStatus.rejected,
        },
        BookingStatus.assigned => {BookingStatus.cancelled},
        _ => <BookingStatus>{},
      };
      if (!allowed.contains(to)) {
        throw ValidationFailure([
          '${b.reference} is ${b.status.label.toLowerCase()} and cannot become ${to.label.toLowerCase()}.',
        ]);
      }
      if (to == BookingStatus.rejected && (reason?.trim().length ?? 0) < 5) {
        throw ValidationFailure(['Give a rejection reason.']);
      }
      if (b.status == BookingStatus.assigned &&
          to == BookingStatus.cancelled &&
          b.tripId != null) {
        // Remove the employee from the (not yet started) trip.
        final t = ctx.db.trips[b.tripId];
        if (t != null && t.actualStart != null) {
          throw ValidationFailure([
            'Trip already started; contact support to change it.',
          ]);
        }
      }
      final next = b.copyWith(
        status: to,
        decisionReason: reason == null ? null : () => reason.trim(),
        updatedAt: ctx.now,
      );
      tx.put(ctx.db.bookings, next);
      ctx.notify(
        tx,
        role: UserRole.employee,
        recipientId: b.employeeId,
        title: title ?? 'Booking ${b.reference} ${to.label.toLowerCase()}',
        body: reason ?? 'Status updated by ${actor.label}.',
        category: NotificationCategory.bookingUpdate,
        entityType: 'booking',
        entityId: b.id,
      );
      if (actor.role == UserRole.employee) {
        ctx.notify(
          tx,
          role: UserRole.fleetManager,
          title: 'Booking ${b.reference} ${to.label.toLowerCase()} by employee',
          body: reason ?? '',
          category: NotificationCategory.bookingUpdate,
          entityType: 'booking',
          entityId: b.id,
        );
      }
      ctx.audit(
        tx,
        actor,
        'booking.${to.name}',
        'booking',
        b.id,
        '${b.reference} → ${to.label}${reason != null ? ': $reason' : ''}.',
      );
      return next;
    }, info: 'Booking ${to.label.toLowerCase()}');
  }

  Future<Result<Booking>> approve(
    String id, {
    Actor actor = Actor.fleetManager,
  }) => _transition(
    id,
    BookingStatus.approved,
    'Approved — a trip assignment will follow.',
    actor,
  );
  Future<Result<Booking>> reject(
    String id,
    String reason, {
    Actor actor = Actor.fleetManager,
  }) => _transition(id, BookingStatus.rejected, reason, actor);
  Future<Result<Booking>> waitlist(
    String id,
    String reason, {
    Actor actor = Actor.fleetManager,
  }) => _transition(id, BookingStatus.waitlisted, reason, actor);
  Future<Result<Booking>> cancelByEmployee(String id, String employeeId) {
    final b = ctx.db.bookings[id];
    if (b == null || b.employeeId != employeeId) {
      return Future.value(Err.single('Booking not found.'));
    }
    if (b.status == BookingStatus.assigned) {
      return Future.value(
        Err.single(
          'This request is already assigned to ${b.tripId}. Raise a support ticket to change an assigned trip.',
        ),
      );
    }
    return _transition(
      id,
      BookingStatus.cancelled,
      'Cancelled by employee.',
      Actor.employee(employeeId),
    );
  }

  /// Adds the booking's employee to an existing, not-yet-started trip.
  Future<Result<Trip>> assignToTrip(
    String bookingId,
    String tripId, {
    Actor actor = Actor.fleetManager,
  }) {
    final b = ctx.db.bookings[bookingId];
    final t = ctx.db.trips[tripId];
    if (b == null || t == null) {
      return Future.value(Err.single('Booking or trip not found.'));
    }
    if (!b.status.isOpen) {
      return Future.value(
        Err.single('${b.reference} is ${b.status.label.toLowerCase()}.'),
      );
    }
    if (!sameDay(t.serviceDate, b.requestedDate)) {
      return Future.value(
        Err.single('${t.tripCode} runs on a different date.'),
      );
    }
    if (t.actualStart != null) {
      return Future.value(Err.single('${t.tripCode} has already started.'));
    }
    return assignments.commit(
      AssignmentRequest(
        tripId: t.id,
        employerId: t.employerId,
        serviceDate: t.serviceDate,
        employeeIds: [...t.employeeIds, b.employeeId],
        driverId: t.assignedDriverId,
        vehicleId: t.assignedVehicleId,
        guardRequired: t.guardRequired,
        instructions: t.instructions,
        bookingIds: [b.id],
      ),
      actor: actor,
    );
  }

  /// Creates a new trip for one or more open bookings on the same date.
  Future<Result<Trip>> createTripForBookings(
    List<String> bookingIds, {
    String? driverId,
    String? vehicleId,
    Actor actor = Actor.fleetManager,
  }) {
    final bookings = bookingIds
        .map((id) => ctx.db.bookings[id])
        .whereType<Booking>()
        .toList();
    if (bookings.isEmpty) {
      return Future.value(Err.single('Select at least one booking.'));
    }
    if (bookings.any((b) => !b.status.isOpen)) {
      return Future.value(Err.single('Only open requests can be assigned.'));
    }
    final date = bookings.first.requestedDate;
    if (bookings.any((b) => !sameDay(b.requestedDate, date))) {
      return Future.value(
        Err.single('All selected requests must be for the same date.'),
      );
    }
    final employer = ctx.db.employees[bookings.first.employeeId]!.employerId;
    return assignments.commit(
      AssignmentRequest(
        employerId: employer,
        serviceDate: date,
        employeeIds: bookings.map((b) => b.employeeId).toList(),
        driverId: driverId,
        vehicleId: vehicleId,
        bookingIds: bookingIds,
      ),
      actor: actor,
    );
  }
}
