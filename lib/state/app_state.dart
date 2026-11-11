import '../services/assignment_socket.dart';

import 'dart:async';
import 'dart:convert';
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

enum AppThemeMode { system, light, dark }

class AppState extends ChangeNotifier with WidgetsBindingObserver {
  final SharedPreferences _prefs;
  final ApiClient client;
  final bool realtime;
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
  bool _disposed = false, _offlineView = false;
  bool get isOffline => _offlineView || repository.offline;
  bool get canPerformActions => loggedIn && !isOffline && !loading && !busy;
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
  }) : client = api ?? ApiClient() {
    repository = driverRepository ?? DriverRepository(client);
    assignments = AssignmentSocket(
      cookieProvider: client.socketCookie,
      changed: _assignmentChanged,
      onAssignment: (event) {
        if (loggedIn && notifications) {
          assignmentNotice = event.notice;
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
    rememberedUser = _prefs.getString('username');
    _applyBrightness();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> initialize() async {
    if (_restoring) return;
    _restoring = true;
    initialized = false;
    _notify();
    repository.beginReadCycle();
    try {
      await client.restore();
      if (client.remember) {
        await client.validate();
        driver = await repository.profile();
        loggedIn = true;
        await _loadAutomaticRefreshInterval();
        if (_disposed || !loggedIn) return;
        if (realtime && !isOffline) tracking.start();
        await refresh(retryConnection: false);
        _startPolling();
      }
    } catch (e) {
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

  Future<void> logout() async {
    if (!initialized) return;
    initialized = false;
    _sessionLost(clearCredential: false);
    try {
      final revoked = await client.logout();
      error = revoked ? null : 'Signed out on this device. Server session revocation could not be confirmed.';
    } finally {
      initialized = true;
      _notify();
    }
  }

  void _sessionLost({bool clearCredential = true}) {
    _generation++;
    loggedIn = false;
    loading = busy = false;
    _poll?.cancel();
    assignments.stop();
    restorePending = false;
    assignmentNotice = null;
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
      if (isOffline && retryConnection) {
        try {
          await client.validate();
        } catch (e) {
          if (!isConnectionFailure(e)) rethrow;
          repository.enterOffline();
        }
      }
      final profile = await repository.profile();
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
      _applyAllStopPlans();
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
      _applyStopPlan(trip);
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

  String _stopPlanKey(String tripId) => 'driver_stop_plan:${driver.id}:$tripId';

  void _applyStopPlan(Trip trip) {
    trip.preferredStopId = null;
    trip.deferredStopIds.clear();
    final saved = _prefs.getString(_stopPlanKey(trip.id));
    if (saved == null || trip.status != TripStatus.inProgress) return;
    try {
      final plan = jsonDecode(saved) as Map<String, dynamic>;
      final pending = trip.stops
          .where((stop) => stop.isGroupedOrder && !stop.isDone)
          .map((stop) => stop.id)
          .toSet();
      trip.deferredStopIds.addAll(
        (plan['skipped'] as List).whereType<String>().where(pending.contains),
      );
      final next = plan['next'] as String?;
      if (pending.contains(next) && !trip.deferredStopIds.contains(next)) {
        trip.preferredStopId = next;
      }
    } catch (_) {
      // Ignore damaged local preferences; the assignment remains usable.
      trip.preferredStopId = null;
      trip.deferredStopIds.clear();
    }
  }

  void _applyAllStopPlans() {
    for (final trip in {...trips, ...currentTrips, ..._details.values}) {
      _applyStopPlan(trip);
    }
  }

  /// Defers or prioritizes one order without sending a delivery outcome.
  Future<void> planGroupedOrder(
    String tripId,
    String stopId, {
    bool skip = false,
  }) async {
    if (!loggedIn || busy || loading) {
      throw StateError('Wait for the current operation.');
    }
    final trip = tripById(tripId);
    final stop = trip.stops.where((stop) => stop.id == stopId).firstOrNull;
    if (trip.status != TripStatus.inProgress ||
        stop == null ||
        !stop.isGroupedOrder ||
        stop.isDone ||
        !(stop.canDeliver || stop.canFail)) {
      throw StateError('This order is no longer available. Refresh the trip.');
    }
    _applyStopPlan(trip);
    final skipped = {...trip.deferredStopIds};
    var next = trip.preferredStopId;
    if (skip) {
      skipped.add(stopId);
      if (next == stopId) next = null;
    } else {
      skipped.remove(stopId);
      next = stopId;
    }
    final generation = _generation;
    final saved = await _prefs.setString(
      _stopPlanKey(tripId),
      jsonEncode({'next': next, 'skipped': skipped.toList()}),
    );
    if (!saved) {
      throw StateError('Could not save your order preference. Try again.');
    }
    if (_disposed || generation != _generation) return;
    _applyAllStopPlans();
    _notify();
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
    requireOnlineAction();
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
        await refresh(retryConnection: false);
        _notify();
      }
    }
  }

  Future<void> recordOutcome(Trip trip, Stop stop, {String? reason}) async {
    requireOnlineAction();
    if (busy) throw StateError('An operation is already pending.');
    busy = true;
    _notify();
    final generation = _generation;
    final identity =
        '${stop.id}:${reason == null ? 'delivered' : 'failed'}:${reason ?? ''}';
    // Retain the same key after an ambiguous timeout, so retry can be reconciled safely.
    final key = _operationKeys.putIfAbsent(identity, newOperationKey);
    try {
      if (reason == null) {
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
    _notify();
  }

  void toggleScreenOn(bool v) {
    keepScreenOn = v;
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
