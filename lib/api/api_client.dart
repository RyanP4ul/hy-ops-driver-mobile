import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../services/offline_policy.dart';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';

import '../core/config.dart';
import '../services/session_store.dart';

class ApiClient {
  final Dio dio;
  final CookieJar cookies = CookieJar();
  final String? baseUrl;
  final SessionStore? sessionStore;
  late final SessionStore _store =
      sessionStore ?? SecureSessionStore(_origin.toString());
  Future<bool>? _refreshing;
  Future<void> _storageQueue = Future.value();
  CancelToken _sessionCancel = CancelToken();
  bool remember = false;
  void Function()? onSessionLost;
  final ValueNotifier<bool> networkUnavailable = ValueNotifier(false);
  Future<void> Function(String scope)? onCacheInvalidated;
  Future<void> Function(String scope)? onSessionQuarantined;
  String? _cacheScope;
  String? get cacheScope => _cacheScope;
  int get sessionGeneration => _generation;
  String _scopeFor(String refresh) =>
      sha256.convert(utf8.encode('${_origin.toString()}|$refresh')).toString();
  int _generation = 0;
  Uri get _origin => baseUrl == null ? Config.origin : Uri.parse(baseUrl!);

  ApiClient({Dio? transport, this.sessionStore, this.baseUrl})
    : dio =
          transport ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
            ),
          ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) async {
          if (networkUnavailable.value &&
              request.method != 'GET' &&
              request.method != 'HEAD' &&
              !request.path.startsWith('/auth/')) {
            return handler.reject(
              DioException(
                requestOptions: request,
                type: DioExceptionType.cancel,
                error: OfflineActionBlocked(),
              ),
            );
          }
          final generation = request.extra['generation'] ??= _generation;
          if (generation != _generation)
            return handler.reject(
              DioException(
                requestOptions: request,
                type: DioExceptionType.cancel,
                message: 'Session changed.',
              ),
            );
          request.cancelToken ??= _sessionCancel;
          final values = await cookies.loadForRequest(request.uri);
          request.headers['Cookie'] = values
              .map((c) => '${c.name}=${c.value}')
              .join('; ');
          handler.next(request);
        },
        onResponse: (response, handler) async {
          if (response.requestOptions.extra['generation'] == _generation)
            networkUnavailable.value = false;
          if (response.requestOptions.extra['generation'] == _generation) {
            final values = response.headers['set-cookie'] ?? [];
            await cookies.saveFromResponse(
              response.requestOptions.uri,
              values.map(Cookie.fromSetCookieValue).toList(),
            );
            if (response.requestOptions.path == '/auth/refresh' && remember) {
              final rotated = values
                  .map(Cookie.fromSetCookieValue)
                  .where((c) => c.name == 'refresh_token')
                  .firstOrNull;
              if (rotated != null) {
                final generation = response.requestOptions.extra['generation'];
                await _persist(() async {
                  if (generation == _generation && remember)
                    await _store.write(rotated.value);
                });
              }
            }
          }
          handler.next(response);
        },
        onError: (error, handler) async {
          final request = error.requestOptions;
          if (request.extra['generation'] == _generation &&
              isConnectionFailure(error))
            networkUnavailable.value = true;
          if (request.extra['generation'] != _generation ||
              error.response?.statusCode != 401 ||
              request.path.startsWith('/auth/'))
            return handler.next(error);
          if (request.extra['retried'] == true) {
            await _expire();
            return handler.next(error);
          }
          try {
            if (!await refresh()) return handler.next(error);
            if (request.extra['noRetry'] == true) return handler.next(error);
            request.extra['retried'] = true;
            handler.resolve(await dio.fetch<dynamic>(request));
          } catch (failure) {
            handler.next(
              failure is DioException && isConnectionFailure(failure)
                  ? failure
                  : error,
            );
          }
        },
      ),
    );
  }

  void configure() {
    dio.options.baseUrl = _origin.toString().replaceFirst(RegExp(r'/$'), '');
  }

  Future<void> _persist(Future<void> Function() operation) {
    final next = _storageQueue
        .catchError((Object _) {})
        .then((_) => operation());
    _storageQueue = next;
    return next;
  }

  Future<void> restore() async {
    configure();
    final token = await _store.read();
    remember = token != null;
    _cacheScope = token == null ? null : _scopeFor(token);
    if (token != null && _store is SessionIdentityStore) {
      _cacheScope =
          await (_store as SessionIdentityStore).readScope() ?? _cacheScope;
    }
    if (token != null)
      await cookies.saveFromResponse(_origin, [
        Cookie('refresh_token', token)..path = '/',
      ]);
  }

  Future<void> login(String email, String password, bool persist) async {
    configure();
    await clear();
    final generation = _generation;
    remember = persist;
    try {
      final response = await dio.post<dynamic>(
        '/auth/login',
        data: {'email': email, 'password': password, 'is_mobile': true},
      );
      if (generation != _generation)
        throw StateError('Session changed. Sign in again.');
      final tokens = response.data as Map;
      if (tokens['access_token'] is! String ||
          tokens['refresh_token'] is! String)
        throw const FormatException('Invalid sign-in response.');
      await cookies.saveFromResponse(_origin, [
        Cookie('access_token', tokens['access_token'] as String)..path = '/',
        Cookie('refresh_token', tokens['refresh_token'] as String)..path = '/',
      ]);
      _cacheScope = _scopeFor(tokens['refresh_token'] as String);
      if (remember)
        await _persist(() => _store.write(tokens['refresh_token'] as String));
    } catch (_) {
      if (generation == _generation) await clear();
      rethrow;
    }
  }

  Future<bool> refresh() {
    if (_refreshing != null) return _refreshing!;
    late Future<bool> attempt;
    attempt = _refresh().whenComplete(() {
      if (identical(_refreshing, attempt)) _refreshing = null;
    });
    return _refreshing = attempt;
  }

  Future<bool> _refresh() async {
    final generation = _generation;
    try {
      await dio.post<dynamic>('/auth/refresh');
      return generation == _generation;
    } on DioException catch (e) {
      if (generation != _generation) return false;
      if (e.response?.statusCode == 401) {
        await _expire();
        return false;
      }
      rethrow;
    }
  }

  Future<void> _expire() async {
    if (_cacheScope != null) {
      try {
        await onSessionQuarantined?.call(_cacheScope!);
      } catch (_) {
        debugPrint(
          'Saved work could not be marked; credentials will still be cleared.',
        );
      }
    }
    await _clear(cancelRequests: false);
    onSessionLost?.call();
  }

  Future<void> validate() async {
    final generation = _generation;
    Response<dynamic> response;
    try {
      response = await dio.get<dynamic>('/auth/me');
    } on DioException catch (e) {
      if (e.response?.statusCode != 401) rethrow;
      if (!await refresh())
        throw StateError('Your session expired. Sign in again.');
      try {
        response = await dio.get<dynamic>('/auth/me');
      } on DioException catch (e) {
        if (e.response?.statusCode == 401) await _expire();
        rethrow;
      }
    }
    if (generation != _generation) throw StateError('Session changed.');
    if ((response.data as Map)['role'] != 'driver') {
      await logout();
      throw StateError('Sign in with a driver account.');
    }
    final id = (response.data as Map)['id'];
    if (id != null && _store is SessionIdentityStore) {
      final scope = sha256
          .convert(utf8.encode('${_origin.toString()}|driver:$id'))
          .toString();
      _cacheScope = scope;
      if (remember)
        await _persist(() async {
          if (generation == _generation && remember)
            await (_store as SessionIdentityStore).writeScope(scope);
        });
    }
  }

  Future<String> socketCookie() async {
    await validate();
    return (await cookies.loadForRequest(_origin))
        .where((c) => c.name == 'access_token')
        .map((c) => '${c.name}=${c.value}')
        .join('; ');
  }

  Future<bool> logout() async {
    var revoked = false;
    try {
      await dio.post<dynamic>('/auth/logout');
      revoked = true;
    } catch (_) {
      /* Always clear local credentials. */
    }
    await clear();
    return revoked;
  }

  void cancelPendingRequests() {
    _generation++;
    _sessionCancel.cancel('Session operation canceled.');
    _sessionCancel = CancelToken();
  }

  Future<void> clear() => _clear(cancelRequests: true);
  Future<void> _clear({required bool cancelRequests}) async {
    final previousScope = _cacheScope;
    _cacheScope = null;
    _generation++;
    if (cancelRequests) _sessionCancel.cancel('Session ended.');
    _sessionCancel = CancelToken();
    _refreshing = null;
    remember = false;
    await cookies.deleteAll();
    await _persist(_store.clear);
    if (previousScope != null) {
      try {
        await onCacheInvalidated?.call(previousScope);
      } catch (_) {
        debugPrint(
          'Offline cache cleanup failed; the session has been cleared.',
        );
      }
    }
  }
}

String apiError(Object error) {
  if (error is DioException) {
    if (error.error is OfflineActionBlocked)
      return error.error.toString().replaceFirst('Bad state: ', '');
    final data = error.response?.data;
    if (data is Map) {
      if (data['message'] is String) return data['message'] as String;
      if (data['errors'] is Map)
        return (data['errors'] as Map).values.join('\n');
    }
    return 'Unable to confirm the operation. Check your connection and refresh before retrying.';
  }
  return error.toString().replaceFirst('Bad state: ', '');
}
