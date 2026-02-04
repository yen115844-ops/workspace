import 'dart:convert';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:go_router/go_router.dart';
import 'package:ionicons/ionicons.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/call_kit_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_logger.dart';
import '../data/huddle_repository.dart';

class HuddleScreen extends StatefulWidget {
  const HuddleScreen({
    super.key,
    required this.channelId,
    required this.channelName,
    this.workspaceId,
  });

  final String channelId;
  final String channelName;
  final String? workspaceId;

  @override
  State<HuddleScreen> createState() => _HuddleScreenState();
}

class _HuddleScreenState extends State<HuddleScreen> {
  final _repo = HuddleRepository();
  Room? _room;
  bool _loading = true;
  String? _error;
  bool _useFrontCamera = true;
  bool _useSpeaker = true;
  Participant? _focusedParticipant; // Participant đang được phóng to
  EventsListener<RoomEvent>? _roomEventsListener; // Lắng nghe participant left, dispose khi rời phòng

  @override
  void initState() {
    super.initState();
    _join();
  }

  @override
  void dispose() {
    _room?.removeListener(_onRoomUpdate);
    _leaveRoom();
    super.dispose();
  }

  Future<void> _join() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tokenResponse = await _repo.getToken(
        channelId: widget.channelId,
        role: 'participant',
      );
      if (!mounted) return;
      if (tokenResponse.token.isEmpty || tokenResponse.url.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'Không lấy được token LiveKit';
        });
        return;
      }
      final room = Room(
        roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
      );
      await room.connect(tokenResponse.url, tokenResponse.token);
      if (!mounted) return;
      _room = room;
      room.addListener(_onRoomUpdate);
      _roomEventsListener = room.createListener();
      _roomEventsListener!.on<ParticipantDisconnectedEvent>(_onParticipantDisconnected);
      setState(() {
        _loading = false;
        _error = null;
      });
      log.d('[Huddle] connected room=${room.name}');

      // Đánh dấu đang trong cuộc gọi channel này (tránh hiển thị incoming call trùng khi người khác gọi lại)
      callKitService.setActiveCallChannel(widget.channelId);

      // Cập nhật CallKit "connected" để bên kia thấy đã bắt máy / đã vào room
      await callKitService.setCallConnected();

      // Gửi thông báo cuộc gọi đến các members khác trong channel
      _notifyCallToChannel();
    } catch (e, st) {
      log.e('[Huddle] join error', e, st);
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e is ApiException
              ? e.message
              : (e is Exception
                    ? e.toString()
                    : 'Không thể tham gia phòng thoại');
        });
      }
    }
  }

  /// Gửi notification đến các members khác trong channel
  Future<void> _notifyCallToChannel() async {
    try {
      await _repo.notifyCall(
        channelId: widget.channelId,
        channelName: widget.channelName,
        workspaceId: widget.workspaceId,
      );
      log.d('[Huddle] Notified call to channel members');
    } catch (e) {
      // Không block nếu notify thất bại
      log.w('[Huddle] Failed to notify call: $e');
    }
  }

  void _onRoomUpdate() {
    if (mounted) setState(() {});
  }

  /// Khi có người thoát phòng (đóng app hoặc bấm rời phòng): cập nhật UI và báo "X đã rời phòng".
  void _onParticipantDisconnected(ParticipantDisconnectedEvent event) {
    final participant = event.participant;
    if (!mounted) return;
    if (_focusedParticipant?.sid == participant.sid) {
      setState(() => _focusedParticipant = null);
    }
    setState(() {});
    final name = participant.name.isNotEmpty ? participant.name : participant.identity;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$name đã rời phòng'),
        duration: const Duration(seconds: 2),
      ),
    );
    log.d('[Huddle] Participant left: $name (${participant.identity})');
  }

  Future<void> _leaveRoom() async {
    final room = _room;
    _room = null;
    await _roomEventsListener?.dispose();
    _roomEventsListener = null;
    if (room != null) {
      room.removeListener(_onRoomUpdate);
      try {
        await room.disconnect();
      } catch (_) {}
      try {
        await room.dispose();
      } catch (_) {}
    }
    // Đóng CallKit UI khi rời phòng (cả caller và callee)
    callKitService.endCall();
  }

  /// Hiển thị dialog xác nhận rời phòng, sau đó rời và pop; có SnackBar "Đã rời phòng".
  Future<void> _onLeave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(ctx).size.width - 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Ionicons.exit_outline, color: AppColors.error),
                  SizedBox(width: 12),
                  Text('Rời phòng thoại'),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Bạn có chắc muốn rời khỏi Voice room?'),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Hủy'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                    child: const Text('Rời phòng'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || confirmed != true) return;
    await _leaveRoom();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    context.pop();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Đã rời phòng thoại'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Hủy khi đang kết nối (đang loading).
  Future<void> _onCancelConnecting() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(ctx).size.width - 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Ionicons.close_circle_outline, color: AppColors.warning),
                  SizedBox(width: 12),
                  Text('Hủy kết nối'),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Bạn có muốn hủy và quay lại?'),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Không'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Có, quay lại'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || confirmed != true) return;
    await _leaveRoom();
    if (!mounted) return;
    context.pop();
  }

  Future<void> _toggleMic() async {
    final room = _room;
    final local = room?.localParticipant;
    if (local == null) return;
    try {
      await local.setMicrophoneEnabled(!(local.isMicrophoneEnabled()));
      if (mounted) setState(() {});
    } on TrackCreateException catch (e) {
      log.e('[Huddle] toggle mic', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Không thể bật mic. Kiểm tra quyền microphone trong Cài đặt.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      log.e('[Huddle] toggle mic', e);
    }
  }

  Future<void> _toggleCamera() async {
    final room = _room;
    final local = room?.localParticipant;
    if (local == null) return;
    try {
      await local.setCameraEnabled(!(local.isCameraEnabled()));
      if (mounted) setState(() {});
    } on TrackCreateException catch (e) {
      log.e('[Huddle] toggle camera', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Không thể bật camera. Kiểm tra quyền camera hoặc dùng thiết bị thật (simulator không có camera).',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      log.e('[Huddle] toggle camera', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is Exception ? e.toString() : 'Không thể bật/tắt camera',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Chuyển đổi camera trước/sau
  Future<void> _switchCamera() async {
    final room = _room;
    final local = room?.localParticipant;
    if (local == null) return;

    // Tìm video track để switch camera
    for (final pub in local.videoTrackPublications) {
      final track = pub.track;
      if (track is LocalVideoTrack) {
        try {
          // Lấy danh sách camera và chuyển đổi
          final devices = await Hardware.instance.enumerateDevices();
          final cameras = devices.where((d) => d.kind == 'videoinput').toList();
          if (cameras.length > 1) {
            // Tìm camera khác với camera hiện tại
            final newPosition = _useFrontCamera
                ? CameraPosition.back
                : CameraPosition.front;
            await track.setCameraPosition(newPosition);
          }
          setState(() {
            _useFrontCamera = !_useFrontCamera;
          });
          log.d(
            '[Huddle] switched camera to ${_useFrontCamera ? "front" : "back"}',
          );
        } catch (e) {
          log.e('[Huddle] switch camera error', e);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Không thể chuyển camera'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
        return;
      }
    }
  }

  /// Chuyển đổi giữa loa ngoài và tai nghe
  Future<void> _toggleSpeaker() async {
    try {
      _useSpeaker = !_useSpeaker;
      await Hardware.instance.setSpeakerphoneOn(_useSpeaker);
      if (mounted) setState(() {});
      log.d('[Huddle] speaker ${_useSpeaker ? "on" : "off"}');
    } catch (e) {
      log.e('[Huddle] toggle speaker error', e);
    }
  }

  /// Hiển thị bottom sheet với danh sách người tham gia
  void _showParticipantsList() {
    final room = _room;
    if (room == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final local = room.localParticipant;
        final remotes = room.remoteParticipants.values.toList();
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.8,
          expand: false,
          builder: (_, scrollController) {
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[400],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Người tham gia (${1 + remotes.length})',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      children: [
                        if (local != null)
                          _ParticipantListItem(
                            participant: local,
                            isLocal: true,
                          ),
                        ...remotes.map(
                          (p) => _ParticipantListItem(
                            participant: p,
                            isLocal: false,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Phóng to 1 participant để xem chi tiết
  void _onFocusParticipant(Participant participant) {
    setState(() {
      _focusedParticipant = participant;
    });
  }

  /// Thoát khỏi chế độ phóng to
  void _onExitFocus() {
    setState(() {
      _focusedParticipant = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.bgDark : AppColors.bgLight,
        appBar: AppBar(
          title: Text('Voice room — ${widget.channelName}'),
          leading: IconButton(
            icon: const Icon(Ionicons.close),
            onPressed: _onCancelConnecting,
          ),
        ),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Đang kết nối...'),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.bgDark : AppColors.bgLight,
        appBar: AppBar(
          title: Text('Voice room — ${widget.channelName}'),
          leading: IconButton(
            icon: const Icon(Ionicons.close),
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Ionicons.alert_circle_outline,
                  size: 48,
                  color: AppColors.warning,
                ),
                const SizedBox(height: 16),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => _join(),
                  icon: const Icon(Ionicons.refresh),
                  label: const Text('Thử lại'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final room = _room!;
    final participantCount = 1 + room.remoteParticipants.length;
    final isCameraOn = room.localParticipant?.isCameraEnabled() ?? false;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgDark : AppColors.bgLight,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Voice room — ${widget.channelName}'),
            Text(
              '$participantCount ${participantCount == 1 ? 'người' : 'người'} trong phòng',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Ionicons.close),
          onPressed: _onLeave,
        ),
        actions: [
          // Nút xem danh sách người tham gia
          IconButton(
            icon: const Icon(Ionicons.people_outline),
            onPressed: _showParticipantsList,
            tooltip: 'Danh sách người tham gia',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            ListenableBuilder(
              listenable: room,
              builder: (_, __) {
                final state = room.connectionState;
                final isReconnecting =
                    state == ConnectionState.reconnecting ||
                    state == ConnectionState.connecting;
                if (!isReconnecting) return const SizedBox.shrink();
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  color: AppColors.warning.withValues(alpha: 0.2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.warning,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        state == ConnectionState.reconnecting
                            ? 'Đang kết nối lại...'
                            : 'Đang kết nối...',
                        style: TextStyle(
                          color: AppColors.warning,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: room,
                builder: (context, _) {
                  final local = room.localParticipant;
                  final remotes = room.remoteParticipants.values.toList();

                  // Nếu có participant đang được focus, hiển thị full screen
                  if (_focusedParticipant != null) {
                    return _FocusedParticipantView(
                      participant: _focusedParticipant!,
                      isLocal: _focusedParticipant?.sid == local?.sid,
                      mirrorLocalVideo: _useFrontCamera,
                      onClose: _onExitFocus,
                      allParticipants: [if (local != null) local, ...remotes],
                      onSwitchParticipant: _onFocusParticipant,
                    );
                  }

                  // Grid view bình thường
                  return GridView.count(
                    padding: const EdgeInsets.all(8),
                    crossAxisCount: 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.8,
                    children: [
                      if (local != null)
                        _ParticipantTile(
                          participant: local,
                          isLocal: true,
                          mirrorVideo: _useFrontCamera,
                          onTap: () => _onFocusParticipant(local),
                        ),
                      ...remotes.map(
                        (p) => _ParticipantTile(
                          participant: p,
                          isLocal: false,
                          onTap: () => _onFocusParticipant(p),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Hàng điều khiển chính
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _ControlButton(
                        icon:
                            room.localParticipant?.isMicrophoneEnabled() ?? true
                            ? Ionicons.mic
                            : Ionicons.mic_off,
                        label:
                            (room.localParticipant?.isMicrophoneEnabled() ??
                                true)
                            ? 'Tắt mic'
                            : 'Bật mic',
                        onPressed: _toggleMic,
                      ),
                      const SizedBox(width: 16),
                      _ControlButton(
                        icon: isCameraOn
                            ? Ionicons.videocam
                            : Ionicons.videocam_off,
                        label: isCameraOn ? 'Tắt camera' : 'Bật camera',
                        onPressed: _toggleCamera,
                      ),
                      const SizedBox(width: 16),
                      // Nút chuyển camera (chỉ hiện khi camera bật)
                      if (isCameraOn)
                        _ControlButton(
                          icon: Ionicons.camera_reverse_outline,
                          label: _useFrontCamera ? 'Cam sau' : 'Cam trước',
                          onPressed: _switchCamera,
                        ),
                      if (isCameraOn) const SizedBox(width: 16),
                      _ControlButton(
                        icon: _useSpeaker
                            ? Ionicons.volume_high
                            : Ionicons.ear_outline,
                        label: _useSpeaker ? 'Loa ngoài' : 'Tai nghe',
                        onPressed: _toggleSpeaker,
                      ),
                      const SizedBox(width: 16),
                      _ControlButton(
                        icon: Ionicons.call,
                        label: 'Rời phòng',
                        onPressed: _onLeave,
                        isDestructive: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Parse avatar URL from LiveKit participant metadata (JSON: { "avatar": "..." }).
String? _avatarFromMetadata(String? metadata) {
  if (metadata == null || metadata.isEmpty) return null;
  try {
    final map = jsonDecode(metadata) as Map<String, dynamic>?;
    final v = map?['avatar'];
    return v is String ? v : null;
  } catch (_) {
    return null;
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({
    required this.participant,
    required this.isLocal,
    this.onTap,
    /// Chỉ mirror preview khi dùng camera trước; camera sau không mirror (tránh ngược trái/phải).
    this.mirrorVideo = false,
  });

  final Participant participant;
  final bool isLocal;
  final VoidCallback? onTap;
  final bool mirrorVideo;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Kiểm tra camera có đang bật và có video track hay không
    final isCameraOn = participant.isCameraEnabled();
    final isMicOn = participant.isMicrophoneEnabled();
    final isSpeaking = participant.isSpeaking;

    VideoTrack? videoTrack;
    if (isCameraOn) {
      for (final pub in participant.videoTrackPublications) {
        if (pub.track != null && !pub.muted) {
          videoTrack = pub.track as VideoTrack?;
          break;
        }
      }
    }

    final displayName = participant.name.isNotEmpty
        ? participant.name
        : participant.identity;
    final avatarUrl = _avatarFromMetadata(participant.metadata);
    final resolvedAvatarUrl = resolveAvatarUrl(avatarUrl);

    // Chỉ hiển thị video khi camera đang bật VÀ có video track hợp lệ
    final showVideo = isCameraOn && videoTrack != null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : AppColors.cardLight,
          borderRadius: BorderRadius.circular(12),
          // Viền xanh khi đang nói
          border: isSpeaking
              ? Border.all(color: AppColors.primaryStart, width: 3)
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(isSpeaking ? 9 : 12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (showVideo)
                VideoTrackRenderer(
                  videoTrack,
                  fit: VideoViewFit.cover,
                  mirrorMode: (isLocal && mirrorVideo)
                      ? VideoViewMirrorMode.mirror
                      : VideoViewMirrorMode.off,
                )
              else
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Avatar với animation khi đang nói
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: isSpeaking
                              ? [
                                  BoxShadow(
                                    color: AppColors.primaryStart.withValues(
                                      alpha: 0.5,
                                    ),
                                    blurRadius: 16,
                                    spreadRadius: 2,
                                  ),
                                ]
                              : null,
                        ),
                        child:
                            resolvedAvatarUrl != null &&
                                resolvedAvatarUrl.isNotEmpty
                            ? _ParticipantAvatar(
                                avatarUrl: resolvedAvatarUrl,
                                displayName: displayName,
                                isDark: isDark,
                              )
                            : _InitialsAvatar(
                                name: displayName,
                                isDark: isDark,
                              ),
                      ),
                    ],
                  ),
                ),
              // Badge trạng thái ở góc trên bên phải (camera off indicator)
              if (!isCameraOn)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Ionicons.videocam_off,
                      size: 14,
                      color: Colors.white70,
                    ),
                  ),
                ),
              // Badge "Bạn" cho local participant
              if (isLocal)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryStart,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Bạn',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              // Thanh thông tin phía dưới
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Icon mic với màu khác khi đang nói
                      Icon(
                        isMicOn ? Ionicons.mic : Ionicons.mic_off,
                        size: 14,
                        color: isSpeaking
                            ? AppColors.primaryStart
                            : Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Indicator đang nói
                      if (isSpeaking) ...[
                        const SizedBox(width: 4),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppColors.primaryStart,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // Icon phóng to ở góc trên bên phải
              if (onTap != null)
                Positioned(
                  top: 8,
                  right: isCameraOn ? 8 : 32,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Ionicons.expand_outline,
                      size: 14,
                      color: Colors.white70,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Avatar từ URL, fallback sang initials khi load lỗi.
class _ParticipantAvatar extends StatelessWidget {
  const _ParticipantAvatar({
    required this.avatarUrl,
    required this.displayName,
    required this.isDark,
  });

  final String avatarUrl;
  final String displayName;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: 96,
        height: 96,
        child: Image.network(
          avatarUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              _InitialsAvatar(name: displayName, isDark: isDark),
        ),
      ),
    );
  }
}

/// Chữ cái đầu từ tên (fallback khi không có avatar).
class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({required this.name, required this.isDark});

  final String name;
  final bool isDark;

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final s = parts.first;
      return s.length >= 2 ? s.substring(0, 2).toUpperCase() : s.toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 48,
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      child: Text(
        _initials(name),
        style: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w600,
          color: isDark
              ? AppColors.textSecondaryDark
              : AppColors.textSecondaryLight,
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          onPressed: onPressed,
          icon: Icon(icon),
          style: IconButton.styleFrom(
            backgroundColor: isDestructive
                ? AppColors.error.withValues(alpha: 0.2)
                : null,
            foregroundColor: isDestructive ? AppColors.error : null,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

/// Widget hiển thị 1 participant trong bottom sheet danh sách
class _ParticipantListItem extends StatelessWidget {
  const _ParticipantListItem({
    required this.participant,
    required this.isLocal,
  });

  final Participant participant;
  final bool isLocal;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayName = participant.name.isNotEmpty
        ? participant.name
        : participant.identity;
    final avatarUrl = _avatarFromMetadata(participant.metadata);
    final resolvedAvatarUrl = resolveAvatarUrl(avatarUrl);
    final isMicOn = participant.isMicrophoneEnabled();
    final isCameraOn = participant.isCameraEnabled();
    final isSpeaking = participant.isSpeaking;

    return ListTile(
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: isDark
                ? AppColors.surfaceDark
                : AppColors.surfaceLight,
            backgroundImage:
                resolvedAvatarUrl != null && resolvedAvatarUrl.isNotEmpty
                ? NetworkImage(resolvedAvatarUrl)
                : null,
            child: resolvedAvatarUrl == null || resolvedAvatarUrl.isEmpty
                ? Text(
                    _InitialsAvatar._initials(displayName),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
                  )
                : null,
          ),
          // Indicator đang nói
          if (isSpeaking)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.primaryStart,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? AppColors.cardDark : AppColors.cardLight,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          Flexible(child: Text(displayName, overflow: TextOverflow.ellipsis)),
          if (isLocal)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primaryStart.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Bạn',
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.primaryStart,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isMicOn ? Ionicons.mic : Ionicons.mic_off,
            size: 18,
            color: isMicOn
                ? (isSpeaking
                      ? AppColors.primaryStart
                      : AppColors.textSecondaryLight)
                : AppColors.error,
          ),
          const SizedBox(width: 12),
          Icon(
            isCameraOn ? Ionicons.videocam : Ionicons.videocam_off,
            size: 18,
            color: isCameraOn ? AppColors.textSecondaryLight : AppColors.error,
          ),
        ],
      ),
    );
  }
}

/// Widget hiển thị participant trong chế độ full screen
class _FocusedParticipantView extends StatelessWidget {
  const _FocusedParticipantView({
    required this.participant,
    required this.isLocal,
    required this.onClose,
    required this.allParticipants,
    required this.onSwitchParticipant,
    /// Mirror preview local chỉ khi camera trước; camera sau không mirror.
    this.mirrorLocalVideo = true,
  });

  final Participant participant;
  final bool isLocal;
  final VoidCallback onClose;
  final List<Participant> allParticipants;
  final void Function(Participant) onSwitchParticipant;
  final bool mirrorLocalVideo;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isCameraOn = participant.isCameraEnabled();
    final isMicOn = participant.isMicrophoneEnabled();
    final isSpeaking = participant.isSpeaking;

    VideoTrack? videoTrack;
    if (isCameraOn) {
      for (final pub in participant.videoTrackPublications) {
        if (pub.track != null && !pub.muted) {
          videoTrack = pub.track as VideoTrack?;
          break;
        }
      }
    }

    final displayName = participant.name.isNotEmpty
        ? participant.name
        : participant.identity;
    final avatarUrl = _avatarFromMetadata(participant.metadata);
    final resolvedAvatarUrl = resolveAvatarUrl(avatarUrl);
    final showVideo = isCameraOn && videoTrack != null;

    return Column(
      children: [
        // Main focused view
        Expanded(
          child: GestureDetector(
            onTap: onClose,
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? AppColors.cardDark : AppColors.cardLight,
                borderRadius: BorderRadius.circular(16),
                border: isSpeaking
                    ? Border.all(color: AppColors.primaryStart, width: 3)
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(isSpeaking ? 13 : 16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (showVideo)
                      VideoTrackRenderer(
                        videoTrack,
                        fit: VideoViewFit.contain,
                        mirrorMode: (isLocal && mirrorLocalVideo)
                            ? VideoViewMirrorMode.mirror
                            : VideoViewMirrorMode.off,
                      )
                    else
                      Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: isSpeaking
                                ? [
                                    BoxShadow(
                                      color: AppColors.primaryStart.withValues(
                                        alpha: 0.5,
                                      ),
                                      blurRadius: 24,
                                      spreadRadius: 4,
                                    ),
                                  ]
                                : null,
                          ),
                          child:
                              resolvedAvatarUrl != null &&
                                  resolvedAvatarUrl.isNotEmpty
                              ? ClipOval(
                                  child: Image.network(
                                    resolvedAvatarUrl,
                                    width: 150,
                                    height: 150,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => CircleAvatar(
                                      radius: 75,
                                      backgroundColor: isDark
                                          ? AppColors.surfaceDark
                                          : AppColors.surfaceLight,
                                      child: Text(
                                        _InitialsAvatar._initials(displayName),
                                        style: TextStyle(
                                          fontSize: 48,
                                          fontWeight: FontWeight.w600,
                                          color: isDark
                                              ? AppColors.textSecondaryDark
                                              : AppColors.textSecondaryLight,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : CircleAvatar(
                                  radius: 75,
                                  backgroundColor: isDark
                                      ? AppColors.surfaceDark
                                      : AppColors.surfaceLight,
                                  child: Text(
                                    _InitialsAvatar._initials(displayName),
                                    style: TextStyle(
                                      fontSize: 48,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? AppColors.textSecondaryDark
                                          : AppColors.textSecondaryLight,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    // Nút đóng ở góc trên bên phải
                    Positioned(
                      top: 12,
                      right: 12,
                      child: IconButton.filled(
                        onPressed: onClose,
                        icon: const Icon(Ionicons.contract_outline),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black45,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    // Thông tin participant ở dưới
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isMicOn ? Ionicons.mic : Ionicons.mic_off,
                              size: 20,
                              color: isSpeaking
                                  ? AppColors.primaryStart
                                  : Colors.white,
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              isCameraOn
                                  ? Ionicons.videocam
                                  : Ionicons.videocam_off,
                              size: 20,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                displayName + (isLocal ? ' (Bạn)' : ''),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isSpeaking)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryStart,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'Đang nói',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Thumbnail strip của các participant khác
        if (allParticipants.length > 1)
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: allParticipants.length,
              itemBuilder: (context, index) {
                final p = allParticipants[index];
                final isSelected = p.sid == participant.sid;
                final pIsLocal = index == 0; // First one is local
                return GestureDetector(
                  onTap: () => onSwitchParticipant(p),
                  child: Container(
                    width: 70,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: isSelected
                          ? Border.all(color: AppColors.primaryStart, width: 2)
                          : null,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(isSelected ? 6 : 8),
                      child: _MiniParticipantTile(
                        participant: p,
                        isLocal: pIsLocal,
                        mirrorVideo: pIsLocal ? mirrorLocalVideo : false,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Mini thumbnail cho participant trong strip
class _MiniParticipantTile extends StatelessWidget {
  const _MiniParticipantTile({
    required this.participant,
    required this.isLocal,
    this.mirrorVideo = false,
  });

  final Participant participant;
  final bool isLocal;
  final bool mirrorVideo;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isCameraOn = participant.isCameraEnabled();

    VideoTrack? videoTrack;
    if (isCameraOn) {
      for (final pub in participant.videoTrackPublications) {
        if (pub.track != null && !pub.muted) {
          videoTrack = pub.track as VideoTrack?;
          break;
        }
      }
    }

    final displayName = participant.name.isNotEmpty
        ? participant.name
        : participant.identity;
    final avatarUrl = _avatarFromMetadata(participant.metadata);
    final resolvedAvatarUrl = resolveAvatarUrl(avatarUrl);
    final showVideo = isCameraOn && videoTrack != null;

    return Container(
      color: isDark ? AppColors.cardDark : AppColors.cardLight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showVideo)
            VideoTrackRenderer(
              videoTrack,
              fit: VideoViewFit.cover,
              mirrorMode: (isLocal && mirrorVideo)
                  ? VideoViewMirrorMode.mirror
                  : VideoViewMirrorMode.off,
            )
          else
            Center(
              child: resolvedAvatarUrl != null && resolvedAvatarUrl.isNotEmpty
                  ? ClipOval(
                      child: Image.network(
                        resolvedAvatarUrl,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => CircleAvatar(
                          radius: 20,
                          backgroundColor: isDark
                              ? AppColors.surfaceDark
                              : AppColors.surfaceLight,
                          child: Text(
                            _InitialsAvatar._initials(displayName),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight,
                            ),
                          ),
                        ),
                      ),
                    )
                  : CircleAvatar(
                      radius: 20,
                      backgroundColor: isDark
                          ? AppColors.surfaceDark
                          : AppColors.surfaceLight,
                      child: Text(
                        _InitialsAvatar._initials(displayName),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondaryLight,
                        ),
                      ),
                    ),
            ),
          // Speaking indicator
          if (participant.isSpeaking)
            Positioned(
              bottom: 4,
              right: 4,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: AppColors.primaryStart,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
