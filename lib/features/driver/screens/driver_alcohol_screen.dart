import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/widgets.dart';
import '../../../domain/models/models.dart';
import '../driver_common.dart';

enum _Scenario { pass, fail, deviceError }

/// Breathalyzer check. No hardware exists in the prototype: the reading is
/// chosen from a simulated scenario or entered by a supervisor.
class DriverAlcoholScreen extends ConsumerStatefulWidget {
  const DriverAlcoholScreen({super.key, this.tripId});
  final String? tripId;

  @override
  ConsumerState<DriverAlcoholScreen> createState() =>
      _DriverAlcoholScreenState();
}

class _DriverAlcoholScreenState extends ConsumerState<DriverAlcoholScreen> {
  _Scenario _scenario = _Scenario.pass;
  final _supervisorReading = TextEditingController();
  final _supervisorName = TextEditingController();
  bool _busy = false;
  AlcoholTest? _last;
  List<String> _errors = const [];

  @override
  void dispose() {
    _supervisorReading.dispose();
    _supervisorName.dispose();
    super.dispose();
  }

  Future<void> _record(
    String driverId, {
    required double? reading,
    required String method,
    String note = '',
  }) async {
    setState(() => _busy = true);
    final r = await ref
        .read(servicesProvider)
        .alcohol
        .record(
          driverId: driverId,
          readingMg: reading,
          method: method,
          tripId: widget.tripId,
          note: note,
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _errors = r.errors;
      _last = r.valueOrNull;
    });
  }

  @override
  Widget build(BuildContext context) {
    final day = ref.watch(driverDayProvider);
    if (day == null) return const LoadingState();
    final data = day.data;
    final policy = data.policy;
    final t = Theme.of(context).textTheme;
    final blocked = day.alcoholFail;
    final history = data.alcoholTestsOf(day.driver.id);
    final trip = data.trips.byId(widget.tripId);

    return Scaffold(
      appBar: driverAppBar(context, 'Alcohol test'),
      body: DrivingLock(
        child: MobilePage(
          children: [
            if (!policy.alcoholMonitoringEnabled)
              const InlineBanner(
                tone: StatusTone.info,
                title: 'Alcohol monitoring is off',
                message:
                    'Your fleet policy does not require breathalyzer tests right now.',
              )
            else ...[
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    KeyValueRow(
                      label: 'Limit',
                      value:
                          '${policy.alcoholThresholdMg.toStringAsFixed(0)} mg/100 ml${policy.alcoholThresholdMg == 0 ? ' (zero tolerance)' : ''}',
                      dense: true,
                    ),
                    KeyValueRow(
                      label: 'Check point',
                      value: policy.alcoholCheckPoint.label,
                      dense: true,
                    ),
                    if (trip != null)
                      KeyValueRow(
                        label: 'Trip',
                        value: trip.tripCode,
                        dense: true,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),
              if (_errors.isNotEmpty) ...[
                InlineBanner(
                  tone: StatusTone.danger,
                  title: 'Test not recorded',
                  messages: _errors,
                ),
                const SizedBox(height: AppSpace.md),
              ],
              if (_last != null) ...[
                _ResultBanner(test: _last!),
                const SizedBox(height: AppSpace.md),
              ],
              if (blocked != null && _last?.id != blocked.id) ...[
                InlineBanner(
                  tone: StatusTone.danger,
                  title: 'Fleet Manager review required',
                  message:
                      'Failed at ${Fmt.time(blocked.testedAt)} (${blocked.readingMg.toStringAsFixed(0)} mg/100 ml). Trips are on hold — do not drive. You can retest after the Fleet Manager lifts the block.',
                ),
                const SizedBox(height: AppSpace.md),
              ] else if (day.alcoholBlockLifted && _last == null) ...[
                const InlineBanner(
                  tone: StatusTone.info,
                  title: 'Block lifted — retest required',
                  message: 'Take a new test before driving.',
                ),
                const SizedBox(height: AppSpace.md),
              ],
              if (_last?.result == AlcoholResult.pass)
                BigButton(
                  label: 'Continue',
                  icon: Icons.arrow_forward_rounded,
                  color: AppColors.driverAccent,
                  onPressed: () => context.go('/driver/home'),
                )
              else if (blocked == null) ...[
                const Overline('Connected breathalyzer (simulated)'),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'No device is connected in this prototype. Choose what the simulated device should read:',
                        style: AppText.secondary(context),
                      ),
                      const SizedBox(height: AppSpace.sm),
                      SegmentedButton<_Scenario>(
                        segments: const [
                          ButtonSegment(
                            value: _Scenario.pass,
                            label: Text('Pass 0 mg'),
                          ),
                          ButtonSegment(
                            value: _Scenario.fail,
                            label: Text('Fail 25 mg'),
                          ),
                          ButtonSegment(
                            value: _Scenario.deviceError,
                            label: Text('Error'),
                          ),
                        ],
                        selected: {_scenario},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) =>
                            setState(() => _scenario = s.first),
                      ),
                      const SizedBox(height: AppSpace.md),
                      BigButton(
                        label: _last?.result == AlcoholResult.inconclusive
                            ? 'Retest'
                            : 'Blow into breathalyzer',
                        icon: Icons.air_rounded,
                        busy: _busy,
                        onPressed: () => _record(
                          day.driver.id,
                          reading: switch (_scenario) {
                            _Scenario.pass => 0,
                            _Scenario.fail => 25,
                            _Scenario.deviceError => null,
                          },
                          method: AlcoholService.deviceSimulated,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                const Overline('Supervisor entry'),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        key: const Key('supervisorReading'),
                        controller: _supervisorReading,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Reading (mg/100 ml)',
                        ),
                      ),
                      const SizedBox(height: AppSpace.sm),
                      TextField(
                        controller: _supervisorName,
                        decoration: const InputDecoration(
                          labelText: 'Supervisor name',
                        ),
                      ),
                      const SizedBox(height: AppSpace.sm),
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () {
                                final v = double.tryParse(
                                  _supervisorReading.text.trim(),
                                );
                                if (v == null ||
                                    _supervisorName.text.trim().isEmpty) {
                                  setState(
                                    () => _errors = [
                                      'Enter the reading and the supervisor name.',
                                    ],
                                  );
                                  return;
                                }
                                _record(
                                  day.driver.id,
                                  reading: v,
                                  method: AlcoholService.supervisorEntry,
                                  note:
                                      'Entered by ${_supervisorName.text.trim()}',
                                );
                              },
                        child: const Text('Record supervisor reading'),
                      ),
                    ],
                  ),
                ),
              ],
            ],
            const SizedBox(height: AppSpace.lg),
            const Overline('History'),
            if (history.isEmpty)
              const EmptyState(
                icon: Icons.history_rounded,
                title: 'No tests yet',
                message: 'Your breathalyzer results appear here.',
                compact: true,
              )
            else
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < history.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      AlcoholTestTile(test: history[i]),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: AppSpace.md),
            const SimulatedNote(
              'Simulated breathalyzer · results are stored locally for the Fleet Manager console.',
            ),
            SizedBox(height: t.bodySmall!.fontSize),
          ],
        ),
      ),
    );
  }
}

class _ResultBanner extends StatelessWidget {
  const _ResultBanner({required this.test});
  final AlcoholTest test;

  @override
  Widget build(BuildContext context) => switch (test.result) {
    AlcoholResult.pass => InlineBanner(
      tone: StatusTone.success,
      title: 'Passed · ${test.readingMg.toStringAsFixed(0)} mg/100 ml',
      message: 'You may continue with your duties.',
    ),
    AlcoholResult.fail => InlineBanner(
      tone: StatusTone.danger,
      title: 'Fleet Manager review required',
      message:
          'Reading ${test.readingMg.toStringAsFixed(0)} mg/100 ml exceeds the limit ${test.thresholdMg.toStringAsFixed(0)}. Your trips are on hold — do not drive.',
    ),
    AlcoholResult.inconclusive => const InlineBanner(
      tone: StatusTone.warning,
      title: 'Inconclusive — retest required',
      message: 'The device did not return a valid reading. Retest now.',
    ),
  };
}

/// One alcohol test in a history list.
class AlcoholTestTile extends StatelessWidget {
  const AlcoholTestTile({super.key, required this.test});
  final AlcoholTest test;

  @override
  Widget build(BuildContext context) {
    final tone = switch (test.result) {
      AlcoholResult.pass => StatusTone.success,
      AlcoholResult.fail => StatusTone.danger,
      AlcoholResult.inconclusive => StatusTone.warning,
    };
    return ListTile(
      title: Text(Fmt.dateTime(test.testedAt)),
      subtitle: Text(
        '${test.result == AlcoholResult.inconclusive ? 'No reading' : '${test.readingMg.toStringAsFixed(0)} mg/100 ml'} · ${test.method}'
        '${test.clearedAt != null ? ' · cleared by ${test.clearedBy}' : ''}',
      ),
      trailing: StatusBadge(test.result.label, tone: tone, dense: true),
    );
  }
}
