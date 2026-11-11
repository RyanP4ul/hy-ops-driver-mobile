import 'dart:async';
import 'dart:ui' as ui;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hyops_flutter/api/api_client.dart';
import 'package:hyops_flutter/core/config.dart';
import 'package:hyops_flutter/repositories/driver_repository.dart';
import 'package:hyops_flutter/services/assignment_socket.dart';
import 'package:hyops_flutter/services/offline_policy.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android real secure storage, expiry/revocation, pagination, filtering, sockets, and proofs',
    (tester) async {
      final client = ApiClient();
      await client.restore();
      await client.clear();
      final repo = DriverRepository(client);
      await client.login('driver1@example.test', 'fixture-password', true);
      await client.validate();
      expect((await repo.profile()).id, '3');
      final restored = ApiClient();
      await restored.restore();
      expect(restored.remember, true);
      await restored.validate();
      final control = Dio(
        BaseOptions(
          baseUrl: Config.origin.toString(),
          headers: {'x-hyops-fixture': 'driver-device-checks'},
        ),
      );
      final expired =
          (await control.get<dynamic>('/__test__/expired-access')).data['token']
              as String;
      await restored.cookies.saveFromResponse(Config.origin, [
        Cookie('access_token', expired)..path = '/',
      ]);
      await restored.validate(); // A real expired, correctly signed JWT refreshes successfully.
      await control.post<dynamic>('/__test__/revoke');
      await expectLater(restored.validate(), throwsStateError);
      final revoked = ApiClient();
      await revoked.restore();
      expect(revoked.remember, false);
      await client.login('driver2@example.test', 'fixture-password', false);
      expect((await repo.trips()).items, isEmpty);
      expect((await repo.history()).items, isEmpty);
      await client.logout();
      await client.login('driver1@example.test', 'fixture-password', true);
      final first = await repo.trips(past: true);
      final second = await repo.trips(past: true, page: 1);
      // A single completed run holds 25 stops; history is independently paginated.
      expect(first.items.length, 1);
      expect(second.items, isEmpty);
      final history1 = await repo.history(
        page: 0,
        status: 'delivered',
        from: '2026-11-01',
        to: '2026-11-01',
      );
      final history2 = await repo.history(
        page: 1,
        status: 'delivered',
        from: '2026-11-01',
        to: '2026-11-01',
      );
      expect(history1.total, 25);
      expect(history1.items.length, 20);
      expect(history2.items.length, 5);
      expect((await repo.history(status: 'failed')).items, isEmpty);
      final before = DateTime.now();
      await control.get<dynamic>('/__test__/slow');
      expect(
        DateTime.now().difference(before).inMilliseconds,
        greaterThanOrEqualTo(450),
      );
      await repo.profile();
      final origin = client.dio.options.baseUrl;
      client.dio.options.baseUrl = 'http://127.0.0.1:1';
      client.dio.options.connectTimeout = const Duration(milliseconds: 500);
      expect((await repo.profile()).id, '3');
      expect(repo.offline, true);
      await expectLater(
        repo.startTrip(first.items.first),
        throwsA(isA<OfflineActionBlocked>()),
      );
      client.dio.options.baseUrl = origin;
      await client
          .validate(); // Network loss did not discard secure credentials.
      repo.beginReadCycle();
      await repo.profile();
      await repo.trips();
      await repo.history();
      repo.completeRefresh();
      expect(repo.offline, false);
      var events = 0;
      final socket = AssignmentSocket(cookieProvider: client.socketCookie, changed: () => events++);
      socket.start();
      Future<void> wait(int count) async {
        for (var i = 0; i < 100 && events < count; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(events, greaterThanOrEqualTo(count));
      }

      await wait(1);
      await control.post<dynamic>('/__test__/assignment');
      await wait(2);
      socket.stop();
      await control.post<dynamic>('/__test__/dispatch');
      final trip = (await repo.trips()).items.first;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)
        ..drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
      canvas.drawCircle(
        const ui.Offset(20, 20),
        10,
        ui.Paint()..color = const ui.Color(0xff000000),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(64, 64);
      final buffer = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = buffer!.buffer.asUint8List();
      image.dispose();
      picture.dispose();
      await repo.uploadProof(
        trip.stops.first.id,
        bytes,
        'photo',
        'bfbf9a82-e629-4d92-a2da-e016848828df',
      );
      await repo.uploadProof(
        trip.stops.first.id,
        bytes,
        'signature',
        'd4624bd6-b552-4a62-82a1-c87463409f62',
      );
      final proofs = await repo.proofs(trip.stops.first.id);
      expect(proofs.length, 2);
      expect(
        (await repo.proofBytes(
          trip.stops.first.id,
          proofs.first['id'] as String,
        )).isNotEmpty,
        true,
      );
      // Persist a fresh remembered session for a second instrumentation process.
      await client.login('driver1@example.test', 'fixture-password', true);
      await repo.profile();
      await repo.trips();
      await repo.history();
    },
  );
}
