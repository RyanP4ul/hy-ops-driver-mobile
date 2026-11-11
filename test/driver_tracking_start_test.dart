import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:web_socket_channel/io.dart';
import 'package:hyops_flutter/services/location_tracking_service.dart';
import 'package:hyops_flutter/data/models.dart';
import 'widget_test.dart' as fixtures;

Position fix() => Position(longitude: 121, latitude: 14.5, timestamp: DateTime.now(), accuracy: 5, altitude: 0, altitudeAccuracy: 0, heading: 90, headingAccuracy: 0, speed: 2, speedAccuracy: 0);

Future<void> until(bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) { await Future<void>.delayed(const Duration(milliseconds: 10)); }
  expect(ready(), true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('trip starts only on its Manila day at or after departure', () {
    final trip = Trip.fromJson(fixtures.tripJson());
    expect(trip.canStartAt(DateTime.parse('2026-11-02T09:59:59+08:00')), false);
    expect(trip.canStartAt(DateTime.parse('2026-11-02T10:00:00+08:00')), true);
    expect(trip.canStartAt(DateTime.parse('2026-11-02T23:59:59+08:00')), true);
    expect(trip.canStartAt(DateTime.parse('2026-11-03T00:00:00+08:00')), false);
    trip.status = TripStatus.inProgress;
    expect(trip.canStartAt(DateTime.parse('2026-11-02T10:00:00+08:00')), false);
  });

  test('signed-in GPS sends through a real socket without a trip and stops immediately on logout', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final peers = <WebSocket>[], received = <Map<String, dynamic>>[];
    final subscription = server.transform(WebSocketTransformer()).listen((socket) {
      peers.add(socket); socket.listen((raw) => received.add(jsonDecode(raw as String) as Map<String, dynamic>));
    });
    final positions = StreamController<Position>.broadcast();
    var signedIn = true;
    final service = LocationTrackingService(cookieProvider: () async => 'access_token=fixture', isSignedIn: () => signedIn,
      locationEnabled: () async => true, checkPermission: () async => LocationPermission.always,
      positions: (_) => positions.stream,
      connectSocket: (cookie) => IOWebSocketChannel.connect(Uri.parse('ws://127.0.0.1:${server.port}'), headers: {'Cookie': cookie}));
    try {
      service.start();
      await until(() => service.socket == SocketStatus.connected && service.status == TrackingStatus.live);
      positions.add(fix()); await until(() => received.length == 1);
      expect(received.single['type'], 'DRIVER_LOCATION_UPDATE');
      expect((received.single['payload'] as List).first, isNull);
      expect((received.single['payload'] as List)[1], 14.5);
      signedIn = false; service.stop();
      positions.add(fix()); service.start();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(received.length, 1); expect(service.pendingCount, 0);
      expect(service.status, TrackingStatus.idle);
    } finally {
      service.dispose(); await positions.close();
      for (final socket in peers) { await socket.close(); }
      await subscription.cancel(); await server.close(force: true);
    }
  });

  test('logout during a location permission check cannot restart tracking', () async {
    final permission = Completer<LocationPermission>();
    var signedIn = true, subscribed = false;
    final service = LocationTrackingService(cookieProvider: () async => throw StateError('Offline'), isSignedIn: () => signedIn,
      locationEnabled: () async => true, checkPermission: () => permission.future,
      positions: (_) { subscribed = true; return const Stream.empty(); });
    service.start(); await Future<void>.delayed(Duration.zero);
    signedIn = false; service.stop(); permission.complete(LocationPermission.always);
    await Future<void>.delayed(Duration.zero);
    expect(subscribed, false); expect(service.status, TrackingStatus.idle);
    expect(service.pendingCount, 0); service.dispose();
  });
}
