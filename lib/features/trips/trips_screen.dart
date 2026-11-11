import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../core/format.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/driver_ui.dart';
import '../../widgets/sync_panel.dart';
import '../../widgets/workspace.dart';
import 'trip_detail_screen.dart';

class TripsScreen extends StatelessWidget {
  const TripsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return RefreshIndicator(
      onRefresh: s.refresh,
      child: WorkspaceList(
        children: [
          const WorkspaceHeading(
            'Trips',
            subtitle: 'Assignment schedule · Manila time',
          ),
          const SyncPanel(),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 360,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Current')),
                  ButtonSegment(value: true, label: Text('Past trips')),
                ],
                selected: {s.pastTrips},
                onSelectionChanged: s.loading || s.busy
                    ? null
                    : (value) => s.setTripPage(0, past: value.single),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (s.trips.isEmpty)
            DriverEmptyState(
              icon: Icons.route_outlined,
              title: s.loading
                  ? 'Loading trips...'
                  : s.isOffline
                  ? 'No saved trips in this view'
                  : s.pastTrips
                  ? 'No past trips yet'
                  : 'No trips assigned',
              message: s.pastTrips
                  ? 'Completed and cancelled trips will appear here.'
                  : 'New deliveries appear automatically while you are connected.',
            ),
          for (final trip in s.trips) ...[
            RecordRow(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TripDetailScreen(tripId: trip.id),
                ),
              ),
              content: WorkspaceColumns(
                stackSpacing: 10,
                first: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('Delivery ${trip.id}', style: T.bodyBold),
                        StatusPill.trip(trip.status),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(manilaSchedule(trip.scheduledAt), style: T.small),
                    Text('${trip.truck} · ${trip.warehouse}', style: T.small),
                  ],
                ),
                second: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${trip.doneCount} of ${trip.stops.length} stops recorded',
                      style: T.bodyBold,
                    ),
                    if (trip.pickups.isNotEmpty)
                      Text(
                        '${trip.pickups.length} return pickups',
                        style: T.small,
                      ),
                  ],
                ),
              ),
            ),
            const Divider(),
          ],
          if (s.tripTotal > 20 || s.tripPage > 0)
            OverflowBar(
              alignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: s.tripPage > 0 && !s.loading && !s.busy
                      ? () => s.setTripPage(s.tripPage - 1)
                      : null,
                  child: const Text('Previous'),
                ),
                Text('Page ${s.tripPage + 1}', style: T.small),
                TextButton(
                  onPressed:
                      (s.tripPage + 1) * 20 < s.tripTotal &&
                          !s.loading &&
                          !s.busy
                      ? () => s.setTripPage(s.tripPage + 1)
                      : null,
                  child: const Text('Next'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
