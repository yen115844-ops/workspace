import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Extension để tránh màn đen khi bấm Back từ deep link (stack không có route trước).
/// Nếu có thể pop thì pop (có thể kèm [result]), không thì go [fallbackPath].
extension SafeNavigation on BuildContext {
  /// Fallback mặc định khi không có route để pop (deep link, FCM, ...).
  static const String defaultFallback = '/workspaces';

  /// Bấm back an toàn: pop nếu có stack, không thì go [fallbackPath].
  /// [result] chỉ dùng khi pop (ví dụ trả task từ TaskDetailScreen).
  void maybePopOrGo(String fallbackPath, [Object? result]) {
    if (Navigator.of(this).canPop()) {
      Navigator.of(this).pop(result);
    } else {
      go(fallbackPath);
    }
  }
}
