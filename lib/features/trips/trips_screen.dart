import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/icons.dart';
import '../../core/palette.dart';
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
    final c = HyOpsColors.of(context);

    return RefreshIndicator(
      onRefresh: s.refresh,
      child: WorkspaceList(
        children: [
          const WorkspaceHeading(
            'Trips',
            subtitle: 'Schedule · Manila (PHT)',
            trailing: SyncStatusHeader(),
          ),
          const SyncPanel(),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Current'),
                      ),
                    ),
                    ButtonSegment(
                      value: true,
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Past trips'),
                      ),
                    ),
                  ],
                  selected: {s.pastTrips},
                  onSelectionChanged: s.loading || s.busy
                      ? null
                      : (value) => s.setTripPage(0, past: value.single),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (s.trips.isEmpty)
            DriverEmptyState(
              icon: Ic.route,
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
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Panel(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => TripDetailScreen(tripId: trip.id),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  'Delivery ${trip.id}',
                                  style: T.subheadingFor(c),
                                ),
                                StatusPill.trip(trip.status),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${manilaSchedule(trip.scheduledAt)} · ${formatVehicle(trip.truck)}',
                            style: T.bodyFor(c),
                          ),
                          Text(trip.warehouse, style: T.smallFor(c)),
                          if (trip.stops.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            SegmentedProgress(trip),
                          ],
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            children: [
                              Text(
                                '${trip.doneCount} of ${trip.stops.length} ${pluralize(trip.stops.length, 'stop')} recorded',
                                style: T.smallBoldFor(c),
                              ),
                              if (trip.pickups.isNotEmpty)
                                Text(
                                  '${trip.pickups.length} return ${pluralize(trip.pickups.length, 'pickup')}',
                                  style: T.smallFor(c),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(Ic.chevron, size: 18, color: c.muted),
                  ],
                ),
              ),
            ),
          ],
          if (s.tripTotal > 20 || s.tripPage > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: OverflowBar(
                alignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: s.tripPage > 0 && !s.loading && !s.busy
                        ? () => s.setTripPage(s.tripPage - 1)
                        : null,
                    child: const Text('Previous'),
                  ),
                  Text('Page ${s.tripPage + 1}', style: T.smallFor(c)),
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
            ),
        ],
      ),
    );
  }
}
