import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:ionicons/ionicons.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/auth_cubit.dart';
import '../../workspace/data/workspace_repository.dart';

class AcceptInviteScreen extends StatefulWidget {
  const AcceptInviteScreen({super.key, required this.token});

  final String token;

  @override
  State<AcceptInviteScreen> createState() => _AcceptInviteScreenState();
}

class _AcceptInviteScreenState extends State<AcceptInviteScreen> {
  final WorkspaceRepository _repo = WorkspaceRepository();
  Map<String, dynamic>? _invite;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInvite();
  }

  Future<void> _loadInvite() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _repo.getInviteByToken(widget.token);
      if (mounted) {
        setState(() {
          _invite = data;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Không thể tải thông tin lời mời';
          _loading = false;
        });
      }
    }
  }

  Future<void> _accept() async {
    setState(() => _loading = true);
    try {
      final result = await _repo.acceptInvite(widget.token);
      if (mounted) {
        context.read<AuthCubit>().refreshUser();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã tham gia workspace "${result['workspaceName']}"'),
            backgroundColor: AppColors.success,
          ),
        );
        context.go('/workspaces/${result['workspaceId']}');
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể chấp nhận lời mời'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authState = context.watch<AuthCubit>().state;
    final isLoggedIn = authState is AuthAuthenticated;
    final userEmail = isLoggedIn ? (authState as AuthAuthenticated).user.email.toLowerCase() : '';
    final inviteEmail = (_invite?['email'] as String?)?.toLowerCase() ?? '';
    final emailMatches = isLoggedIn && inviteEmail.isNotEmpty && userEmail == inviteEmail;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.bgDark, AppColors.cardDark.withValues(alpha: 0.5)],
                )
              : null,
          color: isDark ? null : AppColors.bgLight,
        ),
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Ionicons.warning_outline, size: 64, color: AppColors.error),
                          const SizedBox(height: 16),
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: () => context.go('/workspaces'),
                            icon: const Icon(Ionicons.home_outline),
                            label: const Text('Về trang chủ'),
                          ),
                        ],
                      ),
                    )
                  : _invite == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  gradient: AppColors.primaryGradient,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Icon(Ionicons.mail_open_outline, size: 64, color: Colors.white),
                              ),
                              const SizedBox(height: 32),
                              Text(
                                'Lời mời tham gia workspace',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: isDark ? AppColors.cardDark : AppColors.cardLight,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      _invite!['workspaceName'] ?? 'Workspace',
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Vai trò: ${_invite!['role'] ?? 'member'}',
                                      style: TextStyle(
                                        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 32),
                              if (!isLoggedIn)
                                Column(
                                  children: [
                                    Text(
                                      'Đăng nhập để chấp nhận lời mời',
                                      style: TextStyle(
                                        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    FilledButton.icon(
                                      onPressed: () => context.go('/login'),
                                      icon: const Icon(Ionicons.log_in_outline),
                                      label: const Text('Đăng nhập'),
                                    ),
                                  ],
                                )
                              else if (!emailMatches)
                                Column(
                                  children: [
                                    Text(
                                      'Email của bạn không khớp với lời mời (${_invite!['email']})',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    OutlinedButton(
                                      onPressed: () => context.go('/workspaces'),
                                      child: const Text('Về trang chủ'),
                                    ),
                                  ],
                                )
                              else
                                FilledButton.icon(
                                  onPressed: _loading ? null : _accept,
                                  icon: _loading
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : const Icon(Ionicons.checkmark_outline),
                                  label: Text(_loading ? 'Đang xử lý...' : 'Chấp nhận'),
                                ),
                            ],
                          ),
                        ),
        ),
      ),
    );
  }
}
