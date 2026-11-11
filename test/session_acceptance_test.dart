import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyops_flutter/api/api_client.dart';
import 'package:hyops_flutter/services/session_store.dart';

class MemorySessionStore implements SessionStore {
  String? token;
  @override Future<String?> read() async => token;
  @override Future<void> write(String value) async { token = value; }
  @override Future<void> clear() async { token = null; }
}
class TestAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions request) handle;
  TestAdapter(this.handle);
  @override Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) => handle(options);
  @override void close({bool force = false}) {}
}
ResponseBody reply(Object data, int status, {String? cookie}) => ResponseBody.fromString(jsonEncode(data), status,
  headers: {Headers.contentTypeHeader: ['application/json'], if (cookie != null) 'set-cookie': [cookie]});

void main() {
  test('production proxy keeps /api for login and authenticated driver requests', () async {
    final paths = <String>[];
    final adapter = TestAdapter((request) async {
      paths.add(request.uri.path);
      expect(request.uri.host, 'hy-ops-frontend.vercel.app');
      if (request.path == '/auth/login') {
        return reply({'access_token': 'access', 'refresh_token': 'refresh'}, 200);
      }
      expect(request.headers['Cookie'], contains('access_token=access'));
      return reply({'role': 'driver'}, 200);
    });
    final client = ApiClient(
      transport: Dio()..httpClientAdapter = adapter,
      sessionStore: MemorySessionStore(),
      baseUrl: 'https://hy-ops-frontend.vercel.app/api',
    );
    await client.login('driver@example.test', 'password', false);
    await client.validate();
    expect(paths, ['/api/auth/login', '/api/auth/me']);
  });

  test('remembered login survives a new client; concurrent expiration refreshes once; logout clears it', () async {
    final store = MemorySessionStore();
    var refreshes = 0;
    final adapter = TestAdapter((request) async {
      if (request.path == '/auth/login') {
        expect((request.data as Map)['is_mobile'], true);
        return reply({'access_token': 'expired', 'refresh_token': 'refresh'}, 200);
      }
      if (request.path == '/auth/refresh') {
        refreshes++; await Future<void>.delayed(const Duration(milliseconds: 40));
        return reply('ok', 200, cookie: 'access_token=fresh; Path=/; HttpOnly');
      }
      if (request.path == '/auth/logout') return reply({'ok': true}, 200);
      return request.headers['Cookie'].toString().contains('access_token=fresh') ? reply({'role': 'driver', 'items': []}, 200) : reply({'message': 'Unauthorized'}, 401);
    });
    ApiClient client() => ApiClient(transport: Dio()..httpClientAdapter = adapter, sessionStore: store, baseUrl: 'http://localhost:5192');
    final first = client(); await first.login('driver@example.test', 'password', true);
    expect(store.token, 'refresh');
    final restarted = client(); await restarted.restore();
    expect(restarted.remember, true);
    await Future.wait([restarted.dio.get<dynamic>('/driver/trips'), restarted.dio.get<dynamic>('/driver/profile')]);
    expect(refreshes, 1);
    await restarted.validate(); await restarted.logout();
    expect(store.token, null); expect(await restarted.cookies.loadForRequest(Uri.parse('http://localhost:5192')), isEmpty);
    final again = client(); await again.restore(); expect(again.remember, false);
  });

  test('revoked refresh credentials clear secure session and signal loss once', () async {
    final store = MemorySessionStore()..token = 'revoked';
    final client = ApiClient(transport: Dio()..httpClientAdapter = TestAdapter((_) async => reply({'message': 'Unauthorized'}, 401)), sessionStore: store, baseUrl: 'http://localhost:5192');
    var lost = 0; client.onSessionLost = () => lost++;
    await client.restore();
    await expectLater(client.validate(), throwsStateError);
    expect(store.token, null); expect(lost, 1);
  });

  test('a temporary network failure preserves remembered credentials; offline logout still clears them', () async {
    final store = MemorySessionStore()..token = 'remembered';
    final client = ApiClient(transport: Dio()..httpClientAdapter = TestAdapter((request) async => throw DioException(requestOptions: request, type: DioExceptionType.connectionError)), sessionStore: store, baseUrl: 'http://localhost:5192');
    await client.restore();
    await expectLater(client.validate(), throwsA(isA<DioException>()));
    expect(store.token, 'remembered');
    expect(await client.logout(), false); expect(store.token, null);
  });

  test('late refresh response cannot resurrect a logged-out session', () async {
    final store = MemorySessionStore()..token = 'remembered';
    final response = Completer<ResponseBody>();
    final started = Completer<void>();
    final client = ApiClient(transport: Dio()..httpClientAdapter = TestAdapter((_) { started.complete(); return response.future; }), sessionStore: store, baseUrl: 'http://localhost:5192');
    await client.restore(); final refresh = client.refresh(); await started.future;
    await client.clear();
    response.complete(reply('ok', 200, cookie: 'access_token=obsolete; Path=/'));
    expect(await refresh, false); expect(store.token, null);
    expect(await client.cookies.loadForRequest(Uri.parse('http://localhost:5192')), isEmpty);
  });
}
