import '../../../core/models/models.dart';
import '../../../core/network/api_client.dart';

class TaskRepository {
  final ApiClient _api = ApiClient();

  Future<List<TaskModel>> list(String workspaceId, {String? columnId}) async {
    final query = columnId != null ? {'columnId': columnId} : null;
    final res = await _api.get<dynamic>('/workspaces/$workspaceId/tasks',
        queryParameters: query);
    final data = res.data;
    List<dynamic> list = [];
    if (data != null && data is Map && data['data'] != null) {
      list = data['data'] as List<dynamic>? ?? [];
    }
    if (data is List) list = data;
    return list
        .map((e) => TaskModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<TaskModel> get(String taskId) async {
    final res = await _api.get<dynamic>('/tasks/$taskId');
    final data = res.data;
    Map<String, dynamic>? obj;
    if (data != null && data is Map && data['data'] != null) {
      obj = data['data'] as Map<String, dynamic>?;
    }
    if (obj == null && data is Map) obj = data as Map<String, dynamic>;
    return TaskModel.fromJson(obj ?? {});
  }

  Future<BoardModel?> getBoard(String workspaceId) async {
    final res = await _api.get<dynamic>('/workspaces/$workspaceId/boards');
    final data = res.data;
    Map<String, dynamic>? obj;
    if (data != null && data is Map && data['data'] != null) {
      obj = data['data'] as Map<String, dynamic>?;
    }
    if (obj == null && data is Map) obj = data as Map<String, dynamic>;
    return obj != null ? BoardModel.fromJson(obj) : null;
  }

  Future<TaskModel> create(String workspaceId, String title,
      {String? description,
      String? columnId,
      String? assigneeId,
      DateTime? dueDate,
      String? priority}) async {
    final res = await _api.post<dynamic>(
        '/workspaces/$workspaceId/tasks',
        data: {
          'title': title,
          if (description != null) 'description': description,
          if (columnId != null) 'columnId': columnId,
          if (assigneeId != null) 'assigneeId': assigneeId,
          if (dueDate != null) 'dueDate': dueDate.toIso8601String(),
          if (priority != null) 'priority': priority,
        });
    final data = res.data;
    Map<String, dynamic>? obj;
    if (data != null && data is Map && data['data'] != null) {
      obj = data['data'] as Map<String, dynamic>?;
    }
    if (obj == null && data is Map) obj = data as Map<String, dynamic>;
    return TaskModel.fromJson(obj ?? {});
  }

  Future<TaskModel> update(String taskId,
      {String? title,
      String? description,
      String? columnId,
      String? assigneeId,
      bool clearAssignee = false,
      DateTime? dueDate,
      String? priority,
      String? status}) async {
    final body = <String, dynamic>{};
    if (title != null) body['title'] = title;
    if (description != null) body['description'] = description;
    if (columnId != null) body['columnId'] = columnId;
    if (clearAssignee) {
      body['assigneeId'] = null;
    } else if (assigneeId != null) {
      body['assigneeId'] = assigneeId;
    }
    if (dueDate != null) body['dueDate'] = dueDate.toIso8601String();
    if (priority != null) body['priority'] = priority;
    if (status != null) body['status'] = status;

    final res = await _api.patch<dynamic>('/tasks/$taskId', data: body);
    final data = res.data;
    Map<String, dynamic>? obj;
    if (data != null && data is Map && data['data'] != null) {
      obj = data['data'] as Map<String, dynamic>?;
    }
    if (obj == null && data is Map) obj = data as Map<String, dynamic>;
    return TaskModel.fromJson(obj ?? {});
  }

  Future<void> delete(String taskId) async {
    await _api.delete('/tasks/$taskId');
  }

  Future<void> moveToColumn(String taskId, String columnId,
      {int? position}) async {
    await _api.patch<dynamic>('/tasks/$taskId/move', data: {
      'columnId': columnId,
      if (position != null) 'position': position,
    });
  }

  Future<List<TaskComment>> getComments(String taskId) async {
    final res = await _api.get<dynamic>('/tasks/$taskId/comments');
    final data = res.data;
    List<dynamic> list = [];
    if (data != null && data is Map && data['data'] != null) {
      list = data['data'] as List<dynamic>? ?? [];
    }
    if (data is List) list = data;
    return list
        .map((e) => TaskComment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<TaskComment> addComment(String taskId, String content) async {
    final res = await _api.post<dynamic>('/tasks/$taskId/comments',
        data: {'content': content});
    final data = res.data;
    Map<String, dynamic>? obj;
    if (data != null && data is Map && data['data'] != null) {
      obj = data['data'] as Map<String, dynamic>?;
    }
    if (obj == null && data is Map) obj = data as Map<String, dynamic>;
    return TaskComment.fromJson(obj ?? {});
  }

  Future<void> deleteComment(String taskId, String commentId) async {
    await _api.delete('/tasks/$taskId/comments/$commentId');
  }
}
