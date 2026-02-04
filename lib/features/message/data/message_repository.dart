import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/models/models.dart';
import '../../../core/network/api_client.dart';

class MessageRepository {
  final ApiClient _api = ApiClient();

  /// Tải file từ URL (dùng cho xem/tải file đính kèm tin nhắn). Dùng client có auth.
  Future<Uint8List> downloadAttachmentBytes(String fullUrl) async {
    final res = await _api.get<List<int>>(
      fullUrl,
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data ?? []);
  }

  Future<ChannelStats> getChannelStats(String channelId) async {
    final res = await _api.get<Map<String, dynamic>>('/channels/$channelId/messages/stats');
    final data = res.data;
    Map<String, dynamic>? obj;
    if (data != null && data['data'] != null) {
      obj = data['data'] as Map<String, dynamic>?;
    }
    if (obj == null && data != null) obj = data;
    return ChannelStats.fromJson(obj ?? {});
  }

  Future<ChannelMediaResult> getChannelMedia(
    String channelId,
    String type, {
    int? limit,
    String? cursor,
  }) async {
    final query = <String, dynamic>{'type': type};
    if (limit != null) query['limit'] = limit;
    if (cursor != null) query['cursor'] = cursor;
    final res = await _api.get<Map<String, dynamic>>(
      '/channels/$channelId/messages/media',
      queryParameters: query,
    );
    final data = res.data;
    Map<String, dynamic>? obj;
    if (data != null && data['data'] != null) {
      obj = data['data'] as Map<String, dynamic>?;
    }
    if (obj == null && data != null) obj = data;
    return ChannelMediaResult.fromJson(obj ?? {});
  }

  Future<MessageListResult> getChannelMessages(String channelId,
      {int? limit, String? cursor}) async {
    final query = <String, dynamic>{};
    if (limit != null) query['limit'] = limit;
    if (cursor != null) query['cursor'] = cursor;
    final res = await _api.get<Map<String, dynamic>>(
        '/channels/$channelId/messages',
        queryParameters: query.isNotEmpty ? query : null);
    final data = res.data;
    if (data != null && data['data'] != null) {
      final d = data['data'] as Map<String, dynamic>;
      return MessageListResult.fromJson(d);
    }
    return MessageListResult.fromJson(Map<String, dynamic>.from(data ?? {}));
  }

  Future<MessageModel> sendChannelMessage(String channelId, String content,
      {String? parentId,
      List<MessageAttachment>? attachments,
      String? replyToId}) async {
    final attachmentMaps = attachments
            ?.map((a) => {
                  'url': a.url,
                  if (a.filename != null) 'filename': a.filename,
                  if (a.mimeType != null) 'mimeType': a.mimeType,
                })
            .toList() ??
        [];
    final res = await _api.post<dynamic>('/channels/$channelId/messages',
        data: {
          'content': content,
          if (parentId != null) 'parentId': parentId,
          if (replyToId != null) 'replyToId': replyToId,
          if (attachmentMaps.isNotEmpty) 'attachments': attachmentMaps,
        });
    final data = res.data;
    Map<String, dynamic>? obj;
    if (data != null && data is Map && data['data'] != null) {
      obj = data['data'] as Map<String, dynamic>?;
    }
    if (obj == null && data is Map) obj = data as Map<String, dynamic>;
    return MessageModel.fromJson(obj ?? {});
  }

  Future<MessageModel> editMessage(String messageId, String content) async {
    final res = await _api.patch<dynamic>('/messages/$messageId',
        data: {'content': content});
    final data = res.data;
    Map<String, dynamic>? obj;
    if (data != null && data is Map && data['data'] != null) {
      obj = data['data'] as Map<String, dynamic>?;
    }
    if (obj == null && data is Map) obj = data as Map<String, dynamic>;
    return MessageModel.fromJson(obj ?? {});
  }

  Future<void> deleteMessage(String messageId) async {
    await _api.delete('/messages/$messageId');
  }

  Future<void> markAsRead(String messageId) async {
    await _api.post('/messages/$messageId/read');
  }

  Future<void> markChannelAsRead(String channelId) async {
    await _api.post('/channels/$channelId/messages/read');
  }

  Future<void> addReaction(String messageId, String emoji) async {
    await _api.post('/messages/$messageId/reactions', data: {'emoji': emoji});
  }

  Future<void> removeReaction(String messageId, String emoji) async {
    await _api.delete('/messages/$messageId/reactions/$emoji');
  }

  /// Gửi tin nhắn trả lời trong chuỗi (thread). Hỗ trợ attachments (ảnh đã nén).
  Future<void> sendScheduledMessage(
    String channelId,
    String content,
    DateTime sendAt, {
    List<MessageAttachment>? attachments,
  }) async {
    final attachmentMaps = attachments
            ?.map((a) => {
                  'url': a.url,
                  if (a.filename != null) 'filename': a.filename,
                  if (a.mimeType != null) 'mimeType': a.mimeType,
                })
            .toList() ??
        [];
    await _api.post<dynamic>(
      '/channels/$channelId/scheduled-messages',
      data: {
        'content': content,
        'sendAt': sendAt.toUtc().toIso8601String(),
        if (attachmentMaps.isNotEmpty) 'attachments': attachmentMaps,
      },
    );
  }

  Future<MessageModel> sendThreadReply(String parentMessageId, String content,
      {List<MessageAttachment>? attachments}) async {
    final attachmentMaps = attachments
            ?.map((a) => {
                  'url': a.url,
                  if (a.filename != null) 'filename': a.filename,
                  if (a.mimeType != null) 'mimeType': a.mimeType,
                })
            .toList() ??
        [];
    final res = await _api.post<dynamic>('/messages/$parentMessageId/thread',
        data: {
          'content': content.trim().isEmpty ? ' ' : content,
          if (attachmentMaps.isNotEmpty) 'attachments': attachmentMaps,
        });
    final data = res.data;
    Map<String, dynamic>? obj;
    if (data != null && data is Map && data['data'] != null) {
      obj = data['data'] as Map<String, dynamic>?;
    }
    if (obj == null && data is Map) obj = data as Map<String, dynamic>;
    return MessageModel.fromJson(obj ?? {});
  }

  Future<List<DirectMessageConversation>> getDirectMessages() async {
    final res = await _api.get<dynamic>('/direct-messages');
    final data = res.data;
    List<dynamic> list = [];
    if (data != null && data is Map && data['data'] != null) {
      list = data['data'] as List<dynamic>? ?? [];
    } else if (data is List) {
      list = data;
    }
    return list
        .map((e) =>
            DirectMessageConversation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<MessageListResult> getDirectMessageHistory(String conversationId,
      {int? limit, String? cursor}) async {
    final query = <String, dynamic>{};
    if (limit != null) query['limit'] = limit;
    if (cursor != null) query['cursor'] = cursor;
    final res = await _api.get<Map<String, dynamic>>(
        '/direct-messages/$conversationId/messages',
        queryParameters: query.isNotEmpty ? query : null);
    final data = res.data;
    if (data != null && data['data'] != null) {
      final d = data['data'] as Map<String, dynamic>;
      return MessageListResult.fromJson(d);
    }
    return MessageListResult.fromJson(Map<String, dynamic>.from(data ?? {}));
  }

  Future<MessageModel> sendDirectMessage(String userId, String content) async {
    final res = await _api.post<dynamic>('/direct-messages', data: {
      'recipientId': userId,
      'content': content,
    });
    final data = res.data;
    Map<String, dynamic>? obj;
    if (data != null && data is Map && data['data'] != null) {
      obj = data['data'] as Map<String, dynamic>?;
    }
    if (obj == null && data is Map) obj = data as Map<String, dynamic>;
    return MessageModel.fromJson(obj ?? {});
  }
}
