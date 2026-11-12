import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show MigrationStrategy, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyops_flutter/api/api_client.dart';
import 'package:hyops_flutter/data/local/driver_cache_database.dart';
import 'package:hyops_flutter/data/local/outbox_store.dart';
import 'package:hyops_flutter/data/models.dart';
import 'package:hyops_flutter/repositories/driver_repository.dart';
import 'package:hyops_flutter/services/attachment_store.dart';
import 'package:hyops_flutter/services/session_store.dart';

import 'session_acceptance_test.dart'
    show MemorySessionStore, TestAdapter, reply;
import 'widget_test.dart' show tripJson;
import 'customer_return_test.dart' show pickupJson;

class SyncFixture {
  bool acceptNewCommands = true;
  bool offline = false, reassigned = false, loseOutcomeResponse = false;
  int effects = 0, uploads = 0;
  final List<String> submitted = [];
  final Map<String, Map<String, dynamic>> receipts = {};
  late Map<String, dynamic> trip = {
    ...tripJson(),
    'status': 'in_transit',
    'stops': [
      for (final id in [21, 22])
        {
          ...(tripJson()['stops'] as List).single as Map,
          'id': id,
          'canDeliver': true,
          'canFail': true,
        },
    ],
    'pickups': [pickupJson()],
  };
  Future<ResponseBody> handle(RequestOptions r) async {
    if (offline)
      throw DioException(
        requestOptions: r,
        type: DioExceptionType.connectionError,
      );
    if (r.path == '/auth/login')
      return reply({
        'access_token': 'access',
        'refresh_token': 'sync-driver',
      }, 200);
    if (r.path == '/auth/me') return reply({'role': 'driver'}, 200);
    if (r.path.startsWith('/auth/')) return reply('ok', 200);
    if (r.path == '/driver/profile')
      return reply({'id': 3, 'name': 'Driver'}, 200);
    if (r.path == '/driver/sync/capabilities')
      return reply({
        'protocol': 1,
        'offlineWriteMaxAgeHours': 24,
        'acceptNewCommands': acceptNewCommands,
      }, 200);
    if (r.path.startsWith('/driver/sync/operations/')) {
      final result = receipts[r.path.split('/').last];
      return reply({'accepted': result != null, 'result': result}, 200);
    }
    if (r.path == '/driver/trips')
      return reply({
        'items': reassigned ? [] : [trip],
        'total': reassigned ? 0 : 1,
      }, 200);
    if (r.path == '/driver/history')
      return reply({'items': [], 'total': 0}, 200);
    if (r.path == '/driver/trips/12')
      return reassigned
          ? reply({
              'code': 'ASSIGNMENT_UNAVAILABLE',
              'message': 'Assignment not found',
            }, 404)
          : reply(trip, 200);
    if (r.path.endsWith('/proofs') && r.method == 'GET') return reply([], 200);
    if (r.method == 'POST') {
      if (reassigned) return reply({'message': 'Assignment not found'}, 404);
      if (r.path.endsWith('/proofs')) {
        final data = r.data as FormData;
        final key = data.fields
            .firstWhere((e) => e.key == 'operationKey')
            .value;
        submitted.add('proof');
        final result = receipts.putIfAbsent(key, () {
          uploads++;
          return {
            'id': 'proof-$key',
            'entityId': 21,
            'deliveryId': 12,
            'tripVersion': trip['version'],
          };
        });
        return reply(result, 200);
      }
      final body = r.data as Map;
      final key = body['operationKey'] as String;
      if (receipts.containsKey(key)) return reply(receipts[key]!, 200);
      final kind = r.path.split('/').last;
      if ((kind == 'collected' ? body['tripVersion'] : body['version']) !=
          trip['version']) {
        return reply({
          'code': 'VERSION_CONFLICT',
          'message': 'Assignment changed',
        }, 409);
      }
      effects++;
      submitted.add(kind);
      final before = trip['version'] as int;
      trip['version'] = before + 1;
      if (kind != 'collected') {
        final stop = (trip['stops'] as List).cast<Map>().firstWhere(
          (s) => '${s['id']}' == r.path.split('/')[3],
        );
        stop['status'] = kind;
      } else {
        (trip['pickups'] as List).single['status'] = 'collected';
      }
      final result = receipts[key] = {
        'ok': true,
        'deliveryId': 12,
        'previousTripVersion': before,
        'tripVersion': before + 1,
      };
      if (loseOutcomeResponse) {
        loseOutcomeResponse = false;
        throw DioException(
          requestOptions: r,
          type: DioExceptionType.receiveTimeout,
        );
      }
      return reply(result, 200);
    }
    throw StateError('Unexpected fixture request ${r.method} ${r.path}');
  }
}

class BoundSessionStore extends MemorySessionStore
    implements SessionIdentityStore {
  String? scope;
  @override
  Future<String?> readScope() async => scope;
  @override
  Future<void> writeScope(String value) async {
    scope = value;
  }

  @override
  Future<void> clear() async {
    await super.clear();
    scope = null;
  }
}

class LegacyCache extends DriverCacheDatabase {
  LegacyCache(super.executor);
  @override
  int get schemaVersion => 1;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) => customStatement('''CREATE TABLE driver_read_cache (
    scope_key TEXT NOT NULL, request_key TEXT NOT NULL, payload TEXT NOT NULL,
    saved_at INTEGER NOT NULL, PRIMARY KEY(scope_key, request_key))'''),
  );
}

class V2Cache extends DriverCacheDatabase {
  V2Cache(super.executor);
  @override
  int get schemaVersion => 2;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await super.migration.onCreate(m);
      await customStatement('DROP TABLE local_proof_cache');
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Two independent executors are intentional in the cross-connection lease test.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory directory;
  late DriverCacheDatabase db;
  late SyncFixture fixture;
  late MemorySessionStore session;
  late ApiClient api;
  late DriverRepository repo;
  late File file;
  final photo = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
    ),
  );
  ApiClient client() => ApiClient(
    baseUrl: 'http://localhost:5192',
    sessionStore: session,
    transport: Dio()..httpClientAdapter = TestAdapter(fixture.handle),
  );
  DriverRepository repository() => DriverRepository(
    api,
    cache: db,
    attachmentStore: AttachmentStore(
      directory: Directory('${directory.path}/proofs'),
    ),
  );

  setUp(() async {
    final base = Directory('../.tmp/offline-sync-tests')
      ..createSync(recursive: true);
    directory = base.createTempSync('sync-');
    file = File('${directory.path}/cache.sqlite');
    db = DriverCacheDatabase(NativeDatabase(file));
    fixture = SyncFixture();
    session = MemorySessionStore();
    api = client();
    repo = repository();
    await api.login('driver@test', 'password', true);
    await api.validate();
    await repo.profile();
    await repo.trips();
    await repo.history();
    await repo.checkSyncCapability();
  });
  tearDown(() async {
    await repo.sync.shutdown();
    api.dio.close(force: true);
    await db.close();
    directory.deleteSync(recursive: true);
  });

  Future<void> disconnected() async {
    fixture.offline = true;
    repo.enterOffline();
  }

  Future<Trip> savedTrip() => repo.saved(() => repo.trip('12'));
  Future<void> reopen() async {
    await repo.sync.shutdown();
    api.dio.close(force: true);
    await db.close();
    db = DriverCacheDatabase(NativeDatabase(file));
    api = client();
    await api.restore();
    repo = repository();
    await repo.restoreSync();
  }

  Future<void> drain() async {
    fixture.offline = false;
    await api.validate();
    await db.customStatement('UPDATE sync_outbox SET next_attempt = 0');
    await repo.sync.request();
  }

  test(
    'proof and three ordered actions survive restart and synchronize once',
    () async {
      await disconnected();
      var trip = await savedTrip();
      await repo.uploadProof(
        '21',
        photo,
        'photo',
        '00000000-0000-4000-8000-000000000001',
      );
      await repo.sync.request();
      await repo.outcome(
        trip.stops[0],
        trip.version,
        '00000000-0000-4000-8000-000000000002',
      );
      await repo.outcome(
        trip.stops[1],
        trip.version,
        '00000000-0000-4000-8000-000000000003',
        reason: 'Closed',
      );
      await repo.collectReturn(
        trip.pickups.single,
        '00000000-0000-4000-8000-000000000004',
      );
      await reopen();
      trip = await savedTrip();
      expect(trip.stops[0].status, StopStatus.pending);
      expect(trip.stops[0].pendingSync, 'delivered');
      expect(trip.pickups.single.pendingSync, 'collected');
      expect(repo.sync.pendingCount, 4);
      expect(
        await repo.proofBytes(
          '21',
          'local:00000000-0000-4000-8000-000000000001',
        ),
        photo,
      );
      await drain();
      expect(fixture.submitted, ['proof', 'delivered', 'failed', 'collected']);
      expect(fixture.effects, 3);
      expect(fixture.uploads, 1);
      expect(repo.sync.commands.every((c) => c.accepted && c.reconciled), true);
      expect((await savedTrip()).stops.first.pendingSync, null);
      await repo.sync.request();
      expect(fixture.effects, 3);
    },
  );

  test(
    'lost acknowledgment resolves by receipt after restart and reassignment',
    () async {
      await disconnected();
      final trip = await savedTrip();
      await repo.outcome(
        trip.stops[0],
        trip.version,
        '00000000-0000-4000-8000-000000000005',
        reason: 'Closed',
      );
      fixture.loseOutcomeResponse = true;
      await drain();
      expect(fixture.effects, 1);
      expect(repo.sync.commands.single.state, 'retry_wait');
      fixture.offline = true;
      await reopen();
      fixture.reassigned = true;
      await drain();
      expect(fixture.effects, 1);
      expect(repo.sync.commands.single.accepted, true);
      expect(repo.sync.commands.single.reconciled, false);
    },
  );

  test(
    'external version change conflicts instead of rebasing a queued action',
    () async {
      await disconnected();
      final trip = await savedTrip();
      await repo.outcome(
        trip.stops[0],
        trip.version,
        '00000000-0000-4000-8000-000000000006',
        reason: 'Closed',
      );
      fixture.trip['version'] = 4;
      await drain();
      expect(repo.sync.commands.single.state, 'conflict');
      expect(fixture.effects, 0);
    },
  );

  test(
    'duplicate stop intent is rejected; other scopes cannot see it',
    () async {
      await disconnected();
      final trip = await savedTrip();
      await repo.outcome(
        trip.stops[0],
        trip.version,
        '00000000-0000-4000-8000-000000000007',
        reason: 'Closed',
      );
      await expectLater(
        repo.outcome(
          trip.stops[0],
          trip.version,
          '00000000-0000-4000-8000-000000000008',
        ),
        throwsStateError,
      );
      expect(await repo.outbox.commands('another-driver'), isEmpty);
      expect((await repo.outbox.commands(api.cacheScope!)).length, 1);
    },
  );

  test(
    'missing attachment blocks delivery and preserves both queued commands',
    () async {
      await disconnected();
      final trip = await savedTrip();
      const key = '00000000-0000-4000-8000-000000000009';
      await repo.uploadProof('21', photo, 'photo', key);
      await repo.outcome(
        trip.stops[0],
        trip.version,
        '00000000-0000-4000-8000-000000000010',
      );
      final attachment = await repo.outbox.attachment(api.cacheScope!, key);
      await File(attachment!['path'] as String).delete();
      await drain();
      expect(repo.sync.commands[0].state, 'rejected');
      expect(repo.sync.commands[1].state, 'blocked_dependency');
      expect(fixture.effects, 0);
    },
  );

  test('local-first reads complete before a delayed refresh; cached pages remain explicit', () async {
    final held = Completer<ResponseBody>();
    api.dio.httpClientAdapter = TestAdapter(
      (r) => r.path == '/driver/trips/12' ? held.future : fixture.handle(r),
    );
    final trip = await repo.trip('12').timeout(const Duration(seconds: 1));
    expect(trip.id, '12');
    await expectLater(repo.saved(() => repo.trips(page: 99)), throwsStateError);
    held.complete(reply(fixture.trip, 200));
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });

  test('database leases serialize independent connections and recover expired owners', () async {
    final second = DriverCacheDatabase(NativeDatabase(file));
    try {
      final a = repo.outbox, b = OutboxStore(second), now = DateTime.now();
      expect(await a.acquire('scope', 'foreground', now), true);
      expect(await b.acquire('scope', 'background', now), false);
      expect(
        await b.acquire(
          'scope',
          'background',
          now.add(const Duration(minutes: 3)),
        ),
        true,
      );
      await a.release('scope', 'foreground');
      expect(
        await a.acquire(
          'scope',
          'foreground',
          now.add(const Duration(minutes: 3)),
        ),
        false,
      );
    } finally {
      await second.close();
    }
  });

  test('downloaded proof remains viewable offline after reopening with writes disabled', () async {
    var downloads = 0;
    api.dio.httpClientAdapter = TestAdapter((r) async {
      if (r.path == '/driver/stops/21/proofs/remote-photo') {
        downloads++;
        return ResponseBody.fromBytes(
          photo,
          200,
          headers: {
            Headers.contentTypeHeader: ['image/png'],
          },
        );
      }
      if (r.path == '/driver/stops/21/proofs')
        return reply([
          {'id': 'remote-photo', 'kind': 'photo', 'createdAt': 'now'},
        ], 200);
      return fixture.handle(r);
    });
    await repo.network(() => repo.proofs('21'));
    expect(await repo.proofBytes('21', 'remote-photo'), photo);
    expect(downloads, 1);
    await disconnected();
    await reopen();
    repo.offlineWritesEnabled = false;
    repo.enterOffline();
    expect(await repo.proofBytes('21', 'remote-photo'), photo);
    expect((await repo.proofs('21')).single['availableOffline'], true);
    expect(await repo.proofAvailableOffline('22', 'remote-photo'), false);
    expect(downloads, 1);
  });

  test(
    'uploaded proof retains offline access through its server identifier',
    () async {
      await disconnected();
      const key = '00000000-0000-4000-8000-000000000021';
      await repo.uploadProof('21', photo, 'photo', key);
      await repo.sync.request();
      await drain();
      final serverId = repo.sync.commands.single.result!['id'] as String;
      api.dio.httpClientAdapter = TestAdapter(
        (r) async => r.path == '/driver/stops/21/proofs'
            ? reply([
                {'id': serverId, 'kind': 'photo', 'createdAt': 'now'},
              ], 200)
            : fixture.handle(r),
      );
      await repo.network(() => repo.proofs('21'));
      await disconnected();
      final proofs = await repo.proofs('21');
      expect(proofs.single['id'], serverId);
      expect(proofs.single['availableOffline'], true);
      expect(await repo.proofBytes('21', serverId), photo);
    },
  );

  test(
    'logout removes downloaded proof files and account-scoped cache metadata',
    () async {
      api.dio.httpClientAdapter = TestAdapter(
        (r) async => r.path.endsWith('/remote-photo')
            ? ResponseBody.fromBytes(photo, 200)
            : fixture.handle(r),
      );
      await repo.proofBytes('21', 'remote-photo');
      final row = await db
          .customSelect('SELECT path FROM local_proof_cache')
          .getSingle();
      final saved = File(row.read<String>('path'));
      expect(await saved.exists(), true);
      await api.clear();
      expect(await saved.exists(), false);
      expect(
        await db.customSelect('SELECT * FROM local_proof_cache').get(),
        isEmpty,
      );
      expect(await repo.proofAvailableOffline('21', 'remote-photo'), false);
    },
  );

  test('local pending photos stay readable when server synchronization is unavailable', () async {
    await disconnected();
    const key = '00000000-0000-4000-8000-000000000022';
    await repo.uploadProof('21', photo, 'photo', key); await repo.sync.request();
    repo.syncSupported = false; repo.offlineWritesEnabled = false;
    final proofs = await repo.proofs('21');
    expect(proofs.single['availableOffline'], true);
    expect(await repo.proofBytes('21', 'local:$key'), photo);
  });

  test('uncached photo explains its connection requirement offline', () async {
    await disconnected();
    await expectLater(
      repo.proofBytes('21', 'never-downloaded'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('not saved on this device'),
        ),
      ),
    );
  });

  test(
    'v2 database upgrades preserve queued work and add the photo cache',
    () async {
      final oldFile = File('${directory.path}/v2.sqlite');
      final old = V2Cache(NativeDatabase(oldFile));
      await OutboxStore(old).enqueue(
        scope: 'scope',
        key: 'v2-command',
        kind: 'failed',
        tripId: '12',
        entityId: '21',
        version: 3,
        payload: {'reason': 'Closed'},
        current: () => true,
      );
      await old.close();
      final upgraded = DriverCacheDatabase(NativeDatabase(oldFile));
      try {
        expect(
          (await OutboxStore(upgraded).commands('scope')).single.key,
          'v2-command',
        );
        expect(
          await upgraded.customSelect('SELECT * FROM local_proof_cache').get(),
          isEmpty,
        );
      } finally {
        await upgraded.close();
      }
    },
  );

  test(
    'actual v1 database upgrades without losing downloaded snapshots',
    () async {
      final oldFile = File('${directory.path}/old.sqlite');
      final legacy = LegacyCache(NativeDatabase(oldFile));
      await legacy.customStatement(
        'INSERT INTO driver_read_cache VALUES (?, ?, ?, ?)',
        ['scope', 'saved', '{"id":12}', DateTime.now().millisecondsSinceEpoch],
      );
      await legacy.close();
      final upgraded = DriverCacheDatabase(NativeDatabase(oldFile));
      try {
        expect((await upgraded.read('scope', 'saved'))?.data, {'id': 12});
        expect(await OutboxStore(upgraded).commands('scope'), isEmpty);
        expect(
          (await upgraded.customSelect('PRAGMA user_version').getSingle())
              .read<int>('user_version'),
          3,
        );
      } finally {
        await upgraded.close();
      }
    },
  );

  test(
    'rollout gate stops new offline actions while existing work can drain',
    () async {
      await disconnected();
      final trip = await savedTrip();
      await repo.outcome(
        trip.stops[0],
        trip.version,
        '00000000-0000-4000-8000-000000000015',
        reason: 'Closed',
      );
      await repo.sync.request();
      fixture.offline = false;
      fixture.acceptNewCommands = false;
      await repo.checkSyncCapability();
      expect(repo.offlineWritesEnabled, false);
      expect(repo.syncSupported, true);
      await expectLater(
        repo.outcome(
          trip.stops[1],
          trip.version,
          '00000000-0000-4000-8000-000000000016',
          reason: 'Closed',
        ),
        throwsStateError,
      );
      await drain();
      expect(fixture.effects, 1);
      expect(repo.sync.pendingCount, 0);
    },
  );

  test(
    'revoked authentication quarantines work without deleting the outbox',
    () async {
      await disconnected();
      final trip = await savedTrip();
      await repo.outcome(
        trip.stops[0],
        trip.version,
        '00000000-0000-4000-8000-000000000017',
        reason: 'Closed',
      );
      await repo.sync.request();
      final scope = api.cacheScope!;
      fixture.offline = false;
      api.dio.httpClientAdapter = TestAdapter(
        (r) async => r.path.startsWith('/auth/')
            ? reply({'message': 'Revoked'}, 401)
            : fixture.handle(r),
      );
      await expectLater(api.validate(), throwsStateError);
      expect(api.cacheScope, null);
      final work = await repo.outbox.commands(scope);
      expect(work.single.state, 'blocked_auth');
      expect(fixture.effects, 0);
      api.dio.httpClientAdapter = TestAdapter(fixture.handle);
      await api.login('driver@test', 'password', true);
      await api.validate();
      await drain();
      expect(fixture.effects, 1);
    },
  );

  test('reviewed server rejection can be discarded before recording a corrected action', () async {
    await disconnected();
    final trip = await savedTrip();
    const key = '00000000-0000-4000-8000-000000000018';
    await repo.outcome(trip.stops[0], trip.version, key, reason: 'Closed');
    await repo.sync.request();
    fixture.offline = false;
    api.dio.httpClientAdapter = TestAdapter(
      (r) async => r.method == 'POST' && r.path.endsWith('/failed')
          ? reply({'code': 'OUTCOME_CHANGED', 'message': 'Needs review'}, 409)
          : fixture.handle(r),
    );
    await repo.sync.request();
    expect(repo.sync.commands.single.state, 'conflict');
    expect(repo.sync.commands.single.sendPayload, isNotNull);
    await repo.discardUnsent(key);
    expect(repo.sync.commands, isEmpty);
    api.dio.httpClientAdapter = TestAdapter(fixture.handle);
    await repo.outcome(
      trip.stops[0],
      trip.version,
      '00000000-0000-4000-8000-000000000019',
      reason: 'Customer unavailable',
    );
    await drain();
    expect(fixture.effects, 1);
  });

  test(
    'damaged command payload stays visible and is never submitted',
    () async {
      await disconnected();
      final trip = await savedTrip();
      await repo.outcome(
        trip.stops[0],
        trip.version,
        '00000000-0000-4000-8000-000000000020',
        reason: 'Closed',
      );
      await repo.sync.request();
      await db.customStatement("UPDATE sync_outbox SET payload = '{'");
      await drain();
      expect(repo.sync.commands.single.state, 'rejected');
      expect(repo.sync.commands.single.errorCode, 'COMMAND_UNSUPPORTED');
      expect(fixture.effects, 0);
    },
  );

  test('stale assignments cannot enqueue, while pending data survives cache pruning', () async {
    await disconnected();
    final trip = await savedTrip();
    await repo.outcome(
      trip.stops[0],
      trip.version,
      '00000000-0000-4000-8000-000000000011',
      reason: 'Closed',
    );
    await db.customStatement('UPDATE local_trips SET saved_at = 0');
    await expectLater(
      repo.outcome(
        trip.stops[1],
        trip.version,
        '00000000-0000-4000-8000-000000000012',
        reason: 'Closed',
      ),
      throwsStateError,
    );
    await db.customStatement('UPDATE driver_read_cache SET saved_at = 0');
    expect((await savedTrip()).stops.first.pendingSync, 'failed');
    expect(repo.sync.pendingCount, 1);
  });

  test(
    'older parallel responses cannot overwrite a newer confirmed trip version',
    () async {
      final scope = api.cacheScope!;
      await db.save(scope, {
        '/driver/trips/12:{}': {...fixture.trip, 'version': 9},
      }, () => true);
      await db.save(scope, {
        '/driver/trips/12:{}': {...fixture.trip, 'version': 4},
      }, () => true);
      expect((await savedTrip()).version, 9);
    },
  );

  test(
    'a failed local transaction cannot report or retain an enqueued action',
    () async {
      final scope = api.cacheScope!;
      var checks = 0;
      await expectLater(
        repo.outbox.enqueue(
          scope: scope,
          key: 'rollback',
          kind: 'failed',
          tripId: '12',
          entityId: '21',
          version: 3,
          payload: {'reason': 'Closed'},
          current: () => ++checks == 1,
        ),
        throwsStateError,
      );
      expect(await repo.outbox.commands(scope), isEmpty);
    },
  );

  test(
    'rate limits persist Retry-After and the frozen request across restart',
    () async {
      await disconnected();
      final trip = await savedTrip();
      await repo.outcome(
        trip.stops[0],
        trip.version,
        '00000000-0000-4000-8000-000000000013',
        reason: 'Closed',
      );
      fixture.offline = false;
      api.dio.httpClientAdapter = TestAdapter((r) async {
        if (r.method == 'POST' && r.path.endsWith('/failed')) {
          return ResponseBody.fromString(
            '{"message":"Slow down"}',
            429,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
              'retry-after': ['120'],
            },
          );
        }
        return fixture.handle(r);
      });
      await repo.sync.request();
      final command = repo.sync.commands.single;
      expect(command.state, 'retry_wait');
      expect(command.sendPayload?['version'], 3);
      expect(
        command.nextAttempt,
        greaterThan(
          DateTime.now()
              .add(const Duration(seconds: 110))
              .millisecondsSinceEpoch,
        ),
      );
      await reopen();
      expect(repo.sync.commands.single.sendPayload, command.sendPayload);
      await repo.sync.request();
      expect(fixture.effects, 0);
    },
  );

  test('unsent discard cannot race a later send, and attempted work stays protected', () async {
    await disconnected();
    final trip = await savedTrip();
    const key = '00000000-0000-4000-8000-000000000014';
    await repo.outcome(trip.stops[0], trip.version, key, reason: 'Closed');
    await repo.sync.request();
    final before = (await repo.outbox.commands(api.cacheScope!)).single;
    await repo.discardUnsent(key);
    expect(await repo.outbox.freeze(before, {'version': 3}), false);
    expect(await repo.outbox.commands(api.cacheScope!), isEmpty);
  });

  test('validated account namespace survives credential rotation and stays origin-bound', () async {
    final bound = BoundSessionStore();
    ApiClient boundClient(String origin) => ApiClient(
      baseUrl: origin,
      sessionStore: bound,
      transport: Dio()
        ..httpClientAdapter = TestAdapter(
          (r) async => r.path == '/auth/me'
              ? reply({'role': 'driver', 'id': 3}, 200)
              : fixture.handle(r),
        ),
    );
    final a = boundClient('http://localhost:5192');
    await a.login('driver@test', 'password', true);
    await a.validate();
    final original = a.cacheScope;
    bound.token = 'rotated-refresh-token';
    final b = boundClient('http://localhost:5192');
    await b.restore();
    await b.validate();
    expect(b.cacheScope, original);
    final c = boundClient('http://localhost:5193');
    await c.restore();
    await c.validate();
    expect(c.cacheScope, isNot(original));
    a.dio.close();
    b.dio.close();
    c.dio.close();
  });
}
