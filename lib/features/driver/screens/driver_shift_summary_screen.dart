import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/widgets.dart';
import '../../../domain/models/models.dart';
import '../driver_common.dart';

/// Shift summary + vehicle handover + end shift (with authorized exception).
class DriverShiftSummaryScreen extends ConsumerStatefulWidget {
  const DriverShiftSummaryScreen({super.key});

  @override
  ConsumerState<DriverShiftSummaryScreen> createState() =>
      _DriverShiftSummaryScreenState();
}

class _DriverShiftSummaryScreenState
    extends ConsumerState<DriverShiftSummaryScreen> {
  String? _parking;
  final _odo = TextEditingController();
  final _notes = TextEditingController();
  final _exReason = TextEditingController();
  final _exBy = TextEditingController();
  bool _busy = false;
  List<String> _errors = const [];

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
    final day = ref.watch(driverDayProvider);
    if (day == null) return const LoadingState();
    final ops = ref.read(servicesProvider).driverOps;
    final s = ops.shiftSummary(day.driver.id);
    final data = day.data;
    final t = Theme.of(context).textTheme;
    final ended = s.shift?.status == ShiftStatus.completed;
    final hard = s.endBlockers
        .where((b) => b.contains('in progress') || b.contains('not checked in'))
        .toList();
    final soft = s.endBlockers
        .where((b) => !hard.contains(b) && !b.contains('already ended'))
        .toList();
    _parking ??= day.vehicle?.homeParkingId;

    return Scaffold(
      appBar: driverAppBar(context, 'Shift summary'),
      body: MobilePage(
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(Fmt.weekdayLong(data.today), style: t.titleLarge),
                const SizedBox(height: AppSpace.xs),
                KeyValueRow(
                  label: 'Scheduled',
                  value: s.shift == null
                      ? '—'
                      : '${Fmt.time(s.shift!.scheduledStart)} – ${Fmt.time(s.shift!.scheduledEnd)}',
                  dense: true,
                ),
                KeyValueRow(
                  label: 'Checked in',
                  value: Fmt.time(s.shift?.actualCheckIn),
                  dense: true,
                ),
                KeyValueRow(
                  label: 'Checked out',
                  value: Fmt.time(s.shift?.actualCheckOut),
                  dense: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          MetricGrid(
            minTileWidth: 150,
            children: [
              MetricTile(
                label: 'Trips completed',
                value:
                    '${s.completedTrips}/${s.trips.where((x) => x.status != TripStatus.cancelled).length}',
                icon: Icons.route_outlined,
              ),
              MetricTile(
                label: 'Dropped off',
                value: '${s.passengersCarried}',
                icon: Icons.groups_outlined,
                tone: StatusTone.success,
              ),
              MetricTile(
                label: 'No-shows',
                value: '${s.noShows}',
                icon: Icons.person_off_outlined,
                tone: StatusTone.warning,
              ),
              MetricTile(
                label: 'Distance recorded',
                value: Fmt.km(s.distanceKm),
                icon: Icons.speed_outlined,
                tone: StatusTone.teal,
              ),
            ],
          ),
          if (s.openIncidents.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            InlineBanner(
              tone: StatusTone.info,
              title: '${s.openIncidents.length} open incident(s)',
              messages: [
                for (final i in s.openIncidents)
                  '${i.reference} · ${i.type.label} · ${i.status.label}',
              ],
            ),
          ],
          const SizedBox(height: AppSpace.lg),
          if (ended)
            InlineBanner(
              tone: StatusTone.success,
              title: 'Shift ended ${Fmt.time(s.shift!.actualCheckOut)}',
              message:
                  'Vehicle handed over at ${data.locationLabel(s.shift!.handoverParkingId)}.${s.shift!.endException != null ? ' Exception: ${s.shift!.endException}' : ''}',
            )
          else if (hard.isNotEmpty)
            InlineBanner(
              tone: StatusTone.warning,
              title: 'Cannot end shift yet',
              messages: hard,
            )
          else ...[
            if (_errors.isNotEmpty) ...[
              InlineBanner(
                tone: StatusTone.danger,
                title: 'Shift not ended',
                messages: _errors,
              ),
              const SizedBox(height: AppSpace.md),
            ],
            const Overline('Vehicle handover'),
            if (day.vehicle != null) ...[
              Builder(
                builder: (context) {
                  final v = day.vehicle!;
                  final note = data
                      .notificationsFor(UserRole.driver, day.driver.id)
                      .where(
                        (n) =>
                            n.relatedEntityType == 'vehicle' &&
                            n.relatedEntityId == v.id,
                      )
                      .firstOrNull;
                  return InlineBanner(
                    tone: note != null ? StatusTone.warning : StatusTone.info,
                    icon: Icons.local_parking_rounded,
                    title:
                        note?.title ??
                        'Home parking for Vehicle ${v.vehicleCode}',
                    message:
                        '${data.locationLabel(v.homeParkingId)}${note != null ? ' · ${note.body}' : ''}',
                  );
                },
              ),
              const SizedBox(height: AppSpace.sm),
            ],
            DropdownButtonFormField<String>(
              initialValue: _parking,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Parked at'),
              items: [
                for (final p in data.parkingLocations)
                  DropdownMenuItem(value: p.id, child: Text(p.label)),
              ],
              onChanged: (v) => setState(() => _parking = v),
            ),
            const SizedBox(height: AppSpace.sm),
            TextField(
              controller: _odo,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(
                labelText: 'End odometer (km, optional)',
                helperText: day.vehicle == null
                    ? null
                    : 'Current reading ${day.vehicle!.odometerKm.toStringAsFixed(0)} km',
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Handover notes',
                alignLabelWithHint: true,
                hintText: 'Keys, fuel/charge, cleanliness…',
              ),
            ),
            if (soft.isNotEmpty) ...[
              const SizedBox(height: AppSpace.md),
              InlineBanner(
                tone: StatusTone.warning,
                title: 'Unfinished assignments',
                messages: [
                  ...soft,
                  'Hand them back to the Fleet Manager, or record an authorized exception.',
                ],
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
                decoration: const InputDecoration(labelText: 'Authorized by'),
              ),
            ],
            const SizedBox(height: AppSpace.xl),
            BigButton(
              label: 'End shift',
              icon: Icons.logout_rounded,
              color: AppColors.deepNavy,
              busy: _busy,
              onPressed: () async {
                final ok = await showConfirmDialog(
                  context,
                  title: 'End your shift?',
                  message:
                      'You will be marked off duty. This cannot be undone from the driver app.',
                  confirmLabel: 'End shift',
                );
                if (!ok) return;
                setState(() => _busy = true);
                final r = await ops.endShift(
                  driverId: day.driver.id,
                  handoverParkingId: _parking,
                  handoverNotes: _notes.text,
                  endOdometerKm: double.tryParse(_odo.text.trim()),
                  exceptionReason: soft.isEmpty ? null : _exReason.text,
                  exceptionAuthorizedBy: soft.isEmpty ? null : _exBy.text,
                );
                if (!context.mounted) return;
                setState(() {
                  _busy = false;
                  _errors = r.errors;
                });
                if (r.isOk) {
                  showToast(context, 'Shift ended');
                  context.go('/driver/home');
                }
              },
            ),
          ],
          const SizedBox(height: AppSpace.lg),
          const Overline('Today\'s trips'),
          if (s.trips.isEmpty)
            const EmptyState(
              icon: Icons.event_busy_outlined,
              title: 'No trips today',
              message: 'Nothing was assigned for today.',
              compact: true,
            )
          else
            for (final trip in s.trips) ...[
              DriverTripCard(
                trip: trip,
                onTap: () => context.push('/driver/trip/${trip.id}'),
              ),
              const SizedBox(height: AppSpace.xs),
            ],
        ],
      ),
    );
  }
}
