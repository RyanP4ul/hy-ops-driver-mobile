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
  Future<AppState> setup({
    bool proof = false,
    bool grouped = true,
    bool done = false,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final client = fixtures.FakeClient();
    final data = fixtures.tripJson()..['status'] = 'in_transit';
    final stop = (data['stops'] as List).single as Map<String, dynamic>;
    stop.addAll({
      'status': done ? 'delivered' : 'pending',
      'canDeliver': !done,
      'canFail': !done,
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

  testWidgets(
    'read-only offline mode permits opening saved proofs and explains blocked writes',
    (tester) async {
      final state = await setup(proof: true, grouped: false, done: true);
      state.loggedIn = true;
      state.repository.enterOffline();
      await tester.pumpWidget(shell(state));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('1. Real customer'), 250);
      await tester.tap(find.text('1. Real customer'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Saved proofs'), 250);
      final proofs = find.widgetWithText(OutlinedButton, 'Saved proofs');
      await tester.pumpAndSettle();
      await tester.ensureVisible(proofs);
      await tester.pumpAndSettle();
      expect(tester.widget<OutlinedButton>(proofs).onPressed, isNotNull);
      expect(state.canSaveActions, false);
      await tester.tap(proofs);
      await tester.pumpAndSettle();
      expect(find.text('Delivery proofs'), findsOneWidget);
      expect(
        find.textContaining(
          'Offline delivery recording is not available from this server',
        ),
        findsWidgets,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'enabled remembered offline session keeps delivery and failure actions available',
    (tester) async {
      final state = await setup(proof: true, grouped: false);
      state.loggedIn = true;
      state.client.remember = true;
      state.repository.syncSupported = true;
      state.repository.offlineWritesEnabled = true;
      state.repository.enterOffline();
      await tester.pumpWidget(shell(state));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Record delivery'), 250);
      expect(state.canSaveActions, true);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Report failed'),
            )
            .onPressed,
        isNotNull,
      );
      expect(state.offlineActionRestriction, null);
      await tester.pumpWidget(const SizedBox.shrink());
    },
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
    await tester.scrollUntilVisible(find.text('Report failed'), 250);
    await tester.pumpAndSettle();
    expect(find.text('Call before unloading.'), findsOneWidget);
    final leftBorders = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).where((box) {
      final dec = box.decoration;
      if (dec is BoxDecoration && dec.border is Border) {
        final border = dec.border! as Border;
        return border.left != BorderSide.none &&
            border.top == BorderSide.none &&
            border.right == BorderSide.none &&
            border.bottom == BorderSide.none;
      }
      return false;
    });
    expect(leftBorders, isEmpty);
    expect(find.widgetWithText(OutlinedButton, 'Photos'), findsNothing);
    final route = tester.getRect(
      find.widgetWithText(OutlinedButton, 'Road route'),
    );
    final items = tester.getRect(
      find.widgetWithText(OutlinedButton, 'Order items'),
    );
    final failed = tester.getRect(
      find.widgetWithText(OutlinedButton, 'Report failed'),
    );
    expect(route.top, items.top);
    expect(route.height, items.height);
    expect(route.right, lessThan(items.left));
    expect(route.bottom, lessThan(failed.top));
    expect(failed.left, route.left);
    expect(failed.right, items.right);
    await tester.tap(find.text('Order items'));
    await tester.pumpAndSettle();
    expect(find.text('Order items'), findsOneWidget);
    expect(find.text('Product'), findsOneWidget);
    expect(find.text('Variant: Variant'), findsOneWidget);
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
      find.widgetWithText(OutlinedButton, 'Road route'),
    );
    final items = tester.getRect(
      find.widgetWithText(OutlinedButton, 'Order items'),
    );
    expect(route.bottom, lessThan(items.top));
    expect(tester.takeException(), isNull);
  });
}
