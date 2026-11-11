import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyops_flutter/core/config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(dotenv.clean);

  test(
    'the bundled dotenv asset loads and contains valid HTTP endpoints',
    () async {
      final asset = DotEnv();
      await asset.load();
      expect(
        Config.parseApiUrl(asset.get('BASE_URL'), requireHttps: false).host,
        isNotEmpty,
      );
      expect(
        Config.parseApiUrl(asset.get('API_URL'), requireHttps: false).host,
        isNotEmpty,
      );
    },
  );

  test('dotenv API_URL takes precedence over BASE_URL', () {
    dotenv.loadFromString(
      envString: '''
BASE_URL=https://frontend.example.test
API_URL=https://backend.example.test
WS_URL=wss://sockets.example.test/ws
''',
    );
    if (!const bool.hasEnvironment('API_URL') &&
        !const bool.hasEnvironment('BASE_URL')) {
      expect(Config.origin.toString(), 'https://backend.example.test');
      if (!const bool.hasEnvironment('WS_URL')) {
        expect(Config.wsUrl, 'wss://sockets.example.test/ws');
      }
    }
  });

  test('dotenv BASE_URL supplies the proxy API URL when API_URL is empty', () {
    dotenv.loadFromString(
      envString: '''
BASE_URL=https://frontend.example.test/
API_URL=
''',
    );
    if (!const bool.hasEnvironment('API_URL') &&
        !const bool.hasEnvironment('BASE_URL')) {
      expect(Config.origin.toString(), 'https://frontend.example.test/api');
    }
  });

  test(
    'a build without endpoint flags targets production instead of a LAN IP',
    () {
      if (!const bool.hasEnvironment('API_URL') &&
          !const bool.hasEnvironment('BASE_URL')) {
        expect(
          Config.origin.toString(),
          'https://hy-ops-frontend.vercel.app/api',
        );
        if (!const bool.hasEnvironment('WS_URL')) {
          expect(Config.wsUrl, 'wss://hy-ops-backend.onrender.com/ws');
        }
      }
    },
  );
  test(
    'production API retains the frontend proxy prefix and sockets use Render',
    () {
      final api = Config.parseApiUrl(
        Config.productionApiUrl,
        requireHttps: true,
      );
      expect(api.path, '/api');
      expect(
        Config.resolveWebSocketUrl(api, requireSecure: true),
        'wss://hy-ops-backend.onrender.com/ws',
      );
      expect(
        Config.parseApiUrl('${Config.productionApiUrl}/').toString(),
        Config.productionApiUrl,
      );
    },
  );

  test(
    'direct and local API overrides derive sockets from the same backend',
    () {
      final local = Config.parseApiUrl('http://192.168.0.102:5173');
      expect(Config.resolveWebSocketUrl(local), 'ws://192.168.0.102:5173/ws');
      final direct = Config.parseApiUrl('https://hy-ops-backend.onrender.com');
      expect(
        Config.resolveWebSocketUrl(direct, requireSecure: true),
        'wss://hy-ops-backend.onrender.com/ws',
      );
      expect(
        Config.resolveWebSocketUrl(local, override: 'ws://localhost:5192/ws'),
        'ws://localhost:5192/ws',
      );
    },
  );

  test(
    'invalid endpoints and insecure release configurations are rejected',
    () {
      for (final value in [
        'missing-host',
        'https://example.com/auth',
        'https://example.com/api?token=secret',
        'https://user:secret@example.com',
      ]) {
        expect(() => Config.parseApiUrl(value), throwsStateError);
      }
      expect(
        () => Config.parseApiUrl('http://localhost:5173', requireHttps: true),
        throwsStateError,
      );
      final api = Config.parseApiUrl(Config.productionApiUrl);
      for (final value in [
        'https://example.com/ws',
        'ws:///ws',
        'wss://user:secret@example.com/ws',
      ]) {
        expect(
          () => Config.resolveWebSocketUrl(api, override: value),
          throwsStateError,
        );
      }
      expect(
        () => Config.resolveWebSocketUrl(
          api,
          override: 'ws://localhost:5173/ws',
          requireSecure: true,
        ),
        throwsStateError,
      );
    },
  );
}
