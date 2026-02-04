# LiveKit (Voice room / Huddle) — setup mobile

Tài liệu cài đặt và cấu hình **livekit_client** cho tính năng Voice room (Huddle) trên app Flutter.

---

## 1. Phiên bản và dependency

- **Package:** [livekit_client](https://pub.dev/packages/livekit_client)
- **Phiên bản:** ^2.6.2 (mới nhất tại thời điểm cập nhật)
- **Trong `pubspec.yaml`:**

```yaml
dependencies:
  livekit_client: ^2.6.2
```

Chạy `flutter pub get` sau khi thêm/sửa.

---

## 2. iOS

### 2.1 Quyền trong Info.plist

Đã thêm trong `ios/Runner/Info.plist`:

- **NSCameraUsageDescription** — dùng camera cho video trong Voice room
- **NSMicrophoneUsageDescription** — dùng microphone cho thoại trong Voice room

### 2.2 Background audio (Voice room chạy nền)

Đã thêm `audio` vào **UIBackgroundModes** để thoại tiếp tục khi app ở nền.

### 2.3 Yêu cầu

- iOS 12.1 trở lên
- Flutter 3.3+ khuyến nghị

---

## 3. Android

### 3.1 Quyền trong AndroidManifest.xml

Đã thêm trong `android/app/src/main/AndroidManifest.xml`:

- **CAMERA** — camera cho video
- **RECORD_AUDIO** — ghi âm cho thoại
- **ACCESS_NETWORK_STATE** / **CHANGE_NETWORK_STATE** — kiểm tra mạng
- **MODIFY_AUDIO_SETTINGS** — điều chỉnh âm thanh
- **BLUETOOTH** / **BLUETOOTH_ADMIN** (maxSdkVersion 30) — tai nghe Bluetooth

### 3.2 Uses-feature

- **android.hardware.camera** (required=false)
- **android.hardware.camera.autofocus** (required=false)

`required="false"` để app vẫn cài được trên thiết bị không có camera (chỉ thoại).

### 3.3 Runtime permissions

Trên Android 6+, app cần xin **CAMERA** và **RECORD_AUDIO** tại runtime. `livekit_client` / `flutter_webrtc` thường trigger khi bắt đầu thu; nếu cần xin trước, có thể dùng `permission_handler` hoặc tương tự.

---

## 4. Sử dụng trong app

- **Lấy token:** Gọi API `POST /api/v1/huddle/token` (body: `channelId`, `roomId`, `role`) — xem [HuddleRepository](../../lib/features/huddle/data/huddle_repository.dart).
- **Màn hình Voice room:** [HuddleScreen](../../lib/features/huddle/presentation/huddle_screen.dart) — kết nối LiveKit Room, hiển thị video/audio, bật/tắt mic/camera, rời phòng.
- **Điều hướng:** Từ màn chat channel, bấm icon Voice room (call) trên header → mở Huddle của channel đó.

---

## 5. Backend và LiveKit server

- Backend cần cấu hình `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` (trùng với LiveKit server).
- Chạy LiveKit local: xem [deploy/livekit-local/](../../../deploy/livekit-local/README.md).  
- Chạy LiveKit trên VPS: xem [docs/04-DEPLOYMENT/LIVEKIT_SELF_HOST.md](../../../docs/04-DEPLOYMENT/LIVEKIT_SELF_HOST.md).

---

## 6. Xử lý lỗi thường gặp

- **"Voice room chưa được cấu hình"** (hoặc "Huddle (LiveKit) not configured"): Backend chưa cấu hình LiveKit. Trong `.env` của backend (NestJS) cần có:
  - `LIVEKIT_URL=ws://localhost:7880` (hoặc URL LiveKit của bạn)
  - `LIVEKIT_API_KEY=devkey` (nếu chạy local với deploy/livekit-local)
  - `LIVEKIT_API_SECRET=secret`
  Sau khi sửa, restart backend. Nếu dùng LiveKit local: chạy `docker compose up -d` trong `deploy/livekit-local` trước.

- **"Yêu cầu không hợp lệ"** (400): App đã được cập nhật để hiển thị đúng nội dung lỗi từ API (ví dụ "Voice room chưa được cấu hình"). Kiểm tra lại cấu hình backend và LiveKit server.

---

## 7. Tài liệu tham khảo

- [LiveKit Flutter SDK](https://docs.livekit.io/reference/client-sdk-flutter/)
- [LiveKit Flutter quickstart](https://docs.livekit.io/transport/sdk-platforms/flutter/)
- [livekit_client trên pub.dev](https://pub.dev/packages/livekit_client)
