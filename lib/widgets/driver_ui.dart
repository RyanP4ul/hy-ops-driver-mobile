import 'package:flutter/material.dart';

import '../core/palette.dart';
import 'common.dart';

class DriverBrand extends StatelessWidget {
  final bool compact;
  const DriverBrand({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final c = HyOpsColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/logo.png',
          width: compact ? 34 : 44,
          height: compact ? 34 : 44,
          excludeFromSemantics: true,
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'HYOps',
              style: T.titleFor(c).copyWith(fontSize: compact ? 17 : 20),
            ),
            Text('Driver', style: T.smallFor(c)),
          ],
        ),
      ],
    );
  }
}

class DriverLoadingScreen extends StatelessWidget {
  const DriverLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = HyOpsColors.of(context);
    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/logo.png',
                    width: 88,
                    height: 88,
                    excludeFromSemantics: true,
                  ),
                  const SizedBox(height: 24),
                  Text('HYOps Driver', style: T.titleFor(c)),
                  const SizedBox(height: 8),
                  Semantics(
                    liveRegion: true,
                    child: Text('Loading your shift…', style: T.smallFor(c)),
                  ),
                  const SizedBox(height: 20),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      backgroundColor: c.surfaceSubtle,
                      color: c.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DriverEmptyState extends StatelessWidget {
  final IconData icon;
  final String title, message;
  final Widget? action;

  const DriverEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final c = HyOpsColors.of(context);
    return Panel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(icon, bg: c.surfaceSubtle, fg: c.muted, size: 48),
          const SizedBox(height: 16),
          Semantics(header: true, child: Text(title, style: T.titleFor(c))),
          const SizedBox(height: 6),
          Text(message, style: T.bodyFor(c).copyWith(color: c.muted)),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}
