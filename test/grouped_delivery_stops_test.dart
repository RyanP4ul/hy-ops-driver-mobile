import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hyops_flutter/core/theme.dart';
import 'package:hyops_flutter/data/models.dart';
import 'package:hyops_flutter/features/trips/delivery_stop_groups.dart';
import 'package:hyops_flutter/features/trips/trip_detail_screen.dart';
import 'package:hyops_flutter/repositories/driver_repository.dart';
import 'package:hyops_flutter/state/app_state.dart';

import 'widget_test.dart' as fixtures;

Map<String, dynamic> groupedTrip() {
  final data = fixtures.tripJson()..['status'] = 'in_transit';
  final base = Map<String, dynamic>.from((data['stops'] as List).first as Map);
  data['stops'] = [
    for (var i = 1; i <= 3; i++)
      {
        ...base,
        'id': i,
        'orderId': 100 + i,
        'orderNumber': 'ORD-$i',
        'orderGroupId': i == 3 ? null : 'group-1',
        'orderGroupNumber': i == 3 ? null : 'GRP-001',
        'canDeliver': true,
        'canFail': true,
        'hasProof': true,
      },
  ];
  return data;
}

class GroupedRepository extends fixtures.FakeRepository {
  String driverId = '3';
  Map<String, dynamic> data = groupedTrip();
  final List<String> outcomes = [];
  GroupedRepository(super.client) {
    savedProofs = [
      {'id': 'proof', 'kind': 'photo'},
    ];
  }

  @override
  Future<Driver> profile() async => Driver('Driver', driverId, '', '', '');

  @override
  Future<Trip> trip(String id) async => Trip.fromJson(data);

  @override
  Future<PageResult<Trip>> trips({int page = 0, bool past = false}) async =>
      PageResult([Trip.fromJson(data)], 1);

  @override
  Future<void> outcome(
    Stop stop,
    int version,
    String key, {
    String? reason,
  }) async {
    outcomes.add(stop.id);
    final target = (data['stops'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((row) => row['id'].toString() == stop.id);
    target['status'] = reason == null ? 'delivered' : 'failed';
    target['canDeliver'] = target['canFail'] = false;
    data['version'] = (data['version'] as int) + 1;
  }
}

void main() {
  Future<(AppState, GroupedRepository)> setup({
    bool reset = true,
    GroupedRepository? repository,
  }) async {
    if (reset) SharedPreferences.setMockInitialValues({});
    final client = fixtures.FakeClient();
    final repo = repository ?? GroupedRepository(client);
    final state = AppState(
      await SharedPreferences.getInstance(),
      api: client,
      driverRepository: repo,
      realtime: false,
    );
    addTearDown(state.dispose);
    await state.login('driver@example.test', 'valid-password', remember: false);
    return (state, repo);
  }

  test('merges by group ID across the list, never by customer or payment', () {
    final data = groupedTrip();
    final stops = data['stops'] as List;
    data['stops'] = [
      stops[0],
      stops[2],
      stops[1],
      {...stops[2], 'id': 4},
    ];
    final trip = Trip.fromJson(data);
    final groups = deliveryStopGroups(trip.stops);
    expect(
      groups.map((group) => group.map((stop) => stop.id).toList()).toList(),
      [
        ['1', '2'],
        ['3'],
        ['4'],
      ],
    );
  });

  test(
    'choose and skip persist across refresh, details and app state recreation',
    () async {
      final (state, repo) = await setup();
      await state.planGroupedOrder('12', '2');
      expect(state.tripById('12').currentStop?.id, '2');
      expect(state.activeTrip?.currentStop?.id, '2');
      await state.planGroupedOrder('12', '1', skip: true);
      await state.loadTrip('12');
      await state.refresh();
      expect(state.tripById('12').currentStop?.id, '2');
      expect(state.activeTrip?.currentStop?.id, '2');
      expect(state.tripById('12').deferredStopIds, {'1'});
      expect(
        state.tripById('12').stops.map((stop) => stop.status),
        everyElement(StopStatus.pending),
      );
      expect(repo.outcomes, isEmpty);
      final (restored, _) = await setup(reset: false, repository: repo);
      expect(restored.tripById('12').currentStop?.id, '2');
      expect(restored.tripById('12').deferredStopIds, {'1'});
      await restored.planGroupedOrder('12', '1');
      expect(restored.tripById('12').currentStop?.id, '1');
      expect(restored.tripById('12').deferredStopIds, isEmpty);
    },
  );

  test('planning preferences are isolated to the assigned driver', () async {
    final (state, repo) = await setup();
    await state.planGroupedOrder('12', '2');
    await state.planGroupedOrder('12', '1', skip: true);
    repo.driverId = '4';
    await state.refresh();
    expect(state.tripById('12').currentStop?.id, '1');
    expect(state.tripById('12').deferredStopIds, isEmpty);
    repo.driverId = '3';
    await state.refresh();
    expect(state.tripById('12').currentStop?.id, '2');
    expect(state.tripById('12').deferredStopIds, {'1'});
  });

  test('consecutive skip actions keep both individual preferences', () async {
    final (state, _) = await setup();
    await Future.wait([
      state.planGroupedOrder('12', '1', skip: true),
      state.planGroupedOrder('12', '2', skip: true),
    ]);
    expect(state.tripById('12').deferredStopIds, {'1', '2'});
    expect(state.tripById('12').currentStop?.id, '3');
  });

  test('delivering a later group order updates only that order', () async {
    final (state, repo) = await setup();
    await state.planGroupedOrder('12', '1', skip: true);
    await state.planGroupedOrder('12', '2');
    var trip = state.tripById('12');
    await state.recordOutcome(trip, trip.stops[1]);
    trip = state.tripById('12');
    expect(repo.outcomes, ['2']);
    expect(trip.stops[0].status, StopStatus.pending);
    expect(trip.stops[1].status, StopStatus.delivered);
    expect(trip.stops[2].status, StopStatus.pending);
    expect(trip.deferredStopIds, {'1'});
    expect(trip.currentStop?.id, '3');
    await expectLater(state.planGroupedOrder('12', '2'), throwsStateError);
    await expectLater(
      state.planGroupedOrder('12', '2', skip: true),
      throwsStateError,
    );
    await state.planGroupedOrder('12', '1');
    trip = state.tripById('12');
    await state.recordOutcome(
      trip,
      trip.stops[0],
      reason: 'Customer unavailable',
    );
    trip = state.tripById('12');
    expect(trip.stops[0].status, StopStatus.failed);
    expect(trip.stops[1].status, StopStatus.delivered);
    expect(trip.stops[2].status, StopStatus.pending);
  });

  test('skipping all group orders leaves them pending until resumed', () async {
    final (state, repo) = await setup();
    (repo.data['stops'] as List).removeLast();
    await state.refresh();
    await state.planGroupedOrder('12', '1', skip: true);
    await state.planGroupedOrder('12', '2', skip: true);
    expect(state.tripById('12').currentStop, isNull);
    expect(state.tripById('12').doneCount, 0);
    expect(state.tripById('12').status, TripStatus.inProgress);
    await state.planGroupedOrder('12', '2');
    expect(state.tripById('12').currentStop?.id, '2');
    expect(state.tripById('12').deferredStopIds, {'1'});
    expect(repo.outcomes, isEmpty);
  });

  for (final width in [320.0, 390.0, 1024.0]) {
    testWidgets(
      'group expands with independent order actions at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final (state, repo) = await setup();
        await tester.pumpWidget(
          AppScope(
            state: state,
            child: MaterialApp(
              theme: driverTheme(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(width == 320 ? 1.6 : 1),
                ),
                child: child!,
              ),
              home: const TripDetailScreen(tripId: '12'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Grouped Order'), findsOneWidget);
        expect(find.text('2 orders / 0 recorded'), findsOneWidget);
        expect(find.byType(ExpansionTile), findsNWidgets(2));
        await tester.ensureVisible(find.text('Grouped Order'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Grouped Order'));
        await tester.pumpAndSettle();
        expect(find.text('ORD-2'), findsOneWidget);
        final second = find.byWidgetPredicate(
          (widget) =>
              widget is ExpansionTile &&
              (widget.title as Text?)?.data == 'ORD-2',
        );
        await tester.ensureVisible(find.text('ORD-2'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('ORD-2'));
        await tester.pumpAndSettle();
        final deliverNext = find.descendant(
          of: second,
          matching: find.text('Deliver next'),
        );
        await tester.ensureVisible(deliverNext);
        await tester.pumpAndSettle();
        await tester.tap(deliverNext);
        await tester.pumpAndSettle();
        expect(state.tripById('12').currentStop?.id, '2');
        final skip = find.descendant(
          of: second,
          matching: find.text('Skip for now'),
        );
        await tester.ensureVisible(skip);
        await tester.pumpAndSettle();
        await tester.tap(skip);
        await tester.pumpAndSettle();
        expect(state.tripById('12').deferredStopIds, {'2'});
        expect(state.tripById('12').currentStop?.id, '1');
        expect(find.text('Skipped for now'), findsOneWidget);
        expect(find.text('Pending'), findsNWidgets(3));
        expect(repo.outcomes, isEmpty);
        final resume = find.descendant(
          of: second,
          matching: find.text('Resume order'),
        );
        await tester.ensureVisible(resume);
        await tester.pumpAndSettle();
        await tester.tap(resume);
        await tester.pumpAndSettle();
        expect(state.tripById('12').currentStop?.id, '2');
        expect(state.tripById('12').deferredStopIds, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
