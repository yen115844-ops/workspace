import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../constants/app_constants.dart' show apiBaseUrl;
import '../storage/auth_storage.dart';
import '../utils/app_logger.dart';

/// WebSocket service for real-time communication
class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  final AuthStorage _authStorage = AuthStorage();
  io.Socket? _socket;
  bool _isConnected = false;
  String? _currentChannelId;
  String? _currentWorkspaceId;

  // Event controllers
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _typingController = StreamController<Map<String, dynamic>>.broadcast();
  final _userStatusController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _userUpdatedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _notificationController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _channelCreatedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _addedToChannelController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _taskEventController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _taskCommentController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _workspaceDeletedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _channelDeletedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _channelUpdatedController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Streams
  Stream<Map<String, dynamic>> get onMessage => _messageController.stream;
  Stream<Map<String, dynamic>> get onTyping => _typingController.stream;
  Stream<Map<String, dynamic>> get onUserStatus => _userStatusController.stream;
  Stream<Map<String, dynamic>> get onUserUpdated =>
      _userUpdatedController.stream;
  Stream<Map<String, dynamic>> get onNotification =>
      _notificationController.stream;
  Stream<Map<String, dynamic>> get onChannelCreated =>
      _channelCreatedController.stream;
  Stream<Map<String, dynamic>> get onAddedToChannel =>
      _addedToChannelController.stream;
  Stream<Map<String, dynamic>> get onTaskEvent => _taskEventController.stream;
  Stream<Map<String, dynamic>> get onTaskComment =>
      _taskCommentController.stream;
  Stream<bool> get onConnectionChange => _connectionController.stream;
  Stream<Map<String, dynamic>> get onWorkspaceDeleted =>
      _workspaceDeletedController.stream;
  Stream<Map<String, dynamic>> get onChannelDeleted =>
      _channelDeletedController.stream;
  Stream<Map<String, dynamic>> get onChannelUpdated =>
      _channelUpdatedController.stream;

  bool get isConnected => _isConnected;

  Future<void> connect() async {
    if (_isConnected && _socket != null) return;

    final token = await _authStorage.getAccessToken();
    if (token == null) {
      log.w('[WebSocket] No token available');
      return;
    }

    // Remove /api/v1 suffix and add /ws path for WebSocket
    final baseUrl = apiBaseUrl.replaceAll(RegExp(r'/api(/v1)?$'), '');
    final wsUrl = '$baseUrl/ws';
    log.d('[WebSocket] Connecting to $wsUrl');

    _socket = io.io(baseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'path': '/ws',
      'auth': {'token': token},
      'extraHeaders': {'Authorization': 'Bearer $token'},
    });

    _setupListeners();
    _socket!.connect();
  }

  void _setupListeners() {
    _socket!.onConnect((_) {
      log.d('[WebSocket] Connected');
      _isConnected = true;
      _connectionController.add(true);

      if (_currentChannelId != null) joinChannel(_currentChannelId!);
      if (_currentWorkspaceId != null) joinWorkspace(_currentWorkspaceId!);
    });

    _socket!.onDisconnect((_) {
      log.d('[WebSocket] Disconnected');
      _isConnected = false;
      _connectionController.add(false);
    });

    _socket!.onConnectError((error) {
      log.e('[WebSocket] Connection error: $error');
      _isConnected = false;
      _connectionController.add(false);
    });

    _socket!.onError((error) {
      log.e('[WebSocket] Error: $error');
    });

    // Message events
    _socket!.on('new_message', (data) {
      log.d('[WebSocket] New message: $data');
      _messageController.add({'type': 'new', 'data': data});
    });

    _socket!.on('message_updated', (data) {
      log.d('[WebSocket] Message updated: $data');
      _messageController.add({'type': 'updated', 'data': data});
    });

    _socket!.on('message_deleted', (data) {
      log.d('[WebSocket] Message deleted: $data');
      _messageController.add({'type': 'deleted', 'data': data});
    });

    _socket!.on('thread_reply', (data) {
      log.d('[WebSocket] Thread reply: $data');
      _messageController.add({'type': 'thread_reply', 'data': data});
    });

    // Reaction events
    _socket!.on('message_reaction', (data) {
      log.d('[WebSocket] Message reaction: $data');
      _messageController.add({'type': 'reaction', 'data': data});
    });

    // Read receipt events
    _socket!.on('message_read', (data) {
      log.d('[WebSocket] Message read: $data');
      _messageController.add({'type': 'read', 'data': data});
    });

    _socket!.on('channel_read', (data) {
      log.d('[WebSocket] Channel read: $data');
      _messageController.add({'type': 'channel_read', 'data': data});
    });

    // Typing events - Backend uses 'typing:start' and 'typing:stop'
    _socket!.on('typing:start', (data) {
      log.d('[WebSocket] User typing: $data');
      _typingController.add({'type': 'start', 'data': data});
    });

    _socket!.on('typing:stop', (data) {
      log.d('[WebSocket] User stop typing: $data');
      _typingController.add({'type': 'stop', 'data': data});
    });

    // User presence events - Backend uses 'presence' with status field
    _socket!.on('presence', (data) {
      log.d('[WebSocket] Presence update: $data');
      final status = data['status'];
      _userStatusController.add({'type': status, 'data': data});
    });

    // Notification events
    _socket!.on('notification', (data) {
      log.d('[WebSocket] Notification: $data');
      _notificationController.add(data as Map<String, dynamic>);
    });

    // Channel member events
    _socket!.on('member_joined', (data) {
      log.d('[WebSocket] Member joined: $data');
      _notificationController.add({'type': 'member_joined', 'data': data});
    });

    _socket!.on('member_left', (data) {
      log.d('[WebSocket] Member left: $data');
      _notificationController.add({'type': 'member_left', 'data': data});
    });

    // User profile updated (name, avatar, etc.)
    _socket!.on('user:updated', (data) {
      log.d('[WebSocket] User updated: $data');
      _userUpdatedController.add(data as Map<String, dynamic>);
    });

    // Channel created (public -> workspace, private -> creator only)
    _socket!.on('channel_created', (data) {
      log.d('[WebSocket] Channel created: $data');
      final map = data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{};
      _channelCreatedController.add(map);
    });

    // Được thêm vào channel (private)
    _socket!.on('added_to_channel', (data) {
      log.d('[WebSocket] Added to channel: $data');
      final map = data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{};
      _addedToChannelController.add(map);
    });

    // Workspace/Channel deleted events
    _socket!.on('workspace_deleted', (data) {
      log.d('[WebSocket] Workspace deleted: $data');
      final map = data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{};
      _workspaceDeletedController.add(map);
    });

    _socket!.on('channel_deleted', (data) {
      log.d('[WebSocket] Channel deleted: $data');
      final map = data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{};
      _channelDeletedController.add(map);
    });

    _socket!.on('channel_updated', (data) {
      log.d('[WebSocket] Channel updated: $data');
      final map = data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{};
      _channelUpdatedController.add(map);
    });

    // Task events (created, updated, deleted)
    _socket!.on('task_created', (data) => _emitTaskEvent('task_created', data));
    _socket!.on('task_updated', (data) => _emitTaskEvent('task_updated', data));
    _socket!.on('task_deleted', (data) => _emitTaskEvent('task_deleted', data));

    // Task comment events
    _socket!.on('task_comment_added', (data) {
      log.d('[WebSocket] Task comment added: $data');
      final map = data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{};
      _taskCommentController.add({'type': 'added', ...map});
    });
    _socket!.on('task_comment_deleted', (data) {
      log.d('[WebSocket] Task comment deleted: $data');
      final map = data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{};
      _taskCommentController.add({'type': 'deleted', ...map});
    });
  }

  void _emitTaskEvent(String type, dynamic data) {
    log.d('[WebSocket] $type: $data');
    final map = data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
    _taskEventController.add({'type': type, ...map});
  }

  void joinChannel(String channelId) {
    // Luôn lưu để khi onConnect (sau khi connect xong) có thể join lại
    _currentChannelId = channelId;
    if (_socket == null || !_isConnected) return;

    _socket!.emit('channel:join', {'channelId': channelId});
    log.d('[WebSocket] Joined channel: $channelId');
  }

  void leaveChannel(String channelId) {
    if (_socket == null || !_isConnected) return;

    _socket!.emit('channel:leave', {'channelId': channelId});
    if (_currentChannelId == channelId) {
      _currentChannelId = null;
    }
    log.d('[WebSocket] Left channel: $channelId');
  }

  void joinWorkspace(String workspaceId) {
    // Luôn lưu để khi onConnect có thể join lại
    _currentWorkspaceId = workspaceId;
    if (_socket == null || !_isConnected) return;
    _socket!.emit('workspace:join', {'workspaceId': workspaceId});
    log.d('[WebSocket] Joined workspace: $workspaceId');
  }

  void leaveWorkspace(String workspaceId) {
    if (_socket == null || !_isConnected) return;
    _socket!.emit('workspace:leave', {'workspaceId': workspaceId});
    if (_currentWorkspaceId == workspaceId) _currentWorkspaceId = null;
    log.d('[WebSocket] Left workspace: $workspaceId');
  }

  void sendMessage(
    String channelId,
    String content, {
    String? parentId,
    String? replyToId,
  }) {
    if (_socket == null || !_isConnected) return;

    _socket!.emit('send_message', {
      'channelId': channelId,
      'content': content,
      if (parentId != null) 'parentId': parentId,
      if (replyToId != null) 'replyToId': replyToId,
    });
    log.d('[WebSocket] Sent message to channel: $channelId');
  }

  void startTyping(String channelId) {
    if (_socket == null || !_isConnected) return;

    _socket!.emit('typing:start', {'channelId': channelId});
  }

  void stopTyping(String channelId) {
    if (_socket == null || !_isConnected) return;

    _socket!.emit('typing:stop', {'channelId': channelId});
  }

  void sendDirectMessage(String recipientId, String content) {
    if (_socket == null || !_isConnected) return;

    _socket!.emit('send_direct_message', {
      'recipientId': recipientId,
      'content': content,
    });
    log.d('[WebSocket] Sent DM to: $recipientId');
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _isConnected = false;
    _currentChannelId = null;
    _currentWorkspaceId = null;
    _connectionController.add(false);
    log.d('[WebSocket] Disconnected and disposed');
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _userUpdatedController.close();
    _typingController.close();
    _userStatusController.close();
    _notificationController.close();
    _channelCreatedController.close();
    _addedToChannelController.close();
    _taskEventController.close();
    _connectionController.close();
    _workspaceDeletedController.close();
    _channelDeletedController.close();
  }
}
