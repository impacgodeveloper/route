import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../utils/formatters.dart';

/// Read-only field that opens a time picker; value is minutes of day.
class TimeOfDayField extends StatelessWidget {
  const TimeOfDayField({
    super.key,
    required this.label,
    required this.minutes,
    required this.onChanged,
    this.helper,
    this.errorText,
    this.enabled = true,
  });

  final String label;
  final int? minutes;
  final ValueChanged<int> onChanged;
  final String? helper;
  final String? errorText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: AppRadius.mdAll,
      onTap: !enabled
          ? null
          : () async {
              final m = minutes ?? 540;
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
                initialEntryMode: TimePickerEntryMode.dial,
              );
              if (picked != null) onChanged(picked.hour * 60 + picked.minute);
            },
      child: InputDecorator(
        isEmpty: minutes == null,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          errorText: errorText,
          enabled: enabled,
          suffixIcon: const Icon(Icons.schedule_rounded),
        ),
        child: Text(
          minutes == null ? '' : Fmt.minutesOfDay(minutes!),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}

/// Read-only field that opens a date picker.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.firstDate,
    required this.lastDate,
    this.helper,
    this.errorText,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final DateTime firstDate;
  final DateTime lastDate;
  final String? helper;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: AppRadius.mdAll,
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? firstDate,
          firstDate: firstDate,
          lastDate: lastDate,
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        isEmpty: value == null,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          errorText: errorText,
          suffixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        child: Text(
          value == null ? '' : Fmt.weekday(value),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}

/// Labelled 0–10 weight slider used by optimization settings.
class WeightSlider extends StatelessWidget {
  const WeightSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.description,
    this.max = 10,
    this.divisions = 20,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final String? description;
  final double max;
  final int divisions;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: t.titleSmall)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.softBlue,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                value.toStringAsFixed(1),
                style: t.labelMedium!.copyWith(
                  color: AppColors.primary,
                  fontFeatures: AppText.tabular,
                ),
              ),
            ),
          ],
        ),
        if (description != null)
          Text(
            description!,
            style: t.bodySmall!.copyWith(color: AppColors.textMuted),
          ),
        Slider(
          value: value.clamp(0, max),
          max: max,
          divisions: divisions,
          label: value.toStringAsFixed(1),
          semanticFormatterCallback: (v) => '$label ${v.toStringAsFixed(1)}',
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Two-column responsive form row (stacks on narrow widths).
class FormRow extends StatelessWidget {
  const FormRow({super.key, required this.children, this.breakpoint = 560});
  final List<Widget> children;
  final double breakpoint;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      if (c.maxWidth < breakpoint) {
        return Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpace.sm),
              children[i],
            ],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpace.sm),
            Expanded(child: children[i]),
          ],
        ],
      );
    },
  );
}
