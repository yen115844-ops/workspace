import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:ionicons/ionicons.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/websocket_service.dart';
import '../../../core/utils/safe_navigation.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/models.dart';
import '../data/task_repository.dart';

class TaskBoardScreen extends StatefulWidget {
  const TaskBoardScreen({super.key, required this.workspaceId});
  final String workspaceId;

  @override
  State<TaskBoardScreen> createState() => _TaskBoardScreenState();
}

class _TaskBoardScreenState extends State<TaskBoardScreen> with TickerProviderStateMixin {
  final _repo = TaskRepository();
  final _ws = WebSocketService();
  List<TaskModel> _tasks = [];
  List<BoardColumnModel> _columns = [];
  bool _loading = true;
  String? _filterPriority;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  bool _isListView = false;
  StreamSubscription? _taskEventSubscription;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _ws.connect();
    _ws.joinWorkspace(widget.workspaceId);
    _taskEventSubscription = _ws.onTaskEvent.listen((data) {
      final wsId = data['workspaceId']?.toString();
      if (wsId != widget.workspaceId || !mounted) return;
      _applyTaskEvent(data);
    });
    _searchController.addListener(() => setState(() => _searchQuery = _searchController.text.trim().toLowerCase()));
    _load();
  }

  @override
  void dispose() {
    _taskEventSubscription?.cancel();
    _ws.leaveWorkspace(widget.workspaceId);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final board = await _repo.getBoard(widget.workspaceId);
      _columns = board?.columns ?? [
        BoardColumnModel(id: 'todo', title: 'To Do', order: 0),
        BoardColumnModel(id: 'in_progress', title: 'Đang làm', order: 1),
        BoardColumnModel(id: 'done', title: 'Hoàn thành', order: 2),
      ];
      _tasks = await _repo.list(widget.workspaceId);
    } catch (e) {
      debugPrint('Error loading board: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _applyTaskEvent(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    if (type == null) return;
    if (!mounted) return;
    setState(() {
      switch (type) {
        case 'task_created':
          final taskJson = Map<String, dynamic>.from(data);
          try {
            final task = TaskModel.fromJson(taskJson);
            if (!_tasks.any((t) => t.id == task.id)) {
              _tasks.add(task);
            }
          } catch (_) {}
          break;
        case 'task_updated':
          final taskJson = Map<String, dynamic>.from(data);
          try {
            final task = TaskModel.fromJson(taskJson);
            final i = _tasks.indexWhere((t) => t.id == task.id);
            if (i >= 0) {
              _tasks[i] = task;
            } else {
              _tasks.add(task);
            }
          } catch (_) {}
          break;
        case 'task_deleted':
          final taskId = data['taskId']?.toString();
          if (taskId != null) {
            _tasks.removeWhere((t) => t.id == taskId);
          }
          break;
      }
    });
  }

  List<TaskModel> _getFilteredTasks(String? columnId) {
    return _tasks.where((task) {
      if (columnId != null && task.columnId != columnId) return false;
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        if (!task.title.toLowerCase().contains(query) &&
            !(task.description?.toLowerCase().contains(query) ?? false)) {
          return false;
        }
      }
      if (_filterPriority != null && task.priority != _filterPriority) return false;
      return true;
    }).toList();
  }

  Future<void> _moveTask(TaskModel task, String newColumnId) async {
    if (task.columnId == newColumnId) return;
    
    final oldColumnId = task.columnId;
    // Optimistic update
    setState(() {
      final index = _tasks.indexWhere((t) => t.id == task.id);
      if (index >= 0) {
        _tasks[index] = task.copyWith(columnId: newColumnId);
      }
    });
    
    // Haptic feedback
    HapticFeedback.mediumImpact();
    
    try {
      await _repo.update(task.id, columnId: newColumnId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã chuyển sang ${_getColumnTitle(newColumnId)}'),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      // Rollback on error
      setState(() {
        final index = _tasks.indexWhere((t) => t.id == task.id);
        if (index >= 0) {
          _tasks[index] = task.copyWith(columnId: oldColumnId);
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  String _getColumnTitle(String columnId) {
    switch (columnId) {
      case 'todo': return 'To Do';
      case 'in_progress': return 'Đang làm';
      case 'done': return 'Hoàn thành';
      default: return columnId;
    }
  }

  Future<void> _deleteTask(TaskModel task) async {
    final confirm = await showDialog<bool>(
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
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Ionicons.trash_outline, color: AppColors.error, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text('Xóa task'),
                ],
              ),
              const SizedBox(height: 16),
              Text('Bạn có chắc muốn xóa "${task.title}"?'),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                    child: const Text('Xóa', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    
    if (confirm == true) {
      try {
        await _repo.delete(task.id);
        setState(() => _tasks.removeWhere((t) => t.id == task.id));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã xóa task'), backgroundColor: AppColors.success),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? AppColors.bgDark : AppColors.bgLight,
      appBar: _buildAppBar(isDark),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildSearchBar(isDark),
                _buildFilterBar(isDark),
                _buildViewToggle(isDark),
                if (_isListView)
                  Expanded(child: _buildListView(isDark))
                else ...[
                  _buildTabBar(isDark),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: _columns.map((col) => _buildTaskList(col, isDark)).toList(),
                    ),
                  ),
                ],
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateTask(context),
        icon: const Icon(Ionicons.add),
        label: const Text('Tạo task'),
        backgroundColor: AppColors.primaryStart,
        foregroundColor: Colors.white,
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isDark) {
    return AppBar(
      backgroundColor: isDark ? AppColors.cardDark : Colors.white,
      elevation: 0,
      leading: IconButton(
        onPressed: () => context.maybePopOrGo('/workspaces/${widget.workspaceId}'),
        icon: Icon(
          Ionicons.chevron_back,
          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
        ),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Ionicons.checkbox_outline, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 12),
          const Text(
            'Tasks',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: _load,
          icon: Icon(
            Ionicons.refresh_outline,
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Tìm kiếm task...',
          prefixIcon: Icon(
            Ionicons.search_outline,
            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Ionicons.close_circle),
                  onPressed: () {
                    _searchController.clear();
                  },
                )
              : null,
          filled: true,
          fillColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        style: TextStyle(
          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
        ),
      ),
    );
  }

  Widget _buildViewToggle(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: _ViewToggleChip(
              icon: Ionicons.grid_outline,
              label: 'Kanban',
              selected: !_isListView,
              onTap: () => setState(() => _isListView = false),
              isDark: isDark,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ViewToggleChip(
              icon: Ionicons.list_outline,
              label: 'Danh sách',
              selected: _isListView,
              onTap: () => setState(() => _isListView = true),
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListView(bool isDark) {
    final tasks = _getFilteredTasks(null);
    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Ionicons.clipboard_outline,
              size: 64,
              color: isDark ? AppColors.textSecondaryDark.withOpacity(0.3) : Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'Chưa có task',
              style: TextStyle(
                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _showCreateTask(context),
              icon: const Icon(Ionicons.add),
              label: const Text('Thêm task mới'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        itemCount: tasks.length,
        itemBuilder: (context, index) {
          final task = tasks[index];
          final col = _columns.firstWhere(
            (c) => c.id == task.columnId,
            orElse: () => BoardColumnModel(id: task.columnId, title: task.columnId, order: 0),
          );
          return _SwipeableTaskCard(
            key: ValueKey(task.id),
            task: task,
            isDark: isDark,
            columns: _columns,
            currentColumnId: col.id,
            onTap: () async {
              await context.push(
                '/workspaces/${widget.workspaceId}/tasks/${task.id}',
                extra: task,
              );
              if (mounted) _load();
            },
            onMove: (newColumnId) => _moveTask(task, newColumnId),
            onDelete: () => _deleteTask(task),
          );
        },
      ),
    );
  }

  Widget _buildFilterBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _FilterChip(
              label: 'Tất cả',
              selected: _filterPriority == null,
              onTap: () => setState(() => _filterPriority = null),
              isDark: isDark,
            ),
            const SizedBox(width: 8),
            _FilterChip(
              label: 'Cao',
              icon: Ionicons.flame,
              color: AppColors.error,
              selected: _filterPriority == 'high',
              onTap: () => setState(() => _filterPriority = _filterPriority == 'high' ? null : 'high'),
              isDark: isDark,
            ),
            const SizedBox(width: 8),
            _FilterChip(
              label: 'TB',
              icon: Ionicons.remove,
              color: AppColors.warning,
              selected: _filterPriority == 'normal',
              onTap: () => setState(() => _filterPriority = _filterPriority == 'normal' ? null : 'normal'),
              isDark: isDark,
            ),
            const SizedBox(width: 8),
            _FilterChip(
              label: 'Thấp',
              icon: Ionicons.chevron_down,
              color: AppColors.info,
              selected: _filterPriority == 'low',
              onTap: () => setState(() => _filterPriority = _filterPriority == 'low' ? null : 'low'),
              isDark: isDark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(12),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: const EdgeInsets.all(4),
        labelColor: Colors.white,
        unselectedLabelColor: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        dividerColor: Colors.transparent,
        tabs: [
          _buildTab('To Do', _getFilteredTasks('todo').length, AppColors.info),
          _buildTab('Đang làm', _getFilteredTasks('in_progress').length, AppColors.warning),
          _buildTab('Xong', _getFilteredTasks('done').length, AppColors.success),
        ],
      ),
    );
  }

  Widget _buildTab(String label, int count, Color color) {
    return Tab(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTaskList(BoardColumnModel column, bool isDark) {
    final tasks = _getFilteredTasks(column.id);
    
    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Ionicons.clipboard_outline,
              size: 64,
              color: isDark ? AppColors.textSecondaryDark.withOpacity(0.3) : Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'Chưa có task',
              style: TextStyle(
                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _showCreateTask(context, columnId: column.id),
              icon: const Icon(Ionicons.add),
              label: const Text('Thêm task mới'),
            ),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: tasks.length,
        itemBuilder: (context, index) {
          final task = tasks[index];
          return _SwipeableTaskCard(
            key: ValueKey(task.id),
            task: task,
            isDark: isDark,
            columns: _columns,
            currentColumnId: column.id,
            onTap: () => _showTaskDetail(context, task),
            onMove: (newColumnId) => _moveTask(task, newColumnId),
            onDelete: () => _deleteTask(task),
          );
        },
      ),
    );
  }

  void _showCreateTask(BuildContext context, {String? columnId}) {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    String selectedPriority = 'normal';
    DateTime? selectedDueDate;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          margin: EdgeInsets.only(top: MediaQuery.of(ctx).viewInsets.top + 60),
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          decoration: BoxDecoration(
            color: isDark ? AppColors.cardDark : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
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
                const SizedBox(height: 20),
                
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Ionicons.checkbox_outline, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Tạo task mới',
                      style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Title
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(
                    labelText: 'Tiêu đề task *',
                    hintText: 'Nhập tiêu đề task',
                    prefixIcon: const Icon(Ionicons.text_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                
                // Description
                TextField(
                  controller: descController,
                  decoration: InputDecoration(
                    labelText: 'Mô tả (tùy chọn)',
                    hintText: 'Nhập mô tả chi tiết',
                    prefixIcon: const Icon(Ionicons.document_text_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                
                // Priority selection
                Text(
                  'Độ ưu tiên',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _PriorityOption(
                      label: 'Thấp',
                      icon: Ionicons.chevron_down,
                      color: AppColors.info,
                      selected: selectedPriority == 'low',
                      onTap: () => setModalState(() => selectedPriority = 'low'),
                    ),
                    const SizedBox(width: 8),
                    _PriorityOption(
                      label: 'TB',
                      icon: Ionicons.remove,
                      color: AppColors.warning,
                      selected: selectedPriority == 'normal',
                      onTap: () => setModalState(() => selectedPriority = 'normal'),
                    ),
                    const SizedBox(width: 8),
                    _PriorityOption(
                      label: 'Cao',
                      icon: Ionicons.flame,
                      color: AppColors.error,
                      selected: selectedPriority == 'high',
                      onTap: () => setModalState(() => selectedPriority = 'high'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Due date
                InkWell(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: ctx,
                      initialDate: selectedDueDate ?? DateTime.now().add(const Duration(days: 1)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date != null) {
                      setModalState(() => selectedDueDate = date);
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? AppColors.surfaceDark : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Ionicons.calendar_outline,
                          color: selectedDueDate != null ? AppColors.warning : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          selectedDueDate != null 
                              ? 'Hạn: ${selectedDueDate!.day}/${selectedDueDate!.month}/${selectedDueDate!.year}'
                              : 'Chọn ngày hạn (tùy chọn)',
                          style: TextStyle(
                            color: selectedDueDate != null 
                                ? (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight)
                                : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
                          ),
                        ),
                        const Spacer(),
                        if (selectedDueDate != null)
                          GestureDetector(
                            onTap: () => setModalState(() => selectedDueDate = null),
                            child: const Icon(Ionicons.close_circle, size: 20),
                          ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
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
                              final title = titleController.text.trim();
                              if (title.isEmpty) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(content: Text('Vui lòng nhập tiêu đề')),
                                );
                                return;
                              }
                              Navigator.pop(ctx);
                              try {
                                final newTask = await _repo.create(
                                  widget.workspaceId, 
                                  title,
                                  description: descController.text.trim().isNotEmpty ? descController.text.trim() : null,
                                  columnId: columnId ?? _columns[_tabController.index].id,
                                  priority: selectedPriority,
                                  dueDate: selectedDueDate,
                                );
                                if (mounted && !_tasks.any((t) => t.id == newTask.id)) {
                                  setState(() => _tasks.add(newTask));
                                }
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Đã tạo task mới'),
                                      backgroundColor: AppColors.success,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Lỗi: $e'), backgroundColor: AppColors.error),
                                  );
                                }
                              }
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              alignment: Alignment.center,
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Ionicons.add_circle_outline, color: Colors.white, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'Tạo task',
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

  void _showTaskDetail(BuildContext context, TaskModel task) async {
    await context.push(
      '/workspaces/${widget.workspaceId}/tasks/${task.id}',
      extra: task,
    );
    if (mounted) _load();
  }

  void _showEditTask(BuildContext context, TaskModel task) {
    final titleController = TextEditingController(text: task.title);
    final descController = TextEditingController(text: task.description ?? '');
    String selectedPriority = task.priority;
    DateTime? selectedDueDate = task.dueDate;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          margin: EdgeInsets.only(top: MediaQuery.of(ctx).viewInsets.top + 60),
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          decoration: BoxDecoration(
            color: isDark ? AppColors.cardDark : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
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
                const SizedBox(height: 20),
                
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Ionicons.create_outline, color: AppColors.warning, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Chỉnh sửa task',
                      style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Title
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(
                    labelText: 'Tiêu đề task *',
                    prefixIcon: const Icon(Ionicons.text_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Description
                TextField(
                  controller: descController,
                  decoration: InputDecoration(
                    labelText: 'Mô tả',
                    prefixIcon: const Icon(Ionicons.document_text_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                
                // Priority
                Text(
                  'Độ ưu tiên',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _PriorityOption(
                      label: 'Thấp',
                      icon: Ionicons.chevron_down,
                      color: AppColors.info,
                      selected: selectedPriority == 'low',
                      onTap: () => setModalState(() => selectedPriority = 'low'),
                    ),
                    const SizedBox(width: 8),
                    _PriorityOption(
                      label: 'TB',
                      icon: Ionicons.remove,
                      color: AppColors.warning,
                      selected: selectedPriority == 'normal',
                      onTap: () => setModalState(() => selectedPriority = 'normal'),
                    ),
                    const SizedBox(width: 8),
                    _PriorityOption(
                      label: 'Cao',
                      icon: Ionicons.flame,
                      color: AppColors.error,
                      selected: selectedPriority == 'high',
                      onTap: () => setModalState(() => selectedPriority = 'high'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Due date
                InkWell(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: ctx,
                      initialDate: selectedDueDate ?? DateTime.now().add(const Duration(days: 1)),
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date != null) {
                      setModalState(() => selectedDueDate = date);
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? AppColors.surfaceDark : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Ionicons.calendar_outline,
                          color: selectedDueDate != null ? AppColors.warning : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          selectedDueDate != null 
                              ? 'Hạn: ${selectedDueDate!.day}/${selectedDueDate!.month}/${selectedDueDate!.year}'
                              : 'Chọn ngày hạn',
                          style: TextStyle(
                            color: selectedDueDate != null 
                                ? (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight)
                                : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
                          ),
                        ),
                        const Spacer(),
                        if (selectedDueDate != null)
                          GestureDetector(
                            onTap: () => setModalState(() => selectedDueDate = null),
                            child: const Icon(Ionicons.close_circle, size: 20),
                          ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
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
                              final title = titleController.text.trim();
                              if (title.isEmpty) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(content: Text('Vui lòng nhập tiêu đề')),
                                );
                                return;
                              }
                              Navigator.pop(ctx);
                              try {
                                final updated = await _repo.update(
                                  task.id,
                                  title: title,
                                  description: descController.text.trim(),
                                  priority: selectedPriority,
                                  dueDate: selectedDueDate,
                                );
                                setState(() {
                                  final index = _tasks.indexWhere((t) => t.id == task.id);
                                  if (index >= 0) {
                                    _tasks[index] = updated;
                                  }
                                });
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Đã cập nhật task'),
                                      backgroundColor: AppColors.success,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Lỗi: $e'), backgroundColor: AppColors.error),
                                  );
                                }
                              }
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              alignment: Alignment.center,
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Ionicons.checkmark_circle_outline, color: Colors.white, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'Lưu thay đổi',
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

  Color _getColumnColor(String columnId) {
    switch (columnId) {
      case 'todo': return AppColors.info;
      case 'in_progress': return AppColors.warning;
      case 'done': return AppColors.success;
      default: return AppColors.primaryStart;
    }
  }

  IconData _getColumnIcon(String columnId) {
    switch (columnId) {
      case 'todo': return Ionicons.list_outline;
      case 'in_progress': return Ionicons.time_outline;
      case 'done': return Ionicons.checkmark_done_outline;
      default: return Ionicons.albums_outline;
    }
  }
}

// ============ WIDGETS ============

class _ViewToggleChip extends StatelessWidget {
  const _ViewToggleChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryStart.withOpacity(0.15) : (isDark ? AppColors.cardDark : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primaryStart : (isDark ? AppColors.surfaceDark : Colors.grey.shade300),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: selected ? AppColors.primaryStart : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.primaryStart : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.isDark,
    this.icon,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool isDark;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected 
              ? (color ?? AppColors.primaryStart).withOpacity(0.15)
              : (isDark ? AppColors.cardDark : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected 
                ? (color ?? AppColors.primaryStart)
                : (isDark ? AppColors.surfaceDark : Colors.grey.shade300),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: selected ? color : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected 
                    ? (color ?? AppColors.primaryStart)
                    : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriorityOption extends StatelessWidget {
  const _PriorityOption({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : Colors.grey.shade300,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: selected ? color : Colors.grey),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: selected ? color : Colors.grey,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.columnId});
  final String columnId;

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    String label;
    
    switch (columnId) {
      case 'todo':
        color = AppColors.info;
        icon = Ionicons.ellipse_outline;
        label = 'To Do';
        break;
      case 'in_progress':
        color = AppColors.warning;
        icon = Ionicons.sync_outline;
        label = 'Đang làm';
        break;
      case 'done':
        color = AppColors.success;
        icon = Ionicons.checkmark_circle;
        label = 'Hoàn thành';
        break;
      default:
        color = AppColors.textSecondaryLight;
        icon = Ionicons.help_circle_outline;
        label = columnId;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
        ],
      ),
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.priority});
  final String priority;

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    String label;
    
    switch (priority) {
      case 'high':
        color = AppColors.error;
        icon = Ionicons.flame;
        label = 'Cao';
        break;
      case 'low':
        color = AppColors.info;
        icon = Ionicons.chevron_down;
        label = 'Thấp';
        break;
      default:
        color = AppColors.warning;
        icon = Ionicons.remove;
        label = 'TB';
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 11)),
        ],
      ),
    );
  }
}

class _DueDateCard extends StatelessWidget {
  const _DueDateCard({required this.dueDate, required this.isDark});
  final DateTime dueDate;
  final bool isDark;

  Color _getDueDateColor() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final diff = due.difference(today).inDays;
    
    if (diff < 0) return AppColors.error;
    if (diff <= 2) return AppColors.warning;
    return AppColors.success;
  }

  String _getDueDateText() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final diff = due.difference(today).inDays;
    
    if (diff < 0) return 'Quá hạn ${-diff} ngày';
    if (diff == 0) return 'Hôm nay';
    if (diff == 1) return 'Ngày mai';
    return 'Còn $diff ngày';
  }

  @override
  Widget build(BuildContext context) {
    final color = _getDueDateColor();
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Ionicons.calendar_outline, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hạn hoàn thành',
                style: TextStyle(
                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  fontSize: 12,
                ),
              ),
              Text(
                '${dueDate.day}/${dueDate.month}/${dueDate.year}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            _getDueDateText(),
            style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _AssigneeCard extends StatelessWidget {
  const _AssigneeCard({required this.task, required this.isDark});
  final TaskModel task;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primaryStart,
            backgroundImage: resolveAvatarUrl(task.assigneeAvatar) != null
                ? NetworkImage(resolveAvatarUrl(task.assigneeAvatar)!)
                : null,
            child: resolveAvatarUrl(task.assigneeAvatar) == null
                ? Text(
                    task.assigneeName![0].toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Người thực hiện',
                style: TextStyle(
                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  fontSize: 12,
                ),
              ),
              Text(
                task.assigneeName!,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Swipeable task card with status change actions
class _SwipeableTaskCard extends StatelessWidget {
  const _SwipeableTaskCard({
    super.key,
    required this.task,
    required this.isDark,
    required this.columns,
    required this.currentColumnId,
    required this.onTap,
    required this.onMove,
    required this.onDelete,
  });

  final TaskModel task;
  final bool isDark;
  final List<BoardColumnModel> columns;
  final String currentColumnId;
  final VoidCallback onTap;
  final void Function(String) onMove;
  final VoidCallback onDelete;

  Color _getPriorityColor() {
    switch (task.priority) {
      case 'high': return AppColors.error;
      case 'low': return AppColors.info;
      default: return AppColors.warning;
    }
  }

  IconData _getPriorityIcon() {
    switch (task.priority) {
      case 'high': return Ionicons.flame;
      case 'low': return Ionicons.chevron_down;
      default: return Ionicons.remove;
    }
  }

  Color _getDueDateColor(DateTime dueDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final diff = due.difference(today).inDays;
    
    if (diff < 0) return AppColors.error;
    if (diff <= 2) return AppColors.warning;
    return AppColors.success;
  }

  @override
  Widget build(BuildContext context) {
    // Get adjacent columns for swipe actions
    final currentIndex = columns.indexWhere((c) => c.id == currentColumnId);
    final prevColumn = currentIndex > 0 ? columns[currentIndex - 1] : null;
    final nextColumn = currentIndex < columns.length - 1 ? columns[currentIndex + 1] : null;

    return Dismissible(
      key: ValueKey('${task.id}_dismiss'),
      background: prevColumn != null 
          ? _buildSwipeBackground(prevColumn, true)
          : Container(),
      secondaryBackground: nextColumn != null 
          ? _buildSwipeBackground(nextColumn, false)
          : _buildDeleteBackground(),
      confirmDismiss: (direction) async {
        HapticFeedback.mediumImpact();
        if (direction == DismissDirection.startToEnd && prevColumn != null) {
          onMove(prevColumn.id);
          return false;
        } else if (direction == DismissDirection.endToStart) {
          if (nextColumn != null) {
            onMove(nextColumn.id);
            return false;
          } else {
            // Delete action (when at last column)
            return true;
          }
        }
        return false;
      },
      onDismissed: (direction) {
        if (direction == DismissDirection.endToStart && nextColumn == null) {
          onDelete();
        }
      },
      child: _buildCard(context),
    );
  }

  Widget _buildSwipeBackground(BoardColumnModel column, bool isLeft) {
    Color color;
    IconData icon;
    
    switch (column.id) {
      case 'todo':
        color = AppColors.info;
        icon = Ionicons.list_outline;
        break;
      case 'in_progress':
        color = AppColors.warning;
        icon = Ionicons.time_outline;
        break;
      case 'done':
        color = AppColors.success;
        icon = Ionicons.checkmark_done_outline;
        break;
      default:
        color = AppColors.primaryStart;
        icon = Ionicons.arrow_forward;
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: isLeft ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: isLeft 
            ? [
                Icon(icon, color: Colors.white),
                const SizedBox(width: 8),
                Text(column.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ]
            : [
                Text(column.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Icon(icon, color: Colors.white),
              ],
      ),
    );
  }

  Widget _buildDeleteBackground() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Xóa', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          SizedBox(width: 8),
          Icon(Ionicons.trash_outline, color: Colors.white),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: Priority & swipe hint
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getPriorityColor().withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_getPriorityIcon(), size: 12, color: _getPriorityColor()),
                          const SizedBox(width: 4),
                          Text(
                            task.priority == 'high' ? 'Cao' : (task.priority == 'low' ? 'Thấp' : 'TB'),
                            style: TextStyle(
                              color: _getPriorityColor(),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Ionicons.swap_horizontal_outline,
                      size: 16,
                      color: isDark ? AppColors.textSecondaryDark.withOpacity(0.5) : Colors.grey.shade400,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Title
                Text(
                  task.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                
                // Description
                if (task.description != null && task.description!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    task.description!,
                    style: TextStyle(
                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                      fontSize: 13,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                
                // Footer: due date & assignee
                if (task.dueDate != null || task.assigneeName != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (task.dueDate != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getDueDateColor(task.dueDate!).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Ionicons.calendar_outline,
                                size: 12,
                                color: _getDueDateColor(task.dueDate!),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${task.dueDate!.day}/${task.dueDate!.month}',
                                style: TextStyle(
                                  color: _getDueDateColor(task.dueDate!),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (task.assigneeName != null)
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: AppColors.primaryStart,
                          backgroundImage: resolveAvatarUrl(task.assigneeAvatar) != null
                              ? NetworkImage(resolveAvatarUrl(task.assigneeAvatar)!)
                              : null,
                          child: resolveAvatarUrl(task.assigneeAvatar) == null
                              ? Text(
                                  task.assigneeName![0].toUpperCase(),
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                                )
                              : null,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
