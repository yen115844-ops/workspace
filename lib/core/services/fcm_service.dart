import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../network/api_client.dart';
import '../storage/auth_storage.dart';
import '../utils/app_logger.dart';
import 'call_kit_service.dart';
import 'local_notifications_service.dart';

/// Background message handler — must be top-level function (not class method).
/// @pragma('vm:entry-point') bắt buộc để Flutter biết function này có thể được gọi từ native code
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kDebugMode) {
    log.d('[FCM] Background: ${message.messageId}');
  }
  
  // Kiểm tra nếu là cuộc gọi huddle thì hiển thị call UI
  final data = message.data;
  if (data['type'] == 'huddle_call') {
    final channelId = data['channelId'] as String? ?? '';
    final channelName = data['channelName'] as String? ?? 'Voice Room';
    final callerId = data['callerId'] as String? ?? '';
    final callerName = data['callerName'] as String? ?? 'Ai đó';
    final callerAvatar = data['callerAvatar'] as String?;
    final workspaceId = data['workspaceId'] as String?;
    
    await callKitService.showIncomingCall(
      channelId: channelId,
      channelName: channelName,
      callerId: callerId,
      callerName: callerName,
      callerAvatar: callerAvatar,
      workspaceId: workspaceId,
    );
  }
}

/// FCM: request permission, get token, register with backend, handle messages.
class FcmService {
  static final FcmService _instance = FcmService._();
  factory FcmService() => _instance;

  FcmService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final ApiClient _api = ApiClient();
  final AuthStorage _authStorage = AuthStorage();

  static final StreamController<Map<String, String>> _notificationTapController =
      StreamController<Map<String, String>>.broadcast();

  /// Stream phát khi user nhấn vào thông báo (FCM hoặc local). App subscribe và điều hướng.
  static Stream<Map<String, String>> get notificationTapStream =>
      _notificationTapController.stream;

  /// Dữ liệu thông báo chờ (khi mở app từ notification trước khi có listener).
  static Map<String, String>? _pendingNotificationData;

  static Map<String, String>? get pendingNotificationData => _pendingNotificationData;

  /// Lấy và xóa pending (gọi sau khi subscribe stream để xử lý getInitialMessage).
  static Map<String, String>? takePendingNotificationData() {
    final p = _pendingNotificationData;
    _pendingNotificationData = null;
    return p;
  }

  bool _initialized = false;

  /// Call once after Firebase.initializeApp().
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // iOS: request permission (Android 13+ handled by plugin)
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    if (kDebugMode) {
      log.d('[FCM] Permission: ${settings.authorizationStatus}');
    }

    // Foreground messages
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

    // Token refresh
    _messaging.onTokenRefresh.listen(_sendTokenToBackend);

    // Initial message (app opened from terminated state via notification)
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _emitNotificationTap(_messageDataToMap(initialMessage.data));
    }

    // Get and register token if user is logged in
    await _registerTokenIfLoggedIn();
  }

  /// Register FCM token with backend when user is logged in. Call after login or on app start.
  Future<void> registerTokenIfLoggedIn() => _registerTokenIfLoggedIn();

  Future<void> _registerTokenIfLoggedIn() async {
    final accessToken = await _authStorage.getAccessToken();
    if (accessToken == null || accessToken.isEmpty) return;

    try {
      final fcmToken = await _messaging.getToken();
      if (fcmToken != null && fcmToken.isNotEmpty) {
        await _sendTokenToBackend(fcmToken);
      }
    } on FirebaseException catch (e) {
      // iOS: APNS token chưa có khi app vừa mở — retry sau vài giây hoặc chờ onTokenRefresh
      if (e.code == 'apns-token-not-set' && Platform.isIOS) {
        if (kDebugMode) log.d('[FCM] APNS chưa sẵn sàng, thử lại sau 3s...');
        Future.delayed(const Duration(seconds: 3), _registerTokenIfLoggedIn);
      } else {
        if (kDebugMode) log.e('[FCM] getToken failed', e);
      }
    } catch (e) {
      if (kDebugMode) log.e('[FCM] getToken failed', e);
    }
  }

  Future<void> _sendTokenToBackend(String token) async {
    try {
      await _api.post<void>(
        '/notifications/fcm-token',
        data: {'token': token},
      );
      if (kDebugMode) log.d('[FCM] Token registered');
    } catch (e) {
      if (kDebugMode) log.e('[FCM] Register token failed', e);
    }
  }

  /// Remove FCM token from backend on logout. Optional: call from auth cubit on logout.
  Future<void> removeToken() async {
    try {
      await _api.delete('/notifications/fcm-token');
      if (kDebugMode) log.d('[FCM] Token removed');
    } catch (e) {
      if (kDebugMode) log.e('[FCM] Remove token failed', e);
    }
  }

  void _onForegroundMessage(RemoteMessage message) {
    if (kDebugMode) {
      log.d('[FCM] Foreground: ${message.notification?.title}');
    }
    
    // Kiểm tra nếu là cuộc gọi huddle thì hiển thị call UI
    final data = message.data;
    if (data['type'] == 'huddle_call') {
      _showIncomingCallUI(data);
      return;
    }
    
    showNotificationFromFcm(message);
  }

  /// Hiển thị incoming call UI khi nhận được notification cuộc gọi
  void _showIncomingCallUI(Map<String, dynamic> data) {
    final channelId = data['channelId'] as String? ?? '';
    final channelName = data['channelName'] as String? ?? 'Voice Room';
    final callerId = data['callerId'] as String? ?? '';
    final callerName = data['callerName'] as String? ?? 'Ai đó';
    final callerAvatar = data['callerAvatar'] as String?;
    final workspaceId = data['workspaceId'] as String?;
    
    callKitService.showIncomingCall(
      channelId: channelId,
      channelName: channelName,
      callerId: callerId,
      callerName: callerName,
      callerAvatar: callerAvatar,
      workspaceId: workspaceId,
    );
  }

  void _onMessageOpenedApp(RemoteMessage message) {
    _emitNotificationTap(_messageDataToMap(message.data));
  }

  static Map<String, String> _messageDataToMap(Map<String, dynamic> data) {
    final map = <String, String>{};
    for (final e in data.entries) {
      if (e.value != null) map[e.key] = e.value.toString();
    }
    return map;
  }

  /// Gửi data ra stream hoặc lưu pending nếu chưa có listener.
  void _emitNotificationTap(Map<String, String> data) {
    if (data.isEmpty) return;
    if (kDebugMode) log.d('[FCM] Notification tap: $data');
    if (_notificationTapController.hasListener) {
      _notificationTapController.add(data);
    } else {
      _pendingNotificationData = data;
    }
  }

  /// Gọi khi user nhấn local notification (payload là JSON string từ message.data).
  static void handleLocalNotificationTap(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final map = jsonDecode(payload) as Map<String, dynamic>?;
      if (map == null) return;
      final data = <String, String>{};
      for (final e in map.entries) {
        if (e.value != null) data[e.key] = e.value.toString();
      }
      if (data.isEmpty) return;
      if (_notificationTapController.hasListener) {
        _notificationTapController.add(data);
      } else {
        _pendingNotificationData = data;
      }
    } catch (_) {}
  }

  /// Đăng ký VoIP token lên server (chỉ iOS)
  /// Gọi khi lấy được VoIP token từ PushKit
  Future<void> registerVoipToken(String token) async {
    if (token.isEmpty) return;
    try {
      await _api.post<void>(
        '/notifications/voip-token',
        data: {'token': token},
      );
      if (kDebugMode) log.d('[FCM] VoIP token registered');
    } catch (e) {
      if (kDebugMode) log.e('[FCM] Register VoIP token failed', e);
    }
  }

  /// Xóa VoIP token khi logout
  Future<void> removeVoipToken() async {
    try {
      await _api.delete('/notifications/voip-token');
      if (kDebugMode) log.d('[FCM] VoIP token removed');
    } catch (e) {
      if (kDebugMode) log.e('[FCM] Remove VoIP token failed', e);
    }
  }
}
