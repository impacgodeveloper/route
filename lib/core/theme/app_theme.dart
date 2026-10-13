import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_tokens.dart';

/// Material 3 theme customized to the brand system.
abstract final class AppTheme {
  static const fontFamily = 'Inter';

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.primary,
      onPrimary: AppColors.white,
      primaryContainer: AppColors.softBlue,
      onPrimaryContainer: AppColors.primaryPressed,
      secondary: AppColors.teal,
      onSecondary: AppColors.white,
      secondaryContainer: AppColors.softTeal,
      onSecondaryContainer: Color(0xFF0B6B63),
      tertiary: AppColors.deepNavy,
      onTertiary: AppColors.white,
      error: AppColors.danger,
      onError: AppColors.white,
      errorContainer: AppColors.dangerBg,
      onErrorContainer: AppColors.danger,
      surface: AppColors.white,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      surfaceContainerLowest: AppColors.white,
      surfaceContainerLow: AppColors.surfaceAlt,
      surfaceContainer: AppColors.surfaceAlt,
      surfaceContainerHigh: Color(0xFFF0F4F9),
      surfaceContainerHighest: Color(0xFFE9EEF5),
      outline: AppColors.border,
      outlineVariant: AppColors.divider,
      shadow: AppColors.midnightNavy,
      scrim: Color(0x6610243A),
      inverseSurface: AppColors.midnightNavy,
      onInverseSurface: AppColors.white,
      inversePrimary: Color(0xFF9DB6FF),
    );

    const base = TextTheme(
      displaySmall: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        height: 1.15,
      ),
      headlineMedium: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        height: 1.2,
      ),
      headlineSmall: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        height: 1.25,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        height: 1.3,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        height: 1.35,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.45,
      ),
      bodySmall: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w400,
        height: 1.4,
      ),
      labelLarge: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      labelMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      labelSmall: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    );
    final text = base.apply(
      fontFamily: fontFamily,
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );

    final outline = OutlineInputBorder(
      borderRadius: AppRadius.mdAll,
      borderSide: const BorderSide(color: AppColors.border),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      textTheme: text,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      dividerColor: AppColors.divider,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: AppSpace.gutter,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
        ),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgAll,
          side: BorderSide(color: AppColors.border),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style:
            FilledButton.styleFrom(
              minimumSize: const Size(64, 52),
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
              shape: const RoundedRectangleBorder(
                borderRadius: AppRadius.mdAll,
              ),
              textStyle: text.labelLarge,
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.white,
              disabledBackgroundColor: const Color(0xFFE3E9F2),
              disabledForegroundColor: AppColors.textMuted,
            ).copyWith(
              overlayColor: WidgetStateProperty.resolveWith(
                (s) => s.contains(WidgetState.pressed)
                    ? AppColors.primaryPressed.withValues(alpha: 0.4)
                    : null,
              ),
            ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(64, 52),
          elevation: 0,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          side: const BorderSide(color: AppColors.border),
          foregroundColor: AppColors.textPrimary,
          backgroundColor: AppColors.white,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          foregroundColor: AppColors.primary,
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: AppColors.textSecondary,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: 16,
        ),
        border: outline,
        enabledBorder: outline,
        disabledBorder: outline.copyWith(
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: outline.copyWith(
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
        errorBorder: outline.copyWith(
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: outline.copyWith(
          borderSide: const BorderSide(color: AppColors.danger, width: 1.6),
        ),
        labelStyle: text.bodyMedium!.copyWith(color: AppColors.textSecondary),
        floatingLabelStyle: text.bodyMedium!.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: text.bodyMedium!.copyWith(color: AppColors.textMuted),
        helperStyle: text.bodySmall!.copyWith(color: AppColors.textMuted),
        errorStyle: text.bodySmall!.copyWith(color: AppColors.danger),
        prefixIconColor: AppColors.textMuted,
        suffixIconColor: AppColors.textMuted,
        errorMaxLines: 3,
        helperMaxLines: 3,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.white,
        selectedColor: AppColors.softBlue,
        disabledColor: AppColors.surfaceAlt,
        side: const BorderSide(color: AppColors.border),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
        labelStyle: text.labelMedium!.copyWith(color: AppColors.textSecondary),
        secondaryLabelStyle: text.labelMedium!.copyWith(
          color: AppColors.primary,
        ),
        checkmarkColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        showCheckmark: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: AppColors.softBlue,
        indicatorShape: const RoundedRectangleBorder(
          borderRadius: AppRadius.mdAll,
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => text.labelSmall!.copyWith(
            fontSize: 12,
            color: s.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.textMuted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            size: 24,
            color: s.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.textMuted,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.white,
        indicatorColor: AppColors.softBlue,
        selectedIconTheme: const IconThemeData(color: AppColors.primary),
        unselectedIconTheme: const IconThemeData(color: AppColors.textMuted),
        selectedLabelTextStyle: text.labelMedium!.copyWith(
          color: AppColors.primary,
        ),
        unselectedLabelTextStyle: text.labelMedium!.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium!.copyWith(
          color: AppColors.textSecondary,
        ),
        insetPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: AppSpace.xl,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: AppColors.border,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xxl),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.midnightNavy,
        contentTextStyle: text.bodyMedium!.copyWith(color: AppColors.white),
        actionTextColor: const Color(0xFF9DB6FF),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        insetPadding: const EdgeInsets.all(AppSpace.md),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
        minVerticalPadding: 10,
        iconColor: AppColors.textSecondary,
        titleTextStyle: text.titleSmall,
        subtitleTextStyle: text.bodySmall!.copyWith(
          color: AppColors.textSecondary,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => AppColors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.primary
              : const Color(0xFFCBD5E1),
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: const BorderSide(color: Color(0xFFB8C4D3), width: 1.5),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: AppColors.white,
          selectedBackgroundColor: AppColors.softBlue,
          selectedForegroundColor: AppColors.primary,
          foregroundColor: AppColors.textSecondary,
          side: const BorderSide(color: AppColors.border),
          textStyle: text.labelMedium,
          minimumSize: const Size(0, 44),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: text.labelLarge,
        unselectedLabelStyle: text.labelLarge!.copyWith(
          fontWeight: FontWeight.w500,
        ),
        indicatorColor: AppColors.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: AppColors.divider,
        tabAlignment: TabAlignment.start,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.midnightNavy,
          borderRadius: AppRadius.smAll,
        ),
        textStyle: text.bodySmall!.copyWith(color: AppColors.white),
        waitDuration: const Duration(milliseconds: 400),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.softBlue,
        circularTrackColor: AppColors.softBlue,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        textStyle: text.bodyMedium,
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStateProperty.all(AppColors.white),
          surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
          shape: WidgetStateProperty.all(
            const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
      ),
      badgeTheme: const BadgeThemeData(
        backgroundColor: AppColors.danger,
        textColor: AppColors.white,
      ),
      datePickerTheme: const DatePickerThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
      ),
      timePickerTheme: const TimePickerThemeData(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        shape: Border(),
        collapsedShape: Border(),
        iconColor: AppColors.textSecondary,
        collapsedIconColor: AppColors.textMuted,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(const Color(0xFFC7D1DE)),
        radius: const Radius.circular(8),
        thickness: WidgetStateProperty.all(6),
      ),
    );
  }
}
