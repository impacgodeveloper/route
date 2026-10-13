import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import 'employee_common.dart';
import 'sos_widgets.dart';

enum _SosState { idle, pending, sent, failed }

class EmployeeSafetyScreen extends ConsumerStatefulWidget {
  const EmployeeSafetyScreen({super.key});

  @override
  ConsumerState<EmployeeSafetyScreen> createState() =>
      _EmployeeSafetyScreenState();
}

class _EmployeeSafetyScreenState extends ConsumerState<EmployeeSafetyScreen> {
  _SosState _state = _SosState.idle;
  String? _incidentId;
  bool _dismissed = false;
  List<String> _errors = const [];
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _raise(String employeeId, String? tripId) async {
    if (_state != _SosState.failed) {
      final ok = await showConfirmDialog(
        context,
        title: 'Raise SOS (demo)?',
        message:
            'This records an emergency alert for the Fleet Manager console and your driver. ${DemoLabels.sosDemo}',
        confirmLabel: 'Raise SOS',
        destructive: true,
      );
      if (!ok) return;
    }
    setState(() => _state = _SosState.pending);
    final r = await ref
        .read(servicesProvider)
        .incidents
        .raiseSos(
          actor: Actor.employee(employeeId),
          tripId: tripId,
          note: _note.text,
        );
    if (!mounted) return;
    setState(() {
      if (r.isOk) {
        _state = _SosState.sent;
        _incidentId = r.valueOrNull!.id;
        _dismissed = false;
        _errors = const [];
      } else {
        _state = _SosState.failed;
        _errors = r.errors;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final e = ref.watch(currentEmployeeProvider);
    if (e == null) return const Scaffold(body: LoadingState());
    final t = Theme.of(context).textTheme;
    final next = nextTrip(data, e.id);
    final tripForSos =
        next != null &&
            (next.isActive || sameDay(next.trip.serviceDate, data.today))
        ? next
        : null;
    final activeId =
        _incidentId ?? (_dismissed ? null : openSosOf(data, e.id)?.id);
    final panel = _state == _SosState.pending || _state == _SosState.failed
        ? _state
        : activeId != null
        ? _SosState.sent
        : _SosState.idle;

    return EmployeeSubPage(
      title: 'Safety centre',
      children: [
        AppCard(
          color: AppColors.dangerBg,
          borderColor: AppColors.danger.withValues(alpha: 0.2),
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const IconTile(
                    icon: Icons.sos_outlined,
                    color: AppColors.danger,
                    background: Colors.white,
                    size: 48,
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Emergency SOS', style: t.titleLarge),
                        Text(
                          tripForSos == null
                              ? 'No active trip — alert will not be linked to a trip.'
                              : 'Linked to ${tripForSos.trip.tripCode}',
                          style: t.bodySmall!.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              const InlineBanner(
                tone: StatusTone.danger,
                title: 'In a real emergency',
                message: DemoLabels.sosAlternative,
                icon: Icons.call_outlined,
              ),
              const SizedBox(height: AppSpace.md),
              switch (panel) {
                _SosState.idle => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _note,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'What is happening? (optional)',
                      ),
                    ),
                    const SizedBox(height: AppSpace.sm),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        minimumSize: const Size.fromHeight(56),
                      ),
                      onPressed: () => _raise(e.id, tripForSos?.trip.id),
                      icon: const Icon(Icons.sos_rounded),
                      label: const Text('Raise SOS'),
                    ),
                  ],
                ),
                _SosState.pending => const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpace.md),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: AppColors.danger,
                        ),
                      ),
                      SizedBox(width: AppSpace.sm),
                      Expanded(child: Text('Recording alert locally…')),
                    ],
                  ),
                ),
                _SosState.sent => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InlineBanner(
                      tone: StatusTone.warning,
                      title:
                          'SOS recorded (${data.incident(activeId)?.reference ?? activeId})',
                      message:
                          '${DemoLabels.sosDemo} Recipients below were alerted inside this prototype only.',
                    ),
                    const SizedBox(height: AppSpace.md),
                    SosChainList(incidentId: activeId!),
                    const SizedBox(height: AppSpace.sm),
                    OutlinedButton(
                      onPressed: () => setState(() {
                        _state = _SosState.idle;
                        _incidentId = null;
                        _dismissed = true;
                      }),
                      child: const Text('Done'),
                    ),
                  ],
                ),
                _SosState.failed => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InlineBanner(
                      tone: StatusTone.danger,
                      title: 'SOS not recorded',
                      messages: _errors,
                    ),
                    const SizedBox(height: AppSpace.sm),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.danger,
                      ),
                      onPressed: () => _raise(e.id, tripForSos?.trip.id),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              },
            ],
          ),
        ),
        if (tripForSos != null) ...[
          const SizedBox(height: AppSpace.md),
          AppCard(
            onTap: () async {
              final v = tripForSos;
              final text =
                  'Executive Fleet (demo) — ${e.name} on ${v.trip.tripCode}, ${Fmt.weekday(v.trip.serviceDate)}. '
                  'Pickup ${Fmt.time(v.pickupTime)} at ${v.pickupLocation?.name}. Drop ${v.dropLocation?.name}. '
                  '${v.vehicle != null ? 'Vehicle ${v.vehicle!.vehicleCode} ${v.vehicle!.fictionalRegistration}, driver ${v.driver?.name}.' : 'Vehicle not yet assigned.'}';
              try {
                await Clipboard.setData(ClipboardData(text: text));
                if (context.mounted) {
                  showToast(context, 'Trip details copied — paste to share');
                }
              } catch (_) {
                if (context.mounted) {
                  showToast(
                    context,
                    'Could not access the clipboard on this device',
                    error: true,
                  );
                }
              }
            },
            child: Row(
              children: [
                const IconTile(icon: Icons.ios_share_rounded, size: 40),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Share trip details', style: t.titleSmall),
                      Text(
                        'Copies trip, vehicle and driver to share with someone you trust.',
                        style: AppText.muted(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpace.sectionGap),
        const SectionHeader(title: 'Ride safely'),
        const SizedBox(height: AppSpace.sm),
        AppCard(
          child: Column(
            children: [
              for (final (icon, tip) in const [
                (
                  Icons.verified_user_outlined,
                  'Check the vehicle ID and registration match your e-pass before boarding.',
                ),
                (
                  Icons.airline_seat_recline_normal_outlined,
                  'Always wear your seat belt.',
                ),
                (
                  Icons.qr_code_2_rounded,
                  'Board only after the driver verifies your QR or T-PIN.',
                ),
                (
                  Icons.phone_disabled_outlined,
                  'Do not ask the driver to use their phone while driving.',
                ),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, size: 20, color: AppColors.teal),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(child: Text(tip, style: t.bodyMedium)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
