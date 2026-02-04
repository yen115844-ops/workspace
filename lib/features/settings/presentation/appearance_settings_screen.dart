import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';

import '../../../core/storage/app_settings_notifier.dart';
import '../../../core/storage/settings_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/safe_navigation.dart';

class AppearanceSettingsScreen extends StatefulWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  State<AppearanceSettingsScreen> createState() => _AppearanceSettingsScreenState();
}

class _AppearanceSettingsScreenState extends State<AppearanceSettingsScreen> {
  late String _themeMode;
  late String _fontSize;
  double _fontScale = 1.0;

  @override
  void initState() {
    super.initState();
    _themeMode = settingsService.themeMode;
    _fontScale = settingsService.fontSize;
    _fontSize = _fontScale <= 0.9 ? 'small' : (_fontScale >= 1.1 ? 'large' : 'medium');
  }

  Future<void> _setTheme(String value) async {
    setState(() => _themeMode = value);
    await appSettingsNotifier.setThemeModeFromString(value);
  }

  Future<void> _setFontScale(double scale) async {
    setState(() {
      _fontScale = scale;
      _fontSize = scale <= 0.9 ? 'small' : (scale >= 1.1 ? 'large' : 'medium');
    });
    await appSettingsNotifier.setFontScale(scale);
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
                      'Giao diện',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Theme selection
                    Text(
                      'Chế độ giao diện',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                      ),
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        _buildThemeOption(
                          context,
                          isDark,
                          icon: Ionicons.phone_portrait_outline,
                          title: 'Hệ thống',
                          value: 'system',
                        ),
                        const SizedBox(width: 12),
                        _buildThemeOption(
                          context,
                          isDark,
                          icon: Ionicons.sunny_outline,
                          title: 'Sáng',
                          value: 'light',
                        ),
                        const SizedBox(width: 12),
                        _buildThemeOption(
                          context,
                          isDark,
                          icon: Ionicons.moon_outline,
                          title: 'Tối',
                          value: 'dark',
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Font size
                    Text(
                      'Cỡ chữ',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                      ),
                    ),
                    const SizedBox(height: 12),

                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.cardDark : AppColors.cardLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('A', style: TextStyle(fontSize: 14, color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)),
                              Expanded(
                                child: Slider(
                                  value: _fontScale,
                                  min: 0.8,
                                  max: 1.4,
                                  divisions: 6,
                                  onChanged: (v) => _setFontScale(v),
                                  activeColor: AppColors.primaryStart,
                                ),
                              ),
                              Text('A', style: TextStyle(fontSize: 24, color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _fontSize == 'small' ? 'Nhỏ' : (_fontSize == 'medium' ? 'Vừa' : 'Lớn'),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.primaryStart,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Preview
                    Text(
                      'Xem trước',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                      ),
                    ),
                    const SizedBox(height: 12),

                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.cardDark : AppColors.cardLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  gradient: AppColors.primaryGradient,
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: Text('A', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Nguyễn Văn A',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: _getFontSize(16),
                                      ),
                                    ),
                                    Text(
                                      '10:30',
                                      style: TextStyle(
                                        fontSize: _getFontSize(12),
                                        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Đây là tin nhắn mẫu để xem trước cỡ chữ đã chọn.',
                            style: TextStyle(fontSize: _getFontSize(14)),
                          ),
                        ],
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

  double _getFontSize(double baseSize) {
    return baseSize * _fontScale;
  }

  Widget _buildThemeOption(
    BuildContext context,
    bool isDark, {
    required IconData icon,
    required String title,
    required String value,
  }) {
    final isSelected = _themeMode == value;

    return Expanded(
      child: GestureDetector(
        onTap: () => _setTheme(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primaryStart.withOpacity(0.1)
                : (isDark ? AppColors.cardDark : AppColors.cardLight),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.primaryStart : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? AppColors.primaryStart : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
                size: 28,
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? AppColors.primaryStart : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
