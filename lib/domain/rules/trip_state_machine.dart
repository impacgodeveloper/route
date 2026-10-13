import '../enums/enums.dart';

/// Allowed trip status transitions. Anything not listed is rejected.
abstract final class TripStateMachine {
  static const Map<TripStatus, Set<TripStatus>> _allowed = {
    TripStatus.draft: {
      TripStatus.planned,
      TripStatus.assigned,
      TripStatus.cancelled,
    },
    TripStatus.planned: {
      TripStatus.assigned,
      TripStatus.cancelled,
      TripStatus.draft,
    },
    TripStatus.assigned: {
      TripStatus.driverAccepted,
      TripStatus.ready,
      TripStatus.inProgress,
      TripStatus.planned,
      TripStatus.cancelled,
      TripStatus.needsAttention,
      TripStatus.assigned,
    },
    TripStatus.driverAccepted: {
      TripStatus.ready,
      TripStatus.inProgress,
      TripStatus.planned,
      TripStatus.assigned,
      TripStatus.cancelled,
      TripStatus.needsAttention,
    },
    TripStatus.ready: {
      TripStatus.inProgress,
      TripStatus.assigned,
      TripStatus.planned,
      TripStatus.cancelled,
      TripStatus.needsAttention,
    },
    TripStatus.inProgress: {
      TripStatus.delayed,
      TripStatus.completed,
      TripStatus.needsAttention,
    },
    TripStatus.delayed: {
      TripStatus.inProgress,
      TripStatus.completed,
      TripStatus.needsAttention,
    },
    TripStatus.needsAttention: {
      TripStatus.inProgress,
      TripStatus.delayed,
      TripStatus.assigned,
      TripStatus.planned,
      TripStatus.completed,
      TripStatus.cancelled,
    },
    TripStatus.completed: {},
    TripStatus.cancelled: {},
  };

  static bool canTransition(TripStatus from, TripStatus to) =>
      _allowed[from]?.contains(to) ?? false;

  static Set<TripStatus> nextStates(TripStatus from) => _allowed[from] ?? {};

  /// A trip can be (re)assigned while it has not started or finished.
  static bool canAssign(TripStatus s) =>
      s == TripStatus.draft ||
      s == TripStatus.planned ||
      s == TripStatus.assigned ||
      s == TripStatus.driverAccepted ||
      s == TripStatus.ready ||
      s == TripStatus.needsAttention;

  /// Statuses that occupy a driver/vehicle time window.
  static bool occupiesWindow(TripStatus s) =>
      s != TripStatus.cancelled &&
      s != TripStatus.completed &&
      s != TripStatus.draft;
}
