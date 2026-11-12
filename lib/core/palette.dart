import 'package:flutter/material.dart';

/// Reactive light and dark semantic tokens exposed as a [ThemeExtension].
@immutable
class HyOpsColors extends ThemeExtension<HyOpsColors> {
  final Color bg;
  final Color surface;
  final Color surfaceSubtle;
  final Color ink;
  final Color muted;
  final Color line;
  final Color controlLine;
  final Color actionInk;
  final Color primary;
  final Color primarySoft;
  final Color onPrimary;
  final Color success;
  final Color successSoft;
  final Color danger;
  final Color dangerSoft;
  final Color info;
  final Color infoSoft;
  final Color warn;
  final Color warnSoft;
  final Color chip;
  final Color segTrack;
  final Color warmHighlight;
  final Color blueHighlight;

  const HyOpsColors({
    required this.bg,
    required this.surface,
    required this.surfaceSubtle,
    required this.ink,
    required this.muted,
    required this.line,
    required this.controlLine,
    required this.actionInk,
    required this.primary,
    required this.primarySoft,
    required this.onPrimary,
    required this.success,
    required this.successSoft,
    required this.danger,
    required this.dangerSoft,
    required this.info,
    required this.infoSoft,
    required this.warn,
    required this.warnSoft,
    required this.chip,
    required this.segTrack,
    required this.warmHighlight,
    required this.blueHighlight,
  });

  static const light = HyOpsColors(
    bg: Color(0xFFF4F6F9),
    surface: Color(0xFFFFFFFF),
    surfaceSubtle: Color(0xFFEEF2F7),
    ink: Color(0xFF131C2B),
    muted: Color(0xFF475569),
    line: Color(0xFFD5DEE8),
    controlLine: Color(0xFF7D8DA1),
    actionInk: Color(0xFF2F42A3),
    primary: Color(0xFF2F42A3),
    primarySoft: Color(0xFFE8ECFF),
    onPrimary: Color(0xFFFFFFFF),
    success: Color(0xFF166534),
    successSoft: Color(0xFFDCFCE7),
    danger: Color(0xFFB91C1C),
    dangerSoft: Color(0xFFFEE2E2),
    info: Color(0xFF0369A1),
    infoSoft: Color(0xFFE0F2FE),
    warn: Color(0xFF92400E),
    warnSoft: Color(0xFFFEF3C7),
    chip: Color(0xFFE8EDF3),
    segTrack: Color(0xFFE2E8F0),
    warmHighlight: Color(0xFFFFFBEB),
    blueHighlight: Color(0xFFF0F4FF),
  );

  static const dark = HyOpsColors(
    bg: Color(0xFF0F141E),
    surface: Color(0xFF18202E),
    surfaceSubtle: Color(0xFF20293A),
    ink: Color(0xFFF1F5F9),
    muted: Color(0xFF9FB0C7),
    line: Color(0xFF2E3A4E),
    controlLine: Color(0xFF62738D),
    actionInk: Color(0xFFB8C4FF),
    primary: Color(0xFF5B72E8),
    primarySoft: Color(0xFF232F54),
    onPrimary: Color(0xFFFFFFFF),
    success: Color(0xFF4ADE80),
    successSoft: Color(0xFF133122),
    danger: Color(0xFFF87171),
    dangerSoft: Color(0xFF3D1A1A),
    info: Color(0xFF38BDF8),
    infoSoft: Color(0xFF0E2D3D),
    warn: Color(0xFFFBBF24),
    warnSoft: Color(0xFF382A0E),
    chip: Color(0xFF232C3B),
    segTrack: Color(0xFF1E2634),
    warmHighlight: Color(0xFF2B2412),
    blueHighlight: Color(0xFF17223B),
  );

  static HyOpsColors of(BuildContext context) {
    final ext = Theme.of(context).extension<HyOpsColors>();
    if (ext != null) return ext;
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }

  @override
  HyOpsColors copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceSubtle,
    Color? ink,
    Color? muted,
    Color? line,
    Color? controlLine,
    Color? actionInk,
    Color? primary,
    Color? primarySoft,
    Color? onPrimary,
    Color? success,
    Color? successSoft,
    Color? danger,
    Color? dangerSoft,
    Color? info,
    Color? infoSoft,
    Color? warn,
    Color? warnSoft,
    Color? chip,
    Color? segTrack,
    Color? warmHighlight,
    Color? blueHighlight,
  }) => HyOpsColors(
    bg: bg ?? this.bg,
    surface: surface ?? this.surface,
    surfaceSubtle: surfaceSubtle ?? this.surfaceSubtle,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    line: line ?? this.line,
    controlLine: controlLine ?? this.controlLine,
    actionInk: actionInk ?? this.actionInk,
    primary: primary ?? this.primary,
    primarySoft: primarySoft ?? this.primarySoft,
    onPrimary: onPrimary ?? this.onPrimary,
    success: success ?? this.success,
    successSoft: successSoft ?? this.successSoft,
    danger: danger ?? this.danger,
    dangerSoft: dangerSoft ?? this.dangerSoft,
    info: info ?? this.info,
    infoSoft: infoSoft ?? this.infoSoft,
    warn: warn ?? this.warn,
    warnSoft: warnSoft ?? this.warnSoft,
    chip: chip ?? this.chip,
    segTrack: segTrack ?? this.segTrack,
    warmHighlight: warmHighlight ?? this.warmHighlight,
    blueHighlight: blueHighlight ?? this.blueHighlight,
  );

  @override
  HyOpsColors lerp(covariant ThemeExtension<HyOpsColors>? other, double t) {
    if (other is! HyOpsColors) return this;
    return HyOpsColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceSubtle: Color.lerp(surfaceSubtle, other.surfaceSubtle, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      line: Color.lerp(line, other.line, t)!,
      controlLine: Color.lerp(controlLine, other.controlLine, t)!,
      actionInk: Color.lerp(actionInk, other.actionInk, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primarySoft: Color.lerp(primarySoft, other.primarySoft, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      success: Color.lerp(success, other.success, t)!,
      successSoft: Color.lerp(successSoft, other.successSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoSoft: Color.lerp(infoSoft, other.infoSoft, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      warnSoft: Color.lerp(warnSoft, other.warnSoft, t)!,
      chip: Color.lerp(chip, other.chip, t)!,
      segTrack: Color.lerp(segTrack, other.segTrack, t)!,
      warmHighlight: Color.lerp(warmHighlight, other.warmHighlight, t)!,
      blueHighlight: Color.lerp(blueHighlight, other.blueHighlight, t)!,
    );
  }
}

/// Compatibility accessor kept aligned with [HyOpsColors]. Prefer
/// `HyOpsColors.of(context)` inside widgets so theme switches animate cleanly.
class P {
  static bool dark = false;
  static HyOpsColors get _active =>
      dark ? HyOpsColors.dark : HyOpsColors.light;

  static Color get bg => _active.bg;
  static Color get surface => _active.surface;
  static Color get surfaceSubtle => _active.surfaceSubtle;
  static Color get ink => _active.ink;
  static Color get muted => _active.muted;
  static Color get line => _active.line;
  static Color get controlLine => _active.controlLine;
  static Color get actionInk => _active.actionInk;

  static Color get primary => _active.primary;
  static Color get primarySoft => _active.primarySoft;
  static Color get success => _active.success;
  static Color get successSoft => _active.successSoft;
  static Color get danger => _active.danger;
  static Color get dangerSoft => _active.dangerSoft;
  static Color get info => _active.info;
  static Color get infoSoft => _active.infoSoft;
  static Color get warn => _active.warn;
  static Color get warnSoft => _active.warnSoft;

  static Color get chip => _active.chip;
  static Color get segTrack => _active.segTrack;
  static Color get warmHighlight => _active.warmHighlight;
  static Color get blueHighlight => _active.blueHighlight;

  /// High-visibility driver accent; always paired with [onSignal].
  static const signal = Color(0xFFFFC629);
  static const onSignal = Color(0xFF131C2B);
}

class T {
  static TextStyle displayFor(HyOpsColors c) => TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    color: c.ink,
    height: 1.15,
    letterSpacing: -0.4,
  );
  static TextStyle titleFor(HyOpsColors c) => TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: c.ink,
    height: 1.25,
    letterSpacing: -0.2,
  );
  static TextStyle subheadingFor(HyOpsColors c) => TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: c.ink,
    height: 1.3,
  );
  static TextStyle bodyFor(HyOpsColors c) =>
      TextStyle(fontSize: 15, color: c.ink, height: 1.4);
  static TextStyle bodyBoldFor(HyOpsColors c) => TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: c.ink,
    height: 1.4,
  );
  static TextStyle smallFor(HyOpsColors c) =>
      TextStyle(fontSize: 13, color: c.muted, height: 1.35);
  static TextStyle smallBoldFor(HyOpsColors c) => TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: c.muted,
    height: 1.35,
  );
  static TextStyle amountFor(HyOpsColors c) => TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: c.ink,
    height: 1.2,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  static TextStyle get display => displayFor(P._active);
  static TextStyle get title => titleFor(P._active);
  static TextStyle get subheading => subheadingFor(P._active);
  static TextStyle get body => bodyFor(P._active);
  static TextStyle get bodyBold => bodyBoldFor(P._active);
  static TextStyle get small => smallFor(P._active);
  static TextStyle get smallBold => smallBoldFor(P._active);
  static TextStyle get amount => amountFor(P._active);
}
