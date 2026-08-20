import 'dart:math';

import 'package:dio/dio.dart';

import '../auth/auth_service.dart';

/// Builds the Dio instance every client uses to reach the API Gateway (Section 9).
///
/// Two interceptors matter here: one attaches the access token and silently refreshes it on a 401,
/// the other stamps a correlation id so a user-reported problem can be traced through the dozen
/// services behind the Gateway (Section 10).
abstract final class ApiClient {
  static const String correlationIdHeader = 'X-Correlation-Id';

  static Dio create({
    required String baseUrl,
    required AuthService authService,
    Duration timeout = const Duration(seconds: 20),
  }) {
    final Dio dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: timeout,
        receiveTimeout: timeout,
        sendTimeout: timeout,
        contentType: Headers.jsonContentType,
      ),
    );

    dio.interceptors.add(_CorrelationIdInterceptor());
    dio.interceptors.add(_AuthInterceptor(authService, dio));
    return dio;
  }
}

/// Generates a client-side correlation id when one isn't already set.
///
/// The Gateway generates its own if the client sends none, but originating it here means the id
/// also covers the client-side half of a request — so a screenshot of an error in the app can be
/// tied to the exact server-side trace.
class _CorrelationIdInterceptor extends Interceptor {
  static final Random _random = Random();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers.putIfAbsent(ApiClient.correlationIdHeader, _generate);
    handler.next(options);
  }

  static String _generate() {
    // A UUIDv4-shaped id without taking a uuid package dependency for one call site.
    const String hex = '0123456789abcdef';
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < 32; i++) {
      if (i == 8 || i == 12 || i == 16 || i == 20) {
        buffer.write('-');
      }
      buffer.write(hex[_random.nextInt(16)]);
    }
    return buffer.toString();
  }
}

/// Attaches the bearer token, and retries once after a silent refresh when the Gateway says 401.
class _AuthInterceptor extends QueuedInterceptor {
  _AuthInterceptor(this._authService, this._dio);

  final AuthService _authService;
  final Dio _dio;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final AuthSession? session = _authService.session;
    if (session != null) {
      options.headers['Authorization'] = 'Bearer ${session.accessToken}';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final bool isUnauthorised = err.response?.statusCode == 401;
    final bool alreadyRetried = err.requestOptions.extra['delivery.retried'] == true;

    if (!isUnauthorised || alreadyRetried || _authService.session == null) {
      return handler.next(err);
    }

    try {
      final AuthSession refreshed = await _authService.refresh();
      final RequestOptions retry = err.requestOptions
        ..extra['delivery.retried'] = true
        ..headers['Authorization'] = 'Bearer ${refreshed.accessToken}';

      // QueuedInterceptor serialises this, so a screen firing five parallel requests triggers one
      // refresh rather than five competing ones.
      final Response<dynamic> response = await _dio.fetch<dynamic>(retry);
      return handler.resolve(response);
    } catch (_) {
      // Refresh failed - the session is genuinely gone. Surface the original 401 so the app can
      // route the user back to the login screen.
      return handler.next(err);
    }
  }
}
