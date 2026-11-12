import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:workmanager/workmanager.dart';

import '../api/api_client.dart';
import '../data/local/driver_cache_database.dart';
import '../repositories/driver_repository.dart';

const syncTask = 'com.example.hyops_flutter.sync';
const periodicSyncTask = 'com.example.hyops_flutter.periodic_sync';

@pragma('vm:entry-point')
void syncCallbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    await dotenv.load(isOptional: true);
    if (![syncTask, periodicSyncTask].contains(task)) return true;
    final origin = input?['origin'] as String?;
    final scope = input?['scope'] as String?;
    if (origin == null || scope == null) return true;
    final api = ApiClient(baseUrl: origin);
    final repo = DriverRepository(api);
    try {
      await api.restore();
      if (!api.remember || api.cacheScope != scope) return true;
      await repo.restoreSync();
      await repo.sync.request();
      return !repo.sync.commands.any((c) => c.pending && !c.needsAttention);
    } catch (_) {
      // Locked secure storage, expiration and network failure leave durable work.
      return false;
    } finally {
      await repo.sync.shutdown();
      api.dio.close(force: true);
      await DriverCacheDatabase.closeShared();
    }
  });
}

class SyncScheduler {
  static bool _ready = false;
  static bool get supported => Platform.isAndroid || Platform.isIOS;
  static Future<void> initialize() async {
    if (!supported || _ready) return;
    await Workmanager().initialize(syncCallbackDispatcher);
    _ready = true;
  }

  static Future<void> schedule(ApiClient api, {bool periodic = false}) async {
    if (!_ready || !api.remember || api.cacheScope == null) return;
    final input = <String, dynamic>{
      'origin': api.baseUrl ?? api.dio.options.baseUrl,
      'scope': api.cacheScope,
    };
    final constraints = Constraints(networkType: NetworkType.connected);
    if (periodic) {
      await Workmanager().registerPeriodicTask(
        periodicSyncTask,
        periodicSyncTask,
        frequency: const Duration(minutes: 15),
        constraints: constraints,
        inputData: input,
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
    } else if (Platform.isIOS) {
      await Workmanager().registerProcessingTask(
        syncTask,
        syncTask,
        constraints: constraints,
        inputData: input,
      );
    } else {
      await Workmanager().registerOneOffTask(
        syncTask,
        syncTask,
        constraints: constraints,
        inputData: input,
        existingWorkPolicy: ExistingWorkPolicy.keep,
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(seconds: 30),
      );
    }
  }

  static Future<void> cancel() async {
    if (!_ready) return;
    await Workmanager().cancelByUniqueName(syncTask);
    await Workmanager().cancelByUniqueName(periodicSyncTask);
  }
}
