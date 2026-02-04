import 'model_utils.dart';

class TaskModel {
  final String id;
  final String title;
  final String? description;
  final String columnId;
  final String? assigneeId;
  final String? assigneeName;
  final String? assigneeAvatar;
  final DateTime? dueDate;
  final String priority;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<String>? labels;

  TaskModel({
    required this.id,
    required this.title,
    this.description,
    this.columnId = 'todo',
    this.assigneeId,
    this.assigneeName,
    this.assigneeAvatar,
    this.dueDate,
    this.priority = 'normal',
    this.status = 'todo',
    this.createdAt,
    this.updatedAt,
    this.labels,
  });

  factory TaskModel.fromJson(Map<String, dynamic> json) {
    final assignee = json['assignee'] as Map<String, dynamic>? ?? json['assigneeId'];
    String? assigneeId;
    String? assigneeName;
    String? assigneeAvatar;
    if (assignee is Map) {
      assigneeId = ModelUtils.parseId(assignee);
      assigneeName = assignee['name'] as String?;
      assigneeAvatar = assignee['avatar'] as String?;
    } else if (assignee != null) {
      assigneeId = assignee.toString();
    }

    return TaskModel(
      id: ModelUtils.parseId(json),
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      columnId: json['columnId'] as String? ?? 'todo',
      assigneeId: assigneeId ?? json['assigneeId']?.toString(),
      assigneeName: assigneeName,
      assigneeAvatar: assigneeAvatar,
      dueDate: ModelUtils.parseDate(json['dueDate']),
      priority: json['priority'] as String? ?? 'normal',
      status: json['status'] as String? ?? 'todo',
      createdAt: ModelUtils.parseDate(json['createdAt']),
      updatedAt: ModelUtils.parseDate(json['updatedAt']),
      labels: (json['labels'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
    );
  }

  TaskModel copyWith({
    String? title,
    String? description,
    String? columnId,
    String? assigneeId,
    String? assigneeName,
    String? assigneeAvatar,
    DateTime? dueDate,
    String? priority,
    String? status,
    List<String>? labels,
  }) {
    return TaskModel(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      columnId: columnId ?? this.columnId,
      assigneeId: assigneeId ?? this.assigneeId,
      assigneeName: assigneeName ?? this.assigneeName,
      assigneeAvatar: assigneeAvatar ?? this.assigneeAvatar,
      dueDate: dueDate ?? this.dueDate,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt,
      labels: labels ?? this.labels,
    );
  }
}

class TaskComment {
  final String id;
  final String content;
  final String authorId;
  final String? authorName;
  final String? authorAvatar;
  final DateTime createdAt;

  TaskComment({
    required this.id,
    required this.content,
    required this.authorId,
    this.authorName,
    this.authorAvatar,
    required this.createdAt,
  });

  factory TaskComment.fromJson(Map<String, dynamic> json) {
    final author = json['author'] as Map<String, dynamic>? ?? json['authorId'] as Map<String, dynamic>? ?? json['user'];
    return TaskComment(
      id: ModelUtils.parseId(json),
      content: json['content'] as String? ?? '',
      authorId: author is Map ? ModelUtils.parseId(author) : (json['authorId']?.toString() ?? ''),
      authorName: author is Map ? author['name'] as String? : null,
      authorAvatar: author is Map ? author['avatar'] as String? : null,
      createdAt: ModelUtils.parseDate(json['createdAt']) ?? DateTime.now(),
    );
  }
}

class BoardModel {
  final List<BoardColumnModel> columns;

  BoardModel({required this.columns});

  factory BoardModel.fromJson(Map<String, dynamic> json) {
    final list = json['columns'] as List<dynamic>? ?? [];
    return BoardModel(
      columns: list.map((e) => BoardColumnModel.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

class BoardColumnModel {
  final String id;
  final String title;
  final int order;

  BoardColumnModel({required this.id, required this.title, this.order = 0});

  factory BoardColumnModel.fromJson(Map<String, dynamic> json) {
    return BoardColumnModel(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      order: json['order'] as int? ?? 0,
    );
  }
}
