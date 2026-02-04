import 'model_utils.dart';

class UploadResult {
  final String id;
  final String url;
  /// Relative path (e.g. /uploads/xxx) — nên lưu vào DB thay vì url tuyệt đối để đổi domain không cần migrate.
  final String? path;
  final String? name;
  final String? type;
  final int? size;

  UploadResult({
    required this.id,
    required this.url,
    this.path,
    this.name,
    this.type,
    this.size,
  });

  /// Giá trị nên lưu DB: path nếu có, không thì url (tương thích cũ).
  String get valueForDb => path ?? url;

  factory UploadResult.fromJson(Map<String, dynamic> json) {
    return UploadResult(
      id: ModelUtils.parseId(json),
      url: json['url'] as String? ?? '',
      path: json['path'] as String?,
      name: json['name'] as String? ?? json['filename'] as String?,
      type: json['type'] as String? ?? json['mimeType'] as String?,
      size: json['size'] as int?,
    );
  }
}
