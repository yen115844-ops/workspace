/// Base URL API — có thể override bằng --dart-define=API_BASE_URL=...
/// Emulator Android: dùng 10.0.2.2 thay localhost
// const String kApiBaseUrl =  "https://workspace-backend.trancongtien.io.vn";
const String kApiBaseUrl =  "http://localhost:3000";
//
const String kApiPrefix = '/api/v1';

/// Nếu false: chặn đổi avatar ngay trên mobile (không hiện nút camera, không cho gọi pick ảnh).
bool get kAllowChangeAvatar => true;
const String kWsPath = '/ws';

/// API key Giphy cho chọn GIF/Sticker (nhãn dán). Lấy tại https://developers.giphy.com/dashboard/
/// Để trống thì không mở picker GIF (hoặc dùng beta key: dc6zaTOxFJmzC).
const String kGiphyApiKey = 'n6A184DYhnHLEC5rLSUMshIbJlbWPjaK';

String get apiBaseUrl => kApiBaseUrl.endsWith('/') ? kApiBaseUrl.substring(0, kApiBaseUrl.length - 1) : kApiBaseUrl;

/// Resolve avatar/attachment URL: nếu là đường dẫn tương đối thì ghép với API base URL.
/// Dùng cho avatar user và ảnh đính kèm tin nhắn (attachment).
String? resolveAvatarUrl(String? avatar) {
  if (avatar == null || avatar.isEmpty) return null;
  if (avatar.startsWith('http://') || avatar.startsWith('https://')) return avatar;
  final base = apiBaseUrl.endsWith('/') ? apiBaseUrl : '$apiBaseUrl/';
  return avatar.startsWith('/') ? '$base${avatar.substring(1)}' : '$base$avatar';
}
