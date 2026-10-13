import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/widgets.dart';
import '../../../domain/models/models.dart';
import '../../../domain/rules/capacity_rules.dart';
import '../../../domain/rules/trip_state_machine.dart';
import '../widgets/fleet_common.dart';
import '../widgets/plan_preview.dart';

class TripDetailPage extends ConsumerStatefulWidget {
  const TripDetailPage({
    super.key,
    required this.tripId,
    this.openReassign = false,
  });
  final String tripId;
  final bool openReassign;

  @override
  ConsumerState<TripDetailPage> createState() => _TripDetailPageState();
}

class _TripDetailPageState extends ConsumerState<TripDetailPage> {
  @override
  void initState() {
    super.initState();
    if (widget.openReassign) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final trip = ref.read(dataProvider).trips.byId(widget.tripId);
        if (mounted &&
            trip != null &&
            TripStateMachine.canAssign(trip.status)) {
          showReassignDialog(context, trip);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final trip = data.trips.byId(widget.tripId);
    if (trip == null) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Trip not found',
        message: 'It may have been removed by a demo reset.',
        actionLabel: 'Back to dispatch',
        onAction: () => context.go('/fleet/dispatch'),
      );
    }
    final t = Theme.of(context).textTheme;
    final driver = data.driver(trip.assignedDriverId);
    final vehicle = data.vehicle(trip.assignedVehicleId);
    final employer = data.employer(trip.employerId);
    final incidents = data.incidentsOfTrip(trip.id);
    final billing = data.billingForTrip(trip.id);
    final canAssign = TripStateMachine.canAssign(trip.status);
    final canCancel = TripStateMachine.canTransition(
      trip.status,
      TripStatus.cancelled,
    );
    final seats = vehicle == null
        ? null
        : CapacityRules.breakdown(vehicle, guardRequired: trip.guardRequired);

    return AdminPage(
      title: 'Trip ${trip.tripCode}',
      subtitle:
          '${employer?.name ?? trip.employerId} · ${Fmt.weekdayLong(trip.serviceDate)} · ${Fmt.time(trip.scheduledStart)}–${Fmt.time(trip.scheduledArrival)}',
      actions: [
        TextButton.icon(
          onPressed: () => context.go('/fleet/dispatch'),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Dispatch'),
        ),
        if (canCancel)
          OutlinedButton.icon(
            onPressed: () => _cancel(trip),
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Cancel trip'),
          ),
        if (canAssign)
          FilledButton.icon(
            onPressed: () => showReassignDialog(context, trip),
            icon: const Icon(Icons.swap_horiz_rounded),
            label: Text(
              trip.isAssigned ? 'Reassign' : 'Assign driver & vehicle',
            ),
          ),
      ],
      children: [
        Wrap(
          spacing: AppSpace.xs,
          runSpacing: AppSpace.xs,
          children: [
            TripStatusBadge(trip.status),
            StatusBadge(
              'Billing: ${trip.billableStatus.label}',
              tone: Tones.billable(trip.billableStatus),
            ),
            if (trip.guardRequired)
              const StatusBadge('Guard required', tone: StatusTone.info),
            if (trip.optimizationRunId != null)
              StatusBadge(
                'From ${trip.optimizationRunId}',
                tone: StatusTone.teal,
              ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        if (trip.status == TripStatus.needsAttention) ...[
          InlineBanner(
            tone: StatusTone.danger,
            title: 'Needs attention',
            message: trip.delayReason ?? 'Review this trip before it can run.',
            actions: [
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: () => showReassignDialog(context, trip),
                child: const Text('Reassign vehicle/driver'),
              ),
              if (trip.isAssigned)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 40),
                  ),
                  onPressed: () => _confirmCurrent(trip),
                  child: const Text('Keep current assignment'),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
        ] else if (trip.status == TripStatus.delayed) ...[
          InlineBanner(
            tone: StatusTone.warning,
            title: 'Delayed',
            message: trip.delayReason ?? 'Delay reported.',
          ),
          const SizedBox(height: AppSpace.md),
        ] else if (trip.status == TripStatus.cancelled) ...[
          InlineBanner(
            tone: StatusTone.danger,
            title: 'Cancelled',
            message: trip.cancellationReason ?? '',
          ),
          const SizedBox(height: AppSpace.md),
        ],
        ResponsiveSplit(
          left: PanelCard(
            title: 'Route',
            subtitle: data.trips.routeOf(trip) == null
                ? null
                : '${data.trips.routeOf(trip)!.routeCode} · ${Fmt.km(data.trips.routeOf(trip)!.estimatedDistanceKm)} est. · ${data.trips.routeOf(trip)!.variant.label}',
            child: TripRoutePreview(trip: trip),
          ),
          right: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PanelCard(
                title: 'Assignment',
                child: Column(
                  children: [
                    KeyValueRow(label: 'Driver', value: driverShort(driver)),
                    KeyValueRow(label: 'Vehicle', value: vehicleShort(vehicle)),
                    if (vehicle != null)
                      KeyValueRow(
                        label: 'Registration',
                        value: vehicle.fictionalRegistration,
                      ),
                    if (seats != null)
                      KeyValueRow(label: 'Seats', value: seats.toString()),
                    if (trip.guardRequired ||
                        (vehicle?.requiresSecurityGuard ?? false))
                      KeyValueRow(
                        label: 'Security guard',
                        value:
                            trip.guardReference ??
                            ((vehicle?.securityGuardAssigned ?? false)
                                ? 'Vehicle guard assigned'
                                : 'Not assigned'),
                      ),
                    KeyValueRow(
                      label: 'Passengers',
                      value: '${trip.employeeIds.length}',
                    ),
                    KeyValueRow(
                      label: 'Start',
                      value: Fmt.time(trip.actualStart ?? trip.scheduledStart),
                    ),
                    KeyValueRow(
                      label: 'Distance',
                      value: trip.distanceKm == null
                          ? 'Not recorded'
                          : Fmt.km(trip.distanceKm),
                    ),
                    if (billing != null)
                      KeyValueRow(
                        label: 'Billed',
                        value:
                            '${Fmt.inr(billing.totalAmount)} · ${billing.status.label}',
                      ),
                    if (trip.instructions.isNotEmpty)
                      KeyValueRow(
                        label: 'Instructions',
                        value: trip.instructions,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),
              PanelCard(
                title: 'Passengers',
                subtitle:
                    '${trip.boardedPassengerIds.length} boarded · ${trip.alightedPassengerIds.length} dropped · ${trip.noShowPassengerIds.length} no-show${trip.absentEmployeeIds.isEmpty ? '' : ' · ${trip.absentEmployeeIds.length} absent (seat released)'}',
                child: Column(
                  children: [
                    for (final id in [
                      ...trip.employeeIds,
                      ...trip.absentEmployeeIds.where(
                        (a) => !trip.employeeIds.contains(a),
                      ),
                    ])
                      _PassengerRow(trip: trip, employeeId: id),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),
              PanelCard(
                title: 'Assignment history',
                child: trip.assignmentHistory.isEmpty
                    ? Text('Not assigned yet.', style: AppText.muted(context))
                    : Column(
                        children: [
                          for (final h in trip.assignmentHistory.reversed)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.history_rounded),
                              title: Text(
                                '${h.driverId ?? '—'} · Vehicle ${h.vehicleId ?? '—'}',
                              ),
                              subtitle: Text(
                                '${Fmt.dateTime(h.at)} · ${h.actorRole.label} · ${h.reason}',
                              ),
                            ),
                        ],
                      ),
              ),
              if (incidents.isNotEmpty) ...[
                const SizedBox(height: AppSpace.md),
                PanelCard(
                  title: 'Incidents',
                  child: Column(
                    children: [
                      for (final i in incidents)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${i.reference} · ${i.type.label}'),
                          subtitle: Text(
                            i.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: StatusBadge(
                            i.status.label,
                            tone: Tones.incident(i.status),
                            dense: true,
                          ),
                          onTap: () =>
                              context.go('/fleet/monitoring/incident/${i.id}'),
                        ),
                    ],
                  ),
                ),
              ],
              if (trip.completionException != null ||
                  trip.completionNotes != null) ...[
                const SizedBox(height: AppSpace.md),
                PanelCard(
                  title: 'Completion',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (trip.completionNotes != null)
                        Text(trip.completionNotes!, style: t.bodyMedium),
                      if (trip.completionException != null)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpace.xs),
                          child: InlineBanner(
                            tone: StatusTone.warning,
                            title: 'Authorized exception',
                            message: trip.completionException,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _cancel(Trip trip) async {
    final r = await showReasonDialog(
      context,
      title: 'Cancel ${trip.tripCode}?',
      message:
          'Passengers, the driver and the employer are notified. Bookings on this trip are cancelled. This cannot be undone.',
      confirmLabel: 'Cancel trip',
      destructive: true,
    );
    if (r == null || !mounted) return;
    await runAndShow(
      context,
      ref.read(servicesProvider).assignments.cancelTrip(trip.id, r.reason),
    );
  }

  Future<void> _confirmCurrent(Trip trip) async {
    final r = await ref
        .read(servicesProvider)
        .assignments
        .commit(
          AssignmentRequest(
            tripId: trip.id,
            employerId: trip.employerId,
            serviceDate: trip.serviceDate,
            employeeIds: trip.employeeIds,
            driverId: trip.assignedDriverId,
            vehicleId: trip.assignedVehicleId,
            guardRequired: trip.guardRequired,
            guardReference: trip.guardReference,
            instructions: trip.instructions,
          ),
        );
    if (mounted) {
      await showResult(
        context,
        r,
        successMessage: 'Assignment confirmed',
        failureTitle: 'Current assignment is not valid',
      );
    }
  }
}

class _PassengerRow extends ConsumerWidget {
  const _PassengerRow({required this.trip, required this.employeeId});
  final Trip trip;
  final String employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final e = data.employee(employeeId);
    final state = data.trips.passengerState(trip, employeeId);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: InitialsAvatar(initials: e?.initials ?? '?', size: 34),
      title: Text('${e?.employeeCode ?? employeeId} · ${e?.name ?? ''}'),
      subtitle: Text(
        e == null
            ? ''
            : '${e.pickupLocationId} → ${e.destinationId} · by ${Fmt.minutesOfDay(e.requiredArrivalMinutes)}',
      ),
      trailing: trip.absentEmployeeIds.contains(employeeId)
          ? const StatusBadge(
              'Absent · seat released',
              tone: StatusTone.teal,
              dense: true,
            )
          : StatusBadge(state.label, tone: Tones.passenger(state), dense: true),
    );
  }
}

/// Reassign / assign dialog with live validation; reason required when the
/// trip already has an assignment.
Future<void> showReassignDialog(BuildContext context, Trip trip) =>
    showDialog<void>(
      context: context,
      builder: (c) => _ReassignDialog(trip: trip),
    );

class _ReassignDialog extends ConsumerStatefulWidget {
  const _ReassignDialog({required this.trip});
  final Trip trip;

  @override
  ConsumerState<_ReassignDialog> createState() => _ReassignDialogState();
}

class _ReassignDialogState extends ConsumerState<_ReassignDialog> {
  late String? _driverId = widget.trip.assignedDriverId;
  late String? _vehicleId = widget.trip.assignedVehicleId;
  final _reason = TextEditingController();
  bool _override = false;
  final _overrideReason = TextEditingController();
  late final _guardRef = TextEditingController(
    text: widget.trip.guardReference ?? '',
  );
  bool _busy = false;
  List<String> _errors = const [];

  @override
  void dispose() {
    _reason.dispose();
    _overrideReason.dispose();
    _guardRef.dispose();
    super.dispose();
  }

  AssignmentRequest get _req => AssignmentRequest(
    tripId: widget.trip.id,
    employerId: widget.trip.employerId,
    serviceDate: widget.trip.serviceDate,
    employeeIds: widget.trip.employeeIds,
    scheduledStart: widget.trip.scheduledStart,
    driverId: _driverId,
    vehicleId: _vehicleId,
    guardRequired: widget.trip.guardRequired,
    instructions: widget.trip.instructions,
    reassignReason: _reason.text,
    allowDriverOverride: _override,
    overrideReason: _override ? _overrideReason.text : null,
    guardReference: _guardRef.text,
  );

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final s = ref.read(servicesProvider).assignments;
    final v = s.validate(_req);
    final vOpts = s.vehicleOptions(_req);
    final dOpts = s.driverOptions(_req);
    final needsReason = widget.trip.isAssigned;
    final drv = data.driver(_driverId);
    final offDuty =
        drv != null &&
        (drv.status == DriverStatus.offDuty ||
            drv.status == DriverStatus.unavailable);
    return AlertDialog(
      title: Text(
        '${widget.trip.isAssigned ? 'Reassign' : 'Assign'} ${widget.trip.tripCode}',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.trip.isAssigned)
                Text(
                  'Current: ${widget.trip.assignedDriverId} · Vehicle ${widget.trip.assignedVehicleId}. The previous assignment is kept in history and both drivers are notified.',
                  style: AppText.secondary(context),
                ),
              const SizedBox(height: AppSpace.md),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _vehicleId,
                decoration: const InputDecoration(labelText: 'Vehicle'),
                items: [
                  for (final (veh, errs) in vOpts)
                    DropdownMenuItem(
                      value: veh.id,
                      child: Text(
                        '${vehicleShort(veh)} · ${CapacityRules.passengerCapacity(veh, guardRequired: widget.trip.guardRequired)} seats${errs.isEmpty ? '' : ' · blocked'}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (x) => setState(() => _vehicleId = x),
              ),
              const SizedBox(height: AppSpace.sm),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _driverId,
                decoration: const InputDecoration(labelText: 'Driver'),
                items: [
                  for (final (d, errs) in dOpts)
                    DropdownMenuItem(
                      value: d.id,
                      child: Text(
                        '${driverShort(d)} · ${d.status.label}${errs.isEmpty ? '' : ' · blocked'}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (x) => setState(() => _driverId = x),
              ),
              if (offDuty) ...[
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _override,
                  onChanged: (x) => setState(() => _override = x ?? false),
                  title: Text(
                    'Override: ${drv.driverCode} is ${drv.status.label.toLowerCase()}',
                  ),
                ),
                if (_override)
                  TextField(
                    controller: _overrideReason,
                    decoration: const InputDecoration(
                      labelText: 'Override reason',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
              ],
              if (widget.trip.guardRequired ||
                  (data.vehicle(_vehicleId)?.requiresSecurityGuard ??
                      false)) ...[
                const SizedBox(height: AppSpace.sm),
                TextField(
                  controller: _guardRef,
                  decoration: const InputDecoration(
                    labelText: 'Security guard reference',
                    helperText:
                        'Required unless the vehicle has an assigned guard.',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              if (needsReason) ...[
                const SizedBox(height: AppSpace.sm),
                TextField(
                  controller: _reason,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Reassignment reason (required)',
                    alignLabelWithHint: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: AppSpace.md),
              if (v.errors.isNotEmpty)
                InlineBanner(
                  tone: StatusTone.danger,
                  title: 'Cannot save yet',
                  messages: v.errors,
                )
              else
                const InlineBanner(
                  tone: StatusTone.success,
                  title: 'Validation passed',
                ),
              if (v.warnings.isNotEmpty) ...[
                const SizedBox(height: AppSpace.xs),
                InlineBanner(
                  tone: StatusTone.warning,
                  title: 'Warnings',
                  messages: v.warnings,
                ),
              ],
              if (_errors.isNotEmpty) ...[
                const SizedBox(height: AppSpace.xs),
                InlineBanner(
                  tone: StatusTone.danger,
                  title: 'Not saved',
                  messages: _errors,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy || !v.ok
              ? null
              : () async {
                  final nav = Navigator.of(context);
                  final messenger = ScaffoldMessenger.of(context);
                  setState(() => _busy = true);
                  final r = await s.commit(_req);
                  if (!mounted) return;
                  setState(() {
                    _busy = false;
                    _errors = r.errors;
                  });
                  if (r.isOk) {
                    nav.pop();
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          '${widget.trip.tripCode} ${needsReason ? 'reassigned' : 'assigned'}',
                        ),
                      ),
                    );
                  }
                },
          child: Text(needsReason ? 'Save reassignment' : 'Assign'),
        ),
      ],
    );
  }
}
