import '../../core/utils/result.dart';
import '../../data/repositories/repositories.dart';
import '../../data/seed/seed_data.dart';
import '../models/models.dart';
import 'service_context.dart';

/// Local audit trail (read side lives in DataView.auditTrail).
class AuditService {
  AuditService(this.ctx);
  final ServiceContext ctx;

  Future<Result<void>> record(
    Actor actor,
    String action,
    String entityType,
    String entityId,
    String summary,
  ) => ctx.run(
    (tx) => ctx.audit(tx, actor, action, entityType, entityId, summary),
  );
}

/// Local in-app notifications. Nothing is sent via SMS/push.
class NotificationService {
  NotificationService(this.ctx);
  final ServiceContext ctx;

  Future<Result<void>> markRead(String id) => ctx.run((tx) {
    final n = ctx.db.notifications[id];
    if (n == null || n.isRead) return;
    tx.put(ctx.db.notifications, n.copyWith(readAt: () => ctx.now));
  });

  Future<Result<void>> markUnread(String id) => ctx.run((tx) {
    final n = ctx.db.notifications[id];
    if (n == null) return;
    tx.put(ctx.db.notifications, n.copyWith(readAt: () => null));
  });

  Future<Result<int>> markAllRead(UserRole role, [String? recipientId]) =>
      ctx.run((tx) {
        var count = 0;
        for (final n in ctx.view.notificationsFor(role, recipientId)) {
          if (!n.isRead) {
            tx.put(ctx.db.notifications, n.copyWith(readAt: () => ctx.now));
            count++;
          }
        }
        return count;
      });
}

/// Demo identity selection for the Employee and Driver workspaces.
/// This is NOT authentication; it only remembers who is being demoed.
class SessionService {
  SessionService(this.ctx);
  final ServiceContext ctx;

  Future<Result<Employee>> signInEmployee(
    String employeeId, {
    String? password,
  }) async {
    final e = ctx.db.employees[employeeId];
    if (e == null) return Err.single('Unknown employee $employeeId.');
    if (!e.isActive) {
      return Err.single(
        '${e.employeeCode} is deactivated. Ask your employer admin to reactivate the profile.',
      );
    }
    if (e.optionalDemoPasswordEnabled && password != demoEmployeePassword) {
      return Err.single(
        password == null || password.isEmpty
            ? 'This demo profile is configured with a password.'
            : 'Incorrect demo password.',
      );
    }
    await ctx.db.setAppState(LocalAuthRepository.employeeKey, e.id);
    return Ok(e, info: 'Signed in as ${e.name} (demo identity)');
  }

  Future<Result<Driver>> signInDriver(String driverId) async {
    final d = ctx.db.drivers[driverId];
    if (d == null) return Err.single('Unknown driver $driverId.');
    await ctx.db.setAppState(LocalAuthRepository.driverKey, d.id);
    return Ok(d, info: 'Signed in as ${d.name} (demo identity)');
  }

  Future<void> signOutEmployee() =>
      ctx.db.setAppState(LocalAuthRepository.employeeKey, null);
  Future<void> signOutDriver() =>
      ctx.db.setAppState(LocalAuthRepository.driverKey, null);
  Future<void> rememberWorkspace(String workspace) =>
      ctx.db.setAppState(LocalAuthRepository.workspaceKey, workspace);
  Future<void> setFlag(String key, bool value) =>
      ctx.db.setAppState(key, value ? '1' : null);
  bool flag(String key) => ctx.db.appState(key) == '1';
}

/// Local support tickets and simulated control-room contact.
class SupportService {
  SupportService(this.ctx);
  final ServiceContext ctx;

  Future<Result<SupportTicket>> createTicket({
    required Actor actor,
    required TicketCategory category,
    required String subject,
    required String description,
    String? relatedTripId,
  }) {
    final errors = <String>[
      if (subject.trim().length < 4) 'Subject needs at least 4 characters.',
      if (description.trim().length < 10)
        'Description needs at least 10 characters.',
      if (relatedTripId != null && ctx.db.trips[relatedTripId] == null)
        'Related trip not found.',
    ];
    if (errors.isNotEmpty) return Future.value(Err(errors));
    return ctx.run(
      (tx) {
        final id = tx.newId(ctx.db.tickets, 'TK-');
        final t = SupportTicket(
          id: id,
          reference: id,
          createdByRole: actor.role,
          createdById: actor.id,
          category: category,
          subject: subject.trim(),
          description: description.trim(),
          relatedTripId: relatedTripId,
          status: TicketStatus.open,
          createdAt: ctx.now,
          updatedAt: ctx.now,
        );
        tx.insert(ctx.db.tickets, t);
        ctx.notify(
          tx,
          role: UserRole.fleetManager,
          title: 'Support ticket $id',
          body: '${actor.label}: ${t.subject}',
          category: NotificationCategory.system,
          entityType: 'ticket',
          entityId: id,
        );
        ctx.audit(
          tx,
          actor,
          'ticket.create',
          'ticket',
          id,
          'Created support ticket "${t.subject}".',
        );
        return t;
      },
      info:
          'Ticket created locally. A support agent would respond in a real deployment.',
    );
  }

  Future<Result<SupportTicket>> updateStatus(
    String ticketId,
    TicketStatus status, {
    String? response,
    Actor actor = Actor.fleetManager,
  }) => ctx.run((tx) {
    final t = ctx.db.tickets[ticketId];
    if (t == null) throw ValidationFailure(['Ticket not found.']);
    final next = t.copyWith(
      status: status,
      response: response == null ? null : () => response,
      updatedAt: ctx.now,
    );
    tx.put(ctx.db.tickets, next);
    ctx.notify(
      tx,
      role: t.createdByRole,
      recipientId: t.createdById,
      title: 'Ticket ${t.reference}: ${status.label}',
      body: response ?? 'Status updated.',
      category: NotificationCategory.system,
      entityType: 'ticket',
      entityId: t.id,
    );
    ctx.audit(
      tx,
      actor,
      'ticket.status',
      'ticket',
      t.id,
      'Ticket ${t.reference} → ${status.label}.',
    );
    return next;
  });

  /// Simulated control-room callback request; records an audit event only.
  Future<Result<void>> requestControlRoomContact(
    Actor actor, {
    String? tripId,
  }) => ctx.run((tx) {
    ctx.notify(
      tx,
      role: UserRole.fleetManager,
      title: 'Call-back requested (demo)',
      body:
          '${actor.label} requested control-room contact${tripId != null ? ' about $tripId' : ''}.',
      category: NotificationCategory.system,
      entityType: tripId != null ? 'trip' : null,
      entityId: tripId,
    );
    ctx.audit(
      tx,
      actor,
      'controlRoom.request',
      tripId != null ? 'trip' : 'user',
      tripId ?? actor.id,
      'Simulated control-room contact requested.',
    );
  }, info: 'Simulated control-room contact recorded. No call was placed.');
}

class SettingsService {
  SettingsService(this.ctx);
  final ServiceContext ctx;

  Future<Result<UserSettings>> save(UserSettings s) => ctx.run((tx) {
    tx.put(ctx.db.userSettings, s);
    return s;
  }, info: 'Preferences saved');
}
