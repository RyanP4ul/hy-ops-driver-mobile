import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyops_flutter/data/models.dart';
import 'package:hyops_flutter/features/trips/order_items_screen.dart';
import 'package:hyops_flutter/core/theme.dart';

import 'widget_test.dart' as fixtures;

Stop order(int id, {String? group = 'group-1', int count = 1}) {
  final json = Map<String, dynamic>.from(
    (fixtures.tripJson()['stops'] as List).single,
  );
  json.addAll({
    'id': id,
    'orderId': id,
    'orderNumber': 'ORD-$id',
    'orderGroupId': group,
    'orderGroupNumber': group == null ? null : 'GRP-001',
    'items': List.generate(
      count,
      (index) => {
        'name': 'Product $id-$index',
        'variant': 'Large',
        'sku': 'SKU-$id-$index',
        'qty': 2,
        'unit': 'boxes',
      },
    ),
  });
  return Stop.fromJson(json);
}

void main() {
  for (final width in [320.0, 390.0, 1024.0]) {
    testWidgets('grouped items are separated by order at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final selected = order(1);
      await tester.pumpWidget(
        MaterialApp(
          theme: driverTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(width == 320 ? 1.6 : 1)),
            child: child!,
          ),
          home: OrderItemsScreen(
            stop: selected,
            tripStops: [
              selected,
              order(2),
              order(3, group: null),
              order(4, group: 'other'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Grouped Order'), findsOneWidget);
      expect(find.text('2 orders on this trip'), findsOneWidget);
      expect(find.text('4 total units'), findsOneWidget);
      expect(find.text('ORD-1'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Product 2-0'), 150);
      await tester.pumpAndSettle();
      expect(find.text('ORD-2'), findsOneWidget);
      expect(find.text('Product 2-0'), findsOneWidget);
      expect(find.text('SKU: SKU-2-0'), findsOneWidget);
      expect(find.text('ORD-3'), findsNothing);
      expect(find.text('ORD-4'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('long orders scroll and empty orders have a clear state', (
    tester,
  ) async {
    final selected = order(1, group: null, count: 60);
    await tester.pumpWidget(
      MaterialApp(
        home: OrderItemsScreen(stop: selected, tripStops: [selected]),
      ),
    );
    expect(find.text('60 items'), findsOneWidget);
    expect(find.text('120 total units'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Product 1-59'), 400);
    await tester.pumpAndSettle();
    expect(find.text('Product 1-59'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final empty = order(2, group: null, count: 0);
    await tester.pumpWidget(
      MaterialApp(
        home: OrderItemsScreen(stop: empty, tripStops: [empty]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No items available'), findsOneWidget);
    expect(find.text('Grouped Order'), findsNothing);
  });
}
