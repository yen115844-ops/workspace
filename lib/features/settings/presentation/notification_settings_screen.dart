import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';

import '../../../core/storage/settings_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/safe_navigation.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  bool _allNotifications = true;
  bool _messageNotifications = true;
  bool _taskNotifications = true;
  bool _mentionNotifications = true;
  bool _channelNotifications = true;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _allNotifications = settingsService.notificationsEnabled;
      _messageNotifications = settingsService.messageNotifications;
      _taskNotifications = settingsService.taskNotifications;
      _mentionNotifications = settingsService.mentionNotifications;
      _channelNotifications = settingsService.channelNotifications;
      _soundEnabled = settingsService.soundEnabled;
      _vibrationEnabled = settingsService.vibrationEnabled;
      _isLoading = false;
    });
  }

  Future<void> _updateSetting(String key, bool value) async {
    switch (key) {
      case 'all':
        await settingsService.setNotificationsEnabled(value);
        setState(() => _allNotifications = value);
        break;
      case 'message':
        await settingsService.setMessageNotifications(value);
        setState(() => _messageNotifications = value);
        break;
      case 'task':
        await settingsService.setTaskNotifications(value);
        setState(() => _taskNotifications = value);
        break;
      case 'mention':
        await settingsService.setMentionNotifications(value);
        setState(() => _mentionNotifications = value);
        break;
      case 'channel':
        await settingsService.setChannelNotifications(value);
        setState(() => _channelNotifications = value);
        break;
      case 'sound':
        await settingsService.setSoundEnabled(value);
        setState(() => _soundEnabled = value);
        break;
      case 'vibration':
        await settingsService.setVibrationEnabled(value);
        setState(() => _vibrationEnabled = value);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.bgDark, AppColors.cardDark.withOpacity(0.5)],
                )
              : null,
          color: isDark ? null : AppColors.bgLight,
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => context.maybePopOrGo('/settings'),
                      icon: const Icon(Ionicons.arrow_back),
                      style: IconButton.styleFrom(
                        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Thông báo',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: _isLoading 
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Master toggle
                    _buildSettingsCard(
                      context,
                      isDark,
                      title: 'Bật thông báo',
                      subtitle: 'Bật/tắt tất cả thông báo',
                      icon: Ionicons.notifications_outline,
                      trailing: Switch(
                        value: _allNotifications,
                        onChanged: (v) => _updateSetting('all', v),
                        activeColor: AppColors.primaryStart,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Notification types
                    Text(
                      'Loại thông báo',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                      ),
                    ),
                    const SizedBox(height: 12),

                    _buildSettingsCard(
                      context,
                      isDark,
                      title: 'Tin nhắn mới',
                      subtitle: 'Thông báo khi có tin nhắn mới',
                      icon: Ionicons.chatbubble_outline,
                      trailing: Switch(
                        value: _messageNotifications && _allNotifications,
                        onChanged: _allNotifications ? (v) => _updateSetting('message', v) : null,
                        activeColor: AppColors.primaryStart,
                      ),
                    ),
                    const SizedBox(height: 12),

                    _buildSettingsCard(
                      context,
                      isDark,
                      title: 'Công việc',
                      subtitle: 'Thông báo về task được giao',
                      icon: Ionicons.checkbox_outline,
                      trailing: Switch(
                        value: _taskNotifications && _allNotifications,
                        onChanged: _allNotifications ? (v) => _updateSetting('task', v) : null,
                        activeColor: AppColors.primaryStart,
                      ),
                    ),
                    const SizedBox(height: 12),

                    _buildSettingsCard(
                      context,
                      isDark,
                      title: 'Nhắc đến (@)',
                      subtitle: 'Khi ai đó nhắc đến bạn',
                      icon: Ionicons.at_outline,
                      trailing: Switch(
                        value: _mentionNotifications && _allNotifications,
                        onChanged: _allNotifications ? (v) => _updateSetting('mention', v) : null,
                        activeColor: AppColors.primaryStart,
                      ),
                    ),
                    const SizedBox(height: 12),

                    _buildSettingsCard(
                      context,
                      isDark,
                      title: 'Kênh',
                      subtitle: 'Khi được mời vào kênh mới',
                      icon: Ionicons.people_outline,
                      trailing: Switch(
                        value: _channelNotifications && _allNotifications,
                        onChanged: _allNotifications ? (v) => _updateSetting('channel', v) : null,
                        activeColor: AppColors.primaryStart,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Sound & Vibration
                    Text(
                      'Âm thanh & Rung',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                      ),
                    ),
                    const SizedBox(height: 12),

                    _buildSettingsCard(
                      context,
                      isDark,
                      title: 'Âm thanh',
                      subtitle: 'Phát âm thanh khi có thông báo',
                      icon: Ionicons.volume_medium_outline,
                      trailing: Switch(
                        value: _soundEnabled && _allNotifications,
                        onChanged: _allNotifications ? (v) => _updateSetting('sound', v) : null,
                        activeColor: AppColors.primaryStart,
                      ),
                    ),
                    const SizedBox(height: 12),

                    _buildSettingsCard(
                      context,
                      isDark,
                      title: 'Rung',
                      subtitle: 'Rung khi có thông báo',
                      icon: Ionicons.phone_portrait_outline,
                      trailing: Switch(
                        value: _vibrationEnabled && _allNotifications,
                        onChanged: _allNotifications ? (v) => _updateSetting('vibration', v) : null,
                        activeColor: AppColors.primaryStart,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsCard(
    BuildContext context,
    bool isDark, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primaryStart.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primaryStart, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}
