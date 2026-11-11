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
      builder: (_, __) {
        if (t.status == TrackingStatus.idle) return SizedBox.shrink();
        final (label, color, soft) = switch (t.status) {
          TrackingStatus.live when t.socket == SocketStatus.connected => (
            'Location shared with dispatch',
            P.success,
            P.successSoft,
          ),
          TrackingStatus.live => (
            'Reconnecting location sharing...',
            P.warn,
            P.warnSoft,
          ),
          TrackingStatus.starting => ('Starting location...', P.muted, P.chip),
          TrackingStatus.locationOff => (
            'Location is off - not sharing',
            P.danger,
            P.dangerSoft,
          ),
          TrackingStatus.noPermission => (
            'Location permission needed',
            P.danger,
            P.dangerSoft,
          ),
          _ => ('Location error - retrying', P.warn, P.warnSoft),
        };
        return Semantics(
          liveRegion: true,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: soft,
              borderRadius: BorderRadius.circular(8),
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
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
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
