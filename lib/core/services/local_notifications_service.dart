import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../utils/app_logger.dart';

/// ID kênh thông báo dùng chung với FCM (phải trùng với default_notification_channel_id trong AndroidManifest).
const String kDefaultChannelId = 'default';
const String kDefaultChannelName = 'Thông báo';

/// Custom notification sound file name (without extension for Android, with extension for iOS)
const String kNotificationSoundAndroid = 'notification_sound';
const String kNotificationSoundIOS = 'notification_sound.caf';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

/// Khởi tạo và cấu hình local notifications (tạo channel, xử lý tap).
/// Gọi một lần sau Firebase.initializeApp(), trước FcmService.initialize().
Future<void> initializeLocalNotifications({
  void Function(NotificationResponse)? onDidReceiveNotificationResponse,
}) async {
  const androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
  final darwinInit = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );
  final initSettings = InitializationSettings(
    android: androidInit,
    iOS: darwinInit,
  );

  await flutterLocalNotificationsPlugin.initialize(
    settings: initSettings,
    onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
  );

  if (Platform.isAndroid) {
    final androidPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    const channel = AndroidNotificationChannel(
      kDefaultChannelId,
      kDefaultChannelName,
      description: 'Kênh thông báo mặc định',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      sound: RawResourceAndroidNotificationSound(kNotificationSoundAndroid),
    );
    await androidPlugin?.createNotificationChannel(channel);
    if (kDebugMode) log.d('[LocalNotifications] Channel "$kDefaultChannelId" created');
  }
}

/// Hiển thị thông báo local (dùng khi nhận FCM ở foreground hoặc lên lịch).
Future<void> showLocalNotification({
  required int id,
  required String title,
  String? body,
  String? payload,
  Map<String, String?>? data,
}) async {
  const androidDetails = AndroidNotificationDetails(
    kDefaultChannelId,
    kDefaultChannelName,
    channelDescription: 'Kênh thông báo mặc định',
    importance: Importance.high,
    priority: Priority.high,
    playSound: true,
    sound: RawResourceAndroidNotificationSound(kNotificationSoundAndroid),
  );
  const darwinDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
    sound: kNotificationSoundIOS,
  );
  const details = NotificationDetails(
    android: androidDetails,
    iOS: darwinDetails,
  );
  await flutterLocalNotificationsPlugin.show(
    id: id,
    title: title,
    body: body ?? '',
    notificationDetails: details,
    payload: payload ?? data?.toString(),
  );
}

/// Tạo ID số từ messageId FCM để dùng làm notification id.
int notificationIdFromMessageId(String? messageId) {
  if (messageId?.isEmpty ?? true) {
    return DateTime.now().millisecondsSinceEpoch.remainder(0x7FFFFFFF);
  }
  return messageId!.hashCode.abs().remainder(0x7FFFFFFF);
}

/// Hiển thị thông báo từ FCM message (foreground).
Future<void> showNotificationFromFcm(RemoteMessage message) async {
  try {
    final notification = message.notification;
    final data = message.data;
    String title = notification?.title ?? data['title'] ?? 'Thông báo';
    String? body = notification?.body ?? data['body'];
    if (body == null && data.isNotEmpty) {
      final authorName = data['authorName'];
      final channelName = data['channelName'];
      if (channelName != null) {
        body = authorName != null ? 'Tin nhắn từ $authorName trong #$channelName' : 'Tin nhắn trong #$channelName';
      } else {
        body = authorName != null ? 'Tin nhắn từ $authorName' : 'Tin nhắn mới';
      }
    }
    final id = notificationIdFromMessageId(message.messageId);
    final payloadJson = message.data.isNotEmpty ? jsonEncode(message.data) : null;
    await showLocalNotification(
      id: id,
      title: title,
      body: body,
      payload: payloadJson,
      data: message.data.isNotEmpty
          ? Map.fromEntries(
              message.data.entries.map((e) => MapEntry(e.key, e.value)))
          : null,
    );
  } catch (e) {
    if (kDebugMode) log.e('[LocalNotifications] showNotificationFromFcm failed', e);
  }
}
