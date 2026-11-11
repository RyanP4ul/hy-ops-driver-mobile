import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/io.dart';
import 'package:hyops_flutter/services/assignment_socket.dart';

Future<void> waitUntil(bool Function() check) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!check() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(check(), isTrue);
}

void main() {
  test(
    'assignments arrive immediately, deduplicate, and reconcile on reconnect',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final peers = <WebSocket>[];
      var cookies = '';
      final incoming = server.listen((request) async {
        cookies = request.headers.value('cookie') ?? '';
        final peer = await WebSocketTransformer.upgrade(request);
        peers.add(peer);
        peer.listen((_) {});
        peer.add(jsonEncode({'type': 'WS_READY'}));
      });
      var refreshes = 0;
      final notices = <AssignmentEvent>[];
      final socket = AssignmentSocket(
        cookieProvider: () async => 'access_token=fixture',
        changed: () => refreshes++,
        onAssignment: notices.add,
        retryDelay: (_) => const Duration(milliseconds: 20),
        connectSocket: (cookie) => IOWebSocketChannel.connect(
          Uri.parse('ws://127.0.0.1:${server.port}/ws'),
          headers: {'Cookie': cookie},
        ),
      );
      final event = jsonEncode({
        'type': 'DRIVER_ASSIGNMENT_CHANGED',
        'payload': {
          'eventId': 'assigned-42',
          'deliveryId': 42,
          'driverId': 3,
          'kind': 'assigned',
        },
      });
      try {
        socket.start();
        socket.start();
        await waitUntil(() => refreshes == 1);
        expect(cookies, 'access_token=fixture');
        expect(peers, hasLength(1));
        peers.single.add(event);
        peers.single.add(event);
        peers.single.add('not-json');
        peers.single.add(
          jsonEncode({
            'type': 'DRIVER_ASSIGNMENT_CHANGED',
            'payload': {'eventId': 'invalid'},
          }),
        );
        await waitUntil(() => notices.length == 1);
        expect(notices.single.notice, 'You have a new delivery: #42.');
        expect(refreshes, 2);
        await peers.single.close();
        await waitUntil(() => peers.length == 2 && refreshes == 3);
        peers.last.add(event);
        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(notices, hasLength(1));
        socket.stop();
        final before = refreshes;
        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(refreshes, before);
      } finally {
        socket.stop();
        for (final peer in peers) {
          await peer.close();
        }
        await incoming.cancel();
        await server.close(force: true);
      }
    },
  );

  test(
    'stopping while authentication is pending cannot open an obsolete socket',
    () async {
      final cookie = Completer<String>();
      var opened = false;
      final socket = AssignmentSocket(
        cookieProvider: () => cookie.future,
        changed: () => fail('Stopped session must not refresh'),
        connectSocket: (_) {
          opened = true;
          throw StateError('Obsolete session');
        },
      );
      socket.start();
      socket.stop();
      cookie.complete('access_token=obsolete');
      await Future<void>.delayed(Duration.zero);
      expect(opened, isFalse);
    },
  );
}
