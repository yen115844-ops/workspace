import 'dart:async';
import 'dart:io';

import 'package:any_link_preview/any_link_preview.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:giphy_get/giphy_get.dart';
import 'package:go_router/go_router.dart';
import 'package:ionicons/ionicons.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/upload_constants.dart';
import '../../../core/models/models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/websocket_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/image_picker_service.dart';
import '../../../core/utils/message_content_parser.dart';
import '../../../core/utils/safe_navigation.dart';
import '../../../core/utils/upload_service.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/full_screen_image_viewer.dart';
import '../../../core/widgets/message_content_text.dart';
import '../../auth/presentation/auth_cubit.dart';
import '../../channel/data/channel_repository.dart';
import '../data/message_repository.dart';

class GroupChatScreen extends StatefulWidget {
  const GroupChatScreen({
    super.key,
    required this.channelId,
    required this.channelName,
    this.workspaceId,
    this.initialMessageId,
  });

  final String channelId;
  final String channelName;
  final String? workspaceId;
  final String? initialMessageId;

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen>
    with SingleTickerProviderStateMixin {
  final _repo = MessageRepository();
  final _channelRepo = ChannelRepository();
  final _ws = WebSocketService();
  final _messageController = TextEditingController();
  late final AutoScrollController _scrollController;
  final _focusNode = FocusNode();
  final _searchController = TextEditingController();

  List<MessageModel> _items = [];
  bool _loading = true;
  Object? _error;
  bool _sending = false;
  bool _hasMore = false;
  String? _nextCursor;
  bool _loadingMore = false;

  // Typing indicator
  final Map<String, String> _typingUsers = {}; // userId -> userName
  Timer? _typingTimer;
  Timer? _typingDebounceTimer;
  Timer? _searchDebounceTimer;

  /// Chỉ rebuild list + typing, không rebuild cả màn khi socket nhận tin mới.
  late final ValueNotifier<List<MessageModel>> _itemsNotifier;
  late final ValueNotifier<Map<String, String>> _typingUsersNotifier;

  // WebSocket subscriptions
  StreamSubscription? _messageSubscription;
  StreamSubscription? _typingSubscription;
  StreamSubscription? _userUpdatedSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _workspaceDeletedSubscription;
  StreamSubscription? _channelDeletedSubscription;
  StreamSubscription? _channelUpdatedSubscription;
  bool _wsConnected = false;

  // Search mode
  bool _isSearching = false;
  List<MessageModel> _searchResults = [];
  bool _isSearchLoading = false;

  // Reply mode
  MessageModel? _replyingTo;

  // Pending images (local only - upload when Send)
  final List<AssetEntity> _pendingImages = [];

  // Emoji picker
  bool _showEmojiKeyboard = false;

  // Channel members for read receipt avatars (userId -> member)
  Map<String, ChannelMember> _membersMap = {};

  late AnimationController _animationController;

  // Channel info (avatar, mute), theme trang nhắn tin
  ChannelModel? _channel;
  bool _channelMuted = false;

  /// Nền chat: 'default' | 'gradient_primary' | 'gradient_soft' | 'solid_light' | 'solid_dark'
  String _chatTheme = 'default';

  // Ghi âm tin nhắn thoại
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  String? _currentRecordPath;

  // Voice preview trước khi gửi: path, player, duration/position
  String? _pendingVoicePath;
  AudioPlayer? _voicePreviewPlayer;
  Duration _voiceDuration = Duration.zero;
  Duration _voicePosition = Duration.zero;
  bool _voicePlaying = false;
  StreamSubscription<Duration>? _voicePositionSub;
  StreamSubscription<Duration?>? _voiceDurationSub;

  // Một player chung cho tất cả bản ghi âm trong danh sách tin nhắn (chỉ 1 bản phát tại một thời điểm)
  AudioPlayer? _voiceMessagePlayer;
  String? _playingVoiceMessageUrl;
  Duration _voiceMessagePosition = Duration.zero;
  Duration _voiceMessageDuration = Duration.zero;
  bool _voiceMessagePlaying = false;
  StreamSubscription<Duration>? _voiceMessagePositionSub;
  StreamSubscription<Duration?>? _voiceMessageDurationSub;

  @override
  void initState() {
    super.initState();
    _itemsNotifier = ValueNotifier<List<MessageModel>>(_items);
    _typingUsersNotifier = ValueNotifier<Map<String, String>>(
      Map.from(_typingUsers),
    );
    _scrollController = AutoScrollController(
      axis: Axis.vertical,
      suggestedRowHeight: 150,
    );
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _setupScrollListener();
    _setupFocusListener();
    _connectWebSocket();
    _load();
    _loadChannelAndMute();
  }

  Future<void> _loadChannelAndMute() async {
    try {
      final ch = await _channelRepo.get(widget.channelId);
      final muted = await _channelRepo.isMuted(widget.channelId);
      if (mounted) {
        setState(() {
          _channel = ch;
          _channelMuted = muted;
          _chatTheme = _normalizeThemeId(ch.chatTheme ?? 'default');
        });
      }
    } catch (_) {}
  }

  String _normalizeThemeId(String id) {
    if (id == 'system' || id == 'light' || id == 'dark') return 'default';
    return id;
  }

  @override
  void dispose() {
    _voiceMessagePositionSub?.cancel();
    _voiceMessageDurationSub?.cancel();
    _voiceMessagePlayer?.dispose();
    _voicePositionSub?.cancel();
    _voiceDurationSub?.cancel();
    _voicePreviewPlayer?.dispose();
    _audioRecorder.dispose();
    _animationController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _searchController.dispose();
    _typingTimer?.cancel();
    _typingDebounceTimer?.cancel();
    _searchDebounceTimer?.cancel();
    _messageSubscription?.cancel();
    _typingSubscription?.cancel();
    _userUpdatedSubscription?.cancel();
    _connectionSubscription?.cancel();
    _workspaceDeletedSubscription?.cancel();
    _channelDeletedSubscription?.cancel();
    _channelUpdatedSubscription?.cancel();
    _ws.leaveChannel(widget.channelId);
    super.dispose();
  }

  void _setupScrollListener() {
    _scrollController.addListener(() {
      // Load more when reaching near top (reversed list)
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        _loadMore();
      }
    });
  }

  void _setupFocusListener() {
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus && _showEmojiKeyboard) {
      setState(() => _showEmojiKeyboard = false);
    }
  }

  Future<void> _connectWebSocket() async {
    await _ws.connect();
    _ws.joinChannel(widget.channelId);
    if (widget.workspaceId != null) {
      _ws.joinWorkspace(widget.workspaceId!);
    }

    _connectionSubscription = _ws.onConnectionChange.listen((connected) {
      if (mounted) {
        setState(() => _wsConnected = connected);
        if (connected) {
          _ws.joinChannel(widget.channelId);
          if (widget.workspaceId != null) {
            _ws.joinWorkspace(widget.workspaceId!);
          }
        }
      }
    });

    // Listen for workspace deleted
    _workspaceDeletedSubscription = _ws.onWorkspaceDeleted.listen((data) {
      final deletedWorkspaceId = data['workspaceId']?.toString();
      if (deletedWorkspaceId == widget.workspaceId && mounted) {
        _showDeletedAlert('Workspace đã bị xóa', '/workspaces');
      }
    });

    // Listen for channel deleted
    _channelDeletedSubscription = _ws.onChannelDeleted.listen((data) {
      final deletedChannelId = data['channelId']?.toString();
      if (deletedChannelId == widget.channelId && mounted) {
        final fallback = widget.workspaceId != null
            ? '/workspaces/${widget.workspaceId}'
            : '/workspaces';
        _showDeletedAlert('Channel đã bị xóa', fallback);
      }
    });

    // Listen for channel updated (theme, name, avatar...) — 1 người đổi theme thì bên kia cũng đổi theo
    _channelUpdatedSubscription = _ws.onChannelUpdated.listen((data) {
      final updatedChannelId = data['id']?.toString() ?? data['channelId']?.toString();
      if (updatedChannelId != widget.channelId || !mounted) return;
      final updated = ChannelModel.fromJson(Map<String, dynamic>.from(data));
      setState(() {
        _channel = updated;
        _chatTheme = _normalizeThemeId(updated.chatTheme ?? 'default');
      });
    });

    _messageSubscription = _ws.onMessage.listen((event) {
      final type = event['type'] as String;
      final data = event['data'] as Map<String, dynamic>;

      log.d('[GroupChat] WS event: type=$type');

      // Extract channelId - can be string or object with _id
      String? eventChannelId;
      final channelIdValue = data['channelId'];
      if (channelIdValue is String) {
        eventChannelId = channelIdValue;
      } else if (channelIdValue is Map) {
        eventChannelId =
            channelIdValue['_id']?.toString() ??
            channelIdValue['id']?.toString();
      }

      log.d(
        '[GroupChat] eventChannelId=$eventChannelId, expected=${widget.channelId}',
      );

      if (eventChannelId != widget.channelId) return;

      if (type == 'new') {
        final message = MessageModel.fromJson(data);
        log.d('[GroupChat] New message: ${message.id}');
        if (mounted) {
          // Xóa tin optimistic (pending-*) trùng nội dung + author để thay bằng bản server
          _items.removeWhere((m) =>
              m.id.startsWith('pending-') &&
              m.content == message.content &&
              m.authorId == message.authorId);
          if (!_items.any((m) => m.id == message.id)) {
            _items.insert(0, message);
            _itemsNotifier.value = List.from(_items);
          }
          // Scroll to bottom for new messages
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
          // Đang trong chat và nhận tin từ người khác → mark as read để người gửi thấy "đã xem"
          if (message.authorId != ApiClient.currentUserId) {
            _markChannelAsRead();
          }
        }
      } else if (type == 'updated') {
        final message = MessageModel.fromJson(data);
        if (mounted) {
          final index = _items.indexWhere((m) => m.id == message.id);
          if (index != -1) {
            _items[index] = message;
            _itemsNotifier.value = List.from(_items);
          }
        }
      } else if (type == 'deleted') {
        final messageId =
            data['id']?.toString() ??
            data['messageId']?.toString() ??
            data['_id']?.toString();
        if (mounted && messageId != null) {
          _items.removeWhere((m) => m.id == messageId);
          _itemsNotifier.value = List.from(_items);
        }
      } else if (type == 'reaction') {
        // Handle reaction updates
        final messageId = data['messageId']?.toString();
        final reactions = data['reactions'] as List?;
        if (mounted && messageId != null && reactions != null) {
          final index = _items.indexWhere((m) => m.id == messageId);
          if (index != -1) {
            final msg = _items[index];
            final newReactions = reactions
                .map((r) => MessageReaction.fromJson(r as Map<String, dynamic>))
                .toList();
            _items[index] = MessageModel(
              id: msg.id,
              content: msg.content,
              authorId: msg.authorId,
              authorName: msg.authorName,
              authorAvatar: msg.authorAvatar,
              createdAt: msg.createdAt,
              editedAt: msg.editedAt,
              originalContent: msg.originalContent,
              parentId: msg.parentId,
              reactions: newReactions,
              attachments: msg.attachments,
              isEdited: msg.isEdited,
              readBy: msg.readBy,
              replyToId: msg.replyToId,
              replyTo: msg.replyTo,
            );
            _itemsNotifier.value = List.from(_items);
          }
        }
      } else if (type == 'read') {
        // message_read: { messageId, userId, readCount }
        final messageId = data['messageId']?.toString();
        final userId = data['userId']?.toString();
        if (mounted && messageId != null && userId != null) {
          final index = _items.indexWhere((m) => m.id == messageId);
          if (index != -1) {
            final msg = _items[index];
            final readBy = <String>[...(msg.readBy ?? [])];
            if (!readBy.contains(userId)) {
              readBy.add(userId);
              _items[index] = MessageModel(
                id: msg.id,
                content: msg.content,
                authorId: msg.authorId,
                authorName: msg.authorName,
                authorAvatar: msg.authorAvatar,
                createdAt: msg.createdAt,
                editedAt: msg.editedAt,
                originalContent: msg.originalContent,
                parentId: msg.parentId,
                reactions: msg.reactions,
                attachments: msg.attachments,
                isEdited: msg.isEdited,
                readBy: readBy,
                replyToId: msg.replyToId,
                replyTo: msg.replyTo,
              );
              _itemsNotifier.value = List.from(_items);
            }
          }
        }
      } else if (type == 'channel_read') {
        // channel_read: { channelId, userId } - user đã đọc toàn bộ channel (tin từ người khác)
        final userId = data['userId']?.toString();
        if (mounted && userId != null) {
          var changed = false;
          for (var i = 0; i < _items.length; i++) {
            final msg = _items[i];
            if (msg.authorId != userId &&
                (msg.readBy == null || !msg.readBy!.contains(userId))) {
              final readBy = <String>[...(msg.readBy ?? []), userId];
              _items[i] = MessageModel(
                id: msg.id,
                content: msg.content,
                authorId: msg.authorId,
                authorName: msg.authorName,
                authorAvatar: msg.authorAvatar,
                createdAt: msg.createdAt,
                editedAt: msg.editedAt,
                originalContent: msg.originalContent,
                parentId: msg.parentId,
                reactions: msg.reactions,
                attachments: msg.attachments,
                isEdited: msg.isEdited,
                readBy: readBy,
                replyToId: msg.replyToId,
                replyTo: msg.replyTo,
              );
              changed = true;
            }
          }
          if (changed) _itemsNotifier.value = List.from(_items);
        }
      }
    });

    _typingSubscription = _ws.onTyping.listen((event) {
      final type = event['type'] as String;
      final data = event['data'] as Map<String, dynamic>;

      // Backend sends userId and userName
      final userId = data['userId']?.toString() ?? '';
      final userName =
          data['userName']?.toString() ?? data['name']?.toString() ?? 'Ai đó';
      if (userId.isEmpty) return;

      // Skip if it's the current user typing
      final currentUserId = ApiClient.currentUserId;
      if (userId == currentUserId) return;

      if (mounted) {
        if (type == 'start') {
          _typingUsers[userId] = userName;
        } else {
          _typingUsers.remove(userId);
        }
        _typingUsersNotifier.value = Map.from(_typingUsers);
      }
    });

    _userUpdatedSubscription = _ws.onUserUpdated.listen((data) {
      final userId = data['id']?.toString();
      final name = data['name'] as String?;
      final avatar = data['avatar'] as String?;
      if (userId == null) return;
      if (mounted) {
        if (userId == ApiClient.currentUserId) {
          context.read<AuthCubit>().refreshUser();
        }
        if (_items.any((m) => m.authorId == userId)) {
          for (var i = 0; i < _items.length; i++) {
            if (_items[i].authorId == userId) {
              _items[i] = MessageModel(
                id: _items[i].id,
                content: _items[i].content,
                authorId: _items[i].authorId,
                authorName: name ?? _items[i].authorName,
                authorAvatar: avatar ?? _items[i].authorAvatar,
                createdAt: _items[i].createdAt,
                editedAt: _items[i].editedAt,
                originalContent: _items[i].originalContent,
                parentId: _items[i].parentId,
                reactions: _items[i].reactions,
                attachments: _items[i].attachments,
                isEdited: _items[i].isEdited,
                readBy: _items[i].readBy,
                replyToId: _items[i].replyToId,
                replyTo: _items[i].replyTo,
              );
            }
          }
          _itemsNotifier.value = List.from(_items);
        }
      }
    });

    setState(() => _wsConnected = _ws.isConnected);
  }

  void _showDeletedAlert(String message, String navigateTo) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(ctx).size.width - 48,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Ionicons.warning_outline, color: AppColors.warning),
                  SizedBox(width: 12),
                  Text('Thông báo'),
                ],
              ),
              const SizedBox(height: 16),
              Text(message),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      context.go(navigateTo);
                    },
                    child: const Text('Đóng'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Bottom sheet chọn channel khác trong cùng workspace. Điều hướng -> dispose leaveChannel, màn mới joinChannel.
  void _showChannelSwitcher() async {
    final wsId = widget.workspaceId;
    if (wsId == null || wsId.isEmpty) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    List<ChannelModel> channels = [];
    try {
      channels = await _channelRepo.listByWorkspace(wsId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không tải được danh sách channel: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    if (channels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chưa có channel nào trong workspace này'),
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.surfaceDark
                        : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Ionicons.chatbubbles_outline,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Đổi channel',
                      style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: channels.length,
                  itemBuilder: (context, index) {
                    final ch = channels[index];
                    final isPrivate = ch.type == 'private';
                    final isCurrent = ch.id == widget.channelId;
                    return ListTile(
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: isPrivate
                              ? LinearGradient(
                                  colors: [
                                    AppColors.warning,
                                    AppColors.warning.withOpacity(0.7),
                                  ],
                                )
                              : (isCurrent
                                    ? AppColors.primaryGradient
                                    : LinearGradient(
                                        colors: [
                                          AppColors.primaryStart.withOpacity(
                                            0.6,
                                          ),
                                          AppColors.primaryEnd.withOpacity(0.6),
                                        ],
                                      )),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isPrivate
                              ? Ionicons.lock_closed
                              : Ionicons.chatbubble,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        isPrivate ? ch.name : '# ${ch.name}',
                        style: TextStyle(
                          fontWeight: isCurrent
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      subtitle: isCurrent
                          ? const Text(
                              'Đang mở',
                              style: TextStyle(fontSize: 12),
                            )
                          : null,
                      trailing: isCurrent
                          ? const Icon(
                              Ionicons.checkmark_circle,
                              color: AppColors.success,
                            )
                          : const Icon(Ionicons.chevron_forward),
                      onTap: () {
                        Navigator.pop(ctx);
                        if (ch.id == widget.channelId) return;
                        log.d('[GroupChat] switch channel to ${ch.name}');
                        context.go(
                          '/workspaces/$wsId/channels/${ch.id}',
                          extra: ch.name,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    log.d('[GroupChat] load channel=${widget.channelId}');
    try {
      final results = await Future.wait([
        _repo.getChannelMessages(widget.channelId, limit: 30),
        _channelRepo.getMembers(widget.channelId),
      ]);
      final result = results[0] as MessageListResult;
      final members = results[1] as List<ChannelMember>;
      final membersMap = {for (final m in members) m.id: m};
      if (mounted) {
        setState(() {
          // ListView reverse: true cần [mới nhất, ..., cũ nhất] (index 0 = dưới cùng)
          // Backend trả về [cũ nhất, ..., mới nhất] → đảo ngược
          _items = result.items.reversed.toList();
          _hasMore = result.hasMore;
          _nextCursor = result.nextCursor;
          _membersMap = membersMap;
          _loading = false;
        });
        _itemsNotifier.value = List.from(_items);
        // Mark channel as read when opening
        _markChannelAsRead();
      }
      _animationController.forward(from: 0);
      log.d('[GroupChat] loaded ${result.items.length} messages');
      if (widget.initialMessageId != null && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollToMessage(widget.initialMessageId!);
        });
      }
    } catch (e, st) {
      log.e('[GroupChat] load error', e, st);
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _markChannelAsRead() async {
    try {
      await _repo.markChannelAsRead(widget.channelId);
    } catch (e) {
      log.e('[GroupChat] mark as read error: $e');
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _nextCursor == null) return;

    setState(() => _loadingMore = true);
    try {
      final result = await _repo.getChannelMessages(
        widget.channelId,
        limit: 30,
        cursor: _nextCursor,
      );
      if (mounted) {
        setState(() {
          // Load more: batch cũ hơn, backend trả [cũ, ..., mới] → đảo rồi append
          _items.addAll(result.items.reversed.toList());
          _hasMore = result.hasMore;
          _nextCursor = result.nextCursor;
          _loadingMore = false;
        });
        _itemsNotifier.value = List.from(_items);
      }
    } catch (e) {
      log.e('[GroupChat] load more error', e);
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Debounce search: chỉ search sau khi user ngừng gõ 300ms.
  void _onSearchQueryChanged(String query) {
    _searchDebounceTimer?.cancel();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearchLoading = false;
      });
      return;
    }
    _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _searchMessages(query);
    });
  }

  // Search messages in channel
  Future<void> _searchMessages(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearchLoading = false;
      });
      return;
    }

    setState(() => _isSearchLoading = true);
    try {
      // Filter messages locally first (for quick results)
      final localResults = _items
          .where((m) => m.content.toLowerCase().contains(query.toLowerCase()))
          .toList();

      setState(() {
        _searchResults = localResults;
        _isSearchLoading = false;
      });
    } catch (e) {
      log.e('[GroupChat] search error', e);
      setState(() => _isSearchLoading = false);
    }
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _searchResults = [];
      }
    });
  }

  Future<void> _scrollToMessage(String messageId) async {
    final index = _items.indexWhere((m) => m.id == messageId);
    if (index == -1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Tin nhắn chưa được tải. Kéo lên để tải thêm rồi tìm lại.',
            ),
          ),
        );
      }
      return;
    }
    setState(() {
      _isSearching = false;
      _searchController.clear();
      _searchResults = [];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.scrollToIndex(
        index,
        preferPosition: AutoScrollPosition.middle,
        duration: const Duration(milliseconds: 450),
      );
    });
  }

  // Reply to a message
  void _startReply(MessageModel message) {
    setState(() => _replyingTo = message);
    _focusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() => _replyingTo = null);
  }

  // Copy text to clipboard
  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã sao chép'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  // Reactions - toggle: bấm lại emoji đã reaction thì bỏ, chưa thì thêm
  Future<void> _toggleReaction(MessageModel message, String emoji) async {
    final hasReacted =
        message.reactions?.any(
          (r) =>
              r.emoji == emoji && r.userIds.contains(ApiClient.currentUserId),
        ) ??
        false;
    try {
      if (hasReacted) {
        await _repo.removeReaction(message.id, emoji);
      } else {
        await _repo.addReaction(message.id, emoji);
      }
      // WebSocket sẽ cập nhật UI qua message_reaction event
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _showOriginalContent(MessageModel message) {
    if (message.originalContent == null || message.originalContent!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nội dung gốc không được lưu (tin nhắn sửa trước khi cập nhật)',
          ),
        ),
      );
      return;
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(16),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceDark : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Nội dung gốc trước khi sửa',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.surfaceDark
                      : AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  message.originalContent!,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showWhoReacted(MessageModel message, MessageReaction reaction) {
    if (reaction.userIds.isEmpty) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(16),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceDark : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(reaction.emoji, style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 8),
                  Text(
                    '${reaction.count} người đã thả ${reaction.emoji}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...reaction.userIds.map((userId) {
                final member = _membersMap[userId];
                final name = member?.name ?? member?.email ?? 'Người dùng';
                return ListTile(
                  leading: UserAvatar(
                    imageUrl: resolveAvatarUrl(member?.avatar),
                    name: name,
                    size: 40,
                  ),
                  title: Text(name),
                  subtitle: userId == ApiClient.currentUserId
                      ? const Text(
                          'Bạn',
                          style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        )
                      : null,
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _showReactionPicker(MessageModel message) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildQuickReactionPicker(ctx, message),
    );
  }

  Widget _buildQuickReactionPicker(BuildContext ctx, MessageModel message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const emojis = ['👍', '❤️', '😂', '😮', '😢', '😡', '🎉', '🔥', '👏', '💯'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Chọn phản hồi',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: emojis
                  .map(
                    (emoji) => InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        _toggleReaction(message, emoji);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.surfaceDark
                              : AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _toggleEmojiKeyboard() {
    if (_showEmojiKeyboard) {
      setState(() => _showEmojiKeyboard = false);
      _focusNode.requestFocus();
    } else {
      _focusNode.unfocus();
      setState(() => _showEmojiKeyboard = true);
    }
  }

  void _onEmojiSelected(Category? category, Emoji emoji) {
    _messageController.text += emoji.emoji;
    _messageController.selection = TextSelection.fromPosition(
      TextPosition(offset: _messageController.text.length),
    );
  }

  void _onBackspacePressed() {
    final text = _messageController.text;
    if (text.isNotEmpty) {
      // Handle emoji (which can be multi-char)
      final selection = _messageController.selection;
      if (selection.start > 0) {
        final newText =
            text.substring(0, selection.start - 1) +
            text.substring(selection.start);
        _messageController.text = newText;
        _messageController.selection = TextSelection.fromPosition(
          TextPosition(offset: selection.start - 1),
        );
      }
    }
  }

  Future<void> _attachImage() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth && !permission.hasAccess) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cần quyền truy cập ảnh để chọn'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final entities = await AssetPicker.pickAssets(
      context,
      pickerConfig: AssetPickerConfig(
        maxAssets: 9,
        requestType: RequestType.image,
        selectedAssets: _pendingImages,
        textDelegate: const VietnameseAssetPickerTextDelegate(),
        pathNameBuilder: (AssetPathEntity path) {
          final name = path.name.toLowerCase();
          if (name.contains('recents') || name == 'recent') return 'Gần đây';
          if (name.contains('favorites') || name.contains('favourite'))
            return 'Yêu thích';
          if (name.contains('camera') || name.contains('camera roll'))
            return 'Camera';
          if (name.contains('screenshots')) return 'Ảnh chụp màn hình';
          if (name.contains('downloads')) return 'Tải xuống';
          return path.name;
        },
        gridCount: 4,
        gridThumbnailSize: const ThumbnailSize.square(200),
        pickerTheme: ThemeData(
          brightness: isDark ? Brightness.dark : Brightness.light,
          colorScheme: ColorScheme(
            brightness: isDark ? Brightness.dark : Brightness.light,
            primary: AppColors.primaryStart,
            onPrimary: Colors.white,
            surface: isDark ? AppColors.cardDark : Colors.white,
            onSurface: isDark
                ? AppColors.textPrimaryDark
                : AppColors.textPrimaryLight,
            secondary: AppColors.accent,
            onSecondary: Colors.white,
            error: AppColors.error,
            onError: Colors.white,
          ),
          scaffoldBackgroundColor: isDark
              ? AppColors.bgDark
              : AppColors.bgLight,
          appBarTheme: AppBarTheme(
            backgroundColor: isDark ? AppColors.cardDark : Colors.white,
            foregroundColor: isDark
                ? AppColors.textPrimaryDark
                : AppColors.textPrimaryLight,
            elevation: 0,
            centerTitle: true,
          ),
          bottomSheetTheme: BottomSheetThemeData(
            backgroundColor: isDark ? AppColors.cardDark : Colors.white,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
          ),
        ),
      ),
    );
    if (entities != null && mounted) {
      // Kiểm tra kích thước ngay khi chọn - không chờ đến lúc gửi
      final validEntities = <AssetEntity>[];
      int filteredCount = 0;
      for (final entity in entities) {
        final file = await entity.file;
        if (file != null) {
          final size = await file.length();
          if (size <= UploadConstants.chatImageMaxBytes) {
            validEntities.add(entity);
          } else {
            filteredCount++;
          }
        }
      }
      if (mounted) {
        setState(() {
          _pendingImages.clear();
          _pendingImages.addAll(validEntities);
        });
        if (filteredCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                filteredCount == 1
                    ? '1 ảnh vượt quá ${UploadConstants.chatImageMaxMb}MB đã bỏ qua'
                    : '$filteredCount ảnh vượt quá ${UploadConstants.chatImageMaxMb}MB đã bỏ qua',
              ),
              backgroundColor: AppColors.warning,
            ),
          );
        }
      }
    }
  }

  void _removePendingImage(int index) {
    setState(() => _pendingImages.removeAt(index));
  }

  Future<void> _attachFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: [
        'pdf',
        'doc',
        'docx',
        'txt',
        'xlsx',
        'xls',
        'pptx',
        'zip',
        'mp3',
        'm4a',
        'wav',
      ],
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    setState(() => _sending = true);
    try {
      final attachments = <MessageAttachment>[];
      for (final pf in result.files) {
        final path = pf.path;
        if (path == null) continue;
        final att = await UploadService.uploadAttachment(path);
        if (att != null) attachments.add(att);
      }
      if (attachments.isEmpty && !mounted) return;
      if (!mounted) return;
      final message = await _repo.sendChannelMessage(
        widget.channelId,
        ' ',
        attachments: attachments,
      );
      if (mounted && !_items.any((m) => m.id == message.id)) {
        _items.insert(0, message);
        _itemsNotifier.value = List.from(_items);
      }
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã gửi file')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is ApiException ? e.message : 'Lỗi gửi file'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Mở picker GIF (Giphy) — thư viện giphy_get + API key Giphy đều miễn phí.
  Future<void> _showGifPicker() async {
    if (_sending) return;
    final apiKey = kGiphyApiKey.trim();
    if (apiKey.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Chưa cấu hình Giphy API key. Lấy key miễn phí tại developers.giphy.com và thêm vào app_constants.dart',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }
    final gif = await GiphyGet.getGif(
      context: context,
      apiKey: apiKey,
      showGIFs: true,
      showStickers: true,
      showEmojis: false,
      lang: GiphyLanguage.english,
    );
    if (gif == null || !mounted) return;
    final gifUrl =
        gif.images?.original?.url ??
        gif.images?.downsized?.url ??
        gif.images?.fixedHeight?.url ??
        gif.url;
    if (gifUrl == null || gifUrl.isEmpty) return;
    setState(() => _sending = true);
    try {
      final att = MessageAttachment(
        url: gifUrl,
        filename: 'gif.gif',
        mimeType: 'image/gif',
      );
      final message = await _repo.sendChannelMessage(widget.channelId, ' ', attachments: [att]);
      if (mounted && !_items.any((m) => m.id == message.id)) {
        _items.insert(0, message);
        _itemsNotifier.value = List.from(_items);
      }
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã gửi GIF')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is ApiException ? e.message : 'Lỗi gửi GIF'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showAttachOptions() {
    if (_sending) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.cardDark : Colors.white;
    final textColor = isDark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimaryLight;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Ionicons.document_attach_outline),
                title: Text(
                  'Đính kèm file',
                  style: TextStyle(color: textColor),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _attachFile();
                },
              ),
              ListTile(
                leading: const Icon(Ionicons.images_outline),
                title: Text('Chọn ảnh', style: TextStyle(color: textColor)),
                onTap: () {
                  Navigator.pop(ctx);
                  _attachImage();
                },
              ),
              ListTile(
                leading: const Icon(Ionicons.pricetag_outline),
                title: Text(
                  'GIF / Nhãn dán',
                  style: TextStyle(color: textColor),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showGifPicker();
                },
              ),
              ListTile(
                leading: const Icon(Ionicons.mic_outline),
                title: Text('Ghi âm', style: TextStyle(color: textColor)),
                onTap: () {
                  Navigator.pop(ctx);
                  _startVoiceRecord();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startVoiceRecord() async {
    if (_isRecording) return;
    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cần quyền ghi âm'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }
    final dir = await getTemporaryDirectory();
    _currentRecordPath =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    try {
      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: _currentRecordPath!,
      );
      if (mounted) setState(() => _isRecording = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi ghi âm: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _stopVoiceRecord() async {
    if (!_isRecording || _currentRecordPath == null) return;
    try {
      final path = await _audioRecorder.stop();
      if (mounted)
        setState(() {
          _isRecording = false;
          _currentRecordPath = null;
        });
      if (path == null || path.isEmpty) return;
      final file = File(path);
      if (!await file.exists() || await file.length() == 0) return;
      if (mounted) await _initVoicePreview(path);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRecording = false;
          _currentRecordPath = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi ghi âm: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _initVoicePreview(String path) async {
    _voicePositionSub?.cancel();
    _voiceDurationSub?.cancel();
    _voicePreviewPlayer?.dispose();
    _voicePreviewPlayer = AudioPlayer();
    _voiceDuration = Duration.zero;
    _voicePosition = Duration.zero;
    _voicePlaying = false;
    try {
      await _voicePreviewPlayer!.setSource(DeviceFileSource(path));
      final d = await _voicePreviewPlayer!.getDuration();
      if (d != null) _voiceDuration = d;
      _voicePositionSub = _voicePreviewPlayer!.onPositionChanged.listen((pos) {
        if (mounted) setState(() => _voicePosition = pos);
      });
      _voiceDurationSub = _voicePreviewPlayer!.onDurationChanged.listen((dur) {
        if (mounted) setState(() => _voiceDuration = dur);
      });
      _voicePreviewPlayer!.onPlayerComplete.listen((_) {
        if (mounted)
          setState(() {
            _voicePlaying = false;
            _voicePosition = _voiceDuration;
          });
      });
    } catch (_) {}
    if (mounted) setState(() => _pendingVoicePath = path);
  }

  Future<void> _toggleVoicePlayPause() async {
    if (_voicePreviewPlayer == null || _pendingVoicePath == null) return;
    if (_voicePlaying) {
      await _voicePreviewPlayer!.pause();
    } else {
      await _voicePreviewPlayer!.play(DeviceFileSource(_pendingVoicePath!));
    }
    if (mounted) setState(() => _voicePlaying = !_voicePlaying);
  }

  Future<void> _sendPendingVoice() async {
    final path = _pendingVoicePath;
    if (path == null || _sending) return;
    setState(() => _sending = true);
    _voicePositionSub?.cancel();
    _voiceDurationSub?.cancel();
    _voicePreviewPlayer?.dispose();
    _voicePreviewPlayer = null;
    setState(() {
      _pendingVoicePath = null;
      _voiceDuration = Duration.zero;
      _voicePosition = Duration.zero;
      _voicePlaying = false;
    });
    try {
      final att = await UploadService.uploadAttachment(path);
      if (att != null && mounted) {
        final message = await _repo.sendChannelMessage(
          widget.channelId,
          ' ',
          attachments: [att],
        );
        if (mounted && !_items.any((m) => m.id == message.id)) {
          _items.insert(0, message);
          _itemsNotifier.value = List.from(_items);
        }
        if (mounted && _scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã gửi tin nhắn thoại')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is ApiException ? e.message : 'Lỗi gửi'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _discardPendingVoice() async {
    _voicePositionSub?.cancel();
    _voiceDurationSub?.cancel();
    _voicePreviewPlayer?.dispose();
    _voicePreviewPlayer = null;
    final path = _pendingVoicePath;
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
    if (mounted)
      setState(() {
        _pendingVoicePath = null;
        _voiceDuration = Duration.zero;
        _voicePosition = Duration.zero;
        _voicePlaying = false;
      });
  }

  /// Khởi tạo player chung cho ghi âm trong danh sách (chỉ gọi 1 lần).
  void _ensureVoiceMessagePlayer() {
    if (_voiceMessagePlayer != null) return;
    _voiceMessagePlayer = AudioPlayer();
    _voiceMessagePositionSub = _voiceMessagePlayer!.onPositionChanged.listen((
      p,
    ) {
      if (mounted) setState(() => _voiceMessagePosition = p);
    });
    _voiceMessageDurationSub = _voiceMessagePlayer!.onDurationChanged.listen((
      d,
    ) {
      if (mounted) setState(() => _voiceMessageDuration = d);
    });
    _voiceMessagePlayer!.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _voiceMessagePlaying = false;
          _voiceMessagePosition = _voiceMessageDuration;
        });
      }
    });
  }

  /// Phát/tạm dừng bản ghi âm trong list. Chỉ 1 bản phát tại một thời điểm; phát bản khác sẽ tắt bản đang phát.
  Future<void> _requestVoiceMessagePlay(String url) async {
    _ensureVoiceMessagePlayer();
    final player = _voiceMessagePlayer!;
    final fullUrl = url.startsWith('http')
        ? url
        : (resolveAvatarUrl(url) ?? url);

    // Cùng URL: toggle play/pause hoặc phát lại từ đầu nếu đã hết
    if (_playingVoiceMessageUrl == fullUrl) {
      if (_voiceMessagePlaying) {
        await player.pause();
        if (mounted) setState(() => _voiceMessagePlaying = false);
      } else {
        // Đã hết bản: phát lại từ đầu (play thay vì seek để tránh timeout)
        if (_voiceMessageDuration.inMilliseconds > 0 &&
            _voiceMessagePosition >= _voiceMessageDuration) {
          if (mounted)
            setState(() {
              _voiceMessagePosition = Duration.zero;
              _voiceMessageDuration = Duration.zero;
            });
          await player.play(UrlSource(fullUrl));
        } else {
          await player.resume();
        }
        if (mounted) setState(() => _voiceMessagePlaying = true);
      }
      return;
    }

    // Khác URL: dừng bản cũ, phát bản mới (setSource thay thế nguồn)
    _playingVoiceMessageUrl = fullUrl;
    _voiceMessagePosition = Duration.zero;
    _voiceMessageDuration = Duration.zero;
    _voiceMessagePlaying = true;
    if (mounted) setState(() {});

    try {
      await player.play(UrlSource(fullUrl));
    } catch (e) {
      if (mounted) {
        setState(() {
          _playingVoiceMessageUrl = null;
          _voiceMessagePlaying = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi phát: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Mở xem preview file đã gửi (trình duyệt / app mặc định).
  Future<void> _openFilePreview(MessageAttachment att) async {
    final url = resolveAvatarUrl(att.url) ?? att.url;
    if (url.isEmpty) return;
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không mở được file: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Tải file/ghi âm xuống máy (lưu vào thư mục app).
  Future<void> _downloadAttachment(MessageAttachment att) async {
    final url = resolveAvatarUrl(att.url) ?? att.url;
    if (url.isEmpty) return;
    final filename = (att.filename ?? 'file')
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    try {
      final bytes = await _repo.downloadAttachmentBytes(url);
      final dir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory(p.join(dir.path, 'downloads'));
      if (!await downloadDir.exists()) await downloadDir.create(recursive: true);
      final file = File(p.join(downloadDir.path, filename));
      await file.writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã lưu vào mục Downloads của app: $filename'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is ApiException ? e.message : 'Lỗi tải file: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _onTextChanged(String text) {
    _typingDebounceTimer?.cancel();
    if (text.isNotEmpty) {
      // Debounce: gửi typing sau 300ms kể từ lần gõ cuối, tránh spam socket
      _typingDebounceTimer = Timer(const Duration(milliseconds: 300), () {
        _ws.startTyping(widget.channelId);
        _typingTimer?.cancel();
        _typingTimer = Timer(const Duration(seconds: 3), () {
          _ws.stopTyping(widget.channelId);
        });
      });
    } else {
      _ws.stopTyping(widget.channelId);
      _typingTimer?.cancel();
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    debugPrint(
      '[SendMessage] content: "$content", pendingImages: ${_pendingImages.length}, sending: $_sending',
    );

    if ((content.isEmpty && _pendingImages.isEmpty) || _sending) {
      debugPrint('[SendMessage] Skipped - empty or already sending');
      return;
    }

    setState(() => _sending = true);
    _messageController.clear();
    _ws.stopTyping(widget.channelId);
    _typingTimer?.cancel();
    _typingDebounceTimer?.cancel();

    final replyTo = _replyingTo;
    final pendingImagesCopy = List<AssetEntity>.from(_pendingImages);
    setState(() => _pendingImages.clear());
    _cancelReply();

    try {
      // Upload images when sending (lazy upload - kiểm tra kích thước FE trước)
      List<MessageAttachment>? attachments;
      int skippedCount = 0;
      if (pendingImagesCopy.isNotEmpty) {
        attachments = [];
        for (final entity in pendingImagesCopy) {
          final file = await entity.file;
          if (file != null) {
            final size = await file.length();
            if (size > UploadConstants.chatImageMaxBytes) {
              skippedCount++;
              continue;
            }
            final att = await UploadService.uploadChatImageAttachment(
              file.path,
            );
            if (att != null) attachments.add(att);
          }
        }
        // Tất cả ảnh đều vượt quá giới hạn → không gửi, restore, báo lỗi
        if (attachments.isEmpty && content.isEmpty) {
          if (mounted) {
            setState(() {
              _pendingImages.addAll(pendingImagesCopy);
              _sending = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  skippedCount == 1
                      ? 'Ảnh vượt quá ${UploadConstants.chatImageMaxMb}MB. Vui lòng chọn ảnh nhỏ hơn.'
                      : 'Tất cả $skippedCount ảnh đều vượt quá ${UploadConstants.chatImageMaxMb}MB.',
                ),
                backgroundColor: AppColors.error,
              ),
            );
          }
          return;
        }
        if (skippedCount > 0 && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                skippedCount == 1
                    ? '1 ảnh vượt quá ${UploadConstants.chatImageMaxMb}MB đã bỏ qua'
                    : '$skippedCount ảnh vượt quá ${UploadConstants.chatImageMaxMb}MB đã bỏ qua',
              ),
              backgroundColor: AppColors.warning,
            ),
          );
        }
      }

      final useRest =
          (attachments != null && attachments.isNotEmpty) || !_wsConnected;
      debugPrint(
        '[SendMessage] useRest: $useRest, wsConnected: $_wsConnected, attachments: ${attachments?.length ?? 0}',
      );

      if (useRest) {
        debugPrint('[SendMessage] Sending via REST API...');
        final message = await _repo.sendChannelMessage(
          widget.channelId,
          content.isNotEmpty ? content : ' ',
          replyToId: replyTo?.id,
          attachments: attachments?.isNotEmpty == true ? attachments : null,
        );
        debugPrint('[SendMessage] REST API success, messageId: ${message.id}');
        if (mounted && !_items.any((m) => m.id == message.id)) {
          _items.insert(0, message);
          _itemsNotifier.value = List.from(_items);
        }
      } else {
        // WebSocket send - message will arrive via new_message event
        // If WS disconnects during send, fallback to REST
        if (!_ws.isConnected) {
          debugPrint('[SendMessage] WS disconnected, fallback to REST...');
          final message = await _repo.sendChannelMessage(
            widget.channelId,
            content,
            replyToId: replyTo?.id,
          );
          debugPrint(
            '[SendMessage] REST fallback success, messageId: ${message.id}',
          );
          if (mounted && !_items.any((m) => m.id == message.id)) {
            _items.insert(0, message);
            _itemsNotifier.value = List.from(_items);
          }
        } else {
          debugPrint('[SendMessage] Sending via WebSocket...');
          // Optimistic update: hiển thị tin ngay, thay bằng bản từ server khi nhận new_message
          final pendingId = 'pending-${DateTime.now().millisecondsSinceEpoch}';
          final optimisticMessage = MessageModel(
            id: pendingId,
            content: content,
            authorId: ApiClient.currentUserId ?? '',
            authorName: 'Bạn',
            createdAt: DateTime.now(),
            replyToId: replyTo?.id,
            replyTo: replyTo,
          );
          if (mounted && !_items.any((m) => m.id == pendingId)) {
            _items.insert(0, optimisticMessage);
            _itemsNotifier.value = List.from(_items);
          }
          _ws.sendMessage(widget.channelId, content, replyToId: replyTo?.id);
        }
      }

      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      debugPrint('[SendMessage] Error: $e');
      if (mounted) {
        setState(() => _pendingImages.addAll(pendingImagesCopy));
        final msg = e is ApiException ? e.message : 'Lỗi gửi tin nhắn: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppColors.error),
        );
      }
    } finally {
      debugPrint('[SendMessage] Finally - resetting _sending to false');
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _editMessage(MessageModel message) async {
    final controller = TextEditingController(text: message.content);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(ctx).size.width - 48,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Ionicons.create_outline, color: AppColors.primaryStart),
                  SizedBox(width: 12),
                  Text('Sửa tin nhắn'),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: 'Nhập nội dung mới...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Hủy'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                    child: const Text('Lưu'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (result != null && result.isNotEmpty && result != message.content) {
      try {
        final updated = await _repo.editMessage(message.id, result);
        if (mounted) {
          setState(() {
            final index = _items.indexWhere((m) => m.id == message.id);
            if (index != -1) _items[index] = updated;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Đã sửa tin nhắn'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } on ApiException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.message),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteMessage(MessageModel message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(ctx).size.width - 48,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Ionicons.trash_outline, color: AppColors.error),
                  SizedBox(width: 12),
                  Text('Xóa tin nhắn'),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Bạn có chắc chắn muốn xóa tin nhắn này?'),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Hủy'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.error,
                    ),
                    child: const Text('Xóa'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true) {
      try {
        await _repo.deleteMessage(message.id);
        if (mounted) {
          setState(() => _items.removeWhere((m) => m.id == message.id));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Đã xóa tin nhắn'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } on ApiException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.message),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  void _showMessageOptions(MessageModel message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOwnMessage = message.authorId == ApiClient.currentUserId;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            // Quick reactions row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: ['👍', '❤️', '😂', '😮', '😢', '🎉'].map((emoji) {
                  final hasReacted =
                      message.reactions?.any(
                        (r) =>
                            r.emoji == emoji &&
                            r.userIds.contains(ApiClient.currentUserId),
                      ) ??
                      false;
                  return InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      _toggleReaction(message, emoji);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: hasReacted
                            ? AppColors.primaryStart.withValues(alpha: 0.2)
                            : (isDark
                                  ? AppColors.surfaceDark
                                  : AppColors.surfaceLight),
                        borderRadius: BorderRadius.circular(12),
                        border: hasReacted
                            ? Border.all(
                                color: AppColors.primaryStart,
                                width: 2,
                              )
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Ionicons.happy_outline,
                  color: AppColors.info,
                ),
              ),
              title: const Text('Thêm phản hồi khác'),
              onTap: () {
                Navigator.pop(ctx);
                _showReactionPicker(message);
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Ionicons.copy_outline, color: AppColors.info),
              ),
              title: const Text('Sao chép'),
              onTap: () {
                Navigator.pop(ctx);
                _copyToClipboard(message.content);
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Ionicons.arrow_undo_outline,
                  color: AppColors.info,
                ),
              ),
              title: const Text('Trả lời'),
              onTap: () {
                Navigator.pop(ctx);
                _startReply(message);
              },
            ),
            if (isOwnMessage) ...[
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Ionicons.create_outline,
                    color: AppColors.warning,
                  ),
                ),
                title: const Text('Sửa'),
                onTap: () {
                  Navigator.pop(ctx);
                  _editMessage(message);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Ionicons.trash_outline,
                    color: AppColors.error,
                  ),
                ),
                title: const Text(
                  'Xóa',
                  style: TextStyle(color: AppColors.error),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteMessage(message);
                },
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showChannelInfo(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.3,
            maxChildSize: 0.9,
            expand: false,
            builder: (_, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: isDark ? AppColors.cardDark : Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 24),
                    GestureDetector(
                      onTap: () => _pickAndSetChannelAvatar(ctx, setModalState),
                      child: _channel?.avatarUrl != null
                          ? CircleAvatar(
                              radius: 40,
                              backgroundImage: NetworkImage(
                                resolveAvatarUrl(_channel!.avatarUrl) ?? '',
                              ),
                            )
                          : Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: AppColors.primaryGradient,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Ionicons.chatbubble,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '# ${_channel?.name ?? widget.channelName}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_items.length} tin nhắn',
                      style: TextStyle(
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildInfoAction(
                          context,
                          Ionicons.people_outline,
                          'Thành viên',
                          () {
                            Navigator.pop(ctx);
                            if (widget.workspaceId != null) {
                              context.push(
                                '/workspaces/${widget.workspaceId}/channels/${widget.channelId}/members',
                                extra: _channel?.name ?? widget.channelName,
                              );
                            }
                          },
                        ),
                        _buildInfoAction(
                          context,
                          Ionicons.search_outline,
                          'Tìm kiếm',
                          () {
                            Navigator.pop(ctx);
                            _toggleSearch();
                          },
                        ),
                        _buildInfoAction(
                          context,
                          Ionicons.color_palette_outline,
                          'Nền chat',
                          () {
                            Navigator.pop(ctx);
                            _showChatThemeDialog(context);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Ionicons.pencil_outline,
                        color: AppColors.primaryStart,
                      ),
                      title: const Text('Đổi tên channel'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showRenameChannelDialog(ctx, setModalState);
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        _channelMuted
                            ? Ionicons.notifications_off_outline
                            : Ionicons.notifications_outline,
                        color: AppColors.primaryStart,
                      ),
                      title: const Text('Tắt thông báo channel'),
                      trailing: Switch(
                        value: _channelMuted,
                        onChanged: (v) =>
                            _toggleChannelMute(ctx, setModalState, v),
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Ionicons.image_outline,
                        color: AppColors.primaryStart,
                      ),
                      title: const Text('Đổi avatar channel'),
                      onTap: () => _pickAndSetChannelAvatar(ctx, setModalState),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showRenameChannelDialog(
    BuildContext context,
    void Function(void Function()) setModalState,
  ) {
    final controller = TextEditingController(
      text: _channel?.name ?? widget.channelName,
    );
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(ctx).size.width - 48,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Ionicons.pricetag_outline,
                    color: AppColors.primaryStart,
                  ),
                  SizedBox(width: 12),
                  Text('Đổi tên channel'),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: 'Tên channel',
                  hintText: 'Nhập tên mới',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                autofocus: true,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Hủy'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      final newName = controller.text.trim();
                      if (newName.isEmpty) return;
                      Navigator.pop(ctx);
                      try {
                        final updated = await _channelRepo.update(
                          widget.channelId,
                          name: newName,
                        );
                        if (mounted) {
                          setState(() => _channel = updated);
                          setModalState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Đã đổi tên channel'),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                e is ApiException ? e.message : 'Lỗi đổi tên',
                              ),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      }
                    },
                    child: const Text('Lưu'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndSetChannelAvatar(
    BuildContext modalContext,
    void Function(void Function()) setModalState,
  ) async {
    final file = await ImagePickerService.showImageSourceDialog(context);
    if (file == null || !mounted) return;
    setModalState(() {});
    try {
      final result = await UploadService.uploadFile(
        file.path,
        folder: 'attachments',
      );
      final url = result.valueForDb;
      await _channelRepo.update(widget.channelId, avatarUrl: url);
      if (mounted) {
        setState(() => _channel = _channel?.copyWith(avatarUrl: url));
        if (modalContext.mounted) Navigator.pop(modalContext);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã cập nhật avatar channel')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: ${e is ApiException ? e.message : e}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  static const List<MapEntry<String, String>> _chatThemeOptions = [
    MapEntry('default', 'Mặc định'),
    MapEntry('gradient_primary', 'Tím'),
    MapEntry('gradient_soft', 'Pastel'),
    MapEntry('gradient_sunset', 'Hoàng hôn'),
    MapEntry('gradient_ocean', 'Đại dương'),
    MapEntry('gradient_mint', 'Bạc hà'),
    MapEntry('gradient_rose', 'Hồng'),
    MapEntry('gradient_warm', 'Ấm'),
    MapEntry('solid_light', 'Sáng'),
    MapEntry('solid_dark', 'Tối'),
    MapEntry('solid_gray', 'Xám'),
    MapEntry('solid_blue', 'Xanh dương'),
    MapEntry('solid_green', 'Xanh lá'),
    MapEntry('solid_sand', 'Cát'),
    MapEntry('solid_lavender', 'Oải hương'),
    MapEntry('solid_peach', 'Đào'),
  ];

  BoxDecoration _decorationForThemeId(String id, bool isDark) {
    switch (id) {
      case 'gradient_primary':
        return BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primaryStart.withValues(alpha: 0.25),
              AppColors.primaryEnd.withValues(alpha: 0.2),
            ],
          ),
        );
      case 'gradient_soft':
        return BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.accent.withValues(alpha: 0.12),
              AppColors.primaryStart.withValues(alpha: 0.08),
            ],
          ),
        );
      case 'gradient_sunset':
        return BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFFF9A56).withValues(alpha: 0.35),
              const Color(0xFFEE5A6F).withValues(alpha: 0.3),
            ],
          ),
        );
      case 'gradient_ocean':
        return BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF2E3192).withValues(alpha: 0.2),
              const Color(0xFF1BFFFF).withValues(alpha: 0.15),
            ],
          ),
        );
      case 'gradient_mint':
        return BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF98EECC).withValues(alpha: 0.4),
              const Color(0xFFD6EADF).withValues(alpha: 0.5),
            ],
          ),
        );
      case 'gradient_rose':
        return BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFF8B4C4).withValues(alpha: 0.5),
              const Color(0xFFFCE4EC).withValues(alpha: 0.6),
            ],
          ),
        );
      case 'gradient_warm':
        return BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFF6D365).withValues(alpha: 0.2),
              const Color(0xFFFDA085).withValues(alpha: 0.15),
            ],
          ),
        );
      case 'solid_light':
        return const BoxDecoration(color: AppColors.bgLight);
      case 'solid_dark':
        return const BoxDecoration(color: AppColors.bgDark);
      case 'solid_gray':
        return BoxDecoration(color: Colors.grey.shade300);
      case 'solid_blue':
        return BoxDecoration(color: const Color(0xFFBBDEFB));
      case 'solid_green':
        return BoxDecoration(color: const Color(0xFFC8E6C9));
      case 'solid_sand':
        return BoxDecoration(color: const Color(0xFFE8DCC4));
      case 'solid_lavender':
        return BoxDecoration(color: const Color(0xFFE1BEE7));
      case 'solid_peach':
        return BoxDecoration(color: const Color(0xFFFFCCBC));
      case 'default':
      default:
        return BoxDecoration(
          gradient: isDark
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.bgDark,
                    AppColors.cardDark.withValues(alpha: 0.5),
                  ],
                )
              : null,
          color: isDark ? null : AppColors.bgLight,
        );
    }
  }

  void _showChatThemeDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(ctx).size.width - 48,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Ionicons.color_palette_outline,
                    color: AppColors.primaryStart,
                  ),
                  const SizedBox(width: 12),
                  const Text('Nền trang nhắn tin'),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Chọn nền (xem preview bên dưới)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
              const SizedBox(height: 16),
              SingleChildScrollView(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _chatThemeOptions.map((e) {
                    final id = e.key;
                    final label = e.value;
                    final selected = _chatTheme == id;
                    final decoration = _decorationForThemeId(id, isDark);
                    return InkWell(
                      onTap: () => _applyChatTheme(id),
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 72,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              height: 48,
                              width: 72,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: selected
                                      ? AppColors.primaryStart
                                      : (isDark
                                            ? Colors.white24
                                            : Colors.black12),
                                  width: selected ? 2.5 : 1,
                                ),
                                boxShadow: [
                                  if (selected)
                                    BoxShadow(
                                      color: AppColors.primaryStart.withValues(
                                        alpha: 0.3,
                                      ),
                                      blurRadius: 6,
                                      spreadRadius: 0,
                                    ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Container(decoration: decoration),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? AppColors.textPrimaryDark
                                    : AppColors.textPrimaryLight,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _applyChatTheme(String theme) async {
    if (mounted) Navigator.of(context).pop();
    try {
      final updated = await _channelRepo.update(widget.channelId, chatTheme: theme);
      if (mounted) {
        setState(() {
          _channel = updated;
          _chatTheme = _normalizeThemeId(theme);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is ApiException ? e.message : 'Không đổi được theme'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Nền phía sau khung chat: màu hoặc gradient (không ảnh hưởng sáng/tối).
  BoxDecoration _getChatBackgroundDecoration() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _decorationForThemeId(_chatTheme, isDark);
  }

  /// Màu/decoration cho header và input theo theme đang chọn (đồng bộ với nền).
  ({BoxDecoration decoration, Color surfaceColor, bool useDarkText})
  _getChatThemeUI() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (_chatTheme) {
      case 'gradient_primary':
        return (
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primaryStart.withValues(alpha: 0.92),
                AppColors.primaryEnd.withValues(alpha: 0.88),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          surfaceColor: Colors.white.withValues(alpha: 0.25),
          useDarkText: false,
        );
      case 'gradient_soft':
        return (
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryStart.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          surfaceColor: AppColors.primaryStart.withValues(alpha: 0.08),
          useDarkText: true,
        );
      case 'gradient_sunset':
        return (
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFFFF9A56).withValues(alpha: 0.9),
                const Color(0xFFEE5A6F).withValues(alpha: 0.85),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          surfaceColor: Colors.white.withValues(alpha: 0.25),
          useDarkText: false,
        );
      case 'gradient_ocean':
        return (
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF2E3192).withValues(alpha: 0.88),
                const Color(0xFF1BFFFF).withValues(alpha: 0.2),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          surfaceColor: Colors.white.withValues(alpha: 0.2),
          useDarkText: false,
        );
      case 'gradient_mint':
      case 'gradient_rose':
      case 'gradient_warm':
        return (
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          surfaceColor: Colors.white.withValues(alpha: 0.6),
          useDarkText: true,
        );
      case 'solid_dark':
        return (
          decoration: BoxDecoration(
            color: AppColors.bgDark,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          surfaceColor: AppColors.surfaceDark,
          useDarkText: false,
        );
      case 'solid_gray':
      case 'solid_blue':
      case 'solid_green':
      case 'solid_sand':
      case 'solid_lavender':
      case 'solid_peach':
        return (
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          surfaceColor: Colors.white.withValues(alpha: 0.7),
          useDarkText: true,
        );
      case 'solid_light':
        return (
          decoration: BoxDecoration(
            color: AppColors.bgLight,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          surfaceColor: AppColors.surfaceLight,
          useDarkText: true,
        );
      case 'default':
      default:
        return (
          decoration: BoxDecoration(
            color: isDark ? AppColors.cardDark : Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          surfaceColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          useDarkText: !isDark,
        );
    }
  }

  Future<void> _showScheduledMessageDialog(BuildContext context) async {
    final contentController = TextEditingController();
    DateTime sendAt = DateTime.now().add(const Duration(hours: 1));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (!context.mounted) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(ctx).size.width - 48,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Ionicons.time_outline,
                        color: AppColors.primaryStart,
                      ),
                      SizedBox(width: 12),
                      Text('Hẹn giờ gửi tin nhắn'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: contentController,
                    decoration: InputDecoration(
                      labelText: 'Nội dung',
                      hintText: 'Nhập tin nhắn...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Gửi lúc: ${sendAt.toLocal().toString().substring(0, 16)}',
                    style: TextStyle(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: ctx,
                        initialDate: sendAt,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (date == null) return;
                      final time = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay.fromDateTime(sendAt),
                      );
                      if (time == null) return;
                      sendAt = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      );
                      setDialogState(() {});
                    },
                    icon: const Icon(Ionicons.calendar_outline),
                    label: const Text('Chọn ngày giờ'),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Hủy'),
                      ),
                      FilledButton(
                        onPressed: () {
                          final content = contentController.text.trim();
                          if (content.isEmpty) return;
                          final at = DateTime(
                            sendAt.year,
                            sendAt.month,
                            sendAt.day,
                            sendAt.hour,
                            sendAt.minute,
                          );
                          if (at.isBefore(DateTime.now())) return;
                          Navigator.pop(ctx, {
                            'content': content,
                            'sendAt': at,
                          });
                        },
                        child: const Text('Hẹn giờ'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (result == null || !mounted) return;
    final content = result['content'] as String? ?? '';
    final at = result['sendAt'] as DateTime?;
    if (at == null || at.isBefore(DateTime.now())) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chọn thời gian trong tương lai'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }
    try {
      setState(() => _sending = true);
      await _repo.sendScheduledMessage(widget.channelId, content, at);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Đã hẹn gửi lúc ${at.toLocal().toString().substring(0, 16)}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e is ApiException ? e.message : 'Hẹn giờ gửi tin thất bại';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleChannelMute(
    BuildContext modalContext,
    void Function(void Function()) setModalState,
    bool muted,
  ) async {
    final prev = _channelMuted;
    setModalState(() => _channelMuted = muted);
    setState(() => _channelMuted = muted);
    try {
      if (muted) {
        await _channelRepo.mute(widget.channelId);
      } else {
        await _channelRepo.unmute(widget.channelId);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              muted ? 'Đã tắt thông báo channel' : 'Đã bật thông báo channel',
            ),
          ),
        );
      }
    } catch (e) {
      setModalState(() => _channelMuted = prev);
      setState(() => _channelMuted = prev);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: ${e is ApiException ? e.message : e}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Widget _buildInfoAction(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.primaryStart),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLeaveConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(ctx).size.width - 48,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Ionicons.exit_outline, color: AppColors.error),
                  SizedBox(width: 12),
                  Text('Rời channel'),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Bạn có chắc chắn muốn rời khỏi channel "${widget.channelName}"?',
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Hủy'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final messenger = ScaffoldMessenger.of(context);
                      final navigator = Navigator.of(context);
                      try {
                        await _channelRepo.leave(widget.channelId);
                        if (!mounted) return;
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Đã rời channel'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                        navigator.pop();
                      } on ApiException catch (e) {
                        if (!mounted) return;
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(e.message),
                            backgroundColor: AppColors.error,
                          ),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Không thể rời channel'),
                            backgroundColor: AppColors.error,
                          ),
                        );
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.error,
                    ),
                    child: const Text('Rời'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: _getChatBackgroundDecoration(),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              _isSearching ? _buildSearchHeader(isDark) : _buildHeader(),

              // Connection status
              if (!_wsConnected && !_isSearching)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  color: AppColors.warning.withValues(alpha: 0.2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(
                        Ionicons.cloud_offline_outline,
                        size: 16,
                        color: AppColors.warning,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Đang kết nối lại...',
                        style: TextStyle(
                          color: AppColors.warning,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),

              // Search results or Messages (chỉ list rebuild khi có tin mới/typing, không rebuild cả màn)
              Expanded(
                child: _isSearching
                    ? _buildSearchResults(isDark)
                    : _loading
                    ? _buildLoadingState(isDark)
                    : _error != null
                    ? _buildErrorState(isDark)
                    : ValueListenableBuilder<List<MessageModel>>(
                        valueListenable: _itemsNotifier,
                        builder: (_, items, __) {
                          if (items.isEmpty) return _buildEmptyState(isDark);
                          return _buildMessageList(isDark, items: items);
                        },
                      ),
              ),

              // Reply indicator
              if (_replyingTo != null && !_isSearching)
                _buildReplyIndicator(isDark),

              // Typing indicator (chỉ rebuild strip này khi typing thay đổi)
              ValueListenableBuilder<Map<String, String>>(
                valueListenable: _typingUsersNotifier,
                builder: (_, typingUsers, __) {
                  if (_isSearching || typingUsers.isEmpty)
                    return const SizedBox.shrink();
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 32,
                          height: 16,
                          child: _TypingIndicator(),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            typingUsers.length == 1
                                ? '${typingUsers.values.first} đang nhập...'
                                : '${typingUsers.length} người đang nhập...',
                            style: TextStyle(
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight,
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              // Input area (hide when searching)
              if (!_isSearching) _buildInputArea(),

              // Emoji picker keyboard
              if (_showEmojiKeyboard)
                SizedBox(
                  height: 280,
                  child: EmojiPicker(
                    onEmojiSelected: _onEmojiSelected,
                    onBackspacePressed: _onBackspacePressed,
                    config: Config(
                      height: 280,
                      checkPlatformCompatibility: true,
                      emojiViewConfig: EmojiViewConfig(
                        emojiSizeMax:
                            28 *
                            (foundation.defaultTargetPlatform ==
                                    TargetPlatform.iOS
                                ? 1.2
                                : 1.0),
                        backgroundColor: isDark
                            ? AppColors.cardDark
                            : Colors.white,
                      ),
                      skinToneConfig: const SkinToneConfig(),
                      categoryViewConfig: CategoryViewConfig(
                        backgroundColor: isDark
                            ? AppColors.cardDark
                            : Colors.white,
                        indicatorColor: AppColors.primaryStart,
                        iconColorSelected: AppColors.primaryStart,
                        iconColor: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                      bottomActionBarConfig: BottomActionBarConfig(
                        backgroundColor: isDark
                            ? AppColors.cardDark
                            : Colors.white,
                        buttonColor: AppColors.primaryStart,
                        buttonIconColor: Colors.white,
                      ),
                      searchViewConfig: SearchViewConfig(
                        backgroundColor: isDark
                            ? AppColors.cardDark
                            : Colors.white,
                        buttonIconColor: AppColors.primaryStart,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _onBackPressed() {
    final fallback =
        widget.workspaceId != null && widget.workspaceId!.isNotEmpty
        ? '/workspaces/${widget.workspaceId}'
        : SafeNavigation.defaultFallback;
    context.maybePopOrGo(fallback);
  }

  Widget _buildHeader() {
    final theme = _getChatThemeUI();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = theme.useDarkText
        ? AppColors.textPrimaryLight
        : AppColors.textPrimaryDark;
    final textSecondary = theme.useDarkText
        ? AppColors.textSecondaryLight
        : AppColors.textSecondaryDark;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      decoration: theme.decoration,
      child: Row(
        children: [
          IconButton(
            onPressed: _onBackPressed,
            icon: Icon(Ionicons.arrow_back, color: textPrimary),
            style: IconButton.styleFrom(backgroundColor: theme.surfaceColor),
          ),
          const SizedBox(width: 12),
          if (_channel?.avatarUrl != null) ...[
            CircleAvatar(
              radius: 18,
              backgroundImage: NetworkImage(
                resolveAvatarUrl(_channel!.avatarUrl) ?? '',
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: GestureDetector(
              onTap: widget.workspaceId != null ? _showChannelSwitcher : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '# ${_channel?.name ?? widget.channelName}',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: textPrimary,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.workspaceId != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(
                            Ionicons.chevron_down,
                            size: 18,
                            color: textSecondary,
                          ),
                        ),
                    ],
                  ),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _wsConnected
                              ? AppColors.success
                              : AppColors.warning,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${_items.length} tin nhắn',
                        style: TextStyle(color: textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Voice room (Huddle)
          if (widget.workspaceId != null)
            Container(
              decoration: BoxDecoration(
                color: theme.surfaceColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                icon: Icon(Ionicons.call_outline, color: textPrimary),
                tooltip: 'Voice room',
                onPressed: () {
                  context.push(
                    '/workspaces/${widget.workspaceId}/channels/${widget.channelId}/huddle',
                    extra: _channel?.name ?? widget.channelName,
                  );
                },
              ),
            ),
          if (widget.workspaceId != null) const SizedBox(width: 8),
          // Members button
          Container(
            decoration: BoxDecoration(
              color: theme.surfaceColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(Ionicons.people_outline, color: textPrimary),
              onPressed: () {
                if (widget.workspaceId != null) {
                  context.push(
                    '/workspaces/${widget.workspaceId}/channels/${widget.channelId}/members',
                    extra: _channel?.name ?? widget.channelName,
                  );
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          // More options
          Container(
            decoration: BoxDecoration(
              color: theme.surfaceColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: PopupMenuButton<String>(
              icon:   Icon(Ionicons.ellipsis_vertical,color: textPrimary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'info',
                  child: Row(
                    children: [
                      Icon(Ionicons.information_circle_outline, size: 2),
                      SizedBox(width: 12),
                      Text('Thông tin channel'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'search',
                  child: Row(
                    children: [
                      Icon(Ionicons.search_outline, size: 20),
                      SizedBox(width: 12),
                      Text('Tìm kiếm'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'schedule',
                  child: Row(
                    children: [
                      Icon(Ionicons.time_outline, size: 20),
                      SizedBox(width: 12),
                      Text('Hẹn giờ gửi tin nhắn'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'media',
                  child: Row(
                    children: [
                      Icon(Ionicons.stats_chart_outline, size: 20),
                      SizedBox(width: 12),
                      Text('Thống kê & File đã gửi'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'leave',
                  child: Row(
                    children: [
                      Icon(
                        Ionicons.exit_outline,
                        size: 20,
                        color: AppColors.error,
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Rời channel',
                        style: TextStyle(color: AppColors.error),
                      ),
                    ],
                  ),
                ),
              ],
              onSelected: (value) {
                switch (value) {
                  case 'search':
                    _toggleSearch();
                    break;
                  case 'info':
                    _showChannelInfo(context, isDark);
                    break;
                  case 'schedule':
                    _showScheduledMessageDialog(context);
                    break;
                  case 'media':
                    if (widget.workspaceId != null) {
                      context.push(
                        '/workspaces/${widget.workspaceId}/channels/${widget.channelId}/media',
                        extra: _channel?.name ?? widget.channelName,
                      );
                    }
                    break;
                  case 'leave':
                    _showLeaveConfirmation(context);
                    break;
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _toggleSearch,
            icon: const Icon(Ionicons.arrow_back),
            style: IconButton.styleFrom(
              backgroundColor: isDark
                  ? AppColors.surfaceDark
                  : AppColors.surfaceLight,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Tìm kiếm tin nhắn...',
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  hintStyle: TextStyle(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                  prefixIcon: Icon(
                    Ionicons.search_outline,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Ionicons.close_circle, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                            _onSearchQueryChanged('');
                          },
                        )
                      : null,
                ),
                onChanged: _onSearchQueryChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(bool isDark) {
    if (_isSearchLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchController.text.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Ionicons.search_outline,
              size: 64,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
            const SizedBox(height: 16),
            Text(
              'Nhập từ khóa để tìm kiếm',
              style: TextStyle(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Ionicons.document_text_outline,
              size: 64,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
            const SizedBox(height: 16),
            Text(
              'Không tìm thấy tin nhắn nào',
              style: TextStyle(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final msg = _searchResults[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: isDark ? AppColors.cardDark : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            onTap: () => _scrollToMessage(msg.id),
            leading: CircleAvatar(
              backgroundColor: AppColors.primaryStart.withValues(alpha: 0.2),
              child: Text(
                (msg.authorName ?? '?')[0].toUpperCase(),
                style: const TextStyle(
                  color: AppColors.primaryStart,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              msg.authorName ?? 'Unknown',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              msg.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(
              _formatSearchTime(msg.createdAt),
              style: TextStyle(
                fontSize: 11,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatSearchTime(DateTime? dt) {
    if (dt == null) return '';
    final local = dt.isUtc ? dt.toLocal() : dt;
    final now = DateTime.now();
    if (local.day == now.day &&
        local.month == now.month &&
        local.year == now.year) {
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    return '${local.day}/${local.month}';
  }

  Widget _buildReplyIndicator(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        border: Border(
          top: BorderSide(
            color: AppColors.primaryStart.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryStart.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Ionicons.arrow_undo,
              size: 16,
              color: AppColors.primaryStart,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Trả lời ${_replyingTo?.authorName ?? ''}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryStart,
                    fontSize: 12,
                  ),
                ),
                Text(
                  _replyingTo?.content ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _cancelReply,
            icon: const Icon(Ionicons.close, size: 20),
            style: IconButton.styleFrom(
              backgroundColor: isDark
                  ? AppColors.surfaceDark
                  : AppColors.surfaceLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
              shape: BoxShape.circle,
            ),
            child: const CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 16),
          Text(
            'Đang tải tin nhắn...',
            style: TextStyle(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(bool isDark) {
    return ErrorState(message: _error.toString(), onRetry: _load);
  }

  Widget _buildEmptyState(bool isDark) {
    return EmptyState(
      icon: Ionicons.chatbubbles_outline,
      title: 'Chưa có tin nhắn',
      subtitle: 'Hãy là người đầu tiên gửi tin nhắn trong channel này!',
    );
  }

  Widget _buildMessageList(bool isDark, {List<MessageModel>? items}) {
    final list = items ?? _items;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        controller: _scrollController,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: list.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (_loadingMore && index == list.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }

          final msg = list[index];
          final prevMsg = index < list.length - 1 ? list[index + 1] : null;
          final nextMsg = index > 0 ? list[index - 1] : null;
          final showAvatar =
              prevMsg == null || prevMsg.authorId != msg.authorId;
          final showDateSeparator =
              msg.createdAt != null &&
              (nextMsg == null ||
                  nextMsg.createdAt == null ||
                  !_isSameDay(msg.createdAt!, nextMsg.createdAt!));

          final content = AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              final delay = (index * 0.05).clamp(0.0, 0.5);
              final start = delay;
              final end = (delay + 0.3).clamp(0.0, 1.0);
              final animation = Tween<double>(begin: 0.0, end: 1.0).animate(
                CurvedAnimation(
                  parent: _animationController,
                  curve: Interval(start, end, curve: Curves.easeOutCubic),
                ),
              );
              return Transform.translate(
                offset: Offset(0, 20 * (1 - animation.value)),
                child: Opacity(opacity: animation.value, child: child),
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showDateSeparator)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.surfaceDark
                              : AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _formatDateSeparator(msg.createdAt!),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondaryLight,
                          ),
                        ),
                      ),
                    ),
                  ),
                _MessageBubble(
                  message: msg,
                  isDark: isDark,
                  showAvatar: showAvatar,
                  currentUserId: ApiClient.currentUserId,
                  onReactionChipTap: _showWhoReacted,
                  onShowOriginalTap: _showOriginalContent,
                  membersMap: _membersMap,
                  typingUsers: _typingUsersNotifier.value,
                  readerUserIds: _computeReaderUserIdsAtMessage(list, index),
                  isLastMessage: index == 0,
                  voicePlaybackUrl: _playingVoiceMessageUrl,
                  voicePosition: _voiceMessagePosition,
                  voiceDuration: _voiceMessageDuration,
                  voicePlaying: _voiceMessagePlaying,
                  onVoicePlayRequested: _requestVoiceMessagePlay,
                  onFilePreview: _openFilePreview,
                  onFileDownload: _downloadAttachment,
                ),
              ],
            ),
          );
          return AutoScrollTag(
            key: ValueKey(msg.id),
            controller: _scrollController,
            index: index,
            child: GestureDetector(
              onLongPress: () => _showMessageOptions(msg),
              child: content,
            ),
          );
        },
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    final aLocal = a.isUtc ? a.toLocal() : a;
    final bLocal = b.isUtc ? b.toLocal() : b;
    return aLocal.year == bLocal.year &&
        aLocal.month == bLocal.month &&
        aLocal.day == bLocal.day;
  }

  /// UserIds whose last read position is at message [index]. Index 0 = most recent.
  Set<String> _computeReaderUserIdsAtMessage(
    List<MessageModel> items,
    int index,
  ) {
    final result = <String>{};
    for (final uid in items[index].readBy ?? []) {
      // Check if this is the most recent (smallest index) message with uid in readBy
      bool isLastRead = true;
      for (var i = 0; i < index; i++) {
        if ((items[i].readBy ?? []).contains(uid)) {
          isLastRead = false;
          break;
        }
      }
      if (isLastRead) result.add(uid);
    }
    return result;
  }

  String _formatDateSeparator(DateTime dt) {
    final local = dt.isUtc ? dt.toLocal() : dt;
    final now = DateTime.now();
    if (_isSameDay(dt, now)) return 'Hôm nay';
    final yesterday = now.subtract(const Duration(days: 1));
    if (_isSameDay(dt, yesterday)) return 'Hôm qua';
    return '${local.day}/${local.month}/${local.year}';
  }

  Widget _buildInputArea() {
    final theme = _getChatThemeUI();
    final surface = theme.surfaceColor;
    final textPrimary = theme.useDarkText
        ? AppColors.textPrimaryLight
        : AppColors.textPrimaryDark;
    final textSecondary = theme.useDarkText
        ? AppColors.textSecondaryLight
        : AppColors.textSecondaryDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.decoration.color,
        gradient: theme.decoration.gradient,
        boxShadow: [
          ...?theme.decoration.boxShadow,
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_pendingImages.isNotEmpty) ...[
              SizedBox(
                height: 56,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(bottom: 6),
                  itemCount: _pendingImages.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    final entity = _pendingImages[index];
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 50,
                            height: 50,
                            child: AssetEntityImage(
                              entity,
                              isOriginal: false,
                              thumbnailSize: const ThumbnailSize.square(100),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: surface,
                                child: Icon(
                                  Ionicons.image_outline,
                                  size: 20,
                                  color: textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: -2,
                          right: -2,
                          child: GestureDetector(
                            onTap: () => _removePendingImage(index),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: AppColors.error,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Ionicons.close,
                                size: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
            if (_pendingVoicePath != null)
              _buildVoicePreviewRow(theme.useDarkText, surface),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _compactIconBtn(
                  surface,
                  icon: _isRecording ? Ionicons.stop_circle : Ionicons.add,
                  onTap: _sending
                      ? null
                      : (_isRecording ? _stopVoiceRecord : _showAttachOptions),
                  iconColor: _isRecording ? AppColors.error : textPrimary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            focusNode: _focusNode,
                            onChanged: _onTextChanged,
                            onTap: () {
                              if (_showEmojiKeyboard)
                                setState(() => _showEmojiKeyboard = false);
                            },
                            decoration: InputDecoration(
                              hintText: 'Nhắn tin...',
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              hintStyle: TextStyle(
                                color: textSecondary,
                                fontSize: 15,
                              ),
                            ),
                            maxLines: 4,
                            minLines: 1,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _sendMessage(),
                            style: TextStyle(color: textPrimary, fontSize: 15),
                          ),
                        ),
                        IconButton(
                          onPressed: _toggleEmojiKeyboard,
                          icon: Icon(
                            _showEmojiKeyboard
                                ? Ionicons.keypad_outline
                                : Ionicons.happy_outline,
                            size: 22,
                            color: _showEmojiKeyboard
                                ? AppColors.primaryStart
                                : textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _sending ? null : _sendMessage,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryStart.withValues(
                              alpha: 0.25,
                            ),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: _sending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Icon(
                              Ionicons.send_sharp,
                              color: Colors.white,
                              size: 20,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoicePreviewRow(bool isDark, Color surface) {
    String fmt(Duration d) {
      final m = d.inMinutes;
      final s = d.inSeconds % 60;
      return '$m:${s.toString().padLeft(2, '0')}';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _toggleVoicePlayPause,
            child: Icon(
              _voicePlaying ? Ionicons.pause_circle : Ionicons.play_circle,
              color: AppColors.primaryStart,
              size: 36,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${fmt(_voicePosition)} / ${fmt(_voiceDuration)}',
            style: TextStyle(
              fontSize: 13,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Ionicons.close_circle_outline, size: 22),
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondaryLight,
            onPressed: _discardPendingVoice,
            tooltip: 'Hủy',
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(Ionicons.send, size: 20, color: AppColors.primaryStart),
            onPressed: _sending ? null : _sendPendingVoice,
            tooltip: 'Gửi',
          ),
        ],
      ),
    );
  }

  Widget _compactIconBtn(
    Color surface, {
    required IconData icon,
    VoidCallback? onTap,
    Color? iconColor,
  }) {
    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 22, color: iconColor),
        ),
      ),
    );
  }
}

class _ReadReceiptAvatars extends StatelessWidget {
  const _ReadReceiptAvatars({
    required this.membersMap,
    required this.readerUserIds,
    required this.typingUserIds,
    this.currentUserId,
    required this.isDark,
    this.typingUserNames = const {},
  });

  final Map<String, ChannelMember> membersMap;
  final Set<String> readerUserIds;
  final Set<String> typingUserIds;
  final String? currentUserId;
  final bool isDark;
  final Map<String, String> typingUserNames;

  @override
  Widget build(BuildContext context) {
    final typing = typingUserIds.where((id) => id != currentUserId).toList();
    // Loại người đang gõ khỏi "đã đọc" để tránh hiển thị 2 lần avatar
    final readers = readerUserIds
        .where((id) => id != currentUserId && !typingUserIds.contains(id))
        .toList();
    if (readers.isEmpty && typing.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 2,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ...readers.map(
          (uid) => _AvatarChip(
            member: membersMap[uid],
            fallbackName: null,
            userId: uid,
            isDark: isDark,
            isReading: false,
          ),
        ),
        ...typing.map(
          (uid) => _AvatarChip(
            member: membersMap[uid],
            fallbackName: typingUserNames[uid],
            userId: uid,
            isDark: isDark,
            isReading: true,
          ),
        ),
      ],
    );
  }
}

class _AvatarChip extends StatefulWidget {
  const _AvatarChip({
    this.member,
    this.fallbackName,
    required this.userId,
    required this.isDark,
    required this.isReading,
  });

  final ChannelMember? member;
  final String? fallbackName;
  final String userId;
  final bool isDark;
  final bool isReading;

  @override
  State<_AvatarChip> createState() => _AvatarChipState();
}

class _AvatarChipState extends State<_AvatarChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name =
        widget.member?.name ??
        widget.member?.email ??
        widget.fallbackName ??
        '?';
    final avatarUrl = widget.member?.avatar;
    return Tooltip(
      message: widget.isReading ? '$name đang xem' : '$name đã đọc',
      child: Container(
        margin: const EdgeInsets.only(right: 2),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            UserAvatar(
              imageUrl: resolveAvatarUrl(avatarUrl),
              name: name,
              size: 20,
            ),
            if (widget.isReading)
              Positioned(
                right: -2,
                bottom: -2,
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) => Container(
                    width: 6 + 2 * _pulseController.value,
                    height: 6 + 2 * _pulseController.value,
                    decoration: BoxDecoration(
                      color: AppColors.primaryStart.withValues(
                        alpha: 0.9 - 0.3 * _pulseController.value,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.isDark
                            ? AppColors.cardDark
                            : Colors.white,
                        width: 1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isDark,
    required this.showAvatar,
    this.currentUserId,
    this.onReactionChipTap,
    this.onShowOriginalTap,
    this.membersMap = const {},
    this.typingUsers = const {},
    this.readerUserIds = const {},
    this.isLastMessage = false,
    this.voicePlaybackUrl,
    this.voicePosition = Duration.zero,
    this.voiceDuration = Duration.zero,
    this.voicePlaying = false,
    this.onVoicePlayRequested,
    this.onFilePreview,
    this.onFileDownload,
  });

  final MessageModel message;
  final bool isDark;
  final bool showAvatar;
  final String? currentUserId;
  final void Function(MessageModel message, MessageReaction reaction)?
  onReactionChipTap;
  final void Function(MessageModel message)? onShowOriginalTap;
  final Map<String, ChannelMember> membersMap;
  final Map<String, String> typingUsers;
  final Set<String> readerUserIds;
  final bool isLastMessage;
  final String? voicePlaybackUrl;
  final Duration voicePosition;
  final Duration voiceDuration;
  final bool voicePlaying;
  final void Function(String url)? onVoicePlayRequested;
  final void Function(MessageAttachment att)? onFilePreview;
  final void Function(MessageAttachment att)? onFileDownload;

  Color _getAvatarColor(String? name) {
    if (name == null) return AppColors.primaryStart;
    final colors = [
      AppColors.primaryStart,
      AppColors.primaryEnd,
      AppColors.accent,
      AppColors.success,
      AppColors.warning,
      AppColors.info,
    ];
    return colors[name.hashCode % colors.length];
  }

  bool get _isMe => currentUserId != null && message.authorId == currentUserId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: showAvatar ? 16 : 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: _isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          // Bên trái: avatar người khác
          if (!_isMe) ...[
            if (showAvatar)
              UserAvatar(
                imageUrl: resolveAvatarUrl(message.authorAvatar),
                name: message.authorName ?? '?',
                size: 40,
              )
            else
              const SizedBox(width: 40),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: _isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (showAvatar && !_isMe)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Text(
                          message.authorName ?? 'Unknown',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: _getAvatarColor(message.authorName),
                              ),
                        ),
                        const SizedBox(width: 8),
                        if (message.createdAt != null)
                          Text(
                            _formatTime(message.createdAt!),
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight,
                            ),
                          ),
                        if (message.isEdited) ...[
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: onShowOriginalTap != null
                                ? () => onShowOriginalTap!(message)
                                : null,
                            child: Text(
                              '(đã sửa)',
                              style: TextStyle(
                                fontSize: 10,
                                fontStyle: FontStyle.italic,
                                color:
                                    (onShowOriginalTap != null
                                        ? AppColors.primaryStart
                                        : null) ??
                                    (isDark
                                        ? AppColors.textSecondaryDark
                                        : AppColors.textSecondaryLight),
                                decoration: onShowOriginalTap != null
                                    ? TextDecoration.underline
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (showAvatar && _isMe)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (message.createdAt != null)
                          Text(
                            _formatTime(message.createdAt!),
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight,
                            ),
                          ),
                        if (message.isEdited) ...[
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: onShowOriginalTap != null
                                ? () => onShowOriginalTap!(message)
                                : null,
                            child: Text(
                              '(đã sửa)',
                              style: TextStyle(
                                fontSize: 10,
                                fontStyle: FontStyle.italic,
                                color:
                                    (onShowOriginalTap != null
                                        ? AppColors.primaryStart
                                        : null) ??
                                    (isDark
                                        ? AppColors.textSecondaryDark
                                        : AppColors.textSecondaryLight),
                                decoration: onShowOriginalTap != null
                                    ? TextDecoration.underline
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                // Build message content with separate layout for images vs text
                _buildMessageContent(context),
                // Read receipts (avatars) and reactions row
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisAlignment: _isMe
                        ? MainAxisAlignment.end
                        : MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Avatars: đã đọc (readerUserIds) + đang xem (typingUserIds on last msg)
                      Expanded(
                        child: Align(
                          alignment: _isMe
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: _ReadReceiptAvatars(
                            membersMap: membersMap,
                            readerUserIds: readerUserIds,
                            typingUserIds: isLastMessage
                                ? typingUsers.keys.toSet()
                                : const {},
                            typingUserNames: typingUsers,
                            currentUserId: currentUserId,
                            isDark: isDark,
                          ),
                        ),
                      ),
                      // Reactions
                      if (message.reactions != null &&
                          message.reactions!.isNotEmpty)
                        Expanded(
                          child: Align(
                            alignment: _isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Wrap(
                              alignment: _isMe
                                  ? WrapAlignment.end
                                  : WrapAlignment.start,
                              spacing: 4,
                              children: message.reactions!.map((r) {
                                final hasReacted =
                                    currentUserId != null &&
                                    r.userIds.contains(currentUserId);
                                return GestureDetector(
                                  onTap: onReactionChipTap != null
                                      ? () => onReactionChipTap!(message, r)
                                      : null,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: hasReacted
                                          ? AppColors.primaryStart.withValues(
                                              alpha: 0.2,
                                            )
                                          : (isDark
                                                ? AppColors.surfaceDark
                                                : AppColors.surfaceLight),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: hasReacted
                                            ? AppColors.primaryStart
                                            : AppColors.primaryStart.withValues(
                                                alpha: 0.3,
                                              ),
                                        width: hasReacted ? 2 : 1,
                                      ),
                                    ),
                                    child: Text(
                                      '${r.emoji} ${r.count}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Bên phải: avatar của mình
          if (_isMe) ...[
            const SizedBox(width: 12),
            if (showAvatar)
              UserAvatar(
                imageUrl: resolveAvatarUrl(message.authorAvatar),
                name: message.authorName ?? '?',
                size: 40,
              )
            else
              const SizedBox(width: 40),
          ],
        ],
      ),
    );
  }

  /// Build message content with clean layout - images without container, text with container
  Widget _buildMessageContent(BuildContext context) {
    final hasAttachments =
        message.attachments != null && message.attachments!.isNotEmpty;
    final hasText = message.content.trim().isNotEmpty;
    final hasReply = message.replyTo != null;

    // Separate images, voice (ghi âm), and other files
    List<MessageAttachment> images = [];
    List<MessageAttachment> voiceAttachments = [];
    List<MessageAttachment> files = [];

    if (hasAttachments) {
      for (final att in message.attachments!) {
        final isImage =
            att.mimeType?.startsWith('image/') ??
            (att.url.toLowerCase().contains('.jpg') ||
                att.url.toLowerCase().contains('.png') ||
                att.url.toLowerCase().contains('.jpeg') ||
                att.url.toLowerCase().contains('.gif') ||
                att.url.toLowerCase().contains('.webp'));
        if (isImage) {
          images.add(att);
        } else if (_isVoiceAttachment(att)) {
          voiceAttachments.add(att);
        } else {
          files.add(att);
        }
      }
    }

    final hasImages = images.isNotEmpty;
    final hasVoice = voiceAttachments.isNotEmpty;
    final hasFiles = files.isNotEmpty;

    // Case 1: Only images (no text, no reply, no files, no voice)
    if (hasImages && !hasText && !hasReply && !hasFiles && !hasVoice) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: _buildImageGrid(context, images, _isMe, isDark),
      );
    }

    // Case 2: Only voice (bản ghi âm) - hiển thị bubble ghi âm, có waveform và nghe tại chỗ
    if (hasVoice && !hasText && !hasReply && !hasImages && !hasFiles) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: _buildVoiceOnlyBubble(
          context,
          voiceAttachments,
          isDark,
          voicePlaybackUrl: voicePlaybackUrl,
          voicePosition: voicePosition,
          voiceDuration: voiceDuration,
          voicePlaying: voicePlaying,
          onVoicePlayRequested: onVoicePlayRequested,
        ),
      );
    }

    // Case 3: Only text or reply (no attachments)
    if (!hasAttachments && (hasText || hasReply)) {
      return _buildTextContainer(
        context,
        hasReply: hasReply,
        hasText: hasText,
        voiceAttachments: null,
        files: null,
        voicePlaybackUrl: voicePlaybackUrl,
        voicePosition: voicePosition,
        voiceDuration: voiceDuration,
        voicePlaying: voicePlaying,
        onVoicePlayRequested: onVoicePlayRequested,
      );
    }

    // Case 4: Mixed content - images outside, voice/text/files in container
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      child: Column(
        crossAxisAlignment: _isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (hasImages) ...[
            _buildImageGrid(context, images, _isMe, isDark),
            if (hasText || hasReply || hasVoice || hasFiles)
              const SizedBox(height: 8),
          ],
          if (hasText || hasReply || hasVoice || hasFiles)
            _buildTextContainer(
              context,
              hasReply: hasReply,
              hasText: hasText,
              voiceAttachments: hasVoice ? voiceAttachments : null,
              files: hasFiles ? files : null,
              voicePlaybackUrl: voicePlaybackUrl,
              voicePosition: voicePosition,
              voiceDuration: voiceDuration,
              voicePlaying: voicePlaying,
              onVoicePlayRequested: onVoicePlayRequested,
            ),
        ],
      ),
    );
  }

  static bool _isVoiceAttachment(MessageAttachment att) {
    if (att.mimeType != null && att.mimeType!.startsWith('audio/')) return true;
    final name = (att.filename ?? att.url).toLowerCase();
    return name.endsWith('.m4a') ||
        name.endsWith('.mp3') ||
        name.endsWith('.aac');
  }

  Widget _buildVoiceOnlyBubble(
    BuildContext context,
    List<MessageAttachment> voiceAttachments,
    bool isDark, {
    String? voicePlaybackUrl,
    required Duration voicePosition,
    required Duration voiceDuration,
    required bool voicePlaying,
    void Function(String url)? onVoicePlayRequested,
  }) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: _isMe ? AppColors.primaryGradient : null,
        color: _isMe
            ? null
            : (isDark ? AppColors.surfaceDark : AppColors.surfaceLight),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(_isMe ? 16 : 4),
          bottomRight: Radius.circular(_isMe ? 4 : 16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < voiceAttachments.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i < voiceAttachments.length - 1 ? 8 : 0,
              ),
              child: _VoiceMessageBubble(
                attachment: voiceAttachments[i],
                isMe: _isMe,
                isDark: isDark,
                playbackUrl: voicePlaybackUrl,
                position: voicePosition,
                duration: voiceDuration,
                isPlaying: voicePlaying,
                onPlayRequested: onVoicePlayRequested,
                onDownload: onFileDownload,
              ),
            ),
        ],
      ),
    );
  }

  /// Build text container with optional reply, voice attachments, and files
  Widget _buildTextContainer(
    BuildContext context, {
    required bool hasReply,
    required bool hasText,
    List<MessageAttachment>? voiceAttachments,
    List<MessageAttachment>? files,
    String? voicePlaybackUrl,
    Duration voicePosition = Duration.zero,
    Duration voiceDuration = Duration.zero,
    bool voicePlaying = false,
    void Function(String url)? onVoicePlayRequested,
  }) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: _isMe ? AppColors.primaryGradient : null,
        color: _isMe
            ? null
            : (isDark ? AppColors.surfaceDark : AppColors.surfaceLight),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(_isMe ? 16 : 4),
          bottomRight: Radius.circular(_isMe ? 4 : 16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Reply context
          if (hasReply)
            Container(
              margin: EdgeInsets.only(
                bottom: (hasText || files != null) ? 8 : 0,
              ),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _isMe
                    ? Colors.white.withValues(alpha: 0.25)
                    : (isDark
                          ? AppColors.primaryStart.withValues(alpha: 0.1)
                          : AppColors.primaryStart.withValues(alpha: 0.08)),
                borderRadius: BorderRadius.circular(8),
                border: Border(
                  left: BorderSide(
                    color: _isMe ? Colors.white : AppColors.primaryStart,
                    width: 3,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.replyTo!.authorName ?? 'Unknown',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _isMe ? Colors.white : AppColors.primaryStart,
                    ),
                  ),
                  const SizedBox(height: 2),
                  MessageContentText(
                    content: message.replyTo!.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: _isMe
                          ? Colors.white.withValues(alpha: 0.95)
                          : (isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondaryLight),
                    ),
                  ),
                ],
              ),
            ),
          // Voice (bản ghi âm) - nghe tại chỗ + waveform + tải xuống
          if (voiceAttachments != null && voiceAttachments.isNotEmpty) ...[
            ...voiceAttachments.map(
              (att) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _VoiceMessageBubble(
                  attachment: att,
                  isMe: _isMe,
                  isDark: isDark,
                  playbackUrl: voicePlaybackUrl,
                  position: voicePosition,
                  duration: voiceDuration,
                  isPlaying: voicePlaying,
                  onPlayRequested: onVoicePlayRequested,
                  onDownload: onFileDownload,
                ),
              ),
            ),
            if (hasText || (files != null && files.isNotEmpty))
              const SizedBox(height: 8),
          ],
          // Files (không phải ghi âm)
          if (files != null && files.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: files
                  .map((att) => _buildFileAttachment(att, _isMe, isDark))
                  .toList(),
            ),
            if (hasText) const SizedBox(height: 8),
          ],
          // Message content (URLs clickable)
          if (hasText)
            MessageContentText(
              content: message.content,
              style: TextStyle(
                color: _isMe
                    ? Colors.white
                    : (isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight),
                height: 1.4,
              ),
            ),
          // Link preview (khi nội dung có URL)
          if (hasText) ...[
            _buildLinkPreviewIfAny(context, message.content, _isMe, isDark),
          ],
        ],
      ),
    );
  }

  /// Nếu nội dung chứa link thì hiển thị preview (ảnh, tiêu đề, mô tả). Trả về SizedBox.shrink() nếu không có URL.
  Widget _buildLinkPreviewIfAny(
    BuildContext context,
    String content,
    bool isMe,
    bool isDark,
  ) {
    final url = getFirstUrl(content);
    if (url == null || url.isEmpty) return const SizedBox.shrink();
    final textColor = isMe
        ? Colors.white
        : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight);
    final secondaryColor = isMe
        ? Colors.white70
        : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: AnyLinkPreview(
          link: url,
          displayDirection: UIDirection.uiDirectionHorizontal,
          cache: const Duration(hours: 24),
          placeholderWidget: Container(
            height: 72,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isMe
                  ? Colors.white.withValues(alpha: 0.15)
                  : (isDark ? AppColors.surfaceDark : AppColors.surfaceLight),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Ionicons.link_outline, color: secondaryColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Đang tải preview...',
                    style: TextStyle(color: secondaryColor, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          errorWidget: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isMe
                  ? Colors.white.withValues(alpha: 0.15)
                  : (isDark ? AppColors.surfaceDark : AppColors.surfaceLight),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Ionicons.link_outline, color: secondaryColor, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    url,
                    style: TextStyle(color: textColor, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          backgroundColor: isMe
              ? Colors.white.withValues(alpha: 0.15)
              : (isDark ? AppColors.surfaceDark : AppColors.surfaceLight),
          borderRadius: 10,
          removeElevation: true,
          titleStyle: TextStyle(
            color: textColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          bodyStyle: TextStyle(color: secondaryColor, fontSize: 12),
          bodyMaxLines: 2,
          bodyTextOverflow: TextOverflow.ellipsis,
          showMultimedia: true,
          onTap: () async {
            final uri = Uri.tryParse(url);
            if (uri != null) {
              try {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (_) {}
            }
          },
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final local = dt.isUtc ? dt.toLocal() : dt;
    final now = DateTime.now();
    if (local.day == now.day &&
        local.month == now.month &&
        local.year == now.year) {
      return 'Hôm nay ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (local.day == yesterday.day &&
        local.month == yesterday.month &&
        local.year == yesterday.year) {
      return 'Hôm qua ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    return '${local.day}/${local.month} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildImageGrid(
    BuildContext context,
    List<MessageAttachment> images,
    bool isMe,
    bool isDark,
  ) {
    final imageUrls = images
        .map((img) => resolveAvatarUrl(img.url) ?? img.url)
        .toList();

    if (images.length == 1) {
      // Single image - display with proper aspect ratio
      final imgUrl = imageUrls.first;
      return GestureDetector(
        onTap: () => FullScreenImageViewer.show(context, imgUrl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 250, maxHeight: 300),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              imgUrl,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  width: 200,
                  height: 150,
                  decoration: BoxDecoration(
                    color: isMe
                        ? Colors.white.withValues(alpha: 0.2)
                        : (isDark
                              ? AppColors.surfaceDark
                              : AppColors.surfaceLight),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                          : null,
                      strokeWidth: 2,
                      color: isMe ? Colors.white70 : AppColors.primaryStart,
                    ),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) => Container(
                width: 200,
                height: 150,
                decoration: BoxDecoration(
                  color: isMe
                      ? Colors.white.withValues(alpha: 0.2)
                      : (isDark
                            ? AppColors.surfaceDark
                            : AppColors.surfaceLight),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Ionicons.image_outline,
                  size: 32,
                  color: isMe ? Colors.white70 : null,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Multiple images - grid layout
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: images.length == 2 ? 2 : (images.length <= 4 ? 2 : 3),
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: images.length > 9 ? 9 : images.length,
        itemBuilder: (context, index) {
          final imgUrl = imageUrls[index];
          final showMoreOverlay = index == 8 && images.length > 9;

          return GestureDetector(
            onTap: () => FullScreenImageViewer.showGallery(
              context,
              imageUrls,
              initialIndex: index,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    imgUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: isMe
                          ? Colors.white.withValues(alpha: 0.2)
                          : (isDark
                                ? AppColors.surfaceDark
                                : AppColors.surfaceLight),
                      child: Icon(
                        Ionicons.image_outline,
                        size: 24,
                        color: isMe ? Colors.white70 : null,
                      ),
                    ),
                  ),
                  if (showMoreOverlay)
                    Container(
                      color: Colors.black54,
                      child: Center(
                        child: Text(
                          '+${images.length - 9}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFileAttachment(MessageAttachment att, bool isMe, bool isDark) {
    final canPreview = onFilePreview != null;
    final canDownload = onFileDownload != null;
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      decoration: BoxDecoration(
        color: isMe
            ? Colors.white.withValues(alpha: 0.2)
            : (isDark ? AppColors.surfaceDark : AppColors.surfaceLight),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: canPreview ? () => onFilePreview!(att) : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  Ionicons.document_outline,
                  color: isMe ? Colors.white : AppColors.primaryStart,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        att.filename ?? 'File',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isMe
                              ? Colors.white
                              : (isDark
                                    ? AppColors.textPrimaryDark
                                    : AppColors.textPrimaryLight),
                        ),
                      ),
                      if (canPreview)
                        Text(
                          'Chạm để xem',
                          style: TextStyle(
                            fontSize: 11,
                            color: (isMe ? Colors.white : AppColors.primaryStart)
                                .withValues(alpha: 0.8),
                          ),
                        ),
                    ],
                  ),
                ),
                if (canDownload)
                  IconButton(
                    icon: Icon(
                      Ionicons.download_outline,
                      size: 22,
                      color: isMe ? Colors.white70 : AppColors.primaryStart,
                    ),
                    onPressed: () => onFileDownload!(att),
                    tooltip: 'Tải xuống',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bubble hiển thị bản ghi âm: nhãn "Bản ghi âm", waveform, nút phát/tạm dừng, thời lượng.
/// Dùng 1 player chung từ màn hình (playbackUrl/position/duration/isPlaying) và onPlayRequested.
class _VoiceMessageBubble extends StatefulWidget {
  const _VoiceMessageBubble({
    required this.attachment,
    required this.isMe,
    required this.isDark,
    this.playbackUrl,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isPlaying = false,
    this.onPlayRequested,
    this.onDownload,
  });

  final MessageAttachment attachment;
  final bool isMe;
  final bool isDark;
  final String? playbackUrl;
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final void Function(String url)? onPlayRequested;
  final void Function(MessageAttachment att)? onDownload;

  @override
  State<_VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<_VoiceMessageBubble> {
  static const int _waveformBars = 32;
  late List<double> _barHeights;

  @override
  void initState() {
    super.initState();
    final seed = widget.attachment.url.hashCode;
    _barHeights = List.generate(_waveformBars, (i) {
      final n = (seed + i * 31) % 100;
      return 0.25 + (n / 100) * 0.75;
    });
  }

  String get _audioUrl =>
      resolveAvatarUrl(widget.attachment.url) ?? widget.attachment.url;

  void _onTap() {
    widget.onPlayRequested?.call(_audioUrl);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final isMe = widget.isMe;
    final isActive =
        widget.playbackUrl != null && widget.playbackUrl == _audioUrl;
    final position = isActive ? widget.position : Duration.zero;
    final duration = isActive ? widget.duration : Duration.zero;
    final playing = isActive && widget.isPlaying;
    final barColor = isMe ? Colors.white : AppColors.primaryStart;
    final barInactive = (isMe ? Colors.white : AppColors.primaryStart)
        .withValues(alpha: 0.35);
    final textColor = isMe
        ? Colors.white
        : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight);
    final progress = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onPlayRequested != null ? _onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Nút phát / tạm dừng
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: barColor.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  playing ? Ionicons.pause : Ionicons.play,
                  color: barColor,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              // Waveform + nhãn + thời lượng
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Bản ghi âm',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Sóng âm (thanh cao thấp) + progress
                    SizedBox(
                      height: 28,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: List.generate(_waveformBars, (i) {
                          final h = _barHeights[i];
                          final isActive = (i / _waveformBars) <= progress;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            width: 3,
                            height: 8 + h * 16,
                            decoration: BoxDecoration(
                              color: isActive ? barColor : barInactive,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_fmt(position)} / ${_fmt(duration)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: textColor.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.onDownload != null)
                IconButton(
                  icon: Icon(
                    Ionicons.download_outline,
                    size: 22,
                    color: barColor,
                  ),
                  onPressed: () => widget.onDownload!(widget.attachment),
                  tooltip: 'Tải xuống',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with TickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            final delay = index * 0.2;
            final animation = Tween<double>(begin: 0, end: 1).animate(
              CurvedAnimation(
                parent: _controller,
                curve: Interval(delay, delay + 0.5, curve: Curves.easeInOut),
              ),
            );
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.primaryStart.withValues(
                  alpha: 0.3 + animation.value * 0.7,
                ),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}
