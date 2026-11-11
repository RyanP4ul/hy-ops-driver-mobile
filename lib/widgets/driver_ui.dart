import 'package:flutter/material.dart';

import '../core/palette.dart';

class DriverBrand extends StatelessWidget {
  final bool compact;
  const DriverBrand({super.key, this.compact = false});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Image.asset(
        'assets/logo.png',
        width: compact ? 36 : 48,
        height: compact ? 36 : 48,
        excludeFromSemantics: true,
      ),
      const SizedBox(width: 10),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('HYOps', style: T.title.copyWith(fontSize: compact ? 17 : 20)),
          Text('Driver', style: T.small),
        ],
      ),
    ],
  );
}

class DriverLoadingScreen extends StatelessWidget {
  const DriverLoadingScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: P.dark ? P.bg : P.surface,
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/logo.png',
                width: 56,
                height: 56,
                excludeFromSemantics: true,
              ),
              const SizedBox(height: 24),
              Text('HYOps Driver', style: T.title),
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text('Opening your account…', style: T.small),
              ),
              const SizedBox(height: 24),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ),
        ),
      ),
    ),
  );
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: P.muted, size: 30),
        const SizedBox(height: 16),
        Semantics(header: true, child: Text(title, style: T.title)),
        const SizedBox(height: 8),
        Text(message, style: T.body.copyWith(color: P.muted)),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    ),
  );
}
