import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../data/models.dart';
import '../data/local/driver_cache_database.dart';
import '../services/offline_policy.dart';

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
  final DriverCacheDatabase? _providedCache;
  DriverCacheDatabase? _openedCache;
  DriverCacheDatabase get _cache =>
      _openedCache ??= _providedCache ?? DriverCacheDatabase.shared;
  bool _offlineReadOnly = false, usedCache = false;
  DateTime? cachedAt;
  bool get offline => client.networkUnavailable.value || _offlineReadOnly;
  DriverRepository(this.client, {DriverCacheDatabase? cache})
    : _providedCache = cache {
    client.onCacheInvalidated = (scope) async {
      await _cache.clearScope(scope);
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
  }) async {
    final scope = client.cacheScope, generation = client.sessionGeneration;
    final key = _key(path, query);
    bool current() =>
        scope != null &&
        client.cacheScope == scope &&
        client.sessionGeneration == generation;
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
        return result;
      } on DioException catch (error) {
        if (!isConnectionFailure(error)) {
          if (current() && [401, 403, 404].contains(error.response?.statusCode))
            await _cache.clearScope(scope!);
          rethrow;
        }
        enterOffline();
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
      result = decode(entry.data);
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
  Future<List<Map<String, dynamic>>> proofs(String stopId) => _get(
    '/driver/stops/$stopId/proofs',
    (data) =>
        (data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
  );

  Future<Uint8List> proofBytes(String stopId, String id) async {
    requireOnline();
    return Uint8List.fromList(
      (await client.dio.get<List<int>>(
        '/driver/stops/$stopId/proofs/$id',
        options: Options(responseType: ResponseType.bytes),
      )).data!,
    );
  }

  Future<void> uploadProof(
    String stopId,
    Uint8List bytes,
    String kind,
    String key,
  ) async {
    requireOnline();
    await client.dio.post<dynamic>(
      '/driver/stops/$stopId/proofs',
      data: FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: kind == 'signature' ? 'signature.png' : 'photo.jpg',
        ),
        'kind': kind,
        'operationKey': key,
      }),
      options: Options(extra: {'noRetry': true}),
    );
  }

  Future<void> collectReturn(ReturnPickup pickup, String key) async {
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

  Future<void> outcome(
    Stop stop,
    int version,
    String key, {
    String? reason,
  }) async {
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
}
