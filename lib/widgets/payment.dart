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
  PaymentPill(this.payment, {super.key});
  @override
  Widget build(BuildContext context) =>
      StatusPill(payment.label, tone: paymentTone(payment));
}

/// One-line instruction for the driver about money at the door.
String paymentHint(PaymentArrangement p, double balance) => switch (p) {
  PaymentArrangement.fullyPaid => 'Fully paid - check recorded amounts below',
  PaymentArrangement.partiallyPaid => 'Collect ${rm(balance)} on delivery',
  PaymentArrangement.net30 => 'Net 30 - hand over invoice, no payment now',
  PaymentArrangement.payOnDelivery => 'Collect ${rm(balance)} on delivery',
};

/// Shown in the delivery sheet when the driver needs to act on payment.
class PaymentBanner extends StatelessWidget {
  final Stop stop;
  PaymentBanner(this.stop, {super.key});
  @override
  Widget build(BuildContext context) {
    if (stop.payment == PaymentArrangement.fullyPaid) return SizedBox.shrink();
    final partial =
        stop.payment == PaymentArrangement.partiallyPaid ||
        stop.payment == PaymentArrangement.payOnDelivery;
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Panel(
        color: partial ? P.warnSoft : P.infoSoft,
        radius: 14,
        padding: EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Ic.wallet, size: 20, color: partial ? P.warn : P.info),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                partial
                    ? 'Collect ${rm(stop.collectNow)} from ${stop.contact} before handing over.'
                    : 'Net 30: leave the invoice with ${stop.contact}. No payment due now.',
                style: T.bodyBold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class KvRow extends StatelessWidget {
  final String label;
  final String value;
  const KvRow(this.label, this.value, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label, style: T.small)),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: Text(value, textAlign: TextAlign.right, style: T.bodyBold),
        ),
      ],
    ),
  );
}

/// Full payment breakdown for one order.
class PaymentPanel extends StatelessWidget {
  final PaymentArrangement payment;
  final double total;
  final double paid;
  final String combinedPaymentNumber;
  final double combinedPaymentAllocation;
  PaymentPanel({
    super.key,
    required this.payment,
    required this.total,
    required this.paid,
    this.combinedPaymentNumber = '',
    this.combinedPaymentAllocation = double.nan,
  });
  @override
  Widget build(BuildContext context) {
    final balance = total - paid;
    return Panel(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text('Arrangement', style: T.small)),
              const SizedBox(width: 12),
              Flexible(child: PaymentPill(payment)),
            ],
          ),
          KvRow('Order total', rm(total)),
          KvRow('Paid', rm(paid)),
          if (combinedPaymentNumber.isNotEmpty) ...[
            KvRow('Combined payment', combinedPaymentNumber),
            KvRow('Original allocation', rm(combinedPaymentAllocation)),
          ],
          KvRow(
            payment == PaymentArrangement.net30
                ? 'Due within 30 days'
                : 'Balance',
            rm(balance),
          ),
        ],
      ),
    );
  }
}
