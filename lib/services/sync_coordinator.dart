import 'dart:async';
import 'dart:math';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../data/local/outbox_store.dart';
import 'offline_policy.dart';

typedef Json = Map<String, dynamic>;

/// One drain shared by all foreground triggers and the native worker. Durable
/// leases coordinate separate isolates; idempotent server receipts cover crashes.
class SyncCoordinator extends ChangeNotifier {
  final ApiClient client;
  final OutboxStore store;
  final Future<bool> Function() capability;
  final Future<Json> Function(String) fetchTrip;
  final Future<Json> Function(QueuedCommand, Json) send;
  final Future<void> Function(String) reconcile;
  final DateTime Function() now;
  final Random _random = Random.secure();
  late final String _owner =
      '${now().microsecondsSinceEpoch}-${_random.nextInt(1 << 30)}';
  Future<void>? _running;
  bool _again = false, _forceAgain = false;
  bool syncing = false, _disposed = false, _notifierDisposed = false;
  String? error;
  List<QueuedCommand> commands = [];
  DateTime? lastPush;
  int uploadedBytes = 0, uploadBytesTotal = 0;
  void uploadProgress(int sent, int total) {
    uploadedBytes = sent;
    uploadBytesTotal = total;
    _notify();
  }

  int get pendingCount => commands.where((c) => c.pending).length;
  int get attentionCount => commands.where((c) => c.needsAttention).length;
  int get reconciliationCount =>
      commands.where((c) => c.accepted && !c.reconciled).length;
  bool get hasOldWork => commands.any(
    (c) =>
        c.pending &&
        now().difference(
              DateTime.fromMillisecondsSinceEpoch(c.createdAt, isUtc: true),
            ) >=
            const Duration(days: 29),
  );
  SyncCoordinator({
    required this.client,
    required this.store,
    required this.capability,
    required this.fetchTrip,
    required this.send,
    required this.reconcile,
    DateTime Function()? clock,
  }) : now = clock ?? DateTime.now;

  Future<void> load() async {
    final scope = client.cacheScope;
    if (scope == null) {
      commands = [];
      lastPush = null;
    } else {
      final values = await store.commands(scope);
      final pushed = await store.metadata(scope, 'last_push');
      if (client.cacheScope != scope) return;
      commands = values;
      lastPush = DateTime.tryParse(pushed ?? '');
    }
    _notify();
  }

  Future<void> request({bool force = false}) {
    if (_disposed) return Future.value();
    if (_running != null) {
      _again = true;
      _forceAgain = _forceAgain || force;
      return _running!;
    }
    return _running = _run(force: force)
        .catchError((Object failure) {
          error = apiError(failure);
          syncing = false;
          _notify();
        })
        .whenComplete(() {
          _running = null;
          if (_again && !_disposed) {
            final rerunForce = _forceAgain;
            _again = false;
            _forceAgain = false;
            unawaited(request(force: rerunForce));
          }
        });
  }

  Future<void> _run({bool force = false}) async {
    final scope = client.cacheScope, generation = client.sessionGeneration;
    if (scope == null) return;
    bool current() =>
        !_disposed &&
        client.cacheScope == scope &&
        client.sessionGeneration == generation;
    if (!await store.acquire(scope, _owner, now())) return;
    if (!current()) {
      await store.release(scope, _owner);
      return;
    }
    final precheck = await store.commands(scope);
    if (!current()) {
      await store.release(scope, _owner);
      return;
    }
    final precheckNow = now().millisecondsSinceEpoch;
    final hasWork = precheck.any(
      (command) =>
          (command.accepted && !command.reconciled) ||
          (!command.accepted &&
              !command.needsAttention &&
              (force || command.nextAttempt <= precheckNow)),
    );
    if (!hasWork) {
      await store.release(scope, _owner);
      await load();
      return;
    }
    syncing = true;
    error = null;
    _notify();
    try {
      await client.validate();
      if (!current() || !await capability()) return;
      final initial = await store.commands(scope);
      for (final command in initial) {
        if (!current()) break;
        if (!await store.acquire(scope, _owner, now())) break;
        if (command.accepted) {
          if (!command.reconciled) {
            try {
              await reconcile(command.tripId);
              if (current()) await store.reconciled(scope, command.tripId);
            } catch (_) {
              /* Receipt stays acknowledged even if the read fails. */
            }
          }
          continue;
        }
        if (command.needsAttention ||
            (!force && command.nextAttempt > now().millisecondsSinceEpoch))
          continue;
        if (command.commandVersion != 1 || !command.payloadValid) {
          await store.mark(
            command,
            'rejected',
            'COMMAND_UNSUPPORTED',
            'Saved action is damaged or requires a newer app. Review before continuing.',
          );
          continue;
        }
        final all = await store.commands(scope);
        final prior = all.where(
          (c) => c.tripId == command.tripId && c.sequence < command.sequence,
        );
        if (prior.any((c) => c.pending) ||
            command.dependencies.any(
              (key) => !all.any((c) => c.key == key && c.accepted),
            )) {
          await store.mark(
            command,
            'blocked_dependency',
            'DEPENDENCY_PENDING',
            'Waiting for an earlier action or proof.',
          );
          continue;
        }
        try {
          // A previous process may have died after the server committed. Resolve
          // acceptance BEFORE asking for current assignment access or version.
          final receipt = (await client.dio.get<Json>(
            '/driver/sync/operations/${command.key}',
          )).data!;
          if (!current()) break;
          if (receipt['accepted'] == true) {
            await store.acknowledge(
              command,
              Json.from(receipt['result'] as Map),
              now(),
            );
          } else {
            final trip = await fetchTrip(command.tripId);
            if (!current()) break;
            var body = command.sendPayload;
            if (body == null) {
              var expected = command.baseVersion;
              // Only receipts from earlier local commands may bridge versions.
              for (final p in prior.where(
                (c) => c.accepted && c.kind != 'proof',
              )) {
                final before = p.result?['previousTripVersion'];
                final after = p.result?['tripVersion'];
                if (before == expected && after is int) expected = after;
              }
              if (trip['version'] != expected) {
                await store.mark(
                  command,
                  'conflict',
                  'VERSION_CONFLICT',
                  'Assignment changed. Review before resubmitting.',
                );
                continue;
              }
              if (!['in_transit', 'returning'].contains(trip['status'])) {
                await store.mark(
                  command,
                  'conflict',
                  'ASSIGNMENT_CHANGED',
                  'This assignment is no longer active.',
                );
                continue;
              }
              body = {...command.payload, 'operationKey': command.key};
              if (command.kind == 'collected')
                body['tripVersion'] = expected;
              else if (command.kind != 'proof')
                body['version'] = expected;
            }
            if (!await store.freeze(command, body)) continue;
            if (!current()) break;
            final result = await send(command, body);
            if (!current()) break;
            await store.acknowledge(command, result, now());
          }
          try {
            await reconcile(command.tripId);
            if (current()) await store.reconciled(scope, command.tripId);
          } catch (_) {
            /* The next run reconciles without replaying acceptance. */
          }
        } catch (failure) {
          if (!current()) break;
          await _failed(command, failure);
          if (client.networkUnavailable.value) break;
        }
      }
    } catch (failure) {
      if (current()) {
        error = apiError(failure);
        if (!isConnectionFailure(failure)) {
          for (final c in await store.commands(scope)) {
            if (c.pending && !c.needsAttention) await _failed(c, failure);
          }
        }
      }
    } finally {
      await store.release(scope, _owner);
      syncing = false;
      uploadedBytes = uploadBytesTotal = 0;
      await load();
    }
  }

  Future<void> _failed(QueuedCommand c, Object failure) async {
    final status = failure is DioException
        ? failure.response?.statusCode
        : null;
    final data = failure is DioException ? failure.response?.data : null;
    final code = data is Map
        ? '${data['code'] ?? 'HTTP_$status'}'
        : 'SYNC_FAILED';
    final message = apiError(failure);
    if (status == 401) {
      await store.mark(
        c,
        'blocked_auth',
        'AUTH_REQUIRED',
        'Sign in to synchronize saved work.',
      );
    } else if ([403, 404, 409].contains(status)) {
      await store.mark(c, 'conflict', code, message);
    } else if (isConnectionFailure(failure) ||
        status == 429 ||
        [500, 502, 503, 504].contains(status)) {
      var delay = Duration(
        milliseconds:
            min(300000, 2000 * pow(2, min(c.attempts, 8)).toInt()) +
            _random.nextInt(1000),
      );
      final header = failure is DioException
          ? failure.response?.headers.value('retry-after')
          : null;
      final seconds = int.tryParse(header ?? '');
      DateTime? date;
      if (header != null) {
        try {
          date = HttpDate.parse(header);
        } catch (_) {
          /* Seconds handled above. */
        }
      }
      if (seconds != null && seconds > 0) delay = Duration(seconds: seconds);
      if (date != null && date.isAfter(now())) delay = date.difference(now());
      await store.mark(
        c,
        'retry_wait',
        code,
        message,
        retryAt: now().add(delay),
      );
    } else {
      await store.mark(c, 'rejected', code, message);
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> shutdown() async {
    _disposed = true;
    _again = false;
    await _running;
    dispose();
  }

  @override
  void dispose() {
    _disposed = true;
    _again = false;
    if (!_notifierDisposed) {
      _notifierDisposed = true;
      super.dispose();
    }
  }
}
