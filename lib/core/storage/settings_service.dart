import 'package:shared_preferences/shared_preferences.dart';

/// Service for persisting user settings
class SettingsService {
  static const String _keyThemeMode = 'theme_mode';
  static const String _keyLanguage = 'language';
  static const String _keyNotificationsEnabled = 'notifications_enabled';
  static const String _keyMessageNotifications = 'message_notifications';
  static const String _keyTaskNotifications = 'task_notifications';
  static const String _keyMentionNotifications = 'mention_notifications';
  static const String _keyChannelNotifications = 'channel_notifications';
  static const String _keySoundEnabled = 'sound_enabled';
  static const String _keyVibrationEnabled = 'vibration_enabled';
  static const String _keyFontSize = 'font_size';
  static const String _keyCompactMode = 'compact_mode';
  static const String _keyLastWorkspaceId = 'last_workspace_id';
  static const String _keyChatTheme = 'chat_theme';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  SharedPreferences get _p {
    if (_prefs == null) {
      throw StateError('SettingsService not initialized. Call init() first.');
    }
    return _prefs!;
  }

  // Theme settings
  String get themeMode => _p.getString(_keyThemeMode) ?? 'system';
  Future<void> setThemeMode(String mode) => _p.setString(_keyThemeMode, mode);

  // Language settings
  String get language => _p.getString(_keyLanguage) ?? 'vi';
  Future<void> setLanguage(String lang) => _p.setString(_keyLanguage, lang);

  // Notification settings
  bool get notificationsEnabled => _p.getBool(_keyNotificationsEnabled) ?? true;
  Future<void> setNotificationsEnabled(bool enabled) => _p.setBool(_keyNotificationsEnabled, enabled);

  bool get messageNotifications => _p.getBool(_keyMessageNotifications) ?? true;
  Future<void> setMessageNotifications(bool enabled) => _p.setBool(_keyMessageNotifications, enabled);

  bool get taskNotifications => _p.getBool(_keyTaskNotifications) ?? true;
  Future<void> setTaskNotifications(bool enabled) => _p.setBool(_keyTaskNotifications, enabled);

  bool get mentionNotifications => _p.getBool(_keyMentionNotifications) ?? true;
  Future<void> setMentionNotifications(bool enabled) => _p.setBool(_keyMentionNotifications, enabled);

  bool get channelNotifications => _p.getBool(_keyChannelNotifications) ?? true;
  Future<void> setChannelNotifications(bool enabled) => _p.setBool(_keyChannelNotifications, enabled);

  bool get soundEnabled => _p.getBool(_keySoundEnabled) ?? true;
  Future<void> setSoundEnabled(bool enabled) => _p.setBool(_keySoundEnabled, enabled);

  bool get vibrationEnabled => _p.getBool(_keyVibrationEnabled) ?? true;
  Future<void> setVibrationEnabled(bool enabled) => _p.setBool(_keyVibrationEnabled, enabled);

  // Appearance settings
  double get fontSize => _p.getDouble(_keyFontSize) ?? 1.0;
  Future<void> setFontSize(double size) => _p.setDouble(_keyFontSize, size);

  bool get compactMode => _p.getBool(_keyCompactMode) ?? false;
  Future<void> setCompactMode(bool enabled) => _p.setBool(_keyCompactMode, enabled);

  // Last workspace
  String? get lastWorkspaceId => _p.getString(_keyLastWorkspaceId);
  Future<void> setLastWorkspaceId(String id) => _p.setString(_keyLastWorkspaceId, id);

  /// Nền trang nhắn tin (màu/gradient phía sau khung chat): 'default' | 'gradient_primary' | 'gradient_soft' | 'solid_light' | 'solid_dark'
  String get chatTheme => _p.getString(_keyChatTheme) ?? 'default';
  Future<void> setChatTheme(String theme) => _p.setString(_keyChatTheme, theme);

  // Clear all settings
  Future<void> clear() async {
    await _p.clear();
  }

  // Get all settings as map
  Map<String, dynamic> toMap() {
    return {
      'themeMode': themeMode,
      'language': language,
      'notificationsEnabled': notificationsEnabled,
      'messageNotifications': messageNotifications,
      'taskNotifications': taskNotifications,
      'mentionNotifications': mentionNotifications,
      'channelNotifications': channelNotifications,
      'soundEnabled': soundEnabled,
      'vibrationEnabled': vibrationEnabled,
      'fontSize': fontSize,
      'compactMode': compactMode,
      'lastWorkspaceId': lastWorkspaceId,
    };
  }
}

/// Singleton instance
final settingsService = SettingsService();
