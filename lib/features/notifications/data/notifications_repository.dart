import '../../../core/network/api_client.dart';

class NotificationModel {
  final String id;
  final String type;
  final String title;
  final String? body;
  final Map<String, dynamic>? data;
  final DateTime? readAt;
  final DateTime createdAt;

  NotificationModel({
    required this.id,
    required this.type,
    required this.title,
    this.body,
    this.data,
    this.readAt,
    required this.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id']?.toString() ?? '',
      type: json['type'] as String? ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String?,
      data: json['data'] as Map<String, dynamic>?,
      readAt: json['readAt'] != null ? DateTime.tryParse(json['readAt'].toString()) : null,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  bool get isRead => readAt != null;
}

class NotificationsRepository {
  final ApiClient _api = ApiClient();

  Future<List<NotificationModel>> getNotifications() async {
    final res = await _api.get<dynamic>('/notifications');
    final raw = res.data;
    final list = raw != null && raw['data'] != null
        ? (raw['data'] as List<dynamic>?)
        : (raw is List ? raw : null);
    if (list == null) return [];
    return list
        .map((e) => NotificationModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<int> getUnreadCount() async {
    final res = await _api.get<Map<String, dynamic>>('/notifications/unread-count');
    final raw = res.data;
    final payload = raw != null && raw['data'] != null
        ? (raw['data'] as Map<String, dynamic>)
        : raw as Map<String, dynamic>?;
    return payload?['count'] as int? ?? 0;
  }

  Future<void> markAsRead(String id) async {
    await _api.patch('/notifications/$id/read');
  }

  Future<void> markAllAsRead() async {
    await _api.patch('/notifications/read-all');
  }
}
