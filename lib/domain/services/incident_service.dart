import '../../core/persistence/local_database.dart';
import '../../core/demo/demo_labels.dart';
import '../../core/utils/result.dart';
import '../models/models.dart';
import '../rules/trip_state_machine.dart';
import 'resource_sync.dart';
import 'service_context.dart';

class IncidentDraft {
  const IncidentDraft({
    required this.type,
    required this.description,
    required this.severity,
    required this.reporter,
    this.tripId,
    this.vehicleId,
    this.driverId,
    this.locationId,
    this.demoLocationLabel,
    this.replacementRequested = false,
    this.delayMinutes,
  });

  final IncidentType type;
  final String description;
  final IncidentSeverity severity;
  final Actor reporter;
  final String? tripId;
  final String? vehicleId;
  final String? driverId;
  final String? locationId;
  final String? demoLocationLabel;
  final bool replacementRequested;
  final int? delayMinutes;
}

/// Local incident, breakdown and SOS records. Nothing is sent to a real
/// control room or emergency service.
class IncidentService {
  IncidentService(this.ctx);
  final ServiceContext ctx;

  /// When true, submissions fail as if offline (demo of failure handling).
  static const simulateOfflineKey = 'demo.simulateOffline';
  bool get simulateOffline => ctx.db.appState(simulateOfflineKey) == '1';

  Future<Result<Incident>> report(IncidentDraft d) async {
    final errors = <String>[
      if (d.description.trim().length < 10)
        'Describe what happened (at least 10 characters).',
      if (d.type == IncidentType.delay &&
          (d.delayMinutes == null || d.delayMinutes! <= 0))
        'Enter the expected delay in minutes.',
      if (d.tripId != null && ctx.db.trips[d.tripId] == null) 'Trip not found.',
    ];
    if (errors.isNotEmpty) return Err(errors);
    if (simulateOffline) {
      return Err.single(
        'Submission failed — device appears offline (simulated). Your entries are kept; retry when ready.',
      );
    }
    return ctx.run((tx) {
      final db = ctx.db;
      final id = tx.newId(db.incidents, 'IC-');
      final trip = db.trips[d.tripId];
      final vehicleId = d.vehicleId ?? trip?.assignedVehicleId;
      final driverId = d.driverId ?? trip?.assignedDriverId;
      final inc = Incident(
        id: id,
        reference: id,
        type: d.type,
        tripId: d.tripId,
        driverId: driverId,
        vehicleId: vehicleId,
        locationId: d.locationId,
        description: d.type == IncidentType.delay
            ? '${d.description.trim()} (expected delay ${d.delayMinutes} min)'
            : d.description.trim(),
        severity: d.severity,
        status: IncidentStatus.submittedDemo,
        reportedByRole: d.reporter.role,
        reportedById: d.reporter.id,
        demoLocationLabel: d.demoLocationLabel,
        replacementRequested: d.replacementRequested,
        isSos: d.type == IncidentType.emergency,
        createdAt: ctx.now,
        updatedAt: ctx.now,
      );
      tx.insert(db.incidents, inc);
      if (inc.isSos) escalateSos(tx, inc, trip);

      // Operational side effects.
      if (trip != null) {
        switch (d.type) {
          case IncidentType.delay:
            // Always record the reason; change status only when allowed
            // (a not-yet-started trip keeps its status but shows the delay).
            final canDelay =
                trip.actualStart != null &&
                TripStateMachine.canTransition(trip.status, TripStatus.delayed);
            tx.put(
              db.trips,
              trip.copyWith(
                status: canDelay ? TripStatus.delayed : trip.status,
                delayReason: () =>
                    '${d.description.trim()} (expected ~${d.delayMinutes} min)',
                updatedAt: ctx.now,
              ),
            );
            ctx.notifyEmployees(
              tx,
              trip.employeeIds,
              '${trip.tripCode} running late',
              'Expected delay ~${d.delayMinutes} min: ${d.description.trim()}',
              NotificationCategory.delay,
              entityType: 'trip',
              entityId: trip.id,
            );
          case IncidentType.routeDeviation:
            ctx.notifyEmployees(
              tx,
              trip.employeeIds,
              'Route change on ${trip.tripCode}',
              d.description.trim(),
              NotificationCategory.routeChange,
              entityType: 'trip',
              entityId: trip.id,
            );
          case IncidentType.breakdown:
          case IncidentType.vehicleDefect:
            if (TripStateMachine.canTransition(
              trip.status,
              TripStatus.needsAttention,
            )) {
              tx.put(
                db.trips,
                trip.copyWith(
                  status: TripStatus.needsAttention,
                  delayReason: () => 'Breakdown: ${d.description.trim()}',
                  updatedAt: ctx.now,
                ),
              );
            }
            ctx.notifyEmployees(
              tx,
              trip.employeeIds,
              '${trip.tripCode} affected by a vehicle issue',
              'Your driver reported a breakdown. A replacement is being arranged by the Fleet Manager.',
              NotificationCategory.delay,
              entityType: 'trip',
              entityId: trip.id,
            );
          case IncidentType.emergency:
          case IncidentType.safety:
            if (TripStateMachine.canTransition(
              trip.status,
              TripStatus.needsAttention,
            )) {
              tx.put(
                db.trips,
                trip.copyWith(
                  status: TripStatus.needsAttention,
                  delayReason: () => '${d.type.label} reported',
                  updatedAt: ctx.now,
                ),
              );
            }
            if (d.reporter.role == UserRole.driver) {
              ctx.notifyEmployees(
                tx,
                trip.employeeIds,
                'Safety alert on ${trip.tripCode} (demo)',
                'Your driver raised a ${d.type.label.toLowerCase()} alert. ${DemoLabels.sosDemo}',
                NotificationCategory.incident,
                entityType: 'trip',
                entityId: trip.id,
              );
            } else if (trip.assignedDriverId != null) {
              ctx.notify(
                tx,
                role: UserRole.driver,
                recipientId: trip.assignedDriverId,
                title: 'Passenger raised SOS (demo)',
                body:
                    'A passenger on ${trip.tripCode} raised an SOS. Stop safely and check. ${DemoLabels.sosDemo}',
                category: NotificationCategory.incident,
                entityType: 'incident',
                entityId: id,
              );
            }
          case IncidentType.passengerIssue:
          case IncidentType.other:
            break;
        }
      }
      if (d.type == IncidentType.breakdown ||
          d.type == IncidentType.vehicleDefect) {
        final v = db.vehicles[vehicleId];
        if (v != null) {
          tx.put(
            db.vehicles,
            v.copyWith(
              status: VehicleStatus.maintenance,
              notes: 'Breakdown $id',
            ),
          );
        }
        ResourceSync.driver(tx, db, driverId);
      }
      ctx.notify(
        tx,
        role: UserRole.fleetManager,
        title:
            '${inc.isSos ? 'SOS' : d.type.label} reported${trip != null ? ' · ${trip.tripCode}' : ''}',
        body:
            '${d.reporter.label}: ${d.description.trim()}${d.replacementRequested ? ' · Replacement requested' : ''}',
        category: NotificationCategory.incident,
        entityType: 'incident',
        entityId: id,
      );
      if (trip != null &&
          (d.type == IncidentType.breakdown ||
              d.type == IncidentType.emergency ||
              d.type == IncidentType.delay)) {
        ctx.notify(
          tx,
          role: UserRole.employerAdmin,
          title: '${d.type.label} on ${trip.tripCode}',
          body: d.description.trim(),
          category: NotificationCategory.incident,
          entityType: 'trip',
          entityId: trip.id,
        );
      }
      ctx.audit(
        tx,
        d.reporter,
        'incident.report',
        'incident',
        id,
        '${d.type.label} (${d.severity.label}) reported: ${d.description.trim()}',
      );
      return inc;
    }, info: inc0Info(d.type));
  }

  static String inc0Info(IncidentType t) => t == IncidentType.emergency
      ? 'SOS recorded locally. ${DemoLabels.sosDemo}'
      : 'Report recorded locally. ${DemoLabels.incidentDemo}';

  /// SOS escalation chain (fleet policy). In-app recipients are alerted
  /// immediately; police/phone calls are recorded as "integration
  /// required — not contacted" (no telephony/emergency integration exists).
  void escalateSos(Txn tx, Incident inc, Trip? trip) {
    final db = ctx.db;
    final chain = ctx.view.policy.sosRecipients;
    final who = inc.reportedByRole == UserRole.employee
        ? '${db.employees[inc.reportedById]?.employeeCode ?? inc.reportedById} (employee)'
        : '${db.drivers[inc.reportedById]?.driverCode ?? inc.reportedById} (driver)';
    final where = trip == null ? '' : ' on ${trip.tripCode}';
    void dispatch(
      SosRecipient r,
      SosDispatchStatus s,
      String channel,
      String note,
    ) {
      tx.insert(
        db.sosDispatches,
        SosDispatch(
          id: tx.newId(db.sosDispatches, 'SD-'),
          incidentId: inc.id,
          recipient: r,
          status: s,
          channel: channel,
          createdAt: ctx.now,
          note: note,
        ),
      );
    }

    for (final r in chain) {
      switch (r) {
        case SosRecipient.fleetManager:
          dispatch(
            r,
            SosDispatchStatus.alertedInApp,
            'In-app alert',
            'Shown in Fleet Manager notifications and incident queue.',
          );
        case SosRecipient.companyAdmin:
          final employerId =
              trip?.employerId ?? db.employees[inc.reportedById]?.employerId;
          ctx.notify(
            tx,
            role: UserRole.employerAdmin,
            title: 'SOS raised by $who (demo)',
            body: 'Emergency alert$where. ${DemoLabels.sosDemo}',
            category: NotificationCategory.incident,
            entityType: 'incident',
            entityId: inc.id,
          );
          dispatch(
            r,
            SosDispatchStatus.alertedInApp,
            'In-app alert',
            'Company administrator${employerId == null ? '' : ' of $employerId'} alerted.',
          );
        case SosRecipient.supportTeam:
          final tid = tx.newId(db.tickets, 'TK-');
          tx.insert(
            db.tickets,
            SupportTicket(
              id: tid,
              reference: tid,
              createdByRole: inc.reportedByRole,
              createdById: inc.reportedById ?? 'unknown',
              category: TicketCategory.safety,
              subject: 'SOS escalation ${inc.reference}',
              description: inc.description,
              relatedTripId: trip?.id,
              status: TicketStatus.open,
              createdAt: ctx.now,
              updatedAt: ctx.now,
            ),
          );
          dispatch(
            r,
            SosDispatchStatus.alertedInApp,
            'Support queue',
            'Priority safety ticket $tid opened.',
          );
        case SosRecipient.driver:
          if (inc.reportedByRole == UserRole.employee &&
              trip?.assignedDriverId != null) {
            dispatch(
              r,
              SosDispatchStatus.alertedInApp,
              'In-app alert',
              'Assigned driver ${trip!.assignedDriverId} alerted.',
            );
          } else {
            dispatch(
              r,
              SosDispatchStatus.disabled,
              '—',
              inc.reportedByRole == UserRole.driver
                  ? 'Raised by the driver.'
                  : 'No assigned driver.',
            );
          }
        case SosRecipient.police:
          dispatch(
            r,
            SosDispatchStatus.integrationRequired,
            'Emergency services (112)',
            'No emergency-services integration in this prototype — call 112 directly.',
          );
        case SosRecipient.emergencyContact:
          dispatch(
            r,
            SosDispatchStatus.integrationRequired,
            'Phone call / SMS',
            'No telephony integration in this prototype.',
          );
      }
    }
  }

  Future<Result<SosDispatch>> acknowledgeSos(
    String dispatchId, {
    Actor actor = Actor.fleetManager,
  }) => ctx.run((tx) {
    final d = ctx.db.sosDispatches[dispatchId];
    if (d == null) throw ValidationFailure(['Escalation not found.']);
    if (d.status != SosDispatchStatus.alertedInApp) {
      throw ValidationFailure(['Only in-app alerts can be acknowledged.']);
    }
    final next = d.copyWith(
      status: SosDispatchStatus.acknowledged,
      acknowledgedAt: () => ctx.now,
      acknowledgedBy: () => actor.label,
    );
    tx.put(ctx.db.sosDispatches, next);
    final inc = ctx.db.incidents[d.incidentId];
    if (inc != null && inc.status == IncidentStatus.submittedDemo) {
      tx.put(
        ctx.db.incidents,
        inc.copyWith(
          status: IncidentStatus.acknowledgedDemo,
          updatedAt: ctx.now,
        ),
      );
      if (inc.reportedById != null) {
        ctx.notify(
          tx,
          role: inc.reportedByRole,
          recipientId: inc.reportedById,
          title: 'SOS acknowledged by ${d.recipient.label} (demo)',
          body:
              'Your alert ${inc.reference} was acknowledged in the app. ${DemoLabels.sosDemo}',
          category: NotificationCategory.incident,
          entityType: 'incident',
          entityId: inc.id,
        );
      }
    }
    ctx.audit(
      tx,
      actor,
      'sos.acknowledge',
      'incident',
      d.incidentId,
      '${d.recipient.label} acknowledged SOS ${inc?.reference ?? d.incidentId}.',
      simulated: true,
    );
    return next;
  }, info: 'SOS acknowledged');

  Future<Result<Incident>> raiseSos({
    required Actor actor,
    String? tripId,
    String note = '',
  }) {
    final trip = ctx.db.trips[tripId];
    return report(
      IncidentDraft(
        type: IncidentType.emergency,
        description: note.trim().length >= 10
            ? note.trim()
            : 'SOS raised from the ${actor.role.label} app${note.trim().isNotEmpty ? ': ${note.trim()}' : ''}.',
        severity: IncidentSeverity.critical,
        reporter: actor,
        tripId: trip?.id,
        demoLocationLabel: trip == null
            ? 'Unknown (simulated)'
            : 'Along ${trip.tripCode} route (simulated)',
      ),
    );
  }

  Future<Result<Incident>> setStatus(
    String id,
    IncidentStatus status, {
    String? notes,
    bool restoreVehicle = false,
    Actor actor = Actor.fleetManager,
  }) {
    if (status == IncidentStatus.resolvedDemo &&
        (notes?.trim().length ?? 0) < 5) {
      return Future.value(
        Err.single('Add resolution notes (at least 5 characters).'),
      );
    }
    return ctx.run((tx) {
      final db = ctx.db;
      final inc = db.incidents[id];
      if (inc == null) throw ValidationFailure(['Incident not found.']);
      if (inc.status == IncidentStatus.resolvedDemo) {
        throw ValidationFailure(['Incident already resolved.']);
      }
      final next = inc.copyWith(
        status: status,
        resolutionNotes: notes == null ? null : () => notes.trim(),
        updatedAt: ctx.now,
      );
      tx.put(db.incidents, next);
      if (restoreVehicle && status == IncidentStatus.resolvedDemo) {
        final v = db.vehicles[inc.vehicleId];
        if (v != null && v.status == VehicleStatus.maintenance) {
          tx.put(
            db.vehicles,
            v.copyWith(status: VehicleStatus.available, notes: ''),
          );
          ResourceSync.vehicle(tx, db, v.id);
        }
      }
      if (inc.reportedByRole == UserRole.driver ||
          inc.reportedByRole == UserRole.employee) {
        ctx.notify(
          tx,
          role: inc.reportedByRole,
          recipientId: inc.reportedById,
          title: '${inc.reference} ${status.label.toLowerCase()}',
          body: notes ?? 'Updated by Fleet Manager (demo).',
          category: NotificationCategory.incident,
          entityType: 'incident',
          entityId: inc.id,
        );
      }
      ctx.audit(
        tx,
        actor,
        'incident.status',
        'incident',
        inc.id,
        '${inc.reference} → ${status.label}${notes != null ? ': ${notes.trim()}' : ''}.',
      );
      return next;
    }, info: 'Incident ${status.label.toLowerCase()}');
  }

  Future<Result<Incident>> requestReplacement(String incidentId, Actor actor) =>
      ctx.run((tx) {
        final inc = ctx.db.incidents[incidentId];
        if (inc == null) throw ValidationFailure(['Incident not found.']);
        final next = inc.copyWith(
          replacementRequested: true,
          updatedAt: ctx.now,
        );
        tx.put(ctx.db.incidents, next);
        ctx.notify(
          tx,
          role: UserRole.fleetManager,
          title: 'Replacement requested · ${inc.reference}',
          body: 'Vehicle ${inc.vehicleId ?? '—'} needs a replacement.',
          category: NotificationCategory.incident,
          entityType: 'incident',
          entityId: inc.id,
        );
        ctx.audit(
          tx,
          actor,
          'incident.replacement',
          'incident',
          inc.id,
          'Replacement vehicle requested.',
        );
        return next;
      }, info: 'Replacement requested');
}
