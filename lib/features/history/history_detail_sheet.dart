import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/palette.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';
import '../../widgets/payment.dart';
import '../../widgets/workspace.dart';

Future<void> showHistoryDetailSheet(BuildContext context, HistoryEntry entry) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _HistoryDetailSheet(entry: entry),
    );

class _HistoryDetailSheet extends StatelessWidget {
  final HistoryEntry entry;

  const _HistoryDetailSheet({required this.entry});

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final c = HyOpsColors.of(context);
    final showContact =
        e.contact.trim().isNotEmpty &&
        e.contact.trim().toLowerCase() != e.customer.trim().toLowerCase();

    return AppBottomSheet(
      title: e.customer,
      subtitle: 'Delivery ${e.tripId} · ${manilaSchedule(e.when)} (Manila)',
      closeTooltip: 'Close delivery record',
      trailingBadge: StatusPill(
        e.outcome,
        tone: e.success ? Tone.green : Tone.danger,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (e.reason != null) ...[
            FeedbackStrip(e.reason!),
            const SizedBox(height: 12),
          ],
          const SectionTitle(
            'Delivery details',
            padding: EdgeInsets.only(top: 4, bottom: 10),
          ),
          Panel(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (e.orderNumber.isNotEmpty) ...[
                  KvRow('Order', e.orderNumber),
                  Divider(height: 12, color: c.line),
                ],
                if (showContact) ...[
                  KvRow('Contact', e.contact),
                  Divider(height: 12, color: c.line),
                ],
                Text('Address', style: T.smallFor(c)),
                const SizedBox(height: 4),
                Text(e.address, style: T.bodyFor(c)),
                if (e.phone.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  CallCopyPhoneRow(phone: e.phone, compact: true),
                ],
              ],
            ),
          ),
          SectionTitle(
            'Order items',
            trailing: Text('${e.itemCount} total', style: T.smallBoldFor(c)),
          ),
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(
              children: [
                for (var i = 0; i < e.items.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: c.line),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.items[i].name,
                            style: T.bodyFor(c),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: c.surfaceSubtle,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '×${e.items[i].qty}',
                            style: T.bodyBoldFor(c),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SectionTitle('Payment'),
          PaymentPanel(
            payment: e.payment,
            total: e.total,
            paid: e.paid,
            combinedPaymentNumber: e.combinedPaymentNumber,
            combinedPaymentAllocation: e.combinedPaymentAllocation,
          ),
        ],
      ),
    );
  }
}
