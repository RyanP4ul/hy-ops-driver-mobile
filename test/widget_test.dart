import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hyops_flutter/app.dart';
import 'package:hyops_flutter/api/api_client.dart';
import 'package:hyops_flutter/state/app_state.dart';
import 'package:hyops_flutter/repositories/driver_repository.dart';
import 'package:hyops_flutter/data/models.dart';
import 'package:hyops_flutter/core/format.dart';

class FakeClient extends ApiClient {
  bool accepted = false;
  @override
  Future<void> restore() async { remember = false; }
  @override
  Future<void> login(String email, String password, bool persist) async {
    if (password != 'valid-password') throw StateError('Invalid credentials.');
    accepted = true;
  }
  @override
  Future<void> validate() async { if (!accepted) throw StateError('Unauthorized'); }
  @override
  Future<void> clear() async { accepted = false; }
  @override
  Future<bool> logout() async { accepted = false; return true; }
}

Map<String, dynamic> tripJson() => {
  'id': 12, 'version': 3, 'status': 'scheduled', 'scheduledAt': '2026-11-02T10:00:00+08:00', 'kind': 'INTERNAL',
  'vehicle': {'type': 'truck', 'plate': 'ABC-123'},
  'warehouse': {'name': 'Real warehouse', 'latitude': '14.5', 'longitude': '121.0'},
  'stops': [{ 'id': 21, 'customer': 'Real customer', 'contact': 'Recipient', 'phone': '0900', 'address': 'Saved shipping address',
    'latitude': '14.6', 'longitude': '121.1', 'status': 'pending', 'payment': 'PAY_ON_DELIVERY',
    'total': '24.68', 'paid': '10.00', 'collectNow': '14.68', 'canDeliver': false, 'canFail': false,
    'items': [{'name': 'Product', 'variant': 'Variant', 'qty': 2}], 'doneAt': null, 'reason': null,
  }],
};

class FakeRepository extends DriverRepository {
  List<Map<String, dynamic>> savedProofs = [];
  @override
  Future<List<Map<String, dynamic>>> proofs(String stopId) async => savedProofs;
  bool failReads = false, failWrites = false;
  int reads = 0;
  final List<String> keys = [];
  FakeRepository(super.client);
  @override
  Future<Duration> automaticRefreshInterval() async =>
      DriverRepository.defaultAutomaticRefreshInterval;
  @override
  Future<Driver> profile() async => Driver('Real driver', '3', '0900', 'Per trip', 'See trips');
  @override
  Future<PageResult<Trip>> trips({int page = 0, bool past = false}) async {
    reads++;
    if (failReads) throw StateError('Network unavailable');
    return PageResult([Trip.fromJson(tripJson())], 1);
  }
  @override
  Future<PageResult<HistoryEntry>> history({int page = 0, String? from, String? to, String? status}) async => PageResult([], 0);
  @override
  Future<void> outcome(Stop stop, int version, String key, {String? reason}) async {
    keys.add(key);
    if (failWrites) throw StateError('Timeout');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('DTO maps real IDs, payment options, coordinates and historical money', () {
    final trip = Trip.fromJson(tripJson());
    expect(trip.id, '12'); expect(trip.version, 3);
    expect(trip.stops.single.payment, PaymentArrangement.payOnDelivery);
    expect(trip.stops.single.collectNow, 14.68);
    expect(trip.hasWarehouseCoordinates, true);
    expect(trip.stops.single.hasCoordinates, true);
    expect(trip.scheduledAt!.toUtc().hour, 2);
    expect(rm(24.68), 'PHP 24.68');
    final data = tripJson();
    (data['stops'] as List).first['total'] = null;
    (data['stops'] as List).first['latitude'] = null;
    expect(rm(Trip.fromJson(data).stops.single.total), 'Unverified');
    expect(Trip.fromJson(data).stops.single.hasCoordinates, false);
    data['status'] = 'returning';
    expect(Trip.fromJson(data).status, TripStatus.returning);
    data['status'] = 'unexpected';
    expect(() => Trip.fromJson(data), throwsFormatException);
  });

  test('remembered boolean never authenticates; real reads replace mock state; failures preserve confirmed data', () async {
    SharedPreferences.setMockInitialValues({'logged_in': true});
    final prefs = await SharedPreferences.getInstance();
    final client = FakeClient(); final repo = FakeRepository(client);
    final state = AppState(prefs, api: client, driverRepository: repo, realtime: false);
    addTearDown(state.dispose);
    await state.initialize();
    expect(state.loggedIn, false); expect(state.trips, isEmpty);
    await expectLater(state.login('driver@example.test', 'wrong', remember: false), throwsStateError);
    expect(state.loggedIn, false);
    await state.login('driver@example.test', 'valid-password', remember: false);
    expect(state.driver.name, 'Real driver'); expect(state.trips.single.id, '12');
    repo.failReads = true; await state.refresh();
    expect(state.error, contains('Network unavailable'));
    expect(state.trips.single.id, '12');
    await state.logout(); expect(state.trips, isEmpty); expect(state.history, isEmpty); expect(state.loggedIn, false);
  });

  test('ambiguous command retries retain idempotency key and never locally complete a stop', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final client = FakeClient(); final repo = FakeRepository(client);
    final state = AppState(prefs, api: client, driverRepository: repo, realtime: false);
    addTearDown(state.dispose);
    await state.login('driver@example.test', 'valid-password', remember: false);
    repo.failWrites = true;
    repo.savedProofs = [{'id': 'proof', 'kind': 'photo'}];
    final trip = state.trips.single; final stop = trip.stops.single;
    await expectLater(state.recordOutcome(trip, stop), throwsStateError);
    await expectLater(state.recordOutcome(trip, stop), throwsStateError);
    expect(repo.keys[0], repo.keys[1]);
    expect(stop.status, StopStatus.pending);
    expect(state.trips.single.status, TripStatus.loading);
  });

  testWidgets('current app opens driver email login without seeded credentials', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final client = FakeClient();
    await tester.pumpWidget(HyOpsApp(prefs: prefs, state: AppState(prefs, api: client, driverRepository: FakeRepository(client), realtime: false)));
    await tester.pumpAndSettle();
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('ivan.paring'), findsNothing);
    final inputs = tester.widgetList<EditableText>(find.byType(EditableText));
    expect(inputs.every((i) => i.controller.text.isEmpty), true);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
