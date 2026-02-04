import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/websocket_service.dart';
import 'package:ionicons/ionicons.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/models/models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/safe_navigation.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../workspace/data/workspace_repository.dart';
import '../data/channel_repository.dart';

enum _SortBy { name, joinedAt }

class ChannelMembersScreen extends StatefulWidget {
  const ChannelMembersScreen({
    super.key,
    required this.channelId,
    required this.channelName,
    required this.workspaceId,
  });

  final String channelId;
  final String channelName;
  final String workspaceId;

  @override
  State<ChannelMembersScreen> createState() => _ChannelMembersScreenState();
}

class _ChannelMembersScreenState extends State<ChannelMembersScreen> {
  final ChannelRepository _channelRepo = ChannelRepository();
  final WorkspaceRepository _workspaceRepo = WorkspaceRepository();
  final WebSocketService _ws = WebSocketService();
  final TextEditingController _searchController = TextEditingController();

  List<ChannelMember> _members = [];
  List<WorkspaceMember> _workspaceMembers = [];
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';
  _SortBy _sortBy = _SortBy.name;
  StreamSubscription? _userUpdatedSubscription;

  String? get _currentUserId => ApiClient.currentUserId;

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
    _userUpdatedSubscription = _ws.onUserUpdated.listen((data) {
      final userId = data['id']?.toString();
      final name = data['name'] as String?;
      final avatar = data['avatar'] as String?;
      if (userId == null) return;
      if (mounted && (_members.any((m) => m.id == userId) || _workspaceMembers.any((m) => m.id == userId))) {
        setState(() {
          _members = _members.map((m) {
            if (m.id != userId) return m;
            return ChannelMember(id: m.id, name: name ?? m.name, email: m.email, avatar: avatar ?? m.avatar, joinedAt: m.joinedAt);
          }).toList();
          _workspaceMembers = _workspaceMembers.map((m) {
            if (m.id != userId) return m;
            return WorkspaceMember(id: m.id, name: name ?? m.name, email: m.email, role: m.role, avatar: avatar ?? m.avatar, joinedAt: m.joinedAt);
          }).toList();
        });
      }
    });
  }

  @override
  void dispose() {
    _userUpdatedSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _channelRepo.getMembers(widget.channelId),
        _workspaceRepo.getMembers(widget.workspaceId),
      ]);

      setState(() {
        _members = results[0] as List<ChannelMember>;
        _workspaceMembers = results[1] as List<WorkspaceMember>;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    } catch (e, st) {
      log.e('[ChannelMembers] loadData error', e, st);
      setState(() {
        _error = 'Không thể tải danh sách thành viên';
        _isLoading = false;
      });
    }
  }

  List<ChannelMember> get _filteredAndSortedMembers {
    var list = _members.where((m) {
      if (_searchQuery.isEmpty) return true;
      final name = (m.name.isNotEmpty ? m.name : m.email).toLowerCase();
      final email = m.email.toLowerCase();
      return name.contains(_searchQuery) || email.contains(_searchQuery);
    }).toList();

    list.sort((a, b) {
      final aIsMe = a.id == _currentUserId;
      final bIsMe = b.id == _currentUserId;
      if (aIsMe && !bIsMe) return -1;
      if (!aIsMe && bIsMe) return 1;

      switch (_sortBy) {
        case _SortBy.name:
          final aName = a.name.isNotEmpty ? a.name : a.email;
          final bName = b.name.isNotEmpty ? b.name : b.email;
          return aName.toLowerCase().compareTo(bName.toLowerCase());
        case _SortBy.joinedAt:
          final aDate = a.joinedAt ?? DateTime(0);
          final bDate = b.joinedAt ?? DateTime(0);
          return bDate.compareTo(aDate);
      }
    });
    return list;
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
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => context.maybePopOrGo(
                        '/workspaces/${widget.workspaceId}/channels/${widget.channelId}',
                      ),
                      icon: const Icon(Ionicons.arrow_back),
                      style: IconButton.styleFrom(
                        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Thành viên',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          Text(
                            '# ${widget.channelName}',
                            style: TextStyle(
                              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        onPressed: () => _showAddMemberDialog(context, isDark),
                        icon: const Icon(Ionicons.person_add_outline, color: Colors.white),
                        tooltip: 'Thêm thành viên',
                      ),
                    ),
                  ],
                ),
              ),

              // Search + Sort
              if (!_isLoading && _error == null && _members.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Tìm theo tên hoặc email...',
                            prefixIcon: const Icon(Ionicons.search_outline, size: 20),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Ionicons.close_circle),
                                    onPressed: () => _searchController.clear(),
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
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<_SortBy>(
                        initialValue: _sortBy,
                        tooltip: 'Sắp xếp',
                        icon: Icon(
                          Ionicons.funnel_outline,
                          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        onSelected: (v) => setState(() => _sortBy = v),
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: _SortBy.name,
                            child: Row(
                              children: [
                                Icon(Ionicons.text_outline, size: 20),
                                SizedBox(width: 12),
                                Text('Theo tên (A-Z)'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: _SortBy.joinedAt,
                            child: Row(
                              children: [
                                Icon(Ionicons.calendar_outline, size: 20),
                                SizedBox(width: 12),
                                Text('Mới tham gia'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Members count
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Ionicons.people_outline,
                      size: 18,
                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_filteredAndSortedMembers.length} thành viên'
                          '${_searchQuery.isNotEmpty ? ' (${_members.length} tổng)' : ''}',
                      style: TextStyle(
                        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // Members list
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
        onRetry: _loadData,
      );
    }

    if (_members.isEmpty) {
      return EmptyState(
        icon: Ionicons.people_outline,
        title: 'Chưa có thành viên',
        subtitle: 'Thêm thành viên vào channel để bắt đầu trò chuyện',
        actionLabel: 'Thêm thành viên',
        onAction: () => _showAddMemberDialog(context, isDark),
      );
    }

    final displayList = _filteredAndSortedMembers;
    if (displayList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Ionicons.search_outline, size: 64, color: AppColors.textSecondaryDark),
            const SizedBox(height: 16),
            Text(
              'Không tìm thấy thành viên',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Thử từ khóa khác',
              style: TextStyle(
                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: displayList.length,
        itemBuilder: (context, index) {
          final member = displayList[index];
          return _buildMemberCard(context, member, isDark);
        },
      ),
    );
  }

  Widget _buildMemberCard(BuildContext context, ChannelMember member, bool isDark) {
    final isCurrentUser = member.id == _currentUserId;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          Stack(
            children: [
              _buildAvatar(member),
              if (isCurrentUser)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primaryStart,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: const Text(
                      'Bạn',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: InkWell(
              onTap: () => _showMemberInfoSheet(context, member, isDark),
              borderRadius: BorderRadius.circular(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.name.isNotEmpty ? member.name : member.email,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    member.email,
                    style: TextStyle(
                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                      fontSize: 14,
                    ),
                  ),
                  if (member.joinedAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Tham gia: ${_formatDate(member.joinedAt!)}',
                      style: TextStyle(
                        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isCurrentUser)
            // Nút Rời channel cho chính mình
            TextButton.icon(
              onPressed: () => _showLeaveChannelConfirmation(context, isDark),
              icon: const Icon(Ionicons.exit_outline, size: 18),
              label: const Text('Rời'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.error,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            )
          else
            PopupMenuButton<String>(
              icon: const Icon(Ionicons.ellipsis_vertical),
              tooltip: 'Tùy chọn',
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (value) {
                switch (value) {
                  case 'view_info':
                    _showMemberInfoSheet(context, member, isDark);
                    break;
                  case 'message':
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Nhắn tin cho ${member.name.isNotEmpty ? member.name : member.email} - Đang phát triển'),
                        backgroundColor: AppColors.info,
                      ),
                    );
                    break;
                  case 'remove':
                    _showRemoveConfirmation(context, member);
                    break;
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'view_info',
                  child: Row(
                    children: [
                      Icon(Ionicons.person_outline, size: 20),
                      SizedBox(width: 12),
                      Text('Xem thông tin'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'message',
                  child: Row(
                    children: [
                      Icon(Ionicons.chatbubble_outline, size: 20),
                      SizedBox(width: 12),
                      Text('Nhắn tin'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'remove',
                  child: Row(
                    children: [
                      Icon(Ionicons.remove_circle_outline, size: 20, color: AppColors.error),
                      SizedBox(width: 12),
                      Text('Xóa khỏi channel', style: TextStyle(color: AppColors.error)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildAvatar(ChannelMember member) {
    final avatarUrl = resolveAvatarUrl(member.avatar);
    return UserAvatar(
      imageUrl: avatarUrl,
      name: member.name.isNotEmpty ? member.name : member.email,
      size: 50,
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _showMemberInfoSheet(BuildContext context, ChannelMember member, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _buildAvatar(member),
            if (member.id == _currentUserId)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryStart.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Bạn', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 16),
            Text(
              member.name.isNotEmpty ? member.name : member.email,
              style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              member.email,
              style: TextStyle(
                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
              ),
            ),
            if (member.joinedAt != null) ...[
              const SizedBox(height: 8),
              Text(
                'Tham gia: ${_formatDate(member.joinedAt!)}',
                style: TextStyle(
                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showLeaveChannelConfirmation(BuildContext context, bool isDark) {
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
                children: [
                  Icon(Ionicons.exit_outline, color: AppColors.error),
                  const SizedBox(width: 12),
                  const Text('Rời channel'),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Bạn có chắc chắn muốn rời khỏi channel này? Bạn có thể tham gia lại sau.',
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
                      _leaveChannel(isDark);
                    },
                    style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                    child: const Text('Rời channel'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _leaveChannel(bool isDark) async {
    try {
      await _channelRepo.leave(widget.channelId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã rời channel'),
            backgroundColor: AppColors.success,
          ),
        );
        context.pop();
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể rời channel'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showAddMemberDialog(BuildContext context, bool isDark) {
    final existingIds = _members.map((m) => m.id).toSet();
    final availableMembers = _workspaceMembers.where((m) => !existingIds.contains(m.id)).toList();

    if (availableMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tất cả thành viên workspace đã được thêm vào channel'),
          backgroundColor: AppColors.info,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddMemberSheet(
        isDark: isDark,
        availableMembers: availableMembers,
        onAddSingle: (userId) {
          Navigator.pop(ctx);
          _addMember(userId);
        },
        onAddBulk: (userIds) async {
          Navigator.pop(ctx);
          await _addMembersBulk(userIds);
        },
      ),
    );
  }

  Future<void> _addMember(String userId) async {
    try {
      await _channelRepo.addMember(widget.channelId, userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã thêm thành viên'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadData();
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể thêm thành viên'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _addMembersBulk(List<String> userIds) async {
    if (userIds.isEmpty) return;

    int successCount = 0;
    for (final userId in userIds) {
      try {
        await _channelRepo.addMember(widget.channelId, userId);
        successCount++;
      } catch (_) {
        // Continue with others
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã thêm $successCount thành viên'),
          backgroundColor: successCount > 0 ? AppColors.success : AppColors.error,
        ),
      );
      _loadData();
    }
  }

  void _showRemoveConfirmation(BuildContext context, ChannelMember member) {
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
                  Text('Xóa thành viên'),
                ],
              ),
              const SizedBox(height: 16),
              RichText(
                text: TextSpan(
                  style: DefaultTextStyle.of(ctx).style,
                  children: [
                    const TextSpan(text: 'Bạn có chắc chắn muốn xóa '),
                    TextSpan(
                      text: member.name.isNotEmpty ? member.name : member.email,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const TextSpan(text: ' khỏi channel này?'),
                  ],
                ),
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
                      _removeMember(member);
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

  Future<void> _removeMember(ChannelMember member) async {
    try {
      await _channelRepo.removeMember(widget.channelId, member.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã xóa thành viên'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadData();
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể xóa thành viên'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}



/// Bottom sheet for adding members with search and bulk add
class _AddMemberSheet extends StatefulWidget {
  const _AddMemberSheet({
    required this.isDark,
    required this.availableMembers,
    required this.onAddSingle,
    required this.onAddBulk,
  });

  final bool isDark;
  final List<WorkspaceMember> availableMembers;
  final void Function(String userId) onAddSingle;
  final void Function(List<String> userIds) onAddBulk;

  @override
  State<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<_AddMemberSheet> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<WorkspaceMember> get _filteredMembers {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return widget.availableMembers;
    return widget.availableMembers.where((m) {
      final name = (m.name.isNotEmpty ? m.name : m.email).toLowerCase();
      final email = m.email.toLowerCase();
      return name.contains(q) || email.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredMembers;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: widget.isDark ? AppColors.cardDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: widget.isDark ? AppColors.surfaceDark : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Ionicons.person_add_outline, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Thêm thành viên',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${widget.availableMembers.length} người có thể thêm',
                        style: TextStyle(
                          color: widget.isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Ionicons.close),
                ),
              ],
            ),
          ),
          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Tìm theo tên hoặc email...',
                prefixIcon: const Icon(Ionicons.search_outline, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Ionicons.close_circle),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      )
                    : null,
                filled: true,
                fillColor: widget.isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          // Member list with checkboxes
          Flexible(
            child: filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Ionicons.search_outline, size: 48, color: AppColors.textSecondaryDark),
                        const SizedBox(height: 12),
                        Text(
                          'Không tìm thấy',
                          style: TextStyle(
                            color: widget.isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, index) {
                      final member = filtered[index];
                      final isSelected = _selectedIds.contains(member.id);
                      return ListTile(
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: isSelected,
                              onChanged: (v) {
                                setState(() {
                                  if (v == true) {
                                    _selectedIds.add(member.id);
                                  } else {
                                    _selectedIds.remove(member.id);
                                  }
                                });
                              },
                              activeColor: AppColors.primaryStart,
                            ),
                            const SizedBox(width: 4),
                            UserAvatar(
                              imageUrl: resolveAvatarUrl(member.avatar),
                              name: member.name.isNotEmpty ? member.name : member.email,
                              size: 40,
                            ),
                          ],
                        ),
                        title: Text(
                          member.name.isNotEmpty ? member.name : member.email,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(member.email, style: const TextStyle(fontSize: 12)),
                        trailing: Container(
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: IconButton(
                            icon: const Icon(Ionicons.add, color: Colors.white, size: 20),
                            onPressed: () {
                              widget.onAddSingle(member.id);
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
          // Bulk add button
          if (_selectedIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    widget.onAddBulk(_selectedIds.toList());
                  },
                  icon: const Icon(Ionicons.add_circle_outline),
                  label: Text('Thêm ${_selectedIds.length} người đã chọn'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryStart,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
