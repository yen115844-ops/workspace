class DateHelper {
  static String formatDateTime(DateTime? date, {String format = 'dd/MM/yyyy HH:mm'}) {
    if (date == null) return '';
    return '${_pad(date.day)}/${_pad(date.month)}/${date.year} ${_pad(date.hour)}:${_pad(date.minute)}';
  }

  static String formatDate(DateTime? date) {
    if (date == null) return '';
    return '${_pad(date.day)}/${_pad(date.month)}/${date.year}';
  }

  static String formatTime(DateTime? date) {
    if (date == null) return '';
    return '${_pad(date.hour)}:${_pad(date.minute)}';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

  static String formatRelative(DateTime? date) {
    if (date == null) return '';
    
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays > 365) {
      final years = (diff.inDays / 365).floor();
      return '$years năm trước';
    } else if (diff.inDays > 30) {
      final months = (diff.inDays / 30).floor();
      return '$months tháng trước';
    } else if (diff.inDays > 7) {
      final weeks = (diff.inDays / 7).floor();
      return '$weeks tuần trước';
    } else if (diff.inDays > 0) {
      return '${diff.inDays} ngày trước';
    } else if (diff.inHours > 0) {
      return '${diff.inHours} giờ trước';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes} phút trước';
    } else {
      return 'Vừa xong';
    }
  }

  static String formatMessageTime(DateTime? date) {
    if (date == null) return '';
    
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateDay = DateTime(date.year, date.month, date.day);

    if (dateDay == today) {
      return formatTime(date);
    } else if (dateDay == today.subtract(const Duration(days: 1))) {
      return 'Hôm qua ${formatTime(date)}';
    } else if (dateDay.isAfter(today.subtract(const Duration(days: 7)))) {
      final weekday = _getWeekday(date.weekday);
      return '$weekday ${formatTime(date)}';
    } else {
      return formatDateTime(date);
    }
  }

  static String _getWeekday(int weekday) {
    const weekdays = ['', 'Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ Nhật'];
    return weekdays[weekday];
  }

  static String formatDueDate(DateTime? date) {
    if (date == null) return 'Chưa đặt';
    
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateDay = DateTime(date.year, date.month, date.day);

    if (dateDay.isBefore(today)) {
      return 'Quá hạn ${formatDate(date)}';
    } else if (dateDay == today) {
      return 'Hôm nay';
    } else if (dateDay == today.add(const Duration(days: 1))) {
      return 'Ngày mai';
    } else {
      return formatDate(date);
    }
  }

  static bool isOverdue(DateTime? date) {
    if (date == null) return false;
    return date.isBefore(DateTime.now());
  }

  static bool isDueToday(DateTime? date) {
    if (date == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateDay = DateTime(date.year, date.month, date.day);
    return dateDay == today;
  }

  static bool isDueSoon(DateTime? date, {int days = 3}) {
    if (date == null) return false;
    final now = DateTime.now();
    final threshold = now.add(Duration(days: days));
    return date.isBefore(threshold) && date.isAfter(now);
  }
}
