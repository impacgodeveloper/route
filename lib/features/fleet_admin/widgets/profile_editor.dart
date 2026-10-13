import 'package:flutter/material.dart';

import '../../../core/widgets/widgets.dart';
import '../../../domain/models/models.dart';

const weightLabels = <String, (String, String)>{
  'cost': ('Operating cost', 'Prefer cheaper plans (EV/ICE ₹/km, fixed cost).'),
  'punctuality': (
    'Arrival reliability',
    'Protect arrival buffers before deadlines (punctuality).',
  ),
  'distance': ('Distance', 'Prefer fewer total kilometres.'),
  'travelTime': ('Travel time', 'Prefer fewer vehicle-minutes.'),
  'detour': (
    'Employee detour',
    'Penalize extra ride time versus a direct trip.',
  ),
  'proximity': (
    'Pickup-point proximity',
    'Configurable; no effect while pickups are at registered source points.',
  ),
  'employeePreference': (
    'Employee preferences',
    'Honor saved time/distance/detour/reliability preferences (soft).',
  ),
  'utilization': ('Utilization', 'Fill seats; fewer half-empty vehicles.'),
  'ev': ('EV preference', 'Move EV share toward the target (soft).'),
  'customerPreference': (
    'Customer preference',
    'Luxury class, vehicle type and employee preferences.',
  ),
  'safety': ('Safety (soft)', 'Hard safety rules always apply; soft extras.'),
  'guard': ('Guard requirement', 'Avoid spending guard seats unnecessarily.'),
};

/// Editor for an optimization profile's weights and core constraints.
class ProfileEditor extends StatelessWidget {
  const ProfileEditor({
    super.key,
    required this.config,
    required this.onChanged,
    this.compactWeights = false,
  });

  final OptimizationConfig config;
  final ValueChanged<OptimizationConfig> onChanged;
  final bool compactWeights;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final w = config.weights;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Weights (0–10)', style: t.titleSmall),
        Text(
          'Soft objectives only. Capacity, deadlines, availability, safety and guard policy are hard constraints and are never traded away.',
          style: AppText.muted(context),
        ),
        const SizedBox(height: AppSpace.sm),
        for (final e in weightLabels.entries)
          WeightSlider(
            label: e.value.$1,
            description: compactWeights ? null : e.value.$2,
            value: w[e.key] ?? 0,
            onChanged: (v) => onChanged(
              config.withWeight(e.key, double.parse(v.toStringAsFixed(1))),
            ),
          ),
        const SizedBox(height: AppSpace.sm),
        Text('Constraints', style: t.titleSmall),
        const SizedBox(height: AppSpace.sm),
        FormRow(
          children: [
            TimeOfDayField(
              label: 'Maximum arrival time',
              minutes: config.maximumArrivalMinutes,
              onChanged: (m) =>
                  onChanged(config.copyWith(maximumArrivalMinutes: m)),
            ),
            DropdownButtonFormField<int>(
              isExpanded: true,
              initialValue: config.minimumBufferMinutes,
              decoration: const InputDecoration(
                labelText: 'Minimum arrival buffer',
              ),
              items: [
                for (final m in const [0, 5, 10, 15, 20, 30])
                  DropdownMenuItem(value: m, child: Text('$m min')),
              ],
              onChanged: (v) =>
                  onChanged(config.copyWith(minimumBufferMinutes: v)),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        Text('Allowed vehicle types', style: t.labelMedium),
        const SizedBox(height: AppSpace.xs),
        Wrap(
          spacing: AppSpace.xs,
          runSpacing: AppSpace.xs,
          children: [
            for (final type in VehicleType.values)
              FilterChip(
                label: Text(type.label),
                selected: config.allowedVehicleTypes.contains(type),
                onSelected: (sel) {
                  final next = [...config.allowedVehicleTypes];
                  sel ? next.add(type) : next.remove(type);
                  onChanged(config.copyWith(allowedVehicleTypes: next));
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        Row(
          children: [
            Expanded(child: Text('Minimum EV share', style: t.labelMedium)),
            Text('${config.minimumEvPercentage}%', style: t.labelMedium),
          ],
        ),
        Slider(
          value: config.minimumEvPercentage.toDouble(),
          max: 100,
          divisions: 20,
          label: '${config.minimumEvPercentage}%',
          onChanged: (v) =>
              onChanged(config.copyWith(minimumEvPercentage: v.round())),
        ),
      ],
    );
  }
}
