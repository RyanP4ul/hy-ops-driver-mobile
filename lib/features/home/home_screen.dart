import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/icons.dart';
import '../../core/palette.dart';
import '../../data/models.dart';
import '../../services/external_actions.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/driver_ui.dart';
import '../../widgets/payment.dart';
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
    final c = HyOpsColors.of(context);
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
          WorkspaceHeading(
            'Your shift',
            subtitle: state.driver.name,
            trailing: const SyncStatusHeader(),
          ),
          // Always pinned at the top when visible so cards never jump around.
          const SyncPanel(),
          const SizedBox(height: 16),
          if (trip == null)
            DriverEmptyState(
              icon: Ic.trips,
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
                  Row(
                    children: [
                      Expanded(
                        child: Text('Assignment', style: T.titleFor(c)),
                      ),
                      TextButton(
                        onPressed: () => state.setTab(1),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: const Text('All trips'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Panel(
                    onTap: openTrip,
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
                        const SizedBox(height: 10),
                        Text(formatVehicle(trip.truck), style: T.bodyBoldFor(c)),
                        const SizedBox(height: 2),
                        Text(trip.warehouse, style: T.smallFor(c)),
                        Text(
                          '${manilaSchedule(trip.scheduledAt)} (Manila)',
                          style: T.smallFor(c),
                        ),
                        if (trip.stops.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          SegmentedProgress(trip),
                          const SizedBox(height: 8),
                        ] else
                          const SizedBox(height: 12),
                        Text(
                          '${trip.doneCount} of ${trip.stops.length} ${pluralize(trip.stops.length, 'stop')} recorded',
                          style: T.smallBoldFor(c),
                        ),
                        if (trip.pickups.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${trip.pickups.length} return ${pluralize(trip.pickups.length, 'pickup')}',
                            style: T.smallFor(c),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
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
    final c = HyOpsColors.of(context);
    final stop = trip.status == TripStatus.inProgress ? trip.currentStop : null;
    final pickup = trip.pickups
        .where((pickup) => pickup.status == 'assigned')
        .firstOrNull;
    final groupedCount = stop != null && stop.isGroupedOrder
        ? trip.stops.where((s) => s.orderGroupId == stop.orderGroupId).length
        : 0;

    final (eyebrow, title, description, action) = switch (trip.status) {
      TripStatus.loading => (
        'Scheduled departure',
        'Delivery ${trip.id}',
        'Review your assignment and vehicle before starting your trip.',
        'View trip',
      ),
      TripStatus.returning => (
        'Warehouse return',
        'Return to ${trip.warehouse}',
        'Bring collected returns and undelivered goods to the warehouse for staff receipt.',
        'Continue trip',
      ),
      _ => (
        stop == null ? 'Next task' : 'Next stop',
        stop?.customer ?? 'Delivery manifest',
        stop?.address ??
            (trip.stops.any((s) => !s.isDone)
                ? 'Remaining orders are skipped for now. Open your trip to resume an order.'
                : 'Review your stops and return pickups.'),
        'Continue trip',
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(eyebrow, style: T.titleFor(c)),
        const SizedBox(height: 8),
        Panel(
          color: c.blueHighlight,
          borderColor: c.primary.withValues(alpha: 0.28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (stop != null) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    StatusPill(stop.orderLabel, tone: Tone.neutral),
                    if (stop.isGroupedOrder)
                      StatusPill(
                        'Grouped · $groupedCount orders',
                        tone: Tone.info,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              Text(title, style: T.titleFor(c)),
              const SizedBox(height: 4),
              Text(description, style: T.bodyFor(c)),
              if (stop != null) ...[
                const SizedBox(height: 12),
                CollectionStrip(
                  payment: stop.payment,
                  collectNow: stop.collectNow,
                  total: stop.total,
                  paid: stop.paid,
                ),
              ],
              const SizedBox(height: 16),
              BigButton(action, icon: Ic.arrowRight, onTap: openTrip),
              if (stop != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: !state.isOffline && stop.hasCoordinates
                            ? () => runStopAction(context, trip, stop)
                            : null,
                        icon: const Icon(Ic.navigate, size: 16),
                        label: const Text('Get directions'),
                      ),
                    ),
                    if (stop.phone.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final ok = await callPhoneNumber(stop.phone);
                            if (!ok && context.mounted) {
                              toast(
                                context,
                                'Dialer unavailable (${formatPhoneDisplay(stop.phone)})',
                              );
                            }
                          },
                          icon: const Icon(Ic.phoneCall, size: 16),
                          label: const Text('Call'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              if (stop != null && !stop.hasCoordinates) ...[
                const SizedBox(height: 8),
                Text(
                  'No map location saved. Use the delivery address above.',
                  style: T.smallFor(c),
                ),
              ],
            ],
          ),
        ),
        if (pickup != null) ...[
          const SizedBox(height: 12),
          Panel(
            onTap: openTrip,
            accentColor: c.warn,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const StatusPill('Return pickup', tone: Tone.warn),
                    const Spacer(),
                    Icon(Ic.chevron, size: 18, color: c.muted),
                  ],
                ),
                const SizedBox(height: 8),
                Text(pickup.customer, style: T.bodyBoldFor(c)),
                Text(
                  '${pickup.orderNumber} · ${pickup.address}',
                  style: T.smallFor(c),
                ),
                const SizedBox(height: 4),
                Text(
                  'Retrieve goods only. No cash collection or refund.',
                  style: T.smallBoldFor(c).copyWith(color: c.warn),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
