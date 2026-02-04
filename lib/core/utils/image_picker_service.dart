import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ionicons/ionicons.dart';
import '../theme/app_theme.dart';
import '../utils/app_logger.dart';

/// Service for picking images from camera or gallery
class ImagePickerService {
  static final ImagePicker _picker = ImagePicker();

  /// Pick single image from source
  static Future<File?> pickImage({
    ImageSource source = ImageSource.gallery,
    int maxWidth = 1024,
    int maxHeight = 1024,
    int imageQuality = 85,
  }) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: maxWidth.toDouble(),
        maxHeight: maxHeight.toDouble(),
        imageQuality: imageQuality,
      );
      
      if (image != null) {
        log.d('[ImagePicker] Picked image: ${image.path}');
        return File(image.path);
      }
      return null;
    } catch (e) {
      log.e('[ImagePicker] Error picking image', e);
      return null;
    }
  }

  /// Pick multiple images from gallery
  static Future<List<File>> pickMultipleImages({
    int maxWidth = 1024,
    int maxHeight = 1024,
    int imageQuality = 85,
    int? limit,
  }) async {
    try {
      final List<XFile> images = await _picker.pickMultiImage(
        maxWidth: maxWidth.toDouble(),
        maxHeight: maxHeight.toDouble(),
        imageQuality: imageQuality,
        limit: limit,
      );
      
      log.d('[ImagePicker] Picked ${images.length} images');
      return images.map((x) => File(x.path)).toList();
    } catch (e) {
      log.e('[ImagePicker] Error picking multiple images', e);
      return [];
    }
  }

  /// Show bottom sheet to choose between camera and gallery
  static Future<File?> showImageSourceDialog(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Chọn ảnh',
              style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ImageSourceOption(
                  icon: Ionicons.camera_outline,
                  label: 'Camera',
                  color: AppColors.primaryStart,
                  onTap: () => Navigator.pop(ctx, ImageSource.camera),
                ),
                _ImageSourceOption(
                  icon: Ionicons.images_outline,
                  label: 'Thư viện',
                  color: AppColors.accent,
                  onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );

    if (source == null) return null;
    return pickImage(source: source);
  }
}

class _ImageSourceOption extends StatelessWidget {
  const _ImageSourceOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 32, color: color),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
