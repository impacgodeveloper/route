import '../../core/demo/clock.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/result.dart';
import '../models/models.dart';
import 'billing_service.dart';
import 'service_context.dart';

/// Inclusive billing period on local business dates.
class BillingPeriod {
  const BillingPeriod(this.cycle, this.start, this.end);
  final BillingCycle cycle;
  final DateTime start;
  final DateTime end;

  bool contains(DateTime d) {
    final x = dateOnly(d);
    return !x.isBefore(start) && !x.isAfter(end);
  }

  /// Week boundary: Monday 00:00 → Sunday (ISO week, local date).
  /// Month boundary: 1st → last day of the calendar month.
  static BillingPeriod of(BillingCycle cycle, DateTime date) {
    final d = dateOnly(date);
    if (cycle == BillingCycle.weekly) {
      final start = d.subtract(Duration(days: d.weekday - DateTime.monday));
      return BillingPeriod(
        cycle,
        start,
        DateTime(start.year, start.month, start.day + 6),
      );
    }
    return BillingPeriod(
      cycle,
      DateTime(d.year, d.month, 1),
      DateTime(d.year, d.month + 1, 0),
    );
  }

  BillingPeriod get previous =>
      BillingPeriod.of(cycle, DateTime(start.year, start.month, start.day - 1));
  BillingPeriod get next =>
      BillingPeriod.of(cycle, DateTime(end.year, end.month, end.day + 1));

  /// First local day after this period (the next boundary).
  DateTime get nextBoundary => DateTime(end.year, end.month, end.day + 1);

  String get label => cycle == BillingCycle.weekly
      ? 'Week of ${Fmt.date(start)} – ${Fmt.date(end)}'
      : '${_months[start.month - 1]} ${start.year}';

  String get code {
    if (cycle == BillingCycle.monthly) {
      return '${start.year}-${start.month.toString().padLeft(2, '0')}';
    }
    return '${start.year}${start.month.toString().padLeft(2, '0')}${start.day.toString().padLeft(2, '0')}W';
  }

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  bool operator ==(Object other) =>
      other is BillingPeriod &&
      other.cycle == cycle &&
      other.start == start &&
      other.end == end;
  @override
  int get hashCode => Object.hash(cycle, start, end);
}

/// One trip considered for a billing cycle.
class CycleLine {
  const CycleLine({
    required this.trip,
    this.record,
    this.calculation,
    this.exclusion,
  });
  final Trip trip;

  /// Existing per-trip billing line (null = will be generated on run).
  final BillingRecord? record;
  final BillingCalculation? calculation;

  /// Why the trip is NOT included (null = eligible).
  final String? exclusion;
  bool get eligible => exclusion == null;
  double get total => record?.totalAmount ?? calculation?.total ?? 0;
}

class CyclePreview {
  const CyclePreview({
    required this.period,
    required this.lines,
    required this.existingInvoices,
    required this.blockers,
  });
  final BillingPeriod period;
  final List<CycleLine> lines;
  final List<Invoice> existingInvoices;

  /// Configuration problems that prevent running the cycle.
  final List<String> blockers;

  List<CycleLine> get eligible => lines.where((l) => l.eligible).toList();
  List<CycleLine> get excluded => lines.where((l) => !l.eligible).toList();
  double get total => eligible.fold(0, (s, l) => s + l.total);
  double get distanceKm => eligible.fold(
    0,
    (s, l) =>
        s + (l.record?.billableDistanceKm ?? l.calculation?.distanceKm ?? 0),
  );
  bool get canRun => blockers.isEmpty && eligible.isNotEmpty;
}

/// Weekly/monthly billing-cycle processing (local, deterministic, idempotent).
///
/// Invoices are generated LOCALLY ONLY — never emailed, submitted to an
/// accounting system or paid. There is no background scheduler: cycles are
/// processed by an explicit action; the app shows due cycles when opened.
class BillingCycleService {
  BillingCycleService(this.ctx, this.billing);
  final ServiceContext ctx;
  final BillingService billing;

  BillingPeriod currentPeriod(Employer e) =>
      BillingPeriod.of(e.billingCycle, ctx.now);

  CyclePreview preview(String employerId, BillingPeriod period) {
    final db = ctx.db;
    final employer = db.employers[employerId];
    final blockers = <String>[
      if (employer == null) 'Unknown company.',
      if (employer != null && !employer.billingActive)
        'Billing is paused for ${employer.code}. Activate it in billing settings.',
      if (employer != null && employer.defaultDistanceRate <= 0)
        'Distance rate must be above ₹0.',
    ];
    final lines = <CycleLine>[];
    final trips =
        db.trips
            .where(
              (t) =>
                  t.employerId == employerId &&
                  period.contains(t.actualArrival ?? t.serviceDate),
            )
            .toList()
          ..sort(
            (a, b) => (a.actualArrival ?? a.serviceDate).compareTo(
              b.actualArrival ?? b.serviceDate,
            ),
          );
    for (final t in trips) {
      final rec = db.billing.where((b) => b.tripId == t.id).firstOrNull;
      String? exclusion;
      BillingCalculation? calc;
      if (t.status == TripStatus.cancelled) {
        exclusion = 'Cancelled — never billed';
      } else if (t.status != TripStatus.completed) {
        exclusion = 'Not completed (${t.status.label.toLowerCase()})';
      } else if (rec != null && rec.invoiceId != null) {
        exclusion =
            'Already invoiced on ${db.invoices[rec.invoiceId]?.reference ?? rec.invoiceId}';
      } else if (rec != null && rec.status == BillingStatus.disputed) {
        exclusion = 'Line disputed — resolve before invoicing';
      } else if (rec == null) {
        if (t.distanceKm == null) {
          exclusion = 'Missing actual distance — record it before billing';
        } else if (t.distanceKm! < 0) {
          exclusion = 'Invalid (negative) distance';
        } else if (employer != null) {
          calc = BillingService.calculate(
            distanceKm: t.distanceKm!,
            ratePerKm: employer.defaultDistanceRate,
            additionalCharges: employer.additionalChargePerTrip,
          );
        }
      }
      lines.add(
        CycleLine(
          trip: t,
          record: rec,
          calculation: calc,
          exclusion: exclusion,
        ),
      );
    }
    final existing =
        db.invoices
            .where(
              (i) =>
                  i.employerId == employerId &&
                  i.periodStart == period.start &&
                  i.periodEnd == period.end,
            )
            .toList()
          ..sort((a, b) => a.sequence.compareTo(b.sequence));
    return CyclePreview(
      period: period,
      lines: lines,
      existingInvoices: existing,
      blockers: blockers,
    );
  }

  /// Past periods (most recent first) that still have uninvoiced eligible
  /// trips — shown as "due" when the app opens. Looks back [lookback] periods.
  List<CyclePreview> dueCycles(String employerId, {int lookback = 6}) {
    final e = ctx.db.employers[employerId];
    if (e == null || !e.billingActive) return const [];
    final out = <CyclePreview>[];
    var p = currentPeriod(e).previous;
    for (var i = 0; i < lookback; i++) {
      final pv = preview(employerId, p);
      if (pv.eligible.isNotEmpty) out.add(pv);
      p = p.previous;
    }
    return out;
  }

  Future<Result<Invoice>> runCycle(
    String employerId,
    BillingPeriod period, {
    Actor actor = Actor.employerAdmin,
  }) async {
    final pv = preview(employerId, period);
    final spec = RejectAudit(
      actor: actor,
      action: 'billing.cycle',
      entityType: 'invoice',
      entityId: '$employerId:${period.code}',
      summary: 'Billing cycle ${period.label}',
    );
    if (pv.blockers.isNotEmpty) {
      await ctx.recordRejected(spec, pv.blockers);
      return Err(pv.blockers);
    }
    if (pv.eligible.isEmpty) {
      final msg = pv.existingInvoices.isEmpty
          ? 'No eligible completed trips with valid distance in ${period.label}.'
          : 'Nothing new to invoice — ${pv.existingInvoices.map((i) => i.reference).join(', ')} already covers ${period.label}. No duplicate generated.';
      await ctx.recordRejected(spec, [msg]);
      return Err.single(msg);
    }
    return ctx.run(
      (tx) {
        final db = ctx.db;
        final employer = db.employers[employerId]!;
        // Re-check inside the transaction (idempotency).
        final fresh = preview(employerId, period);
        if (fresh.eligible.isEmpty) {
          throw ValidationFailure(['Nothing new to invoice.']);
        }
        final records = <BillingRecord>[];
        for (final line in fresh.eligible) {
          var rec = line.record;
          rec ??= billing.generateInTx(
            tx,
            line.trip.id,
            additionalCharges: employer.additionalChargePerTrip,
            actor: actor,
          );
          if (rec == null) continue;
          records.add(rec);
        }
        if (records.isEmpty) {
          throw ValidationFailure(['No billing lines could be generated.']);
        }
        final sequence = fresh.existingInvoices.length + 1;
        final id = tx.newId(db.invoices, 'INV-');
        final reference =
            'INV-${employer.code}-${period.code}${sequence > 1 ? '-S$sequence' : ''}';
        double r2(double v) => double.parse(v.toStringAsFixed(2));
        final distance = r2(
          records.fold(0.0, (s, r) => s + r.billableDistanceKm),
        );
        final distanceCharges = r2(
          records.fold(0.0, (s, r) => s + r.distanceCharge),
        );
        final additional = r2(
          records.fold(0.0, (s, r) => s + r.additionalCharges),
        );
        final adjustments = r2(records.fold(0.0, (s, r) => s + r.adjustment));
        final total = r2(records.fold(0.0, (s, r) => s + r.totalAmount));
        final invoice = Invoice(
          id: id,
          reference: reference,
          employerId: employerId,
          cycle: period.cycle,
          periodStart: period.start,
          periodEnd: period.end,
          sequence: sequence,
          billingRecordIds: records.map((r) => r.id).toList(),
          tripIds: records.map((r) => r.tripId).toList(),
          distanceKm: distance,
          distanceCharges: distanceCharges,
          additionalCharges: additional,
          adjustments: adjustments,
          total: total,
          status: InvoiceStatus.generated,
          generatedAt: ctx.now,
          notes: sequence > 1
              ? 'Supplementary invoice for trips completed after the first run.'
              : '',
        );
        tx.insert(db.invoices, invoice);
        for (final r in records) {
          tx.put(
            db.billing,
            (db.billing[r.id] ?? r).copyWith(invoiceId: () => id),
          );
        }
        ctx.notify(
          tx,
          role: UserRole.employerAdmin,
          title: 'Invoice $reference generated (demo)',
          body:
              '${records.length} trip line(s) · ${Fmt.inr(total)} · ${period.label}. Generated locally — not emailed or submitted.',
          category: NotificationCategory.billing,
          entityType: 'invoice',
          entityId: id,
        );
        ctx.notify(
          tx,
          role: UserRole.fleetManager,
          title: 'Billing cycle processed: ${employer.code}',
          body:
              '$reference · ${records.length} trips · ${distance.toStringAsFixed(1)} km.',
          category: NotificationCategory.billing,
          entityType: 'invoice',
          entityId: id,
        );
        ctx.audit(
          tx,
          actor,
          'billing.cycle',
          'invoice',
          id,
          'Processed ${period.cycle.name} cycle ${period.label}: $reference with ${records.length} line(s), total ${Fmt.inr(total)}.',
          related: {
            'company': employerId,
            'trips': records.map((r) => r.tripId).join(','),
          },
        );
        return invoice;
      },
      info: 'Invoice generated locally (demo) — not emailed, submitted or paid',
      rejectAudit: RejectAudit(
        actor: actor,
        action: 'billing.cycle',
        entityType: 'invoice',
        entityId: '$employerId:${period.code}',
        summary: 'Billing cycle ${period.label}',
      ),
    );
  }

  Future<Result<Invoice>> setStatus(
    String invoiceId,
    InvoiceStatus status, {
    String? reason,
    Actor actor = Actor.employerAdmin,
  }) {
    if (status == InvoiceStatus.disputed && (reason?.trim().length ?? 0) < 5) {
      return Future.value(
        Err.single('Give a dispute reason (at least 5 characters).'),
      );
    }
    return ctx.run(
      (tx) {
        final inv = ctx.db.invoices[invoiceId];
        if (inv == null) throw ValidationFailure(['Invoice not found.']);
        final allowed = switch (inv.status) {
          InvoiceStatus.generated => {
            InvoiceStatus.reviewed,
            InvoiceStatus.disputed,
          },
          InvoiceStatus.reviewed => {
            InvoiceStatus.paidDemo,
            InvoiceStatus.disputed,
          },
          InvoiceStatus.disputed => {InvoiceStatus.reviewed},
          InvoiceStatus.paidDemo => <InvoiceStatus>{},
        };
        if (!allowed.contains(status)) {
          throw ValidationFailure([
            'Cannot change ${inv.reference} from ${inv.status.label} to ${status.label}.',
          ]);
        }
        final next = inv.copyWith(
          status: status,
          disputeReason: status == InvoiceStatus.disputed
              ? () => reason!.trim()
              : null,
          reviewedAt: status == InvoiceStatus.reviewed ? () => ctx.now : null,
        );
        tx.put(ctx.db.invoices, next);
        if (status == InvoiceStatus.disputed) {
          ctx.notify(
            tx,
            role: UserRole.fleetManager,
            title: 'Invoice disputed: ${inv.reference}',
            body: reason!.trim(),
            category: NotificationCategory.billing,
            entityType: 'invoice',
            entityId: inv.id,
          );
        }
        ctx.audit(
          tx,
          actor,
          'invoice.status',
          'invoice',
          inv.id,
          '${inv.reference} → ${status.label}.',
          changes: 'status: ${inv.status.label} → ${status.label}',
          reason: reason?.trim(),
          related: {'company': inv.employerId},
        );
        return next;
      },
      info: status == InvoiceStatus.paidDemo
          ? 'Marked paid (demo) — no payment was processed'
          : 'Invoice ${status.label.toLowerCase()}',
    );
  }
}
