import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/widgets.dart';
import '../../../domain/models/models.dart';
import '../driver_common.dart';
import '../driver_v2_widgets.dart';

/// Stop management + passenger manifest with demo QR/T-PIN verification.
class DriverStopScreen extends ConsumerStatefulWidget {
  const DriverStopScreen({
    super.key,
    required this.tripId,
    required this.stopId,
  });
  final String tripId;
  final String stopId;

  @override
  ConsumerState<DriverStopScreen> createState() => _DriverStopScreenState();
}

class _DriverStopScreenState extends ConsumerState<DriverStopScreen> {
  String _query = '';
  VerificationOutcome? _last;
  final Set<String> _dropSelection = {};
  bool _busy = false;

  DriverOpsService get _ops => ref.read(servicesProvider).driverOps;

  Future<void> _act(Future<Result> Function() f) async {
    setState(() => _busy = true);
    final r = await f();
    if (!mounted) return;
    setState(() => _busy = false);
    await showResult(context, r);
  }

  Future<void> _verify(
    VerificationMethod method,
    String input, {
    String? employeeId,
  }) async {
    setState(() => _busy = true);
    final r = await _ops.verifyAndBoard(
      stopId: widget.stopId,
      method: method,
      input: input,
      employeeId: employeeId,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _last = r.valueOrNull;
    });
    if (!r.isOk) {
      await showResult(context, r);
    } else if (_last?.ok ?? false) {
      HapticFeedback.mediumImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final trip = data.trips.byId(widget.tripId);
    final stop = data.db.routeStops[widget.stopId];
    final t = Theme.of(context).textTheme;
    if (trip == null || stop == null) {
      return Scaffold(
        appBar: driverAppBar(context, 'Stop'),
        body: const EmptyState(
          icon: Icons.search_off_rounded,
          title: 'Stop not found',
          message: 'It may have been reset.',
        ),
      );
    }
    final loc = data.location(stop.locationId);
    final isPickup = stop.kind == StopKind.pickup;
    final ids = isPickup ? stop.boardingEmployeeIds : stop.alightingEmployeeIds;
    final people = ids.map(data.employee).whereType<Employee>().where((e) {
      final q = _query.trim().toLowerCase();
      return q.isEmpty ||
          e.name.toLowerCase().contains(q) ||
          e.employeeCode.toLowerCase().contains(q);
    }).toList();
    final active = trip.status.isActive && trip.actualStart != null;
    final arrived = stop.status == StopStatus.arrived;
    final issues = arrived ? _ops.stopDiscrepancies(stop) : const <String>[];
    final boardedHere = stop.boardingEmployeeIds
        .where(trip.boardedPassengerIds.contains)
        .length;
    final droppedHere = stop.alightingEmployeeIds
        .where(trip.alightedPassengerIds.contains)
        .length;

    return Scaffold(
      appBar: driverAppBar(
        context,
        'Stop ${stop.sequence}',
        fallback: '/driver/trip/${trip.id}/active',
        actions: [
          IconButton(
            tooltip: 'SOS',
            onPressed: () => context.push('/driver/sos?trip=${trip.id}'),
            icon: const Icon(Icons.sos_rounded, color: AppColors.danger),
          ),
        ],
      ),
      body: DrivingLock(
        child: MobilePage(
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      StatusBadge(
                        stop.kind.label,
                        tone: isPickup ? StatusTone.info : StatusTone.teal,
                        dense: true,
                      ),
                      const SizedBox(width: AppSpace.xs),
                      StatusBadge(
                        stop.status.label,
                        tone: Tones.stop(stop.status),
                        dense: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text(loc?.name ?? stop.locationId, style: t.headlineSmall),
                  Text(
                    '${loc?.code ?? ''} · ${trip.tripCode}',
                    style: AppText.secondary(context),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  StopTimingPanel(stop: stop),
                  KeyValueRow(
                    label: isPickup
                        ? 'Boarded / expected'
                        : 'Dropped / expected',
                    value: isPickup
                        ? '$boardedHere / ${stop.expectedBoardingCount}'
                        : '$droppedHere / ${stop.expectedAlightingCount}',
                    dense: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.md),
            if (!active)
              const InlineBanner(
                tone: StatusTone.info,
                title: 'Trip not in progress',
                message:
                    'Passenger actions are available only during an active trip.',
              )
            else if (stop.status == StopStatus.upcoming &&
                data.trips.currentStop(trip)?.id == stop.id)
              BigButton(
                label: 'Arrived at stop',
                icon: Icons.where_to_vote_outlined,
                color: AppColors.teal,
                busy: _busy,
                onPressed: () => _act(() => _ops.arriveAtStop(stop.id)),
              ),
            if (_last != null) ...[
              _OutcomeBanner(
                outcome: _last!,
                onClose: () => setState(() => _last = null),
              ),
              const SizedBox(height: AppSpace.md),
            ],
            if (arrived && isPickup) ...[
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _openScan(context, data, trip, stop),
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      label: const Text('Scan QR'),
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _openTpin(context, data, trip, stop, null),
                      icon: const Icon(Icons.pin_outlined),
                      label: const Text('Enter T-PIN'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
            ],
            const Overline('Passengers at this stop'),
            if (ids.length > 3) ...[
              AppSearchField(
                hint: 'Search name or ID',
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: AppSpace.sm),
            ],
            if (people.isEmpty)
              EmptyState(
                icon: Icons.person_search_outlined,
                title: ids.isEmpty ? 'No passengers here' : 'No match',
                message: ids.isEmpty
                    ? 'Nobody boards or alights at this stop.'
                    : 'Clear the search to see everyone.',
                compact: true,
              )
            else
              for (final e in people) ...[
                _PassengerRow(
                  employee: e,
                  window:
                      '${isPickup ? 'Pickup' : 'Drop'} window ${windowLabel(stop.plannedArrival, employeeTolerance(data, e))}',
                  state: data.trips.passengerState(trip, e.id),
                  pickup: isPickup,
                  enabled: active && arrived && !_busy,
                  selected: _dropSelection.contains(e.id),
                  onSelect: (v) => setState(
                    () => v
                        ? _dropSelection.add(e.id)
                        : _dropSelection.remove(e.id),
                  ),
                  onTpin: () => _openTpin(context, data, trip, stop, e),
                  onOverride: () async {
                    final input = await showReasonDialog(
                      context,
                      title: 'Manual override · ${e.employeeCode}',
                      message:
                          'Board without QR/T-PIN only when authorized (e.g. phone battery dead, identity confirmed by control room).',
                      requireAuthorizer: true,
                      authorizerHint: 'e.g. Fleet Manager on call',
                      confirmLabel: 'Board passenger',
                    );
                    if (input == null) return;
                    await _act(
                      () => _ops.manualBoard(
                        stopId: stop.id,
                        employeeId: e.id,
                        reason: input.reason,
                        authorizedBy: input.authorizedBy!,
                      ),
                    );
                  },
                  onNoShow: () async {
                    final input = await showReasonDialog(
                      context,
                      title: 'Mark ${e.employeeCode} as no-show',
                      label: 'Reason',
                      minLength: 3,
                      initial: 'Not at pickup after waiting',
                      confirmLabel: 'Mark no-show',
                    );
                    if (input == null) return;
                    await _act(
                      () => _ops.markNoShow(
                        stopId: stop.id,
                        employeeId: e.id,
                        reason: input.reason,
                      ),
                    );
                  },
                  onCorrect: () async {
                    final input = await showReasonDialog(
                      context,
                      title: 'Correct status · ${e.employeeCode}',
                      message:
                          'Resets this passenger to awaiting. The correction is recorded.',
                      confirmLabel: 'Reset status',
                    );
                    if (input == null) return;
                    await _act(
                      () => _ops.correctPassenger(
                        tripId: trip.id,
                        employeeId: e.id,
                        reason: input.reason,
                      ),
                    );
                  },
                ),
                const SizedBox(height: AppSpace.xs),
              ],
            for (final e
                in trip.absentEmployeeIds
                    .map(data.employee)
                    .whereType<Employee>()
                    .where(
                      (e) =>
                          (isPickup ? e.pickupLocationId : e.destinationId) ==
                          stop.locationId,
                    )) ...[
              Opacity(
                opacity: 0.55,
                child: AppCard(
                  color: AppColors.surfaceAlt,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.md,
                    vertical: AppSpace.sm,
                  ),
                  semanticLabel: '${e.name} not travelling (reported)',
                  child: Row(
                    children: [
                      InitialsAvatar(
                        initials: e.initials,
                        size: 40,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.name,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(
                              '${e.employeeCode} · not expected at this stop',
                              style: AppText.muted(context),
                            ),
                          ],
                        ),
                      ),
                      const StatusBadge(
                        'Not travelling (reported)',
                        tone: StatusTone.neutral,
                        dense: true,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.xs),
            ],
            if (arrived && !isPickup) ...[
              const SizedBox(height: AppSpace.sm),
              Builder(
                builder: (context) {
                  final pending = stop.alightingEmployeeIds
                      .where(
                        (id) =>
                            trip.boardedPassengerIds.contains(id) &&
                            !trip.alightedPassengerIds.contains(id),
                      )
                      .toList();
                  final sel = _dropSelection.where(pending.contains).toList();
                  return BigButton(
                    label: pending.isEmpty
                        ? 'All drop-offs recorded'
                        : (sel.isEmpty
                              ? 'Record drop-off for all (${pending.length})'
                              : 'Record drop-off (${sel.length})'),
                    icon: Icons.logout_rounded,
                    color: AppColors.teal,
                    busy: _busy,
                    onPressed: pending.isEmpty
                        ? null
                        : () async {
                            await _act(
                              () => _ops.alight(
                                stopId: stop.id,
                                employeeIds: sel.isEmpty ? pending : sel,
                              ),
                            );
                            _dropSelection.clear();
                          },
                  );
                },
              ),
            ],
            if (arrived) ...[
              const SizedBox(height: AppSpace.lg),
              if (issues.isNotEmpty) ...[
                InlineBanner(
                  tone: StatusTone.warning,
                  title: 'Passenger mismatch',
                  messages: issues,
                ),
                const SizedBox(height: AppSpace.sm),
              ],
              BigButton(
                label: 'Complete stop',
                icon: Icons.check_circle_outline_rounded,
                busy: _busy,
                onPressed: () async {
                  String? reason;
                  if (issues.isNotEmpty) {
                    final input = await showReasonDialog(
                      context,
                      title: 'Complete with mismatch?',
                      message: issues.join('\n'),
                      label: 'Reason for the mismatch',
                      confirmLabel: 'Record & complete',
                    );
                    if (input == null) return;
                    reason = input.reason;
                  }
                  setState(() => _busy = true);
                  final r = await _ops.departStop(
                    stop.id,
                    discrepancyReason: reason,
                  );
                  if (!context.mounted) return;
                  setState(() => _busy = false);
                  if (r.isOk) {
                    showToast(context, 'Stop ${stop.sequence} completed');
                    context.go('/driver/trip/${trip.id}/active');
                  } else {
                    await showResult(context, r);
                  }
                },
              ),
            ],
            if (active && !stop.isDone) ...[
              const SizedBox(height: AppSpace.sm),
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        final input = await showReasonDialog(
                          context,
                          title: 'Skip this stop?',
                          message:
                              'Skipping needs a reason and who authorized it. Waiting passengers are marked no-show and notified.',
                          requireAuthorizer: true,
                          authorizerHint: 'e.g. Fleet Manager on call',
                          confirmLabel: 'Skip stop',
                          destructive: true,
                        );
                        if (input == null) return;
                        final r = await _ops.skipStop(
                          stop.id,
                          reason: input.reason,
                          authorizedBy: input.authorizedBy!,
                        );
                        if (!context.mounted) return;
                        if (await showResult(context, r) && context.mounted) {
                          context.go('/driver/trip/${trip.id}/active');
                        }
                      },
                icon: const Icon(Icons.redo_rounded),
                label: const Text('Skip stop (authorized)'),
              ),
            ],
            const SizedBox(height: AppSpace.md),
            const SimulatedNote(
              DemoLabels.credentialDemo,
              icon: Icons.verified_user_outlined,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openScan(
    BuildContext context,
    DataView data,
    Trip trip,
    RouteStop stop,
  ) async {
    const v = VerificationService();
    final waiting = stop.boardingEmployeeIds
        .map(data.employee)
        .whereType<Employee>()
        .where(
          (e) =>
              data.trips.passengerState(trip, e.id) == PassengerState.awaiting,
        )
        .toList();
    final boarded = stop.boardingEmployeeIds
        .map(data.employee)
        .whereType<Employee>()
        .where((e) => trip.boardedPassengerIds.contains(e.id))
        .toList();
    final sample = data.employee(stop.boardingEmployeeIds.firstOrNull);
    final other = data.trips
        .all()
        .where(
          (x) =>
              x.id != trip.id &&
              x.tripCode != trip.tripCode &&
              x.employeeIds.isNotEmpty,
        )
        .firstOrNull;
    final options = <(String, String, IconData)>[
      for (final e in waiting)
        (
          'Valid pass · ${e.employeeCode} ${e.name}',
          v.qrPayload(trip, e),
          Icons.qr_code_2_rounded,
        ),
      for (final e in boarded.take(1))
        (
          'Duplicate · ${e.employeeCode} already boarded',
          v.qrPayload(trip, e),
          Icons.content_copy_rounded,
        ),
      if (sample != null)
        (
          'Expired pass (yesterday)',
          v.qrPayload(
            trip.copyWith(
              serviceDate: trip.serviceDate.subtract(const Duration(days: 1)),
            ),
            sample,
          ),
          Icons.history_toggle_off_rounded,
        ),
      if (sample != null)
        (
          'Altered / invalid code',
          '${v.qrPayload(trip, sample).substring(0, v.qrPayload(trip, sample).length - 1)}Z',
          Icons.gpp_bad_outlined,
        ),
      if (other != null && data.employee(other.employeeIds.first) != null)
        (
          'Pass for another trip (${other.tripCode})',
          v.qrPayload(other, data.employee(other.employeeIds.first)!),
          Icons.wrong_location_outlined,
        ),
    ];
    final payload = await showAppSheet<String>(
      context,
      title: 'Scan QR (demo)',
      builder: (c) => _ScanSheet(options: options),
    );
    if (payload == null || payload.trim().isEmpty) return;
    await _verify(VerificationMethod.qrDemo, payload);
  }

  Future<void> _openTpin(
    BuildContext context,
    DataView data,
    Trip trip,
    RouteStop stop,
    Employee? preset,
  ) async {
    final candidates = stop.boardingEmployeeIds
        .map(data.employee)
        .whereType<Employee>()
        .toList();
    if (candidates.isEmpty) return;
    final initial =
        preset ??
        candidates.firstWhere(
          (e) =>
              data.trips.passengerState(trip, e.id) == PassengerState.awaiting,
          orElse: () => candidates.first,
        );
    final result = await showAppSheet<(String, String)>(
      context,
      title: 'Enter T-PIN',
      builder: (c) =>
          _TpinSheet(trip: trip, candidates: candidates, initial: initial),
    );
    if (result == null) return;
    await _verify(
      VerificationMethod.tpinDemo,
      result.$2,
      employeeId: result.$1,
    );
  }
}

/// Simulated scanner: scenario picker + paste field (owns its controller).
class _ScanSheet extends StatefulWidget {
  const _ScanSheet({required this.options});
  final List<(String, String, IconData)> options;

  @override
  State<_ScanSheet> createState() => _ScanSheetState();
}

class _ScanSheetState extends State<_ScanSheet> {
  final _manual = TextEditingController();

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const InlineBanner(
        tone: StatusTone.info,
        title: 'Simulated scanner',
        message:
            'No camera is used. Pick a scenario to simulate what the scanner would read, or paste a pass code shown in the Employee app.',
      ),
      const SizedBox(height: AppSpace.sm),
      for (final o in widget.options)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: IconTile(icon: o.$3, size: 36),
          title: Text(o.$1),
          onTap: () => Navigator.pop(context, o.$2),
        ),
      const SizedBox(height: AppSpace.sm),
      TextField(
        controller: _manual,
        decoration: const InputDecoration(
          labelText: 'Paste pass code',
          hintText: 'EFM-DEMO|…',
        ),
      ),
      const SizedBox(height: AppSpace.sm),
      FilledButton(
        onPressed: () => Navigator.pop(context, _manual.text),
        child: const Text('Verify pasted code'),
      ),
    ],
  );
}

/// T-PIN entry for a chosen passenger (owns its controller).
class _TpinSheet extends StatefulWidget {
  const _TpinSheet({
    required this.trip,
    required this.candidates,
    required this.initial,
  });
  final Trip trip;
  final List<Employee> candidates;
  final Employee initial;

  @override
  State<_TpinSheet> createState() => _TpinSheetState();
}

class _TpinSheetState extends State<_TpinSheet> {
  final _pin = TextEditingController();
  late Employee _selected = widget.initial;
  bool _showHint = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DropdownButtonFormField<String>(
        initialValue: _selected.id,
        decoration: const InputDecoration(labelText: 'Passenger'),
        items: [
          for (final e in widget.candidates)
            DropdownMenuItem(
              value: e.id,
              child: Text('${e.employeeCode} · ${e.name}'),
            ),
        ],
        onChanged: (id) => setState(
          () => _selected = widget.candidates.firstWhere((e) => e.id == id),
        ),
      ),
      const SizedBox(height: AppSpace.sm),
      TextField(
        key: const Key('tpinField'),
        controller: _pin,
        autofocus: true,
        keyboardType: TextInputType.number,
        maxLength: 4,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(
          fontSize: 28,
          letterSpacing: 12,
          fontWeight: FontWeight.w700,
        ),
        textAlign: TextAlign.center,
        decoration: const InputDecoration(
          labelText: '4-digit T-PIN',
          counterText: '',
        ),
      ),
      const SizedBox(height: AppSpace.xs),
      TextButton(
        onPressed: () => setState(() => _showHint = !_showHint),
        child: Text(
          _showHint
              ? 'Demo T-PIN: ${const VerificationService().tpin(widget.trip, _selected)}'
              : 'Show demo T-PIN (testing only)',
        ),
      ),
      const SizedBox(height: AppSpace.xs),
      FilledButton(
        onPressed: () => Navigator.pop(context, (_selected.id, _pin.text)),
        child: const Text('Verify T-PIN'),
      ),
    ],
  );
}

class _OutcomeBanner extends StatelessWidget {
  const _OutcomeBanner({required this.outcome, required this.onClose});
  final VerificationOutcome outcome;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final (tone, title) = switch (outcome.status) {
      VerificationStatus.verified => (StatusTone.success, 'Verified · boarded'),
      VerificationStatus.duplicate => (
        StatusTone.warning,
        'Duplicate — not boarded again',
      ),
      VerificationStatus.expired => (
        StatusTone.warning,
        'Expired pass — not boarded',
      ),
      VerificationStatus.wrongTrip => (
        StatusTone.danger,
        'Wrong trip — not boarded',
      ),
      VerificationStatus.invalid => (
        StatusTone.danger,
        'Invalid — not boarded',
      ),
      VerificationStatus.overridden => (StatusTone.info, 'Override recorded'),
    };
    return InlineBanner(
      tone: tone,
      title: title,
      message: outcome.message,
      onClose: onClose,
    );
  }
}

class _PassengerRow extends StatelessWidget {
  const _PassengerRow({
    required this.employee,
    required this.window,
    required this.state,
    required this.pickup,
    required this.enabled,
    required this.selected,
    required this.onSelect,
    required this.onTpin,
    required this.onOverride,
    required this.onNoShow,
    required this.onCorrect,
  });

  final Employee employee;
  final String window;
  final PassengerState state;
  final bool pickup;
  final bool enabled;
  final bool selected;
  final ValueChanged<bool> onSelect;
  final VoidCallback onTpin;
  final VoidCallback onOverride;
  final VoidCallback onNoShow;
  final VoidCallback onCorrect;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final canDrop = !pickup && state == PassengerState.boarded;
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.sm,
      ),
      child: Row(
        children: [
          if (!pickup)
            Checkbox(
              value: selected,
              onChanged: enabled && canDrop
                  ? (v) => onSelect(v ?? false)
                  : null,
            )
          else
            InitialsAvatar(initials: employee.initials, size: 40),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(employee.name, style: t.titleSmall),
                Text(
                  employee.employeeCode,
                  style: t.bodySmall!.copyWith(color: AppColors.textMuted),
                ),
                Text(
                  window,
                  style: t.bodySmall!.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          StatusBadge(state.label, tone: Tones.passenger(state), dense: true),
          if (enabled)
            PopupMenuButton<String>(
              tooltip: 'Passenger actions',
              onSelected: (v) => switch (v) {
                'tpin' => onTpin(),
                'override' => onOverride(),
                'noshow' => onNoShow(),
                'correct' => onCorrect(),
                _ => null,
              },
              itemBuilder: (c) => [
                if (pickup && state == PassengerState.awaiting) ...[
                  const PopupMenuItem(
                    value: 'tpin',
                    child: Text('Verify with T-PIN'),
                  ),
                  const PopupMenuItem(
                    value: 'override',
                    child: Text('Manual override (authorized)'),
                  ),
                  const PopupMenuItem(
                    value: 'noshow',
                    child: Text('Mark no-show'),
                  ),
                ],
                if (state != PassengerState.awaiting)
                  const PopupMenuItem(
                    value: 'correct',
                    child: Text('Correct status'),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
