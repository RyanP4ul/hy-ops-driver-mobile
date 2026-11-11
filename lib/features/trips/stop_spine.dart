import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/icons.dart';
import '../../core/palette.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';
import '../../widgets/payment.dart';
import '../home/home_screen.dart';

/// Vertical route line: each stop is a node on a spine. Done stops are solid
/// green, the current stop is signal yellow, upcoming stops are hollow.
class StopSpine extends StatelessWidget {
  final Trip trip;
  final bool compact;
  StopSpine({super.key, required this.trip, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final cur = trip.currentStop;
    return Column(
      children: [
        for (var i = 0; i < trip.stops.length; i++)
          _Row(
            key: ValueKey(trip.stops[i].id),
            trip: trip,
            stop: trip.stops[i],
            index: i,
            isLast: i == trip.stops.length - 1,
            isCurrent:
                trip.stops[i] == cur && trip.status == TripStatus.inProgress,
            compact: compact,
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final Trip trip;
  final Stop stop;
  final int index;
  final bool isLast;
  final bool isCurrent;
  final bool compact;
  _Row({
    super.key,
    required this.trip,
    required this.stop,
    required this.index,
    required this.isLast,
    required this.isCurrent,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final done = stop.isDone;
    final failed = stop.status == StopStatus.failed;
    final cancelled = stop.status == StopStatus.cancelled;
    final nodeColor = failed
        ? P.danger
        : cancelled
        ? Color(0xFF9AA7A1)
        : done
        ? P.success
        : isCurrent
        ? P.signal
        : P.surface;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                SizedBox(height: 18),
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: nodeColor,
                    border: Border.all(
                      color: done
                          ? nodeColor
                          : isCurrent
                          ? P.ink
                          : P.line,
                      width: 2,
                    ),
                  ),
                  child: done
                      ? Icon(
                          failed || cancelled ? Ic.fail : Ic.check,
                          size: 12,
                          color: Colors.white,
                        )
                      : null,
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: done && !cancelled ? P.success : P.line,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Panel(
                radius: 16,
                color: isCurrent ? P.warmHighlight : P.surface,
                padding: EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(stop.customer, style: T.bodyBold)),
                        StatusPill.stop(stop.status),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(stop.orderLabel, style: T.smallBold),
                    Text(stop.address, style: T.small),
                    if (!compact) ...[
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Ic.profile, size: 14, color: P.muted),
                          SizedBox(width: 6),
                          Text(
                            '${stop.contact}  -  ${stop.phone}',
                            style: T.small,
                          ),
                        ],
                      ),
                      SizedBox(height: 6),
                      if (stop.combinedPaymentNumber.isNotEmpty)
                        Text(
                          'Combined payment: ${stop.combinedPaymentNumber} / Original allocation: ${rm(stop.combinedPaymentAllocation)}',
                          style: T.small,
                        ),
                      _ItemsList(
                        key: ValueKey(stop.id),
                        stop: stop,
                        initiallyOpen: isCurrent,
                      ),
                      if (stop.doneAt != null) ...[
                        SizedBox(height: 6),
                        Text(
                          cancelled
                              ? 'Cancelled: ${stop.failReason}'
                              : stop.failReason ??
                                    'Completed at ${fmtTime(stop.doneAt!)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: failed
                                ? P.danger
                                : cancelled
                                ? P.muted
                                : P.success,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (isCurrent) ...[
                        SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: SmallAction(
                                'Call',
                                Ic.phone,
                                () => toast(
                                  context,
                                  'Calling ${stop.contact}...',
                                ),
                              ),
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: SmallAction(
                                stopActionLabel(stop),
                                Ic.navigate,
                                () => runStopAction(context, trip, stop),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tap-to-expand list of the order items for one stop.
class _ItemsList extends StatefulWidget {
  final Stop stop;
  final bool initiallyOpen;
  _ItemsList({super.key, required this.stop, required this.initiallyOpen});
  @override
  State<_ItemsList> createState() => _ItemsListState();
}

class _ItemsListState extends State<_ItemsList> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final stop = widget.stop;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(Ic.box, size: 14, color: P.primary),
                SizedBox(width: 6),
                Text(
                  '${stop.itemCount} items',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: P.primary,
                  ),
                ),
                SizedBox(width: 2),
                Icon(
                  _open ? Ic.chevronUp : Ic.chevronDown,
                  size: 16,
                  color: P.primary,
                ),
                Spacer(),
                if (stop.distanceKm > 0) ...[
                  Icon(Ic.route, size: 14, color: P.muted),
                  SizedBox(width: 6),
                  Text('${stop.distanceKm} km', style: T.small),
                ],
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: !_open
              ? SizedBox(width: double.infinity)
              : Container(
                  width: double.infinity,
                  margin: EdgeInsets.only(top: 6),
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: P.bg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < stop.items.length; i++) ...[
                        if (i > 0) SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(stop.items[i].name, style: T.body),
                            ),
                            Text('x${stop.items[i].qty}', style: T.bodyBold),
                          ],
                        ),
                      ],
                      SizedBox(height: 10),
                      Divider(height: 1, color: P.line),
                      SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(Ic.wallet, size: 14, color: P.muted),
                          SizedBox(width: 6),
                          Text('Payment', style: T.small),
                          Spacer(),
                          PaymentPill(stop.payment),
                        ],
                      ),
                      SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          paymentHint(stop.payment, stop.balance),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color:
                                stop.payment == PaymentArrangement.partiallyPaid
                                ? P.warn
                                : P.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
