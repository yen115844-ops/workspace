import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:ionicons/ionicons.dart';

import '../../../../core/network/websocket_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../core/models/models.dart';
import '../../auth/presentation/auth_cubit.dart';
import '../../notifications/data/notifications_repository.dart';
import '../data/workspace_repository.dart';

class WorkspaceListScreen extends StatefulWidget {
  const WorkspaceListScreen({super.key});

  @override
  State<WorkspaceListScreen> createState() => _WorkspaceListScreenState();
}

class _WorkspaceListScreenState extends State<WorkspaceListScreen>
    with SingleTickerProviderStateMixin {
  List<WorkspaceModel> _list = [];
  bool _loading = true;
  Object? _error;
  int _unreadCount = 0;
  final _repo = WorkspaceRepository();
  final _notifRepo = NotificationsRepository();
  final _ws = WebSocketService();
  late AnimationController _animationController;
  StreamSubscription? _notificationSubscription;
  StreamSubscription? _workspaceDeletedSubscription;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _ws.connect(); // Kết nối sớm để nhận notification real-time
    _load();
    _loadUnreadCount();
    _notificationSubscription = _ws.onNotification.listen((_) {
      if (mounted) setState(() => _unreadCount = _unreadCount + 1);
    });
    _workspaceDeletedSubscription = _ws.onWorkspaceDeleted.listen((data) {
      final wsId = data['workspaceId']?.toString();
      if (wsId != null && mounted) {
        setState(() {
          _list = _list.where((w) => w.id != wsId).toList();
        });
      }
    });
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    _workspaceDeletedSubscription?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadUnreadCount() async {
    try {
      final count = await _notifRepo.getUnreadCount();
      if (mounted) setState(() => _unreadCount = count);
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    log.d('[Workspace] load list');
    try {
      final list = await _repo.list();
      if (mounted)
        setState(() {
          _list = list;
          _loading = false;
        });
      _animationController.forward(from: 0);
      log.d('[Workspace] loaded ${list.length} items');
    } catch (e, st) {
      log.e('[Workspace] load error', e, st);
      if (mounted)
        setState(() {
          _error = e;
          _loading = false;
        });
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
                  colors: [
                    AppColors.bgDark,
                    AppColors.cardDark.withOpacity(0.5),
                  ],
                )
              : null,
          color: isDark ? null : AppColors.bgLight,
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Custom Header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Workspaces',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_list.length} workspace${_list.length != 1 ? 's' : ''}',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: isDark
                                    ? AppColors.textSecondaryDark
                                    : AppColors.textSecondaryLight,
                              ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.surfaceDark
                                : AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Ionicons.notifications_outline,
                                ),
                                onPressed: () async {
                                  await context.push('/notifications');
                                  if (mounted) {
                                    _load();
                                    _loadUnreadCount();
                                  }
                                },
                              ),
                              if (_unreadCount > 0)
                                Positioned(
                                  top: 6,
                                  right: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: const BoxDecoration(
                                      color: AppColors.error,
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(10),
                                      ),
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 18,
                                      minHeight: 18,
                                    ),
                                    child: Text(
                                      _unreadCount > 99
                                          ? '99+'
                                          : '$_unreadCount',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
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
                          child: PopupMenuButton<String>(
                            icon: const Icon(Ionicons.ellipsis_vertical),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'profile',
                                child: Row(
                                  children: const [
                                    Icon(Ionicons.person_outline, size: 20),
                                    SizedBox(width: 12),
                                    Text('Hồ sơ & Cài đặt'),
                                  ],
                                ),
                              ),
                              const PopupMenuDivider(),
                              PopupMenuItem(
                                value: 'logout',
                                child: Row(
                                  children: const [
                                    Icon(
                                      Ionicons.log_out_outline,
                                      size: 20,
                                      color: AppColors.error,
                                    ),
                                    SizedBox(width: 12),
                                    Text(
                                      'Đăng xuất',
                                      style: TextStyle(color: AppColors.error),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            onSelected: (value) async {
                              if (value == 'profile') {
                                await context.push('/profile');
                                if (mounted) _load();
                              } else if (value == 'logout') {
                                await context.read<AuthCubit>().logout();
                                if (context.mounted) {
                                  log.nav('workspaces', '/login');
                                  context.go('/login');
                                }
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Content
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
                              'Đang tải...',
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
                    : _buildWorkspaceList(isDark),
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
                  onTap: () => _showCreateDialog(context),
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
              'Không thể tải dữ liệu',
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
                Ionicons.business_outline,
                size: 64,
                color: AppColors.primaryStart,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Chưa có workspace nào',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Tạo workspace đầu tiên để bắt đầu\nlàm việc cùng nhau',
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
                  onTap: () => _showCreateDialog(context),
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
                          'Tạo workspace',
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

  Widget _buildWorkspaceList(bool isDark) {
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primaryStart,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: _list.length,
        itemBuilder: (context, index) {
          final w = _list[index];
          return AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              final delay = index * 0.1;
              final start = delay.clamp(0.0, 1.0);
              final end = (delay + 0.4).clamp(0.0, 1.0);
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
            child: _WorkspaceCard(
              workspace: w,
              isDark: isDark,
              onTap: () async {
                log.nav('workspaces', '/workspaces/${w.id}');
                await context.push('/workspaces/${w.id}', extra: w.name);
                if (mounted) _load();
              },
              onDelete: () => _deleteWorkspace(w),
              onRename: (workspace, newName) => _renameWorkspace(workspace, newName),
            ),
          );
        },
      ),
    );
  }

  Future<void> _renameWorkspace(WorkspaceModel workspace, String newName) async {
    if (newName.trim().isEmpty) return;
    try {
      await _repo.update(workspace.id, name: newName.trim());
      log.d('[Workspace] renamed: ${workspace.name} -> $newName');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã đổi tên workspace'), backgroundColor: AppColors.success),
        );
        _load();
      }
    } catch (e) {
      log.e('[Workspace] rename error', e);
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

  Future<void> _deleteWorkspace(WorkspaceModel workspace) async {
    try {
      await _repo.delete(workspace.id);
      log.d('[Workspace] deleted: ${workspace.name}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã xóa workspace "${workspace.name}"'),
            backgroundColor: AppColors.success,
          ),
        );
        _load();
      }
    } catch (e) {
      log.e('[Workspace] delete error', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể xóa workspace: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showCreateDialog(BuildContext context) {
    final nameController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
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
                      Ionicons.business_outline,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Tạo workspace mới',
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
                  labelText: 'Tên workspace',
                  hintText: 'Ví dụ: Marketing Team',
                  prefixIcon: const Icon(Ionicons.text_outline),
                ),
                autofocus: true,
                onSubmitted: (_) =>
                    _createWorkspace(ctx, nameController.text.trim()),
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
                          onTap: () =>
                              _createWorkspace(ctx, nameController.text.trim()),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            alignment: Alignment.center,
                            child: const Text(
                              'Tạo workspace',
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
    );
  }

  Future<void> _createWorkspace(BuildContext ctx, String name) async {
    if (name.isEmpty) return;
    Navigator.pop(ctx);
    try {
      await _repo.create(name);
      log.d('[Workspace] created: $name');
      _load();
    } catch (e) {
      if (ctx.mounted)
        ScaffoldMessenger.of(
          ctx,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }
}

class _WorkspaceCard extends StatelessWidget {
  const _WorkspaceCard({
    required this.workspace,
    required this.isDark,
    required this.onTap,
    required this.onDelete,
    required this.onRename,
  });

  final WorkspaceModel workspace;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final void Function(WorkspaceModel workspace, String newName) onRename;

  Color _getAvatarColor(String name) {
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

  static void _showRenameDialog(
    BuildContext context,
    WorkspaceModel workspace,
    void Function(WorkspaceModel, String) onRename,
  ) {
    final controller = TextEditingController(text: workspace.name);
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
                  Icon(Ionicons.business_outline, color: AppColors.primaryStart),
                  SizedBox(width: 12),
                  Text('Đổi tên workspace'),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: 'Tên workspace',
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
                    onPressed: () {
                      final newName = controller.text.trim();
                      if (newName.isEmpty) return;
                      Navigator.pop(ctx);
                      onRename(workspace, newName);
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

  @override
  Widget build(BuildContext context) {
    final avatarColor = _getAvatarColor(workspace.name);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? AppColors.surfaceDark.withOpacity(0.5)
              : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: () => _showOptionsMenu(context),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [avatarColor, avatarColor.withOpacity(0.7)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      workspace.name.isNotEmpty
                          ? workspace.name[0].toUpperCase()
                          : 'W',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        workspace.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (workspace.slug != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Ionicons.link_outline,
                              size: 14,
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                workspace.slug!,
                                style: TextStyle(
                                  color: isDark
                                      ? AppColors.textSecondaryDark
                                      : AppColors.textSecondaryLight,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.surfaceDark
                        : AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Ionicons.chevron_forward,
                    size: 20,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showOptionsMenu(BuildContext context) {
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
                        gradient: LinearGradient(
                          colors: [
                            _getAvatarColor(workspace.name),
                            _getAvatarColor(workspace.name).withOpacity(0.7),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          workspace.name.isNotEmpty
                              ? workspace.name[0].toUpperCase()
                              : 'W',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        workspace.name,
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
                title: const Text('Đổi tên workspace'),
                subtitle: const Text('Đặt tên mới cho workspace'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showRenameDialog(ctx, workspace, onRename);
                },
              ),
              ListTile(
                leading: const Icon(
                  Ionicons.trash_outline,
                  color: AppColors.error,
                ),
                title: const Text(
                  'Xóa workspace',
                  style: TextStyle(color: AppColors.error),
                ),
                subtitle: const Text('Xóa vĩnh viễn workspace này'),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDelete(context);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
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
                  Text('Xóa workspace?'),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Bạn có chắc muốn xóa workspace "${workspace.name}"?\n\n'
                'Tất cả channels, tin nhắn và dữ liệu trong workspace sẽ bị xóa vĩnh viễn.',
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
                      onDelete();
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
}
