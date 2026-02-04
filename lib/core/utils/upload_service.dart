import 'dart:io';

import 'package:dio/dio.dart';
import '../models/models.dart';
import '../network/api_client.dart';
import 'app_logger.dart';
import 'image_compression_utils.dart';

class UploadService {
  static final ApiClient _api = ApiClient();

  static Future<UploadResult> uploadFile(String filePath, {String? folder}) async {
    try {
      final fileName = filePath.split('/').last;
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
        if (folder != null) 'folder': folder,
      });

      final res = await _api.post<Map<String, dynamic>>('/upload', data: formData);
      final data = res.data;

      if (data != null && data['data'] != null) {
        return UploadResult.fromJson(data['data'] as Map<String, dynamic>);
      }
      return UploadResult.fromJson(data ?? {});
    } catch (e) {
      log.e('[Upload] Error uploading file', e);
      rethrow;
    }
  }

  static Future<List<UploadResult>> uploadFiles(List<String> filePaths,
      {String? folder}) async {
    try {
      final files = await Future.wait(
        filePaths.map((path) async {
          final fileName = path.split('/').last;
          return MapEntry('files', await MultipartFile.fromFile(path, filename: fileName));
        }),
      );

      final formData = FormData.fromMap({
        if (folder != null) 'folder': folder,
      });

      for (final file in files) {
        formData.files.add(file);
      }

      final res =
          await _api.post<Map<String, dynamic>>('/upload/multiple', data: formData);
      final data = res.data;

      if (data != null && data['data'] is List) {
        return (data['data'] as List)
            .map((e) => UploadResult.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      log.e('[Upload] Error uploading files', e);
      rethrow;
    }
  }

  static Future<String?> uploadAvatar(String filePath) async {
    try {
      final result = await uploadFile(filePath, folder: 'avatars');
      return result.valueForDb;
    } catch (e) {
      log.e('[Upload] Error uploading avatar', e);
      return null;
    }
  }

  static Future<MessageAttachment?> uploadAttachment(String filePath) async {
    try {
      final result = await uploadFile(filePath, folder: 'attachments');
      return MessageAttachment(url: result.valueForDb, filename: result.name, mimeType: result.type);
    } catch (e) {
      log.e('[Upload] Error uploading attachment', e);
      return null;
    }
  }

  /// Upload ảnh chat đã nén (resize + compress) để giảm dung lượng.
  /// Dùng cho tin nhắn có hình ảnh trong channel/DM.
  static Future<MessageAttachment?> uploadChatImageAttachment(String filePath) async {
    String? pathToUpload = filePath;
    String? tempCompressedPath;
    try {
      final compressed = await ImageCompressionUtils.compressImageForChat(filePath);
      if (compressed != null) {
        tempCompressedPath = compressed;
        pathToUpload = compressed;
      }
      final result = await uploadFile(pathToUpload, folder: 'attachments');
      return MessageAttachment(
        url: result.valueForDb,
        filename: result.name,
        mimeType: result.type,
      );
    } catch (e) {
      log.e('[Upload] Error uploading chat image', e);
      return null;
    } finally {
      if (tempCompressedPath != null) {
        try {
          final f = File(tempCompressedPath);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
  }
}
