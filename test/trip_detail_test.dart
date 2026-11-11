import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hyops_flutter/data/models.dart';
import 'package:hyops_flutter/features/trips/trip_detail_screen.dart';
import 'package:hyops_flutter/state/app_state.dart';

import 'widget_test.dart' as fixtures;

class _TripRepository extends fixtures.FakeRepository {
  final Trip assignment;
  _TripRepository(super.client, this.assignment);

  @override
  Future<Trip> trip(String id) async => assignment;
}

void main() {
  Future<AppState> setup({bool proof = false, bool grouped = true}) async {
    SharedPreferences.setMockInitialValues({});
    final client = fixtures.FakeClient();
    final data = fixtures.tripJson()..['status'] = 'in_transit';
    final stop = (data['stops'] as List).single as Map<String, dynamic>;
    stop.addAll({
      'canDeliver': true,
      'canFail': true,
      'hasProof': proof,
      'orderGroupId': grouped ? 'group-1' : null,
      'orderGroupNumber': grouped ? 'GRP-001' : null,
      'notes': 'Call before unloading.',
    });
    final assignment = Trip.fromJson(data);
    final state = AppState(
      await SharedPreferences.getInstance(),
      api: client,
      driverRepository: _TripRepository(client, assignment),
      realtime: false,
    );
    state.trips.add(assignment);
    addTearDown(state.dispose);
    return state;
  }

  Widget shell(AppState state, {double scale = 1}) => AppScope(
    state: state,
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: const TripDetailScreen(tripId: '12'),
    ),
  );

  testWidgets('notes, grouped badge, grid and all-items navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = await setup();
    await tester.pumpWidget(shell(state));
    await tester.pumpAndSettle();
    expect(find.text('Grouped Order'), findsOneWidget);
    await tester.ensureVisible(find.text('Grouped Order'));
    await tester.tap(find.text('Grouped Order'));
    await tester.pumpAndSettle();
    expect(find.text('Record delivery'), findsNothing);
    expect(find.text('Product - Variant'), findsNothing);
    await tester.scrollUntilVisible(find.text('View All Order Items'), 250);
    await tester.pumpAndSettle();
    expect(find.text('Call before unloading.'), findsOneWidget);
    final route = tester.getRect(
      find.widgetWithText(OutlinedButton, 'View Road Routes'),
    );
    final failed = tester.getRect(
      find.widgetWithText(OutlinedButton, 'Report Failed Attempt'),
    );
    expect(route.top, failed.top);
    expect(route.right, lessThan(failed.left));
    await tester.tap(find.text('View All Order Items'));
    await tester.pumpAndSettle();
    expect(find.text('Order items'), findsOneWidget);
    expect(find.text('Product'), findsOneWidget);
    expect(find.text('Variant'), findsOneWidget);
    expect(find.text('Qty: 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved proof reveals record action; large text stacks actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = await setup(proof: true, grouped: false);
    await tester.pumpWidget(shell(state, scale: 1.6));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Record delivery'), 200);
    expect(find.text('Record delivery'), findsOneWidget);
    expect(find.text('Grouped Order'), findsNothing);
    final route = tester.getRect(
      find.widgetWithText(OutlinedButton, 'View Road Routes'),
    );
    final failed = tester.getRect(
      find.widgetWithText(OutlinedButton, 'Report Failed Attempt'),
    );
    expect(route.bottom, lessThan(failed.top));
    expect(tester.takeException(), isNull);
  });
}
