import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import 'app_card.dart';
import 'states.dart';
import 'status_badge.dart';

/// KPI tile. Values must come from computed records — never decorative.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.icon,
    this.tone = StatusTone.info,
    this.onTap,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;
  final StatusTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpace.md),
      semanticLabel: '$label: $value${caption != null ? ', $caption' : ''}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall!.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (icon != null) Icon(icon, size: 18, color: tone.foreground),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.headlineSmall!.copyWith(fontFeatures: AppText.tabular),
          ),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(
              caption!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t.bodySmall!.copyWith(color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Responsive grid of metric tiles.
class MetricGrid extends StatelessWidget {
  const MetricGrid({
    super.key,
    required this.children,
    this.minTileWidth = 200,
  });
  final List<Widget> children;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = (c.maxWidth / minTileWidth).floor().clamp(1, 6);
        final w = (c.maxWidth - (cols - 1) * AppSpace.sm) / cols;
        return Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final child in children) SizedBox(width: w, child: child),
          ],
        );
      },
    );
  }
}

/// Horizontal bar chart for computed values (no fake data).
class SimpleBarChart extends StatelessWidget {
  const SimpleBarChart({
    super.key,
    required this.values,
    this.format,
    this.color = AppColors.primary,
    this.height = 160,
    this.emptyMessage = 'No data in this period.',
  });

  final List<(String label, double value)> values;
  final String Function(double)? format;
  final Color color;
  final double height;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final max = values.fold<double>(0, (m, v) => v.$2 > m ? v.$2 : m);
    if (values.isEmpty || max <= 0) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            emptyMessage,
            style: t.bodySmall!.copyWith(color: AppColors.textMuted),
          ),
        ),
      );
    }
    return Semantics(
      label: values
          .map(
            (v) => '${v.$1}: ${format?.call(v.$2) ?? v.$2.toStringAsFixed(0)}',
          )
          .join(', '),
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, c) {
            final barW =
                ((c.maxWidth - (values.length - 1) * 6) / values.length).clamp(
                  6.0,
                  56.0,
                );
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final v in values)
                  Tooltip(
                    message:
                        '${v.$1}: ${format?.call(v.$2) ?? v.$2.toStringAsFixed(0)}',
                    child: SizedBox(
                      width: barW,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (v.$2 > 0)
                            Text(
                              format?.call(v.$2) ?? v.$2.toStringAsFixed(0),
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: t.labelSmall!.copyWith(
                                color: AppColors.textSecondary,
                                fontSize: 10,
                              ),
                            ),
                          const SizedBox(height: 4),
                          // Bar takes whatever height the labels leave, so
                          // larger text sizes never overflow.
                          Flexible(
                            child: FractionallySizedBox(
                              heightFactor: (v.$2 / max).clamp(0.02, 1.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: v.$2 > 0 ? color : AppColors.divider,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            v.$1,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: t.labelSmall!.copyWith(
                              color: AppColors.textMuted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Labelled progress bar (e.g. EV target vs actual, utilization).
class ProgressStat extends StatelessWidget {
  const ProgressStat({
    super.key,
    required this.label,
    required this.value,
    required this.valueLabel,
    this.target,
    this.color = AppColors.primary,
  });

  final String label;

  /// 0..1
  final double value;
  final String valueLabel;

  /// Optional 0..1 marker.
  final double? target;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      label: '$label $valueLabel',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: t.bodySmall!.copyWith(color: AppColors.textSecondary),
                ),
              ),
              Text(valueLabel, style: t.labelMedium),
            ],
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, c) {
              return SizedBox(
                height: 10,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: value.clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                    if (target != null)
                      Positioned(
                        left: (c.maxWidth * target!.clamp(0.0, 1.0)) - 1,
                        top: -3,
                        child: Container(
                          width: 2,
                          height: 16,
                          color: AppColors.midnightNavy,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Column definition for [AdaptiveTable].
class TableCol<T> {
  const TableCol(this.label, this.cell, {this.flex = 1, this.numeric = false});
  final String label;
  final Widget Function(T row) cell;
  final int flex;
  final bool numeric;
}

/// Table on wide screens; stacked cards on narrow screens. No overflow.
class AdaptiveTable<T> extends StatelessWidget {
  const AdaptiveTable({
    super.key,
    required this.rows,
    required this.columns,
    required this.mobileCard,
    this.onRowTap,
    this.breakpoint = 760,
    this.empty,
    this.selectedPredicate,
  });

  final List<T> rows;
  final List<TableCol<T>> columns;
  final Widget Function(T row) mobileCard;
  final void Function(T row)? onRowTap;
  final double breakpoint;
  final Widget? empty;
  final bool Function(T row)? selectedPredicate;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return empty ??
          const EmptyState(
            icon: Icons.inbox_outlined,
            title: 'Nothing here',
            message: 'No records match.',
            compact: true,
          );
    }
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < breakpoint) {
          return Column(
            children: [
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.xs),
                  child: AppCard(
                    padding: const EdgeInsets.all(AppSpace.md),
                    onTap: onRowTap == null ? null : () => onRowTap!(r),
                    borderColor: (selectedPredicate?.call(r) ?? false)
                        ? AppColors.primary
                        : AppColors.border,
                    child: mobileCard(r),
                  ),
                ),
            ],
          );
        }
        final t = Theme.of(context).textTheme;
        return AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.md,
                  vertical: 12,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(AppRadius.lg),
                  ),
                ),
                child: Row(
                  children: [
                    for (final col in columns)
                      Expanded(
                        flex: col.flex,
                        child: Text(
                          col.label.toUpperCase(),
                          textAlign: col.numeric
                              ? TextAlign.right
                              : TextAlign.left,
                          style: t.labelSmall!.copyWith(
                            color: AppColors.textMuted,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                Material(
                  color: (selectedPredicate?.call(rows[i]) ?? false)
                      ? AppColors.softBlue
                      : Colors.transparent,
                  child: InkWell(
                    onTap: onRowTap == null ? null : () => onRowTap!(rows[i]),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.md,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          for (final col in columns)
                            Expanded(
                              flex: col.flex,
                              child: Align(
                                alignment: col.numeric
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: DefaultTextStyle.merge(
                                  style: t.bodyMedium,
                                  child: col.cell(rows[i]),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Search box with clear button.
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    required this.onChanged,
    this.hint = 'Search',
    this.initial = '',
  });
  final ValueChanged<String> onChanged;
  final String hint;
  final String initial;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _c,
    onChanged: (v) {
      setState(() {});
      widget.onChanged(v);
    },
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      hintText: widget.hint,
      prefixIcon: const Icon(Icons.search_rounded),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: 14,
      ),
      suffixIcon: _c.text.isEmpty
          ? null
          : IconButton(
              tooltip: 'Clear search',
              icon: const Icon(Icons.close_rounded),
              onPressed: () {
                _c.clear();
                setState(() {});
                widget.onChanged('');
              },
            ),
    ),
  );
}

/// Horizontally scrollable filter chips.
class FilterChipBar<T> extends StatelessWidget {
  const FilterChipBar({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    required this.labelOf,
    this.countOf,
  });

  final List<T> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final String Function(T) labelOf;
  final int Function(T)? countOf;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final o in options)
          Padding(
            padding: const EdgeInsets.only(right: AppSpace.xs),
            child: ChoiceChip(
              label: Text(
                countOf == null ? labelOf(o) : '${labelOf(o)} · ${countOf!(o)}',
              ),
              selected: o == selected,
              onSelected: (_) => onSelected(o),
              labelStyle: TextStyle(
                color: o == selected
                    ? AppColors.primary
                    : AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              side: BorderSide(
                color: o == selected
                    ? AppColors.primary.withValues(alpha: 0.4)
                    : AppColors.border,
              ),
            ),
          ),
      ],
    ),
  );
}
