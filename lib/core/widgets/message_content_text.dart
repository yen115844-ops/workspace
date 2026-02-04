import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../utils/message_content_parser.dart';

/// Hiển thị nội dung tin nhắn với xử lý theo loại:
/// - URL: link, bấm mở trình duyệt
/// - Email: link, bấm mở mail client
/// - Phone: link, bấm gọi
/// - @mention: highlight, bấm gọi [onMentionTap]
/// - Inline code: font monospace, nền nhạt
class MessageContentText extends StatelessWidget {
  const MessageContentText({
    super.key,
    required this.content,
    required this.style,
    this.linkStyle,
    this.codeStyle,
    this.mentionStyle,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.onMentionTap,
  });

  final String content;
  final TextStyle style;
  final TextStyle? linkStyle;
  final TextStyle? codeStyle;
  final TextStyle? mentionStyle;
  final int? maxLines;
  final TextOverflow overflow;
  /// Bấm vào @username (username không bao gồm @)
  final void Function(String username)? onMentionTap;

  @override
  Widget build(BuildContext context) {
    if (content.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final segments = parseMessageContent(content);
    final needsRich = segments.any((s) => s.isSpecial);

    if (!needsRich) {
      return Text(
        content,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    final link = linkStyle ?? _defaultLinkStyle(context);
    final code = codeStyle ?? _defaultCodeStyle(context);
    final mention = mentionStyle ?? _defaultMentionStyle(context);

    return RichText(
      maxLines: maxLines,
      overflow: overflow,
      text: TextSpan(
        style: style,
        children: [
          for (final segment in segments) _buildSpan(context, segment, link, code, mention),
        ],
      ),
    );
  }

  InlineSpan _buildSpan(
    BuildContext context,
    MessageContentSegment segment,
    TextStyle linkStyle,
    TextStyle codeStyle,
    TextStyle mentionStyle,
  ) {
    if (segment.isText) {
      return TextSpan(text: segment.raw);
    }
    if (segment.isUrl) {
      return TextSpan(
        text: segment.raw,
        style: linkStyle,
        recognizer: TapGestureRecognizer()
          ..onTap = () => _openUrl(segment.raw),
      );
    }
    if (segment.isEmail) {
      return TextSpan(
        text: segment.raw,
        style: linkStyle,
        recognizer: TapGestureRecognizer()
          ..onTap = () => _openMailto(segment.raw),
      );
    }
    if (segment.isPhone) {
      return TextSpan(
        text: segment.raw,
        style: linkStyle,
        recognizer: TapGestureRecognizer()
          ..onTap = () => _openTel(segment.raw),
      );
    }
    if (segment.isMention) {
      final username = segment.raw.startsWith('@') ? segment.raw.substring(1) : segment.raw;
      return TextSpan(
        text: segment.raw,
        style: mentionStyle,
        recognizer: TapGestureRecognizer()
          ..onTap = () => onMentionTap?.call(username),
      );
    }
    if (segment.isCode) {
      return TextSpan(text: '`${segment.raw}`', style: codeStyle);
    }
    return TextSpan(text: segment.raw);
  }

  TextStyle _defaultLinkStyle(BuildContext context) {
    final base = style.color ?? Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black;
    final color = base.computeLuminance() > 0.7
        ? base.withValues(alpha: 0.95)
        : Theme.of(context).colorScheme.primary;
    return style.copyWith(
      color: color,
      decoration: TextDecoration.underline,
      decorationColor: color,
    );
  }

  TextStyle _defaultCodeStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.white.withValues(alpha: 0.12) : AppColors.surfaceLight;
    final fg = style.color ?? (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight);
    return style.copyWith(
      color: fg,
      fontFamily: 'monospace',
      fontSize: (style.fontSize ?? 14) * 0.92,
      backgroundColor: bg,
    );
  }

  TextStyle _defaultMentionStyle(BuildContext context) {
    final base = style.color ?? Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black;
    final color = base.computeLuminance() > 0.7
        ? base.withValues(alpha: 0.95)
        : AppColors.primaryStart;
    return style.copyWith(
      color: color,
      fontWeight: FontWeight.w600,
    );
  }

  static Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  static Future<void> _openMailto(String email) async {
    final uri = Uri.parse('mailto:$email');
    try {
      await launchUrl(uri);
    } catch (_) {}
  }

  static Future<void> _openTel(String raw) async {
    final digits = raw.replaceAll(RegExp(r'[\s\-]'), '');
    final uri = Uri.parse('tel:$digits');
    try {
      await launchUrl(uri);
    } catch (_) {}
  }
}
