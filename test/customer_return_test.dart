import 'package:flutter_test/flutter_test.dart';
import 'package:hyops_flutter/data/models.dart';

import 'widget_test.dart' show tripJson;

Map<String, dynamic> pickupJson() => {
  'id': 7,
  'orderNumber': 'ORDER-7',
  'customer': 'Return customer',
  'address': 'Saved address',
  'reason': 'Wrong goods',
  'status': 'assigned',
  'phone': null,
  'version': 2,
  'coordinates': [121.1, 14.6],
  'items': [
    {'name': 'Product - Variant', 'qty': 2},
  ],
};

void main() {
  test(
    'pickup-only trips preserve coordinates, quantities and independent status',
    () {
      final trip = Trip.fromJson({
        ...tripJson(),
        'status': 'in_transit',
        'stops': [],
        'pickups': [pickupJson()],
      });
      expect(trip.status, TripStatus.inProgress);
      expect(trip.stops, isEmpty);
      expect(trip.pickups.single.items.single.qty, 2);
      expect(trip.pickups.single.lat, 14.6);
      expect(trip.pickups.single.lng, 121.1);
      expect(trip.pickups.single.hasCoordinates, true);
      expect(trip.pickups.single.phone, '');
      expect(Trip.fromJson(tripJson()).pickups, isEmpty);
    },
  );
  test('missing or invalid pickup coordinates never invent a destination', () {
    for (final coordinates in [
      null,
      <double>[],
      [181.0, 14.6],
      [121.0, double.nan],
    ]) {
      expect(
        ReturnPickup.fromJson({...pickupJson(), 'coordinates': coordinates})
            .hasCoordinates,
        false,
      );
    }
  });
}
