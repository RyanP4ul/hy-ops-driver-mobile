import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart' show Variable;

import '../api/api_client.dart';
import '../data/models.dart';
import '../data/local/driver_cache_database.dart';
import '../services/offline_policy.dart';
import '../services/attachment_store.dart';
import '../services/sync_coordinator.dart';
import '../data/local/outbox_store.dart';

class PageResult<T> {
  final List<T> items;
  final int total;
  PageResult(this.items, this.total);
}

class DriverRepository {
  static const defaultAutomaticRefreshInterval = Duration(seconds: 30);

  Future<Duration> automaticRefreshInterval() =>
      _get('/driver/settings', (data) {
        final value = (data as Map)['mobile_automatic_refresh_interval_ms'];
        final milliseconds = int.tryParse(value?.toString().trim() ?? '');
        return milliseconds != null && milliseconds > 0
            ? Duration(milliseconds: milliseconds)
            : defaultAutomaticRefreshInterval;
      });

  final ApiClient client;
  void Function(String tripId)? onTripUnavailable;
  final AttachmentStore attachments;
  late final OutboxStore outbox = OutboxStore(_cache);
  late final SyncCoordinator sync = SyncCoordinator(
    client: client,
    store: outbox,
    capability: checkSyncCapability,
    fetchTrip: _fetchTripForSync,
    send: _sendQueued,
    reconcile: _reconcile,
  );
  bool get preferSaved => Zone.current[#driverSavedOnly] == true;
  Future<T> saved<T>(Future<T> Function() read) =>
      runZoned(read, zoneValues: {#driverSavedOnly: true});
  bool get _networkRead => Zone.current[#driverNetworkRead] == true;
  Future<T> network<T>(Future<T> Function() read) =>
      runZoned(read, zoneValues: {#driverNetworkRead: true});
  final Map<String, Future<void>> _backgroundReads = {};
  bool syncSupported = false;
  bool offlineWritesEnabled = false;
  int offlineWriteMaxAgeHours = 24;
  Stream<void> get changes => _cache.changes;
  Future<void> restoreSync() async {
    final scope = client.cacheScope;
    if (scope == null) return;
    syncSupported = await outbox.metadata(scope, 'protocol') == '1';
    offlineWritesEnabled = await outbox.metadata(scope, 'accept_new') == 'true';
    offlineWriteMaxAgeHours =
        int.tryParse(await outbox.metadata(scope, 'max_age_hours') ?? '') ?? 24;
    await sync.load();
    await _pruneProofCache(scope);
    if (syncSupported || sync.commands.isNotEmpty) await recoverAttachments();
  }

  Future<void> recoverAttachments() async {
    final scope = client.cacheScope;
    if (scope == null) return;
    final commands = await outbox.commands(scope);
    for (final file in await outbox.attachments(scope)) {
      final command = commands
          .where((c) => c.key == file['operation_key'])
          .firstOrNull;
      if (command != null &&
          command.accepted &&
          command.reconciled &&
          DateTime.now().toUtc().difference(
                DateTime.fromMillisecondsSinceEpoch(
                  command.createdAt,
                  isUtc: true,
                ),
              ) >
              const Duration(days: 7)) {
        await attachments.remove(file['path'] as String);
        await _cache.customStatement(
          'DELETE FROM local_attachments WHERE scope_key = ? AND operation_key = ?',
          [scope, command.key],
        );
        continue;
      }
      if (command != null &&
          command.pending &&
          !await File(file['path'] as String).exists()) {
        await outbox.mark(
          command,
          'rejected',
          'PROOF_MISSING',
          'Saved proof file is missing. Review this action.',
        );
      }
    }
    // A failed file/database commit may leave a file without a row. Never prune
    // files referenced by any account, including quarantined sessions.
    final referenced = await _cache
        .customSelect(
          'SELECT path FROM local_attachments UNION SELECT path FROM local_proof_cache',
        )
        .get();
    await attachments.removeOrphans(
      referenced.map((r) => r.read<String>('path')).toSet(),
      DateTime.now().subtract(const Duration(days: 1)),
    );
    await sync.load();
  }

  Future<bool> checkSyncCapability() async {
    final scope = client.cacheScope, generation = client.sessionGeneration;
    if (scope == null) return false;
    try {
      final data = (await client.dio.get<dynamic>('/driver/sync/capabilities'))
          .data;
      if (scope != client.cacheScope || generation != client.sessionGeneration)
        return false;
      syncSupported = data is Map && data['protocol'] == 1;
      offlineWritesEnabled =
          syncSupported && data['acceptNewCommands'] != false;
      if (syncSupported) {
        offlineWriteMaxAgeHours =
            ((data['offlineWriteMaxAgeHours'] as num?)?.toInt() ?? 24).clamp(
              1,
              24,
            );
        await outbox.setMetadata(scope, 'protocol', '1');
        await outbox.setMetadata(scope, 'accept_new', '$offlineWritesEnabled');
        await outbox.setMetadata(
          scope,
          'max_age_hours',
          '$offlineWriteMaxAgeHours',
        );
      } else {
        await outbox.setMetadata(scope, 'protocol', '0');
        offlineWritesEnabled = false;
      }
    } on DioException catch (e) {
      if ([404, 405].contains(e.response?.statusCode)) {
        syncSupported = false;
        offlineWritesEnabled = false;
        await outbox.setMetadata(scope, 'protocol', '0');
      } else {
        rethrow;
      }
    }
    return syncSupported;
  }

  final DriverCacheDatabase? _providedCache;
  DriverCacheDatabase? _openedCache;
  DriverCacheDatabase get _cache =>
      _openedCache ??= _providedCache ?? DriverCacheDatabase.shared;
  bool _offlineReadOnly = false, usedCache = false;
  DateTime? cachedAt;
  bool get offline => client.networkUnavailable.value || _offlineReadOnly;
  DriverRepository(
    this.client, {
    DriverCacheDatabase? cache,
    AttachmentStore? attachmentStore,
  }) : _providedCache = cache,
       attachments = attachmentStore ?? AttachmentStore() {
    client.onCacheInvalidated = (scope) async {
      final previews = await _cache
          .customSelect(
            'SELECT path FROM local_proof_cache WHERE scope_key = ?',
            variables: [Variable(scope)],
          )
          .get();
      await _cache.clearScope(scope);
      for (final preview in previews) {
        try {
          await attachments.remove(preview.read<String>('path'));
        } catch (_) {
          debugPrint('Downloaded proof cleanup requires retry.');
        }
      }
    };
    client.onSessionQuarantined = (scope) async {
      for (final c in await outbox.commands(scope)) {
        if (c.pending && !c.needsAttention)
          await outbox.mark(
            c,
            'blocked_auth',
            'AUTH_REQUIRED',
            'Sign in to synchronize saved work.',
          );
      }
    };
  }
  void enterOffline() {
    _offlineReadOnly = true;
    client.networkUnavailable.value = true;
  }

  void beginReadCycle() {
    usedCache = false;
    cachedAt = null;
  }

  void completeRefresh() {
    if (!client.networkUnavailable.value && !usedCache)
      _offlineReadOnly = false;
  }

  void requireOnline() {
    if (offline) throw OfflineActionBlocked();
  }

  static String _key(String path, Map<String, dynamic> query) {
    final keys = query.keys.toList()..sort();
    return '$path:${jsonEncode({for (final key in keys) key: query[key]})}';
  }

  Future<T> _get<T>(
    String path,
    T Function(dynamic) decode, {
    Map<String, dynamic> query = const {},
    bool tripPage = false,
    bool allowFallback = true,
  }) async {
    final scope = client.cacheScope, generation = client.sessionGeneration;
    final key = _key(path, query);
    bool current() =>
        scope != null &&
        client.cacheScope == scope &&
        client.sessionGeneration == generation;
    if (preferSaved && !current()) throw OfflineCacheMiss();
    if ((preferSaved || (syncSupported && !_networkRead)) && current()) {
      final cached = await _cache.read(scope!, key);
      if (cached != null) {
        if (!current()) throw StateError('Session changed.');
        if (!preferSaved && !offline) {
          _backgroundReads.putIfAbsent(
            '$scope/$key',
            () => network(() async {
              try {
                await _get(path, decode, query: query, tripPage: tripPage);
              } catch (_) {
                /* Saved reads stay usable; sync/refresh reports failures. */
              }
            }).whenComplete(() => _backgroundReads.remove('$scope/$key')),
          );
        }
        final overlaid = await _overlay(path, cached.data, scope);
        if (!current()) throw StateError('Session changed.');
        return decode(overlaid);
      }
      if (preferSaved) throw OfflineCacheMiss();
    }
    if (!client.networkUnavailable.value) {
      try {
        final data = (await client.dio.get<dynamic>(
          path,
          queryParameters: query,
        )).data;
        final result = decode(data);
        if (current()) {
          final snapshots = <String, Object?>{key: data};
          if (tripPage) {
            for (final item in (data as Map)['items'] as List)
              snapshots[_key('/driver/trips/${item['id']}', const {})] = item;
          }
          try {
            await _cache.save(scope!, snapshots, current);
          } catch (_) {
            debugPrint(
              'Offline snapshot could not be saved. Online data remains available.',
            );
          }
        }
        if (generation != client.sessionGeneration)
          throw StateError('Session changed.');
        return scope == null
            ? result
            : decode(await _overlay(path, data, scope));
      } on DioException catch (error) {
        if (!isConnectionFailure(error)) {
          if (current() && [401, 403, 404].contains(error.response?.statusCode))
            await _cache.clearScope(scope!);
          rethrow;
        }
        enterOffline();
        if (!allowFallback) rethrow;
      }
    }
    _offlineReadOnly = true;
    if (!current()) throw OfflineCacheMiss();
    CachedRead? entry;
    try {
      entry = await _cache.read(scope!, key);
    } catch (_) {
      throw OfflineCacheMiss();
    }
    if (!current() || entry == null) throw OfflineCacheMiss();
    T result;
    try {
      result = decode(await _overlay(path, entry.data, scope));
    } catch (_) {
      await _cache.remove(scope, key);
      throw OfflineCacheMiss();
    }
    usedCache = true;
    if (cachedAt == null || entry.savedAt.isBefore(cachedAt!))
      cachedAt = entry.savedAt;
    return result;
  }

  Future<Driver> profile() => _get(
    '/driver/profile',
    (data) => Driver.fromJson(Map<String, dynamic>.from(data as Map)),
  );
  Future<PageResult<Trip>> trips({int page = 0, bool past = false}) => _get(
    '/driver/trips',
    (data) => PageResult(
      ((data as Map)['items'] as List)
          .map((e) => Trip.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      data['total'] as int,
    ),
    query: {'page': page, 'pageSize': 20, 'past': '$past'},
    tripPage: true,
  );
  Future<Trip> trip(String id) => _get(
    '/driver/trips/$id',
    (data) => Trip.fromJson(Map<String, dynamic>.from(data as Map)),
  );
  Future<PageResult<HistoryEntry>> history({
    int page = 0,
    String? from,
    String? to,
    String? status,
  }) => _get(
    '/driver/history',
    (data) => PageResult(
      ((data as Map)['items'] as List)
          .map(
            (e) => HistoryEntry.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
      data['total'] as int,
    ),
    query: {
      'page': page,
      'pageSize': 20,
      if (from != null) 'from': from,
      if (to != null) 'to': to,
      if (status != null) 'status': status,
    },
  );
  Future<List<Map<String, dynamic>>> proofs(String stopId) async {
    final generation = client.sessionGeneration;
    List<Map<String, dynamic>> saved = [];
    try {
      saved = await _get(
        '/driver/stops/$stopId/proofs',
        (data) => (data as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );
    } on OfflineCacheMiss {
      final scope = client.cacheScope;
      if (!syncSupported && (scope == null || !(await outbox.commands(scope)).any((c) => c.kind == 'proof' && c.entityId == stopId))) rethrow;
    }
    final scope = client.cacheScope;
    if (scope == null) return saved;
    for (final c in await outbox.commands(scope)) {
      if (c.kind == 'proof' &&
          c.entityId == stopId &&
          !saved.any((p) => p['id'] == c.result?['id'])) {
        if (c.accepted && await outbox.attachment(scope, c.key) == null)
          continue;
        saved.add({
          'id': 'local:${c.key}',
          'kind': c.payload['kind'],
          'createdAt': c.accepted
              ? 'Uploaded'
              : 'Saved on device - pending sync',
        });
      }
    }
    for (final proof in saved) {
      proof['availableOffline'] = await proofAvailableOffline(
        stopId,
        '${proof['id']}',
      );
    }
    if (scope != client.cacheScope || generation != client.sessionGeneration)
      throw StateError('Session changed.');
    return saved;
  }

  Future<Map<String, dynamic>?> _savedProof(
    String scope,
    String stopId,
    String id,
  ) async {
    final local = id.startsWith('local:')
        ? await _cache
              .customSelect(
                'SELECT * FROM local_attachments WHERE scope_key = ? AND stop_id = ? AND operation_key = ?',
                variables: [
                  Variable(scope),
                  Variable(stopId),
                  Variable(id.substring(6)),
                ],
              )
              .get()
        : await _cache
              .customSelect(
                'SELECT * FROM local_attachments WHERE scope_key = ? AND stop_id = ? AND server_id = ?',
                variables: [Variable(scope), Variable(stopId), Variable(id)],
              )
              .get();
    if (local.isNotEmpty) return local.first.data;
    final preview = await _cache
        .customSelect(
          'SELECT * FROM local_proof_cache WHERE scope_key = ? AND stop_id = ? AND proof_id = ?',
          variables: [Variable(scope), Variable(stopId), Variable(id)],
        )
        .get();
    if (preview.isEmpty) return null;
    final saved = preview.single;
    if (DateTime.now().toUtc().difference(
          DateTime.fromMillisecondsSinceEpoch(
            saved.read<int>('saved_at'),
            isUtc: true,
          ),
        ) >
        const Duration(days: 7))
      return null;
    return saved.data;
  }

  Future<bool> proofAvailableOffline(String stopId, String id) async {
    final scope = client.cacheScope;
    if (scope == null) return false;
    final saved = await _savedProof(scope, stopId, id);
    return saved != null &&
        await File(saved['path'] as String).exists() &&
        scope == client.cacheScope;
  }

  Future<Uint8List> proofBytes(String stopId, String id) async {
    final scope = client.cacheScope, generation = client.sessionGeneration;
    bool current() =>
        scope != null &&
        scope == client.cacheScope &&
        generation == client.sessionGeneration;
    if (scope != null) {
      final saved = await _savedProof(scope, stopId, id);
      if (saved != null) {
        try {
          final bytes = await attachments.read(saved);
          if (!current()) throw StateError('Session changed.');
          return bytes;
        } on FileSystemException {
          /* A missing downloaded copy can be fetched again online. */
        } on StateError {
          if (id.startsWith('local:') || !current()) rethrow;
        }
      }
    }
    if (id.startsWith('local:') || offline) {
      throw StateError(
        'This photo is not saved on this device. Connect to download it.',
      );
    }
    requireOnline();
    final bytes = Uint8List.fromList(
      (await client.dio.get<List<int>>(
        '/driver/stops/$stopId/proofs/$id',
        options: Options(responseType: ResponseType.bytes),
      )).data!,
    );
    if (generation != client.sessionGeneration)
      throw StateError('Session changed.');
    if (current()) {
      try {
        final file = await attachments.save(
          scope!,
          'download:$stopId/$id/${DateTime.now().microsecondsSinceEpoch}',
          bytes,
        );
        await _cache.transaction(() async {
          if (!current()) throw StateError('Session changed.');
          await _cache.customStatement(
            '''INSERT OR REPLACE INTO local_proof_cache
            (scope_key, stop_id, proof_id, path, byte_size, sha256, saved_at) VALUES (?, ?, ?, ?, ?, ?, ?)''',
            [
              scope,
              stopId,
              id,
              file['path'],
              file['size'],
              file['hash'],
              DateTime.now().toUtc().millisecondsSinceEpoch,
            ],
          );
          if (!current()) throw StateError('Session changed.');
          _cache.changed();
        });
        await _pruneProofCache(scope);
      } catch (_) {
        debugPrint('Photo could not be saved for offline viewing.');
      }
    }
    if (generation != client.sessionGeneration)
      throw StateError('Session changed.');
    return bytes;
  }

  Future<void> _pruneProofCache(String scope) async {
    final rows = await _cache
        .customSelect(
          'SELECT * FROM local_proof_cache WHERE scope_key = ? ORDER BY saved_at DESC',
          variables: [Variable(scope)],
        )
        .get();
    var keptBytes = 0;
    for (final row in rows) {
      keptBytes += row.read<int>('byte_size');
      final expired =
          DateTime.now().toUtc().difference(
            DateTime.fromMillisecondsSinceEpoch(
              row.read<int>('saved_at'),
              isUtc: true,
            ),
          ) >
          const Duration(days: 7);
      if (!expired && keptBytes <= 100 * 1024 * 1024) continue;
      final removed = await _cache
          .customSelect(
            'DELETE FROM local_proof_cache WHERE scope_key = ? AND stop_id = ? AND proof_id = ? AND saved_at = ? RETURNING path',
            variables: [
              Variable(scope),
              Variable(row.read<String>('stop_id')),
              Variable(row.read<String>('proof_id')),
              Variable(row.read<int>('saved_at')),
            ],
          )
          .get();
      if (removed.isNotEmpty)
        await attachments.remove(removed.single.read<String>('path'));
    }
  }

  Future<void> uploadProof(
    String stopId,
    Uint8List bytes,
    String kind,
    String key,
  ) async {
    if (kind != 'photo') {
      throw StateError('Invalid proof kind.');
    }
    if (syncSupported && offlineWritesEnabled) {
      final context = await _eligible('local_stops', stopId);
      final scope = client.cacheScope!, generation = client.sessionGeneration;
      final existing = await outbox.attachment(scope, key);
      if (existing != null) return;
      final proofs = await this.proofs(stopId);
      if (proofs.where((p) => p['kind'] == 'photo').length >= 3) {
        throw StateError(
          'This stop already has the maximum proofs of this kind.',
        );
      }
      final saved = await attachments.save(scope, key, bytes);
      try {
        await outbox.enqueue(
          scope: scope,
          key: key,
          kind: 'proof',
          tripId: context.$1,
          entityId: stopId,
          version: context.$2,
          payload: {'kind': 'photo'},
          attachment: saved,
          current: () =>
              client.cacheScope == scope &&
              client.sessionGeneration == generation,
        );
      } catch (_) {
        await attachments.remove(saved['path'] as String);
        rethrow;
      }
      await sync.load();
      if (!offline) unawaited(sync.request());
      return;
    }
    requireOnline();
    await client.dio.post<dynamic>(
      '/driver/stops/$stopId/proofs',
      data: FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: 'photo.jpg'),
        'kind': 'photo',
        'operationKey': key,
      }),
      options: Options(extra: {'noRetry': true}),
    );
  }

  Future<void> collectReturn(ReturnPickup pickup, String key) async {
    if (syncSupported && offlineWritesEnabled) {
      final context = await _eligible('local_return_pickups', pickup.id);
      await _enqueue(key, 'collected', context, pickup.id, {
        'version': pickup.version,
      });
      return;
    }
    requireOnline();
    await client.dio.post<dynamic>(
      '/driver/returns/${pickup.id}/collected',
      data: {'version': pickup.version, 'operationKey': key},
    );
  }

  Future<void> startTrip(Trip trip) async {
    requireOnline();
    await client.dio.post<dynamic>(
      '/driver/trips/${trip.id}/start',
      data: {'version': trip.version},
    );
  }

  Future<void> planStop(String stopId, {required bool skip}) async {
    requireOnline();
    await client.dio.post<dynamic>(
      '/driver/stops/$stopId/plan',
      data: {'action': skip ? 'skip' : 'next'},
      options: Options(extra: {'noRetry': true}),
    );
  }

  Future<void> outcome(
    Stop stop,
    int version,
    String key, {
    String? reason,
  }) async {
    if (syncSupported && offlineWritesEnabled) {
      final context = await _eligible('local_stops', stop.id);
      if (reason != null &&
          (reason.trim().isEmpty || reason.trim().length > 500))
        throw StateError('Enter a failure reason up to 500 characters.');
      final dependencies = (await outbox.commands(client.cacheScope!))
          .where((c) => c.kind == 'proof' && c.entityId == stop.id)
          .map((c) => c.key)
          .toList();
      if (reason == null && !stop.hasProof && dependencies.isEmpty)
        throw StateError('Save Proof of Delivery before confirming delivery.');
      await _enqueue(
        key,
        reason == null ? 'delivered' : 'failed',
        context,
        stop.id,
        {if (reason != null) 'reason': reason.trim()},
        dependencies: dependencies,
      );
      return;
    }
    requireOnline();
    await client.dio.post<dynamic>(
      '/driver/stops/${stop.id}/${reason == null ? 'delivered' : 'failed'}',
      data: {
        'version': version,
        'operationKey': key,
        if (reason != null) 'reason': reason,
      },
    );
  }

  Future<(String, int)> _eligible(String table, String id) async {
    final scope = client.cacheScope;
    if (!syncSupported || scope == null || (offline && !client.remember))
      throw OfflineActionBlocked();
    final rows = await _cache
        .customSelect(
          '''SELECT t.payload, t.saved_at, e.payload AS entity_payload
      FROM $table e JOIN local_trips t ON t.scope_key = e.scope_key AND t.entity_id = e.parent_id
      WHERE e.scope_key = ? AND e.entity_id = ?''',
          variables: [Variable(scope), Variable(id)],
        )
        .get();
    if (rows.isEmpty)
      throw StateError(
        'Download this assignment before saving offline actions.',
      );
    final row = rows.single;
    final savedAt = DateTime.fromMillisecondsSinceEpoch(
      row.read<int>('saved_at'),
      isUtc: true,
    );
    final age = DateTime.now().toUtc().difference(savedAt);
    if (age.isNegative || age > Duration(hours: offlineWriteMaxAgeHours))
      throw StateError(
        'Reconnect to verify this assignment before recording another action.',
      );
    final trip = jsonDecode(row.read<String>('payload')) as Map;
    final entity = jsonDecode(row.read<String>('entity_payload')) as Map;
    if (!['in_transit', 'returning'].contains(trip['status']) ||
        (table == 'local_stops' &&
            (trip['status'] != 'in_transit' ||
                entity['status'] != 'pending')) ||
        (table == 'local_return_pickups' && entity['status'] != 'assigned')) {
      throw StateError(
        'This action requires an active, downloaded assignment.',
      );
    }
    return ('${trip['id']}', trip['version'] as int);
  }

  Future<void> _enqueue(
    String key,
    String kind,
    (String, int) context,
    String id,
    Map<String, dynamic> payload, {
    List<String> dependencies = const [],
  }) async {
    final scope = client.cacheScope!, generation = client.sessionGeneration;
    await outbox.enqueue(
      scope: scope,
      key: key,
      kind: kind,
      tripId: context.$1,
      entityId: id,
      version: context.$2,
      payload: payload,
      dependencies: dependencies,
      current: () =>
          client.cacheScope == scope && client.sessionGeneration == generation,
    );
    await sync.load();
    if (!offline) unawaited(sync.request());
  }

  Future<Map<String, dynamic>> _fetchTripForSync(String id) async {
    final scope = client.cacheScope, generation = client.sessionGeneration;
    Map<String, dynamic> data;
    try {
      data = Map<String, dynamic>.from(
        (await client.dio.get<dynamic>('/driver/trips/$id')).data as Map,
      );
    } on DioException catch (failure) {
      if ([403, 404].contains(failure.response?.statusCode) &&
          scope != null &&
          scope == client.cacheScope &&
          generation == client.sessionGeneration) {
        await _cache.transaction(() async {
          for (final table in ['local_stops', 'local_return_pickups']) {
            await _cache.customStatement(
              'DELETE FROM $table WHERE scope_key = ? AND parent_id = ?',
              [scope, id],
            );
          }
          await _cache.customStatement(
            'DELETE FROM local_trips WHERE scope_key = ? AND entity_id = ?',
            [scope, id],
          );
          await _cache.remove(scope, _key('/driver/trips/$id', const {}));
          final pages = await _cache
              .customSelect(
                "SELECT request_key, payload FROM driver_read_cache WHERE scope_key = ? AND request_key LIKE '/driver/trips:%'",
                variables: [Variable(scope)],
              )
              .get();
          for (final page in pages) {
            final payload = jsonDecode(page.read<String>('payload')) as Map;
            if ((payload['items'] as List).any((trip) => '${trip['id']}' == id))
              await _cache.remove(scope, page.read<String>('request_key'));
          }
          _cache.changed();
        });
        if (scope == client.cacheScope &&
            generation == client.sessionGeneration)
          onTripUnavailable?.call(id);
      }
      rethrow;
    }
    Trip.fromJson(data);
    if (scope == null ||
        scope != client.cacheScope ||
        generation != client.sessionGeneration)
      throw StateError('Session changed.');
    await _cache.save(
      scope,
      {_key('/driver/trips/$id', const {}): data},
      () =>
          scope == client.cacheScope && generation == client.sessionGeneration,
    );
    return data;
  }

  Future<Map<String, dynamic>> _sendQueued(
    QueuedCommand c,
    Map<String, dynamic> body,
  ) async {
    dynamic data = body;
    String path;
    if (c.kind == 'proof') {
      final attachment = await outbox.attachment(c.scope, c.key);
      if (attachment == null)
        throw StateError('Saved proof is missing. Review this action.');
      final bytes = await attachments.read(attachment);
      path = '/driver/stops/${c.entityId}/proofs';
      data = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: '${c.key}.proof'),
        'kind': body['kind'],
        'operationKey': c.key,
      });
    } else if (c.kind == 'collected') {
      path = '/driver/returns/${c.entityId}/collected';
    } else if (['delivered', 'failed'].contains(c.kind)) {
      path = '/driver/stops/${c.entityId}/${c.kind}';
    } else {
      throw StateError(
        'Unsupported saved command. Update the app to synchronize.',
      );
    }
    final response = await client.dio.post<dynamic>(
      path,
      data: data,
      onSendProgress: c.kind == 'proof' ? sync.uploadProgress : null,
      options: Options(
        extra: {'noRetry': true},
        sendTimeout: const Duration(seconds: 30),
      ),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> _reconcile(String id) async {
    await _fetchTripForSync(id);
    final scope = client.cacheScope, generation = client.sessionGeneration;
    if (scope != null) {
      final pages = await _cache
          .customSelect(
            "SELECT request_key FROM driver_read_cache WHERE scope_key = ? AND (request_key LIKE '/driver/history:%' OR request_key LIKE '/driver/trips:%')",
            variables: [Variable(scope)],
          )
          .get();
      for (final page in pages) {
        if (scope != client.cacheScope ||
            generation != client.sessionGeneration)
          throw StateError('Session changed.');
        final key = page.read<String>('request_key'),
            split = page.read<String>('request_key').indexOf(':');
        final path = key.substring(0, split);
        final query = Map<String, dynamic>.from(
          jsonDecode(key.substring(split + 1)) as Map,
        );
        await network(
          () => _get(
            path,
            (data) => data,
            query: query,
            tripPage: path == '/driver/trips',
            allowFallback: false,
          ),
        );
      }
      if (!client.networkUnavailable.value) _offlineReadOnly = false;
    }
  }

  Future<Object?> _overlay(String path, Object? value, String scope) async {
    if (value == null || !path.startsWith('/driver/trips')) return value;
    final copy = jsonDecode(jsonEncode(value));
    final commands = await outbox.commands(scope);
    void apply(Map trip) {
      for (final c in commands.where(
        (c) => c.tripId == '${trip['id']}' && (!c.accepted || !c.reconciled),
      )) {
        final items =
            (c.kind == 'collected' ? trip['pickups'] : trip['stops'])
                as List? ??
            [];
        for (final item in items.cast<Map>().where(
          (e) => '${e['id']}' == c.entityId,
        )) {
          if (c.kind != 'proof') {
            item['pendingSync'] = c.kind;
            item['syncError'] = c.needsAttention ? c.errorMessage : null;
            item['canDeliver'] = false;
            item['canFail'] = false;
          } else {
            item['hasLocalProof'] = true;
          }
        }
      }
    }

    if (copy is Map && copy['items'] is List) {
      final items = copy['items'] as List;
      for (var i = 0; i < items.length; i++) {
        final id = '${items[i]['id']}';
        final detail = await _cache.read(
          scope,
          _key('/driver/trips/$id', const {}),
        );
        if (detail?.data is Map)
          items[i] = jsonDecode(jsonEncode(detail!.data));
        apply(items[i] as Map);
      }
    } else if (copy is Map) {
      apply(copy);
    }
    return copy;
  }

  Future<void> discardPending() async {
    final scope = client.cacheScope;
    if (scope == null) return;
    final files = await outbox.attachments(scope);
    await outbox.discard(scope);
    for (final file in files) {
      try {
        await attachments.remove(file['path'] as String);
      } catch (_) {
        debugPrint('Private proof cleanup requires retry.');
      }
    }
    await sync.load();
  }

  Future<void> discardUnsent(String key) async {
    final scope = client.cacheScope, generation = client.sessionGeneration;
    if (scope == null) throw StateError('Sign in to review saved work.');
    final command = (await outbox.commands(scope))
        .where((c) => c.key == key)
        .firstOrNull;
    var reviewed = false;
    if (command != null &&
        command.sendPayload != null &&
        command.needsAttention) {
      await client.validate();
      final receipt =
          (await client.dio.get<dynamic>('/driver/sync/operations/$key')).data
              as Map;
      if (receipt['accepted'] == true) {
        if (scope == client.cacheScope &&
            generation == client.sessionGeneration) {
          await outbox.acknowledge(
            command,
            Map<String, dynamic>.from(receipt['result'] as Map),
            DateTime.now(),
          );
          await sync.load();
        }
        throw StateError(
          'The server accepted this action. Sync to refresh its details.',
        );
      }
      reviewed = true;
    }
    final file = await outbox.attachment(scope, key);
    await outbox.discardUnsent(
      scope,
      key,
      reviewedRejection: reviewed,
      current: () =>
          scope == client.cacheScope && generation == client.sessionGeneration,
    );
    if (file != null) await attachments.remove(file['path'] as String);
    await sync.load();
  }
}
