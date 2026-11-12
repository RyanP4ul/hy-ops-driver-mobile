import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import 'driver_cache_database.dart';

class QueuedCommand {
  final int sequence,
      baseVersion,
      attempts,
      nextAttempt,
      commandVersion,
      createdAt;
  final String key, scope, kind, tripId, entityId, state;
  final String? errorCode, errorMessage;
  final Map<String, dynamic> payload;
  final Map<String, dynamic>? sendPayload, result;
  final List<String> dependencies;
  final bool reconciled;
  final bool payloadValid;
  QueuedCommand(QueryRow row)
    : sequence = row.read<int>('sequence'),
      key = row.read<String>('operation_key'),
      scope = row.read<String>('scope_key'),
      kind = row.read<String>('kind'),
      tripId = row.read<String>('trip_id'),
      entityId = row.read<String>('entity_id'),
      baseVersion = row.read<int>('base_version'),
      attempts = row.read<int>('attempts'),
      commandVersion = row.read<int>('command_version'),
      createdAt = row.read<int>('created_at'),
      nextAttempt = row.read<int>('next_attempt'),
      state = row.read<String>('state'),
      errorCode = row.readNullable<String>('error_code'),
      errorMessage = row.readNullable<String>('error_message'),
      payload = _map(row.read<String>('payload')) ?? {},
      payloadValid =
          _map(row.read<String>('payload')) != null &&
          sha256.convert(utf8.encode(row.read<String>('payload'))).toString() ==
              row.read<String>('payload_hash') &&
          _listValid(row.read<String>('dependencies')) &&
          (row.readNullable<String>('send_payload') == null ||
              _map(row.read<String>('send_payload')) != null),
      sendPayload = _map(row.readNullable<String>('send_payload')),
      result = _map(row.readNullable<String>('result')),
      dependencies = _listValid(row.read<String>('dependencies'))
          ? (jsonDecode(row.read<String>('dependencies')) as List)
                .cast<String>()
          : [],
      reconciled = row.read<int>('reconciled') == 1;
  static Map<String, dynamic>? _map(String? value) {
    try {
      final data = value == null ? null : jsonDecode(value);
      return data is Map<String, dynamic> ? data : null;
    } catch (_) {
      return null;
    }
  }

  static bool _listValid(String value) {
    try {
      final data = jsonDecode(value);
      return data is List && data.every((v) => v is String);
    } catch (_) {
      return false;
    }
  }

  bool get accepted => state == 'acknowledged';
  bool get needsAttention => ['conflict', 'rejected'].contains(state);
  bool get pending => !accepted;
}

class OutboxStore {
  final DriverCacheDatabase db;
  OutboxStore(this.db);

  Future<List<QueuedCommand>> commands(String scope) async =>
      (await db
              .customSelect(
                'SELECT * FROM sync_outbox WHERE scope_key = ? ORDER BY sequence',
                variables: [Variable(scope)],
              )
              .get())
          .map(QueuedCommand.new)
          .toList();

  Future<String?> metadata(String scope, String name) async {
    final rows = await db
        .customSelect(
          'SELECT value FROM sync_metadata WHERE scope_key = ? AND name = ?',
          variables: [Variable(scope), Variable(name)],
        )
        .get();
    return rows.isEmpty ? null : rows.single.read<String>('value');
  }

  Future<void> setMetadata(String scope, String name, String value) async {
    await db.customStatement(
      'INSERT OR REPLACE INTO sync_metadata(scope_key, name, value) VALUES (?, ?, ?)',
      [scope, name, value],
    );
  }

  Future<void> enqueue({
    required String scope,
    required String key,
    required String kind,
    required String tripId,
    required String entityId,
    required int version,
    required Map<String, dynamic> payload,
    List<String> dependencies = const [],
    Map<String, Object?>? attachment,
    required bool Function() current,
  }) => db.transaction(() async {
    if (!current()) throw StateError('Session changed.');
    final existing = await commands(scope);
    if (existing.any((c) => c.key == key)) return;
    if (kind != 'proof' &&
        existing.any(
          (c) =>
              c.entityId == entityId &&
              c.kind != 'proof' &&
              c.kind != 'collected' &&
              kind != 'collected' &&
              c.pending,
        )) {
      throw StateError(
        'This stop already has an action pending synchronization.',
      );
    }
    final encoded = jsonEncode(payload);
    await db.customStatement(
      '''INSERT INTO sync_outbox
        (operation_key, scope_key, kind, trip_id, entity_id, payload, payload_hash,
         base_version, dependencies, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        key,
        scope,
        kind,
        tripId,
        entityId,
        encoded,
        sha256.convert(utf8.encode(encoded)).toString(),
        version,
        jsonEncode(dependencies),
        DateTime.now().toUtc().millisecondsSinceEpoch,
      ],
    );
    if (attachment != null) {
      await db.customStatement(
        '''INSERT INTO local_attachments
          (operation_key, scope_key, stop_id, path, kind, byte_size, sha256) VALUES (?, ?, ?, ?, ?, ?, ?)''',
        [
          key,
          scope,
          entityId,
          attachment['path'],
          payload['kind'],
          attachment['size'],
          attachment['hash'],
        ],
      );
    }
    if (!current()) throw StateError('Session changed.');
    db.changed();
  });

  Future<Map<String, dynamic>?> attachment(String scope, String key) async {
    final rows = await db
        .customSelect(
          'SELECT * FROM local_attachments WHERE scope_key = ? AND operation_key = ?',
          variables: [Variable(scope), Variable(key)],
        )
        .get();
    return rows.isEmpty ? null : rows.single.data;
  }

  Future<List<Map<String, dynamic>>> attachments(String scope) async =>
      (await db
              .customSelect(
                'SELECT * FROM local_attachments WHERE scope_key = ?',
                variables: [Variable(scope)],
              )
              .get())
          .map((r) => r.data)
          .toList();

  Future<bool> acquire(String scope, String owner, DateTime now) =>
      db.transaction(() async {
        final rows = await db
            .customSelect(
              '''INSERT INTO sync_leases(scope_key, owner, expires_at) VALUES (?, ?, ?)
      ON CONFLICT(scope_key) DO UPDATE SET owner = excluded.owner, expires_at = excluded.expires_at
      WHERE sync_leases.expires_at < ? OR sync_leases.owner = ? RETURNING owner''',
              variables: [
                Variable(scope),
                Variable(owner),
                Variable(
                  now.add(const Duration(minutes: 2)).millisecondsSinceEpoch,
                ),
                Variable(now.millisecondsSinceEpoch),
                Variable(owner),
              ],
            )
            .get();
        return rows.isNotEmpty;
      });
  Future<void> release(String scope, String owner) => db.customStatement(
    'DELETE FROM sync_leases WHERE scope_key = ? AND owner = ?',
    [scope, owner],
  );

  Future<bool> freeze(QueuedCommand c, Map<String, dynamic> payload) async {
    final rows = await db
        .customSelect(
          "UPDATE sync_outbox SET send_payload = ?, state = 'in_flight', attempts = attempts + 1 WHERE operation_key = ? AND scope_key = ? RETURNING operation_key",
          variables: [
            Variable(jsonEncode(payload)),
            Variable(c.key),
            Variable(c.scope),
          ],
        )
        .get();
    db.changed();
    return rows.isNotEmpty;
  }

  Future<void> acknowledge(
    QueuedCommand c,
    Map<String, dynamic> result,
    DateTime now,
  ) => db.transaction(() async {
    await db.customStatement(
      "UPDATE sync_outbox SET state = 'acknowledged', result = ?, error_code = NULL, error_message = NULL WHERE operation_key = ? AND scope_key = ?",
      [jsonEncode(result), c.key, c.scope],
    );
    if (c.kind == 'proof')
      await db.customStatement(
        'UPDATE local_attachments SET server_id = ? WHERE operation_key = ? AND scope_key = ?',
        [result['id'], c.key, c.scope],
      );
    await setMetadata(c.scope, 'last_push', now.toUtc().toIso8601String());
    db.changed();
  });
  Future<void> mark(
    QueuedCommand c,
    String state,
    String code,
    String message, {
    DateTime? retryAt,
  }) async {
    await db.customStatement(
      'UPDATE sync_outbox SET state = ?, error_code = ?, error_message = ?, next_attempt = ?, attempts = MAX(attempts, ?) WHERE operation_key = ? AND scope_key = ?',
      [
        state,
        code,
        message,
        retryAt?.millisecondsSinceEpoch ?? 0,
        c.attempts + (state == 'retry_wait' ? 1 : 0),
        c.key,
        c.scope,
      ],
    );
    db.changed();
  }

  Future<void> reconciled(String scope, String tripId) async {
    await db.customStatement(
      "UPDATE sync_outbox SET reconciled = 1 WHERE scope_key = ? AND trip_id = ? AND state = 'acknowledged'",
      [scope, tripId],
    );
    db.changed();
  }

  Future<void> discard(String scope) => db.transaction(() async {
    for (final table in [
      'sync_outbox',
      'local_attachments',
      'sync_metadata',
      'sync_leases',
    ]) {
      await db.customStatement('DELETE FROM $table WHERE scope_key = ?', [
        scope,
      ]);
    }
    db.changed();
  });
  Future<void> discardUnsent(
    String scope,
    String key, {
    bool reviewedRejection = false,
    bool Function()? current,
  }) => db.transaction(() async {
    if (current != null && !current()) throw StateError('Session changed.');
    final all = await commands(scope);
    final command = all.where((c) => c.key == key).firstOrNull;
    if (command == null) return;
    if (command.accepted ||
        (command.sendPayload != null &&
            !(reviewedRejection && command.needsAttention)))
      throw StateError(
        'This action may have reached the server. Reconcile it before discarding.',
      );
    if (all.any((c) => c.dependencies.contains(key)))
      throw StateError(
        'Discard dependent actions before discarding this proof.',
      );
    await db.customStatement(
      "DELETE FROM sync_outbox WHERE scope_key = ? AND operation_key = ? AND (send_payload IS NULL OR (? = 1 AND state IN ('conflict', 'rejected')))",
      [scope, key, reviewedRejection ? 1 : 0],
    );
    await db.customStatement(
      'DELETE FROM local_attachments WHERE scope_key = ? AND operation_key = ?',
      [scope, key],
    );
    db.changed();
    if (current != null && !current()) throw StateError('Session changed.');
  });
}
