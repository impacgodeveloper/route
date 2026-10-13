import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/widgets.dart';
import '../../../domain/models/models.dart';
import '../driver_common.dart';
import '../driver_v2_widgets.dart';

/// Delay / route deviation / breakdown / passenger / safety reports.
/// Failed submissions keep every field so the driver can retry.
class DriverReportScreen extends ConsumerStatefulWidget {
  const DriverReportScreen({super.key, this.initialType, this.tripId});
  final IncidentType? initialType;
  final String? tripId;

  @override
  ConsumerState<DriverReportScreen> createState() => _DriverReportScreenState();
}

class _DriverReportScreenState extends ConsumerState<DriverReportScreen> {
  static const _types = [
    IncidentType.delay,
    IncidentType.routeDeviation,
    IncidentType.breakdown,
    IncidentType.passengerIssue,
    IncidentType.safety,
    IncidentType.other,
  ];

  late IncidentType _type =
      widget.initialType != null && _types.contains(widget.initialType)
      ? widget.initialType!
      : IncidentType.delay;
  IncidentSeverity _severity = IncidentSeverity.medium;
  late String? _tripId = widget.tripId;
  final _desc = TextEditingController();
  final _minutes = TextEditingController(text: '10');
  bool _replacement = false;
  bool _busy = false;
  List<String> _errors = const [];
  Incident? _submitted;

  @override
  void dispose() {
    _desc.dispose();
    _minutes.dispose();
    super.dispose();
  }

  String _demoLocation(DataView data) {
    final trip = data.trips.byId(_tripId);
    if (trip == null) return 'Depot area (simulated)';
    final pos = ref.read(locationServiceProvider).positionOf(trip);
    return pos.available
        ? '${pos.label} (simulated)'
        : 'Along ${trip.tripCode} route (simulated)';
  }

  Future<void> _submit(String driverId, DataView data) async {
    setState(() => _busy = true);
    final r = await ref
        .read(servicesProvider)
        .incidents
        .report(
          IncidentDraft(
            type: _type,
            description: _desc.text,
            severity:
                _type == IncidentType.breakdown &&
                    _severity.index < IncidentSeverity.high.index
                ? IncidentSeverity.high
                : _severity,
            reporter: Actor.driver(driverId),
            tripId: _tripId,
            driverId: driverId,
            vehicleId:
                data.trips.byId(_tripId)?.assignedVehicleId ??
                data.driver(driverId)?.assignedVehicleId,
            demoLocationLabel: _demoLocation(data),
            replacementRequested:
                _type == IncidentType.breakdown && _replacement,
            delayMinutes: _type == IncidentType.delay
                ? int.tryParse(_minutes.text.trim())
                : null,
          ),
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _errors = r.errors;
      _submitted = r.valueOrNull;
    });
  }

  @override
  Widget build(BuildContext context) {
    final day = ref.watch(driverDayProvider);
    if (day == null) return const LoadingState();
    final data = day.data;
    final t = Theme.of(context).textTheme;
    if (_submitted != null) {
      final i = _submitted!;
      return Scaffold(
        appBar: driverAppBar(context, 'Report sent'),
        body: MobilePage(
          children: [
            const SizedBox(height: AppSpace.lg),
            const Center(
              child: IconTile(
                icon: Icons.mark_email_read_outlined,
                color: AppColors.teal,
                size: 64,
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              '${i.type.label} recorded · ${i.reference}',
              textAlign: TextAlign.center,
              style: t.headlineSmall,
            ),
            const SizedBox(height: AppSpace.md),
            const InlineBanner(
              tone: StatusTone.info,
              title: 'Local demo record',
              message: DemoLabels.incidentDemo,
            ),
            const SizedBox(height: AppSpace.sm),
            KeyValueRow(label: 'Status', value: i.status.label),
            KeyValueRow(label: 'Severity', value: i.severity.label),
            KeyValueRow(label: 'Location', value: i.demoLocationLabel ?? '—'),
            if (i.replacementRequested)
              const KeyValueRow(label: 'Replacement', value: 'Requested'),
            const SizedBox(height: AppSpace.xl),
            BigButton(
              label: _tripId != null ? 'Back to trip' : 'Back to Home',
              icon: Icons.arrow_back_rounded,
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/driver/home'),
            ),
          ],
        ),
      );
    }
    final trips = day.todayTrips.where((x) => !x.status.isTerminal).toList();
    return Scaffold(
      appBar: driverAppBar(context, 'Report an issue'),
      body: DrivingLock(
        child: MobilePage(
          children: [
            if (_errors.isNotEmpty) ...[
              InlineBanner(
                tone: StatusTone.danger,
                title: 'Not submitted',
                messages: _errors,
                actions: [
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _submit(day.driver.id, data),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
            ],
            const Overline('What happened?'),
            Wrap(
              spacing: AppSpace.xs,
              runSpacing: AppSpace.xs,
              children: [
                for (final ty in _types)
                  ChoiceChip(
                    label: Text(ty.label),
                    selected: _type == ty,
                    onSelected: (_) => setState(() => _type = ty),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            DropdownButtonFormField<String?>(
              initialValue: trips.any((x) => x.id == _tripId) ? _tripId : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Trip'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Not trip-related'),
                ),
                for (final x in trips)
                  DropdownMenuItem<String?>(
                    value: x.id,
                    child: Text('${x.tripCode} · ${x.status.label}'),
                  ),
              ],
              onChanged: (v) => setState(() => _tripId = v),
            ),
            const SizedBox(height: AppSpace.sm),
            if (_type == IncidentType.delay) ...[
              TextField(
                controller: _minutes,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Expected delay (minutes)',
                ),
              ),
              const SizedBox(height: AppSpace.sm),
            ],
            DropdownButtonFormField<IncidentSeverity>(
              initialValue: _severity,
              decoration: const InputDecoration(labelText: 'Severity'),
              items: [
                for (final s in IncidentSeverity.values)
                  DropdownMenuItem(value: s, child: Text(s.label)),
              ],
              onChanged: (v) => setState(() => _severity = v ?? _severity),
            ),
            const SizedBox(height: AppSpace.sm),
            TextField(
              controller: _desc,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: 'Description',
                alignLabelWithHint: true,
                hintText: switch (_type) {
                  IncidentType.delay =>
                    'e.g. Heavy congestion near the junction',
                  IncidentType.routeDeviation =>
                    'e.g. Road closed, taking alternate route via …',
                  IncidentType.breakdown =>
                    'e.g. Warning light on, vehicle stopped safely',
                  _ => 'Describe what happened',
                },
              ),
            ),
            if (_type == IncidentType.breakdown) ...[
              const SizedBox(height: AppSpace.sm),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _replacement,
                onChanged: (v) => setState(() => _replacement = v ?? false),
                title: const Text('Request a replacement vehicle'),
                subtitle: const Text(
                  'The vehicle is set to maintenance and the Fleet Manager is alerted.',
                ),
              ),
            ],
            const SizedBox(height: AppSpace.sm),
            AppCard(
              color: AppColors.surfaceAlt,
              padding: const EdgeInsets.all(AppSpace.md),
              child: Row(
                children: [
                  const Icon(
                    Icons.my_location_outlined,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text(
                      'Location: ${_demoLocation(data)}',
                      style: AppText.secondary(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            BigButton(
              label: 'Submit report',
              icon: Icons.send_rounded,
              color: _type == IncidentType.breakdown ? AppColors.danger : null,
              busy: _busy,
              onPressed: () => _submit(day.driver.id, data),
            ),
            const SizedBox(height: AppSpace.sm),
            const SimulatedNote(DemoLabels.incidentDemo),
          ],
        ),
      ),
    );
  }
}

enum _SosPhase { confirm, pending, done, failed }

/// SOS: confirm → pending → honest demo result with real-world alternatives.
class DriverSosScreen extends ConsumerStatefulWidget {
  const DriverSosScreen({super.key, this.tripId});
  final String? tripId;

  @override
  ConsumerState<DriverSosScreen> createState() => _DriverSosScreenState();
}

class _DriverSosScreenState extends ConsumerState<DriverSosScreen> {
  _SosPhase _phase = _SosPhase.confirm;
  String? _reference;
  String? _incidentId;
  List<String> _errors = const [];

  Future<void> _raise(String driverId) async {
    setState(() => _phase = _SosPhase.pending);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final r = await ref
        .read(servicesProvider)
        .incidents
        .raiseSos(actor: Actor.driver(driverId), tripId: widget.tripId);
    if (!mounted) return;
    setState(() {
      _phase = r.isOk ? _SosPhase.done : _SosPhase.failed;
      _reference = r.valueOrNull?.reference;
      _incidentId = r.valueOrNull?.id;
      _errors = r.errors;
    });
  }

  @override
  Widget build(BuildContext context) {
    final day = ref.watch(driverDayProvider);
    if (day == null) return const LoadingState();
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: driverAppBar(context, 'SOS'),
      body: MobilePage(
        children: [
          const SizedBox(height: AppSpace.md),
          ...switch (_phase) {
            _SosPhase.confirm => [
              const Center(
                child: IconTile(
                  icon: Icons.sos_rounded,
                  color: AppColors.danger,
                  size: 76,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Text(
                'Raise SOS?',
                textAlign: TextAlign.center,
                style: t.headlineMedium,
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                'This creates an emergency record for the Fleet Manager console and alerts passengers on your trip in the app.',
                textAlign: TextAlign.center,
                style: AppText.secondary(context),
              ),
              const SizedBox(height: AppSpace.md),
              const InlineBanner(
                tone: StatusTone.warning,
                title: 'Demo only',
                message: '${DemoLabels.sosDemo} ${DemoLabels.sosAlternative}',
              ),
              const SizedBox(height: AppSpace.xl),
              BigButton(
                label: 'Raise SOS now',
                icon: Icons.sos_rounded,
                color: AppColors.danger,
                onPressed: () => _raise(day.driver.id),
              ),
              const SizedBox(height: AppSpace.sm),
              BigButton(
                label: 'Cancel',
                outlined: true,
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go('/driver/home'),
              ),
            ],
            _SosPhase.pending => [
              const SizedBox(height: AppSpace.xxl),
              const LoadingState(message: 'Recording SOS locally…'),
            ],
            _SosPhase.done => [
              const Center(
                child: IconTile(
                  icon: Icons.check_rounded,
                  color: AppColors.danger,
                  size: 76,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Text(
                'SOS recorded${_reference != null ? ' · $_reference' : ''}',
                textAlign: TextAlign.center,
                style: t.headlineSmall,
              ),
              const SizedBox(height: AppSpace.md),
              const InlineBanner(
                tone: StatusTone.danger,
                title: 'No real emergency service was contacted',
                message: DemoLabels.sosDemo,
              ),
              const SizedBox(height: AppSpace.sm),
              const InlineBanner(
                tone: StatusTone.info,
                title: 'If this is a real emergency',
                message: DemoLabels.sosAlternative,
              ),
              const SizedBox(height: AppSpace.md),
              if (_incidentId != null) SosChainList(incidentId: _incidentId!),
              const SizedBox(height: AppSpace.xl),
              BigButton(
                label: 'Request control-room call-back (simulated)',
                icon: Icons.support_agent_rounded,
                outlined: true,
                onPressed: () async {
                  final r = await ref
                      .read(servicesProvider)
                      .support
                      .requestControlRoomContact(
                        Actor.driver(day.driver.id),
                        tripId: widget.tripId,
                      );
                  if (context.mounted) await showResult(context, r);
                },
              ),
              const SizedBox(height: AppSpace.sm),
              BigButton(
                label: 'Done',
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go('/driver/home'),
              ),
            ],
            _SosPhase.failed => [
              InlineBanner(
                tone: StatusTone.danger,
                title: 'SOS could not be recorded',
                messages: _errors,
              ),
              const SizedBox(height: AppSpace.sm),
              const InlineBanner(
                tone: StatusTone.warning,
                title: 'Use an alternative now',
                message:
                    '${DemoLabels.sosAlternative} Stay with the vehicle if it is safe to do so.',
              ),
              const SizedBox(height: AppSpace.xl),
              BigButton(
                label: 'Retry',
                icon: Icons.refresh_rounded,
                color: AppColors.danger,
                onPressed: () => _raise(day.driver.id),
              ),
            ],
          },
        ],
      ),
    );
  }
}
