import 'dart:math' as math;

import 'package:flutter/material.dart';

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
        padding: EdgeInsets.fromLTRB(inset, 20, inset, 32),
        children: children,
      );
    },
  );
}

class WorkspaceHeading extends StatelessWidget {
  final String title;
  final String? subtitle;

  const WorkspaceHeading(this.title, {super.key, this.subtitle});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(header: true, child: Text(title, style: T.display)),
      if (subtitle != null) ...[
        const SizedBox(height: 6),
        Text(subtitle!, style: T.small),
      ],
    ],
  );
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
  Widget build(BuildContext context) => Material(
    color: P.surface,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(child: content),
            const SizedBox(width: 12),
            Icon(Icons.chevron_right, color: P.muted),
          ],
        ),
      ),
    ),
  );
}

class FeedbackStrip extends StatelessWidget {
  final String message;
  final bool warning;

  const FeedbackStrip(this.message, {super.key, this.warning = false});

  @override
  Widget build(BuildContext context) {
    final color = warning ? P.warn : P.danger;
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: warning ? P.warnSoft : P.dangerSoft,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                warning ? Icons.wifi_off : Icons.error_outline,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(message, style: T.small.copyWith(color: color)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
