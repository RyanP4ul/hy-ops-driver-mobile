import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/config.dart';

enum TrackingStatus { idle, starting, live, locationOff, noPermission, error }

enum SocketStatus { disconnected, connecting, connected }

/// Streams the phone's GPS position to the dispatch server over a WebSocket.
///
/// * On Android the position stream runs inside a **foreground service**
///   (geolocator's ForegroundNotificationConfig), so tracking keeps going with
///   the screen off or the app in the background. A persistent notification is shown.
/// * iOS background location requires the configured platform permissions.
/// * The socket reconnects automatically (1s, 2s, 4s ... max 30s) and positions
///   captured while offline are buffered (last 100) and sent on reconnect.
///
/// Message sent for every position:
/// { "type": "DRIVER_LOCATION_UPDATE", "payload":
///   [deliveryIdOrNull, latitude, longitude, accuracyMeters, speedMps, heading, utcTimestamp] }
class LocationTrackingService extends ChangeNotifier {
  LocationTrackingService({required this.cookieProvider, required this.isSignedIn,
    Future<bool> Function()? locationEnabled,
    Future<LocationPermission> Function()? checkPermission,
    Future<LocationPermission> Function()? requestPermission,
    Stream<Position> Function(LocationSettings)? positions,
    WebSocketChannel Function(String)? connectSocket,
  }) : locationEnabled = locationEnabled ?? Geolocator.isLocationServiceEnabled,
       checkPermission = checkPermission ?? Geolocator.checkPermission,
       requestPermission = requestPermission ?? Geolocator.requestPermission,
       positions = positions ?? ((settings) => Geolocator.getPositionStream(locationSettings: settings)),
       connectSocket = connectSocket ?? ((cookie) => IOWebSocketChannel.connect(Uri.parse(Config.wsUrl), headers: {'Cookie': cookie}, pingInterval: const Duration(seconds: 20), connectTimeout: const Duration(seconds: 8)));

  final bool Function() isSignedIn;
  final Future<bool> Function() locationEnabled;
  final Future<LocationPermission> Function() checkPermission, requestPermission;
  final Stream<Position> Function(LocationSettings) positions;
  final WebSocketChannel Function(String) connectSocket;

  final Future<String> Function() cookieProvider;
  int _generation = 0;

  TrackingStatus status = TrackingStatus.idle;
  SocketStatus socket = SocketStatus.disconnected;
  Position? lastPosition;
  DateTime? lastSentAt;
  int sentCount = 0;
  int get pendingCount => _pending.length;

  String? _tripId;
  bool _wanted = false;
  StreamSubscription<Position>? _posSub;
  WebSocketChannel? _channel;
  Timer? _retryTimer;
  Timer? _reconnectTimer;
  int _backoff = 0;
  final List<String> _pending = [];

  // ------------------------------------------------------------ public API

  /// Starts tracking (idempotent). Calling it again just updates trip / stop ids.
  void start({String? tripId, String? stopId}) {
    if (!isSignedIn()) return;
    if (_tripId != tripId) { stop(); _generation++; }
    _tripId = tripId;
    if (_wanted) return;
    _wanted = true;
    _backoff = 0;
    _connect();
    _startLocation();
  }

  void stop() {
    if (!_wanted && status == TrackingStatus.idle) return;
    _wanted = false;
    _generation++;
    _retryTimer?.cancel();
    _reconnectTimer?.cancel();
    _posSub?.cancel();
    _posSub = null;
    _channel?.sink.close();
    _channel = null;
    _pending.clear();
    lastPosition = null; lastSentAt = null; sentCount = 0;
    socket = SocketStatus.disconnected;
    status = TrackingStatus.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  // ------------------------------------------------------------ location

  LocationSettings _settings() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
          intervalDuration: const Duration(seconds: 5),
          // This turns the stream into a foreground service with a notification.
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'HYOps - driver location',
            notificationText: 'Sharing your live location with dispatch',
            notificationChannelName: 'Live location',
            enableWakeLock: true,
            setOngoing: true,
          ),
        );
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return AppleSettings(
          accuracy: LocationAccuracy.high,
          activityType: ActivityType.automotiveNavigation,
          distanceFilter: 10,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
          allowBackgroundLocationUpdates: true,
        );
      default:
        return const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10);
    }
  }

  Future<void> _startLocation() async {
    if (!_wanted || !isSignedIn()) return;
    final generation = _generation;
    _retryTimer?.cancel();
    _setStatus(TrackingStatus.starting);
    try {
      final enabled = await locationEnabled();
      if (!_wanted || generation != _generation || !isSignedIn()) return;
      if (!enabled) return _fail(TrackingStatus.locationOff);
      var perm = await checkPermission();
      if (!_wanted || generation != _generation || !isSignedIn()) return;
      if (perm == LocationPermission.denied) perm = await requestPermission();
      if (!_wanted || generation != _generation || !isSignedIn()) return;
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return _fail(TrackingStatus.noPermission);
      }
      if (!_wanted) return; // stopped while we were asking
      await _posSub?.cancel();
      if (!_wanted || generation != _generation || !isSignedIn()) return;
      _posSub = positions(_settings()).listen(
        (p) { if (generation == _generation) _onPosition(p); },
        onError: (_) { if (generation == _generation && _wanted) _fail(TrackingStatus.error); },
      );
      _setStatus(TrackingStatus.live);
    } catch (_) {
      if (generation == _generation && _wanted) _fail(TrackingStatus.error);
    }
  }

  void _fail(TrackingStatus s) {
    if (!_wanted || !isSignedIn()) return;
    _posSub?.cancel();
    _posSub = null;
    _setStatus(s);
    if (_wanted) _retryTimer = Timer(const Duration(seconds: 10), _startLocation);
  }

  void _onPosition(Position p) {
    if (!_wanted || !isSignedIn()) return;
    lastPosition = p;
    final msg = jsonEncode({
      'type': 'DRIVER_LOCATION_UPDATE',
      'payload': [_tripId, p.latitude, p.longitude, p.accuracy.isFinite ? p.accuracy.clamp(0, double.infinity) : 0,
        p.speed.isFinite ? p.speed.clamp(0, double.infinity) : 0,
        p.heading.isFinite ? p.heading.clamp(0, 360) : 0, p.timestamp.toUtc().toIso8601String()],
    });
    final ch = _channel;
    if (socket == SocketStatus.connected && ch != null) {
      ch.sink.add(msg);
      lastSentAt = DateTime.now();
      sentCount++;
    } else {
      _pending.add(msg);
      if (_pending.length > 100) _pending.removeAt(0);
    }
    notifyListeners();
  }

  // ------------------------------------------------------------ websocket

  Future<void> _connect() async {
    if (!_wanted || !isSignedIn() || socket == SocketStatus.connecting) return;
    _setSocket(SocketStatus.connecting);
    final generation = _generation;
    try {
      final cookie = await cookieProvider();
      if (!_wanted || generation != _generation || !isSignedIn()) return;
      final ch = connectSocket(cookie);
      await ch.ready; // throws if the server is unreachable
      if (!_wanted || generation != _generation || !isSignedIn()) {
        ch.sink.close();
        return;
      }
      _channel = ch;
      _backoff = 0;
      _setSocket(SocketStatus.connected);
      for (final m in _pending) {
        final payload = (jsonDecode(m) as Map)['payload'] as List;
        if (payload[0] != _tripId || DateTime.now().toUtc().difference(DateTime.parse(payload[6] as String)).inSeconds > 60) continue;
        ch.sink.add(m);
        sentCount++;
      }
      _pending.clear();
      ch.stream.listen((_) {}, onDone: () { if (generation == _generation) _onSocketClosed(); }, onError: (_) { if (generation == _generation) _onSocketClosed(); }, cancelOnError: true);
    } catch (_) {
      if (generation == _generation) _onSocketClosed();
    }
  }

  void _onSocketClosed() {
    _channel = null;
    _setSocket(SocketStatus.disconnected);
    if (!_wanted || !isSignedIn()) return;
    _reconnectTimer?.cancel();
    final secs = math.min(30, 1 << math.min(_backoff, 5));
    _backoff++;
    _reconnectTimer = Timer(Duration(seconds: secs), _connect);
  }

  void _setStatus(TrackingStatus s) {
    if (status == s) return;
    status = s;
    notifyListeners();
  }

  void _setSocket(SocketStatus s) {
    if (socket == s) return;
    socket = s;
    notifyListeners();
  }
}
