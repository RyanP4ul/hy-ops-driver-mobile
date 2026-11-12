import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../core/format.dart';
import '../../core/icons.dart';
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
import 'delivery_stop_groups.dart';
import 'order_items_screen.dart';
import 'proof_sheet.dart';

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
    final s = AppScope.of(context);
    final c = HyOpsColors.of(context);
    final trip = s.findTrip(widget.tripId);
    final stopGroups = deliveryStopGroups(trip?.stops ?? []);
    final pendingCollect = (trip?.stops ?? [])
        .where((st) => !st.isDone && st.collectNow.isFinite && st.collectNow > 0)
        .fold<double>(0, (sum, st) => sum + st.collectNow);

    return Scaffold(
      appBar: AppBar(
        title: Text('Delivery ${widget.tripId}'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 6),
            child: SyncStatusHeader(iconOnly: true),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: WorkspaceList(
          children: [
            const SyncPanel(),
            if (trip == null)
              DriverEmptyState(
                icon: Ic.route,
                title: 'Assignment unavailable',
                message: 'Refresh the assignment or return to Trips.',
                action: OutlinedButton(
                  onPressed: _reload,
                  child: const Text('Refresh assignment'),
                ),
              ),
            if (trip != null) ...[
              const SizedBox(height: 4),
              WorkspaceColumns(
                first: Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 6,
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            StatusPill.trip(trip.status),
                            Text(
                              '${manilaSchedule(trip.scheduledAt)} (Manila)',
                              style: T.smallFor(c),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(formatVehicle(trip.truck), style: T.titleFor(c)),
                      const SizedBox(height: 4),
                      Text(trip.warehouse, style: T.bodyFor(c)),
                      if (trip.stops.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        SegmentedProgress(trip),
                      ],
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          Text(
                            '${trip.doneCount} of ${trip.stops.length} ${pluralize(trip.stops.length, 'order')} recorded',
                            style: T.bodyBoldFor(c),
                          ),
                          if (pendingCollect > 0)
                            Text(
                              'Collect remaining: ${formatPhp(pendingCollect)}',
                              style: T.smallBoldFor(c).copyWith(color: c.warn),
                            ),
                          if (trip.pickups.isNotEmpty)
                            Text(
                              '${trip.pickups.length} return ${pluralize(trip.pickups.length, 'pickup')}',
                              style: T.smallFor(c),
                            ),
                        ],
                      ),
                      if (trip.status == TripStatus.loading) ...[
                        const SizedBox(height: 12),
                        Text(
                          trip.canStartAt(DateTime.now())
                              ? 'Your trip is ready to start.'
                              : 'Start on the scheduled Manila date, at or after departure time.',
                          style: T.smallFor(c),
                        ),
                        const SizedBox(height: 14),
                        BigButton(
                          s.busy ? 'Starting trip...' : 'Start trip',
                          icon: Ic.play,
                          busy: s.busy,
                          onTap:
                              s.canPerformActions &&
                                  trip.canStartAt(DateTime.now())
                              ? () async {
                                  try {
                                    await s.startTrip(trip);
                                  } catch (e) {
                                    if (context.mounted) {
                                      toast(context, apiError(e));
                                    }
                                  }
                                }
                              : null,
                        ),
                      ],
                      if (trip.status == TripStatus.returning) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Return with all collected returns and undelivered goods. Staff will confirm warehouse receipt.',
                          style: T.bodyFor(c),
                        ),
                        const SizedBox(height: 14),
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
                          icon: const Icon(Ic.navigate, size: 16),
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
                      Text('Refunded / return pickups', style: T.titleFor(c)),
                      const SizedBox(height: 6),
                      Text(
                        'Retrieve the goods only. Do not collect or refund money.',
                        style: T.smallFor(c),
                      ),
                      const SizedBox(height: 10),
                      for (final pickup in trip.pickups) ...[
                        Panel(
                          accentColor: pickup.status == 'assigned'
                              ? c.warn
                              : c.success,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      pickup.orderNumber,
                                      style: T.bodyBoldFor(c),
                                    ),
                                  ),
                                  StatusPill(
                                    switch (pickup.status) {
                                      'received' => 'Received',
                                      'assigned' => 'Pending pickup',
                                      _ => 'Collected',
                                    },
                                    tone: pickup.status == 'assigned'
                                        ? Tone.warn
                                        : Tone.green,
                                  ),
                                ],
                              ),
                              if (pickup.pendingSync != null) ...[
                                const SizedBox(height: 6),
                                FeedbackStrip(
                                  pickup.syncError ??
                                      'Pending collection - saved on device',
                                  warning: true,
                                ),
                              ],
                              const SizedBox(height: 6),
                              Text(pickup.customer, style: T.bodyBoldFor(c)),
                              Text(pickup.address, style: T.bodyFor(c)),
                              if (pickup.phone.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                CallCopyPhoneRow(
                                  phone: pickup.phone,
                                  compact: true,
                                ),
                              ],
                              if (pickup.reason.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Reason: ${pickup.reason}',
                                  style: T.smallFor(c),
                                ),
                              ],
                              if (pickup.items.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                for (final item in pickup.items)
                                  Text(
                                    '${item.qty} × ${item.name}',
                                    style: T.smallFor(c),
                                  ),
                              ],
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
                                  icon: const Icon(Ic.navigate, size: 16),
                                  label: const Text('Route to pickup'),
                                ),
                                if (!pickup.hasCoordinates) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Coordinates unavailable. Confirm the address with staff.',
                                    style: T.smallFor(c),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                BigButton(
                                  'Confirm collection',
                                  icon: Ic.box,
                                  onTap:
                                      !s.canSaveActions ||
                                          pickup.pendingSync != null
                                      ? null
                                      : () => _confirmPickupCollection(
                                          context,
                                          s,
                                          pickup,
                                        ),
                                ),
                              ] else
                                Text(switch (pickup.status) {
                                  'received' => 'Received at warehouse',
                                  'assigned' => 'Awaiting pickup',
                                  _ =>
                                    'Collected / awaiting warehouse receipt',
                                }, style: T.bodyBoldFor(c)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      const SizedBox(height: 8),
                    ],
                    Text('Delivery stops', style: T.titleFor(c)),
                    const SizedBox(height: 4),
                    Text(
                      'Open a stop for route, order items, proof, and delivery confirmation.',
                      style: T.smallFor(c),
                    ),
                    const SizedBox(height: 14),
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

  Future<void> _confirmPickupCollection(
    BuildContext context,
    AppState s,
    ReturnPickup pickup,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm goods collected'),
        content: Text(
          'Have you physically collected ALL goods for ${pickup.orderNumber}? Return them to the warehouse. This does not issue a financial refund.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm collection'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await s.collectReturn(pickup);
      if (context.mounted) {
        toast(
          context,
          s.repository.syncSupported
              ? 'Collection saved on device. Pending sync. Return the goods to the warehouse.'
              : 'Collection confirmed. Return the goods to the warehouse.',
        );
      }
    } catch (e) {
      if (context.mounted) toast(context, apiError(e));
    }
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
    final s = AppScope.of(context);
    final c = HyOpsColors.of(context);
    final first = stops.first;
    final recorded = stops.where((stop) => stop.isDone).length;
    final skipped = stops
        .where((stop) => !stop.isDone && trip.deferredStopIds.contains(stop.id))
        .length;
    final isNext = stops.any((stop) => stop.id == trip.currentStop?.id);
    final totalUnits = stops.fold<int>(0, (sum, st) => sum + st.itemCount);
    final activeStop =
        stops.where((st) => st.id == trip.currentStop?.id).firstOrNull ??
        stops.where((st) => !st.isDone).firstOrNull ??
        first;

    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isNext ? c.primary : c.line,
          width: isNext ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey('group:${trip.id}:${first.orderGroupId}'),
        tilePadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          '$number. ${first.customer}',
          style: T.subheadingFor(c),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(first.address, style: T.smallFor(c)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const StatusPill('Grouped Order', tone: Tone.info),
                  Text(
                    '${stops.length} ${pluralize(stops.length, 'order')} / $recorded recorded',
                    style: T.smallBoldFor(c),
                  ),
                  if (skipped > 0)
                    StatusPill('$skipped skipped', tone: Tone.warn),
                  if (isNext)
                    const StatusPill('Next stop', tone: Tone.info),
                ],
              ),
              if (first.orderGroupNumber.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Group ref: ${shortRef(first.orderGroupNumber)}',
                  style: T.smallFor(c).copyWith(fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        children: [
          if (trip.status == TripStatus.inProgress &&
              stops.any((stop) => !stop.isDone)) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Text(
                'Choose any pending order to deliver next. Skipped orders stay pending and can be resumed.',
                style: T.smallFor(c),
              ),
            ),
            if (stops.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: !s.isOffline && activeStop.hasCoordinates
                            ? () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => NavigationScreen(
                                    tripId: trip.id,
                                    stopId: activeStop.id,
                                  ),
                                ),
                              )
                            : null,
                        icon: const Icon(Ic.navigate, size: 16),
                        label: const Text('Group route'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => OrderItemsScreen(
                              stop: activeStop,
                              tripStops: trip.stops,
                            ),
                          ),
                        ),
                        icon: const Icon(Ic.box, size: 16),
                        label: Text('All items ($totalUnits)'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          for (var i = 0; i < stops.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _StopCard(
              key: ValueKey(stops[i].id),
              trip: trip,
              stop: stops[i],
              number: i + 1,
              onChanged: onChanged,
              insideGroup: true,
              groupAddress: first.address,
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
  final String? groupAddress;

  const _StopCard({
    super.key,
    required this.trip,
    required this.stop,
    required this.number,
    required this.onChanged,
    this.insideGroup = false,
    this.groupAddress,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = HyOpsColors.of(context);
    final isNext = trip.currentStop?.id == stop.id && !stop.isDone;
    final skipped = !stop.isDone && trip.deferredStopIds.contains(stop.id);
    final canPlan = s.canPerformActions;
    final showAddress =
        insideGroup &&
        (groupAddress == null || stop.address.trim() != groupAddress!.trim());
    final hasProof = stop.hasProof || stop.hasLocalProof;

    final cardBg = insideGroup
        ? (isNext ? c.surface : c.surfaceSubtle)
        : c.surface;
    final cardBorder = isNext ? c.primary : c.line;

    return Material(
      color: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: cardBorder,
          width: isNext ? 1.5 : 1,
        ),
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
            style: T.bodyBoldFor(c),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!insideGroup) ...[
                  Text(stop.address, style: T.smallFor(c)),
                  const SizedBox(height: 6),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusPill.stop(stop.status),
                    if (stop.isGroupedOrder && !insideGroup)
                      const StatusPill('Grouped Order', tone: Tone.info),
                    if (skipped)
                      const StatusPill('Skipped for now', tone: Tone.warn),
                    if (isNext)
                      StatusPill(
                        insideGroup ? 'Delivering next' : 'Next stop',
                        tone: Tone.info,
                      ),
                  ],
                ),
              ],
            ),
          ),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Divider(height: 1, color: c.line),
                const SizedBox(height: 12),
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
                          icon: const Icon(Ic.navigate, size: 16),
                          label: Text(skipped ? 'Resume order' : 'Deliver next'),
                        ),
                      if (!skipped)
                        TextButton.icon(
                          onPressed: !canPlan
                              ? null
                              : () => _planOrder(context, s, skip: true),
                          icon: const Icon(Ic.skip, size: 16),
                          label: const Text('Skip for now'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if (!insideGroup) ...[
                  Text(stop.orderLabel, style: T.bodyBoldFor(c)),
                  const SizedBox(height: 4),
                ],
                if (stop.pendingSync != null) ...[
                  FeedbackStrip(
                    stop.syncError ??
                        'Pending ${stop.pendingSync} - saved on device',
                    warning: true,
                  ),
                  const SizedBox(height: 10),
                ],
                if (!insideGroup && stop.orderGroupNumber.isNotEmpty) ...[
                  Text(
                    'Group: ${shortRef(stop.orderGroupNumber)}',
                    style: T.smallBoldFor(c),
                  ),
                  const SizedBox(height: 4),
                ],
                if (showAddress) ...[
                  Text(stop.address, style: T.bodyFor(c)),
                  const SizedBox(height: 8),
                ],
                if (stop.contact.isNotEmpty &&
                    stop.contact.trim() != stop.customer.trim()) ...[
                  Text(
                    'Recipient: ${stop.contact}',
                    style: T.bodyBoldFor(c),
                  ),
                  const SizedBox(height: 8),
                ],
                if (stop.phone.isNotEmpty) ...[
                  CallCopyPhoneRow(phone: stop.phone, compact: true),
                  const SizedBox(height: 12),
                ],
                CollectionStrip(
                  payment: stop.payment,
                  collectNow: stop.collectNow,
                  total: stop.total,
                  paid: stop.paid,
                  completed: stop.isDone,
                ),
                if (!stop.isDone) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Staff records payment receipts.',
                    style: T.smallFor(c),
                  ),
                ],
                if (stop.combinedPaymentNumber.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () async {
                      await Clipboard.setData(
                        ClipboardData(text: stop.combinedPaymentNumber),
                      );
                      if (context.mounted) {
                        toast(context, 'Combined payment reference copied');
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Combined payment: ${shortRef(stop.combinedPaymentNumber)} · Allocated: ${formatPhp(stop.combinedPaymentAllocation)}',
                              style: T.smallFor(c),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(Ic.copy, size: 14, color: c.muted),
                        ],
                      ),
                    ),
                  ),
                ],
                if (stop.notes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: insideGroup ? c.surface : c.surfaceSubtle,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: c.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Ic.notes, size: 14, color: c.muted),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Delivery notes',
                                style: T.smallBoldFor(c),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(stop.notes, style: T.bodyFor(c)),
                      ],
                    ),
                  ),
                ],
                if (stop.failReason != null) ...[
                  const SizedBox(height: 12),
                  FeedbackStrip(stop.failReason!),
                ],
                // Primary Delivery CTA is ALWAYS discoverable for active orders.
                if (trip.status == TripStatus.inProgress && stop.canDeliver) ...[
                  const SizedBox(height: 16),
                  BigButton(
                    hasProof ? 'Record delivery' : 'Add proof & deliver',
                    icon: Ic.check,
                    onTap: !s.canSaveActions || stop.pendingSync != null
                        ? null
                        : () async {
                            await showDeliverySheet(context, trip, stop);
                            await onChanged();
                          },
                  ),
                  if (!hasProof) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Photo required before confirmation.',
                      style: T.smallFor(c),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                _StopActionGrid(
                  items: [
                    if (trip.status == TripStatus.inProgress &&
                        (stop.canDeliver || stop.canFail))
                      _StopActionItem(
                        label: 'Road route',
                        icon: Ic.navigate,
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
                      ),
                    _StopActionItem(
                      label: 'Order items',
                      icon: Ic.box,
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => OrderItemsScreen(
                            stop: stop,
                            tripStops: trip.stops,
                          ),
                        ),
                      ),
                    ),
                    if (stop.isDone &&
                        trip.status != TripStatus.loading &&
                        trip.status != TripStatus.cancelled)
                      _StopActionItem(
                        label: 'Saved proofs',
                        icon: Ic.camera,
                        onPressed: !s.loggedIn || s.busy
                            ? null
                            : () async {
                                await showProofSheet(
                                  context,
                                  stop.id,
                                  orderLabel: stop.orderLabel,
                                  customer: stop.customer,
                                  readOnly: true,
                                );
                                await onChanged();
                              },
                      ),
                    if (trip.status == TripStatus.inProgress && stop.canFail)
                      _StopActionItem(
                        label: 'Report failed',
                        icon: Ic.warning,
                        destructive: true,
                        onPressed:
                            !s.canSaveActions || stop.pendingSync != null
                            ? null
                            : () async {
                                await showIssueSheet(context, trip, stop);
                                await onChanged();
                              },
                      ),
                  ],
                ),
                if (trip.status == TripStatus.inProgress &&
                    (stop.canDeliver || stop.canFail) &&
                    !stop.hasCoordinates) ...[
                  const SizedBox(height: 8),
                  Text(
                    'No map location saved. Use the delivery address above.',
                    style: T.smallFor(c),
                  ),
                ],
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

class _StopActionItem {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool destructive;

  const _StopActionItem({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.destructive = false,
  });
}

class _StopActionGrid extends StatelessWidget {
  final List<_StopActionItem> items;
  const _StopActionGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final c = HyOpsColors.of(context);

    Widget buildButton(_StopActionItem item, {required bool tile}) {
      final style = OutlinedButton.styleFrom(
        foregroundColor: item.destructive ? c.danger : null,
        side: item.destructive
            ? BorderSide(
                color: item.onPressed == null
                    ? c.line
                    : c.danger.withValues(alpha: 0.55),
              )
            : null,
        minimumSize: Size(tile ? 0 : double.infinity, tile ? 68 : 48),
        padding: tile
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 12)
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );
      return OutlinedButton(
        onPressed: item.onPressed,
        style: style,
        child: tile
            ? Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(item.icon, size: 18),
                  const SizedBox(height: 6),
                  Text(item.label, textAlign: TextAlign.center),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(item.icon, size: 16),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(item.label, textAlign: TextAlign.center),
                  ),
                ],
              ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final useGrid =
            items.length > 1 &&
            constraints.maxWidth >= 260 &&
            MediaQuery.textScalerOf(context).scale(14) <= 20;
        if (!useGrid) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                buildButton(items[i], tile: false),
              ],
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i += 2) ...[
              if (i > 0) const SizedBox(height: 8),
              if (i + 1 < items.length)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: buildButton(items[i], tile: true)),
                      const SizedBox(width: 8),
                      Expanded(child: buildButton(items[i + 1], tile: true)),
                    ],
                  ),
                )
              else
                buildButton(items[i], tile: false),
            ],
          ],
        );
      },
    );
  }
}
