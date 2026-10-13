import '../../core/demo/clock.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/result.dart';
import '../models/models.dart';
import '../rules/tolerance_rules.dart';
import 'service_context.dart';

/// Fleet–company contracts (Fleet Manager). Records are never deleted —
/// status changes keep history.
class ContractService {
  ContractService(this.ctx);
  final ServiceContext ctx;

  List<String> validate(Contract c, {bool isNew = false}) {
    final db = ctx.db;
    return [
      if (!RegExp(r'^[A-Za-z0-9-]{3,20}$').hasMatch(c.contractCode))
        'Contract ID must be 3–20 letters/digits/hyphens.',
      if (db.contracts.any(
        (x) =>
            x.id != c.id &&
            x.contractCode.toLowerCase() == c.contractCode.toLowerCase(),
      ))
        'Contract ID ${c.contractCode} already exists.',
      if (isNew && db.contracts.contains(c.id)) 'Duplicate contract record.',
      if (db.employers[c.employerId] == null) 'Unknown company.',
      if (c.documentRef.trim().isEmpty)
        'Contract document reference is required (metadata only).',
      if (dateOnly(c.validUntil).isBefore(dateOnly(c.validFrom)))
        'Valid-until date cannot be earlier than valid-from.',
      if (c.agreedVehicleCount < 1 || c.agreedVehicleCount > 500)
        'Agreed number of cars must be 1–500.',
      if (c.costPerVehicle < 0) 'Cost per car cannot be negative.',
    ];
  }

  /// Warnings shown with a contract (not blocking the save).
  List<String> warnings(Contract c) {
    final v = c.validityOn(ctx.now);
    return [
      if (v == ContractValidity.expired)
        'Contract expired on ${Fmt.date(c.validUntil)} — assignments for ${ctx.db.employers[c.employerId]?.code} need an active contract.',
      if (v == ContractValidity.notYetValid)
        'Contract starts on ${Fmt.date(c.validFrom)}.',
      if (v == ContractValidity.suspended) 'Contract is suspended.',
    ];
  }

  Future<Result<Contract>> save(
    Contract c, {
    bool isNew = false,
    Actor actor = Actor.fleetManager,
  }) {
    final errors = validate(c, isNew: isNew);
    if (errors.isNotEmpty) return Future.value(Err(errors));
    return ctx.run(
      (tx) {
        final prev = ctx.db.contracts[c.id];
        final saved = c.copyWith(updatedAt: ctx.now);
        if (isNew) {
          tx.insert(ctx.db.contracts, saved);
        } else {
          if (prev == null) throw ValidationFailure(['Contract not found.']);
          tx.put(ctx.db.contracts, saved);
        }
        ctx.audit(
          tx,
          actor,
          isNew ? 'contract.create' : 'contract.update',
          'contract',
          c.id,
          '${isNew ? 'Created' : 'Updated'} contract ${c.contractCode} for ${c.employerId} '
              '(${Fmt.date(c.validFrom)}–${Fmt.date(c.validUntil)}, ${c.agreedVehicleCount} cars).',
          changes: prev == null
              ? ''
              : describeChanges({
                  'status': (prev.status.label, saved.status.label),
                  'validFrom': (
                    Fmt.date(prev.validFrom),
                    Fmt.date(saved.validFrom),
                  ),
                  'validUntil': (
                    Fmt.date(prev.validUntil),
                    Fmt.date(saved.validUntil),
                  ),
                  'cars': (prev.agreedVehicleCount, saved.agreedVehicleCount),
                  'costPerCar': (prev.costPerVehicle, saved.costPerVehicle),
                  'hardLimit': (prev.hardVehicleLimit, saved.hardVehicleLimit),
                  'document': (prev.documentRef, saved.documentRef),
                }),
          related: {'company': c.employerId},
        );
        return saved;
      },
      info: isNew ? 'Contract created' : 'Contract saved',
      warnings: warnings,
    );
  }

  Future<Result<Contract>> setStatus(
    String id,
    ContractStatus status, {
    required String reason,
    Actor actor = Actor.fleetManager,
  }) {
    if (reason.trim().length < 5) {
      return Future.value(Err.single('Give a reason (at least 5 characters).'));
    }
    return ctx.run((tx) {
      final c = ctx.db.contracts[id];
      if (c == null) throw ValidationFailure(['Contract not found.']);
      if (c.status == ContractStatus.terminated) {
        throw ValidationFailure(['Terminated contracts cannot be changed.']);
      }
      final next = c.copyWith(status: status, updatedAt: ctx.now);
      tx.put(ctx.db.contracts, next);
      ctx.audit(
        tx,
        actor,
        'contract.status',
        'contract',
        id,
        'Contract ${c.contractCode} → ${status.label}.',
        changes: 'status: ${c.status.label} → ${status.label}',
        reason: reason.trim(),
        related: {'company': c.employerId},
      );
      return next;
    }, info: 'Contract ${status.label.toLowerCase()}');
  }

  /// Vehicles used by the company on [day] vs the contract allowance.
  ({int used, int? allowed, Contract? contract}) usage(
    String employerId,
    DateTime day,
  ) {
    final contract = ctx.view.activeContract(employerId, day);
    final used = {
      for (final t in ctx.db.trips.values)
        if (t.employerId == employerId &&
            t.assignedVehicleId != null &&
            sameDay(t.serviceDate, day) &&
            t.status != TripStatus.cancelled)
          t.assignedVehicleId!,
    }.length;
    return (
      used: used,
      allowed: contract?.agreedVehicleCount,
      contract: contract,
    );
  }
}

/// Fleet–company allocations: which vehicles/drivers may serve which
/// company in which daily windows.
class AllocationService {
  AllocationService(this.ctx);
  final ServiceContext ctx;

  List<String> validate(FleetAllocation a) {
    final db = ctx.db;
    final errors = <String>[
      if (db.employers[a.employerId] == null) 'Unknown company.',
      if (a.resourceType == ResourceType.vehicle &&
          db.vehicles[a.resourceId] == null)
        'Unknown vehicle ${a.resourceId}.',
      if (a.resourceType == ResourceType.driver &&
          db.drivers[a.resourceId] == null)
        'Unknown driver ${a.resourceId}.',
      if (a.windowStartMinutes < 0 ||
          a.windowStartMinutes >= 1440 ||
          a.windowEndMinutes < 0 ||
          a.windowEndMinutes >= 1440)
        'Window times must be within the day.',
      if (a.windowStartMinutes == a.windowEndMinutes)
        'Window start and end cannot be equal.',
    ];
    if (errors.isNotEmpty || !a.active) return errors;
    // Same resource cannot be allocated to two companies at overlapping
    // times (shared fleet = non-overlapping windows).
    for (final o in db.allocations.values) {
      if (o.id == a.id || !o.active) continue;
      if (o.resourceType != a.resourceType || o.resourceId != a.resourceId) {
        continue;
      }
      if (o.employerId == a.employerId) {
        if (ShiftRules.overlaps(
          o.windowStartMinutes,
          o.windowEndMinutes,
          a.windowStartMinutes,
          a.windowEndMinutes,
        )) {
          errors.add(
            'Overlaps existing window ${Fmt.hhmm(o.windowStartMinutes)}–${Fmt.hhmm(o.windowEndMinutes)} for the same company.',
          );
        }
        continue;
      }
      if (ShiftRules.overlaps(
        o.windowStartMinutes,
        o.windowEndMinutes,
        a.windowStartMinutes,
        a.windowEndMinutes,
      )) {
        errors.add(
          '${a.resourceType.label} ${a.resourceId} is already allocated to ${db.employers[o.employerId]?.code ?? o.employerId} '
          'at ${Fmt.hhmm(o.windowStartMinutes)}–${Fmt.hhmm(o.windowEndMinutes)}.',
        );
      }
    }
    return errors;
  }

  Future<Result<FleetAllocation>> save(
    FleetAllocation a, {
    bool isNew = false,
    Actor actor = Actor.fleetManager,
  }) {
    final errors = validate(a);
    if (errors.isNotEmpty) return Future.value(Err(errors));
    return ctx.run((tx) {
      final id = isNew ? tx.newId(ctx.db.allocations, 'FA-') : a.id;
      final saved = isNew
          ? FleetAllocation(
              id: id,
              employerId: a.employerId,
              resourceType: a.resourceType,
              resourceId: a.resourceId,
              windowStartMinutes: a.windowStartMinutes,
              windowEndMinutes: a.windowEndMinutes,
              label: a.label,
              active: a.active,
              createdAt: ctx.now,
            )
          : a;
      final prev = ctx.db.allocations[id];
      tx.put(ctx.db.allocations, saved);
      ctx.audit(
        tx,
        actor,
        isNew ? 'allocation.create' : 'allocation.update',
        'fleetAllocation',
        id,
        '${saved.resourceType.label} ${saved.resourceId} ${saved.active ? 'allocated to' : 'removed from'} '
            '${saved.employerId} ${Fmt.hhmm(saved.windowStartMinutes)}–${Fmt.hhmm(saved.windowEndMinutes)}.',
        changes: prev == null
            ? ''
            : describeChanges({
                'window': (
                  '${Fmt.hhmm(prev.windowStartMinutes)}–${Fmt.hhmm(prev.windowEndMinutes)}',
                  '${Fmt.hhmm(saved.windowStartMinutes)}–${Fmt.hhmm(saved.windowEndMinutes)}',
                ),
                'active': (prev.active, saved.active),
              }),
        related: {
          'company': saved.employerId,
          saved.resourceType.name: saved.resourceId,
        },
      );
      return saved;
    }, info: isNew ? 'Allocation added' : 'Allocation saved');
  }

  /// Removal keeps the record (inactive) for audit history.
  Future<Result<FleetAllocation>> remove(
    String id, {
    Actor actor = Actor.fleetManager,
  }) {
    final a = ctx.db.allocations[id];
    if (a == null) return Future.value(Err.single('Allocation not found.'));
    return save(a.copyWith(active: false), actor: actor);
  }
}
