import 'model_utils.dart';

class ChannelModel {
  final String id;
  final String name;
  final String type;
  final String? description;
  final String? avatarUrl;
  final String workspaceId;
  final int memberCount;
  final DateTime? createdAt;
  final String? lastMessagePreview;
  final DateTime? lastMessageAt;
  /// Client-side: đã tắt thông báo channel (từ API GET :id/mute)
  final bool isMuted;
  /// Theme nền chat theo channel (đồng bộ server — 1 người đổi thì mọi người thấy)
  final String? chatTheme;

  ChannelModel({
    required this.id,
    required this.name,
    this.type = 'public',
    this.description,
    this.avatarUrl,
    this.workspaceId = '',
    this.memberCount = 0,
    this.createdAt,
    this.lastMessagePreview,
    this.lastMessageAt,
    this.isMuted = false,
    this.chatTheme,
  });

  ChannelModel copyWith({
    String? id,
    String? name,
    String? type,
    String? description,
    String? avatarUrl,
    String? workspaceId,
    int? memberCount,
    DateTime? createdAt,
    String? lastMessagePreview,
    DateTime? lastMessageAt,
    bool? isMuted,
    String? chatTheme,
  }) {
    return ChannelModel(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      description: description ?? this.description,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      workspaceId: workspaceId ?? this.workspaceId,
      memberCount: memberCount ?? this.memberCount,
      createdAt: createdAt ?? this.createdAt,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      isMuted: isMuted ?? this.isMuted,
      chatTheme: chatTheme ?? this.chatTheme,
    );
  }

  factory ChannelModel.fromJson(Map<String, dynamic> json) {
    final memberIds = json['memberIds'] as List<dynamic>?;
    final lastMsg = json['lastMessage'] as Map<String, dynamic>?;
    return ChannelModel(
      id: ModelUtils.parseId(json),
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? 'public',
      description: json['description'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      workspaceId: json['workspaceId']?.toString() ?? '',
      memberCount: json['memberCount'] as int? ?? memberIds?.length ?? 0,
      createdAt: ModelUtils.parseDate(json['createdAt']),
      lastMessagePreview: lastMsg?['content'] as String?,
      lastMessageAt: ModelUtils.parseDate(lastMsg?['createdAt']),
      isMuted: json['muted'] as bool? ?? false,
      chatTheme: json['chatTheme'] as String?,
    );
  }
}

class ChannelMember {
  final String id;
  final String name;
  final String email;
  final String? avatar;
  final DateTime? joinedAt;

  ChannelMember({
    required this.id,
    required this.name,
    required this.email,
    this.avatar,
    this.joinedAt,
  });

  factory ChannelMember.fromJson(Map<String, dynamic> json) {
    // Backend: workspace format có 'user', channel private format có 'user' hoặc 'userId' là object
    final userJson = json['user'] as Map<String, dynamic>? ??
        (json['userId'] is Map ? json['userId'] as Map<String, dynamic> : null);
    final user = userJson ?? json;
    final idFromUser = ModelUtils.parseId(user);
    return ChannelMember(
      id: idFromUser.isNotEmpty ? idFromUser : (json['userId']?.toString() ?? ModelUtils.parseId(json)),
      name: user['name'] as String? ?? '',
      email: user['email'] as String? ?? '',
      avatar: user['avatar'] as String?,
      joinedAt: ModelUtils.parseDate(json['joinedAt'] ?? json['createdAt']),
    );
  }
}
