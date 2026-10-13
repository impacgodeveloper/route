import '../../core/persistence/local_database.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/result.dart';
import '../models/models.dart';
import 'service_context.dart';

/// Transparent result of the billing formula.
class BillingCalculation {
  const BillingCalculation({
    required this.distanceKm,
    required this.ratePerKm,
    required this.additionalCharges,
    required this.adjustment,
  });

  final double distanceKm;
  final double ratePerKm;
  final double additionalCharges;
  final double adjustment;

  double get distanceCharge => distanceKm * ratePerKm;
  double get total => double.parse(
    (distanceCharge + additionalCharges + adjustment).toStringAsFixed(2),
  );

  String get explanation =>
      '${distanceKm.toStringAsFixed(1)} km × ${Fmt.inr(ratePerKm)}/km = ${Fmt.inr(distanceCharge)}'
      '${additionalCharges != 0 ? ' + ${Fmt.inr(additionalCharges)} additional' : ''}'
      '${adjustment != 0 ? ' ${adjustment < 0 ? '−' : '+'} ${Fmt.inr(adjustment.abs())} adjustment' : ''}'
      ' = ${Fmt.inr(total)}';
}

/// Distance-based billing: `distanceKm × ratePerKm + additionalCharges + adjustment`.
/// Generated exactly once per completed trip with a valid, non-negative distance.
/// No payment processing — "Paid (demo)" is a label only.
class BillingService {
  BillingService(this.ctx);
  final ServiceContext ctx;

  static BillingCalculation calculate({
    required double distanceKm,
    required double ratePerKm,
    double additionalCharges = 0,
    double adjustment = 0,
  }) => BillingCalculation(
    distanceKm: distanceKm,
    ratePerKm: ratePerKm,
    additionalCharges: additionalCharges,
    adjustment: adjustment,
  );

  /// Why a trip cannot be billed automatically, or null if it can.
  String? blockReason(Trip t) {
    if (t.status == TripStatus.cancelled) {
      return 'Cancelled trips are never billed.';
    }
    if (t.status != TripStatus.completed) return 'Trip is not completed yet.';
    if (ctx.db.billing.where((b) => b.tripId == t.id).isNotEmpty) {
      return 'Billing already generated.';
    }
    if (t.distanceKm == null) {
      return 'Distance missing — enter the trip distance to bill.';
    }
    if (t.distanceKm! < 0) {
      return 'Distance is negative — correct it before billing.';
    }
    return null;
  }

  /// Generates billing inside an existing transaction. Returns the record,
  /// or null when blocked (the trip's billableStatus is updated accordingly).
  BillingRecord? generateInTx(
    Txn tx,
    String tripId, {
    double? additionalCharges,
    double adjustment = 0,
    Actor actor = Actor.system,
  }) {
    final db = ctx.db;
    final t = db.trips[tripId];
    if (t == null) return null;
    if (db.billing.where((b) => b.tripId == t.id).isNotEmpty) {
      return null; // exactly once
    }
    if (t.status != TripStatus.completed) return null;
    if (t.distanceKm == null || t.distanceKm! < 0) {
      tx.put(
        db.trips,
        t.copyWith(billableStatus: BillableStatus.missingDistance),
      );
      ctx.notify(
        tx,
        role: UserRole.employerAdmin,
        title: 'Billing blocked: ${t.tripCode}',
        body:
            'Completed trip has no valid distance. Enter the distance to generate billing.',
        category: NotificationCategory.billing,
        entityType: 'trip',
        entityId: t.id,
      );
      ctx.notify(
        tx,
        role: UserRole.fleetManager,
        title: 'Billing blocked: ${t.tripCode}',
        body: 'Distance missing on completed trip.',
        category: NotificationCategory.billing,
        entityType: 'trip',
        entityId: t.id,
      );
      ctx.audit(
        tx,
        actor,
        'billing.generate',
        'trip',
        t.id,
        'Automatic billing blocked for ${t.tripCode}: missing or invalid distance.',
        outcome: AuditOutcome.rejected,
        related: {'company': t.employerId},
      );
      return null;
    }
    final employer = db.employers[t.employerId]!;
    final calc = calculate(
      distanceKm: t.distanceKm!,
      ratePerKm: employer.defaultDistanceRate,
      additionalCharges: additionalCharges ?? employer.additionalChargePerTrip,
      adjustment: adjustment,
    );
    final id = tx.newId(db.billing, 'BL-');
    final rec = BillingRecord(
      id: id,
      employerId: employer.id,
      tripId: t.id,
      tripCode: t.tripCode,
      completedAt: t.actualArrival ?? ctx.now,
      billableDistanceKm: calc.distanceKm,
      ratePerKm: calc.ratePerKm,
      additionalCharges: calc.additionalCharges,
      adjustment: calc.adjustment,
      totalAmount: calc.total,
      status: BillingStatus.generated,
      calculationNotes: calc.explanation,
      createdAt: ctx.now,
    );
    tx.insert(db.billing, rec);
    tx.put(db.trips, t.copyWith(billableStatus: BillableStatus.billed));
    ctx.notify(
      tx,
      role: UserRole.employerAdmin,
      title: 'Billing generated: ${t.tripCode}',
      body: '${calc.explanation}.',
      category: NotificationCategory.billing,
      entityType: 'billing',
      entityId: id,
    );
    ctx.audit(
      tx,
      actor,
      'billing.generate',
      'billing',
      id,
      'Billing for ${t.tripCode}: ${calc.explanation}.',
    );
    return rec;
  }

  Future<Result<BillingRecord>> generate(
    String tripId, {
    Actor actor = Actor.employerAdmin,
  }) {
    final t = ctx.db.trips[tripId];
    if (t == null) return Future.value(Err.single('Trip not found.'));
    final block = blockReason(t);
    if (block != null) return Future.value(Err.single(block));
    return ctx.run((tx) {
      final r = generateInTx(tx, tripId, actor: actor);
      if (r == null) {
        throw ValidationFailure(['Billing could not be generated.']);
      }
      return r;
    }, info: 'Billing generated');
  }

  /// Records a corrected distance for a completed trip and bills it once.
  Future<Result<BillingRecord>> recordDistanceAndBill(
    String tripId,
    double distanceKm,
    String note, {
    Actor actor = Actor.employerAdmin,
  }) {
    if (distanceKm < 0) {
      return Future.value(Err.single('Distance cannot be negative.'));
    }
    if (note.trim().length < 5) {
      return Future.value(
        Err.single(
          'Add a note explaining the distance source (at least 5 characters).',
        ),
      );
    }
    return ctx.run((tx) {
      final db = ctx.db;
      final t = db.trips[tripId];
      if (t == null) throw ValidationFailure(['Trip not found.']);
      if (t.status != TripStatus.completed) {
        throw ValidationFailure(['Only completed trips can be billed.']);
      }
      if (db.billing.where((b) => b.tripId == t.id).isNotEmpty) {
        throw ValidationFailure([
          'Billing already generated for ${t.tripCode}.',
        ]);
      }
      tx.put(
        db.trips,
        t.copyWith(
          distanceKm: () => distanceKm,
          completionNotes: () =>
              '${t.completionNotes ?? ''} Distance recorded: $note'.trim(),
        ),
      );
      ctx.audit(
        tx,
        actor,
        'trip.distance',
        'trip',
        t.id,
        'Recorded distance ${distanceKm.toStringAsFixed(1)} km for ${t.tripCode}: $note',
      );
      final r = generateInTx(tx, tripId, actor: actor);
      if (r == null) {
        throw ValidationFailure(['Billing could not be generated.']);
      }
      return r;
    }, info: 'Distance recorded and billing generated');
  }

  Future<Result<BillingRecord>> setStatus(
    String billingId,
    BillingStatus status, {
    String? reason,
    Actor actor = Actor.employerAdmin,
  }) {
    if (status == BillingStatus.disputed && (reason?.trim().length ?? 0) < 5) {
      return Future.value(
        Err.single('Give a dispute reason (at least 5 characters).'),
      );
    }
    return ctx.run(
      (tx) {
        final b = ctx.db.billing[billingId];
        if (b == null) throw ValidationFailure(['Billing record not found.']);
        final allowed = switch (b.status) {
          BillingStatus.draft => {BillingStatus.generated},
          BillingStatus.generated => {
            BillingStatus.reviewed,
            BillingStatus.disputed,
          },
          BillingStatus.reviewed => {
            BillingStatus.paidDemo,
            BillingStatus.disputed,
          },
          BillingStatus.disputed => {BillingStatus.reviewed},
          BillingStatus.paidDemo => <BillingStatus>{},
        };
        if (!allowed.contains(status)) {
          throw ValidationFailure([
            'Cannot change billing from ${b.status.label} to ${status.label}.',
          ]);
        }
        final next = b.copyWith(
          status: status,
          disputeReason: status == BillingStatus.disputed
              ? () => reason!.trim()
              : null,
          reviewedAt: status == BillingStatus.reviewed ? () => ctx.now : null,
        );
        tx.put(ctx.db.billing, next);
        if (status == BillingStatus.disputed) {
          ctx.notify(
            tx,
            role: UserRole.fleetManager,
            title: 'Billing disputed: ${b.tripCode}',
            body: reason!.trim(),
            category: NotificationCategory.billing,
            entityType: 'billing',
            entityId: b.id,
          );
        }
        ctx.audit(
          tx,
          actor,
          'billing.status',
          'billing',
          b.id,
          '${b.tripCode} billing → ${status.label}${reason != null ? ': $reason' : ''}.',
        );
        return next;
      },
      info: status == BillingStatus.paidDemo
          ? 'Marked paid (demo) — no payment was processed'
          : 'Billing ${status.label.toLowerCase()}',
    );
  }
}
