import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/config.dart';

class AssignmentEvent {
  final String eventId, kind;
  final int deliveryId, driverId;
  const AssignmentEvent(
    this.eventId,
    this.kind,
    this.deliveryId,
    this.driverId,
  );

  static AssignmentEvent? parse(Object? payload) {
    if (payload is! Map) return null;
    final id = payload['eventId'], kind = payload['kind'];
    final delivery = payload['deliveryId'], driver = payload['driverId'];
    if (id is! String ||
        id.isEmpty ||
        delivery is! int ||
        delivery <= 0 ||
        driver is! int ||
        driver <= 0 ||
        !['assigned', 'updated', 'removed', 'cancelled'].contains(kind)) {
      return null;
    }
    return AssignmentEvent(id, kind as String, delivery, driver);
  }

  String get notice => switch (kind) {
    'assigned' => 'You have a new delivery: #$deliveryId.',
    'removed' => 'Delivery #$deliveryId is no longer assigned to you.',
    'cancelled' => 'Delivery #$deliveryId has been cancelled.',
    _ => 'Your delivery #$deliveryId has been updated.',
  };
}

/// Receives assignments independently of GPS permission and reconciles after
/// every authenticated connection, including events missed while disconnected.
class AssignmentSocket {
  final Future<String> Function() cookieProvider;
  final void Function() changed;
  final void Function(AssignmentEvent)? onAssignment;
  final WebSocketChannel Function(String) connectSocket;
  final Duration handshakeTimeout;
  final Duration Function(int attempt) retryDelay;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retry, _handshake;
  bool _active = false, _ready = false;
  int _generation = 0, _attempt = 0;
  final Set<String> _seen = {};

  AssignmentSocket({
    required this.cookieProvider,
    required this.changed,
    this.onAssignment,
    WebSocketChannel Function(String)? connectSocket,
    this.handshakeTimeout = const Duration(seconds: 10),
    Duration Function(int)? retryDelay,
  }) : connectSocket =
           connectSocket ??
           ((cookie) => IOWebSocketChannel.connect(
             Uri.parse(Config.wsUrl),
             headers: {'Cookie': cookie},
             pingInterval: const Duration(seconds: 20),
             connectTimeout: const Duration(seconds: 10),
           )),
       retryDelay =
           retryDelay ??
           ((attempt) => Duration(seconds: 1 << attempt.clamp(0, 5)));

  void start() {
    if (_active) return;
    _active = true;
    unawaited(_connect());
  }

  void stop() {
    _active = false;
    _generation++;
    _retry?.cancel();
    _close();
    _seen.clear();
    _attempt = 0;
  }

  Future<void> _connect() async {
    if (!_active) return;
    final generation = ++_generation;
    _ready = false;
    try {
      final cookie = await cookieProvider();
      if (!_active || generation != _generation) return;
      final socket = connectSocket(cookie);
      _channel = socket;
      _subscription = socket.stream.listen(
        (raw) => _message(raw, generation),
        onDone: () => _reconnect(generation),
        onError: (_) => _reconnect(generation),
        cancelOnError: true,
      );
      _handshake = Timer(handshakeTimeout, () => _reconnect(generation));
      await socket.ready;
      if (!_active || generation != _generation) {
        unawaited(_closeSocket(socket));
      }
    } catch (_) {
      _reconnect(generation);
    }
  }

  void _message(Object? raw, int generation) {
    if (!_active || generation != _generation || raw is! String) return;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return;
    }
    if (decoded is! Map) return;
    if (decoded['type'] == 'WS_READY') {
      if (_ready) return;
      _ready = true;
      _handshake?.cancel();
      _attempt = 0;
      changed();
    } else if (_ready && decoded['type'] == 'DRIVER_ASSIGNMENT_CHANGED') {
      final event = AssignmentEvent.parse(decoded['payload']);
      if (event == null || !_seen.add(event.eventId)) return;
      if (_seen.length > 200) _seen.remove(_seen.first);
      onAssignment?.call(event);
      changed();
    }
  }

  void _reconnect(int generation) {
    if (!_active || generation != _generation) return;
    // Invalidate callbacks before closing to prevent duplicate reconnect timers.
    _generation++;
    _close();
    _retry?.cancel();
    _retry = Timer(retryDelay(_attempt++), () => unawaited(_connect()));
  }

  void _close() {
    _handshake?.cancel();
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    final socket = _channel;
    _channel = null;
    if (socket != null) unawaited(_closeSocket(socket));
  }

  static Future<void> _closeSocket(WebSocketChannel socket) async {
    try {
      await socket.sink.close();
    } catch (_) {
      /* Already disconnected. */
    }
  }
}
