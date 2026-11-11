import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyops_flutter/core/theme.dart';
import 'package:hyops_flutter/data/models.dart';
import 'package:hyops_flutter/features/trips/stop_spine.dart';

import 'widget_test.dart' show tripJson;

void main() {
  Map<String, dynamic> multipleOrders() {
    final data = tripJson();
    final first = Map<String, dynamic>.from((data['stops'] as List).first as Map)
      ..addAll({'orderId': 101, 'orderNumber': 'ORD-000101'});
    final second = Map<String, dynamic>.from(first)
      ..addAll({
        'id': 22, 'orderId': 102, 'orderNumber': 'ORD-000102',
        'address': 'Second saved shipping address',
        'latitude': '14.7', 'longitude': '121.3',
        'total': '37.02', 'paid': '0.00', 'collectNow': '37.02',
      });
    data['stops'] = [first, second];
    return data;
  }

  test('same customer orders retain separate identities, destinations and money', () {
    final trip = Trip.fromJson(multipleOrders());
    final first = trip.stops[0], second = trip.stops[1];
    expect(first.customer, second.customer);
    expect(first.orderId, '101');
    expect(second.orderId, '102');
    expect(first.orderLabel, 'ORD-000101');
    expect(second.orderLabel, 'ORD-000102');
    expect(first.address, 'Saved shipping address');
    expect(second.address, 'Second saved shipping address');
    expect(first.lat, 14.6);
    expect(second.lat, 14.7);
    expect(first.collectNow, 14.68);
    expect(second.collectNow, 37.02);
    final entry = HistoryEntry.fromStop(trip, second, outcome: 'Delivered');
    expect(entry.orderNumber, 'ORD-000102');
    expect(entry.address, second.address);
    final json = Map<String, dynamic>.from((multipleOrders()['stops'] as List)[1] as Map)
      ..addAll({'tripId': 12, 'status': 'delivered', 'doneAt': '2026-11-05T10:00:00+08:00'});
    expect(HistoryEntry.fromJson(json).orderNumber, 'ORD-000102');
  });

  testWidgets('mobile shows both orders and their saved destinations for one customer', (tester) async {
    final trip = Trip.fromJson(multipleOrders());
    await tester.pumpWidget(MaterialApp(
      theme: driverTheme(),
      home: Scaffold(body: SingleChildScrollView(child: StopSpine(trip: trip, compact: true))),
    ));
    expect(find.text('Real customer'), findsNWidgets(2));
    expect(find.text('ORD-000101'), findsOneWidget);
    expect(find.text('ORD-000102'), findsOneWidget);
    expect(find.text('Saved shipping address'), findsOneWidget);
    expect(find.text('Second saved shipping address'), findsOneWidget);
  });
  test('combined receipts retain only each assigned order allocation in delivery and history', () {
    final data = multipleOrders();
    final stops = data['stops'] as List;
    stops[0].addAll({'combinedPaymentNumber': 'CP-ONE', 'combinedPaymentAllocation': '3.33', 'total': '12.34', 'paid': '4.33', 'collectNow': '8.01', 'payment': 'PARTIALLY_PAID'});
    stops[1].addAll({'combinedPaymentNumber': 'CP-ONE', 'combinedPaymentAllocation': '6.67', 'total': '24.68', 'paid': '6.67', 'collectNow': '18.01', 'payment': 'PARTIALLY_PAID'});
    final trip = Trip.fromJson(data);
    expect(trip.stops[0].combinedPaymentNumber, 'CP-ONE');
    expect(trip.stops[0].combinedPaymentAllocation, 3.33);
    expect(trip.stops[0].paid, 4.33);
    expect(trip.stops[1].combinedPaymentAllocation, 6.67);
    expect(trip.stops[1].collectNow, 18.01);
    expect(trip.stops[0].balance, closeTo(8.01, 0.00001));
    expect(trip.stops[1].balance, closeTo(18.01, 0.00001));
    expect(HistoryEntry.fromStop(trip, trip.stops[0], outcome: 'Delivered').combinedPaymentAllocation, 3.33);
    final entry = HistoryEntry.fromJson(Map<String, dynamic>.from(stops[1] as Map)
      ..addAll({'tripId': 12, 'status': 'delivered', 'doneAt': '2026-11-05T10:00:00+08:00'}));
    expect(entry.combinedPaymentNumber, 'CP-ONE');
    expect(entry.combinedPaymentAllocation, 6.67);
  });

  testWidgets('driver route shows the combined reference and allocated amount on its own stop', (tester) async {
    final data = tripJson();
    (data['stops'] as List)[0].addAll({'combinedPaymentNumber': 'CP-ONE', 'combinedPaymentAllocation': 3.33});
    await tester.pumpWidget(MaterialApp(theme: driverTheme(), home: Scaffold(
      body: SingleChildScrollView(child: StopSpine(trip: Trip.fromJson(data))),
    )));
    expect(find.textContaining('CP-ONE'), findsOneWidget);
    expect(find.textContaining('3.33'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

}
