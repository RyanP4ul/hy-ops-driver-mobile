import 'package:dio/dio.dart';

/// HTTP errors, invalid credentials, cancellation and server errors are not
/// evidence of an offline device and must never reveal a cached response.
bool isConnectionFailure(Object error) =>
    error is DioException &&
    error.response == null &&
    [
      DioExceptionType.connectionError,
      DioExceptionType.connectionTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.sendTimeout,
    ].contains(error.type);

class OfflineActionBlocked extends StateError {
  OfflineActionBlocked()
    : super(
        'You are offline. Reconnect and refresh before taking this action.',
      );
}

class OfflineCacheMiss extends StateError {
  OfflineCacheMiss()
    : super('No saved data for this view. Connect to the internet to load it.');
}
