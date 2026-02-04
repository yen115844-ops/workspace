/// Giới hạn upload - đồng bộ với backend
/// Backend: 10MB (upload.controller.ts limits.fileSize)
/// FE chat: 5MB - kiểm tra trước để tránh lỗi và tiết kiệm bandwidth
class UploadConstants {
  /// Giới hạn backend (10MB) - dùng cho message lỗi
  static const int backendMaxBytes = 10 * 1024 * 1024;

  /// Giới hạn FE cho ảnh chat (5MB) - validate trước khi upload
  static const int chatImageMaxBytes = 5 * 1024 * 1024;

  static String get chatImageMaxMb => '${chatImageMaxBytes ~/ (1024 * 1024)}';
  static String get backendMaxMb => '${backendMaxBytes ~/ (1024 * 1024)}';
}
