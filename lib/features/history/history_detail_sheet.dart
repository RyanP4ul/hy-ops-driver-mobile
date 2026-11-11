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
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: WorkspaceHeading(
                    e.customer,
                    subtitle:
                        'Delivery ${e.tripId} · ${manilaSchedule(e.when)} (Manila)',
                  ),
                ),
                IconButton(
                  tooltip: 'Close delivery record',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: StatusPill(
                e.outcome,
                tone: e.success ? Tone.green : Tone.danger,
              ),
            ),
            if (e.reason != null) ...[
              const SizedBox(height: 12),
              FeedbackStrip(e.reason!),
            ],
            const SectionTitle('Delivery details'),
            const Divider(),
            if (e.orderNumber.isNotEmpty) KvRow('Order', e.orderNumber),
            KvRow('Address', e.address),
            KvRow('Contact', e.contact),
            KvRow('Phone', e.phone),
            SectionTitle(
              'Order items',
              trailing: Text('${e.itemCount} total', style: T.smallBold),
            ),
            const Divider(),
            for (final item in e.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(child: Text(item.name, style: T.body)),
                    const SizedBox(width: 12),
                    Text('×${item.qty}', style: T.bodyBold),
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
      ),
    );
  }
}
