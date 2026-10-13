import '../../core/demo/clock.dart';
import '../../core/persistence/local_database.dart';
import '../../core/utils/result.dart';
import '../../data/repositories/repositories.dart';
import '../models/models.dart';

/// Who performed an action (recorded in audit events).
class Actor {
  const Actor(this.role, this.id, [this.displayName]);
  final UserRole role;
  final String id;
  final String? displayName;

  static const fleetManager = Actor(
    UserRole.fleetManager,
    'FM',
    'Fleet Manager',
  );
  static const employerAdmin = Actor(
    UserRole.employerAdmin,
    'EA-C1',
    'Employer Admin',
  );
  static const system = Actor(UserRole.system, 'system', 'System');
  factory Actor.employee(String id) => Actor(UserRole.employee, id);
  factory Actor.driver(String id) => Actor(UserRole.driver, id);

  String get label => displayName ?? '${role.label} $id';
}

/// Shared plumbing for every domain service.
class ServiceContext {
  ServiceContext(this.db, this.clock);

  final LocalDatabase db;
  final Clock clock;

  DateTime get now => clock.now();
  DataView get view => DataView(db, clock);

  /// Runs [body] in a transaction and converts aborts into [Err] results,
  /// so callers can keep form input and show the message inline.
  /// When [rejectAudit] is given, a rejected operation is still recorded
  /// in the audit trail (outcome = rejected) in its own transaction.
  Future<Result<T>> run<T>(
    T Function(Txn tx) body, {
    String? info,
    List<String> Function(T value)? warnings,
    RejectAudit? rejectAudit,
  }) async {
    try {
      final value = await db.transaction(body);
      return Ok(value, info: info, warnings: warnings?.call(value) ?? const []);
    } on TxnAbort catch (e) {
      await _auditRejected(rejectAudit, [e.message]);
      return Err.single(e.message);
    } on ValidationFailure catch (e) {
      await _auditRejected(rejectAudit, e.messages);
      return Err(e.messages);
    }
  }

  Future<void> _auditRejected(RejectAudit? spec, List<String> errors) async {
    if (spec == null) return;
    await recordRejected(spec, errors);
  }

  /// Records a rejected/failed operation (separate transaction).
  Future<void> recordRejected(
    RejectAudit spec,
    List<String> errors, {
    AuditOutcome outcome = AuditOutcome.rejected,
  }) => db.transaction(
    (tx) => audit(
      tx,
      spec.actor,
      spec.action,
      spec.entityType,
      spec.entityId,
      '${spec.summary} — ${outcome.label.toLowerCase()}',
      outcome: outcome,
      reason: errors.join(' '),
      related: spec.related,
    ),
  );

  void audit(
    Txn tx,
    Actor actor,
    String action,
    String entityType,
    String entityId,
    String summary, {
    AuditOutcome outcome = AuditOutcome.success,
    String changes = '',
    String? reason,
    Map<String, String> related = const {},
    bool simulated = false,
  }) {
    tx.insert(
      db.audit,
      AuditEvent(
        id: tx.newId(db.audit, 'AU-'),
        actorRole: actor.role,
        actorId: actor.id,
        action: action,
        entityType: entityType,
        entityId: entityId,
        timestamp: now,
        summary: summary,
        outcome: outcome,
        changes: changes,
        reason: reason,
        related: related,
        simulated: simulated,
      ),
    );
  }

  void notify(
    Txn tx, {
    required UserRole role,
    String? recipientId,
    required String title,
    required String body,
    required NotificationCategory category,
    String? entityType,
    String? entityId,
  }) {
    tx.insert(
      db.notifications,
      AppNotification(
        id: tx.newId(db.notifications, 'NT-'),
        recipientRole: role,
        recipientId: recipientId,
        title: title,
        body: body,
        category: category,
        createdAt: now,
        relatedEntityType: entityType,
        relatedEntityId: entityId,
      ),
    );
  }

  void notifyEmployees(
    Txn tx,
    Iterable<String> employeeIds,
    String title,
    String body,
    NotificationCategory category, {
    String? entityType,
    String? entityId,
  }) {
    for (final id in employeeIds) {
      notify(
        tx,
        role: UserRole.employee,
        recipientId: id,
        title: title,
        body: body,
        category: category,
        entityType: entityType,
        entityId: entityId,
      );
    }
  }
}

/// Thrown with several validation messages; becomes an [Err].
class ValidationFailure implements Exception {
  ValidationFailure(this.messages);
  final List<String> messages;
  @override
  String toString() => messages.join('\n');
}

/// What to record in the audit trail when an operation is rejected.
class RejectAudit {
  const RejectAudit({
    required this.actor,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.summary,
    this.related = const {},
  });

  final Actor actor;
  final String action;
  final String entityType;
  final String entityId;
  final String summary;
  final Map<String, String> related;
}

/// Builds a safe "field: before → after" change summary.
String describeChanges(Map<String, (Object?, Object?)> fields) => fields.entries
    .where((e) => '${e.value.$1}' != '${e.value.$2}')
    .map((e) => '${e.key}: ${e.value.$1 ?? '—'} → ${e.value.$2 ?? '—'}')
    .join('; ');
