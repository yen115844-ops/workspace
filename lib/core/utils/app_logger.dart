import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// Logger chỉ in khi kDebugMode (dev). Production không log ra console.
final AppLogger log = AppLogger();

class AppLogger {
  late final Logger _logger;

  AppLogger() {
    _logger = Logger(
      level: kDebugMode ? Level.debug : Level.nothing,
      printer: PrettyPrinter(
        methodCount: 0,
        errorMethodCount: 4,
        lineLength: 80,
        colors: true,
        printEmojis: true,
      ),
    );
  }

  void d(String message, [dynamic error, StackTrace? stackTrace]) {
    if (kDebugMode) _logger.d(message, error: error, stackTrace: stackTrace);
  }

  void i(String message, [dynamic error, StackTrace? stackTrace]) {
    if (kDebugMode) _logger.i(message, error: error, stackTrace: stackTrace);
  }

  void w(String message, [dynamic error, StackTrace? stackTrace]) {
    if (kDebugMode) _logger.w(message, error: error, stackTrace: stackTrace);
  }

  void e(String message, [dynamic error, StackTrace? stackTrace]) {
    if (kDebugMode) _logger.e(message, error: error, stackTrace: stackTrace);
  }

  void api(String method, String path, {int? statusCode, dynamic body, dynamic response}) {
    if (!kDebugMode) return;
    _logger.d('[API] $method $path ${statusCode != null ? "→ $statusCode" : ""}');
    if (body != null) _logger.d('[API] body: $body');
    if (response != null) _logger.d('[API] response: $response');
  }

  void nav(String from, String to) {
    if (kDebugMode) _logger.d('[NAV] $from → $to');
  }

  void auth(String event, [dynamic extra]) {
    if (kDebugMode) _logger.d('[AUTH] $event ${extra != null ? extra : ""}');
  }
}
