import 'package:flutter/material.dart';

/// Brand palette (white-first, restrained enterprise UI).
abstract final class AppColors {
  static const midnightNavy = Color(0xFF10243A);
  static const deepNavy = Color(0xFF172F4D);
  static const primary = Color(0xFF2457E6);
  static const primaryPressed = Color(0xFF1C46C7);
  static const softBlue = Color(0xFFEDF3FF);
  static const teal = Color(0xFF0D9488);
  static const softTeal = Color(0xFFE7F7F4);
  static const background = Color(0xFFF4F7FB);
  static const white = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFF8FAFD);
  static const textPrimary = Color(0xFF172B4D);
  static const textSecondary = Color(0xFF526579);
  static const textMuted = Color(0xFF718096);
  static const border = Color(0xFFDFE6EF);
  static const divider = Color(0xFFE8EDF3);

  static const success = Color(0xFF16835D);
  static const successBg = Color(0xFFE9F7EF);
  static const warning = Color(0xFFA66A00);
  static const warningBg = Color(0xFFFFF5DF);
  static const danger = Color(0xFFC0393A);
  static const dangerBg = Color(0xFFFDEEEE);
  static const info = Color(0xFF2457E6);
  static const infoBg = Color(0xFFEDF3FF);

  /// Workspace accents (used sparingly: launcher cards, shell marks).
  static const employeeAccent = primary;
  static const driverAccent = teal;
  static const employerAccent = Color(0xFF5B4FCF);
  static const fleetAccent = deepNavy;
}
