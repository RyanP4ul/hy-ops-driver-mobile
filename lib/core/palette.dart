import 'package:flutter/material.dart';

/// Design tokens with light + dark values. Every colour except [signal] is a
/// getter that reads [dark], which AppState sets from the saved theme mode
/// (and the phone's brightness when the mode is "System").
class P {
  static bool dark = false;
  static Color _c(int light, int dk) => Color(dark ? dk : light);

  static Color get bg => _c(0xFFF3F5F8, 0xFF111622);
  static Color get surface => _c(0xFFFFFFFF, 0xFF1B2230);
  static Color get ink => _c(0xFF192335, 0xFFEDF1F7);
  static Color get muted => _c(0xFF4E5C70, 0xFFA9B6C8);
  static Color get line => _c(0xFFD6DEE9, 0xFF354155);
  static Color get controlLine => _c(0xFF78879C, 0xFF78879C);
  static Color get actionInk => _c(0xFF3444A5, 0xFFBBC5FF);

  static Color get primary => _c(0xFF3444A5, 0xFF495DC5);
  static Color get primarySoft => _c(0xFFE5E9FF, 0xFF293555);
  static Color get success => _c(0xFF1F7A4D, 0xFF3FBF82);
  static Color get successSoft => _c(0xFFDDF1E6, 0xFF123222);
  static Color get danger => _c(0xFFAF3024, 0xFFF2705E);
  static Color get dangerSoft => _c(0xFFF8E1DC, 0xFF3A1E1A);
  static Color get info => _c(0xFF0E7490, 0xFF3CB7D3);
  static Color get infoSoft => _c(0xFFD9F1F6, 0xFF0F2F38);
  static Color get warn => _c(0xFF795200, 0xFFE9B949);
  static Color get warnSoft => _c(0xFFFFF0C7, 0xFF3A2F10);

  // Neutral helpers
  static Color get chip => _c(0xFFE8ECEA, 0xFF232B33);
  static Color get segTrack => _c(0xFFE4E9E6, 0xFF1E252D);
  static Color get warmHighlight => _c(0xFFFFFAE8, 0xFF2A2511);
  static Color get blueHighlight => _c(0xFFF2F6FF, 0xFF152038);

  /// Hazard yellow: the same in both themes, always paired with [onSignal].
  static const signal = Color(0xFFFFC629);
  static const onSignal = Color(0xFF192335);
}

class T {
  static TextStyle get display => TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: P.ink,
    height: 1.1,
    letterSpacing: -0.5,
  );
  static TextStyle get title => TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: P.ink,
    height: 1.2,
    letterSpacing: -0.3,
  );
  static TextStyle get body =>
      TextStyle(fontSize: 15, color: P.ink, height: 1.35);
  static TextStyle get bodyBold => TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: P.ink,
    height: 1.35,
  );
  static TextStyle get small =>
      TextStyle(fontSize: 13, color: P.muted, height: 1.35);
  static TextStyle get smallBold =>
      TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: P.muted);
}
