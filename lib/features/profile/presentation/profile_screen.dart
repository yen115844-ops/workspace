import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ionicons/ionicons.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/models/models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/safe_navigation.dart';
import '../../../core/widgets/full_screen_image_viewer.dart';
import '../../auth/presentation/auth_cubit.dart';
import '../data/profile_repository.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ProfileRepository _profileRepo = ProfileRepository();
  // ignore: unused_field
  bool _loading = false;

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.error),
      );
    }
  }

  void _showSuccess(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.success),
      );
    }
  }

  Future<void> _updateName(String newName) async {
    if (newName.trim().isEmpty) return;

    setState(() => _loading = true);
    try {
      await _profileRepo.updateProfile(name: newName.trim());
      if (mounted) {
        context.read<AuthCubit>().refreshUser();
        _showSuccess('Đã cập nhật tên thành công');
      }
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    if (!kAllowChangeAvatar) {
      _showError('Bạn không có quyền đổi ảnh đại diện');
      return;
    }
    final picker = ImagePicker();
    final xFile = await picker.pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 85);
    if (xFile == null || !mounted) return;

    setState(() => _loading = true);
    try {
      final url = await _profileRepo.uploadAvatar(File(xFile.path));
      if (url == null || url.isEmpty) {
        _showError('Upload thất bại');
        return;
      }
      await _profileRepo.updateProfile(avatar: url);
      if (mounted) {
        context.read<AuthCubit>().refreshUser();
        _showSuccess('Đã cập nhật ảnh đại diện');
      }
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, state) {
        final user = state is AuthAuthenticated ? state.user : null;

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
                          onPressed: () => context.maybePopOrGo(SafeNavigation.defaultFallback),
                          icon: const Icon(Ionicons.arrow_back),
                          style: IconButton.styleFrom(
                            backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Hồ sơ & Cài đặt',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          // Avatar section
                          _buildAvatarSection(context, user, isDark),
                          const SizedBox(height: 32),

                          // User info section
                          _buildInfoSection(context, user, isDark),
                          const SizedBox(height: 24),

                          // Settings section
                          _buildSettingsSection(context, isDark),
                          const SizedBox(height: 24),

                          // Logout button
                          _buildLogoutButton(context, isDark),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAvatarSection(BuildContext context, UserModel? user, bool isDark) {
    final avatarUrl = resolveAvatarUrl(user?.avatar);
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            // Tap avatar → xem lại ảnh toàn màn hình (chỉ khi có ảnh)
            GestureDetector(
              onTap: _loading
                  ? null
                  : () {
                      if (avatarUrl != null && avatarUrl.isNotEmpty) {
                        FullScreenImageViewer.show(context, avatarUrl);
                      }
                    },
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryStart.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: avatarUrl != null
                    ? ClipOval(
                        child: Image.network(
                          avatarUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildAvatarPlaceholder(user),
                        ),
                      )
                    : _buildAvatarPlaceholder(user),
              ),
            ),
            if (_loading)
              Positioned.fill(
                child: ClipOval(
                  child: Container(
                    color: Colors.black38,
                    child: const Center(
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            // Nút camera → upload ảnh mới (chỉ hiện khi có quyền đổi avatar)
            if (kAllowChangeAvatar)
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: _loading ? null : _pickAndUploadAvatar,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.cardDark : AppColors.cardLight,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Icon(
                      Ionicons.camera_outline,
                      size: 20,
                      color: AppColors.primaryStart,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          user?.name ?? 'User',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          user?.email ?? '',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
              ),
        ),
      ],
    );
  }

  Widget _buildAvatarPlaceholder(UserModel? user) {
    return Center(
      child: Text(
        (user?.name ?? 'U').substring(0, 1).toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 48,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildInfoSection(BuildContext context, UserModel? user, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        children: [
          _buildInfoTile(
            context,
            icon: Ionicons.person_outline,
            title: 'Họ tên',
            value: user?.name ?? 'Chưa cập nhật',
            isDark: isDark,
            onTap: () => _showEditNameDialog(context),
          ),
          Divider(height: 1, color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight),
          _buildInfoTile(
            context,
            icon: Ionicons.mail_outline,
            title: 'Email',
            value: user?.email ?? '',
            isDark: isDark,
          ),
          Divider(height: 1, color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight),
          _buildInfoTile(
            context,
            icon: Ionicons.lock_closed_outline,
            title: 'Mật khẩu',
            value: '••••••••',
            isDark: isDark,
            onTap: () => context.push('/profile/change-password'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
    required bool isDark,
    VoidCallback? onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.primaryStart.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.primaryStart, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
        ),
      ),
      subtitle: Text(
        value,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: onTap != null
          ? Icon(
              Ionicons.chevron_forward,
              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
            )
          : null,
    );
  }

  Widget _buildSettingsSection(BuildContext context, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        children: [
          _buildSettingsTile(
            context,
            icon: Ionicons.notifications_outline,
            title: 'Thông báo',
            isDark: isDark,
            onTap: () => context.push('/settings/notifications'),
          ),
          Divider(height: 1, color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight),
          _buildSettingsTile(
            context,
            icon: Ionicons.color_palette_outline,
            title: 'Giao diện',
            isDark: isDark,
            onTap: () => context.push('/settings/appearance'),
          ),
          Divider(height: 1, color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight),
          _buildSettingsTile(
            context,
            icon: Ionicons.information_circle_outline,
            title: 'Về ứng dụng',
            isDark: isDark,
            onTap: () => _showAboutDialog(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? value,
    required bool isDark,
    VoidCallback? onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.primaryStart.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.primaryStart, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            Text(
              value,
              style: TextStyle(
                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
              ),
            ),
          const SizedBox(width: 8),
          Icon(
            Ionicons.chevron_forward,
            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _showLogoutConfirmation(context),
            icon: const Icon(Ionicons.log_out_outline, color: AppColors.error),
            label: const Text('Đăng xuất', style: TextStyle(color: AppColors.error)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: const BorderSide(color: AppColors.error),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _loading ? null : () => _showDeleteAccountConfirmation(context),
          child: Text(
            'Xóa tài khoản',
            style: TextStyle(color: AppColors.error.withOpacity(0.9), fontSize: 14),
          ),
        ),
      ],
    );
  }

  Future<void> _deleteAccount() async {
    setState(() => _loading = true);
    try {
      await _profileRepo.deleteAccount();
      if (mounted) _showSuccess('Tài khoản đã được xóa');
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showDeleteAccountConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(ctx).size.width - 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Ionicons.warning_outline, color: AppColors.error),
                  SizedBox(width: 12),
                  Text('Xóa tài khoản'),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Bạn có chắc chắn muốn xóa tài khoản? Hành động này không thể hoàn tác và mọi dữ liệu sẽ bị mất vĩnh viễn.',
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Hủy'),
                  ),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _deleteAccount();
                    },
                    style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                    child: const Text('Xóa tài khoản'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditNameDialog(BuildContext context) {
    final controller = TextEditingController();
    final authState = context.read<AuthCubit>().state;
    if (authState is AuthAuthenticated) {
      controller.text = authState.user.name;
    }

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(ctx).size.width - 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Ionicons.person_outline, color: AppColors.primaryStart),
                  SizedBox(width: 12),
                  Text('Đổi tên'),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: 'Họ tên',
                  hintText: 'Nhập họ tên mới',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Hủy'),
                  ),
                  FilledButton(
                    onPressed: () {
                      final newName = controller.text.trim();
                      Navigator.pop(ctx);
                      _updateName(newName);
                    },
                    child: const Text('Lưu'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(ctx).size.width - 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Ionicons.log_out_outline, color: AppColors.error),
                  SizedBox(width: 12),
                  Text('Đăng xuất'),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Bạn có chắc chắn muốn đăng xuất khỏi ứng dụng?'),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Hủy'),
                  ),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      context.read<AuthCubit>().logout();
                    },
                    style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                    child: const Text('Đăng xuất'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'HanCity Work',
      applicationVersion: '1.0.0',
      applicationIcon: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Ionicons.business_outline, color: Colors.white, size: 32),
      ),
      children: [
        const Text('Ứng dụng quản lý workspace và cộng tác nhóm.'),
      ],
    );
  }
}
