import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/widgets/widgets.dart';
import 'safety_alcohol.dart';
import 'safety_policy.dart';
import 'safety_sos.dart';

enum SafetyTab { policy, alcohol, sos }

/// Safety & SOS: policy, breathalyzer log (simulated) and SOS escalation.
class SafetyPage extends ConsumerStatefulWidget {
  const SafetyPage({super.key, this.initialTab});
  final String? initialTab;

  @override
  ConsumerState<SafetyPage> createState() => _SafetyPageState();
}

class _SafetyPageState extends ConsumerState<SafetyPage> {
  late SafetyTab _tab = SafetyTab.values.firstWhere(
    (t) => t.name == widget.initialTab,
    orElse: () => SafetyTab.policy,
  );

  @override
  void didUpdateWidget(SafetyPage old) {
    super.didUpdateWidget(old);
    if (old.initialTab != widget.initialTab && widget.initialTab != null) {
      _tab = SafetyTab.values.firstWhere(
        (t) => t.name == widget.initialTab,
        orElse: () => _tab,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final blocked = data.alcoholTests.where((a) => a.blocking).length;
    final openSos = data.incidents
        .where((i) => i.isSos && i.status.isOpen)
        .length;
    return AdminPage(
      title: 'Safety & SOS',
      subtitle:
          'Alcohol monitoring, speed and geofence policy, and SOS escalation. Devices and telephony are simulated in this prototype.',
      children: [
        FilterChipBar<SafetyTab>(
          options: SafetyTab.values,
          selected: _tab,
          onSelected: (t) => setState(() => _tab = t),
          labelOf: (t) => switch (t) {
            SafetyTab.policy => 'Policy',
            SafetyTab.alcohol =>
              blocked == 0
                  ? 'Alcohol tests'
                  : 'Alcohol tests · $blocked blocked',
            SafetyTab.sos =>
              openSos == 0
                  ? 'SOS escalations'
                  : 'SOS escalations · $openSos open',
          },
        ),
        const SizedBox(height: AppSpace.md),
        switch (_tab) {
          SafetyTab.policy => const SafetyPolicyTab(),
          SafetyTab.alcohol => const SafetyAlcoholTab(),
          SafetyTab.sos => const SafetySosTab(),
        },
      ],
    );
  }
}
