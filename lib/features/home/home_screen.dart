import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/palette.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/driver_ui.dart';
import '../../widgets/sync_panel.dart';
import '../../widgets/tracking_badge.dart';
import '../../widgets/workspace.dart';
import '../navigation/navigation_screen.dart';
import '../trips/trip_detail_screen.dart';

String stopActionLabel(Stop stop) => 'Get directions';

void runStopAction(BuildContext context, Trip trip, Stop stop) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => NavigationScreen(tripId: trip.id, stopId: stop.id),
    ),
  );
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final trip = state.activeTrip;
    void openTrip() => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TripDetailScreen(tripId: trip!.id),
      ),
    );
    return RefreshIndicator(
      onRefresh: state.refresh,
      child: WorkspaceList(
        children: [
          WorkspaceHeading('Your shift', subtitle: state.driver.name),
          if (state.isOffline || state.error != null) const SyncPanel(),
          const SizedBox(height: 20),
          if (trip == null)
            DriverEmptyState(
              icon: Icons.local_shipping_outlined,
              title: state.loading
                  ? 'Loading assignments...'
                  : state.isOffline
                  ? 'No saved trips'
                  : 'No active assignment',
              message: state.isOffline
                  ? 'Connect to download your assignments.'
                  : 'New assignments appear here when dispatch sends them.',
              action: OutlinedButton(
                onPressed: () => state.setTab(1),
                child: const Text('View all trips'),
              ),
            )
          else
            WorkspaceColumns(
              first: _NextTask(trip: trip, openTrip: openTrip),
              second: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Assignment', style: T.title),
                  const SizedBox(height: 12),
                  Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text('Delivery ${trip.id}', style: T.bodyBold),
                            StatusPill.trip(trip.status),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(trip.truck, style: T.body),
                        Text(trip.warehouse, style: T.small),
                        Text(
                          '${manilaSchedule(trip.scheduledAt)} (Manila)',
                          style: T.small,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '${trip.doneCount} of ${trip.stops.length} stops recorded',
                          style: T.smallBold,
                        ),
                        if (trip.stops.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: trip.progress,
                            minHeight: 4,
                          ),
                        ],
                        if (trip.pickups.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            '${trip.pickups.length} return pickups',
                            style: T.small,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => state.setTab(1),
                      child: const Text('View all trips'),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          const Divider(),
          if (!state.isOffline && state.error == null) const SyncPanel(),
          const TrackingBadge(),
        ],
      ),
    );
  }
}

class _NextTask extends StatelessWidget {
  final Trip trip;
  final VoidCallback openTrip;

  const _NextTask({required this.trip, required this.openTrip});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final stop = trip.status == TripStatus.inProgress ? trip.currentStop : null;
    final pickup = trip.pickups
        .where((pickup) => pickup.status == 'assigned')
        .firstOrNull;
    final (title, description, action) = switch (trip.status) {
      TripStatus.loading => (
        'Scheduled departure',
        'Review the assignment before starting your trip.',
        'View trip',
      ),
      TripStatus.returning => (
        'Return to warehouse',
        'Bring collected returns and undelivered goods to the warehouse for staff to receive.',
        'Continue trip',
      ),
      _ => (
        stop?.customer ?? 'Delivery manifest',
        stop?.address ??
            (trip.stops.any((stop) => !stop.isDone)
                ? 'Remaining orders are skipped for now. Open your trip to resume an order.'
                : 'Review your stops and return pickups.'),
        'Continue trip',
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(stop == null ? 'Next task' : 'Next stop', style: T.title),
        const SizedBox(height: 12),
        Panel(
          color: P.blueHighlight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: T.title),
              const SizedBox(height: 6),
              Text(description, style: T.body),
              if (stop != null) ...[
                const SizedBox(height: 8),
                Text(stop.orderLabel, style: T.small),
                Text(
                  'Collect on delivery: ${rm(stop.collectNow)}',
                  style: T.bodyBold,
                ),
              ],
              const SizedBox(height: 16),
              BigButton(action, icon: Icons.arrow_forward, onTap: openTrip),
              if (stop != null)
                TextButton.icon(
                  onPressed: !state.isOffline && stop.hasCoordinates
                      ? () => runStopAction(context, trip, stop)
                      : null,
                  icon: const Icon(Icons.navigation_outlined),
                  label: const Text('Get directions'),
                ),
              if (stop != null && !stop.hasCoordinates)
                Text(
                  'No map location saved. Use the delivery address.',
                  style: T.small,
                ),
            ],
          ),
        ),
        if (pickup != null) ...[
          const SizedBox(height: 16),
          RecordRow(
            onTap: openTrip,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Return pickup', style: T.smallBold),
                Text(pickup.customer, style: T.bodyBold),
                Text(
                  '${pickup.orderNumber} · ${pickup.address}',
                  style: T.small,
                ),
                Text(
                  'Retrieve goods only. No cash collection or refund.',
                  style: T.small,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
