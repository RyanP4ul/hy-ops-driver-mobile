import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyops_flutter/api/api_client.dart';
import 'package:hyops_flutter/app.dart';
import 'package:hyops_flutter/core/format.dart';
import 'package:hyops_flutter/core/theme.dart';
import 'package:hyops_flutter/data/local/driver_cache_database.dart';
import 'package:hyops_flutter/data/models.dart';
import 'package:hyops_flutter/features/profile/profile_screen.dart';
import 'package:hyops_flutter/features/trips/delivery_sheets.dart';
import 'package:hyops_flutter/features/trips/order_items_screen.dart';
import 'package:hyops_flutter/features/trips/trip_detail_screen.dart';
import 'package:hyops_flutter/repositories/driver_repository.dart';
import 'package:hyops_flutter/services/assignment_socket.dart';
import 'package:hyops_flutter/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_acceptance_test.dart' show MemorySessionStore, TestAdapter, reply;
import 'widget_test.dart' as fixtures;

class _RestoredClient extends fixtures.FakeClient {
  @override
  Future<void> restore() async {
    remember = true;
    accepted = true;
  }
}

class _MultiOrderRepo extends fixtures.FakeRepository {
  final Trip assignment;
  _MultiOrderRepo(super.client, this.assignment);

  @override
  Future<Trip> trip(String id) async => assignment;

  @override
  Future<PageResult<Trip>> trips({int page = 0, bool past = false}) async =>
      PageResult([assignment], 1);
}

class _SlowSyncRepo extends fixtures.FakeRepository {
  Completer<void>? holdTrips;
  _SlowSyncRepo(super.client);

  @override
  Future<PageResult<Trip>> trips({int page = 0, bool past = false}) async {
    if (holdTrips != null) await holdTrips!.future;
    return super.trips(page: page, past: past);
  }
}

Future<void> _pumpRestoredApp(
  WidgetTester tester,
  SharedPreferences prefs,
  AppState state,
) async {
  await tester.pumpWidget(HyOpsApp(prefs: prefs, state: state));
  for (var i = 0;
      i < 40 &&
          (!state.initialized || state.loading || state.isStartupValidating);
      i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(state.initialized, isTrue, reason: 'error=${state.error}');
  expect(state.loggedIn, isTrue, reason: 'error=${state.error}');
  expect(state.loading, isFalse);
  expect(state.isStartupValidating, isFalse);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('formatting helpers normalize vehicle, units, refs, distance and phones', () {
    expect(formatVehicle('truck - ABC-1234'), 'Truck · ABC-1234');
    expect(formatPhoneDisplay('639482734769'), '+63 948 273 4769');
    expect(formatUnit(1, 'roll'), 'roll');
    expect(formatUnit(50, 'roll'), 'rolls');
    expect(formatUnit(2, 'box'), 'boxes');
    expect(shortRef('GRP-001'), 'GRP-001');
    expect(shortRef('OG-bf9ddc112c51452e8b77'), 'OG-bf9ddc…8b77');
    expect(formatDistance(850), '850 m');
    expect(formatDistance(4250), '4.3 km');
    expect(formatDuration(720), '~12 min');
    expect(formatDuration(4500), '~1h 15m');
  });

  testWidgets('theme changes keep active navigation routes intact', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final client = _RestoredClient();
    final state = AppState(
      prefs,
      api: client,
      driverRepository: fixtures.FakeRepository(client),
      realtime: false,
    );

    await _pumpRestoredApp(tester, prefs, state);

    await tester.tap(find.text('View trip'));
    await tester.pumpAndSettle();
    expect(find.text('Delivery 12'), findsOneWidget);

    state.setThemeMode(AppThemeMode.dark);
    await tester.pumpAndSettle();
    expect(find.text('Delivery 12'), findsOneWidget);

    state.setThemeMode(AppThemeMode.light);
    await tester.pumpAndSettle();
    expect(find.text('Delivery 12'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'cached startup hydrates trips before exposing loggedIn without false offline flash',
    () async {
      final db = DriverCacheDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = MemorySessionStore();
      final validateCompleter = Completer<void>();
      var holdValidate = false;

      final adapter = TestAdapter((request) async {
        if (request.path == '/auth/login') {
          return reply({'access_token': 'acc', 'refresh_token': 'ref'}, 200);
        }
        if (request.path == '/auth/me') {
          if (holdValidate) await validateCompleter.future;
          return reply({'id': 9, 'role': 'driver'}, 200);
        }
        if (request.path == '/driver/profile') {
          return reply({'id': 9, 'name': 'Jhon Driver', 'phone': '63948'}, 200);
        }
        if (request.path == '/driver/trips') {
          return reply({
            'items': [
              fixtures.tripJson()..['status'] = 'in_transit',
            ],
            'total': 1,
          }, 200);
        }
        if (request.path == '/driver/history') {
          return reply({'items': [], 'total': 0}, 200);
        }
        if (request.path == '/driver/sync/capabilities') {
          return reply({'protocol': 1, 'acceptNew': true, 'maxAgeHours': 24}, 200);
        }
        return reply({}, 200);
      });

      final api = ApiClient(
        baseUrl: 'http://localhost:5192',
        sessionStore: store,
        transport: Dio()..httpClientAdapter = adapter,
      );
      final repo = DriverRepository(api, cache: db);
      await api.login('driver@example.test', 'password', true);
      await api.validate();
      await repo.profile();
      await repo.trips();
      await repo.history();

      holdValidate = true;
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final restoredApi = ApiClient(
        baseUrl: 'http://localhost:5192',
        sessionStore: store,
        transport: Dio()..httpClientAdapter = adapter,
      );
      final state = AppState(
        prefs,
        api: restoredApi,
        driverRepository: DriverRepository(restoredApi, cache: db),
        realtime: false,
      );
      addTearDown(state.dispose);

      final emissions = <({bool initialized, bool loggedIn, int trips, bool offline})>[];
      state.addListener(() {
        emissions.add((
          initialized: state.initialized,
          loggedIn: state.loggedIn,
          trips: state.trips.length,
          offline: state.isOffline,
        ));
      });

      final initFuture = state.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      validateCompleter.complete();
      await initFuture;

      final loggedInEmissions = emissions.where((e) => e.loggedIn).toList();
      expect(loggedInEmissions, isNotEmpty);
      expect(
        loggedInEmissions.every((e) => e.trips == 1 && !e.offline),
        isTrue,
      );
    },
  );

  testWidgets(
    'TripDetail humanizes group titles, surfaces Add proof & deliver, and collapses delivered stops',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final data = fixtures.tripJson()..['status'] = 'in_transit';
      final base = Map<String, dynamic>.from((data['stops'] as List).first as Map);
      data['stops'] = [
        {
          ...base,
          'id': 1,
          'orderId': 101,
          'orderNumber': 'ORD-000001',
          'orderGroupId': 'g1',
          'orderGroupNumber': 'OG-bf9ddc112c51452e8b77',
          'customer': 'Miguel Cunanan',
          'status': 'delivered',
          'canDeliver': false,
          'canFail': false,
          'hasProof': true,
          'total': '29.99',
          'paid': '0.02',
          'collectNow': '29.97',
          'payment': 'PARTIALLY_PAID',
        },
        {
          ...base,
          'id': 2,
          'orderId': 102,
          'orderNumber': 'ORD-000002',
          'orderGroupId': 'g1',
          'orderGroupNumber': 'OG-bf9ddc112c51452e8b77',
          'customer': 'Miguel Cunanan',
          'status': 'pending',
          'canDeliver': true,
          'canFail': true,
          'hasProof': false,
          'total': '1499.50',
          'paid': '0.98',
          'collectNow': '1498.52',
          'payment': 'PARTIALLY_PAID',
        },
      ];
      final trip = Trip.fromJson(data);
      final client = fixtures.FakeClient();
      final state = AppState(
        await SharedPreferences.getInstance(),
        api: client,
        driverRepository: _MultiOrderRepo(client, trip),
        realtime: false,
      );
      addTearDown(state.dispose);
      await state.login('driver@example.test', 'valid-password', remember: false);

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

      // Group header uses customer name rather than raw 23-char OG hash.
      expect(find.text('1. Miguel Cunanan'), findsOneWidget);
      expect(find.text('1. OG-bf9ddc112c51452e8b77'), findsNothing);

      await tester.tap(find.text('1. Miguel Cunanan'));
      await tester.pumpAndSettle();

      // Pending ORD-000002 is auto-expanded with guided CTA visible without prior proof.
      expect(find.text('Add proof & deliver'), findsOneWidget);
      // Delivered ORD-000001 is collapsed by default.
      expect(find.text('PHP 29.97'), findsNothing);
    },
  );

  testWidgets('quick fail reason chips populate reason field in outcome sheet', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final client = fixtures.FakeClient();
    final state = AppState(
      await SharedPreferences.getInstance(),
      api: client,
      driverRepository: fixtures.FakeRepository(client),
      realtime: false,
    );
    addTearDown(state.dispose);
    await state.login('driver@example.test', 'valid-password', remember: false);
    final trip = Trip.fromJson(fixtures.tripJson()..['status'] = 'in_transit');

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          theme: driverTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showIssueSheet(context, trip, trip.stops.single),
                child: const Text('Open issue'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open issue'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Customer unreachable'));
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'Customer unreachable');
  });

  testWidgets('OrderItemsScreen pluralizes units and shows order status', (tester) async {
    final json = fixtures.tripJson();
    final s1 = Map<String, dynamic>.from((json['stops'] as List).single as Map)
      ..addAll({
        'id': 1,
        'orderId': 1,
        'orderNumber': 'ORD-1',
        'status': 'delivered',
        'items': [
          {'name': 'Sakolin', 'variant': '52', 'sku': 'HY-SK52', 'qty': 1, 'unit': 'roll'},
        ],
      });
    final stop = Stop.fromJson(s1);
    await tester.pumpWidget(
      MaterialApp(
        theme: driverTheme(),
        home: OrderItemsScreen(stop: stop, tripStops: [stop]),
      ),
    );
    expect(find.text('1 item · 1 unit'), findsOneWidget);
    expect(find.text('Qty: 1 roll'), findsOneWidget);
    expect(find.text('Variant: 52'), findsOneWidget);
    expect(find.text('Delivered'), findsOneWidget);
  });

  testWidgets('ProfileScreen toggles Appearance and persists Assignment alerts', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final client = fixtures.FakeClient();
    final state = AppState(
      prefs,
      api: client,
      driverRepository: fixtures.FakeRepository(client),
      realtime: false,
    );
    addTearDown(state.dispose);
    await state.login('driver@example.test', 'valid-password', remember: false);

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          theme: driverTheme(),
          home: const Scaffold(body: ProfileScreen()),
        ),
      ),
    );
    await tester.tap(find.text('Dark'));
    await tester.pump();
    expect(state.themeMode, AppThemeMode.dark);
    expect(prefs.getString('theme_mode'), 'dark');

    await tester.ensureVisible(find.text('Assignment alerts'));
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(state.notifications, false);
    expect(prefs.getBool('notifications'), false);
  });

  testWidgets('assignment notice banner shows Open and Dismiss controls', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final client = _RestoredClient();
    final state = AppState(
      prefs,
      api: client,
      driverRepository: fixtures.FakeRepository(client),
      realtime: false,
    );

    await _pumpRestoredApp(tester, prefs, state);

    state.assignmentNotice = const AssignmentEvent('e1', 'assigned', 12, 3).notice;
    state.assignmentTripId = '12';
    state.setTab(2);
    await tester.pumpAndSettle();

    expect(find.text('You have a new delivery: #12.'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Delivery 12'), findsOneWidget);
    expect(state.assignmentNotice, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'syncing displays blocking dialog spinner and prevents user input and back pop',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final client = _RestoredClient();
      final repo = _SlowSyncRepo(client);
      final state = AppState(
        prefs,
        api: client,
        driverRepository: repo,
        realtime: false,
      );

      await _pumpRestoredApp(tester, prefs, state);

      // Push a route so Back navigation can also be verified as blocked during sync.
      await tester.tap(find.text('View trip'));
      await tester.pumpAndSettle();
      expect(find.byType(TripDetailScreen), findsOneWidget);

      final hold = Completer<void>();
      repo.holdTrips = hold;
      await tester.tap(find.byTooltip('Refresh assignments'));
      await tester.pump();

      expect(find.byKey(const Key('sync-blocking-dialog')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Syncing…'), findsOneWidget);

      // Background controls and system back cannot act while syncing.
      await tester.tap(find.byTooltip('Back'), warnIfMissed: false);
      await tester.pump();
      expect(find.byType(TripDetailScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(TripDetailScreen), findsOneWidget);
      expect(find.byKey(const Key('sync-blocking-dialog')), findsOneWidget);

      hold.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sync-blocking-dialog')), findsNothing);
      expect(find.byType(TripDetailScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(TripDetailScreen), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'outbox sync spinner shows upload progress without overflow on small screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final client = _RestoredClient();
      final state = AppState(
        prefs,
        api: client,
        driverRepository: fixtures.FakeRepository(client),
        realtime: false,
      );

      await tester.pumpWidget(HyOpsApp(prefs: prefs, state: state));
      for (var i = 0;
          i < 40 &&
              (!state.initialized || state.loading || state.isStartupValidating);
          i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      state.repository.sync.syncing = true;
      state.repository.sync.uploadProgress(50, 100);
      await tester.pump();

      expect(find.byKey(const Key('sync-blocking-dialog')), findsOneWidget);
      expect(find.text('Synchronizing saved work…'), findsOneWidget);
      expect(find.text('Uploading proof (50%). Please wait…'), findsOneWidget);

      // Tapping a bottom tab behind the modal barrier is blocked.
      await tester.tap(find.text('Trips'), warnIfMissed: false);
      await tester.pump();
      expect(state.tab, 0);
      expect(tester.takeException(), isNull);

      state.repository.sync.syncing = false;
      state.repository.sync.uploadProgress(0, 0);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sync-blocking-dialog')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
