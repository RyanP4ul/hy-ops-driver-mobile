import 'package:flutter/material.dart';

import '../core/palette.dart';
import '../core/format.dart';
import '../state/app_state.dart';
import 'workspace.dart';

class SyncPanel extends StatelessWidget {
  const SyncPanel({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (s.isOffline)
            const FeedbackStrip(
              'Offline - viewing saved data. Reconnect and refresh to resume delivery actions.',
              warning: true,
            ),
          if (s.loading) const LinearProgressIndicator(minHeight: 2),
          if (s.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FeedbackStrip(s.error!),
            ),
          Row(
            children: [
              Expanded(
                child: Text(
                  s.loading
                      ? 'Updating deliveries...'
                      : s.lastSynced == null
                      ? 'Not updated yet'
                      : s.isOffline
                      ? 'Saved ${fmtWhen(s.lastSynced!.toLocal())}'
                      : 'Updated ${fmtTime(s.lastSynced!.toLocal())}',
                  style: T.small,
                ),
              ),
              IconButton(
                tooltip: s.isOffline
                    ? 'Retry connection'
                    : 'Refresh assignments',
                onPressed: s.loading || s.busy ? null : s.refresh,
                icon: const Icon(Icons.refresh, size: 22),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
