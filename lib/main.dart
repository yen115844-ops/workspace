import 'dart:ui' as ui;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:mobile/firebase_options.dart';

import 'app.dart';
import 'core/services/call_kit_service.dart';
import 'core/services/fcm_service.dart';
import 'core/services/local_notifications_service.dart';
import 'core/storage/app_settings_notifier.dart';
import 'core/storage/cache_service.dart';
import 'core/storage/settings_service.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Bắt lỗi tap-to-focus trong Voice Room: LiveKit gọi setFocusPoint/setExposurePoint
  // khi tap vào video; thiết bị không hỗ trợ sẽ ném PlatformException → tránh spam console.
  final originalOnError = ui.PlatformDispatcher.instance.onError;
  ui.PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    if (error is PlatformException) {
      final code = error.code;
      if (code == 'mediaStreamTrackSetFocusPointFailed' ||
          code == 'mediaStreamTrackSetExposurePointFailed') {
        return true; // Đã xử lý, không propagate
      }
    }
    return originalOnError?.call(error, stack) ?? false;
  };

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await initializeLocalNotifications(
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      FcmService.handleLocalNotificationTap(response.payload);
    },
  );
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await FcmService().initialize();
  await callKitService.initialize(); // Initialize CallKit for incoming calls
  await settingsService.init();
  await CacheService.init();
  appSettingsNotifier.loadFromStorage();
  FlutterNativeSplash.remove();

  runApp(const App());
}
