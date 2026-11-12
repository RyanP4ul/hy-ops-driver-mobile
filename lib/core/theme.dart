import 'package:flutter/material.dart';

import 'palette.dart';

ThemeData driverTheme({Brightness? brightness, String? fontFamily}) {
  final effectiveBrightness =
      brightness ?? (P.dark ? Brightness.dark : Brightness.light);
  final dark = effectiveBrightness == Brightness.dark;
  final c = dark ? HyOpsColors.dark : HyOpsColors.light;

  final colorScheme = ColorScheme.fromSeed(
    seedColor: c.primary,
    brightness: effectiveBrightness,
    surface: c.surface,
  ).copyWith(
    primary: c.primary,
    onPrimary: c.onPrimary,
    secondary: c.actionInk,
    surface: c.surface,
    onSurface: c.ink,
    error: c.danger,
    onError: Colors.white,
    outline: c.controlLine,
    outlineVariant: c.line,
  );

  return ThemeData(
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    fontFamily: fontFamily,
    brightness: effectiveBrightness,
    scaffoldBackgroundColor: c.bg,
    extensions: [c],
    colorScheme: colorScheme,
    appBarTheme: AppBarTheme(
      backgroundColor: c.surface,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: T.titleFor(c).copyWith(fontFamily: fontFamily),
      shape: Border(bottom: BorderSide(color: c.line)),
    ),
    bannerTheme: MaterialBannerThemeData(
      backgroundColor: c.infoSoft,
      contentTextStyle: T.bodyFor(c),
      leadingPadding: const EdgeInsetsDirectional.only(end: 12),
      elevation: 0,
    ),
    dividerTheme: DividerThemeData(color: c.line, space: 1, thickness: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.line),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 680),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      dragHandleColor: c.controlLine,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        minimumSize: const Size(48, 48),
        backgroundColor: c.surface,
        foregroundColor: c.muted,
        selectedBackgroundColor: c.primarySoft,
        selectedForegroundColor: c.actionInk,
        side: BorderSide(color: c.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.primarySoft,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? c.actionInk : c.muted,
          size: 22,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: fontFamily,
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? c.actionInk : c.muted,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: c.surface,
      indicatorColor: c.primarySoft,
      selectedIconTheme: IconThemeData(color: c.actionInk, size: 22),
      unselectedIconTheme: IconThemeData(color: c.muted, size: 22),
      selectedLabelTextStyle: TextStyle(
        fontFamily: fontFamily,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: c.actionInk,
      ),
      unselectedLabelTextStyle: TextStyle(
        fontFamily: fontFamily,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: c.muted,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      labelStyle: TextStyle(color: c.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c.controlLine),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c.primary, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c.controlLine),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c.danger, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: c.actionInk,
        backgroundColor: c.surface,
        side: BorderSide(color: c.controlLine),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: c.actionInk,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.surfaceSubtle,
      selectedColor: c.primarySoft,
      labelStyle: TextStyle(
        fontFamily: fontFamily,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: c.ink,
      ),
      side: BorderSide(color: c.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}
