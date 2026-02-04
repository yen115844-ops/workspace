import 'dart:io';

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/auth_storage.dart';

class ProfileRepository {
  final ApiClient _api = ApiClient();
  final AuthStorage _storage = AuthStorage();

  Future<void> changePassword(String currentPassword, String newPassword) async {
    await _api.post('/auth/change-password', data: {
      'currentPassword': currentPassword,
      'newPassword': newPassword,
    });
  }

  Future<Map<String, dynamic>> updateProfile({String? name, String? avatar}) async {
    final res = await _api.patch<dynamic>('/users/me', data: {
      if (name != null) 'name': name,
      if (avatar != null) 'avatar': avatar,
    });
    final data = res.data;
    if (data != null && data is Map && data['data'] != null) {
      return data['data'] as Map<String, dynamic>;
    }
    return data as Map<String, dynamic>? ?? {};
  }

  Future<String?> uploadAvatar(File file) async {
    final fileName = file.path.split('/').last;
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path, filename: fileName),
    });
    
    final res = await _api.post<dynamic>('/upload', data: formData);
    final data = res.data;
    
    if (data != null && data is Map) {
      // Ưu tiên path tương đối để lưu DB, tương thích đổi domain
      // Giống cách gửi tin nhắn dùng UploadService.uploadAvatar -> result.valueForDb
      final nested = data['data'] as Map<String, dynamic>?;
      final path = nested?['path'] as String? ?? data['path'] as String?;
      final url = nested?['url'] as String? ?? data['url'] as String?;
      return path ?? url;
    }
    return null;
  }

  Future<Map<String, dynamic>> getProfile() async {
    final res = await _api.get<dynamic>('/users/me');
    final data = res.data;
    if (data != null && data is Map && data['data'] != null) {
      return data['data'] as Map<String, dynamic>;
    }
    return data as Map<String, dynamic>? ?? {};
  }

  Future<void> deleteAccount() async {
    try {
      await _api.delete('/users/me');
    } finally {
      await _storage.clear();
      authEventController.add(AuthEvent.forceLogout);
    }
  }
}
