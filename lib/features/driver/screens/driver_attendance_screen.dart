import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/widgets.dart';
import '../../../domain/models/models.dart';
import '../driver_common.dart';

/// Shift times, check-in, early/late, history and regularization.
class DriverAttendanceScreen extends ConsumerStatefulWidget {
  const DriverAttendanceScreen({super.key});

  @override
  ConsumerState<DriverAttendanceScreen> createState() =>
      _DriverAttendanceScreenState();
}

class _DriverAttendanceScreenState
    extends ConsumerState<DriverAttendanceScreen> {
  bool _busy = false;

  static String delta(Shift s) {
    final d = s.checkInDeltaMinutes;
    if (d == null) return 'Not checked in';
    if (d == 0) return 'On time';
    return d > 0 ? '$d min late' : '${-d} min early';
  }

  static StatusTone deltaTone(Shift s) {
    final d = s.checkInDeltaMinutes;
    if (d == null) return StatusTone.neutral;
    return d > 10 ? StatusTone.warning : StatusTone.success;
  }

  @override
  Widget build(BuildContext context) {
    final day = ref.watch(driverDayProvider);
    if (day == null) return const LoadingState();
    final shift = day.shift;
    final t = Theme.of(context).textTheme;
    final history = day.data.shiftsOf(day.driver.id);
    final ops = ref.read(servicesProvider).driverOps;
    return Scaffold(
      appBar: driverAppBar(context, 'Attendance'),
      body: MobilePage(
        children: [
          AppCard(
            padding: const EdgeInsets.all(AppSpace.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Today · ${Fmt.weekday(day.data.today)}',
                  style: AppText.overline(context),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  shift == null
                      ? '${Fmt.minutesOfDay(day.driver.shiftStartMinutes)} – ${Fmt.minutesOfDay(day.driver.shiftEndMinutes)}'
                      : '${Fmt.time(shift.scheduledStart)} – ${Fmt.time(shift.scheduledEnd)}',
                  style: t.headlineSmall,
                ),
                const SizedBox(height: AppSpace.md),
                KeyValueRow(
                  label: 'Checked in',
                  value: Fmt.time(shift?.actualCheckIn),
                ),
                KeyValueRow(
                  label: 'Checked out',
                  value: Fmt.time(shift?.actualCheckOut),
                ),
                KeyValueRow(
                  label: 'Punctuality',
                  valueWidget: shift == null
                      ? const Text('—')
                      : StatusBadge(
                          delta(shift),
                          tone: deltaTone(shift),
                          dense: true,
                        ),
                ),
                KeyValueRow(
                  label: 'Status',
                  valueWidget: StatusBadge(
                    shift?.status.label ?? 'Scheduled',
                    tone: shift == null
                        ? StatusTone.neutral
                        : Tones.shift(shift.status),
                    dense: true,
                  ),
                ),
                if (shift?.regularizationStatus != null)
                  KeyValueRow(
                    label: 'Regularization',
                    value:
                        '${shift!.regularizationStatus!.label}: ${shift.regularizationReason ?? ''}',
                  ),
                const SizedBox(height: AppSpace.md),
                if (shift?.actualCheckIn == null)
                  BigButton(
                    label: 'Check in now',
                    icon: Icons.login_rounded,
                    color: AppColors.driverAccent,
                    busy: _busy,
                    onPressed: () async {
                      setState(() => _busy = true);
                      final r = await ops.checkIn(day.driver.id);
                      if (!context.mounted) return;
                      setState(() => _busy = false);
                      await showResult(context, r);
                    },
                  )
                else ...[
                  const InlineBanner(
                    tone: StatusTone.success,
                    title: 'Already checked in',
                    message: 'Duplicate check-ins are prevented.',
                  ),
                  if (shift!.regularizationStatus !=
                          RegularizationStatus.pending &&
                      (shift.checkInDeltaMinutes ?? 0) > 0) ...[
                    const SizedBox(height: AppSpace.sm),
                    BigButton(
                      label: 'Request regularization',
                      icon: Icons.edit_calendar_outlined,
                      outlined: true,
                      onPressed: () async {
                        final input = await showReasonDialog(
                          context,
                          title: 'Request regularization',
                          message:
                              'Explain why your check-in time should be corrected. The Fleet Manager reviews the request.',
                          minLength: 10,
                          confirmLabel: 'Send request',
                        );
                        if (input == null) return;
                        final res = await ops.requestRegularization(
                          shift.id,
                          input.reason,
                        );
                        if (!context.mounted) return;
                        await showResult(context, res);
                      },
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          const Overline('History'),
          if (history.isEmpty)
            const EmptyState(
              icon: Icons.history_rounded,
              title: 'No shifts yet',
              message: 'Past shifts appear here.',
              compact: true,
            )
          else
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < history.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      title: Text(Fmt.weekday(history[i].shiftDate)),
                      subtitle: Text(
                        'In ${Fmt.time(history[i].actualCheckIn)} · Out ${Fmt.time(history[i].actualCheckOut)} · ${delta(history[i])}',
                      ),
                      trailing: StatusBadge(
                        history[i].status.label,
                        tone: Tones.shift(history[i].status),
                        dense: true,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
