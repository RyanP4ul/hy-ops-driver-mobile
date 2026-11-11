import 'package:flutter/material.dart';

import 'palette.dart';

ThemeData driverTheme({String? fontFamily}) => ThemeData(
  useMaterial3: true,
  visualDensity: VisualDensity.standard,
  materialTapTargetSize: MaterialTapTargetSize.padded,
  fontFamily: fontFamily,
  brightness: P.dark ? Brightness.dark : Brightness.light,
  scaffoldBackgroundColor: P.bg,
  appBarTheme: AppBarTheme(
    backgroundColor: P.bg,
    foregroundColor: P.ink,
    elevation: 0,
    titleTextStyle: T.title.copyWith(fontFamily: fontFamily),
    scrolledUnderElevation: 0,
  ),
  bannerTheme: MaterialBannerThemeData(
    backgroundColor: P.primarySoft,
    contentTextStyle: T.body,
    leadingPadding: const EdgeInsetsDirectional.only(end: 12),
    elevation: 0,
  ),
  dividerTheme: DividerThemeData(color: P.line, space: 1),
  dialogTheme: DialogThemeData(
    backgroundColor: P.surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  ),
  bottomSheetTheme: BottomSheetThemeData(
    backgroundColor: P.surface,
    constraints: const BoxConstraints(maxWidth: 680),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
  ),
  segmentedButtonTheme: SegmentedButtonThemeData(
    style: SegmentedButton.styleFrom(
      minimumSize: const Size(48, 48),
      selectedBackgroundColor: P.primarySoft,
      selectedForegroundColor: P.ink,
      side: BorderSide(color: P.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  ),
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: P.surface,
    indicatorColor: P.primarySoft,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: P.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: P.controlLine),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: P.actionInk, width: 2),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: P.controlLine),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      foregroundColor: P.actionInk,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      minimumSize: const Size(48, 48),
      foregroundColor: P.actionInk,
    ),
  ),
  colorScheme: ColorScheme.fromSeed(
    seedColor: P.primary,
    brightness: P.dark ? Brightness.dark : Brightness.light,
    surface: P.surface,
  ).copyWith(primary: P.primary, onPrimary: Colors.white),
);
