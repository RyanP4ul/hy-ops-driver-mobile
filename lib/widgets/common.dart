import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../core/icons.dart';
import '../core/palette.dart';
import '../data/models.dart';
import '../services/external_actions.dart';

enum Tone { neutral, green, info, warn, danger }

class StatusPill extends StatelessWidget {
  final String label;
  final Tone tone;
  final bool onDark;
  final IconData? icon;

  const StatusPill(
    this.label, {
    super.key,
    this.tone = Tone.neutral,
    this.onDark = false,
    this.icon,
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
        return StatusPill(
          'Delivered',
          key: key,
          tone: Tone.green,
          icon: Ic.check,
        );
      case StopStatus.failed:
        return StatusPill('Failed', key: key, tone: Tone.danger, icon: Ic.fail);
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
        return StatusPill(
          'Completed',
          key: key,
          tone: Tone.green,
          icon: Ic.check,
        );
      case TripStatus.cancelled:
        return StatusPill('Cancelled', key: key, tone: Tone.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = HyOpsColors.of(context);
    final (bg, fg, border) = switch (tone) {
      Tone.green => (
        c.successSoft,
        c.success,
        c.success.withValues(alpha: 0.25),
      ),
      Tone.info => (c.infoSoft, c.info, c.info.withValues(alpha: 0.25)),
      Tone.warn => (c.warnSoft, c.warn, c.warn.withValues(alpha: 0.25)),
      Tone.danger => (
        c.dangerSoft,
        c.danger,
        c.danger.withValues(alpha: 0.25),
      ),
      Tone.neutral => (c.surfaceSubtle, c.muted, c.line),
    };
    final effectiveFg = onDark ? Colors.white : fg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: onDark ? Colors.white.withValues(alpha: 0.14) : bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: onDark ? Colors.white.withValues(alpha: 0.25) : border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: effectiveFg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.2,
                color: effectiveFg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Crisp surface card with a 1px hairline border and optional left accent.
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final double borderWidth;
  final Color? accentColor;

  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 12,
    this.onTap,
    this.color,
    this.borderColor,
    this.borderWidth = 1,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = HyOpsColors.of(context);
    final padded = Padding(padding: padding, child: child);
    final inner = accentColor == null
        ? padded
        : IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: accentColor),
                Expanded(child: padded),
              ],
            ),
          );
    return Material(
      color: color ?? c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: borderColor ?? c.line, width: borderWidth),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? inner : InkWell(onTap: onTap, child: inner),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const SectionTitle(
    this.text, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.only(top: 20, bottom: 10),
  });

  @override
  Widget build(BuildContext context) {
    final c = HyOpsColors.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(text, style: T.titleFor(c)),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// One segment per stop - the trip's progress is readable at a glance.
class SegmentedProgress extends StatelessWidget {
  final Trip trip;
  const SegmentedProgress(this.trip, {super.key});

  @override
  Widget build(BuildContext context) {
    if (trip.stops.isEmpty) return const SizedBox.shrink();
    final c = HyOpsColors.of(context);
    final cur = trip.currentIndex;
    return Row(
      children: [
        for (var i = 0; i < trip.stops.length; i++) ...[
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: trip.stops[i].status == StopStatus.failed
                    ? c.danger
                    : trip.stops[i].status == StopStatus.cancelled
                    ? c.controlLine
                    : trip.stops[i].isDone
                    ? c.success
                    : i == cur && trip.status == TripStatus.inProgress
                    ? c.primary
                    : c.line,
              ),
            ),
          ),
          if (i != trip.stops.length - 1) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

enum BtnStyle { signal, primary, success, ghost, danger, dangerOutline, onDark }

/// Primary full-width action button built cleanly on Material 3 [FilledButton].
class BigButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final BtnStyle style;
  final bool busy;

  const BigButton(
    this.label, {
    super.key,
    this.icon,
    this.onTap,
    this.style = BtnStyle.primary,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = HyOpsColors.of(context);
    final (bg, fg, border) = switch (style) {
      BtnStyle.signal => (P.signal, P.onSignal, P.signal),
      BtnStyle.primary => (c.primary, c.onPrimary, c.primary),
      BtnStyle.danger => (c.danger, Colors.white, c.danger),
      BtnStyle.success => (c.success, Colors.white, c.success),
      BtnStyle.dangerOutline => (Colors.transparent, c.danger, c.danger),
      BtnStyle.onDark => (
        Colors.transparent,
        Colors.white,
        const Color(0x66FFFFFF),
      ),
      BtnStyle.ghost => (c.surface, c.ink, c.controlLine),
    };
    final effectiveTap = busy ? null : onTap;
    final buttonStyle = FilledButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: fg,
      minimumSize: const Size(double.infinity, 52),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide(
        color: effectiveTap == null && style == BtnStyle.primary
            ? Colors.transparent
            : border,
      ),
      textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    );
    return FilledButton(
      onPressed: effectiveTap,
      style: buttonStyle,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (busy) ...[
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: fg),
            ),
            const SizedBox(width: 10),
          ] else if (icon != null) ...[
            Icon(icon, size: 18),
            const SizedBox(width: 8),
          ],
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ],
      ),
    );
  }
}

/// Secondary action built on Material [OutlinedButton].
class SmallAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const SmallAction(this.label, this.icon, this.onTap, {super.key});

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onTap,
    icon: Icon(icon, size: 16),
    label: Text(label, textAlign: TextAlign.center),
  );
}

class IconTile extends StatelessWidget {
  final IconData icon;
  final Color? bg;
  final Color? fg;
  final double size;

  const IconTile(this.icon, {super.key, this.bg, this.fg, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final c = HyOpsColors.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg ?? c.primarySoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: size * 0.48, color: fg ?? c.primary),
    );
  }
}

/// Standardized bottom sheet shell with consistent title, subtitle, close
/// button, drag handle, and keyboard-safe scrolling.
class AppBottomSheet extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailingBadge;
  final String closeTooltip;
  final bool canClose;
  final Widget child;
  final double? fixedHeightFraction;

  const AppBottomSheet({
    super.key,
    required this.title,
    this.subtitle,
    this.trailingBadge,
    this.closeTooltip = 'Close',
    this.canClose = true,
    required this.child,
    this.fixedHeightFraction,
  });

  @override
  Widget build(BuildContext context) {
    final c = HyOpsColors.of(context);
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(title, style: T.titleFor(c).copyWith(fontSize: 20)),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: T.smallFor(c)),
                ],
                if (trailingBadge != null) ...[
                  const SizedBox(height: 8),
                  trailingBadge!,
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: closeTooltip,
            onPressed: canClose ? () => Navigator.of(context).pop() : null,
            icon: const Icon(Ic.close, size: 20),
          ),
        ],
      ),
    );

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Divider(height: 1, color: c.line),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              24 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SafeArea(top: false, child: child),
          ),
        ),
      ],
    );

    if (fixedHeightFraction != null) {
      return SizedBox(
        height: MediaQuery.sizeOf(context).height * fixedHeightFraction!,
        child: body,
      );
    }
    return body;
  }
}

/// Interactive phone row offering tap-to-call (`tel:`) and copy-to-clipboard.
class CallCopyPhoneRow extends StatelessWidget {
  final String phone;
  final bool compact;

  const CallCopyPhoneRow({
    super.key,
    required this.phone,
    this.compact = false,
  });

  Future<void> _call(BuildContext context) async {
    final ok = await callPhoneNumber(phone);
    if (!ok && context.mounted) {
      await Clipboard.setData(ClipboardData(text: phone));
      if (context.mounted) {
        toast(context, 'Dialer unavailable. Phone number copied.');
      }
    }
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: phone));
    if (context.mounted) toast(context, 'Phone number copied');
  }

  @override
  Widget build(BuildContext context) {
    final c = HyOpsColors.of(context);
    final display = formatPhoneDisplay(phone);
    if (display.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: c.surfaceSubtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.line),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: compact ? 4 : 6,
      ),
      child: Row(
        children: [
          Icon(Ic.phone, size: 16, color: c.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              display,
              style: T.bodyBoldFor(c).copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Copy phone number',
            onPressed: () => _copy(context),
            icon: Icon(Ic.copy, size: 18, color: c.muted),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
          TextButton.icon(
            onPressed: () => _call(context),
            icon: const Icon(Ic.phoneCall, size: 16),
            label: const Text('Call'),
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 44),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
          ),
        ],
      ),
    );
  }
}

void toast(BuildContext context, String msg) => toastWith(
  ScaffoldMessenger.of(context),
  msg,
  colors: HyOpsColors.of(context),
);

/// Use this when the originating context may be gone (e.g. after closing a sheet).
void toastWith(
  ScaffoldMessengerState m,
  String msg, {
  HyOpsColors? colors,
}) {
  final c = colors ?? (P.dark ? HyOpsColors.dark : HyOpsColors.light);
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: TextStyle(color: c.bg, fontWeight: FontWeight.w600),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
}
