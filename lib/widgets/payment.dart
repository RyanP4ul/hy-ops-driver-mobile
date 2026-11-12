import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/icons.dart';
import '../core/palette.dart';
import '../data/models.dart';
import 'common.dart';

Tone paymentTone(PaymentArrangement p) => switch (p) {
  PaymentArrangement.fullyPaid => Tone.green,
  PaymentArrangement.partiallyPaid => Tone.warn,
  PaymentArrangement.payOnDelivery => Tone.warn,
  PaymentArrangement.net30 => Tone.info,
};

class PaymentPill extends StatelessWidget {
  final PaymentArrangement payment;
  const PaymentPill(this.payment, {super.key});

  @override
  Widget build(BuildContext context) =>
      StatusPill(payment.label, tone: paymentTone(payment));
}

/// One-line instruction for the driver about money at the door.
String paymentHint(PaymentArrangement p, double balance) => switch (p) {
  PaymentArrangement.fullyPaid => 'Fully paid - no cash due',
  PaymentArrangement.partiallyPaid => 'Collect ${formatPhp(balance)} on delivery',
  PaymentArrangement.net30 => 'Net 30 - leave invoice, no cash due',
  PaymentArrangement.payOnDelivery => 'Collect ${formatPhp(balance)} on delivery',
};

/// Shown in the delivery sheet when the driver needs to act on payment.
class PaymentBanner extends StatelessWidget {
  final Stop stop;
  const PaymentBanner(this.stop, {super.key});

  @override
  Widget build(BuildContext context) {
    if (stop.payment == PaymentArrangement.fullyPaid) {
      return const SizedBox.shrink();
    }
    final c = HyOpsColors.of(context);
    final partial =
        stop.payment == PaymentArrangement.partiallyPaid ||
        stop.payment == PaymentArrangement.payOnDelivery;
    final fg = partial ? c.warn : c.info;
    final bg = partial ? c.warnSoft : c.infoSoft;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Panel(
        color: bg,
        borderColor: fg.withValues(alpha: 0.25),
        radius: 10,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Ic.wallet, size: 18, color: fg),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                partial
                    ? 'Collect ${formatPhp(stop.collectNow)} from ${stop.contact.isEmpty ? stop.customer : stop.contact} before handing over.'
                    : 'Net 30: leave the invoice with ${stop.contact.isEmpty ? stop.customer : stop.contact}. No payment due now.',
                style: T.bodyBoldFor(c).copyWith(fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// High-clarity collection box used on stop cards and Home next-stop summary.
class CollectionStrip extends StatelessWidget {
  final PaymentArrangement payment;
  final double collectNow;
  final double total;
  final double paid;
  final bool completed;

  const CollectionStrip({
    super.key,
    required this.payment,
    required this.collectNow,
    required this.total,
    required this.paid,
    this.completed = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = HyOpsColors.of(context);
    if (completed) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.surfaceSubtle,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.line),
        ),
        child: Wrap(
          spacing: 10,
          runSpacing: 6,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            PaymentPill(payment),
            Text(
              'Order ${formatPhp(total)} · Paid ${formatPhp(paid)}',
              style: T.smallFor(c).copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
    }

    final needsCash =
        payment == PaymentArrangement.partiallyPaid ||
        payment == PaymentArrangement.payOnDelivery;
    final bg = needsCash ? c.warnSoft : c.surfaceSubtle;
    final border = needsCash ? c.warn.withValues(alpha: 0.3) : c.line;
    final labelColor = needsCash ? c.warn : c.muted;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  payment == PaymentArrangement.net30
                      ? 'Net 30 invoice'
                      : payment == PaymentArrangement.fullyPaid
                      ? 'Payment status'
                      : 'Collect on delivery',
                  style: T.smallBoldFor(c).copyWith(color: labelColor),
                ),
                PaymentPill(payment),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                payment == PaymentArrangement.fullyPaid
                    ? 'No cash due'
                    : payment == PaymentArrangement.net30
                    ? 'No cash due now'
                    : formatPhp(collectNow),
                style: T.amountFor(c),
              ),
              Text(
                'Order ${formatPhp(total)} · Paid ${formatPhp(paid)}',
                style: T.smallFor(c).copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class KvRow extends StatelessWidget {
  final String label;
  final String value;
  const KvRow(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = HyOpsColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: T.smallFor(c))),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: T.bodyBoldFor(c).copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full payment breakdown for one order.
class PaymentPanel extends StatelessWidget {
  final PaymentArrangement payment;
  final double total;
  final double paid;
  final String combinedPaymentNumber;
  final double combinedPaymentAllocation;

  const PaymentPanel({
    super.key,
    required this.payment,
    required this.total,
    required this.paid,
    this.combinedPaymentNumber = '',
    this.combinedPaymentAllocation = double.nan,
  });

  @override
  Widget build(BuildContext context) {
    final c = HyOpsColors.of(context);
    final balance = total - paid;
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(child: Text('Arrangement', style: T.smallFor(c))),
                const SizedBox(width: 12),
                Flexible(child: PaymentPill(payment)),
              ],
            ),
          ),
          KvRow('Order total', formatPhp(total)),
          KvRow('Paid', formatPhp(paid)),
          if (combinedPaymentNumber.isNotEmpty) ...[
            KvRow('Combined payment', shortRef(combinedPaymentNumber)),
            KvRow('Allocated amount', formatPhp(combinedPaymentAllocation)),
          ],
          Divider(height: 12, color: c.line),
          KvRow(
            payment == PaymentArrangement.net30
                ? 'Due within 30 days'
                : 'Balance',
            formatPhp(balance),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Text(
                'Staff records payment receipts.',
                style: T.smallFor(c),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
