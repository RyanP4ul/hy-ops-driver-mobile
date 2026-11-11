import 'package:flutter/material.dart';

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
                padding: EdgeInsets.fromLTRB(inset, 20, inset, 20),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (stop.isGroupedOrder) ...[
                        const StatusPill('Grouped Order', tone: Tone.info),
                        const SizedBox(height: 10),
                      ],
                      Text(
                        stop.isGroupedOrder && stop.orderGroupNumber.isNotEmpty
                            ? stop.orderGroupNumber
                            : stop.orderLabel,
                        style: T.title,
                      ),
                      const SizedBox(height: 6),
                      Text(stop.customer, style: T.body),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 16,
                        runSpacing: 6,
                        children: [
                          Text(
                            '$lineCount ${lineCount == 1 ? 'item' : 'items'}',
                            style: T.bodyBold,
                          ),
                          Text('$quantity total units', style: T.bodyBold),
                          if (stop.isGroupedOrder)
                            Text(
                              '${orders.length} ${orders.length == 1 ? 'order' : 'orders'} on this trip',
                              style: T.small,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              for (final order in orders) ...[
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(inset, 0, inset, 0),
                  sliver: SliverToBoxAdapter(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: P.bg,
                        border: Border(bottom: BorderSide(color: P.line)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(order.orderLabel, style: T.bodyBold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${order.items.length} ${order.items.length == 1 ? 'item' : 'items'} · ${order.itemCount} units',
                              style: T.small,
                            ),
                            if (stop.isGroupedOrder &&
                                order.address.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(order.address, style: T.small),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (order.items.isEmpty)
                  SliverPadding(
                    padding: EdgeInsets.symmetric(
                      horizontal: inset,
                      vertical: 16,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: const DriverEmptyState(
                        icon: Icons.inventory_2_outlined,
                        title: 'No items available',
                        message: 'No items are listed for this order.',
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(inset, 0, inset, 24),
                  sliver: SliverList.builder(
                    itemCount: order.items.length,
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
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: P.line)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.imageUrl?.isNotEmpty == true) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                item.imageUrl!,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                errorBuilder: (context, error, stackTrace) => SizedBox(
                  width: 56,
                  height: 56,
                  child: Icon(Icons.inventory_2_outlined, color: P.muted),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.productName, style: T.bodyBold),
                if (item.variant.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(item.variant, style: T.body),
                ],
                if (item.sku.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('SKU: ${item.sku}', style: T.small),
                ],
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: P.chip,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Qty: ${item.qty}${item.unit.isEmpty ? '' : ' ${item.unit}'}',
                    style: T.bodyBold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
