import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../core/palette.dart';
import '../data/models.dart';

enum Tone { neutral, green, info, warn, danger }

class StatusPill extends StatelessWidget {
  final String label;
  final Tone tone;
  final bool onDark;
  const StatusPill(
    this.label, {
    super.key,
    this.tone = Tone.neutral,
    this.onDark = false,
  });

  factory StatusPill.stop(StopStatus s, {Key? key}) {
    switch (s) {
      case StopStatus.pending:
        return StatusPill('Pending', key: key);
      case StopStatus.inTransit:
        return StatusPill('In transit', key: key, tone: Tone.info);
      case StopStatus.arrived:
        return StatusPill('Arrived', key: key, tone: Tone.warn);
      case StopStatus.delivered:
        return StatusPill('Delivered', key: key, tone: Tone.green);
      case StopStatus.failed:
        return StatusPill('Failed', key: key, tone: Tone.danger);
      case StopStatus.cancelled:
        return StatusPill('Cancelled', key: key, tone: Tone.danger);
    }
  }

  factory StatusPill.trip(TripStatus s, {Key? key}) {
    switch (s) {
      case TripStatus.returning:
        return StatusPill('Returning', key: key, tone: Tone.info);
      case TripStatus.loading:
        return StatusPill('Scheduled', key: key, tone: Tone.warn);
      case TripStatus.inProgress:
        return StatusPill('In progress', key: key, tone: Tone.info);
      case TripStatus.completed:
        return StatusPill('Completed', key: key, tone: Tone.green);
      case TripStatus.cancelled:
        return StatusPill('Cancelled', key: key, tone: Tone.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      Tone.green => (P.successSoft, P.success),
      Tone.info => (P.infoSoft, P.info),
      Tone.warn => (P.warnSoft, P.warn),
      Tone.danger => (P.dangerSoft, P.danger),
      Tone.neutral => (P.chip, P.muted),
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: onDark ? Colors.white.withValues(alpha: 0.14) : bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: onDark ? Colors.white : fg,
        ),
      ),
    );
  }
}

/// White surface with a hairline border. Radius is a parameter on purpose:
/// hero surfaces are rounder than list rows.
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final double borderWidth;
  Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 8,
    this.onTap,
    this.color,
    this.borderColor,
    this.borderWidth = 1,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return Material(
      color: color ?? P.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: borderColor ?? P.line, width: borderWidth),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: 24, bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Semantics(header: true, child: Text(text, style: T.title)),
        ),
        if (trailing != null) trailing!,
      ],
    ),
  );
}

/// One segment per stop - the trip's progress is readable at a glance.
class SegmentedProgress extends StatelessWidget {
  final Trip trip;
  SegmentedProgress(this.trip, {super.key});
  @override
  Widget build(BuildContext context) {
    final cur = trip.currentIndex;
    return Row(
      children: [
        for (var i = 0; i < trip.stops.length; i++) ...[
          Expanded(
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: trip.stops[i].status == StopStatus.failed
                    ? P.danger
                    : trip.stops[i].status == StopStatus.cancelled
                    ? Color(0xFF9AA7A1)
                    : trip.stops[i].isDone
                    ? P.success
                    : i == cur && trip.status == TripStatus.inProgress
                    ? P.signal
                    : P.line,
              ),
            ),
          ),
          if (i != trip.stops.length - 1) SizedBox(width: 4),
        ],
      ],
    );
  }
}

enum BtnStyle { signal, primary, success, ghost, danger, dangerOutline, onDark }

/// Large, one-handed primary action.
class BigButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final BtnStyle style;
  BigButton(
    this.label, {
    super.key,
    this.icon,
    this.onTap,
    this.style = BtnStyle.primary,
  });

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (style) {
      BtnStyle.signal => (P.signal, P.onSignal, P.signal),
      BtnStyle.primary => (P.primary, Colors.white, P.primary),
      BtnStyle.danger => (P.danger, Colors.white, P.danger),
      BtnStyle.success => (P.success, Colors.white, P.success),
      BtnStyle.dangerOutline => (Colors.transparent, P.danger, P.danger),
      BtnStyle.onDark => (Colors.transparent, Colors.white, Color(0x66FFFFFF)),
      BtnStyle.ghost => (Colors.transparent, P.ink, P.line),
    };
    final buttonStyle = FilledButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: fg,
      minimumSize: const Size(double.infinity, 56),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide(color: border),
      textStyle: Theme.of(context).textTheme.labelLarge
          ?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
    );
    return FilledButton(
      onPressed: onTap,
      style: buttonStyle,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20),
            const SizedBox(width: 10),
          ],
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ],
      ),
    );
  }
}

/// Secondary action built on forui's FButton.
class SmallAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  SmallAction(this.label, this.icon, this.onTap, {super.key});
  @override
  Widget build(BuildContext context) => FButton(
    variant: FButtonVariant.outline,
    onPress: onTap,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 16), SizedBox(width: 8), Text(label)],
    ),
  );
}

class IconTile extends StatelessWidget {
  final IconData icon;
  final Color? bg;
  final Color? fg;
  final double size;
  IconTile(this.icon, {super.key, this.bg, this.fg, this.size = 44});
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: bg ?? P.primarySoft,
      borderRadius: BorderRadius.circular(size * 0.32),
    ),
    child: Icon(icon, size: size * 0.46, color: fg ?? P.primary),
  );
}

void toast(BuildContext context, String msg) =>
    toastWith(ScaffoldMessenger.of(context), msg);

/// Use this when the originating context may be gone (e.g. after closing a sheet).
void toastWith(ScaffoldMessengerState m, String msg) {
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: TextStyle(color: P.bg, fontWeight: FontWeight.w600),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: P.ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
}
