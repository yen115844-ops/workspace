import 'model_utils.dart';

class SearchResult {
  final List<MessageSearchResult> messages;
  final List<UserSearchResult> users;
  final List<TaskSearchResult> tasks;
  final List<ChannelSearchResult> channels;

  SearchResult({
    this.messages = const [],
    this.users = const [],
    this.tasks = const [],
    this.channels = const [],
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      messages: (json['messages'] as List<dynamic>?)
              ?.map((e) => MessageSearchResult.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      users: (json['users'] as List<dynamic>?)
              ?.map((e) => UserSearchResult.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      tasks: (json['tasks'] as List<dynamic>?)
              ?.map((e) => TaskSearchResult.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      channels: (json['channels'] as List<dynamic>?)
              ?.map((e) => ChannelSearchResult.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  bool get isEmpty =>
      messages.isEmpty && users.isEmpty && tasks.isEmpty && channels.isEmpty;
}

class MessageSearchResult {
  final String id;
  final String content;
  final String? authorName;
  final String? channelName;
  final String? channelId;
  final String? workspaceId;
  final DateTime? createdAt;

  MessageSearchResult({
    required this.id,
    required this.content,
    this.authorName,
    this.channelName,
    this.channelId,
    this.workspaceId,
    this.createdAt,
  });

  factory MessageSearchResult.fromJson(Map<String, dynamic> json) {
    final author = json['author'] as Map<String, dynamic>?;
    final channel = json['channel'] as Map<String, dynamic>?;
    return MessageSearchResult(
      id: ModelUtils.parseId(json),
      content: json['content'] as String? ?? '',
      authorName:
          json['authorName'] as String? ?? author?['name'] as String?,
      channelName: json['channelName'] as String? ??
          channel?['name'] as String?,
      channelId: json['channelId']?.toString(),
      workspaceId: json['workspaceId']?.toString(),
      createdAt: ModelUtils.parseDate(json['createdAt']),
    );
  }
}

class UserSearchResult {
  final String id;
  final String name;
  final String email;
  final String? avatar;

  UserSearchResult({
    required this.id,
    required this.name,
    required this.email,
    this.avatar,
  });

  factory UserSearchResult.fromJson(Map<String, dynamic> json) {
    return UserSearchResult(
      id: ModelUtils.parseId(json),
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      avatar: json['avatar'] as String?,
    );
  }
}

class TaskSearchResult {
  final String id;
  final String title;
  final String? description;
  final String? status;
  final String? workspaceId;
  final String? workspaceName;

  TaskSearchResult({
    required this.id,
    required this.title,
    this.description,
    this.status,
    this.workspaceId,
    this.workspaceName,
  });

  factory TaskSearchResult.fromJson(Map<String, dynamic> json) {
    final workspace = json['workspace'] as Map<String, dynamic>?;
    return TaskSearchResult(
      id: ModelUtils.parseId(json),
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      status: json['status'] as String? ?? json['columnId'] as String?,
      workspaceId: json['workspaceId']?.toString(),
      workspaceName:
          json['workspaceName'] as String? ?? workspace?['name'] as String?,
    );
  }
}

class ChannelSearchResult {
  final String id;
  final String name;
  final String? type;
  final String? workspaceId;
  final String? workspaceName;

  ChannelSearchResult({
    required this.id,
    required this.name,
    this.type,
    this.workspaceId,
    this.workspaceName,
  });

  factory ChannelSearchResult.fromJson(Map<String, dynamic> json) {
    final workspace = json['workspace'] as Map<String, dynamic>?;
    return ChannelSearchResult(
      id: ModelUtils.parseId(json),
      name: json['name'] as String? ?? '',
      type: json['type'] as String?,
      workspaceId: json['workspaceId']?.toString(),
      workspaceName:
          json['workspaceName'] as String? ?? workspace?['name'] as String?,
    );
  }
}
