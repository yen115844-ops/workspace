/// ============================================================================
/// CALL KIT SERVICE - Hiển thị UI cuộc gọi đến như phone
/// ============================================================================
/// 
/// Sử dụng flutter_callkit_incoming để hiển thị native call UI
/// Hỗ trợ cả iOS (CallKit) và Android (Custom Notification)
/// ============================================================================

import 'dart:io';

import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:uuid/uuid.dart';

import '../utils/app_logger.dart';
import 'fcm_service.dart';

/// Service xử lý incoming call UI (giống như cuộc gọi điện thoại)
/// Sử dụng flutter_callkit_incoming để hiển thị native call UI
class CallKitService {
  static final CallKitService _instance = CallKitService._();
  factory CallKitService() => _instance;
  CallKitService._();

  final _uuid = const Uuid();
  String? _currentCallId;
  /// Channel đang trong cuộc gọi (để tránh hiển thị incoming call trùng khi B gọi lại trong lúc A đã trong room)
  String? _activeChannelId;
  bool _initialized = false;

  // Callback khi user accept cuộc gọi
  void Function(String channelId, String channelName, String? workspaceId)? _callAcceptedCallback;
  void Function(String callId)? _callDeclinedCallback;
  void Function(String callId)? _callEndedCallback;
  void Function(String callId)? _callTimeoutCallback;

  /// Khởi tạo và lắng nghe các events
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    
    // Request notification permission cho Android 13+
    await FlutterCallkitIncoming.requestNotificationPermission({
      "title": "Quyền thông báo",
      "rationaleMessagePermission": "Cần quyền thông báo để hiển thị cuộc gọi đến.",
      "postNotificationMessageRequired": "Vui lòng bật quyền thông báo trong cài đặt.",
    });

    // iOS: Đăng ký VoIP token lên server khi có
    if (Platform.isIOS) {
      _registerVoIPTokenListener();
    }

    // Lắng nghe các events từ call UI
    FlutterCallkitIncoming.onEvent.listen((CallEvent? event) {
      if (event == null) return;
      
      switch (event.event) {
        case Event.actionCallIncoming:
          log.d('[CallKit] 📞 Incoming call received');
          break;
          
        case Event.actionCallStart:
          log.d('[CallKit] 📞 Call started');
          break;
          
        case Event.actionCallAccept:
          _handleCallAccepted(event);
          break;
          
        case Event.actionCallDecline:
          _handleCallDeclined(event);
          break;
          
        case Event.actionCallEnded:
          _handleCallEnded(event);
          break;
          
        case Event.actionCallTimeout:
          _handleCallTimeout(event);
          break;
          
        case Event.actionCallCallback:
          // User nhấn "Gọi lại" từ missed call notification
          log.d('[CallKit] 📞 Callback from missed call');
          _handleCallCallback(event);
          break;
          
        case Event.actionCallToggleHold:
          log.d('[CallKit] 📞 Call hold toggled (iOS only)');
          break;
          
        case Event.actionCallToggleMute:
          log.d('[CallKit] 📞 Call mute toggled (iOS only)');
          break;
          
        case Event.actionCallToggleDmtf:
          log.d('[CallKit] 📞 DTMF toggled (iOS only)');
          break;
          
        case Event.actionCallToggleGroup:
          log.d('[CallKit] 📞 Call group toggled (iOS only)');
          break;
          
        case Event.actionCallToggleAudioSession:
          log.d('[CallKit] 📞 Audio session toggled (iOS only)');
          break;
          
        case Event.actionDidUpdateDevicePushTokenVoip:
          log.d('[CallKit] 📞 VoIP token updated (iOS only)');
          break;
          
        case Event.actionCallCustom:
          log.d('[CallKit] 📞 Custom action');
          break;
          
        case Event.actionCallConnected:
          log.d('[CallKit] 📞 Call connected');
          break;
      }
    });
    
    log.d('[CallKit] ✅ Initialized successfully');
  }

  /// Xử lý khi user accept cuộc gọi
  void _handleCallAccepted(CallEvent event) {
    final callId = event.body['id'] as String?;
    final extra = Map<String, dynamic>.from(event.body['extra'] ?? {});
    
    log.d('[CallKit] ✅ Call accepted: $callId');
    log.d('[CallKit] Extra data: $extra');
    
    if (callId != null) {
      final channelId = extra['channelId'] as String? ?? '';
      final channelName = extra['channelName'] as String? ?? '';
      final workspaceId = extra['workspaceId'] as String?;
      
      _callAcceptedCallback?.call(channelId, channelName, workspaceId);
    }
  }

  /// Xử lý khi user decline cuộc gọi
  void _handleCallDeclined(CallEvent event) {
    final callId = event.body['id'] as String?;
    log.d('[CallKit] ❌ Call declined: $callId');
    
    if (callId != null) {
      _callDeclinedCallback?.call(callId);
    }
    _currentCallId = null;
  }

  /// Xử lý khi cuộc gọi kết thúc
  void _handleCallEnded(CallEvent event) {
    final callId = event.body['id'] as String?;
    log.d('[CallKit] 📴 Call ended: $callId');
    
    if (callId != null) {
      _callEndedCallback?.call(callId);
    }
    _currentCallId = null;
  }

  /// Xử lý khi cuộc gọi timeout (không trả lời)
  void _handleCallTimeout(CallEvent event) {
    final callId = event.body['id'] as String?;
    log.d('[CallKit] ⏰ Call timeout: $callId');
    
    if (callId != null) {
      _callTimeoutCallback?.call(callId);
    }
    _currentCallId = null;
  }

  /// Xử lý khi user nhấn "Gọi lại" từ missed call notification
  void _handleCallCallback(CallEvent event) {
    final extra = Map<String, dynamic>.from(event.body['extra'] ?? {});
    final channelId = extra['channelId'] as String? ?? '';
    final channelName = extra['channelName'] as String? ?? '';
    final workspaceId = extra['workspaceId'] as String?;
    
    _callAcceptedCallback?.call(channelId, channelName, workspaceId);
  }

  /// Đặt channel đang trong cuộc gọi (gọi từ HuddleScreen khi join room).
  void setActiveCallChannel(String? channelId) {
    _activeChannelId = channelId?.isEmpty == true ? null : channelId;
    log.d('[CallKit] Active call channel: $_activeChannelId');
  }

  /// Xóa channel đang gọi (gọi từ HuddleScreen khi leave room).
  void clearActiveCallChannel() {
    _activeChannelId = null;
  }

  /// Hiển thị incoming call UI khi nhận được FCM notification.
  /// Không hiển thị nếu đang trong cuộc gọi cùng channel (tránh B gọi lại → A bị ring lại).
  Future<void> showIncomingCall({
    required String channelId,
    required String channelName,
    required String callerId,
    required String callerName,
    String? callerAvatar,
    String? workspaceId,
    bool isVideo = false,
  }) async {
    if (channelId.isNotEmpty &&
        _activeChannelId != null &&
        _activeChannelId == channelId) {
      log.d('[CallKit] Ignore incoming call: already in call for channel $channelId');
      return;
    }

    _currentCallId = _uuid.v4();
    log.d('[CallKit] 📞 Showing incoming call from $callerName');
    log.d('[CallKit] Channel: $channelName, ID: $channelId');
    
    final params = CallKitParams(
      id: _currentCallId!,
      nameCaller: callerName,
      appName: 'HanCity',
      avatar: callerAvatar,
      handle: channelName,
      type: isVideo ? 1 : 0, // 0: Audio, 1: Video
      textAccept: 'Tham gia',
      textDecline: 'Từ chối',
      duration: 45000, // 45 giây timeout
      extra: <String, dynamic>{
        'channelId': channelId,
        'channelName': channelName,
        'callerId': callerId,
        'callerName': callerName,
        'workspaceId': workspaceId ?? '',
      },
      headers: <String, dynamic>{},
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: true,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#6366F1', // Indigo - màu chủ đạo của app
        actionColor: '#4CAF50',
        textColor: '#ffffff',
        incomingCallNotificationChannelName: 'Cuộc gọi đến',
        missedCallNotificationChannelName: 'Cuộc gọi nhỡ',
        isShowCallID: false,
      ),
      ios: const IOSParams(
        iconName: 'AppIcon',
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 2,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'voiceChat',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: true,
        supportsHolding: true,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: true,
        subtitle: 'Cuộc gọi nhỡ',
        callbackText: 'Gọi lại',
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
    log.d('[CallKit] ✅ Incoming call UI displayed');
  }

  /// Set trạng thái call đã connected (bắt đầu tính giờ)
  Future<void> setCallConnected([String? callId]) async {
    final id = callId ?? _currentCallId;
    if (id != null) {
      await FlutterCallkitIncoming.setCallConnected(id);
      log.d('[CallKit] 📞 Call connected: $id');
    }
  }

  /// Kết thúc cuộc gọi hiện tại
  Future<void> endCall([String? callId]) async {
    final id = callId ?? _currentCallId;
    if (id != null) {
      await FlutterCallkitIncoming.endCall(id);
      log.d('[CallKit] 📴 Call ended: $id');
      if (id == _currentCallId) {
        _currentCallId = null;
      }
    }
    _activeChannelId = null;
  }

  /// Kết thúc tất cả cuộc gọi
  Future<void> endAllCalls() async {
    await FlutterCallkitIncoming.endAllCalls();
    _currentCallId = null;
    _activeChannelId = null;
    log.d('[CallKit] 📴 All calls ended');
  }

  /// Ẩn incoming call notification (Android only)
  Future<void> hideIncomingCall([String? callId]) async {
    final id = callId ?? _currentCallId;
    if (id != null) {
      await FlutterCallkitIncoming.hideCallkitIncoming(
        CallKitParams(id: id),
      );
      log.d('[CallKit] 🔕 Incoming call hidden: $id');
    }
  }

  /// Lấy danh sách cuộc gọi đang active
  Future<List<dynamic>> getActiveCalls() async {
    final calls = await FlutterCallkitIncoming.activeCalls();
    log.d('[CallKit] Active calls: ${calls.length}');
    return calls;
  }

  /// Đăng ký callback khi user accept cuộc gọi
  void setOnCallAccepted(void Function(String channelId, String channelName, String? workspaceId) callback) {
    _callAcceptedCallback = callback;
  }

  /// Đăng ký callback khi user decline cuộc gọi
  void setOnCallDeclined(void Function(String callId) callback) {
    _callDeclinedCallback = callback;
  }

  /// Đăng ký callback khi cuộc gọi kết thúc
  void setOnCallEnded(void Function(String callId) callback) {
    _callEndedCallback = callback;
  }

  /// Đăng ký callback khi cuộc gọi timeout
  void setOnCallTimeout(void Function(String callId) callback) {
    _callTimeoutCallback = callback;
  }

  /// iOS: Lắng nghe VoIP token từ PushKit và đăng ký lên server
  void _registerVoIPTokenListener() {
    FlutterCallkitIncoming.onEvent.listen((CallEvent? event) {
      if (event == null) return;
      
      if (event.event == Event.actionDidUpdateDevicePushTokenVoip) {
        final token = event.body['deviceTokenVoIP'] as String?;
        if (token != null && token.isNotEmpty) {
          log.d('[CallKit] 📱 VoIP token received: ${token.substring(0, 20)}...');
          // Đăng ký token lên server
          FcmService().registerVoipToken(token);
        }
      }
    });
    
    // Lấy token hiện tại (nếu đã có)
    _getAndRegisterVoIPToken();
  }

  /// Lấy VoIP token hiện tại và đăng ký lên server
  Future<void> _getAndRegisterVoIPToken() async {
    try {
      final token = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
      if (token != null && token.isNotEmpty) {
        log.d('[CallKit] 📱 Existing VoIP token: ${token.substring(0, 20)}...');
        await FcmService().registerVoipToken(token);
      }
    } catch (e) {
      log.e('[CallKit] Failed to get VoIP token', e);
    }
  }

  /// Đăng ký lại VoIP token khi user login
  Future<void> registerVoIPTokenIfNeeded() async {
    if (Platform.isIOS) {
      await _getAndRegisterVoIPToken();
    }
  }
}

/// Singleton instance
final callKitService = CallKitService();
