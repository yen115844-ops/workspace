# Hướng dẫn cấu hình Flutter Local Notifications

Dự án đã tích hợp `flutter_local_notifications` với FCM: khi nhận push ở **foreground**, app sẽ hiển thị thông báo qua local notifications (kênh `default`).

## Đã cấu hình

### 1. Pubspec
- `flutter_local_notifications: ^20.0.0`
- `timezone: ^0.10.0` (dùng cho lên lịch thông báo sau này)

### 2. Android

**Gradle (`android/app/build.gradle.kts`):**
- `compileSdk = 35`
- `isCoreLibraryDesugaringEnabled = true`
- `multiDexEnabled = true`
- Dependency: `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")`

**AndroidManifest.xml:**
- Quyền: `POST_NOTIFICATIONS`, `VIBRATE`, `RECEIVE_BOOT_COMPLETED`
- Meta-data FCM: `default_notification_channel_id` = `default`
- Receivers cho scheduled notifications: `ScheduledNotificationReceiver`, `ScheduledNotificationBootReceiver`

**Icon thông báo:** Đang dùng `@mipmap/launcher_icon`. Nếu muốn icon trắng đúng chuẩn Android cho status bar, thêm drawable (vd. `res/drawable/ic_notification.png`) và đổi trong `local_notifications_service.dart`: `AndroidInitializationSettings('ic_notification')`.

### 3. iOS

**AppDelegate.swift:**
- `import UserNotifications`
- Trong `application(_:didFinishLaunchingWithOptions:)`:  
  `UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate`

**Quyền:** FCM đã xin quyền; local notifications dùng chung. Nếu muốn xin quyền muộn hơn, trong `DarwinInitializationSettings` đã set `requestAlertPermission: false` (vì FCM đã xin).

### 4. Code

- **`lib/core/services/local_notifications_service.dart`**
  - `initializeLocalNotifications()`: khởi tạo plugin, tạo kênh Android `default`, xin quyền Android 13+.
  - `showLocalNotification()`: hiển thị thông báo với channel `default`.
  - `showNotificationFromFcm()`: chuyển FCM message thành local notification (dùng khi app ở foreground).

- **`lib/main.dart`**
  - Gọi `initializeLocalNotifications(onDidReceiveNotificationResponse: ...)` sau Firebase, trước `FcmService().initialize()`.
  - Callback tap: hiện chỉ `debugPrint` payload; có thể bổ sung điều hướng (vd. mở màn thông báo, channel, task).

- **FCM foreground:** Trong `FcmService._onForegroundMessage()` gọi `showNotificationFromFcm(message)` để hiện thông báo khi app đang mở.

## Lên lịch thông báo (tùy chọn)

Nếu sau này cần lên lịch (ví dụ nhắc task):

1. Khởi tạo timezone trong `main()`:
   ```dart
   import 'package:timezone/data/latest_all.dart' as tz;
   import 'package:timezone/timezone.dart' as tz;
   tz.initializeTimeZones();
   ```

2. Dùng `flutterLocalNotificationsPlugin.zonedSchedule()` với `AndroidNotificationDetails(..., channelId: kDefaultChannelId)`.

3. Trên Android 14+, nếu cần exact alarm: thêm quyền `SCHEDULE_EXACT_ALARM` hoặc `USE_EXACT_ALARM` trong manifest và gọi `requestExactAlarmsPermission()` (Android implementation của plugin).

## Tài liệu tham khảo

- [flutter_local_notifications trên pub.dev](https://pub.dev/packages/flutter_local_notifications)
- [Compatibility with firebase_messaging](https://pub.dev/packages/flutter_local_notifications#compatibility-with-firebase_messaging) (đã tương thích từ firebase_messaging 6.0.13+)
