import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ionicons/ionicons.dart';

import '../../../../core/network/websocket_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../../core/utils/safe_navigation.dart';
import '../../../core/models/models.dart';
import '../../workspace/data/workspace_repository.dart';
import '../data/channel_repository.dart';

class ChannelListScreen extends StatefulWidget {
  const ChannelListScreen({
    super.key,
    required this.workspaceId,
    this.workspaceName,
  });

  final String workspaceId;
  final String? workspaceName;

  @override
  State<ChannelListScreen> createState() => _ChannelListScreenState();
}

class _ChannelListScreenState extends State<ChannelListScreen>
    with SingleTickerProviderStateMixin {
  List<ChannelModel> _list = [];
  bool _loading = true;
  Object? _error;
  final _repo = ChannelRepository();
  final _workspaceRepo = WorkspaceRepository();
  final _ws = WebSocketService();
  late AnimationController _animationController;
  StreamSubscription? _channelCreatedSubscription;
  StreamSubscription? _addedToChannelSubscription;
  StreamSubscription? _channelDeletedSubscription;
  StreamSubscription? _workspaceDeletedSubscription;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _ws.connect();
    _ws.joinWorkspace(widget.workspaceId);
    _channelCreatedSubscription = _ws.onChannelCreated.listen((data) {
      final wsId = data['workspaceId']?.toString();
      if (wsId != widget.workspaceId || !mounted) return;
      _applyChannelEvent(data);
    });
    _addedToChannelSubscription = _ws.onAddedToChannel.listen((data) {
      final wsId = data['workspaceId']?.toString();
      if (wsId != widget.workspaceId || !mounted) return;
      _applyAddedToChannelEvent(data);
    });
    _channelDeletedSubscription = _ws.onChannelDeleted.listen((data) {
      final wsId = data['workspaceId']?.toString();
      final channelId = data['channelId']?.toString();
      if (wsId != widget.workspaceId || !mounted) return;
      _applyChannelDeletedEvent(channelId);
    });
    _workspaceDeletedSubscription = _ws.onWorkspaceDeleted.listen((data) {
      final wsId = data['workspaceId']?.toString();
      if (wsId != widget.workspaceId || !mounted) return;
      _showDeletedAlert('Workspace đã bị xóa');
    });
    _load();
  }

  @override
  void dispose() {
    _channelCreatedSubscription?.cancel();
    _addedToChannelSubscription?.cancel();
    _channelDeletedSubscription?.cancel();
    _workspaceDeletedSubscription?.cancel();
    _ws.leaveWorkspace(widget.workspaceId);
    _animationController.dispose();
    super.dispose();
  }

  void _applyChannelDeletedEvent(String? channelId) {
    if (channelId == null || !mounted) return;
    setState(() {
      _list = _list.where((c) => c.id != channelId).toList();
    });
  }

  void _showDeletedAlert(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
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
                      context.go('/workspaces');
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

  void _applyChannelEvent(Map<String, dynamic> data) {
    if (!mounted) return;
    try {
      final channel = ChannelModel.fromJson(Map<String, dynamic>.from(data));
      if (_list.any((c) => c.id == channel.id)) return;
      setState(() => _list = [..._list, channel]);
    } catch (_) {
      if (mounted) _load();
    }
  }

  void _applyAddedToChannelEvent(Map<String, dynamic> data) {
    if (!mounted) return;
    final id = data['channelId']?.toString();
    final name = data['channelName']?.toString() ?? '';
    final wsId = data['workspaceId']?.toString() ?? widget.workspaceId;
    if (id == null || id.isEmpty) return;
    if (_list.any((c) => c.id == id)) return;
    setState(() {
      _list = [
        ..._list,
        ChannelModel(id: id, name: name, type: 'private', workspaceId: wsId),
      ];
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    log.d('[Channel] load list workspace=${widget.workspaceId}');
    try {
      final list = await _repo.listByWorkspace(widget.workspaceId);
      if (mounted)
        setState(() {
          _list = list;
          _loading = false;
        });
      _animationController.forward(from: 0);
      log.d('[Channel] loaded ${list.length} items');
    } catch (e, st) {
      log.e('[Channel] load error', e, st);
      if (mounted)
        setState(() {
          _error = e;
          _loading = false;
        });
    }
  }

  /// Bottom sheet chọn workspace khác. Điều hướng -> dispose leaveWorkspace, màn mới joinWorkspace.
  void _showWorkspaceSwitcher() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    List<WorkspaceModel> workspaces = [];
    try {
      workspaces = await _workspaceRepo.list();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không tải được danh sách workspace: $e'), backgroundColor: AppColors.error),
        );
      }
      return;
    }
    if (!mounted) return;
    if (workspaces.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có workspace nào')),
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
                    color: isDark ? AppColors.surfaceDark : Colors.grey.shade300,
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
                      child: const Icon(Ionicons.business_outline, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Đổi workspace',
                      style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: workspaces.length,
                  itemBuilder: (context, index) {
                    final w = workspaces[index];
                    final isCurrent = w.id == widget.workspaceId;
                    return ListTile(
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: isCurrent
                              ? AppColors.primaryGradient
                              : LinearGradient(
                                  colors: [
                                    AppColors.primaryStart.withOpacity(0.6),
                                    AppColors.primaryEnd.withOpacity(0.6),
                                  ],
                                ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            w.name.isNotEmpty ? w.name[0].toUpperCase() : 'W',
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      title: Text(
                        w.name,
                        style: TextStyle(
                          fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      subtitle: isCurrent ? const Text('Đang mở', style: TextStyle(fontSize: 12)) : null,
                      trailing: isCurrent ? const Icon(Ionicons.checkmark_circle, color: AppColors.success) : const Icon(Ionicons.chevron_forward),
                      onTap: () {
                        Navigator.pop(ctx);
                        if (w.id == widget.workspaceId) return;
                        log.nav('channels', 'switch workspace to /workspaces/${w.id}');
                        context.go('/workspaces/${w.id}', extra: w.name);
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.bgDark,
                    AppColors.cardDark.withOpacity(0.5),
                  ],
                )
              : null,
          color: isDark ? null : AppColors.bgLight,
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Custom Header
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () =>
                          context.maybePopOrGo(SafeNavigation.defaultFallback),
                      icon: const Icon(Ionicons.arrow_back),
                      style: IconButton.styleFrom(
                        backgroundColor: isDark
                            ? AppColors.surfaceDark
                            : AppColors.surfaceLight,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.workspaceName ?? 'Channels',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${_list.length} channel${_list.length != 1 ? 's' : ''}',
                            style: TextStyle(
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Đổi workspace (switch) — socket leave/join tự động khi dispose/initState
                    Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.surfaceDark
                            : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        icon: const Icon(Ionicons.business_outline),
                        tooltip: 'Đổi workspace',
                        onPressed: _showWorkspaceSwitcher,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.surfaceDark
                            : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        icon: const Icon(Ionicons.people_outline),
                        tooltip: 'Thành viên',
                        onPressed: () {
                          log.nav(
                            'channels',
                            '/workspaces/${widget.workspaceId}/members',
                          );
                          context.push(
                            '/workspaces/${widget.workspaceId}/members',
                            extra: widget.workspaceName ?? 'Workspace',
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.surfaceDark
                            : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        icon: const Icon(Ionicons.checkbox_outline),
                        tooltip: 'Tasks',
                        onPressed: () {
                          log.nav(
                            'channels',
                            '/workspaces/${widget.workspaceId}/tasks',
                          );
                          context.push(
                            '/workspaces/${widget.workspaceId}/tasks',
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.surfaceDark
                            : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        icon: const Icon(Ionicons.search_outline),
                        tooltip: 'Tìm kiếm',
                        onPressed: () {
                          context.push(
                            '/search?workspaceId=${widget.workspaceId}',
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // Channel sections
              Expanded(
                child: _loading
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColors.surfaceDark
                                    : AppColors.surfaceLight,
                                shape: BoxShape.circle,
                              ),
                              child: const CircularProgressIndicator(
                                strokeWidth: 3,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Đang tải channels...',
                              style: TextStyle(
                                color: isDark
                                    ? AppColors.textSecondaryDark
                                    : AppColors.textSecondaryLight,
                              ),
                            ),
                          ],
                        ),
                      )
                    : _error != null
                    ? _buildErrorState(isDark)
                    : _list.isEmpty
                    ? _buildEmptyState(context, isDark)
                    : _buildChannelList(isDark),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: !_loading && _error == null
          ? Container(
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryStart.withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _showCreateChannel(context),
                  borderRadius: BorderRadius.circular(16),
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Icon(Ionicons.add, color: Colors.white, size: 28),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildErrorState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Ionicons.cloud_offline_outline,
                size: 48,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Không thể tải channels',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '$_error',
              style: TextStyle(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Ionicons.refresh_outline),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient.scale(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Ionicons.chatbubbles_outline,
                size: 64,
                color: AppColors.primaryStart,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Chưa có channel nào',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Tạo channel đầu tiên để bắt đầu\ntrò chuyện với team',
              style: TextStyle(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Container(
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryStart.withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _showCreateChannel(context),
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Ionicons.add_circle_outline, color: Colors.white),
                        SizedBox(width: 12),
                        Text(
                          'Tạo channel',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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

  Widget _buildChannelList(bool isDark) {
    final publicChannels = _list.where((ch) => ch.type != 'private').toList();
    final privateChannels = _list.where((ch) => ch.type == 'private').toList();

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primaryStart,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          // Public channels section
          if (publicChannels.isNotEmpty) ...[
            _buildSectionHeader(
              'Channels',
              Ionicons.chatbubble_outline,
              isDark,
            ),
            const SizedBox(height: 8),
            ...publicChannels.asMap().entries.map(
              (entry) =>
                  _buildChannelItem(entry.value, entry.key, isDark, false),
            ),
            const SizedBox(height: 24),
          ],

          // Private channels section
          if (privateChannels.isNotEmpty) ...[
            _buildSectionHeader(
              'Tin nhắn riêng',
              Ionicons.lock_closed_outline,
              isDark,
            ),
            const SizedBox(height: 8),
            ...privateChannels.asMap().entries.map(
              (entry) =>
                  _buildChannelItem(entry.value, entry.key, isDark, true),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, bool isDark) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: isDark
              ? AppColors.textSecondaryDark
              : AppColors.textSecondaryLight,
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondaryLight,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildChannelItem(
    ChannelModel channel,
    int index,
    bool isDark,
    bool isPrivate,
  ) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        final delay = index * 0.08;
        final start = delay.clamp(0.0, 1.0);
        final end = (delay + 0.3).clamp(0.0, 1.0);
        final animation = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Interval(start, end, curve: Curves.easeOutCubic),
          ),
        );
        return Transform.translate(
          offset: Offset(20 * (1 - animation.value), 0),
          child: Opacity(opacity: animation.value, child: child),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark
                ? AppColors.surfaceDark.withOpacity(0.5)
                : Colors.grey.shade200,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              log.nav(
                'channels',
                '/workspaces/${widget.workspaceId}/channels/${channel.id}',
              );
              context.push(
                '/workspaces/${widget.workspaceId}/channels/${channel.id}',
                extra: channel.name,
              );
            },
            onLongPress: () => _showChannelOptions(context, channel, isPrivate),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
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
                          : AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isPrivate ? Ionicons.lock_closed : Ionicons.chatbubble,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isPrivate ? channel.name : '# ${channel.name}',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isPrivate ? 'Kênh riêng tư' : 'Kênh công khai',
                          style: TextStyle(
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondaryLight,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Ionicons.chevron_forward,
                    size: 18,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showChannelOptions(
    BuildContext context,
    ChannelModel channel,
    bool isPrivate,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceDark : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Container(
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
                            : AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isPrivate ? Ionicons.lock_closed : Ionicons.chatbubble,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        isPrivate ? channel.name : '# ${channel.name}',
                        style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Ionicons.pencil_outline, color: AppColors.primaryStart),
                title: const Text('Đổi tên channel'),
                subtitle: const Text('Đặt tên mới cho channel'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showRenameChannelDialog(context, channel);
                },
              ),
              ListTile(
                leading: const Icon(
                  Ionicons.trash_outline,
                  color: AppColors.error,
                ),
                title: const Text(
                  'Xóa channel',
                  style: TextStyle(color: AppColors.error),
                ),
                subtitle: const Text('Xóa vĩnh viễn channel này'),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDeleteChannel(context, channel);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showRenameChannelDialog(BuildContext context, ChannelModel channel) {
    final controller = TextEditingController(text: channel.name);
    showDialog<void>(
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
                  Icon(Ionicons.pricetag_outline, color: AppColors.primaryStart),
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
                      await _renameChannel(channel, newName);
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

  Future<void> _renameChannel(ChannelModel channel, String newName) async {
    try {
      await _repo.update(channel.id, name: newName);
      log.d('[Channel] renamed: ${channel.name} -> $newName');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã đổi tên channel'), backgroundColor: AppColors.success),
        );
        _load();
      }
    } catch (e) {
      log.e('[Channel] rename error', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể đổi tên: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _confirmDeleteChannel(BuildContext context, ChannelModel channel) {
    showDialog(
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
                  Icon(Ionicons.warning_outline, color: AppColors.error),
                  SizedBox(width: 12),
                  Text('Xóa channel?'),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Bạn có chắc muốn xóa channel "${channel.name}"?\n\n'
                'Tất cả tin nhắn trong channel sẽ bị xóa vĩnh viễn.',
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
                      Navigator.pop(ctx);
                      _deleteChannel(channel);
                    },
                    style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                    child: const Text('Xóa'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteChannel(ChannelModel channel) async {
    try {
      await _repo.delete(channel.id);
      log.d('[Channel] deleted: ${channel.name}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã xóa channel "${channel.name}"'),
            backgroundColor: AppColors.success,
          ),
        );
        _load();
      }
    } catch (e) {
      log.e('[Channel] delete error', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể xóa channel: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showCreateChannel(BuildContext context) {
    final nameController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    bool isPrivate = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          decoration: BoxDecoration(
            color: isDark ? AppColors.cardDark : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Handle bar
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
                const SizedBox(height: 24),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Ionicons.chatbubbles_outline,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Tạo channel mới',
                      style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Tên channel',
                    hintText: 'Ví dụ: general',
                    prefixIcon: const Icon(Ionicons.text_outline),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),

                // Private toggle
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.surfaceDark
                        : AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Ionicons.lock_closed_outline,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Channel riêng tư',
                              style: Theme.of(ctx).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              'Chỉ thành viên được mời mới có thể xem',
                              style: TextStyle(
                                color: isDark
                                    ? AppColors.textSecondaryDark
                                    : AppColors.textSecondaryLight,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: isPrivate,
                        onChanged: (value) =>
                            setModalState(() => isPrivate = value),
                        activeColor: AppColors.primaryStart,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Hủy'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () async {
                              final name = nameController.text.trim();
                              if (name.isEmpty) return;
                              Navigator.pop(ctx);
                              try {
                                await _repo.create(
                                  widget.workspaceId,
                                  name,
                                  type: isPrivate ? 'private' : 'public',
                                );
                                log.d(
                                  '[Channel] created: $name (${isPrivate ? "private" : "public"})',
                                );
                                _load();
                              } catch (e) {
                                if (ctx.mounted)
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(content: Text('Lỗi: $e')),
                                  );
                              }
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              alignment: Alignment.center,
                              child: const Text(
                                'Tạo channel',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
