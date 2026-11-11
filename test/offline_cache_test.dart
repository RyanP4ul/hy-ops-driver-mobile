import 'customer_return_test.dart' show pickupJson;

import 'package:hyops_flutter/data/models.dart';

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hyops_flutter/api/api_client.dart';
import 'package:hyops_flutter/data/local/driver_cache_database.dart';
import 'package:hyops_flutter/repositories/driver_repository.dart';
import 'package:hyops_flutter/services/offline_policy.dart';
import 'package:hyops_flutter/state/app_state.dart';

import 'session_acceptance_test.dart'
    show MemorySessionStore, TestAdapter, reply;
import 'widget_test.dart' as fixtures;

class OfflineFixture {
  bool disconnected = false;
  int? responseStatus;
  int writes = 0, reads = 0;
  String token = 'remembered-driver-a';
  Future<ResponseBody> handle(RequestOptions request) async {
    if (disconnected)
      throw DioException(
        requestOptions: request,
        type: DioExceptionType.connectionError,
      );
    if (request.path == '/auth/login')
      return reply({'access_token': 'access', 'refresh_token': token}, 200);
    if (request.path == '/auth/refresh' && responseStatus == 401)
      return reply({'message': 'Revoked'}, 401);
    if (request.path == '/auth/me') return reply({'role': 'driver'}, 200);
    if (request.path.startsWith('/auth/')) return reply('ok', 200);
    if (request.method != 'GET') {
      writes++;
      return reply({'ok': true}, 200);
    }
    reads++;
    if (responseStatus != null)
      return reply({'message': 'Server response'}, responseStatus!);
    if (request.path == '/driver/profile')
      return reply({'id': 3, 'name': 'Cached driver', 'phone': '0900'}, 200);
    if (request.path == '/driver/settings')
      return reply({'mobile_automatic_refresh_interval_ms': '15000'}, 200);
    if (request.path == '/driver/trips')
      return reply({
        'items': [fixtures.tripJson()],
        'total': 1,
      }, 200);
    if (request.path == '/driver/trips/12')
      return reply(fixtures.tripJson(), 200);
    if (request.path == '/driver/history')
      return reply({'items': [], 'total': 0}, 200);
    if (request.path.endsWith('/proofs')) return reply([], 200);
    throw StateError('Unexpected fixture request: ${request.path}');
  }

  ApiClient client(
    MemorySessionStore store, {
    String origin = 'http://localhost:5192',
  }) => ApiClient(
    transport: Dio()..httpClientAdapter = TestAdapter(handle),
    sessionStore: store,
    baseUrl: origin,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DriverCacheDatabase database;
  late OfflineFixture fixture;
  late MemorySessionStore store;
  late ApiClient api;
  late DriverRepository repository;
  setUp(() async {
    database = DriverCacheDatabase(NativeDatabase.memory());
    fixture = OfflineFixture();
    store = MemorySessionStore();
    api = fixture.client(store);
    repository = DriverRepository(api, cache: database);
    await api.login('driver@example.test', 'password', true);
  });
  tearDown(() async {
    await database.close();
  });
  Future<void> warm() async {
    await repository.profile();
    await repository.trips();
    await repository.history();
  }

  test('online reads stay network-first; disconnected reads use exact persisted snapshots and trip detail', () async {
    await warm();
    final reads = fixture.reads;
    await repository.profile();
    expect(fixture.reads, reads + 1);
    fixture.disconnected = true;
    repository.beginReadCycle();
    expect((await repository.profile()).name, 'Cached driver');
    expect((await repository.trips()).total, 1);
    expect(
      (await repository.trip('12')).stops.single.customer,
      'Real customer',
    );
    expect((await repository.history()).total, 0);
    expect(repository.offline, true);
    expect(repository.usedCache, true);
    expect(repository.cachedAt, isNotNull);
    await expectLater(
      repository.trips(page: 1),
      throwsA(isA<OfflineCacheMiss>()),
    );
    await expectLater(
      repository.history(status: 'failed'),
      throwsA(isA<OfflineCacheMiss>()),
    );
  });

  test('offline actions are blocked at repository and HTTP levels and are never queued', () async {
    await warm();
    final trip = (await repository.trips()).items.single;
    fixture.disconnected = true;
    await repository.profile();
    await expectLater(
      repository.startTrip(trip),
      throwsA(isA<OfflineActionBlocked>()),
    );
    await expectLater(
      repository.outcome(trip.stops.single, trip.version, 'key'),
      throwsA(isA<OfflineActionBlocked>()),
    );
    await expectLater(
      repository.uploadProof('21', Uint8List(1), 'photo', 'key'),
      throwsA(isA<OfflineActionBlocked>()),
    );
    await expectLater(
      repository.collectReturn(ReturnPickup.fromJson(pickupJson()), 'key'),
      throwsA(isA<OfflineActionBlocked>()),
    );
    await expectLater(
      api.dio.post<dynamic>('/driver/trips/12/start'),
      throwsA(isA<DioException>()),
    );
    expect(fixture.writes, 0);
    fixture.disconnected = false;
    await api.validate();
    repository.beginReadCycle();
    await warm();
    repository.completeRefresh();
    expect(repository.offline, false);
    expect(fixture.writes, 0);
    await repository.startTrip(trip);
    expect(fixture.writes, 1);
  });

  for (final status in [401, 403, 404, 500]) {
    test('HTTP $status never falls back to cached protected data', () async {
      await warm();
      fixture.responseStatus = status;
      await expectLater(repository.profile(), throwsA(isA<DioException>()));
      expect(repository.usedCache, false);
      expect(api.networkUnavailable.value, false);
      if (status == 401) {
        expect(api.cacheScope, null);
        expect(store.token, null);
      }
    });
  }

  test('other sessions/origins cannot load cached data; offline logout purges the owner scope', () async {
    await warm();
    final owner = api.cacheScope!;
    fixture.token = 'different-driver-session';
    final other = fixture.client(MemorySessionStore());
    final otherRepository = DriverRepository(other, cache: database);
    await other.login('other@example.test', 'password', true);
    fixture.disconnected = true;
    await expectLater(
      otherRepository.profile(),
      throwsA(isA<OfflineCacheMiss>()),
    );
    final otherOrigin = fixture.client(store, origin: 'http://localhost:5193');
    final otherOriginRepository = DriverRepository(
      otherOrigin,
      cache: database,
    );
    await otherOrigin.restore();
    await expectLater(
      otherOriginRepository.profile(),
      throwsA(isA<OfflineCacheMiss>()),
    );
    expect((await repository.profile()).name, 'Cached driver');
    expect(await api.logout(), false);
    expect(await database.read(owner, '/driver/profile:{}'), null);
    expect(store.token, null);
    expect(api.cacheScope, null);
  });

  test('cached remembered session opens read-only offline; recovery validates and refreshes before unlocking', () async {
    await warm();
    fixture.disconnected = true;
    SharedPreferences.setMockInitialValues({});
    final restored = fixture.client(store);
    final restoredRepository = DriverRepository(restored, cache: database);
    final state = AppState(
      await SharedPreferences.getInstance(),
      api: restored,
      driverRepository: restoredRepository,
      realtime: false,
    );
    addTearDown(state.dispose);
    await state.initialize();
    expect(state.loggedIn, true);
    expect(state.isOffline, true);
    expect(state.canPerformActions, false);
    expect(state.driver.name, 'Cached driver');
    expect(state.trips.single.id, '12');
    expect(state.lastSynced, isNotNull);
    await expectLater(
      state.startTrip(state.trips.single),
      throwsA(isA<OfflineActionBlocked>()),
    );
    await expectLater(
      state.recordOutcome(state.trips.single, state.trips.single.stops.single),
      throwsA(isA<OfflineActionBlocked>()),
    );
    fixture.disconnected = false;
    await state.refresh();
    expect(state.isOffline, false);
    expect(state.canPerformActions, true);
    expect(fixture.writes, 0);
    fixture.responseStatus = 401;
    await state.refresh();
    expect(state.loggedIn, false);
    expect(state.trips, isEmpty);
    expect(store.token, null);
  });

  test(
    'cold offline start without cached data cannot authenticate a driver',
    () async {
      fixture.disconnected = true;
      SharedPreferences.setMockInitialValues({});
      final restored = fixture.client(store);
      final state = AppState(
        await SharedPreferences.getInstance(),
        api: restored,
        driverRepository: DriverRepository(restored, cache: database),
        realtime: false,
      );
      addTearDown(state.dispose);
      await state.initialize();
      expect(state.loggedIn, false);
      expect(state.restorePending, true);
      expect(state.canPerformActions, false);
    },
  );

  test('expired snapshots and cancelled requests are not treated as valid offline responses', () async {
    await warm();
    await database.customStatement('UPDATE driver_read_cache SET saved_at = 0');
    fixture.disconnected = true;
    await expectLater(repository.profile(), throwsA(isA<OfflineCacheMiss>()));
    expect(await database.read(api.cacheScope!, '/driver/profile:{}'), null);
    expect(
      isConnectionFailure(
        DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.cancel,
        ),
      ),
      false,
    );
    expect(
      isConnectionFailure(
        DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.badCertificate,
        ),
      ),
      false,
    );
  });

  test(
    'late responses after logout cannot repopulate the cleared cache',
    () async {
      await warm();
      final scope = api.cacheScope!;
      final started = Completer<void>(), response = Completer<ResponseBody>();
      api.dio.httpClientAdapter = TestAdapter((request) {
        started.complete();
        return response.future;
      });
      final pending = repository.profile();
      final assertion = expectLater(pending, throwsA(isA<DioException>()));
      await started.future;
      await api.clear();
      response.complete(reply({'id': 3, 'name': 'Old response'}, 200));
      await assertion;
      await Future<void>.delayed(Duration.zero);
      expect(await database.read(scope, '/driver/profile:{}'), null);
    },
  );
  test(
    'Drift snapshots survive closing and reopening an on-disk database',
    () async {
      final parent = Directory('../.tmp/offline-cache-tests')
        ..createSync(recursive: true);
      final directory = parent.createTempSync('driver-');
      final file = File('${directory.path}/cache.sqlite');
      await database.close();
      database = DriverCacheDatabase(NativeDatabase(file));
      await database.save('scope', {
        'trip': {'id': 12},
      }, () => true);
      await database.close();
      database = DriverCacheDatabase(NativeDatabase(file));
      expect((await database.read('scope', 'trip'))?.data, {'id': 12});
      await database.close();
      directory.deleteSync(recursive: true);
      database = DriverCacheDatabase(NativeDatabase.memory());
    },
  );
}
