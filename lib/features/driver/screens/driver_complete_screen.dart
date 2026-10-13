import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/widgets.dart';
import '../../../domain/models/models.dart';
import '../driver_common.dart';

/// Trip completion with validation, odometer distance and exceptions.
class DriverCompleteTripScreen extends ConsumerStatefulWidget {
  const DriverCompleteTripScreen({super.key, required this.tripId});
  final String tripId;

  @override
  ConsumerState<DriverCompleteTripScreen> createState() =>
      _DriverCompleteTripScreenState();
}

class _DriverCompleteTripScreenState
    extends ConsumerState<DriverCompleteTripScreen> {
  final _odo = TextEditingController();
  final _notes = TextEditingController();
  final _exReason = TextEditingController();
  final _exBy = TextEditingController();
  bool _busy = false;
  List<String> _errors = const [];
  Trip? _done;

  @override
  void dispose() {
    _odo.dispose();
    _notes.dispose();
    _exReason.dispose();
    _exBy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final t = Theme.of(context).textTheme;
    final trip = data.trips.byId(widget.tripId);
    if (trip == null) {
      return Scaffold(
        appBar: driverAppBar(context, 'Complete trip'),
        body: const EmptyState(
          icon: Icons.search_off_rounded,
          title: 'Trip not found',
          message: 'It may have been reset.',
        ),
      );
    }
    if (_done != null || trip.status == TripStatus.completed) {
      return _success(context, data, data.trips.byId(trip.id)!);
    }
    final ops = ref.read(servicesProvider).driverOps;
    final report = ops.completionReport(trip.id);
    final rec = report.reconciliation;
    final start = trip.startOdometerKm;
    final end = double.tryParse(_odo.text.trim());
    final distance = (end != null && start != null) ? end - start : null;

    return Scaffold(
      appBar: driverAppBar(
        context,
        'Complete ${trip.tripCode}',
        fallback: '/driver/trip/${trip.id}/active',
      ),
      body: DrivingLock(
        child: MobilePage(
          children: [
            if (_errors.isNotEmpty) ...[
              InlineBanner(
                tone: StatusTone.danger,
                title: 'Trip not completed',
                messages: _errors,
              ),
              const SizedBox(height: AppSpace.md),
            ],
            const Overline('Checks'),
            AppCard(
              child: Column(
                children: [
                  _Check(
                    ok: report.openStops.isEmpty,
                    label: report.openStops.isEmpty
                        ? 'All stops completed or skipped'
                        : '${report.openStops.length} stop(s) still open',
                  ),
                  _Check(
                    ok: rec.awaiting.isEmpty,
                    label: rec.awaiting.isEmpty
                        ? 'Every passenger boarded or marked no-show'
                        : 'Not accounted for: ${rec.awaiting.join(', ')}',
                  ),
                  _Check(
                    ok: rec.stillOnboard.isEmpty,
                    label: rec.stillOnboard.isEmpty
                        ? 'Nobody left on board'
                        : 'Still on board: ${rec.stillOnboard.join(', ')}',
                  ),
                  _Check(
                    ok: rec.boarded == rec.alighted,
                    label: 'Boarded ${rec.boarded} · alighted ${rec.alighted}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.md),
            MetricGrid(
              minTileWidth: 150,
              children: [
                MetricTile(
                  label: 'Expected',
                  value: '${rec.expected}',
                  tone: StatusTone.neutral,
                ),
                MetricTile(
                  label: 'Boarded',
                  value: '${rec.boarded}',
                  tone: StatusTone.teal,
                ),
                MetricTile(
                  label: 'Alighted',
                  value: '${rec.alighted}',
                  tone: StatusTone.success,
                ),
                MetricTile(
                  label: 'No-show',
                  value: '${rec.noShow}',
                  tone: StatusTone.warning,
                ),
              ],
            ),
            const SizedBox(height: AppSpace.lg),
            const Overline('Distance'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KeyValueRow(
                    label: 'Start odometer',
                    value: start == null
                        ? 'Not recorded'
                        : '${start.toStringAsFixed(1)} km',
                    dense: true,
                  ),
                  const SizedBox(height: AppSpace.xs),
                  TextField(
                    key: const Key('endOdometer'),
                    controller: _odo,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'End odometer (km)',
                      helperText: distance == null
                          ? 'Leave empty only if unavailable — billing will then be blocked for missing distance.'
                          : 'Trip distance ${distance.toStringAsFixed(1)} km (used for billing)',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Completion notes (optional)',
                alignLabelWithHint: true,
              ),
            ),
            if (!report.canComplete) ...[
              const SizedBox(height: AppSpace.lg),
              const Overline('Authorized exception'),
              const InlineBanner(
                tone: StatusTone.warning,
                title: 'Requirements not met',
                message:
                    'Resolve the checks above, or record an authorized exception. Open stops are closed as skipped with this reason.',
              ),
              const SizedBox(height: AppSpace.sm),
              TextField(
                controller: _exReason,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Exception reason (min 10 characters)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              TextField(
                controller: _exBy,
                decoration: const InputDecoration(
                  labelText: 'Authorized by',
                  hintText: 'e.g. Fleet Manager on call',
                ),
              ),
            ],
            const SizedBox(height: AppSpace.xl),
            // Repeat the outcome next to the button so it is visible.
            if (_errors.isNotEmpty) ...[
              InlineBanner(
                tone: StatusTone.danger,
                title: 'Fix before completing',
                messages: _errors,
              ),
              const SizedBox(height: AppSpace.md),
            ],
            BigButton(
              label: 'Complete trip',
              icon: Icons.flag_rounded,
              color: AppColors.teal,
              busy: _busy,
              onPressed: () async {
                if (_odo.text.trim().isEmpty) {
                  final ok = await showConfirmDialog(
                    context,
                    title: 'Complete without distance?',
                    message:
                        'Without an end odometer reading the trip distance is missing and automatic billing will be blocked until someone records it.',
                    confirmLabel: 'Complete anyway',
                  );
                  if (!ok) return;
                }
                setState(() => _busy = true);
                final r = await ops.completeTrip(
                  tripId: trip.id,
                  driverId: trip.assignedDriverId ?? '',
                  endOdometerKm: end,
                  notes: _notes.text,
                  exceptionReason: report.canComplete ? null : _exReason.text,
                  exceptionAuthorizedBy: report.canComplete ? null : _exBy.text,
                );
                if (!mounted) return;
                setState(() {
                  _busy = false;
                  _errors = r.errors;
                  _done = r.valueOrNull;
                });
              },
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              'Completion updates the Employee, Employer and Fleet Manager workspaces.',
              style: AppText.muted(context),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: t.bodySmall!.fontSize),
          ],
        ),
      ),
    );
  }

  Widget _success(BuildContext context, DataView data, Trip trip) {
    final bill = data.billingForTrip(trip.id);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(trip.tripCode),
      ),
      body: MobilePage(
        children: [
          const SizedBox(height: AppSpace.xl),
          const Center(
            child: IconTile(
              icon: Icons.task_alt_rounded,
              color: AppColors.success,
              size: 72,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            'Trip completed',
            textAlign: TextAlign.center,
            style: t.headlineMedium,
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            '${trip.alightedPassengerIds.length} of ${trip.employeeIds.length} passengers dropped · ${Fmt.duration(trip.actualDurationMinutes)}',
            textAlign: TextAlign.center,
            style: AppText.secondary(context),
          ),
          const SizedBox(height: AppSpace.xl),
          if (bill != null)
            InlineBanner(
              tone: StatusTone.success,
              title: 'Billing generated (${bill.id})',
              message: bill.calculationNotes,
            )
          else if (trip.distanceKm == null)
            const InlineBanner(
              tone: StatusTone.warning,
              title: 'Billing blocked — distance missing',
              message:
                  'The employer admin or Fleet Manager must record the distance before this trip can be billed.',
            )
          else
            const InlineBanner(
              tone: StatusTone.info,
              title: 'Billing pending',
              message: 'No billing line was generated for this trip.',
            ),
          if (trip.completionException != null) ...[
            const SizedBox(height: AppSpace.sm),
            InlineBanner(
              tone: StatusTone.warning,
              title: 'Exception recorded',
              message: trip.completionException,
            ),
          ],
          const SizedBox(height: AppSpace.xl),
          BigButton(
            label: 'Back to Home',
            icon: Icons.home_outlined,
            onPressed: () => context.go('/driver/home'),
          ),
        ],
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.ok, required this.label});
  final bool ok;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(
          ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
          color: ok ? AppColors.success : AppColors.warning,
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    ),
  );
}
