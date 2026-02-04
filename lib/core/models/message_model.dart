import 'model_utils.dart';

class MessageListResult {
  final List<MessageModel> items;
  final String? nextCursor;
  final bool hasMore;

  MessageListResult({required this.items, this.nextCursor, this.hasMore = false});

  factory MessageListResult.fromJson(Map<String, dynamic> json) {
    final list = json['items'] as List<dynamic>? ?? json['data'] as List<dynamic>? ?? [];
    return MessageListResult(
      items: list.map((e) => MessageModel.fromJson(e as Map<String, dynamic>)).toList(),
      nextCursor: json['nextCursor']?.toString(),
      hasMore: json['hasMore'] as bool? ?? (json['nextCursor'] != null),
    );
  }
}

class MessageModel {
  final String id;
  final String content;
  final String authorId;
  final String? authorName;
  final String? authorAvatar;
  final DateTime? createdAt;
  final DateTime? editedAt;
  final String? originalContent;
  final String? parentId;
  final List<MessageReaction>? reactions;
  final List<MessageAttachment>? attachments;
  final bool isEdited;
  final List<String>? readBy;
  final String? replyToId;
  final MessageModel? replyTo;

  MessageModel({
    required this.id,
    required this.content,
    required this.authorId,
    this.authorName,
    this.authorAvatar,
    this.createdAt,
    this.editedAt,
    this.originalContent,
    this.parentId,
    this.reactions,
    this.attachments,
    this.isEdited = false,
    this.readBy,
    this.replyToId,
    this.replyTo,
  });

  bool get isRead => readBy != null && readBy!.isNotEmpty;
  int get readCount => readBy?.length ?? 0;

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    // REST: authorId = populated object. WebSocket: author = User object, authorId = uuid
    final authorObj = json['authorId'] is Map ? json['authorId'] as Map : (json['author'] is Map ? json['author'] as Map<String, dynamic> : null);
    String authorId = '';
    String? authorName;
    String? authorAvatar;
    if (authorObj != null) {
      authorId = ModelUtils.parseId(authorObj);
      authorName = authorObj['name'] as String?;
      authorAvatar = authorObj['avatar'] as String?;
    } else {
      authorId = json['authorId']?.toString() ?? (json['author'] is Map ? ModelUtils.parseId(json['author'] as Map) : null) ?? '';
    }

    List<MessageReaction>? reactions;
    if (json['reactions'] is List) {
      reactions = (json['reactions'] as List)
          .map((e) => MessageReaction.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    List<MessageAttachment>? attachments;
    if (json['attachments'] is List) {
      attachments = (json['attachments'] as List)
          .map((e) => MessageAttachment.fromJson(e is Map ? e as Map<String, dynamic> : {'url': e.toString()}))
          .toList();
    }

    List<String>? readBy;
    if (json['readBy'] is List) {
      readBy = (json['readBy'] as List).map((e) => e?.toString() ?? '').toList();
    }

    MessageModel? replyTo;
    String? replyToId;
    final replyData = json['replyToId'];
    if (replyData is Map) {
      replyTo = MessageModel.fromJson(replyData as Map<String, dynamic>);
      replyToId = replyTo.id;
    } else if (replyData != null) {
      replyToId = replyData.toString();
    }
    if (replyTo == null && json['replyTo'] is Map) {
      replyTo = MessageModel.fromJson(json['replyTo'] as Map<String, dynamic>);
    }

    return MessageModel(
      id: ModelUtils.parseId(json),
      content: json['content'] as String? ?? '',
      authorId: authorId,
      authorName: authorName ?? json['authorName'] as String?,
      authorAvatar: authorAvatar,
      createdAt: ModelUtils.parseDate(json['createdAt']),
      editedAt: ModelUtils.parseDate(json['editedAt']),
      originalContent: json['originalContent']?.toString(),
      parentId: json['parentId']?.toString(),
      reactions: reactions,
      attachments: attachments,
      isEdited: json['isEdited'] as bool? ?? (json['editedAt'] != null),
      readBy: readBy,
      replyToId: replyToId,
      replyTo: replyTo,
    );
  }
}

class MessageAttachment {
  final String url;
  final String? filename;
  final String? mimeType;

  MessageAttachment({required this.url, this.filename, this.mimeType});

  factory MessageAttachment.fromJson(Map<String, dynamic> json) {
    return MessageAttachment(
      url: json['url'] as String? ?? '',
      filename: json['filename'] as String?,
      mimeType: json['mimeType'] as String? ?? json['type'] as String?,
    );
  }

  String get displayUrl => url;
}

class MessageReaction {
  final String emoji;
  final int count;
  final List<String> userIds;

  MessageReaction({required this.emoji, this.count = 0, this.userIds = const []});

  factory MessageReaction.fromJson(Map<String, dynamic> json) {
    final userIdsList = json['userIds'] as List<dynamic>? ?? [];
    return MessageReaction(
      emoji: json['emoji'] as String? ?? '',
      count: json['count'] as int? ?? userIdsList.length,
      userIds: userIdsList.map((e) => e?.toString() ?? '').toList(),
    );
  }
}

/// Thống kê channel (tin nhắn, ảnh, file, link)
class ChannelStats {
  final int totalMessages;
  final int totalImages;
  final int totalFiles;
  final int totalLinks;

  ChannelStats({
    required this.totalMessages,
    required this.totalImages,
    required this.totalFiles,
    required this.totalLinks,
  });

  factory ChannelStats.fromJson(Map<String, dynamic> json) {
    return ChannelStats(
      totalMessages: json['totalMessages'] as int? ?? 0,
      totalImages: json['totalImages'] as int? ?? 0,
      totalFiles: json['totalFiles'] as int? ?? 0,
      totalLinks: json['totalLinks'] as int? ?? 0,
    );
  }
}

/// Một item ảnh/file trong danh sách media
class ChannelMediaItem {
  final String messageId;
  final DateTime? createdAt;
  final String? authorId;
  final String? authorName;
  final String? url;
  final String? filename;
  final String? mimeType;
  final String? content;
  final List<Map<String, String>>? links;

  ChannelMediaItem({
    required this.messageId,
    this.createdAt,
    this.authorId,
    this.authorName,
    this.url,
    this.filename,
    this.mimeType,
    this.content,
    this.links,
  });

  factory ChannelMediaItem.fromJson(Map<String, dynamic> json) {
    List<Map<String, String>>? links;
    if (json['links'] is List) {
      links = (json['links'] as List)
          .map((e) => (e is Map ? Map<String, String>.from(e.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''))) : <String, String>{}))
          .toList();
    }
    return ChannelMediaItem(
      messageId: json['messageId']?.toString() ?? '',
      createdAt: ModelUtils.parseDate(json['createdAt']),
      authorId: json['authorId']?.toString(),
      authorName: json['authorName']?.toString(),
      url: json['url']?.toString(),
      filename: json['filename']?.toString(),
      mimeType: json['mimeType']?.toString(),
      content: json['content']?.toString(),
      links: links,
    );
  }
}

class ChannelMediaResult {
  final List<ChannelMediaItem> items;
  final String? nextCursor;
  final bool hasMore;

  ChannelMediaResult({required this.items, this.nextCursor, this.hasMore = false});

  factory ChannelMediaResult.fromJson(Map<String, dynamic> json) {
    final list = json['items'] as List<dynamic>? ?? [];
    return ChannelMediaResult(
      items: list.map((e) => ChannelMediaItem.fromJson(e as Map<String, dynamic>)).toList(),
      nextCursor: json['nextCursor']?.toString(),
      hasMore: json['hasMore'] as bool? ?? (json['nextCursor'] != null),
    );
  }
}

class DirectMessageConversation {
  final String id;
  final String recipientId;
  final String? recipientName;
  final String? recipientAvatar;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;

  DirectMessageConversation({
    required this.id,
    required this.recipientId,
    this.recipientName,
    this.recipientAvatar,
    this.lastMessage,
    this.lastMessageAt,
    this.unreadCount = 0,
  });

  factory DirectMessageConversation.fromJson(Map<String, dynamic> json) {
    final otherUser = json['otherUser'] as Map<String, dynamic>? ?? json['recipient'];
    final lastMsg = json['lastMessage'] as Map<String, dynamic>?;
    return DirectMessageConversation(
      id: ModelUtils.parseId(json),
      recipientId: otherUser != null ? ModelUtils.parseId(otherUser) : (json['recipientId']?.toString() ?? ''),
      recipientName: otherUser?['name'] as String?,
      recipientAvatar: otherUser?['avatar'] as String?,
      lastMessage: lastMsg?['content'] as String?,
      lastMessageAt: ModelUtils.parseDate(lastMsg?['createdAt']),
      unreadCount: json['unreadCount'] as int? ?? 0,
    );
  }
}
