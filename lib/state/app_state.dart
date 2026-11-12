import '../services/assignment_socket.dart';

import 'dart:async';
import 'dart:math';
import 'dart:ui' show PlatformDispatcher, Brightness;

import 'package:flutter/widgets.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../core/palette.dart';
import '../data/models.dart';
import '../repositories/driver_repository.dart';
import '../services/location_tracking_service.dart';
import '../services/offline_policy.dart';
import '../services/sync_scheduler.dart';

enum AppThemeMode { system, light, dark }

class AppState extends ChangeNotifier with WidgetsBindingObserver {
  final SharedPreferences _prefs;
  final ApiClient client;
  final bool realtime;
  final bool _ownsRepository;
  late final AssignmentSocket assignments;
  bool restorePending = false, _refreshQueued = false, _restoring = false;
  String? historyFrom, historyTo, historyStatus;
  late final DriverRepository repository;
  late final LocationTrackingService tracking;
  bool initialized = false, loggedIn = false, loading = false, busy = false;
  int tab = 0, tripPage = 0, historyPage = 0, tripTotal = 0, historyTotal = 0;
  bool pastTrips = false;
  String? rememberedUser, error;
  String? assignmentNotice;
  String? assignmentTripId;
  DateTime? lastSynced;
  Driver driver = Driver('', '', '', '', '');
  List<Trip> trips = [];
  List<Trip> currentTrips = [];
  final Map<String, Trip> _details = {};
  List<HistoryEntry> history = [];
  AppThemeMode themeMode = AppThemeMode.system;
  bool notifications = true, keepScreenOn = true;
  Timer? _poll;
  Duration _automaticRefreshInterval =
      DriverRepository.defaultAutomaticRefreshInterval;
  Duration get automaticRefreshInterval => _automaticRefreshInterval;
  bool _disposed = false,
      _offlineView = false,
      _startupValidating = false,
      _manualSyncing = false;
  bool get isOffline => _offlineView || repository.offline;
  bool get isStartupValidating => _startupValidating;
  bool get isSyncing => loggedIn && (repository.sync.syncing || _manualSyncing);
  bool get canPerformActions =>
      loggedIn && !isOffline && !loading && !busy && !_startupValidating;
  bool get canSaveActions =>
      loggedIn &&
      !busy &&
      !_startupValidating &&
      ((repository.syncSupported &&
              repository.offlineWritesEnabled &&
              (!isOffline || client.remember)) ||
          (!isOffline && !loading));
  int get pendingSyncCount => loggedIn ? repository.sync.pendingCount : 0;
  String? get offlineActionRestriction {
    if (!repository.syncSupported)
      return 'Offline delivery recording is not available from this server. Connect and ask your administrator to finish synchronization setup. Saved details and downloaded photos remain available.';
    if (!repository.offlineWritesEnabled)
      return 'Offline delivery recording is not enabled on the server. Saved details and downloaded photos remain available.';
    if (!client.remember)
      return 'Offline recording requires Remember me. Connect and sign in with Remember me enabled. Saved details and downloaded photos remain available.';
    return null;
  }

  void requireSavedAction() {
    if (!loggedIn) throw StateError('Sign in to continue.');
    if (!repository.syncSupported || !repository.offlineWritesEnabled)
      requireOnlineAction();
  }

  StreamSubscription<void>? _localChanges;
  Timer? _savedDebounce;
  int _scheduledPending = 0;
  void _syncChanged() {
    if (loggedIn && !repository.sync.syncing && !repository.offline) {
      _offlineView = false;
      if (realtime) {
        tracking.start();
        assignments.start();
      }
    }
    final pending = pendingSyncCount;
    if (pending > _scheduledPending)
      unawaited(SyncScheduler.schedule(client).catchError((Object _) {}));
    _scheduledPending = pending;
    _notify();
  }

  void _tripUnavailable(String id) {
    if (_disposed || !loggedIn) return;
    trips.removeWhere((trip) => trip.id == id);
    currentTrips.removeWhere((trip) => trip.id == id);
    _details.remove(id);
    _notify();
  }

  Future<void> _prepareSync() async {
    try {
      await repository.restoreSync();
      await repository.checkSyncCapability();
      if (repository.syncSupported)
        await SyncScheduler.schedule(client, periodic: true);
    } catch (_) {
      /* Unsupported servers retain read-only offline fallback. */
    }
  }

  Future<void> _showSaved({bool startup = false}) async {
    final generation = _generation;
    try {
      await repository.saved(() async {
        final profile = await repository.profile();
        final savedTrips = await repository.trips(
          page: tripPage,
          past: pastTrips,
        );
        final current = !pastTrips && tripPage == 0
            ? savedTrips
            : await repository.trips();
        final details = <String, Trip>{};
        for (final id in _details.keys.toList()) {
          try {
            details[id] = await repository.trip(id);
          } on OfflineCacheMiss {
            /* Not downloaded. */
          }
        }
        if (_disposed || generation != _generation) return;
        driver = profile;
        trips = savedTrips.items;
        tripTotal = savedTrips.total;
        currentTrips = current.items;
        _details.addAll(details);
        final scope = client.cacheScope;
        if (scope != null) {
          final pull = await repository.outbox.metadata(scope, 'last_pull');
          if (_disposed ||
              generation != _generation ||
              scope != client.cacheScope)
            return;
          lastSynced = DateTime.tryParse(pull ?? '') ?? lastSynced;
        }
        try {
          final savedHistory = await repository.history(
            page: historyPage,
            from: historyFrom,
            to: historyTo,
            status: historyStatus,
          );
          if (_disposed || generation != _generation) return;
          history = savedHistory.items;
          historyTotal = savedHistory.total;
        } on OfflineCacheMiss {
          /* A missing filtered page is loaded separately. */
        }
        if (startup && !_disposed && generation == _generation) {
          loggedIn = true;
          initialized = true;
        }
        _notify();
      });
    } catch (_) {
      /* A cache miss leaves the existing view intact. */
    }
  }

  void requireOnlineAction() {
    if (!loggedIn) throw StateError('Sign in to continue.');
    if (isOffline) throw OfflineActionBlocked();
  }

  void _networkChanged() {
    if (client.networkUnavailable.value) {
      _offlineView = true;
      repository.enterOffline();
      tracking.stop();
      assignments.stop();
    }
    _notify();
  }

  int _generation = 0;
  final Map<String, String> _operationKeys = {};

  AppState(
    this._prefs, {
    ApiClient? api,
    DriverRepository? driverRepository,
    this.realtime = true,
  }) : client = api ?? ApiClient(),
       _ownsRepository = driverRepository == null {
    repository = driverRepository ?? DriverRepository(client);
    repository.onTripUnavailable = _tripUnavailable;
    repository.sync.addListener(_syncChanged);
    _localChanges = repository.changes.listen((_) {
      if (!loggedIn || !repository.syncSupported) return;
      _savedDebounce?.cancel();
      _savedDebounce = Timer(
        const Duration(milliseconds: 50),
        () => unawaited(_showSaved()),
      );
    });
    assignments = AssignmentSocket(
      cookieProvider: client.socketCookie,
      changed: _assignmentChanged,
      onAssignment: (event) {
        if (loggedIn && notifications) {
          assignmentNotice = event.notice;
          assignmentTripId = '${event.deliveryId}';
          _notify();
        }
      },
    );
    tracking = LocationTrackingService(
      cookieProvider: client.socketCookie,
      isSignedIn: () => loggedIn && !_disposed,
    );
    client.onSessionLost = _sessionLost;
    client.networkUnavailable.addListener(_networkChanged);
    final saved = _prefs.getString('theme_mode');
    themeMode = AppThemeMode.values.firstWhere(
      (m) => m.name == saved,
      orElse: () => AppThemeMode.system,
    );
    notifications = _prefs.getBool('notifications') ?? true;
    keepScreenOn = _prefs.getBool('keep_screen_on') ?? true;
    rememberedUser = _prefs.getString('username');
    _applyBrightness();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> initialize() async {
    if (_restoring) return;
    _restoring = true;
    initialized = false;
    _startupValidating = false;
    _notify();
    repository.beginReadCycle();
    try {
      await client.restore();
      if (client.remember) {
        _startupValidating = true;
        await repository.restoreSync();
        await _showSaved(startup: true);
        await client.validate();
        driver = await repository.profile();
        loggedIn = true;
        await _prepareSync();
        await _loadAutomaticRefreshInterval();
        if (_disposed || !loggedIn) return;
        _startupValidating = false;
        if (realtime && !isOffline) tracking.start();
        await refresh(retryConnection: false);
        _startPolling();
      }
    } catch (e) {
      _startupValidating = false;
      if (isConnectionFailure(e) &&
          client.remember &&
          client.cacheScope != null) {
        repository.enterOffline();
        try {
          driver = await repository.profile();
          loggedIn = true;
          _offlineView = true;
          await _loadAutomaticRefreshInterval();
          if (_disposed || !loggedIn) return;
          lastSynced = repository.cachedAt;
          await refresh(retryConnection: false);
          _startPolling();
        } catch (cachedError) {
          error = apiError(cachedError);
        }
      } else {
        error = apiError(e);
      }
    }
    _startupValidating = false;
    _restoring = false;
    restorePending = !loggedIn && client.remember;
    initialized = true;
    _notify();
  }

  Future<void> login(
    String email,
    String password, {
    required bool remember,
  }) async {
    error = null;
    await client.login(email, password, remember);
    try {
      await client.validate();
      driver = await repository.profile();
      loggedIn = true;
      await _prepareSync();
      _offlineView = repository.offline;
      await _loadAutomaticRefreshInterval();
      if (_disposed || !loggedIn) return;
      if (realtime && !isOffline) tracking.start();
      tab = tripPage = historyPage = 0;
      pastTrips = false;
      if (remember) {
        await _prefs.setString('username', email);
        rememberedUser = email;
      } else {
        await _prefs.remove('username');
        rememberedUser = null;
      }
      await refresh();
      _startPolling();
    } catch (_) {
      _sessionLost();
      await client.clear();
      rethrow;
    }
    _notify();
  }

  Future<void> logout({bool discardPending = false}) async {
    if (!initialized) return;
    if (pendingSyncCount > 0 && !discardPending)
      throw StateError(
        'Sync saved work first, or choose discard and sign out.',
      );
    // Invalidate in-flight requests before deleting queue rows or private files.
    var cleanupFailed = false;
    if (discardPending) {
      client.cancelPendingRequests();
      try {
        await client.onSessionQuarantined?.call(client.cacheScope ?? '');
        await repository.discardPending();
      } catch (_) {
        cleanupFailed = true;
      }
    }
    initialized = false;
    _sessionLost(clearCredential: false);
    try {
      final revoked = await client.logout();
      error = revoked ? null : 'Signed out on this device. Server session revocation could not be confirmed.';
      if (cleanupFailed) error = 'Signed out. Some saved work could not be removed and remains isolated to your account.';
    } finally {
      initialized = true;
      _notify();
    }
  }

  void _sessionLost({bool clearCredential = true}) {
    _generation++;
    loggedIn = false;
    unawaited(SyncScheduler.cancel().catchError((Object _) {}));
    _poll?.cancel();
    assignments.stop();
    loading = busy = _manualSyncing = false;
    restorePending = false;
    assignmentNotice = null;
    assignmentTripId = null;
    tracking.stop();
    trips = [];
    currentTrips = [];
    history = [];
    _operationKeys.clear();
    _details.clear();
    driver = Driver('', '', '', '', '');
    lastSynced = null;
    _offlineView = false;
    error = 'Sign in to continue.';
    if (clearCredential) unawaited(client.clear());
    _notify();
  }

  Future<void> refresh({bool retryConnection = true}) async {
    await repository.network(() => _refresh(retryConnection: retryConnection));
  }

  /// Synchronize any queued offline work and refresh assignments, blocking UI
  /// interaction via [isSyncing] until complete.
  Future<void> synchronize() async {
    if (!loggedIn || loading || busy || _manualSyncing) return;
    _manualSyncing = true;
    _notify();
    try {
      if (repository.syncSupported) {
        await repository.sync.request(force: true);
      }
      await refresh();
    } finally {
      if (!_disposed) {
        _manualSyncing = false;
        _notify();
      }
    }
  }

  Future<void> _refresh({bool retryConnection = true}) async {
    if (!loggedIn) return;
    if (loading || busy) {
      _refreshQueued = true;
      return;
    }
    loading = true;
    final generation = _generation;
    _notify();
    repository.beginReadCycle();
    try {
      if (repository.syncSupported) await _showSaved();
      if (isOffline && retryConnection) {
        try {
          await client.validate();
        } catch (e) {
          if (!isConnectionFailure(e)) rethrow;
          repository.enterOffline();
        }
      }
      final profile = await repository.profile();
      if (!client.networkUnavailable.value) {
        try {
          await repository.checkSyncCapability();
        } catch (_) {
          /* Keep the last known server policy until it can be checked. */
        }
      }
      final assignments = await repository.trips(
        page: tripPage,
        past: pastTrips,
      );
      final current = !pastTrips && tripPage == 0
          ? assignments
          : await repository.trips();
      final outcomes = await repository.history(
        page: historyPage,
        from: historyFrom,
        to: historyTo,
        status: historyStatus,
      );
      final details = <String, Trip>{};
      for (final id in _details.keys.toList()) {
        try {
          details[id] = await repository.trip(id);
        } on DioException catch (e) {
          if (e.response?.statusCode != 404) rethrow;
        }
      }
      if (_disposed || generation != _generation || !loggedIn) return;
      _details
        ..clear()
        ..addAll(details);
      driver = profile;
      currentTrips = current.items;
      trips = assignments.items;
      tripTotal = assignments.total;
      history = outcomes.items;
      historyTotal = outcomes.total;
      // The server resolves any current active assignment from the authenticated
      // driver, so logged-in location sharing also works without a trip.
      repository.completeRefresh();
      _offlineView = repository.offline || repository.usedCache;
      if (realtime && !isOffline) {
        tracking.start();
        this.assignments.start();
      }
      error = null;
      lastSynced = repository.usedCache ? repository.cachedAt : DateTime.now();
      if (repository.syncSupported && !isOffline && client.cacheScope != null) {
        await repository.outbox.setMetadata(
          client.cacheScope!,
          'last_pull',
          lastSynced!.toUtc().toIso8601String(),
        );
      }
      if (repository.syncSupported && !isOffline)
        unawaited(repository.sync.request());
    } catch (e) {
      if (generation == _generation) {
        error = apiError(e);
        if (repository.offline) _offlineView = true;
      }
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        _notify();
        if (_refreshQueued) {
          _refreshQueued = false;
          unawaited(refresh());
        }
      }
    }
  }

  Future<void> loadTrip(String id) async {
    final generation = _generation;
    try {
      final trip = await repository.trip(id);
      if (_disposed || generation != _generation || !loggedIn) return;
      if (repository.offline) {
        _offlineView = true;
        if (repository.cachedAt != null) lastSynced = repository.cachedAt;
      }
      _details[id] = trip;
      final index = trips.indexWhere((t) => t.id == id);
      if (index >= 0)
        trips[index] = trip;
      else
        trips.add(trip);
      error = null;
      if (realtime &&
          !isOffline &&
          (trip.status == TripStatus.completed ||
              trip.status == TripStatus.cancelled))
        tracking.start();
      _notify();
    } catch (e) {
      if (generation == _generation) {
        _details.remove(id);
        trips.removeWhere((t) => t.id == id);
        tracking.stop();
        error = apiError(e);
        _notify();
      }
      rethrow;
    }
  }

  Future<void> _stopPlanQueue = Future.value();

  /// Save a planning choice on the server without recording a delivery outcome.
  Future<void> planGroupedOrder(
    String tripId,
    String stopId, {
    bool skip = false,
  }) {
    requireOnlineAction();
    final generation = _generation;
    final operation = _stopPlanQueue.then((_) async {
      if (_disposed || generation != _generation) return;
      requireOnlineAction();
      if (busy || loading) throw StateError('Wait for the current operation.');
      final trip = tripById(tripId);
      final stop = trip.stops.where((stop) => stop.id == stopId).firstOrNull;
      if (trip.status != TripStatus.inProgress ||
          stop == null ||
          !stop.isGroupedOrder ||
          stop.isDone ||
          !(stop.canDeliver || stop.canFail)) {
        throw StateError(
          'This order is no longer available. Refresh the trip.',
        );
      }
      busy = true;
      _notify();
      try {
        await repository.planStop(stopId, skip: skip);
      } catch (e) {
        if (generation == _generation) error = apiError(e);
        rethrow;
      } finally {
        if (!_disposed && generation == _generation) {
          busy = false;
          await refresh(retryConnection: false);
          _notify();
        }
      }
    });
    // Keep later commands usable after a failed request.
    _stopPlanQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  Future<void> startTrip(Trip trip) async {
    requireOnlineAction();
    if (!loggedIn || busy || loading)
      throw StateError('Wait for the current operation.');
    if (!trip.canStartAt(DateTime.now()))
      throw StateError('This trip is not due to start today.');
    busy = true;
    _notify();
    final generation = _generation;
    try {
      await repository.startTrip(trip);
    } catch (e) {
      if (generation == _generation) error = apiError(e);
      rethrow;
    } finally {
      if (!_disposed && generation == _generation) {
        busy = false;
        await refresh(retryConnection: false);
        _notify();
      }
    }
  }

  Future<void> collectReturn(ReturnPickup pickup) async {
    requireSavedAction();
    if (busy) throw StateError('An operation is already pending.');
    busy = true;
    _notify();
    final generation = _generation;
    final identity = 'pickup:${pickup.id}';
    final key = _operationKeys.putIfAbsent(identity, newOperationKey);
    try {
      await repository.collectReturn(pickup, key);
      if (generation == _generation) _operationKeys.remove(identity);
    } catch (e) {
      if (generation == _generation) error = apiError(e);
      rethrow;
    } finally {
      if (!_disposed && generation == _generation) {
        busy = false;
        if (repository.syncSupported)
          await _showSaved();
        else
          await refresh(retryConnection: false);
        _notify();
      }
    }
  }

  Future<void> recordOutcome(Trip trip, Stop stop, {String? reason}) async {
    requireSavedAction();
    if (busy) throw StateError('An operation is already pending.');
    busy = true;
    _notify();
    final generation = _generation;
    final identity =
        '${stop.id}:${reason == null ? 'delivered' : 'failed'}:${reason ?? ''}';
    // Retain the same key after an ambiguous timeout, so retry can be reconciled safely.
    final key = _operationKeys.putIfAbsent(identity, newOperationKey);
    try {
      if (reason == null &&
          !(repository.syncSupported && repository.offlineWritesEnabled)) {
        final proofs = await repository.proofs(stop.id);
        if (proofs.isEmpty) {
          throw StateError(
            'Submit Proof of Delivery before confirming delivery.',
          );
        }
        if (_disposed || generation != _generation) return;
      }
      await repository.outcome(stop, trip.version, key, reason: reason);
      if (generation != _generation) return;
      _operationKeys.remove(identity);
    } catch (e) {
      error = apiError(e);
      rethrow;
    } finally {
      if (!_disposed && generation == _generation) {
        busy = false;
        if (repository.syncSupported)
          await _showSaved();
        else
          await refresh(retryConnection: false);
        _notify();
      }
    }
  }

  static String newOperationKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  Trip? get activeTrip {
    for (final t in currentTrips) {
      if (t.status == TripStatus.inProgress || t.status == TripStatus.returning)
        return t;
    }
    for (final t in currentTrips) {
      if (t.status == TripStatus.loading) return t;
    }
    return null;
  }

  Trip? findTrip(String id) {
    if (_details.containsKey(id)) return _details[id];
    for (final t in trips) {
      if (t.id == id) return t;
    }
    return null;
  }

  Trip tripById(String id) =>
      findTrip(id) ?? (throw StateError('Assignment is no longer available.'));
  Future<void> setTripPage(int page, {bool? past}) async {
    if (loading || busy) return;
    final oldPage = tripPage, oldPast = pastTrips;
    tripPage = page;
    if (past != null) pastTrips = past;
    await refresh(retryConnection: false);
    if (error != null) {
      tripPage = oldPage;
      pastTrips = oldPast;
      _notify();
    }
  }

  Future<void> setHistoryPage(int page) async {
    if (loading || busy) return;
    final old = historyPage;
    historyPage = page;
    await refresh(retryConnection: false);
    if (error != null) {
      historyPage = old;
      _notify();
    }
  }

  void setTab(int value) {
    tab = value;
    _notify();
  }

  Future<void> _loadAutomaticRefreshInterval() async {
    final generation = _generation;
    var interval = DriverRepository.defaultAutomaticRefreshInterval;
    try {
      interval = await repository.automaticRefreshInterval();
    } catch (_) {
      // Optional settings must not prevent startup when unavailable.
    }
    if (!_disposed && generation == _generation && loggedIn) {
      _automaticRefreshInterval = interval;
    }
  }

  void _startPolling() {
    _poll?.cancel();
    if (!realtime) return;
    if (realtime && !isOffline) {
      assignments.start();
    }
    _poll = Timer.periodic(
      _automaticRefreshInterval,
      (_) => unawaited(refresh()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && loggedIn) {
      unawaited(refresh());
      _startPolling();
    } else {
      _poll?.cancel();
      assignments.stop();
    }
  }

  void _assignmentChanged() {
    if (loggedIn) {
      tripPage = 0;
      pastTrips = false;
      unawaited(refresh());
    }
  }

  void dismissAssignmentNotice() {
    assignmentNotice = null;
    assignmentTripId = null;
    _notify();
  }

  Future<void> setHistoryFilter({
    String? from,
    String? to,
    String? status,
  }) async {
    if (loading || busy) return;
    historyFrom = from;
    historyTo = to;
    historyStatus = status;
    historyPage = 0;
    history = [];
    historyTotal = 0;
    await refresh(retryConnection: false);
  }

  bool get isDark => P.dark;

  void _applyBrightness() {
    P.dark =
        themeMode == AppThemeMode.dark ||
        (themeMode == AppThemeMode.system &&
            PlatformDispatcher.instance.platformBrightness == Brightness.dark);
  }

  void setThemeMode(AppThemeMode mode) {
    themeMode = mode;
    _prefs.setString('theme_mode', mode.name);
    _applyBrightness();
    _notify();
  }

  void refreshBrightness() {
    _applyBrightness();
    _notify();
  }

  void toggleNotifications(bool v) {
    notifications = v;
    _prefs.setBool('notifications', v);
    _notify();
  }

  void toggleScreenOn(bool v) {
    keepScreenOn = v;
    _prefs.setBool('keep_screen_on', v);
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _poll?.cancel();
    _savedDebounce?.cancel();
    unawaited(_localChanges?.cancel());
    repository.sync.removeListener(_syncChanged);
    if (repository.onTripUnavailable == _tripUnavailable)
      repository.onTripUnavailable = null;
    if (_ownsRepository) repository.sync.dispose();
    assignments.stop();
    client.onSessionLost = null;
    client.networkUnavailable.removeListener(_networkChanged);
    WidgetsBinding.instance.removeObserver(this);
    tracking.dispose();
    super.dispose();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);
  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
