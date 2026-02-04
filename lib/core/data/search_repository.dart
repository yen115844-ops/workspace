import '../models/models.dart';
import '../network/api_client.dart';

class SearchRepository {
  final ApiClient _api = ApiClient();

  Future<SearchResult> searchAll(String query, {String? workspaceId}) async {
    final params = <String, dynamic>{'q': query};
    if (workspaceId != null) params['workspaceId'] = workspaceId;

    final res = await _api.get<Map<String, dynamic>>('/search',
        queryParameters: params);
    final data = res.data;

    if (data != null && data['data'] != null) {
      return SearchResult.fromJson(data['data'] as Map<String, dynamic>);
    }
    return SearchResult.fromJson(data ?? {});
  }

  Future<List<MessageSearchResult>> searchMessages(String query,
      {String? channelId, String? workspaceId}) async {
    final params = <String, dynamic>{'q': query};
    if (channelId != null) params['channelId'] = channelId;
    if (workspaceId != null) params['workspaceId'] = workspaceId;

    final res = await _api.get<dynamic>('/search/messages',
        queryParameters: params);
    final data = res.data;

    List<dynamic> list = [];
    if (data != null && data is Map && data['data'] != null) {
      list = data['data'] as List<dynamic>? ?? [];
    } else if (data is List) {
      list = data;
    }
    return list
        .map((e) => MessageSearchResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<UserSearchResult>> searchUsers(String query,
      {String? workspaceId}) async {
    final params = <String, dynamic>{'q': query};
    if (workspaceId != null) params['workspaceId'] = workspaceId;

    final res =
        await _api.get<dynamic>('/search/users', queryParameters: params);
    final data = res.data;

    List<dynamic> list = [];
    if (data != null && data is Map && data['data'] != null) {
      list = data['data'] as List<dynamic>? ?? [];
    } else if (data is List) {
      list = data;
    }
    return list
        .map((e) => UserSearchResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<TaskSearchResult>> searchTasks(String query,
      {String? workspaceId}) async {
    final params = <String, dynamic>{'q': query};
    if (workspaceId != null) params['workspaceId'] = workspaceId;

    final res =
        await _api.get<dynamic>('/search/tasks', queryParameters: params);
    final data = res.data;

    List<dynamic> list = [];
    if (data != null && data is Map && data['data'] != null) {
      list = data['data'] as List<dynamic>? ?? [];
    } else if (data is List) {
      list = data;
    }
    return list
        .map((e) => TaskSearchResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ChannelSearchResult>> searchChannels(String query,
      {String? workspaceId}) async {
    final params = <String, dynamic>{'q': query};
    if (workspaceId != null) params['workspaceId'] = workspaceId;

    final res =
        await _api.get<dynamic>('/search/channels', queryParameters: params);
    final data = res.data;

    List<dynamic> list = [];
    if (data != null && data is Map && data['data'] != null) {
      list = data['data'] as List<dynamic>? ?? [];
    } else if (data is List) {
      list = data;
    }
    return list
        .map((e) => ChannelSearchResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
