import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hyops_flutter/core/theme.dart';
import 'package:hyops_flutter/data/models.dart';
import 'package:hyops_flutter/features/trips/trip_detail_screen.dart';
import 'package:hyops_flutter/repositories/driver_repository.dart';
import 'package:hyops_flutter/state/app_state.dart';

import 'customer_return_test.dart' show pickupJson;
import 'widget_test.dart' as fixtures;

class PickupRepository extends fixtures.FakeRepository {
  bool collected = false, failCollection = false;
  final List<String> collectionKeys = [];
  PickupRepository(super.client);
  Trip data() => Trip.fromJson({
    ...fixtures.tripJson(),
    'stops': [],
    'status': collected ? 'returning' : 'in_transit',
    'pickups': [
      {...pickupJson(), 'status': collected ? 'collected' : 'assigned'},
    ],
  });
  @override
  Future<PageResult<Trip>> trips({int page = 0, bool past = false}) async =>
      PageResult([data()], 1);
  @override
  Future<Trip> trip(String id) async => data();
  @override
  Future<void> collectReturn(ReturnPickup pickup, String key) async {
    requireOnline();
    collectionKeys.add(key);
    if (failCollection) throw StateError('Connection interrupted');
    collected = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;
  late PickupRepository repository;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final api = fixtures.FakeClient();
    repository = PickupRepository(api);
    state = AppState(
      await SharedPreferences.getInstance(),
      api: api,
      driverRepository: repository,
      realtime: false,
    );
    await state.initialize();
    await state.login('driver@example.test', 'valid-password', remember: false);
  });
  tearDown(() => state.dispose());
  test('ambiguous collection failure retains its key and never changes the cached task optimistically', () async {
    repository.failCollection = true;
    final pickup = state.trips.single.pickups.single;
    await expectLater(state.collectReturn(pickup), throwsStateError);
    expect(state.trips.single.pickups.single.status, 'assigned');
    repository.failCollection = false;
    await state.collectReturn(pickup);
    expect(repository.collectionKeys[0], repository.collectionKeys[1]);
    expect(state.trips.single.status, TripStatus.returning);
  });
  testWidgets(
    'collection requires confirmation and refreshed server state shows warehouse receipt pending',
    (tester) async {
      await tester.pumpWidget(
        AppScope(
          state: state,
          child: MaterialApp(
            theme: driverTheme(),
            home: const TripDetailScreen(tripId: '12'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final collect = find.text('Confirm collection');
      await tester.ensureVisible(collect);
      await tester.tap(collect);
      await tester.pumpAndSettle();
      expect(find.text('Confirm goods collected'), findsOneWidget);
      expect(repository.collectionKeys, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repository.collectionKeys, isEmpty);
      await tester.tap(collect);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Confirm collection'),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.collectionKeys, hasLength(1));
      expect(
        find.text('Collected / awaiting warehouse receipt'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
