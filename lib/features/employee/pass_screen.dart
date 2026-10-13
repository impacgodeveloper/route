import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import 'employee_common.dart';

/// Demo boarding credential. Non-production; payload/PIN never logged.
class EmployeePassScreen extends ConsumerStatefulWidget {
  const EmployeePassScreen({super.key, required this.tripId});
  final String tripId;

  @override
  ConsumerState<EmployeePassScreen> createState() => _EmployeePassScreenState();
}

class _EmployeePassScreenState extends ConsumerState<EmployeePassScreen> {
  bool _showPin = false;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final e = ref.watch(currentEmployeeProvider);
    final trip = data.trips.byId(widget.tripId);
    final t = Theme.of(context).textTheme;
    if (e == null) return const Scaffold(body: LoadingState());
    if (trip == null || !trip.employeeIds.contains(e.id)) {
      return EmployeeSubPage(
        title: 'E-pass',
        children: [
          EmptyState(
            icon: Icons.qr_code_2_rounded,
            title: 'Pass not available',
            message: trip != null && trip.absentEmployeeIds.contains(e.id)
                ? 'You marked yourself absent for this trip — your seat was released.'
                : 'You are not on this trip.',
            actionLabel: 'Back to my trips',
            onAction: () => context.go('/employee/trips'),
          ),
        ],
      );
    }
    final view = EmployeeTripView(data, trip, e.id);
    final verifier = ref.read(servicesProvider).verification;
    final expired = verifier.isExpired(trip, data.now);
    final cancelled = trip.status == TripStatus.cancelled;
    final valid = !expired && !cancelled && trip.status != TripStatus.completed;
    final state = view.state;
    final futureDay = dateOnly(trip.serviceDate).isAfter(data.today);

    return EmployeeSubPage(
      title: 'E-pass',
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: AppRadius.xlAll,
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadows.soft,
          ),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpace.lg),
                decoration: const BoxDecoration(
                  color: AppColors.midnightNavy,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(AppRadius.xl),
                  ),
                ),
                child: Row(
                  children: [
                    InitialsAvatar(
                      initials: e.initials,
                      color: Colors.white,
                      background: Colors.white.withValues(alpha: 0.14),
                      size: 44,
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.name,
                            style: t.titleMedium!.copyWith(color: Colors.white),
                          ),
                          Text(
                            '${e.employeeCode} · ${trip.tripCode}',
                            style: t.bodySmall!.copyWith(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    const DemoBadge(label: 'DEMO PASS', onDark: true),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpace.lg),
                child: Column(
                  children: [
                    Semantics(
                      label: valid
                          ? 'Demo boarding QR code for ${trip.tripCode}'
                          : 'Pass not valid',
                      image: true,
                      child: Opacity(
                        opacity: valid ? 1 : 0.18,
                        child: Container(
                          padding: const EdgeInsets.all(AppSpace.sm),
                          decoration: BoxDecoration(
                            borderRadius: AppRadius.lgAll,
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: QrImageView(
                            data: verifier.qrPayload(trip, e),
                            size: 200,
                            backgroundColor: Colors.white,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: AppColors.midnightNavy,
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: AppColors.midnightNavy,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpace.md),
                    if (!valid)
                      InlineBanner(
                        tone: StatusTone.neutral,
                        title: cancelled
                            ? 'Trip cancelled'
                            : (expired ? 'Pass expired' : 'Trip completed'),
                        message: cancelled
                            ? 'This pass can no longer be used.'
                            : 'Passes are valid only on the service date (${Fmt.date(trip.serviceDate)}).',
                      )
                    else ...[
                      Text('T-PIN', style: AppText.overline(context)),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _showPin
                                ? verifier.tpin(trip, e).split('').join(' ')
                                : '• • • •',
                            style: t.headlineMedium!.copyWith(
                              letterSpacing: 4,
                              fontFeatures: AppText.tabular,
                            ),
                          ),
                          const SizedBox(width: AppSpace.xs),
                          IconButton(
                            tooltip: _showPin ? 'Hide T-PIN' : 'Reveal T-PIN',
                            onPressed: () =>
                                setState(() => _showPin = !_showPin),
                            icon: Icon(
                              _showPin
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ],
                      ),
                      if (futureDay)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Becomes valid on ${Fmt.weekday(trip.serviceDate)}.',
                            style: AppText.muted(context),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.lg,
                  vertical: AppSpace.sm,
                ),
                child: Column(
                  children: [
                    KeyValueRow(
                      label: 'Boarding status',
                      valueWidget: StatusBadge(
                        passengerStateLabel(state),
                        tone: Tones.passenger(state),
                      ),
                    ),
                    KeyValueRow(
                      label: 'Date',
                      value: Fmt.weekday(trip.serviceDate),
                    ),
                    KeyValueRow(
                      label: 'Pickup',
                      value:
                          '${Fmt.time(view.pickupTime)} · ${view.pickupLocation?.name ?? '—'}',
                    ),
                    KeyValueRow(
                      label: view.pickup?.actualArrival == null
                          ? 'Pickup window'
                          : 'Picked up',
                      value: view.pickup?.actualArrival == null
                          ? pickupWindowText(
                              view.pickupTime,
                              e.toleranceMinutes(
                                data.employer(trip.employerId),
                              ),
                            )
                          : '${Fmt.time(view.pickup!.actualArrival)} · ${ToleranceRules.describe(view.pickup!.actualArrival!, view.pickupTime, e.toleranceMinutes(data.employer(trip.employerId)))}',
                    ),
                    KeyValueRow(
                      label: 'Destination',
                      value: view.dropLocation?.name ?? '—',
                    ),
                    KeyValueRow(
                      label: 'Vehicle',
                      value: view.vehicle == null
                          ? 'Not yet assigned'
                          : 'Vehicle ${view.vehicle!.vehicleCode} · ${view.vehicle!.fictionalRegistration}',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        const InlineBanner(
          tone: StatusTone.warning,
          title: DemoLabels.credentialDemo,
          message:
              'Show the QR code or tell your driver the T-PIN at pickup. Boarding status updates when the driver verifies you.',
        ),
      ],
    );
  }
}
