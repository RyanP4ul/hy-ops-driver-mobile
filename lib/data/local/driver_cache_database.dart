import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

class CachedRead {
  final Object? data;
  final DateTime savedAt;
  const CachedRead(this.data, this.savedAt);
}

/// Confirmed API snapshots and additive, durable synchronization storage.
class DriverCacheDatabase extends GeneratedDatabase {
  DriverCacheDatabase(super.executor);
  static DriverCacheDatabase? _native;
  static Future<void> closeShared() async {
    final db = _native;
    _native = null;
    await db?.close();
  }

  static DriverCacheDatabase get shared => _native ??= DriverCacheDatabase(
    LazyDatabase(() async {
      final directory = await getApplicationSupportDirectory();
      await directory.create(recursive: true);
      return NativeDatabase.createInBackground(
        File('${directory.path}/hyops_driver_cache.sqlite'),
      );
    }),
  );

  @override
  int get schemaVersion => 3;
  @override
  Iterable<TableInfo> get allTables => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement('''CREATE TABLE driver_read_cache (
      scope_key TEXT NOT NULL, request_key TEXT NOT NULL,
      payload TEXT NOT NULL, saved_at INTEGER NOT NULL,
      PRIMARY KEY (scope_key, request_key)
    )''');
      await _createSyncTables();
      await _createProofCache();
    },
    onUpgrade: (_, from, to) async {
      if (from < 2) await _createSyncTables();
      if (from < 3) await _createProofCache();
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA busy_timeout = 5000');
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _createProofCache() =>
      customStatement('''CREATE TABLE local_proof_cache (
    scope_key TEXT NOT NULL, stop_id TEXT NOT NULL, proof_id TEXT NOT NULL,
    path TEXT NOT NULL, byte_size INTEGER NOT NULL, sha256 TEXT NOT NULL,
    saved_at INTEGER NOT NULL, PRIMARY KEY(scope_key, stop_id, proof_id))''');

  Future<void> _createSyncTables() async {
    for (final name in [
      'local_driver_profiles',
      'local_trips',
      'local_stops',
      'local_return_pickups',
      'local_history',
    ]) {
      await customStatement('''CREATE TABLE $name (
        scope_key TEXT NOT NULL, entity_id TEXT NOT NULL, parent_id TEXT,
        payload TEXT NOT NULL, saved_at INTEGER NOT NULL,
        PRIMARY KEY(scope_key, entity_id))''');
    }
    await customStatement(
      '''CREATE TABLE sync_outbox (
      sequence INTEGER PRIMARY KEY AUTOINCREMENT, operation_key TEXT NOT NULL UNIQUE,
      scope_key TEXT NOT NULL, kind TEXT NOT NULL, trip_id TEXT NOT NULL,
      entity_id TEXT NOT NULL, payload TEXT NOT NULL, payload_hash TEXT NOT NULL,
      command_version INTEGER NOT NULL DEFAULT 1,
      base_version INTEGER NOT NULL, send_payload TEXT, dependencies TEXT NOT NULL,
      state TEXT NOT NULL DEFAULT 'pending', attempts INTEGER NOT NULL DEFAULT 0,
      next_attempt INTEGER NOT NULL DEFAULT 0, error_code TEXT, error_message TEXT,
      result TEXT, reconciled INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL)''',
    );
    await customStatement(
      'CREATE INDEX outbox_scope_sequence ON sync_outbox(scope_key, sequence)',
    );
    await customStatement('''CREATE UNIQUE INDEX outbox_pending_entity ON sync_outbox(scope_key, kind, entity_id)
      WHERE kind <> 'proof' AND state <> 'acknowledged' ''');
    await customStatement('''CREATE TABLE local_attachments (
      operation_key TEXT PRIMARY KEY, scope_key TEXT NOT NULL, stop_id TEXT NOT NULL,
      path TEXT NOT NULL, kind TEXT NOT NULL, byte_size INTEGER NOT NULL,
      sha256 TEXT NOT NULL, server_id TEXT)''');
    await customStatement('''CREATE TABLE sync_metadata (
      scope_key TEXT NOT NULL, name TEXT NOT NULL, value TEXT NOT NULL,
      PRIMARY KEY(scope_key, name))''');
    await customStatement(
      '''CREATE TABLE sync_leases (
      scope_key TEXT PRIMARY KEY, owner TEXT NOT NULL, expires_at INTEGER NOT NULL)''',
    );
  }

  void changed() => notifyUpdates({const TableUpdate('driver_local_data')});
  Stream<void> get changes =>
      tableUpdates(TableUpdateQuery.onTableName('driver_local_data'))
          .map((_) {});

  Future<CachedRead?> read(String scope, String key) async {
    final rows = await customSelect(
      'SELECT payload, saved_at FROM driver_read_cache WHERE scope_key = ? AND request_key = ?',
      variables: [Variable(scope), Variable(key)],
    ).get();
    if (rows.isEmpty) return null;
    final savedAt = DateTime.fromMillisecondsSinceEpoch(
      rows.first.read<int>('saved_at'),
      isUtc: true,
    );
    if (DateTime.now().toUtc().difference(savedAt) > const Duration(days: 7)) {
      final pending = await customSelect(
        "SELECT 1 FROM sync_outbox WHERE scope_key = ? AND (state <> 'acknowledged' OR reconciled = 0) LIMIT 1",
        variables: [Variable(scope)],
      ).get();
      if (pending.isEmpty) {
        await remove(scope, key);
        return null;
      }
    }
    try {
      return CachedRead(
        jsonDecode(rows.first.read<String>('payload')),
        savedAt,
      );
    } on FormatException {
      await remove(scope, key);
      return null;
    }
  }

  Future<void> save(
    String scope,
    Map<String, Object?> snapshots,
    bool Function() stillCurrent,
  ) => transaction(() async {
    if (!stillCurrent()) return;
    final now = DateTime.now().toUtc();
    await customStatement(
      "DELETE FROM driver_read_cache WHERE saved_at < ? AND scope_key NOT IN (SELECT scope_key FROM sync_outbox WHERE state <> 'acknowledged' OR reconciled = 0)",
      [now.subtract(const Duration(days: 7)).millisecondsSinceEpoch],
    );
    for (final entry in snapshots.entries) {
      final path = entry.key.split(':').first;
      final data = entry.value;
      if (path.startsWith('/driver/trips/') && data is Map) {
        final prior = await customSelect(
          'SELECT payload FROM local_trips WHERE scope_key = ? AND entity_id = ?',
          variables: [Variable(scope), Variable('${data['id']}')],
        ).get();
        if (prior.isNotEmpty) {
          final old = jsonDecode(prior.single.read<String>('payload')) as Map;
          if (old['version'] is num &&
              data['version'] is num &&
              old['version'] > data['version'])
            continue;
        }
      }
      await customStatement(
        'INSERT OR REPLACE INTO driver_read_cache(scope_key, request_key, payload, saved_at) VALUES (?, ?, ?, ?)',
        [scope, entry.key, jsonEncode(entry.value), now.millisecondsSinceEpoch],
      );
      // Page snapshots retain filter/page membership; entity records carry the
      // freshest confirmed detail independently of pending outbox overlays.
      if (path == '/driver/profile' && data is Map) {
        await _saveEntity('local_driver_profiles', scope, data, null, now);
      } else if (path.startsWith('/driver/trips/') && data is Map) {
        await _saveEntity('local_trips', scope, data, null, now);
        for (final table in ['local_stops', 'local_return_pickups']) {
          await customStatement(
            'DELETE FROM $table WHERE scope_key = ? AND parent_id = ?',
            [scope, '${data['id']}'],
          );
        }
        for (final stop in data['stops'] as List? ?? []) {
          await _saveEntity(
            'local_stops',
            scope,
            stop as Map,
            '${data['id']}',
            now,
          );
        }
        for (final pickup in data['pickups'] as List? ?? []) {
          await _saveEntity(
            'local_return_pickups',
            scope,
            pickup as Map,
            '${data['id']}',
            now,
          );
        }
      } else if (path == '/driver/history' && data is Map) {
        for (final item in data['items'] as List? ?? []) {
          await _saveEntity(
            'local_history',
            scope,
            item as Map,
            '${item['tripId']}',
            now,
          );
        }
      }
    }
    if (!stillCurrent()) await clearScope(scope);
    changed();
  });
  Future<void> _saveEntity(
    String table,
    String scope,
    Map data,
    String? parent,
    DateTime now,
  ) => customStatement(
    'INSERT OR REPLACE INTO $table(scope_key, entity_id, parent_id, payload, saved_at) VALUES (?, ?, ?, ?, ?)',
    [
      scope,
      '${data['id']}',
      parent,
      jsonEncode(data),
      now.millisecondsSinceEpoch,
    ],
  );
  Future<void> remove(String scope, String key) => customStatement(
    'DELETE FROM driver_read_cache WHERE scope_key = ? AND request_key = ?',
    [scope, key],
  );
  Future<void> clearScope(String scope) => transaction(() async {
    for (final table in [
      'driver_read_cache',
      'local_driver_profiles',
      'local_trips',
      'local_stops',
      'local_return_pickups',
      'local_history',
      'local_proof_cache',
    ]) {
      await customStatement('DELETE FROM $table WHERE scope_key = ?', [scope]);
    }
    changed();
  });
}
