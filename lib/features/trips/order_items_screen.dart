import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/icons.dart';
import '../../core/palette.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';
import '../../widgets/driver_ui.dart';

/// Shows only orders assigned to this trip; group membership never implies
/// that goods from other trips should be loaded or delivered here.
class OrderItemsScreen extends StatelessWidget {
  final Stop stop;
  final List<Stop> tripStops;

  const OrderItemsScreen({
    super.key,
    required this.stop,
    required this.tripStops,
  });

  List<Stop> get _orders {
    final orders = <Stop>[stop];
    if (stop.isGroupedOrder) {
      orders.addAll(
        tripStops.where(
          (other) =>
              other.id != stop.id && other.orderGroupId == stop.orderGroupId,
        ),
      );
    }
    final seen = <String>{};
    return orders
        .where(
          (order) => seen.add(order.orderId.isEmpty ? order.id : order.orderId),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = HyOpsColors.of(context);
    final orders = _orders;
    final lineCount = orders.fold<int>(
      0,
      (sum, order) => sum + order.items.length,
    );
    final quantity = orders.fold<int>(0, (sum, order) => sum + order.itemCount);

    return Scaffold(
      appBar: AppBar(title: const Text('Order items')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final gutter = constraints.maxWidth < 600 ? 16.0 : 28.0;
          final inset = constraints.maxWidth > 760
              ? (constraints.maxWidth - 704) / 2
              : gutter;
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(inset, 16, inset, 16),
                sliver: SliverToBoxAdapter(
                  child: Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (stop.isGroupedOrder) ...[
                          const StatusPill('Grouped Order', tone: Tone.info),
                          const SizedBox(height: 10),
                        ],
                        Text(stop.customer, style: T.titleFor(c)),
                        const SizedBox(height: 4),
                        Text(
                          stop.isGroupedOrder && stop.orderGroupNumber.isNotEmpty
                              ? 'Group ${shortRef(stop.orderGroupNumber)}'
                              : stop.orderLabel,
                          style: T.smallFor(c),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '$lineCount ${pluralize(lineCount, 'item')}',
                              style: T.bodyBoldFor(c),
                            ),
                            Text(
                              '$quantity total ${pluralize(quantity, 'unit')}',
                              style: T.bodyBoldFor(c),
                            ),
                            if (stop.isGroupedOrder)
                              Text(
                                '${orders.length} ${pluralize(orders.length, 'order')} on this trip',
                                style: T.smallFor(c),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              for (final order in orders) ...[
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(inset, 0, inset, 8),
                  sliver: SliverToBoxAdapter(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: c.surfaceSubtle,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: c.line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Semantics(
                                  header: true,
                                  child: Text(
                                    order.orderLabel,
                                    style: T.bodyBoldFor(c),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              StatusPill.stop(order.status),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${order.items.length} ${pluralize(order.items.length, 'item')} · ${order.itemCount} ${pluralize(order.itemCount, 'unit')}',
                            style: T.smallFor(c),
                          ),
                          if (stop.isGroupedOrder &&
                              order.address.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(order.address, style: T.smallFor(c)),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (order.items.isEmpty)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(inset, 0, inset, 16),
                    sliver: const SliverToBoxAdapter(
                      child: DriverEmptyState(
                        icon: Ic.box,
                        title: 'No items available',
                        message: 'No items are listed for this order.',
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(inset, 0, inset, 20),
                    sliver: SliverList.separated(
                      itemCount: order.items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) =>
                          _ItemRow(item: order.items[index]),
                    ),
                  ),
              ],
              SliverToBoxAdapter(
                child: SizedBox(
                  height: MediaQuery.paddingOf(context).bottom + 16,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final Item item;
  const _ItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final c = HyOpsColors.of(context);
    final unit = formatUnit(item.qty, item.unit);
    final qtyBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.surfaceSubtle,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.line),
      ),
      child: Text(
        'Qty: ${item.qty}${unit.isEmpty ? '' : ' $unit'}',
        style: T.bodyBoldFor(c).copyWith(
          fontSize: 13,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
    final thumb = item.imageUrl?.isNotEmpty == true
        ? ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              item.imageUrl!,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => IconTile(
                Ic.box,
                bg: c.surfaceSubtle,
                fg: c.muted,
                size: 48,
              ),
            ),
          )
        : IconTile(Ic.box, bg: c.surfaceSubtle, fg: c.muted, size: 48);

    return Panel(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackQty =
              constraints.maxWidth < 340 ||
              MediaQuery.textScalerOf(context).scale(15) > 19;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              thumb,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.productName, style: T.bodyBoldFor(c)),
                    if (item.variant.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text('Variant: ${item.variant}', style: T.smallFor(c)),
                    ],
                    if (item.sku.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text('SKU: ${item.sku}', style: T.smallFor(c)),
                    ],
                    if (stackQty) ...[
                      const SizedBox(height: 8),
                      qtyBadge,
                    ],
                  ],
                ),
              ),
              if (!stackQty) ...[
                const SizedBox(width: 10),
                qtyBadge,
              ],
            ],
          );
        },
      ),
    );
  }
}
