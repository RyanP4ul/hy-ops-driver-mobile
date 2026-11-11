import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyops_flutter/api/api_client.dart';
import 'package:hyops_flutter/repositories/driver_repository.dart';
import 'package:hyops_flutter/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_acceptance_test.dart' show TestAdapter, reply;
import 'widget_test.dart' as fixtures;

class SettingsRepository extends fixtures.FakeRepository {
  int settingsReads = 0;
  bool unavailable = false;
  SettingsRepository(super.client);

  @override
  Future<Duration> automaticRefreshInterval() async {
    settingsReads++;
    if (unavailable) throw StateError('Settings unavailable');
    return const Duration(milliseconds: 5000);
  }
}

class RestoredClient extends fixtures.FakeClient {
  @override
  Future<void> restore() async {
    remember = true;
    accepted = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'settings endpoint accepts milliseconds and falls back for invalid values',
    () async {
      for (final value in [
        '15000',
        45000,
        null,
        '',
        'bad',
        '1.5',
        '0',
        '-100',
      ]) {
        final api = ApiClient(
          baseUrl: 'http://localhost:5192',
          transport: Dio()
            ..httpClientAdapter = TestAdapter((request) async {
              expect(request.path, '/driver/settings');
              return reply({
                'mobile_automatic_refresh_interval_ms': value,
              }, 200);
            }),
        );
        api.configure();
        final interval = await DriverRepository(api).automaticRefreshInterval();
        expect(
          interval.inMilliseconds,
          value == '15000'
              ? 15000
              : value == 45000
              ? 45000
              : 30000,
        );
        api.dio.close();
      }
    },
  );

  for (final restore in [false, true]) {
    testWidgets(
      'configured timer is used after ${restore ? 'session restore' : 'login'} and resume',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final client = restore ? RestoredClient() : fixtures.FakeClient();
        // Keep real GPS and sockets disabled while exercising the polling timer.
        client.networkUnavailable.value = true;
        final repo = SettingsRepository(client);
        final state = AppState(
          await SharedPreferences.getInstance(),
          api: client,
          driverRepository: repo,
        );
        try {
          await state.initialize();
          if (!restore) {
            await state.login(
              'driver@example.test',
              'valid-password',
              remember: false,
            );
          }
          expect(state.automaticRefreshInterval.inMilliseconds, 5000);
          expect(repo.settingsReads, 1);
          final before = repo.reads;
          await tester.pump(const Duration(milliseconds: 4999));
          expect(repo.reads, before);
          await tester.pump(const Duration(milliseconds: 1));
          expect(repo.reads, before + 1);
          state.didChangeAppLifecycleState(AppLifecycleState.paused);
          await tester.pump(const Duration(seconds: 10));
          expect(repo.reads, before + 1);
          state.didChangeAppLifecycleState(AppLifecycleState.resumed);
          await tester.pump();
          final resumed = repo.reads;
          await tester.pump(const Duration(seconds: 5));
          expect(repo.reads, resumed + 1);
          expect(repo.settingsReads, 1);
          await state.logout();
          final loggedOut = repo.reads;
          await tester.pump(const Duration(seconds: 10));
          expect(repo.reads, loggedOut);
        } finally {
          state.dispose();
        }
      },
    );
  }

  testWidgets(
    'unavailable settings preserve login and the 30 second fallback',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final client = fixtures.FakeClient()..networkUnavailable.value = true;
      final repo = SettingsRepository(client)..unavailable = true;
      final state = AppState(
        await SharedPreferences.getInstance(),
        api: client,
        driverRepository: repo,
      );
      try {
        await state.login(
          'driver@example.test',
          'valid-password',
          remember: false,
        );
        expect(state.loggedIn, true);
        expect(state.automaticRefreshInterval.inSeconds, 30);
        final before = repo.reads;
        await tester.pump(const Duration(seconds: 30));
        expect(repo.reads, before + 1);
      } finally {
        state.dispose();
      }
    },
  );
}
