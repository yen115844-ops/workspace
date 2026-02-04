// Phân tích nội dung tin nhắn thành các đoạn: text, URL, email, phone, @mention, inline code.
// Dùng cho hiển thị tin nhắn với link clickable, highlight mention, v.v.

enum MessageSegmentType {
  text,
  url,
  email,
  phone,
  mention,
  code,
}

class MessageContentSegment {
  final MessageSegmentType type;
  final String raw;

  const MessageContentSegment({required this.type, required this.raw});

  bool get isUrl => type == MessageSegmentType.url;
  bool get isText => type == MessageSegmentType.text;
  bool get isEmail => type == MessageSegmentType.email;
  bool get isPhone => type == MessageSegmentType.phone;
  bool get isMention => type == MessageSegmentType.mention;
  bool get isCode => type == MessageSegmentType.code;
  bool get isSpecial => !isText;
}

/// Match với vị trí (dùng để sắp xếp và tránh overlap)
class _Match {
  final int start;
  final int end;
  final MessageSegmentType type;
  final String raw;

  _Match(this.start, this.end, this.type, this.raw);
}

// --- Regex (thứ tự ưu tiên khi parse: URL > email > code > phone > mention)

final RegExp _urlRegex = RegExp(
  r'(https?:\/\/[^\s<>\[\]()]+|www\.[^\s<>\[\]()]+)',
  caseSensitive: false,
);

/// Email: word@domain.tld (tránh match trong URL bằng cách parse URL trước)
final RegExp _emailRegex = RegExp(
  r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b',
);

/// Inline code: `nội dung` (một backtick mỗi bên)
final RegExp _codeRegex = RegExp(r'`([^`]*)`');

/// Số điện thoại VN: 0xxxxxxxxx (9–11 số), có thể có space/dash
final RegExp _phoneRegex = RegExp(
  r'\b0[0-9][0-9\s\-]{8,14}\b',
);

/// @mention: @username (chữ, số, gạch dưới; không có @ trong username)
final RegExp _mentionRegex = RegExp(r'@([a-zA-Z0-9_]+)');

List<MessageContentSegment> parseMessageContent(String content) {
  if (content.isEmpty) return [];

  final matches = <_Match>[];

  void addMatches(RegExp re, MessageSegmentType type, {String Function(String)? transform}) {
    for (final m in re.allMatches(content)) {
      String raw;
      if (type == MessageSegmentType.code && m.groupCount >= 1) {
        raw = m.group(1) ?? m.group(0)!;
      } else {
        raw = m.group(0)!;
      }
      if (transform != null) raw = transform(raw);
      matches.add(_Match(m.start, m.end, type, raw));
    }
  }

  // Thu thập tất cả match
  addMatches(_urlRegex, MessageSegmentType.url, transform: (s) {
    if (s.startsWith('www.')) return 'https://$s';
    return s;
  });
  addMatches(_emailRegex, MessageSegmentType.email, transform: (s) => s);
  addMatches(_codeRegex, MessageSegmentType.code); // raw đã là nội dung trong ``
  addMatches(_phoneRegex, MessageSegmentType.phone); // Giữ nguyên để hiển thị, chuẩn hóa khi mở tel:
  for (final m in _mentionRegex.allMatches(content)) {
    matches.add(_Match(m.start, m.end, MessageSegmentType.mention, m.group(0)!));
  }

  // Loại bỏ overlap: ưu tiên URL > email > code > phone > mention
  int order(MessageSegmentType t) {
    switch (t) {
      case MessageSegmentType.url: return 0;
      case MessageSegmentType.email: return 1;
      case MessageSegmentType.code: return 2;
      case MessageSegmentType.phone: return 3;
      case MessageSegmentType.mention: return 4;
      case MessageSegmentType.text: return 5;
    }
  }

  matches.sort((a, b) {
    if (a.start != b.start) return a.start.compareTo(b.start);
    return order(a.type).compareTo(order(b.type));
  });

  final nonOverlap = <_Match>[];
  int lastEnd = 0;
  for (final m in matches) {
    if (m.start >= lastEnd) {
      nonOverlap.add(m);
      lastEnd = m.end;
    }
  }

  // Build segments: text + special xen kẽ
  final segments = <MessageContentSegment>[];
  int pos = 0;
  for (final m in nonOverlap) {
    if (m.start > pos) {
      segments.add(MessageContentSegment(
        type: MessageSegmentType.text,
        raw: content.substring(pos, m.start),
      ));
    }
    // Với code, raw đã là nội dung trong backtick; khi hiển thị ta có thể thêm lại backtick hoặc chỉ style
    segments.add(MessageContentSegment(type: m.type, raw: m.raw));
    pos = m.end;
  }
  if (pos < content.length) {
    segments.add(MessageContentSegment(
      type: MessageSegmentType.text,
      raw: content.substring(pos),
    ));
  }

  return segments;
}

/// Kiểm tra nhanh có cần parse (có URL hoặc loại đặc biệt khác)
bool contentNeedsParsing(String content) {
  return _urlRegex.hasMatch(content) ||
      _emailRegex.hasMatch(content) ||
      _codeRegex.hasMatch(content) ||
      _phoneRegex.hasMatch(content) ||
      _mentionRegex.hasMatch(content);
}

/// Lấy URL đầu tiên trong nội dung (để hiển thị link preview). Trả về null nếu không có.
String? getFirstUrl(String content) {
  if (content.isEmpty) return null;
  final m = _urlRegex.firstMatch(content);
  if (m == null) return null;
  String raw = m.group(0)!;
  if (raw.startsWith('www.')) raw = 'https://$raw';
  return raw;
}
