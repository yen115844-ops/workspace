import 'model_utils.dart';

class WorkspaceModel {
  final String id;
  final String name;
  final String? slug;
  final String? description;
  final int memberCount;

  WorkspaceModel({
    required this.id,
    required this.name,
    this.slug,
    this.description,
    this.memberCount = 0,
  });

  factory WorkspaceModel.fromJson(Map<String, dynamic> json) {
    final memberIds = json['memberIds'] as List<dynamic>?;
    return WorkspaceModel(
      id: ModelUtils.parseId(json),
      name: json['name'] as String? ?? '',
      slug: json['slug'] as String?,
      description: json['description'] as String?,
      memberCount: json['memberCount'] as int? ?? memberIds?.length ?? 0,
    );
  }
}

class WorkspaceMember {
  final String id;
  final String name;
  final String email;
  final String role;
  final String? avatar;
  final DateTime? joinedAt;

  WorkspaceMember({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.avatar,
    this.joinedAt,
  });

  factory WorkspaceMember.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? json['userId'] as Map<String, dynamic>? ?? json;
    return WorkspaceMember(
      id: ModelUtils.parseId(user),
      name: user['name'] as String? ?? '',
      email: user['email'] as String? ?? '',
      role: json['role'] as String? ?? 'member',
      avatar: user['avatar'] as String?,
      joinedAt: ModelUtils.parseDate(json['createdAt'] ?? json['joinedAt']),
    );
  }
}
