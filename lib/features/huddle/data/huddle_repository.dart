import '../../../core/network/api_client.dart';

/// Response from POST /api/v1/huddle/token
class HuddleTokenResponse {
  HuddleTokenResponse({
    required this.token,
    required this.url,
    required this.room,
  });

  final String token;
  final String url;
  final String room;

  factory HuddleTokenResponse.fromJson(Map<String, dynamic> json) {
    return HuddleTokenResponse(
      token: json['token'] as String? ?? '',
      url: json['url'] as String? ?? '',
      room: json['room'] as String? ?? '',
    );
  }
}

class HuddleRepository {
  final ApiClient _api = ApiClient();

  /// Lấy token LiveKit để tham gia voice/video room (Huddle).
  /// [channelId] — channel hiện tại (room = channel-{channelId}).
  /// [roomId] — tùy chọn, nếu có thì dùng thay cho channel-{channelId}.
  /// [role] — participant hoặc host.
  Future<HuddleTokenResponse> getToken({
    String? channelId,
    String? roomId,
    String role = 'participant',
  }) async {
    final body = <String, dynamic>{'role': role};
    if (channelId != null && channelId.isNotEmpty) body['channelId'] = channelId;
    if (roomId != null && roomId.isNotEmpty) body['roomId'] = roomId;

    final res = await _api.post<dynamic>('/huddle/token', data: body);
    final data = res.data;
    final map = data is Map ? data as Map<String, dynamic> : null;
    final obj = map?['data'] is Map<String, dynamic>
        ? map!['data'] as Map<String, dynamic>
        : map;
    return HuddleTokenResponse.fromJson(obj ?? {});
  }

  /// Gửi thông báo cuộc gọi đến tất cả members trong channel.
  /// Gọi API này khi bắt đầu Voice room để các members khác nhận được notification.
  Future<void> notifyCall({
    required String channelId,
    required String channelName,
    String? workspaceId,
  }) async {
    final body = <String, dynamic>{
      'channelId': channelId,
      'channelName': channelName,
    };
    if (workspaceId != null && workspaceId.isNotEmpty) {
      body['workspaceId'] = workspaceId;
    }
    await _api.post<dynamic>('/huddle/notify-call', data: body);
  }
}
