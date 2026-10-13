import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

/// White surface with a hairline border — the base building block.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.lg),
    this.onTap,
    this.color = AppColors.white,
    this.borderColor = AppColors.border,
    this.radius = AppRadius.lg,
    this.shadow = false,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color color;
  final Color borderColor;
  final double radius;
  final bool shadow;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    Widget content = Padding(padding: padding, child: child);
    if (onTap != null) {
      content = InkWell(onTap: onTap, borderRadius: br, child: content);
    }
    return Semantics(
      label: semanticLabel,
      button: onTap != null,
      container: true,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: br,
          border: Border.all(color: borderColor),
          boxShadow: shadow ? AppShadows.subtle : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: br,
          clipBehavior: Clip.antiAlias,
          child: content,
        ),
      ),
    );
  }
}

/// Section title with optional subtitle and trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.padding = EdgeInsets.zero,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(title, style: t.titleMedium),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: t.bodySmall!.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Label/value pair used in detail panels.
class KeyValueRow extends StatelessWidget {
  const KeyValueRow({
    super.key,
    required this.label,
    this.value,
    this.valueWidget,
    this.icon,
    this.dense = false,
  });

  final String label;
  final String? value;
  final Widget? valueWidget;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 4 : 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: AppColors.textMuted),
            const SizedBox(width: AppSpace.sm),
          ],
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: t.bodyMedium!.copyWith(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerRight,
              child:
                  valueWidget ??
                  Text(
                    value ?? '—',
                    textAlign: TextAlign.right,
                    style: t.bodyMedium!.copyWith(fontWeight: FontWeight.w600),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Circle with initials (no photos of real people).
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({
    super.key,
    required this.initials,
    this.size = 40,
    this.color = AppColors.primary,
    this.background,
  });

  final String initials;
  final double size;
  final Color color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background ?? color.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Text(
          initials,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: size * 0.36,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

/// Rounded square icon container used consistently for leading icons.
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    this.color = AppColors.primary,
    this.background,
    this.size = 40,
  });

  final IconData icon;
  final Color color;
  final Color? background;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: background ?? color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(size * 0.3),
    ),
    child: Icon(icon, color: color, size: size * 0.5),
  );
}
