import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/icons.dart';
import '../core/palette.dart';

class WorkspaceList extends StatelessWidget {
  final List<Widget> children;
  final double maxWidth;

  const WorkspaceList({
    super.key,
    required this.children,
    this.maxWidth = 1100,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final gutter = constraints.maxWidth < 600 ? 16.0 : 28.0;
      final inset = math.max(gutter, (constraints.maxWidth - maxWidth) / 2);
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(inset, 16, inset, 32),
        children: children,
      );
    },
  );
}

class WorkspaceHeading extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const WorkspaceHeading(
    this.title, {
    super.key,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = HyOpsColors.of(context);
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(title, style: T.displayFor(c))),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: T.smallFor(c)),
        ],
      ],
    );
    if (trailing == null) return heading;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack =
            constraints.maxWidth < 340 ||
            MediaQuery.textScalerOf(context).scale(15) > 19;
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading,
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerLeft, child: trailing!),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: heading),
            const SizedBox(width: 12),
            trailing!,
          ],
        );
      },
    );
  }
}

class WorkspaceColumns extends StatelessWidget {
  final Widget first;
  final Widget second;
  final double stackSpacing;

  const WorkspaceColumns({
    super.key,
    required this.first,
    required this.second,
    this.stackSpacing = 20,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 680 ||
          MediaQuery.textScalerOf(context).scale(15) > 20) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            first,
            SizedBox(height: stackSpacing),
            second,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: first),
          const SizedBox(width: 24),
          Expanded(flex: 2, child: second),
        ],
      );
    },
  );
}

class RecordRow extends StatelessWidget {
  final Widget content;
  final VoidCallback onTap;

  const RecordRow({super.key, required this.content, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = HyOpsColors.of(context);
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(child: content),
              const SizedBox(width: 12),
              Icon(Ic.chevron, color: c.muted, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class FeedbackStrip extends StatelessWidget {
  final String message;
  final bool warning;
  final bool info;
  final Widget? action;

  const FeedbackStrip(
    this.message, {
    super.key,
    this.warning = false,
    this.info = false,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final c = HyOpsColors.of(context);
    final (bg, fg, icon) = info
        ? (c.infoSoft, c.info, Ic.info)
        : warning
        ? (c.warnSoft, c.warn, Ic.wifiOff)
        : (c.dangerSoft, c.danger, Ic.alert);
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: fg.withValues(alpha: 0.28)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon, color: fg, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: T.smallFor(c).copyWith(color: fg, fontWeight: FontWeight.w500),
                ),
              ),
              if (action != null) ...[
                const SizedBox(width: 8),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
