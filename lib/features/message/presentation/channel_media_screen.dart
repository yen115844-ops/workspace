import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ionicons/ionicons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/full_screen_image_viewer.dart';
import '../data/message_repository.dart';

class ChannelMediaScreen extends StatefulWidget {
  const ChannelMediaScreen({
    super.key,
    required this.channelId,
    required this.channelName,
    this.workspaceId,
  });

  final String channelId;
  final String channelName;
  final String? workspaceId;

  @override
  State<ChannelMediaScreen> createState() => _ChannelMediaScreenState();
}

class _ChannelMediaScreenState extends State<ChannelMediaScreen>
    with SingleTickerProviderStateMixin {
  final MessageRepository _repo = MessageRepository();
  late TabController _tabController;

  ChannelStats? _stats;
  bool _statsLoading = true;
  final Map<String, List<ChannelMediaItem>> _items = {
    'images': [],
    'files': [],
    'links': [],
  };
  final Map<String, String?> _nextCursor = {
    'images': null,
    'files': null,
    'links': null,
  };
  final Map<String, bool> _loading = {
    'images': false,
    'files': false,
    'links': false,
  };
  final Map<String, bool> _hasMore = {
    'images': true,
    'files': true,
    'links': true,
  };

  static const List<_TabDef> _tabs = [
    _TabDef(key: 'images', label: 'Ảnh', icon: Ionicons.images_outline),
    _TabDef(key: 'files', label: 'File', icon: Ionicons.document_outline),
    _TabDef(key: 'links', label: 'Link', icon: Ionicons.link_outline),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _loadStats();
    _loadMedia(_tabs[0].key);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    setState(() => _statsLoading = true);
    try {
      final s = await _repo.getChannelStats(widget.channelId);
      if (mounted) setState(() { _stats = s; _statsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  Future<void> _loadMedia(String type, {bool loadMore = false}) async {
    if (_loading[type]! || (!loadMore && _items[type]!.isNotEmpty && !_hasMore[type]!)) return;
    if (loadMore && !(_hasMore[type] ?? false)) return;
    setState(() => _loading[type] = true);
    try {
      final result = await _repo.getChannelMedia(
        widget.channelId,
        type,
        limit: 30,
        cursor: loadMore ? _nextCursor[type] : null,
      );
      if (!mounted) return;
      final list = _items[type]!;
      if (loadMore) {
        list.addAll(result.items);
      } else {
        list.clear();
        list.addAll(result.items);
      }
      _nextCursor[type] = result.nextCursor;
      _hasMore[type] = result.hasMore;
      setState(() => _loading[type] = false);
    } catch (_) {
      if (mounted) setState(() => _loading[type] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.bgDark : AppColors.bgLight,
      appBar: AppBar(
        title: const Text('Thống kê & File đã gửi'),
        leading: IconButton(
          icon: const Icon(Ionicons.arrow_back),
          onPressed: () => context.pop(),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: _tabs
              .map((t) => Tab(
                    icon: Icon(t.icon, size: 20),
                    text: t.label,
                  ))
              .toList(),
          onTap: (i) {
            final key = _tabs[i].key;
            if (_items[key]!.isEmpty && _hasMore[key]!) _loadMedia(key);
          },
        ),
      ),
      body: Column(
        children: [
          _buildStats(isDark),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _tabs.map((t) => _buildList(t.key, isDark)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats(bool isDark) {
    if (_statsLoading) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final s = _stats;
    if (s == null) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _StatCard(
            label: 'Tin nhắn',
            value: s.totalMessages,
            icon: Ionicons.chatbubbles_outline,
            isDark: isDark,
          ),
          const SizedBox(width: 12),
          _StatCard(
            label: 'Ảnh',
            value: s.totalImages,
            icon: Ionicons.images_outline,
            isDark: isDark,
          ),
          const SizedBox(width: 12),
          _StatCard(
            label: 'File',
            value: s.totalFiles,
            icon: Ionicons.document_outline,
            isDark: isDark,
          ),
          const SizedBox(width: 12),
          _StatCard(
            label: 'Link',
            value: s.totalLinks,
            icon: Ionicons.link_outline,
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildList(String type, bool isDark) {
    final list = _items[type]!;
    final isLoading = _loading[type]!;
    final hasMore = _hasMore[type]!;

    if (list.isEmpty && isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _tabs.firstWhere((t) => t.key == type).icon,
              size: 48,
              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
            ),
            const SizedBox(height: 12),
            Text(
              type == 'images'
                  ? 'Chưa có ảnh nào'
                  : type == 'files'
                      ? 'Chưa có file nào'
                      : 'Chưa có link nào',
              style: TextStyle(
                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        _nextCursor[type] = null;
        _hasMore[type] = true;
        await _loadMedia(type);
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: list.length + (hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == list.length) {
            if (hasMore && !isLoading) {
              _loadMedia(type, loadMore: true);
            }
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: isLoading
                    ? const CircularProgressIndicator(strokeWidth: 2)
                    : const SizedBox.shrink(),
              ),
            );
          }
          final item = list[index];
          if (type == 'images') {
            return _buildImageTile(item, isDark);
          }
          if (type == 'files') {
            return _buildFileTile(item, isDark);
          }
          return _buildLinkTile(item, isDark);
        },
      ),
    );
  }

  Widget _buildImageTile(ChannelMediaItem item, bool isDark) {
    final url = resolveAvatarUrl(item.url) ?? item.url ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? AppColors.cardDark : Colors.white,
      child: InkWell(
        onTap: () {
          if (url.isNotEmpty) {
            FullScreenImageViewer.show(context, url);
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  url,
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 72,
                    height: 72,
                    color: AppColors.surfaceDark,
                    child: const Icon(Ionicons.image_outline),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.authorName != null)
                      Text(
                        item.authorName!,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                        ),
                      ),
                    if (item.createdAt != null)
                      Text(
                        _formatDate(item.createdAt!),
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileTile(ChannelMediaItem item, bool isDark) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? AppColors.cardDark : Colors.white,
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primaryStart.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Ionicons.document_outline, color: AppColors.primaryStart),
        ),
        title: Text(
          item.filename ?? item.url?.split('/').last ?? 'File',
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: item.authorName != null || item.createdAt != null
            ? Text(
                '${item.authorName ?? ''} • ${item.createdAt != null ? _formatDate(item.createdAt!) : ''}',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                ),
              )
            : null,
        onTap: () async {
          final u = item.url;
          if (u != null && u.isNotEmpty) {
            final fullUrl = resolveAvatarUrl(u) ?? u;
            try {
              await launchUrl(Uri.parse(fullUrl));
            } catch (_) {}
          }
        },
      ),
    );
  }

  Widget _buildLinkTile(ChannelMediaItem item, bool isDark) {
    final links = item.links ?? [];
    final firstUrl = links.isNotEmpty ? links.first['url'] ?? '' : '';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? AppColors.cardDark : Colors.white,
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Ionicons.link_outline, color: AppColors.accent),
        ),
        title: Text(
          firstUrl,
          style: TextStyle(
            fontSize: 13,
            color: AppColors.primaryStart,
            decoration: TextDecoration.underline,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: item.authorName != null || item.createdAt != null
            ? Text(
                '${item.authorName ?? ''} • ${item.createdAt != null ? _formatDate(item.createdAt!) : ''}',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                ),
              )
            : null,
        onTap: () async {
          if (firstUrl.isNotEmpty) {
            try {
              await launchUrl(Uri.parse(firstUrl));
            } catch (_) {}
          }
        },
      ),
    );
  }

  String _formatDate(DateTime d) {
    final local = d.isUtc ? d.toLocal() : d;
    final now = DateTime.now();
    if (local.day == now.day && local.month == now.month && local.year == now.year) {
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    return '${local.day}/${local.month}/${local.year}';
  }
}

class _TabDef {
  const _TabDef({required this.key, required this.label, required this.icon});
  final String key;
  final String label;
  final IconData icon;
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.isDark,
  });

  final String label;
  final int value;
  final IconData icon;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 22, color: AppColors.primaryStart),
          const SizedBox(height: 4),
          Text(
            value.toString(),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
            ),
          ),
        ],
      ),
    );
  }
}
