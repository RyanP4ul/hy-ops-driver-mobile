import 'package:flutter/material.dart';

import '../core/palette.dart';
import '../services/location_tracking_service.dart';
import '../state/app_state.dart';

/// Small status strip: is the driver's location being shared with dispatch?
class TrackingBadge extends StatelessWidget {
  const TrackingBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).tracking;
    return ListenableBuilder(
      listenable: t,
      builder: (_, _) {
        if (t.status == TrackingStatus.idle) return const SizedBox.shrink();
        final c = HyOpsColors.of(context);
        final (label, color, soft) = switch (t.status) {
          TrackingStatus.live when t.socket == SocketStatus.connected => (
            'Location shared with dispatch',
            c.success,
            c.successSoft,
          ),
          TrackingStatus.live => (
            'Reconnecting location sharing...',
            c.warn,
            c.warnSoft,
          ),
          TrackingStatus.starting => (
            'Starting location...',
            c.muted,
            c.surfaceSubtle,
          ),
          TrackingStatus.locationOff => (
            'Location is off - not sharing',
            c.danger,
            c.dangerSoft,
          ),
          TrackingStatus.noPermission => (
            'Location permission needed',
            c.danger,
            c.dangerSoft,
          ),
          _ => ('Location error - retrying', c.warn, c.warnSoft),
        };
        return Semantics(
          liveRegion: true,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: soft,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
