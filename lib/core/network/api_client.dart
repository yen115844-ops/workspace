import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import '../storage/auth_storage.dart';
import '../utils/app_logger.dart';

/// Stream controller for auth events (e.g., forced logout on token expiry)
final authEventController = StreamController<AuthEvent>.broadcast();

enum AuthEvent { tokenExpired, forceLogout }

/// Custom API Exception that extracts meaningful error messages
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic originalError;

  ApiException({
    required this.message,
    this.statusCode,
    this.originalError,
  });

  @override
  String toString() => message;

  /// Common error message translations from English to Vietnamese
  static final Map<String, String> _errorTranslations = {
    'Invalid email or password': 'Email hoặc mật khẩu không đúng',
    'Invalid credentials': 'Thông tin đăng nhập không đúng',
    'User not found': 'Không tìm thấy người dùng',
    'Email already exists': 'Email đã được sử dụng',
    'Unauthorized': 'Phiên đăng nhập hết hạn',
    'Forbidden': 'Bạn không có quyền truy cập',
    'Internal server error': 'Lỗi máy chủ',
    'Bad Request': 'Yêu cầu không hợp lệ',
    'Token expired': 'Phiên đăng nhập đã hết hạn',
    'Invalid token': 'Token không hợp lệ',
    'Password must be at least 6 characters': 'Mật khẩu phải có ít nhất 6 ký tự',
    'Email is required': 'Vui lòng nhập email',
    'Password is required': 'Vui lòng nhập mật khẩu',
    'Name is required': 'Vui lòng nhập tên',
    'Invalid email format': 'Email không đúng định dạng',
    'Refresh token revoked or expired': 'Phiên đăng nhập đã hết hạn',
    'Refresh token expired or invalid': 'Phiên đăng nhập đã hết hạn',
    'Not Found': 'Không tìm thấy tài nguyên',
    'Conflict': 'Dữ liệu đã tồn tại',
    'File too large': 'File quá lớn (tối đa 10MB)',
    'Payload too large': 'File quá lớn (tối đa 10MB)',
    'File size too large': 'File quá lớn (tối đa 10MB)',
    'Limit file size': 'File quá lớn (tối đa 10MB)',
    'Huddle (LiveKit) not configured': 'Voice room chưa được cấu hình. Vui lòng cấu hình LiveKit trên server.',
    // Channel/Workspace member management
    'Admin only': 'Chỉ quản trị viên mới có quyền thực hiện',
    'Not a member of this workspace': 'Bạn không phải thành viên của workspace này',
    'Not a member of this channel': 'Bạn không phải thành viên của channel này',
    'Cannot remove yourself': 'Không thể xoá chính bạn',
    'Cannot remove yourself. Use leave channel instead.': 'Không thể xoá chính bạn. Hãy rời channel thay vì xoá.',
    'Cannot remove the owner': 'Không thể xoá chủ sở hữu',
    'Member not found': 'Không tìm thấy thành viên',
    'Member not found in this channel': 'Thành viên không có trong channel này',
    'Already a member': 'Đã là thành viên',
    'Channel not found': 'Không tìm thấy channel',
  };

  /// Translate common English error messages to Vietnamese
  static String _translateMessage(String message) {
    // Check exact match first
    if (_errorTranslations.containsKey(message)) {
      return _errorTranslations[message]!;
    }
    // Check partial match (case insensitive)
    for (final entry in _errorTranslations.entries) {
      if (message.toLowerCase().contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }
    return message;
  }

  /// Parse error message from DioException response
  static ApiException fromDioException(DioException error) {
    String message = 'Đã xảy ra lỗi';
    final statusCode = error.response?.statusCode;

    // Try to extract error message from response body
    final responseData = error.response?.data;
    if (responseData != null) {
      if (responseData is Map<String, dynamic>) {
        // Try different common error message fields - handle both String and Map types
        String? rawMessage;

        // NestJS exception filter: { success: false, error: { code, message } }
        final errorObj = responseData['error'];
        if (errorObj is Map && errorObj['message'] != null) {
          rawMessage = errorObj['message'] is String
              ? errorObj['message'] as String
              : errorObj['message'].toString();
        }

        rawMessage ??= responseData['message'] is String
            ? responseData['message'] as String
            : null;
        if (rawMessage == null && responseData['message'] is Map) {
          rawMessage = (responseData['message'] as Map)['message']?.toString();
        }

        rawMessage ??= responseData['error'] is String
            ? responseData['error'] as String
            : null;

        rawMessage ??= responseData['errors'] is List
            ? (responseData['errors'] as List)
                .map((e) => e is Map ? (e['message'] ?? e.toString()) : e.toString())
                .join(', ')
            : null;

        rawMessage ??= responseData['msg'] is String ? responseData['msg'] as String : null;

        if (rawMessage != null && rawMessage.isNotEmpty) {
          message = _translateMessage(rawMessage);
        }
      } else if (responseData is String && responseData.isNotEmpty) {
        message = _translateMessage(responseData);
      }
    }

    // Fallback to status code based messages
    if (message == 'Đã xảy ra lỗi') {
      switch (statusCode) {
        case 400:
          message = 'Yêu cầu không hợp lệ';
          break;
        case 401:
          message = 'Email hoặc mật khẩu không đúng';
          break;
        case 403:
          message = 'Bạn không có quyền truy cập';
          break;
        case 404:
          message = 'Không tìm thấy tài nguyên';
          break;
        case 413:
          message = 'File quá lớn (tối đa 10MB)';
          break;
        case 409:
          message = 'Dữ liệu đã tồn tại';
          break;
        case 422:
          message = 'Dữ liệu không hợp lệ';
          break;
        case 429:
          message = 'Quá nhiều yêu cầu, vui lòng thử lại sau';
          break;
        case 500:
        case 502:
        case 503:
          message = 'Lỗi máy chủ, vui lòng thử lại sau';
          break;
        default:
          if (error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.receiveTimeout ||
              error.type == DioExceptionType.sendTimeout) {
            message = 'Kết nối timeout, vui lòng kiểm tra mạng';
          } else if (error.type == DioExceptionType.connectionError) {
            message = 'Không thể kết nối đến máy chủ';
          }
      }
    }

    return ApiException(
      message: message,
      statusCode: statusCode,
      originalError: error,
    );
  }
}

class ApiClient {
  late final Dio _dio;
  final AuthStorage _authStorage = AuthStorage();
  
  /// Cache current user ID for quick access
  static String? _currentUserId;
  static String? get currentUserId => _currentUserId;
  static set currentUserId(String? value) => _currentUserId = value;

  ApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl: '$apiBaseUrl$kApiPrefix',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
    ));
    if (kDebugMode) _dio.interceptors.add(_LogInterceptor());
    _dio.interceptors.add(_AuthInterceptor(_authStorage, _dio));
    _dio.interceptors.add(_ErrorInterceptor());
  }

  Dio get dio => _dio;

  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? queryParameters, Options? options}) {
    return _dio.get<T>(path, queryParameters: queryParameters, options: options);
  }

  Future<Response<T>> post<T>(String path, {dynamic data, Options? options}) {
    return _dio.post<T>(path, data: data, options: options);
  }

  Future<Response<T>> patch<T>(String path, {dynamic data, Options? options}) {
    return _dio.patch<T>(path, data: data, options: options);
  }

  Future<Response<T>> delete<T>(String path, {Options? options}) {
    return _dio.delete<T>(path, options: options);
  }
}

class _LogInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    log.api(options.method, options.uri.toString(), body: options.data);
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    log.api(response.requestOptions.method, response.requestOptions.uri.toString(),
        statusCode: response.statusCode, response: response.data);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    log.api(err.requestOptions.method, err.requestOptions.uri.toString(),
        statusCode: err.response?.statusCode, response: err.response?.data);
    log.e('API Error', err.message, err.stackTrace);
    handler.next(err);
  }
}

/// Error interceptor that converts DioException to ApiException
class _ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Skip conversion for 401 errors that will be handled by AuthInterceptor
    if (err.response?.statusCode == 401 && err.requestOptions.extra['skipAuthRetry'] != true) {
      handler.next(err);
      return;
    }
    
    final apiException = ApiException.fromDioException(err);
    handler.reject(
      DioException(
        requestOptions: err.requestOptions,
        response: err.response,
        type: err.type,
        error: apiException,
        message: apiException.message,
      ),
    );
  }
}

class _AuthInterceptor extends QueuedInterceptor {
  final AuthStorage _authStorage;
  final Dio _dio;

  _AuthInterceptor(this._authStorage, this._dio);

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final skipAuth = options.extra['skipAuth'] == true;
    if (!skipAuth) {
      final token = await _authStorage.getAccessToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  /// Chỉ force logout khi refresh token thực sự không hợp lệ (401/403 từ server).
  /// Khi refresh thất bại do mạng/timeout (app nền, cuộc gọi), không xóa token để tránh logout nhầm.
  static bool _isRefreshTokenInvalid(dynamic e) {
    if (e is! DioException) return false;
    final code = e.response?.statusCode;
    return code == 401 || code == 403;
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401 && err.requestOptions.extra['skipAuthRetry'] != true) {
      final refreshToken = await _authStorage.getRefreshToken();
      if (refreshToken != null && refreshToken.isNotEmpty) {
        bool shouldClearAndLogout = false;
        Future<Map<String, dynamic>?> tryRefresh() async {
          final dioRefresh = Dio(BaseOptions(
            baseUrl: '$apiBaseUrl$kApiPrefix',
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 10),
          ));
          final res = await dioRefresh.post<Map<String, dynamic>>(
            '/auth/refresh',
            data: {'refreshToken': refreshToken},
          );
          final raw = res.data;
          final payload = raw != null && raw['data'] != null
              ? (raw['data'] as Map<String, dynamic>)
              : raw;
          return payload;
        }

        for (int attempt = 0; attempt < 2; attempt++) {
          try {
            final payload = await tryRefresh();
            final accessToken = payload?['access_token'] as String?;
            if (accessToken != null && accessToken.isNotEmpty) {
              await _authStorage.saveTokens(
                accessToken: accessToken,
                refreshToken: (payload!['refresh_token'] as String?) ?? refreshToken,
              );
              err.requestOptions.headers['Authorization'] = 'Bearer $accessToken';
              err.requestOptions.extra['skipAuthRetry'] = true;
              final response = await _dio.fetch(err.requestOptions);
              return handler.resolve(response);
            }
            shouldClearAndLogout = true; // 200 nhưng không có access_token
            break;
          } catch (e) {
            if (_isRefreshTokenInvalid(e)) {
              log.w('[Auth] Refresh token rejected by server, forcing logout');
              shouldClearAndLogout = true;
              break;
            }
            if (attempt == 0) {
              log.w('[Auth] Refresh failed (network/timeout), retrying once...');
            } else {
              log.w('[Auth] Refresh failed (network/timeout), keeping session');
            }
          }
        }
        if (shouldClearAndLogout) {
          await _authStorage.clear();
          authEventController.add(AuthEvent.forceLogout);
        }
      }

      // Mark as handled and convert to ApiException
      err.requestOptions.extra['skipAuthRetry'] = true;
      final apiException = ApiException.fromDioException(err);
      return handler.reject(
        DioException(
          requestOptions: err.requestOptions,
          response: err.response,
          type: err.type,
          error: apiException,
          message: apiException.message,
        ),
      );
    }
    handler.next(err);
  }
}
