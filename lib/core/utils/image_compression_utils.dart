import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

/// Nén ảnh trước khi upload chat để giảm dung lượng, tiết kiệm bandwidth và storage.
/// - Resize max cạnh 1280px, quality 85, format JPEG (trừ khi ảnh PNG/WebP cần giữ nền trong suốt).
class ImageCompressionUtils {
  /// Max cạnh dài (px). Ảnh lớn hơn sẽ thu nhỏ.
  static const int chatImageMaxDimension = 1280;

  /// Chất lượng nén 0-100. 85 cân bằng dung lượng/chất lượng.
  static const int chatImageQuality = 85;

  /// Nén file ảnh và trả về đường dẫn file đã nén (tạm). Trả về null nếu lỗi hoặc không phải ảnh.
  /// Gọi [File(outPath).delete()] khi không dùng nữa để giải phóng bộ nhớ.
  static Future<String?> compressImageForChat(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final ext = filePath.toLowerCase();
      final isPng = ext.endsWith('.png');
      final isWebP = ext.endsWith('.webp');
      final format = isPng || isWebP
          ? CompressFormat.png
          : CompressFormat.jpeg;

      final dir = await getTemporaryDirectory();
      final targetName =
          'chat_${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
      final outPath =
          '${dir.path}/$targetName${isPng || isWebP ? '.png' : '.jpg'}';

      final result = await FlutterImageCompress.compressWithFile(
        file.absolute.path,
        minWidth: chatImageMaxDimension,
        minHeight: chatImageMaxDimension,
        quality: chatImageQuality,
        format: format,
      );

      if (result == null || result.isEmpty) return null;

      final outFile = File(outPath);
      await outFile.writeAsBytes(result);
      return outPath;
    } catch (_) {
      return null;
    }
  }
}
