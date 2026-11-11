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

/// Versioned, read-only API snapshots. Operational commands are never stored.
class DriverCacheDatabase extends GeneratedDatabase {
  DriverCacheDatabase(super.executor);
  static DriverCacheDatabase? _native;
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
  int get schemaVersion => 1;
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
    },
  );

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
      await remove(scope, key);
      return null;
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
    await customStatement('DELETE FROM driver_read_cache WHERE saved_at < ?', [
      now.subtract(const Duration(days: 7)).millisecondsSinceEpoch,
    ]);
    for (final entry in snapshots.entries) {
      await customStatement(
        'INSERT OR REPLACE INTO driver_read_cache(scope_key, request_key, payload, saved_at) VALUES (?, ?, ?, ?)',
        [scope, entry.key, jsonEncode(entry.value), now.millisecondsSinceEpoch],
      );
    }
    if (!stillCurrent()) await clearScope(scope);
  });
  Future<void> remove(String scope, String key) => customStatement(
    'DELETE FROM driver_read_cache WHERE scope_key = ? AND request_key = ?',
    [scope, key],
  );
  Future<void> clearScope(String scope) => customStatement(
    'DELETE FROM driver_read_cache WHERE scope_key = ?',
    [scope],
  );
}
