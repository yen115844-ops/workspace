import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ionicons/ionicons.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/websocket_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/safe_navigation.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/models/models.dart';
import '../../auth/presentation/auth_cubit.dart';
import '../../workspace/data/workspace_repository.dart';
import '../data/task_repository.dart';

class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen({
    super.key,
    required this.workspaceId,
    required this.taskId,
    this.task,
  });

  final String workspaceId;
  final String taskId;
  final TaskModel? task;

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> with SingleTickerProviderStateMixin {
  TaskModel? _task;
  final _repo = TaskRepository();
  final _wsRepo = WorkspaceRepository();
  final _ws = WebSocketService();
  StreamSubscription<Map<String, dynamic>>? _taskCommentSubscription;
  bool _loading = false;
  bool _initialLoading = false;
  bool _commentsLoading = false;
  List<TaskComment> _comments = [];
  late TabController _tabController;
  final _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _task = widget.task;
    _tabController = TabController(length: 2, vsync: this);
    _ws.connect();
    _ws.joinWorkspace(widget.workspaceId);
    _taskCommentSubscription = _ws.onTaskComment.listen((data) {
      final taskId = data['taskId']?.toString();
      if (taskId != widget.taskId || !mounted) return;
      final type = data['type'] as String?;
      if (type == 'added') {
        final raw = data['comment'];
        if (raw != null && raw is Map) {
          try {
            final comment = TaskComment.fromJson(Map<String, dynamic>.from(raw));
            if (!_comments.any((c) => c.id == comment.id)) {
              setState(() => _comments.add(comment));
            }
          } catch (_) {}
        }
      } else if (type == 'deleted') {
        final commentId = data['commentId']?.toString();
        if (commentId != null) {
          setState(() => _comments.removeWhere((c) => c.id == commentId));
        }
      }
    });
    if (_task != null) {
      _loadComments();
    } else {
      _loadTask();
    }
  }

  Future<void> _loadTask() async {
    setState(() => _initialLoading = true);
    try {
      final task = await _repo.get(widget.taskId);
      if (mounted) {
        setState(() {
          _task = task;
          _initialLoading = false;
        });
        _loadComments();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _initialLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không tải được task: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  void dispose() {
    _taskCommentSubscription?.cancel();
    _ws.leaveWorkspace(widget.workspaceId);
    _tabController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    final taskId = _task?.id ?? widget.taskId;
    setState(() => _commentsLoading = true);
    try {
      final comments = await _repo.getComments(taskId);
      setState(() => _comments = comments);
    } catch (e) {
      // Ignore error for now, comments may not be supported
    } finally {
      if (mounted) setState(() => _commentsLoading = false);
    }
  }

  Future<void> _updateTask({String? columnId, String? priority, DateTime? dueDate, String? title, String? description, String? assigneeId, bool clearAssignee = false}) async {
    if (_task == null) return;
    setState(() => _loading = true);
    try {
      final updated = await _repo.update(
        _task!.id,
        title: title,
        description: description,
        columnId: columnId,
        priority: priority,
        dueDate: dueDate,
        assigneeId: assigneeId,
        clearAssignee: clearAssignee,
      );
      setState(() => _task = updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã cập nhật task'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteTask(TaskModel task) async {
    setState(() => _loading = true);
    try {
      await _repo.delete(task.id);
      if (mounted) {
        context.maybePopOrGo('/workspaces/${widget.workspaceId}/tasks', null);
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteComment(TaskComment comment) async {
    try {
      await _repo.deleteComment(_task!.id, comment.id);
      setState(() => _comments.removeWhere((c) => c.id == comment.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xóa bình luận'), backgroundColor: AppColors.success),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    } catch (_) {}
  }

  Future<void> _addComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty || _task == null) return;

    setState(() => _commentsLoading = true);
    try {
      final comment = await _repo.addComment(_task!.id, content);
      setState(() {
        _comments.add(comment);
        _commentController.clear();
      });
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    } catch (e) {
      // Ignore error
    } finally {
      if (mounted) setState(() => _commentsLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_task == null || _initialLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Đang tải task...'),
            ],
          ),
        ),
      );
    }

    final task = _task!;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.bgDark, AppColors.cardDark.withOpacity(0.5)],
                )
              : null,
          color: isDark ? null : AppColors.bgLight,
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => context.maybePopOrGo(
                        '/workspaces/${widget.workspaceId}/tasks',
                        task,
                      ),
                      icon: const Icon(Ionicons.arrow_back),
                      style: IconButton.styleFrom(
                        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                      ),
                    ),
                    const Spacer(),
                    if (_loading) 
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => _showEditDialog(context, task),
                      icon: const Icon(Ionicons.create_outline),
                      style: IconButton.styleFrom(
                        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => _showDeleteConfirmation(context, task),
                      icon: const Icon(Ionicons.trash_outline, color: AppColors.error),
                      style: IconButton.styleFrom(
                        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                      ),
                    ),
                  ],
                ),
              ),

              // Title and priority
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            task.title,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                        _buildPriorityBadge(task, isDark),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Tabs
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabController,
                  labelColor: AppColors.primaryStart,
                  unselectedLabelColor: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  indicator: BoxDecoration(
                    color: AppColors.primaryStart.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(text: 'Chi tiết'),
                    Tab(text: 'Bình luận'),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildDetailsTab(task, isDark),
                    _buildCommentsTab(task, isDark),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPriorityBadge(TaskModel task, bool isDark) {
    final priorityColors = {
      'low': Colors.grey,
      'normal': AppColors.info,
      'high': AppColors.warning,
      'urgent': AppColors.error,
    };

    final priorityLabels = {
      'low': 'Thấp',
      'normal': 'Bình thường',
      'high': 'Cao',
      'urgent': 'Khẩn cấp',
    };

    final color = priorityColors[task.priority] ?? Colors.grey;
    final label = priorityLabels[task.priority] ?? 'Bình thường';

    return GestureDetector(
      onTap: () => _showPriorityPicker(context, task),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Ionicons.flag, color: color, size: 14),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsTab(TaskModel task, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status badge
          _buildStatusSection(task, isDark),
          const SizedBox(height: 24),

          // Description
          _buildDescriptionSection(task, isDark),
          const SizedBox(height: 24),

          // Due date
          _buildDueDateSection(task, isDark),
          const SizedBox(height: 24),

          // Assignee
          _buildAssigneeSection(task, isDark),

          // Timestamps
          if (task.createdAt != null || task.updatedAt != null) ...[
            const SizedBox(height: 24),
            _buildTimestampsSection(task, isDark),
          ],
        ],
      ),
    );
  }

  Widget _buildCommentsTab(TaskModel task, bool isDark) {
    return Column(
      children: [
        // Comment input
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? AppColors.cardDark : AppColors.cardLight,
            border: Border(
              bottom: BorderSide(
                color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentController,
                  decoration: InputDecoration(
                    hintText: 'Viết bình luận...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  maxLines: null,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  onPressed: _commentsLoading ? null : _addComment,
                  icon: _commentsLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Ionicons.send, color: Colors.white),
                ),
              ),
            ],
          ),
        ),

        // Comments list
        Expanded(
          child: _comments.isEmpty
              ? EmptyState(
                  icon: Ionicons.chatbubble_outline,
                  title: 'Chưa có bình luận',
                  subtitle: 'Hãy là người đầu tiên bình luận',
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _comments.length,
                  itemBuilder: (context, index) {
                    final comment = _comments[index];
                    return _buildCommentCard(task, comment, isDark);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCommentCard(TaskModel task, TaskComment comment, bool isDark) {
    final authState = context.read<AuthCubit>().state;
    final currentUserId = authState is AuthAuthenticated ? authState.user.id : null;
    final canDelete = currentUserId != null && comment.authorId == currentUserId;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (resolveAvatarUrl(comment.authorAvatar) != null)
                CircleAvatar(
                  radius: 16,
                  backgroundImage: NetworkImage(resolveAvatarUrl(comment.authorAvatar)!),
                )
              else
                UserAvatar(name: comment.authorName ?? 'User', size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comment.authorName ?? 'Người dùng',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      _formatDateTime(comment.createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                      ),
                    ),
                  ],
                ),
              ),
              if (canDelete)
                IconButton(
                  icon: Icon(Ionicons.trash_outline, size: 18, color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
                  onPressed: () {
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
                              const Text('Xóa bình luận'),
                              const SizedBox(height: 16),
                              const Text('Bạn có chắc muốn xóa bình luận này?'),
                              const SizedBox(height: 24),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
                                  FilledButton(
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _deleteComment(comment);
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
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(comment.content),
        ],
      ),
    );
  }

  Widget _buildStatusSection(TaskModel task, bool isDark) {
    final statusColors = {
      'todo': Colors.grey,
      'in_progress': AppColors.info,
      'done': AppColors.success,
    };

    final statusLabels = {
      'todo': 'Chờ xử lý',
      'in_progress': 'Đang làm',
      'done': 'Hoàn thành',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Trạng thái',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: statusLabels.entries.map((entry) {
            final isSelected = task.columnId == entry.key;
            final color = statusColors[entry.key] ?? Colors.grey;

            return GestureDetector(
              onTap: _loading ? null : () => _updateTask(columnId: entry.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? color.withOpacity(0.2) : (isDark ? AppColors.surfaceDark : AppColors.surfaceLight),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? color : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSelected)
                      Icon(Ionicons.checkmark_circle, color: color, size: 18)
                    else
                      Icon(Ionicons.ellipse_outline, color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      entry.value,
                      style: TextStyle(
                        color: isSelected ? color : null,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildDescriptionSection(TaskModel task, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Ionicons.document_text_outline,
                size: 20,
                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
              ),
              const SizedBox(width: 8),
              Text(
                'Mô tả',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            task.description ?? 'Chưa có mô tả',
            style: TextStyle(
              color: task.description != null
                  ? null
                  : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
              fontStyle: task.description != null ? FontStyle.normal : FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDueDateSection(TaskModel task, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Ionicons.calendar_outline, color: AppColors.warning, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hạn hoàn thành',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  task.dueDate != null
                      ? '${task.dueDate!.day}/${task.dueDate!.month}/${task.dueDate!.year}'
                      : 'Chưa đặt',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: task.dueDate != null ? null : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _selectDueDate(context, task),
            icon: const Icon(Ionicons.add_circle_outline),
          ),
        ],
      ),
    );
  }

  Widget _buildAssigneeSection(TaskModel task, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primaryStart.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Ionicons.person_outline, color: AppColors.primaryStart, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Người thực hiện',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  ),
                ),
                const SizedBox(height: 4),
                if (task.assigneeName != null && task.assigneeName!.isNotEmpty)
                  Row(
                    children: [
                      if (resolveAvatarUrl(task.assigneeAvatar) != null)
                        CircleAvatar(
                          radius: 12,
                          backgroundImage: NetworkImage(resolveAvatarUrl(task.assigneeAvatar)!),
                        )
                      else
                        UserAvatar(name: task.assigneeName!, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        task.assigneeName!,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  )
                else
                  Text(
                    task.assigneeId != null ? 'Đã gán' : 'Chưa gán',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: task.assigneeId != null ? null : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: _loading ? null : () => _showAssigneePicker(context, task),
            icon: const Icon(Ionicons.add_circle_outline),
          ),
        ],
      ),
    );
  }

  Widget _buildTimestampsSection(TaskModel task, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Ionicons.time_outline,
                size: 20,
                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
              ),
              const SizedBox(width: 8),
              Text(
                'Thời gian',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (task.createdAt != null) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Tạo lúc:',
                  style: TextStyle(
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  ),
                ),
                Text(_formatDateTime(task.createdAt!)),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (task.updatedAt != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Cập nhật:',
                  style: TextStyle(
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  ),
                ),
                Text(_formatDateTime(task.updatedAt!)),
              ],
            ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _showPriorityPicker(BuildContext context, TaskModel task) {
    final priorities = {
      'low': ('Thấp', Colors.grey, Ionicons.flag_outline),
      'normal': ('Bình thường', AppColors.info, Ionicons.flag_outline),
      'high': ('Cao', AppColors.warning, Ionicons.flag),
      'urgent': ('Khẩn cấp', AppColors.error, Ionicons.flag),
    };

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Chọn mức độ ưu tiên',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...priorities.entries.map((entry) {
              final isSelected = task.priority == entry.key;
              final (label, color, icon) = entry.value;

              return ListTile(
                leading: Icon(icon, color: color),
                title: Text(label),
                trailing: isSelected ? Icon(Ionicons.checkmark_circle, color: color) : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _updateTask(priority: entry.key);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _showAssigneePicker(BuildContext context, TaskModel task) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    List<WorkspaceMember> members = [];
    try {
      members = await _wsRepo.getMembers(widget.workspaceId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không tải được danh sách thành viên: $e'), backgroundColor: AppColors.error),
        );
      }
      return;
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.6),
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Gán người thực hiện',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Ionicons.close_circle_outline),
              title: const Text('Bỏ gán'),
              onTap: () {
                Navigator.pop(ctx);
                _updateTask(clearAssignee: true);
              },
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: members.length,
                itemBuilder: (_, i) {
                  final m = members[i];
                  final isSelected = task.assigneeId == m.id;
                  return ListTile(
                    leading: m.avatar != null && m.avatar!.isNotEmpty
                        ? CircleAvatar(backgroundImage: NetworkImage(resolveAvatarUrl(m.avatar)!))
                        : UserAvatar(name: m.name, size: 40),
                    title: Text(m.name),
                    subtitle: Text(m.email),
                    trailing: isSelected ? const Icon(Ionicons.checkmark_circle, color: AppColors.success) : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      _updateTask(assigneeId: m.id);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDueDate(BuildContext context, TaskModel task) async {
    final date = await showDatePicker(
      context: context,
      initialDate: task.dueDate ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (date != null) {
      _updateTask(dueDate: date);
    }
  }

  void _showEditDialog(BuildContext context, TaskModel task) {
    final titleController = TextEditingController(text: task.title);
    final descController = TextEditingController(text: task.description ?? '');

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
              Row(
                children: const [
                  Icon(Ionicons.create_outline, color: AppColors.primaryStart),
                  SizedBox(width: 12),
                  Text('Chỉnh sửa task'),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleController,
                decoration: InputDecoration(
                  labelText: 'Tiêu đề',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descController,
                decoration: InputDecoration(
                  labelText: 'Mô tả',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                maxLines: 3,
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
                      _updateTask(
                        title: titleController.text.trim(),
                        description: descController.text.trim(),
                      );
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

  void _showDeleteConfirmation(BuildContext context, TaskModel task) {
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
              Row(
                children: const [
                  Icon(Ionicons.warning_outline, color: AppColors.error),
                  SizedBox(width: 12),
                  Text('Xóa task'),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Bạn có chắc chắn muốn xóa task này? Hành động này không thể hoàn tác.'),
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
                      _deleteTask(task);
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
