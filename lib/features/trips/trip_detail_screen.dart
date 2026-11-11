import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../core/format.dart';
import '../../core/palette.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/driver_ui.dart';
import '../../widgets/payment.dart';
import '../../widgets/sync_panel.dart';
import '../../widgets/workspace.dart';
import '../navigation/navigation_screen.dart';
import 'delivery_sheets.dart';
import 'proof_sheet.dart';
import 'order_items_screen.dart';
import 'delivery_stop_groups.dart';

class TripDetailScreen extends StatefulWidget {
  final String tripId;
  const TripDetailScreen({super.key, required this.tripId});
  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  bool _started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reload();
      });
    }
  }

  Future<void> _reload() async {
    if (!mounted) return;
    try {
      await AppScope.of(context).loadTrip(widget.tripId);
    } catch (e) {
      if (mounted) toast(context, apiError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context), trip = s.findTrip(widget.tripId);
    final stopGroups = deliveryStopGroups(trip?.stops ?? []);
    return Scaffold(
      appBar: AppBar(title: Text('Delivery ${widget.tripId}')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: WorkspaceList(
          children: [
            const SyncPanel(),
            if (trip == null)
              DriverEmptyState(
                icon: Icons.route_outlined,
                title: 'Assignment unavailable',
                message: 'Refresh the assignment or return to Trips.',
                action: OutlinedButton(
                  onPressed: _reload,
                  child: const Text('Refresh assignment'),
                ),
              ),
            if (trip != null) ...[
              WorkspaceColumns(
                first: Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatusPill.trip(trip.status),
                      const SizedBox(height: 12),
                      Text(trip.truck, style: T.title),
                      const SizedBox(height: 4),
                      Text(trip.warehouse, style: T.body),
                      const SizedBox(height: 8),
                      Text(
                        '${manilaSchedule(trip.scheduledAt)} (Manila)',
                        style: T.small,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '${trip.doneCount} of ${trip.stops.length} orders recorded${trip.pickups.isEmpty ? '' : ' / ${trip.pickups.length} return pickups'}',
                        style: T.bodyBold,
                      ),
                      if (trip.status == TripStatus.loading) ...[
                        const SizedBox(height: 12),
                        Text(
                          trip.canStartAt(DateTime.now())
                              ? 'Your trip is ready to start.'
                              : 'Start on the scheduled Manila date, at or after departure time.',
                          style: T.small,
                        ),
                        const SizedBox(height: 16),
                        BigButton(
                          s.busy ? 'Starting trip...' : 'Start trip',
                          icon: Icons.play_arrow_rounded,
                          onTap:
                              s.canPerformActions &&
                                  trip.canStartAt(DateTime.now())
                              ? () async {
                                  try {
                                    await s.startTrip(trip);
                                  } catch (e) {
                                    if (context.mounted)
                                      toast(context, apiError(e));
                                  }
                                }
                              : null,
                        ),
                      ],
                      if (trip.status == TripStatus.returning) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Return with all collected returns and undelivered goods. Staff will confirm warehouse receipt.',
                          style: T.body,
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed:
                              !s.isOffline && trip.hasWarehouseCoordinates
                              ? () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        NavigationScreen(tripId: trip.id),
                                  ),
                                )
                              : null,
                          icon: const Icon(Icons.navigation_outlined),
                          label: const Text('Route to warehouse'),
                        ),
                      ],
                    ],
                  ),
                ),
                second: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (trip.pickups.isNotEmpty) ...[
                      Text('Refunded / return pickups', style: T.title),
                      const SizedBox(height: 8),
                      Text(
                        'Retrieve the goods only. Do not collect or refund money.',
                        style: T.small,
                      ),
                      for (final pickup in trip.pickups)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Panel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(pickup.orderNumber, style: T.bodyBold),
                                Text(pickup.customer, style: T.body),
                                Text(pickup.address, style: T.body),
                                if (pickup.phone.isNotEmpty)
                                  SelectableText(pickup.phone),
                                Text(
                                  'Reason: ${pickup.reason}',
                                  style: T.small,
                                ),
                                for (final item in pickup.items)
                                  Text(
                                    '${item.qty} x ${item.name}',
                                    style: T.small,
                                  ),
                                const SizedBox(height: 12),
                                if (pickup.status == 'assigned' &&
                                    trip.status == TripStatus.inProgress) ...[
                                  OutlinedButton.icon(
                                    onPressed:
                                        s.canPerformActions &&
                                            pickup.hasCoordinates
                                        ? () => Navigator.of(context).push(
                                            MaterialPageRoute<void>(
                                              builder: (_) => NavigationScreen(
                                                tripId: trip.id,
                                                pickupId: pickup.id,
                                              ),
                                            ),
                                          )
                                        : null,
                                    icon: const Icon(Icons.navigation_outlined),
                                    label: const Text('Route to pickup'),
                                  ),
                                  if (!pickup.hasCoordinates)
                                    Text(
                                      'Coordinates unavailable. Confirm the address with staff.',
                                      style: T.small,
                                    ),
                                  BigButton(
                                    'Confirm collection',
                                    icon: Icons.inventory_2_outlined,
                                    onTap: !s.canPerformActions
                                        ? null
                                        : () async {
                                            final confirmed = await showDialog<bool>(
                                              context: context,
                                              builder: (dialogContext) =>
                                                  AlertDialog(
                                                    title: const Text(
                                                      'Confirm goods collected',
                                                    ),
                                                    content: Text(
                                                      'Have you physically collected ALL goods for ${pickup.orderNumber}? Return them to the warehouse. This does not issue a financial refund.',
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                              dialogContext,
                                                              false,
                                                            ),
                                                        child: const Text(
                                                          'Cancel',
                                                        ),
                                                      ),
                                                      FilledButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                              dialogContext,
                                                              true,
                                                            ),
                                                        child: const Text(
                                                          'Confirm collection',
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                            );
                                            if (confirmed != true ||
                                                !context.mounted)
                                              return;
                                            try {
                                              await s.collectReturn(pickup);
                                              if (context.mounted)
                                                toast(
                                                  context,
                                                  'Collection confirmed. Return the goods to the warehouse.',
                                                );
                                            } catch (e) {
                                              if (context.mounted)
                                                toast(context, apiError(e));
                                            }
                                          },
                                  ),
                                ] else
                                  Text(switch (pickup.status) {
                                    'received' => 'Received at warehouse',
                                    'assigned' => 'Awaiting pickup',
                                    _ =>
                                      'Collected / awaiting warehouse receipt',
                                  }, style: T.bodyBold),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                    ],
                    Text('Delivery stops', style: T.title),
                    const SizedBox(height: 8),
                    Text(
                      'Open a stop for directions, delivery details and proof.',
                      style: T.small,
                    ),
                    const SizedBox(height: 16),
                    for (var i = 0; i < stopGroups.length; i++)
                      Padding(
                        key: ValueKey(
                          stopGroups[i].first.isGroupedOrder
                              ? 'group:${stopGroups[i].first.orderGroupId}'
                              : 'stop:${stopGroups[i].first.id}',
                        ),
                        padding: const EdgeInsets.only(bottom: 12),
                        child: stopGroups[i].first.isGroupedOrder
                            ? _GroupedStopCard(
                                trip: trip,
                                stops: stopGroups[i],
                                number: i + 1,
                                onChanged: _reload,
                              )
                            : _StopCard(
                                trip: trip,
                                stop: stopGroups[i].first,
                                number: i + 1,
                                onChanged: _reload,
                              ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GroupedStopCard extends StatelessWidget {
  final Trip trip;
  final List<Stop> stops;
  final int number;
  final Future<void> Function() onChanged;
  const _GroupedStopCard({
    required this.trip,
    required this.stops,
    required this.number,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final first = stops.first;
    final recorded = stops.where((stop) => stop.isDone).length;
    final skipped = stops
        .where((stop) => !stop.isDone && trip.deferredStopIds.contains(stop.id))
        .length;
    final isNext = stops.any((stop) => stop.id == trip.currentStop?.id);
    return Material(
      color: P.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: isNext ? P.primary : P.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey('group:${trip.id}:${first.orderGroupId}'),
        tilePadding: const EdgeInsets.all(16),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          '$number. ${first.orderGroupNumber.isEmpty ? first.customer : first.orderGroupNumber}',
          style: T.bodyBold,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (first.orderGroupNumber.isNotEmpty) ...[
                Text(first.customer, style: T.small),
                const SizedBox(height: 6),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  const StatusPill('Grouped Order', tone: Tone.info),
                  Text(
                    '${stops.length} ${stops.length == 1 ? 'order' : 'orders'} / $recorded recorded',
                    style: T.smallBold,
                  ),
                  if (skipped > 0)
                    Text('$skipped skipped for now', style: T.small),
                  if (isNext) Text('Next stop', style: T.smallBold),
                ],
              ),
            ],
          ),
        ),
        children: [
          if (trip.status == TripStatus.inProgress &&
              stops.any((stop) => !stop.isDone))
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: Text(
                'Choose any pending order to deliver next. Skipped orders stay pending and can be resumed.',
                style: T.small,
              ),
            ),
          for (var i = 0; i < stops.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _StopCard(
              key: ValueKey(stops[i].id),
              trip: trip,
              stop: stops[i],
              number: i + 1,
              onChanged: onChanged,
              insideGroup: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _StopCard extends StatelessWidget {
  final Trip trip;
  final Stop stop;
  final int number;
  final Future<void> Function() onChanged;
  final bool insideGroup;
  const _StopCard({
    super.key,
    required this.trip,
    required this.stop,
    required this.number,
    required this.onChanged,
    this.insideGroup = false,
  });
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final isNext = trip.currentStop?.id == stop.id && !stop.isDone;
    final skipped = !stop.isDone && trip.deferredStopIds.contains(stop.id);
    final canPlan = s.loggedIn && !s.loading && !s.busy;
    return Material(
      color: P.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: insideGroup
            ? BorderSide.none
            : BorderSide(color: isNext ? P.primary : P.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey('${trip.id}:${stop.id}:${stop.status.name}'),
        initiallyExpanded: isNext,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          insideGroup ? stop.orderLabel : '$number. ${stop.customer}',
          style: T.bodyBold,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusPill.stop(stop.status),
              if (stop.isGroupedOrder && !insideGroup)
                const StatusPill('Grouped Order', tone: Tone.info),
              if (skipped) const StatusPill('Skipped for now', tone: Tone.warn),
              if (isNext)
                Text(
                  insideGroup ? 'Delivering next' : 'Next stop',
                  style: T.smallBold,
                ),
            ],
          ),
        ),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Divider(),
              const SizedBox(height: 8),
              if (insideGroup &&
                  trip.status == TripStatus.inProgress &&
                  !stop.isDone &&
                  (stop.canDeliver || stop.canFail)) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (!isNext)
                      OutlinedButton.icon(
                        onPressed: !canPlan
                            ? null
                            : () => _planOrder(context, s),
                        icon: const Icon(Icons.near_me_outlined),
                        label: Text(skipped ? 'Resume order' : 'Deliver next'),
                      ),
                    if (!skipped)
                      TextButton.icon(
                        onPressed: !canPlan
                            ? null
                            : () => _planOrder(context, s, skip: true),
                        icon: const Icon(Icons.skip_next_outlined),
                        label: const Text('Skip for now'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              if (!insideGroup) Text(stop.orderLabel, style: T.bodyBold),
              if (!insideGroup && stop.orderGroupNumber.isNotEmpty)
                Text('Group: ${stop.orderGroupNumber}', style: T.smallBold),
              if (stop.combinedPaymentNumber.isNotEmpty)
                Text(
                  'Combined payment: ${stop.combinedPaymentNumber} / Original allocation: ${rm(stop.combinedPaymentAllocation)}',
                  style: T.small,
                ),
              Text(stop.address, style: T.body),
              const SizedBox(height: 8),
              Text(stop.contact, style: T.bodyBold),
              if (stop.phone.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: stop.phone));
                      if (context.mounted)
                        toast(context, 'Phone number copied');
                    },
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    label: Text(stop.phone),
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [PaymentPill(stop.payment)],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text('Collect on delivery', style: T.bodyBold),
                  ),
                  const SizedBox(width: 12),
                  Flexible(child: Text(rm(stop.collectNow), style: T.title)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Order: ${rm(stop.total)} / Paid: ${rm(stop.paid)}',
                style: T.small,
              ),
              Text('Staff records payment receipts.', style: T.small),
              if (stop.notes.isNotEmpty) ...[
                const SectionTitle('Delivery notes'),
                Text(stop.notes, style: T.body),
              ],
              if (stop.failReason != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    stop.failReason!,
                    style: TextStyle(color: P.danger),
                  ),
                ),
              if (trip.status == TripStatus.inProgress &&
                  (stop.canDeliver || stop.canFail)) ...[
                const SizedBox(height: 16),
                _StopActionGrid(
                  children: [
                    OutlinedButton.icon(
                      onPressed: !s.isOffline && stop.hasCoordinates
                          ? () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => NavigationScreen(
                                  tripId: trip.id,
                                  stopId: stop.id,
                                ),
                              ),
                            )
                          : null,
                      icon: const Icon(Icons.navigation_outlined),
                      label: const Text(
                        'View Road Routes',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (stop.canFail)
                      OutlinedButton.icon(
                        onPressed: !s.canPerformActions || s.error != null
                            ? null
                            : () async {
                                await showIssueSheet(context, trip, stop);
                                await onChanged();
                              },
                        icon: const Icon(Icons.report_problem_outlined),
                        label: const Text(
                          'Report Failed Attempt',
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
                if (!stop.hasCoordinates)
                  Text(
                    'No map location saved. Use the delivery address above.',
                    style: T.small,
                  ),
              ],
              if (trip.status == TripStatus.inProgress &&
                  stop.canDeliver &&
                  stop.hasProof) ...[
                const SizedBox(height: 12),
                BigButton(
                  'Record delivery',
                  icon: Icons.check,
                  onTap: !s.canPerformActions || s.error != null
                      ? null
                      : () async {
                          await showDeliverySheet(context, trip, stop);
                          await onChanged();
                        },
                ),
              ],
              if (trip.status != TripStatus.loading &&
                  trip.status != TripStatus.cancelled)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: OutlinedButton.icon(
                    onPressed: !s.canPerformActions
                        ? null
                        : () async {
                            await showProofSheet(context, stop.id);
                            await onChanged();
                          },
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Photos / signature'),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          OrderItemsScreen(stop: stop, tripStops: trip.stops),
                    ),
                  ),
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('View All Order Items'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _planOrder(
    BuildContext context,
    AppState state, {
    bool skip = false,
  }) async {
    try {
      await state.planGroupedOrder(trip.id, stop.id, skip: skip);
      if (context.mounted && skip) {
        toast(
          context,
          '${stop.orderLabel} skipped for now. It remains pending.',
        );
      }
    } catch (e) {
      if (context.mounted) toast(context, apiError(e));
    }
  }
}

class _StopActionGrid extends StatelessWidget {
  final List<Widget> children;
  const _StopActionGrid({required this.children});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns =
          constraints.maxWidth >= 280 &&
              MediaQuery.textScalerOf(context).scale(14) <= 20
          ? 2
          : 1;
      final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final child in children)
            SizedBox(
              width: width,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: child,
              ),
            ),
        ],
      );
    },
  );
}
