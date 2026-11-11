import 'package:flutter_dotenv/flutter_dotenv.dart';

const _releaseMode = bool.fromEnvironment('dart.vm.product');

class Config {
  static const productionApiUrl = 'https://hy-ops-frontend.vercel.app/api';
  static const productionWsUrl = 'wss://hy-ops-backend.onrender.com/ws';
  static String? get _apiOverride =>
      _nonEmpty(const String.fromEnvironment('API_URL'));
  static String? get _baseOverride =>
      _nonEmpty(const String.fromEnvironment('BASE_URL'));

  static String get apiUrl {
    final apiOverride = _apiOverride;
    if (apiOverride != null) return apiOverride;

    final baseOverride = _baseOverride;
    if (baseOverride != null) return _proxyApiUrl(baseOverride);

    final api = _env('API_URL');
    if (api != null) return api;

    final base = _env('BASE_URL');
    return base == null ? productionApiUrl : _proxyApiUrl(base);
  }

  static String _proxyApiUrl(String base) =>
      parseApiUrl(base).replace(path: '/api').toString();

  static String? _env(String key) =>
      dotenv.isInitialized ? _nonEmpty(dotenv.maybeGet(key)) : null;

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static const routingUrl = String.fromEnvironment(
    'ROUTING_URL',
    defaultValue: 'https://router.project-osrm.org',
  );

  static Uri get origin => parseApiUrl(apiUrl);

  static Uri parseApiUrl(String value, {bool requireHttps = _releaseMode}) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        !['http', 'https'].contains(uri.scheme) ||
        !['', '/', '/api', '/api/'].contains(uri.path) ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      throw StateError(
        'Configure API_URL with the HYOps backend origin or frontend /api URL.',
      );
    }
    if (requireHttps && uri.scheme != 'https') {
      throw StateError('Release builds require an HTTPS backend.');
    }
    return uri.path.endsWith('/')
        ? uri.replace(path: uri.path.substring(0, uri.path.length - 1))
        : uri;
  }

  static String get wsUrl => resolveWebSocketUrl(
    origin,
    override:
        _nonEmpty(const String.fromEnvironment('WS_URL')) ??
        (_apiOverride == null && _baseOverride == null
            ? _env('WS_URL')
            : null) ??
        '',
  );

  static String resolveWebSocketUrl(
    Uri api, {
    String override = '',
    bool requireSecure = _releaseMode,
  }) {
    // The frontend forwards /api/* only. Live tracking connects to Render.
    // A local/direct backend override derives its own /ws endpoint instead.
    final fallback = api.origin == Uri.parse(productionApiUrl).origin
        ? productionWsUrl
        : api
              .replace(
                scheme: api.scheme == 'https' ? 'wss' : 'ws',
                path: '/ws',
              )
              .toString();
    final uri = Uri.tryParse(override.isEmpty ? fallback : override);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        !['ws', 'wss'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        (requireSecure && uri.scheme != 'wss')) {
      throw StateError('Configure a valid secure WebSocket URL.');
    }
    return uri.toString();
  }
}
