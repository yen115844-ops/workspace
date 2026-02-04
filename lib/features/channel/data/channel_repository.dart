import 'package:dio/dio.dart';

import '../../../core/models/models.dart';
import '../../../core/network/api_client.dart';

class ChannelRepository {
  final ApiClient _api = ApiClient();

  /// Helper to extract ApiException from DioException
  Never _rethrowAsApiException(Object e, StackTrace st) {
    if (e is DioException && e.error is ApiException) {
      throw e.error as ApiException;
    }
    if (e is ApiException) {
      throw e;
    }
    throw ApiException(message: 'Đã xảy ra lỗi', originalError: e);
  }

  Future<List<ChannelModel>> listByWorkspace(String workspaceId) async {
    final res = await _api.get<dynamic>('/workspaces/$workspaceId/channels');
    final data = res.data;
    List<dynamic> list = [];
    if (data != null && data is Map && data['data'] != null) {
      list = data['data'] as List<dynamic>? ?? [];
    }
    if (data is List) list = data;
    return list
        .map((e) => ChannelModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ChannelModel> get(String channelId) async {
    final res = await _api.get<dynamic>('/channels/$channelId');
    final data = res.data;
    Map<String, dynamic>? obj;
    if (data != null && data is Map && data['data'] != null) {
      obj = data['data'] as Map<String, dynamic>?;
    }
    if (obj == null && data is Map) obj = data as Map<String, dynamic>;
    return ChannelModel.fromJson(obj ?? {});
  }

  Future<ChannelModel> create(String workspaceId, String name,
      {String type = 'public', String? description}) async {
    final res = await _api.post<dynamic>('/workspaces/$workspaceId/channels',
        data: {
          'name': name,
          'type': type,
          if (description != null) 'description': description,
        });
    final data = res.data;
    Map<String, dynamic>? obj;
    if (data != null && data is Map && data['data'] != null) {
      obj = data['data'] as Map<String, dynamic>?;
    }
    if (obj == null && data is Map) obj = data as Map<String, dynamic>;
    return ChannelModel.fromJson(obj ?? {});
  }

  Future<ChannelModel> update(String channelId,
      {String? name, String? description, String? type, String? avatarUrl, String? chatTheme}) async {
    final res = await _api.patch<dynamic>('/channels/$channelId', data: {
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (type != null) 'type': type,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      if (chatTheme != null) 'chatTheme': chatTheme,
    });
    final data = res.data;
    Map<String, dynamic>? obj;
    if (data != null && data['data'] != null) {
      obj = data['data'] as Map<String, dynamic>?;
    }
    if (obj == null && data is Map) obj = data as Map<String, dynamic>;
    return ChannelModel.fromJson(obj ?? {});
  }

  Future<void> mute(String channelId) async {
    await _api.post('/channels/$channelId/mute');
  }

  Future<void> unmute(String channelId) async {
    await _api.delete('/channels/$channelId/mute');
  }

  Future<bool> isMuted(String channelId) async {
    final res = await _api.get<Map<String, dynamic>>('/channels/$channelId/mute');
    final data = res.data;
    if (data != null && data['data'] != null) {
      final inner = data['data'];
      if (inner is Map) return inner['muted'] as bool? ?? false;
    }
    final map = data is Map ? data as Map<String, dynamic> : null;
    return map?['muted'] as bool? ?? false;
  }

  Future<void> delete(String channelId) async {
    await _api.delete('/channels/$channelId');
  }

  Future<void> join(String channelId) async {
    await _api.post('/channels/$channelId/join');
  }

  Future<void> leave(String channelId) async {
    await _api.post('/channels/$channelId/leave');
  }

  Future<List<ChannelMember>> getMembers(String channelId) async {
    final res = await _api.get<dynamic>('/channels/$channelId/members');
    final data = res.data;
    List<dynamic> list = [];
    if (data != null && data is Map && data['data'] != null) {
      list = data['data'] as List<dynamic>? ?? [];
    }
    if (data is List) list = data;
    return list
        .map((e) => ChannelMember.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> addMember(String channelId, String userId) async {
    try {
      await _api.post('/channels/$channelId/members', data: {'userId': userId});
    } catch (e, st) {
      _rethrowAsApiException(e, st);
    }
  }

  Future<void> removeMember(String channelId, String userId) async {
    try {
      await _api.delete('/channels/$channelId/members/$userId');
    } catch (e, st) {
      _rethrowAsApiException(e, st);
    }
  }
}
