import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 8-point spacing scale.
abstract final class AppSpace {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 40;

  /// Mobile horizontal gutter.
  static const double gutter = 20;
  static const double sectionGap = 28;
}

abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
}

abstract final class AppShadows {
  /// The only elevation used: a soft, low shadow for floating surfaces.
  static const List<BoxShadow> soft = [
    BoxShadow(color: Color(0x0F10243A), blurRadius: 24, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x0A10243A), blurRadius: 4, offset: Offset(0, 1)),
  ];
  static const List<BoxShadow> subtle = [
    BoxShadow(color: Color(0x0A10243A), blurRadius: 10, offset: Offset(0, 2)),
  ];
}

/// Layout breakpoints (logical px).
abstract final class Breakpoints {
  static const double compact = 600;
  static const double medium = 1024;
  static const double expanded = 1280;
}

extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;
  bool get isCompact => screenWidth < Breakpoints.compact;
  bool get isMedium =>
      screenWidth >= Breakpoints.compact && screenWidth < Breakpoints.medium;
  bool get isExpanded => screenWidth >= Breakpoints.medium;
  TextTheme get text => Theme.of(this).textTheme;
  ColorScheme get colors => Theme.of(this).colorScheme;
}

/// Common text helpers with brand colors baked in.
abstract final class AppText {
  static TextStyle muted(BuildContext c) =>
      Theme.of(c).textTheme.bodySmall!.copyWith(color: AppColors.textMuted);
  static TextStyle secondary(BuildContext c) => Theme.of(
    c,
  ).textTheme.bodyMedium!.copyWith(color: AppColors.textSecondary);
  static TextStyle overline(BuildContext c) =>
      Theme.of(c).textTheme.labelSmall!.copyWith(
        color: AppColors.textMuted,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w600,
      );
  static const tabular = [FontFeature.tabularFigures()];
}
