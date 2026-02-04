import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/models/models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/safe_navigation.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/workspace_repository.dart';

enum _SortBy { name, joinedAt }

class WorkspaceMembersScreen extends StatefulWidget {
  const WorkspaceMembersScreen({super.key, required this.workspaceId, required this.workspaceName});

  final String workspaceId;
  final String workspaceName;

  @override
  State<WorkspaceMembersScreen> createState() => _WorkspaceMembersScreenState();
}

class _WorkspaceMembersScreenState extends State<WorkspaceMembersScreen> {
  final WorkspaceRepository _repository = WorkspaceRepository();
  final TextEditingController _searchController = TextEditingController();

  List<WorkspaceMember> _members = [];
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';
  _SortBy _sortBy = _SortBy.name;

  String? get _currentUserId => ApiClient.currentUserId;

  @override
  void initState() {
    super.initState();
    _loadMembers();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final members = await _repository.getMembers(widget.workspaceId);
      setState(() {
        _members = members;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Không thể tải danh sách thành viên';
        _isLoading = false;
      });
    }
  }

  List<WorkspaceMember> get _filteredAndSortedMembers {
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
                  colors: [AppColors.bgDark, AppColors.cardDark.withOpacity(0.5)],
                )
              : null,
          color: isDark ? null : AppColors.bgLight,
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => context.maybePopOrGo('/workspaces/${widget.workspaceId}'),
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
                            widget.workspaceName,
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
                        onPressed: () => _showInviteDialog(context),
                        icon: const Icon(Ionicons.person_add_outline, color: Colors.white),
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
                const SizedBox(height: 8),
              ],

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
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return ErrorState(
        message: _error!,
        onRetry: _loadMembers,
      );
    }

    if (_members.isEmpty) {
      return EmptyState(
        icon: Ionicons.people_outline,
        title: 'Chưa có thành viên',
        subtitle: 'Mời thành viên để bắt đầu làm việc cùng nhau',
        actionLabel: 'Mời thành viên',
        onAction: () => _showInviteDialog(context),
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
      onRefresh: _loadMembers,
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

  Widget _buildMemberCard(BuildContext context, WorkspaceMember member, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          _buildAvatar(member),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        member.name.isNotEmpty ? member.name : member.email,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    _buildRoleBadge(member.role),
                  ],
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
          PopupMenuButton<String>(
            icon: Icon(
              Ionicons.ellipsis_vertical,
              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'change_role',
                child: Row(
                  children: const [
                    Icon(Ionicons.shield_outline, size: 20),
                    SizedBox(width: 12),
                    Text('Đổi vai trò'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'remove',
                child: Row(
                  children: const [
                    Icon(Ionicons.person_remove_outline, size: 20, color: AppColors.error),
                    SizedBox(width: 12),
                    Text('Xóa khỏi workspace', style: TextStyle(color: AppColors.error)),
                  ],
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'remove') {
                _showRemoveConfirmation(context, member);
              } else if (value == 'change_role') {
                _showChangeRoleDialog(context, member);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(WorkspaceMember member) {
    final avatarUrl = resolveAvatarUrl(member.avatar);
    return UserAvatar(
      imageUrl: avatarUrl,
      name: member.name.isNotEmpty ? member.name : member.email,
      size: 50,
    );
  }

  Widget _buildRoleBadge(String role) {
    Color color;
    String label;
    
    switch (role.toLowerCase()) {
      case 'admin':
      case 'owner':
        color = AppColors.warning;
        label = role == 'owner' ? 'Chủ sở hữu' : 'Admin';
        break;
      default:
        color = AppColors.info;
        label = 'Thành viên';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _showInviteDialog(BuildContext context) {
    final emailController = TextEditingController();
    String selectedRole = 'member';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
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
                    Icon(Ionicons.person_add_outline, color: AppColors.primaryStart),
                    SizedBox(width: 12),
                    Text('Mời thành viên'),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailController,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    hintText: 'Nhập email người dùng',
                    prefixIcon: const Icon(Ionicons.mail_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                Text(
                  'Vai trò',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'member',
                      label: Text('Thành viên'),
                      icon: Icon(Ionicons.person_outline),
                    ),
                    ButtonSegment(
                      value: 'admin',
                      label: Text('Admin'),
                      icon: Icon(Ionicons.shield_outline),
                    ),
                  ],
                  selected: {selectedRole},
                  onSelectionChanged: (v) => setDialogState(() => selectedRole = v.first),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Hủy'),
                    ),
                    FilledButton.icon(
                      onPressed: () async {
                        final email = emailController.text.trim();
                        if (email.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Vui lòng nhập email'),
                              backgroundColor: AppColors.error,
                            ),
                          );
                          return;
                        }
                        
                        Navigator.pop(ctx);
                        _inviteMember(email, selectedRole);
                      },
                      icon: const Icon(Ionicons.send_outline),
                      label: const Text('Mời'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _inviteMember(String email, String role) async {
    try {
      final result = await _repository.inviteMember(widget.workspaceId, email, role: role);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: AppColors.success,
          ),
        );
        _loadMembers();
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
            content: Text('Không thể gửi lời mời'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showRemoveConfirmation(BuildContext context, WorkspaceMember member) {
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
                    const TextSpan(text: ' khỏi workspace?'),
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

  Future<void> _removeMember(WorkspaceMember member) async {
    try {
      await _repository.removeMember(widget.workspaceId, member.id);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã xóa thành viên'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadMembers();
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

  void _showChangeRoleDialog(BuildContext context, WorkspaceMember member) {
    String selectedRole = member.role;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
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
                    Icon(Ionicons.shield_outline, color: AppColors.primaryStart),
                    SizedBox(width: 12),
                    Text('Đổi vai trò'),
                  ],
                ),
                const SizedBox(height: 16),
                RadioListTile<String>(
                  title: const Text('Admin'),
                  subtitle: const Text('Toàn quyền quản lý'),
                  value: 'admin',
                  groupValue: selectedRole,
                  activeColor: AppColors.primaryStart,
                  onChanged: (v) => setDialogState(() => selectedRole = v!),
                ),
                RadioListTile<String>(
                  title: const Text('Thành viên'),
                  subtitle: const Text('Quyền cơ bản'),
                  value: 'member',
                  groupValue: selectedRole,
                  activeColor: AppColors.primaryStart,
                  onChanged: (v) => setDialogState(() => selectedRole = v!),
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
                        _updateMemberRole(member, selectedRole);
                      },
                      child: const Text('Lưu'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _updateMemberRole(WorkspaceMember member, String newRole) async {
    if (member.role == newRole) return;

    try {
      await _repository.updateMemberRole(widget.workspaceId, member.id, newRole);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã cập nhật vai trò'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadMembers();
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
            content: Text('Không thể cập nhật vai trò'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}
