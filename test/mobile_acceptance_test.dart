import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hyops_flutter/data/models.dart';
import 'package:hyops_flutter/repositories/driver_repository.dart';
import 'package:hyops_flutter/state/app_state.dart';
import 'package:hyops_flutter/features/home/home_screen.dart';
import 'package:hyops_flutter/features/trips/trip_detail_screen.dart';
import 'package:hyops_flutter/features/history/history_screen.dart';
import 'package:hyops_flutter/features/trips/proof_sheet.dart';

import 'widget_test.dart' as fixtures;

class AcceptanceRepository extends fixtures.FakeRepository {
  bool empty = false;
  int starts = 0;
  Completer<void>? startDelay;
  @override
  Future<void> startTrip(Trip trip) async {
    starts++;
    if (startDelay != null) await startDelay!.future;
    if (failWrites) throw StateError("Start could not be confirmed");
    data = Map<String, dynamic>.from(data)..["status"] = "in_transit";
  }

  Completer<void>? delay;
  String? from, to, status;
  Map<String, dynamic> data = fixtures.tripJson();
  AcceptanceRepository(super.client);
  @override
  Future<PageResult<Trip>> trips({int page = 0, bool past = false}) async {
    if (delay != null) await delay!.future;
    if (failReads) throw StateError('Network unavailable');
    final payload = Map<String, dynamic>.from(data)..['id'] = page + 12;
    return PageResult(empty ? [] : [Trip.fromJson(payload)], empty ? 0 : 45);
  }

  @override
  Future<Trip> trip(String id) async => Trip.fromJson(data);
  @override
  Future<PageResult<HistoryEntry>> history({
    int page = 0,
    String? from,
    String? to,
    String? status,
  }) async {
    this.from = from;
    this.to = to;
    this.status = status;
    return PageResult([], 0);
  }
}

Widget shell(AppState state, Widget page) => AppScope(
  state: state,
  child: MaterialApp(
    home: Scaffold(body: page),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<(AppState, AcceptanceRepository)> setup() async {
    SharedPreferences.setMockInitialValues({});
    final client = fixtures.FakeClient();
    final repo = AcceptanceRepository(client);
    final state = AppState(
      await SharedPreferences.getInstance(),
      api: client,
      driverRepository: repo,
      realtime: false,
    );
    addTearDown(state.dispose);
    await state.initialize();
    await state.login('driver@example.test', 'valid-password', remember: false);
    return (state, repo);
  }

  testWidgets(
    'unconfigured server explains offline restrictions and blocks operational writes',
    (tester) async {
      final (state, repo) = await setup();
      final today = DateTime.now()
          .toUtc()
          .add(const Duration(hours: 8))
          .toIso8601String()
          .split('T')
          .first;
      repo.data['scheduledAt'] = '${today}T00:00:00+08:00';
      repo.enterOffline();
      await state.refresh(retryConnection: false);
      await tester.pumpWidget(
        shell(state, const TripDetailScreen(tripId: '12')),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Offline delivery recording is not available from this server'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Start trip'),
            )
            .onPressed,
        null,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      repo.data['status'] = 'in_transit';
      (repo.data['stops'] as List).first['canDeliver'] = true;
      (repo.data['stops'] as List).first['hasProof'] = true;
      await state.refresh(retryConnection: false);
      await tester.pumpWidget(
        shell(state, const TripDetailScreen(tripId: '12')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Record delivery'),
            )
            .onPressed,
        null,
      );
      await tester.pumpWidget(shell(state, const ProofSheet(stopId: '21')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Camera'),
            )
            .onPressed,
        null,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Choose photo'),
            )
            .onPressed,
        null,
      );
      expect(find.text('Sign'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'start button waits for server confirmation before showing an in-transit trip',
    (tester) async {
      final (state, repo) = await setup();
      final today = DateTime.now()
          .toUtc()
          .add(const Duration(hours: 8))
          .toIso8601String()
          .split('T')
          .first;
      repo.data['scheduledAt'] = '${today}T00:00:00+08:00';
      await state.refresh();
      repo.startDelay = Completer<void>();
      await tester.pumpWidget(
        shell(state, const TripDetailScreen(tripId: '12')),
      );
      await tester.pump();
      await tester.tap(find.text('Start trip'));
      await tester.pump();
      expect(repo.starts, 1);
      expect(state.busy, true);
      expect(state.findTrip('12')!.status, TripStatus.loading);
      repo.startDelay!.complete();
      await tester.pumpAndSettle();
      expect(state.busy, false);
      expect(state.findTrip('12')!.status, TripStatus.inProgress);
      expect(find.text('Start trip'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'empty assignments display an honest empty state without demo records',
    (tester) async {
      final (state, repo) = await setup();
      repo.empty = true;
      await state.refresh();
      await tester.pumpWidget(shell(state, const HomeScreen()));
      await tester.pump();
      expect(find.textContaining('No active assignment'), findsOneWidget);
      expect(find.textContaining('Real customer'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test('pagination updates records and restores the confirmed page after a failed fetch', () async {
    final (state, repo) = await setup();
    await state.setTripPage(1);
    expect(state.tripPage, 1);
    expect(state.trips.single.id, '13');
    repo.failReads = true;
    await state.setTripPage(2);
    expect(state.tripPage, 1);
    expect(state.trips.single.id, '13');
    expect(state.error, contains('Network unavailable'));
  });
  testWidgets(
    'slow reads show progress; failures remain visible with previously confirmed records',
    (tester) async {
      final (state, repo) = await setup();
      repo.delay = Completer<void>();
      final read = state.refresh();
      await tester.pumpWidget(shell(state, const HomeScreen()));
      await tester.pump();
      final updating = find.byWidgetPredicate(
        (widget) => widget is LinearProgressIndicator && widget.value == null,
      );
      expect(updating, findsOneWidget);
      repo.delay!.complete();
      await read;
      await tester.pump();
      expect(updating, findsNothing);
      repo.failReads = true;
      await state.refresh();
      await tester.pump();
      expect(find.textContaining('Network unavailable'), findsOneWidget);
      expect(state.trips.single.id, '12');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'history status filter reaches repository and resets pagination',
    (tester) async {
      final (state, repo) = await setup();
      state.historyPage = 3;
      await tester.pumpWidget(shell(state, const HistoryScreen()));
      await tester.pump();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Failed').last);
      await tester.pumpAndSettle();
      expect(repo.status, 'failed');
      expect(state.historyPage, 0);
      await state.setHistoryFilter(
        from: '2026-11-01',
        to: '2026-11-02',
        status: 'delivered',
      );
      expect(repo.from, '2026-11-01');
      expect(repo.to, '2026-11-02');
      expect(repo.status, 'delivered');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'missing coordinates disable route action and unverified money is shown explicitly',
    (tester) async {
      final (state, repo) = await setup();
      repo.data['status'] = 'in_transit';
      final stop = (repo.data['stops'] as List).first as Map;
      stop['latitude'] = null;
      stop['total'] = null;
      stop['collectNow'] = null;
      stop['canDeliver'] = true;
      await state.refresh();
      await tester.pumpWidget(
        shell(state, const TripDetailScreen(tripId: '12')),
      );
      await tester.pumpAndSettle();
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Road route'),
      );
      expect(button.onPressed, null);
      expect(find.textContaining('Unverified'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test('all payment arrangements and Manila date boundaries map without fabricated coordinates', () {
    for (final code in [
      'FULLY_PAID',
      'PARTIALLY_PAID',
      'PAY_ON_DELIVERY',
      'NET_30',
    ]) {
      final data = fixtures.tripJson();
      (data['stops'] as List).first['payment'] = code;
      data['scheduledAt'] = '2026-11-01T00:00:00+08:00';
      final trip = Trip.fromJson(data);
      expect(trip.stops.single.payment.code, code);
      expect(trip.scheduledAt!.toUtc(), DateTime.utc(2026, 10, 31, 16));
    }
  });
}
