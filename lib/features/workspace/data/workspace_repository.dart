import 'package:dio/dio.dart';

import '../../../core/models/models.dart';
import '../../../core/network/api_client.dart';

class InviteResult {
  final String status;
  final String message;
  InviteResult({required this.status, required this.message});
}

class WorkspaceRepository {
  final ApiClient _api = ApiClient();

  Future<List<WorkspaceModel>> list() async {
    final res = await _api.get<dynamic>('/workspaces');
    final data = res.data;
    List<dynamic> list = [];
    if (data != null && data is Map && data['data'] != null) {
      final d = data['data'];
      if (d is List) list = d;
    } else if (data is List) {
      list = data;
    }
    return list
        .map((e) => WorkspaceModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<WorkspaceModel> create(String name, {String? slug}) async {
    final res = await _api.post<Map<String, dynamic>>('/workspaces',
        data: {'name': name, if (slug != null) 'slug': slug});
    final data = res.data;
    if (data != null && data['data'] != null) {
      return WorkspaceModel.fromJson(data['data'] as Map<String, dynamic>);
    }
    return WorkspaceModel.fromJson(data as Map<String, dynamic>);
  }

  Future<WorkspaceModel> update(String workspaceId,
      {String? name, String? slug}) async {
    final res = await _api.patch<Map<String, dynamic>>(
        '/workspaces/$workspaceId',
        data: {
          if (name != null) 'name': name,
          if (slug != null) 'slug': slug,
        });
    final data = res.data;
    if (data != null && data['data'] != null) {
      return WorkspaceModel.fromJson(data['data'] as Map<String, dynamic>);
    }
    return WorkspaceModel.fromJson(data as Map<String, dynamic>);
  }

  Future<void> delete(String workspaceId) async {
    await _api.delete('/workspaces/$workspaceId');
  }

  Future<List<WorkspaceMember>> getMembers(String workspaceId) async {
    final res = await _api.get<dynamic>('/workspaces/$workspaceId/members');
    final data = res.data;
    List<dynamic> list = [];
    if (data != null && data is Map && data['data'] != null) {
      list = data['data'] as List<dynamic>? ?? [];
    } else if (data is List) {
      list = data;
    }
    return list
        .map((e) => WorkspaceMember.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<InviteResult> inviteMember(String workspaceId, String email,
      {String role = 'member'}) async {
    final res = await _api.post<Map<String, dynamic>>(
        '/workspaces/$workspaceId/members',
        data: {'email': email, 'role': role});
    final raw = res.data;
    final payload = raw != null && raw['data'] != null
        ? (raw['data'] as Map<String, dynamic>)
        : raw as Map<String, dynamic>?;
    final status = payload?['status'] as String? ?? 'added';
    final message = payload?['message'] as String? ?? 'Đã gửi lời mời';
    return InviteResult(status: status, message: message);
  }

  Future<Map<String, dynamic>> getInviteByToken(String token) async {
    final res = await _api.get<Map<String, dynamic>>('/invites/$token',
        options: Options(extra: {'skipAuth': true})); // Public endpoint
    final raw = res.data;
    final payload = raw != null && raw['data'] != null
        ? (raw['data'] as Map<String, dynamic>)
        : raw as Map<String, dynamic>?;
    return payload ?? {};
  }

  Future<Map<String, dynamic>> acceptInvite(String token) async {
    final res =
        await _api.post<Map<String, dynamic>>('/invites/$token/accept');
    final raw = res.data;
    final payload = raw != null && raw['data'] != null
        ? (raw['data'] as Map<String, dynamic>)
        : raw as Map<String, dynamic>?;
    return payload ?? {};
  }

  Future<void> updateMemberRole(
      String workspaceId, String userId, String role) async {
    await _api.patch('/workspaces/$workspaceId/members/$userId',
        data: {'role': role});
  }

  Future<void> removeMember(String workspaceId, String userId) async {
    await _api.delete('/workspaces/$workspaceId/members/$userId');
  }
}
