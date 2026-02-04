import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ionicons/ionicons.dart';

import '../../../core/data/search_repository.dart';
import '../../../core/models/models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/safe_navigation.dart';
import '../../../core/widgets/common_widgets.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.workspaceId});

  final String? workspaceId;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  final _repository = SearchRepository();
  
  late TabController _tabController;
  
  SearchResult? _result;
  bool _isLoading = false;
  String? _error;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _result = null;
        _error = null;
      });
      return;
    }
    
    if (query == _lastQuery) return;
    _lastQuery = query;
    
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    try {
      final result = await _repository.searchAll(query, workspaceId: widget.workspaceId);
      if (mounted && query == _lastQuery) {
        setState(() {
          _result = result;
          _isLoading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Không thể tìm kiếm';
          _isLoading = false;
        });
      }
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
                  colors: [AppColors.bgDark, AppColors.cardDark.withOpacity(0.5)],
                )
              : null,
          color: isDark ? null : AppColors.bgLight,
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Search Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => context.maybePopOrGo(
                        widget.workspaceId != null
                            ? '/workspaces/${widget.workspaceId}'
                            : SafeNavigation.defaultFallback,
                      ),
                      icon: const Icon(Ionicons.arrow_back),
                      style: IconButton.styleFrom(
                        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: TextField(
                          controller: _searchController,
                          focusNode: _focusNode,
                          onChanged: _search,
                          decoration: InputDecoration(
                            hintText: 'Tìm kiếm tin nhắn, người dùng, tasks...',
                            hintStyle: TextStyle(
                              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                            ),
                            prefixIcon: Icon(
                              Ionicons.search_outline,
                              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                            ),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Ionicons.close_circle),
                                    onPressed: () {
                                      _searchController.clear();
                                      _search('');
                                    },
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              // Tabs
              if (_result != null && !_result!.isEmpty)
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.cardDark : Colors.white,
                    border: Border(
                      bottom: BorderSide(
                        color: isDark ? AppColors.surfaceDark : Colors.grey.shade200,
                      ),
                    ),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    labelColor: AppColors.primaryStart,
                    unselectedLabelColor: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                    indicatorColor: AppColors.primaryStart,
                    tabs: [
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Ionicons.chatbubble_outline, size: 18),
                            const SizedBox(width: 4),
                            Text('${_result!.messages.length}'),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Ionicons.person_outline, size: 18),
                            const SizedBox(width: 4),
                            Text('${_result!.users.length}'),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Ionicons.checkbox_outline, size: 18),
                            const SizedBox(width: 4),
                            Text('${_result!.tasks.length}'),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Ionicons.chatbubbles_outline, size: 18),
                            const SizedBox(width: 4),
                            Text('${_result!.channels.length}'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              
              // Results
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
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_error != null) {
      return ErrorState(
        message: _error!,
        onRetry: () => _search(_lastQuery),
      );
    }
    
    if (_searchController.text.isEmpty) {
      return EmptyState(
        icon: Ionicons.search_outline,
        title: 'Nhập từ khóa để tìm kiếm',
        subtitle: 'Tìm tin nhắn, người dùng, tasks và channels',
      );
    }
    
    if (_result == null || _result!.isEmpty) {
      return EmptyState(
        icon: Ionicons.search_outline,
        title: 'Không tìm thấy kết quả',
        subtitle: 'Thử tìm với từ khóa khác',
      );
    }
    
    return TabBarView(
      controller: _tabController,
      children: [
        _buildMessageResults(isDark),
        _buildUserResults(isDark),
        _buildTaskResults(isDark),
        _buildChannelResults(isDark),
      ],
    );
  }

  Widget _buildMessageResults(bool isDark) {
    if (_result!.messages.isEmpty) {
      return EmptyState(
        icon: Ionicons.chatbubble_outline,
        title: 'Không tìm thấy tin nhắn',
        subtitle: 'Thử tìm với từ khóa khác',
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _result!.messages.length,
      itemBuilder: (context, index) {
        final msg = _result!.messages[index];
        return _buildMessageCard(msg, isDark);
      },
    );
  }

  Widget _buildMessageCard(MessageSearchResult msg, bool isDark) {
    final workspaceId = msg.workspaceId ?? widget.workspaceId;
    final channelId = msg.channelId;
    final channelName = msg.channelName ?? 'Channel';
    final canNavigate = workspaceId != null && channelId != null;

    return InkWell(
      onTap: canNavigate
          ? () {
              Navigator.of(context).pop();
              context.push(
                '/workspaces/$workspaceId/channels/$channelId?messageId=${msg.id}',
                extra: channelName,
              );
            }
          : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : AppColors.cardLight,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserAvatar(name: msg.authorName ?? 'Unknown', size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        msg.authorName ?? 'Unknown',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (msg.channelName != null)
                        Text(
                          '# ${msg.channelName}',
                          style: TextStyle(
                            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                if (msg.createdAt != null)
                  Text(
                    _formatDate(msg.createdAt!),
                    style: TextStyle(
                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              msg.content,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserResults(bool isDark) {
    if (_result!.users.isEmpty) {
      return EmptyState(
        icon: Ionicons.person_outline,
        title: 'Không tìm thấy người dùng',
        subtitle: 'Thử tìm với từ khóa khác',
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _result!.users.length,
      itemBuilder: (context, index) {
        final user = _result!.users[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isDark ? AppColors.cardDark : AppColors.cardLight,
            borderRadius: BorderRadius.circular(16),
          ),
          child: ListTile(
            leading: UserAvatar(name: user.name, size: 44),
            title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(user.email),
            trailing: Container(
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(8),
              ),
              child: IconButton(
                icon: const Icon(Ionicons.chatbubble_outline, color: Colors.white, size: 18),
                onPressed: () {
                  // TODO: Start DM
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTaskResults(bool isDark) {
    if (_result!.tasks.isEmpty) {
      return EmptyState(
        icon: Ionicons.checkbox_outline,
        title: 'Không tìm thấy task',
        subtitle: 'Thử tìm với từ khóa khác',
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _result!.tasks.length,
      itemBuilder: (context, index) {
        final task = _result!.tasks[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? AppColors.cardDark : AppColors.cardLight,
            borderRadius: BorderRadius.circular(16),
          ),
          child: InkWell(
            onTap: () {
              final wsId = task.workspaceId ?? widget.workspaceId;
              if (wsId != null) {
                final taskModel = TaskModel(
                  id: task.id,
                  title: task.title,
                  description: task.description,
                  columnId: task.status ?? 'todo',
                  status: task.status ?? 'todo',
                );
                Navigator.of(context).pop();
                context.push(
                  '/workspaces/$wsId/tasks/${task.id}',
                  extra: taskModel,
                );
              }
            },
            borderRadius: BorderRadius.circular(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryStart.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Ionicons.checkbox_outline, color: AppColors.primaryStart),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (task.description != null)
                        Text(
                          task.description!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
                if (task.status != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStatusColor(task.status!).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    task.status!,
                    style: TextStyle(
                      color: _getStatusColor(task.status!),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
      },
    );
  }

  Widget _buildChannelResults(bool isDark) {
    if (_result!.channels.isEmpty) {
      return EmptyState(
        icon: Ionicons.chatbubbles_outline,
        title: 'Không tìm thấy channel',
        subtitle: 'Thử tìm với từ khóa khác',
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _result!.channels.length,
      itemBuilder: (context, index) {
        final channel = _result!.channels[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isDark ? AppColors.cardDark : AppColors.cardLight,
            borderRadius: BorderRadius.circular(16),
          ),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                channel.type == 'private' ? Ionicons.lock_closed : Ionicons.chatbubble,
                color: Colors.white,
                size: 20,
              ),
            ),
            title: Text('# ${channel.name}', style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: channel.workspaceName != null
                ? Text(channel.workspaceName!)
                : null,
            trailing: const Icon(Ionicons.chevron_forward),
            onTap: () {
              final wsId = channel.workspaceId ?? widget.workspaceId;
              if (wsId != null) {
                Navigator.of(context).pop();
                context.push(
                  '/workspaces/$wsId/channels/${channel.id}',
                  extra: channel.name,
                );
              }
            },
          ),
        );
      },
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'done':
      case 'completed':
        return AppColors.success;
      case 'in_progress':
      case 'in-progress':
        return AppColors.info;
      case 'blocked':
        return AppColors.error;
      default:
        return AppColors.warning;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (date.day == now.day && date.month == now.month && date.year == now.year) {
      return 'Hôm nay';
    }
    if (date.day == now.day - 1 && date.month == now.month && date.year == now.year) {
      return 'Hôm qua';
    }
    return '${date.day}/${date.month}/${date.year}';
  }
}
