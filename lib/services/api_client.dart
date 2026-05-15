import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:digi_sanchika/services/token_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiClient {
  ApiClient._internal();

  static final ApiClient instance = ApiClient._internal();

  late final Dio _dio;
  late final Dio _authDio;
  PersistCookieJar? _cookieJar;
  String _baseUrl = 'https://digisanchika.acstechnologies.co.in/api';
  bool _initialized = false;
  Future<bool>? _refreshInFlight;

  Dio get dio => _dio;
  String get baseUrl => _baseUrl;

  Future<void> initialize({String? baseUrl}) async {
    if (_initialized) return;

    final envBaseUrl =
        dotenv.isInitialized
            ? (dotenv.env['BASE_URL'] ?? dotenv.env['API_BASE_URL'] ?? '')
            : '';
    final effectiveBaseUrl =
        (baseUrl != null && baseUrl.trim().isNotEmpty)
            ? baseUrl.trim()
            : envBaseUrl.trim();

    if (effectiveBaseUrl.isNotEmpty) {
      _baseUrl = effectiveBaseUrl;
    }

    final dir = await getApplicationDocumentsDirectory();
    _cookieJar = PersistCookieJar(
      ignoreExpires: false,
      storage: FileStorage('${dir.path}/.cookies/'),
    );

    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 30),
        headers: {
          'Accept': 'application/json',
        },
        // Allow 4xx to be handled by callers (e.g., 429 rate limit)
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    _authDio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 30),
        headers: {
          'Accept': 'application/json',
        },
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    _configureBadCertificateHandling(_dio);
    _configureBadCertificateHandling(_authDio);

    if (_cookieJar != null) {
      _dio.interceptors.add(CookieManager(_cookieJar!));
      _authDio.interceptors.add(CookieManager(_cookieJar!));
    }

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await TokenStorage.getAccessToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onResponse: (response, handler) async {
          // validateStatus allows 4xx as responses instead of errors,
          // so we must handle 401 here rather than in onError.
          if (response.statusCode == 401) {
            final requestOptions = response.requestOptions;
            final alreadyRetried = requestOptions.extra['retried'] == true;
            if (!alreadyRetried) {
              final refreshed = await _tryRefreshTokenLocked();
              if (refreshed) {
                requestOptions.extra['retried'] = true;
                final newToken = await TokenStorage.getAccessToken();
                if (newToken != null && newToken.isNotEmpty) {
                  requestOptions.headers['Authorization'] = 'Bearer $newToken';
                }
                try {
                  final retryResponse = await _dio.fetch(requestOptions);
                  return handler.resolve(retryResponse);
                } catch (_) {}
              }
            }
          }
          handler.next(response);
        },
        onError: (error, handler) async {
          final response = error.response;
          if (response != null && response.statusCode == 401) {
            final requestOptions = error.requestOptions;
            final alreadyRetried =
                requestOptions.extra['retried'] == true;

            if (!alreadyRetried) {
              final refreshed = await _tryRefreshTokenLocked();
              if (refreshed) {
                requestOptions.extra['retried'] = true;
                try {
                  final retryResponse = await _dio.fetch(requestOptions);
                  return handler.resolve(retryResponse);
                } catch (e) {
                  return handler.next(error);
                }
              }
            }
          }
          handler.next(error);
        },
      ),
    );

    _initialized = true;
  }

  void _configureBadCertificateHandling(Dio dio) {
    if (!kDebugMode) return;
    final uri = Uri.tryParse(_baseUrl);
    if (uri == null) return;
    final isIpHost = uri.host.isNotEmpty && RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(uri.host);
    if (uri.scheme != 'https' || !isIpHost) return;

    final adapter = dio.httpClientAdapter;
    if (adapter is IOHttpClientAdapter) {
      adapter.onHttpClientCreate = (client) {
        client.badCertificateCallback = (cert, host, port) => true;
        return client;
      };
    }
  }

  Future<bool> _tryRefreshToken() async {
    try {
      final refreshToken = await TokenStorage.getRefreshToken();
      final data = <String, dynamic>{};
      if (refreshToken != null && refreshToken.isNotEmpty) {
        data['refreshToken'] = refreshToken;
        data['refresh_token'] = refreshToken;
      }

      final response = await _authDio.post('/auth/refresh', data: data);
      if (response.statusCode == 200) {
        final body = response.data;
        if (body is Map<String, dynamic>) {
          final access =
              body['accessToken'] ?? body['access_token'] ?? body['token'];
          final refresh =
              body['refreshToken'] ?? body['refresh_token'] ?? body['refresh'];
          if (access is String && access.isNotEmpty) {
            await TokenStorage.saveAccessToken(access);
          }
          if (refresh is String && refresh.isNotEmpty) {
            await TokenStorage.saveRefreshToken(refresh);
          }
        }
        return true;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Refresh token failed: $e');
      }
    }
    return false;
  }

  Future<bool> _tryRefreshTokenLocked() async {
    // Prevent multiple simultaneous refresh attempts (can break if refresh tokens rotate).
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;

    final future = _tryRefreshToken();
    _refreshInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_refreshInFlight, future)) {
        _refreshInFlight = null;
      }
    }
  }

  Future<void> clearTokens() async {
    await TokenStorage.clearAll();
    if (_cookieJar != null) {
      await _cookieJar!.deleteAll();
    }
  }
}
