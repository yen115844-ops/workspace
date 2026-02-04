/// Utilities for parsing API responses (PostgreSQL uses `id`, MongoDB used `_id`)
class ModelUtils {
  ModelUtils._();

  /// Parse ID from json - backend PostgreSQL returns `id`, legacy MongoDB used `_id`
  static String parseId(dynamic json) {
    if (json == null) return '';
    if (json is Map) {
      return json['id']?.toString() ?? json['_id']?.toString() ?? '';
    }
    return json.toString();
  }

  /// Parse DateTime from json
  static DateTime? parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  /// Parse list of IDs from json (handles both string IDs and ObjectIds)
  static List<String> parseIdList(dynamic value) {
    if (value == null || value is! List) return [];
    return value.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
  }
}
