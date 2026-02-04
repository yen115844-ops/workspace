import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ionicons/ionicons.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/safe_navigation.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/notifications_repository.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationsRepository _repo = NotificationsRepository();
  List<NotificationModel> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _repo.getNotifications();
      if (mounted) {
        setState(() {
          _items = list;
          _loading = false;
        });
        // Đã mở màn hình = đã xem → đánh dấu tất cả đã đọc
        if (list.any((n) => !n.isRead)) {
          _markAllAsReadQuiet();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// Gọi API đánh dấu tất cả đã đọc và cập nhật UI (không reload list).
  Future<void> _markAllAsReadQuiet() async {
    try {
      await _repo.markAllAsRead();
      if (mounted) {
        setState(() {
          _items = _items
              .map((n) => n.isRead
                  ? n
                  : NotificationModel(
                      id: n.id,
                      type: n.type,
                      title: n.title,
                      body: n.body,
                      data: n.data,
                      readAt: DateTime.now(),
                      createdAt: n.createdAt,
                    ))
              .toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _markAsRead(NotificationModel n) async {
    if (n.isRead) return;
    try {
      await _repo.markAsRead(n.id);
      if (mounted) {
        setState(() {
          final i = _items.indexWhere((x) => x.id == n.id);
          if (i != -1) {
            _items[i] = NotificationModel(
              id: n.id,
              type: n.type,
              title: n.title,
              body: n.body,
              data: n.data,
              readAt: DateTime.now(),
              createdAt: n.createdAt,
            );
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _markAllAsRead() async {
    try {
      await _repo.markAllAsRead();
      if (mounted) _load();
    } catch (_) {}
  }

  void _onTapNotification(NotificationModel n) async {
    await _markAsRead(n);
    final data = n.data;
    if (data == null) return;
    final workspaceId = data['workspaceId']?.toString();
    final channelId = data['channelId']?.toString();
    final taskId = data['taskId']?.toString();

    if (!mounted) return;
    if (workspaceId != null && taskId != null &&
        (n.type == 'task_assigned' || n.type == 'task_due_soon' || n.type == 'task_overdue')) {
      context.pushReplacement('/workspaces/$workspaceId/tasks/$taskId');
      return;
    }
    if (workspaceId != null && channelId != null) {
      context.pushReplacement('/workspaces/$workspaceId/channels/$channelId',
          extra: data['channelName']?.toString() ?? 'Channel');
    } else if (workspaceId != null) {
      context.pushReplacement('/workspaces/$workspaceId', extra: data['workspaceName']?.toString());
    }
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
                  colors: [AppColors.bgDark, AppColors.cardDark.withValues(alpha: 0.5)],
                )
              : null,
          color: isDark ? null : AppColors.bgLight,
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => context.maybePopOrGo(SafeNavigation.defaultFallback),
                      icon: const Icon(Ionicons.arrow_back),
                      style: IconButton.styleFrom(
                        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Thông báo',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                    if (_items.any((n) => !n.isRead))
                      TextButton(
                        onPressed: _markAllAsRead,
                        child: const Text('Đánh dấu đã đọc'),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: _buildContent(isDark),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(bool isDark) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorState(message: _error!, onRetry: _load);
    }
    if (_items.isEmpty) {
      return EmptyState(
        icon: Ionicons.notifications_outline,
        title: 'Chưa có thông báo',
        subtitle: 'Thông báo mới sẽ hiển thị tại đây',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final n = _items[index];
          return _buildNotificationTile(n, isDark);
        },
      ),
    );
  }

  Widget _buildNotificationTile(NotificationModel n, bool isDark) {
    IconData icon;
    Color iconColor;
    switch (n.type) {
      case 'workspace_invited':
        icon = Ionicons.business_outline;
        iconColor = AppColors.primaryStart;
        break;
      case 'channel_added':
        icon = Ionicons.chatbubbles_outline;
        iconColor = AppColors.success;
        break;
      case 'task_assigned':
        icon = Ionicons.person_add_outline;
        iconColor = AppColors.info;
        break;
      case 'task_due_soon':
        icon = Ionicons.time_outline;
        iconColor = AppColors.warning;
        break;
      case 'task_overdue':
        icon = Ionicons.alert_circle_outline;
        iconColor = AppColors.error;
        break;
      default:
        icon = Ionicons.notifications_outline;
        iconColor = AppColors.info;
    }

    return ListTile(
      onTap: () => _onTapNotification(n),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor, size: 24),
      ),
      title: Text(
        n.title,
        style: TextStyle(
          fontWeight: n.isRead ? FontWeight.normal : FontWeight.w600,
        ),
      ),
      subtitle: n.body != null
          ? Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                n.body!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                ),
              ),
            )
          : null,
      trailing: n.isRead
          ? null
          : Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.primaryStart,
                shape: BoxShape.circle,
              ),
            ),
    );
  }
}
