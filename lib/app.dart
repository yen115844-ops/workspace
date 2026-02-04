import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'core/router/app_router.dart';
import 'core/services/call_kit_service.dart';
import 'core/services/fcm_service.dart';
import 'core/storage/app_settings_notifier.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/presentation/auth_cubit.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final AuthCubit _authCubit;
  late final AppRouter _appRouter;
  StreamSubscription<Map<String, String>>? _notificationTapSubscription;

  @override
  void initState() {
    super.initState();
    _authCubit = AuthCubit(AuthRepository());
    _appRouter = AppRouter(_authCubit);
    _notificationTapSubscription = FcmService.notificationTapStream.listen(_onNotificationTap);
    // Xử lý pending (app mở từ notification khi terminated)
    WidgetsBinding.instance.addPostFrameCallback((_) => _flushPendingNotification());
    
    // Setup callback cho CallKit khi user accept cuộc gọi
    _setupCallKitCallbacks();
  }

  /// Setup callback để navigate đến Huddle screen khi user accept cuộc gọi.
  /// Chờ auth xong (tránh navigate khi AuthLoading rồi bị 401/out đăng nhập khi vào Huddle).
  void _setupCallKitCallbacks() {
    callKitService.setOnCallAccepted((channelId, channelName, workspaceId) {
      if (!mounted) return;
      if (channelId.isEmpty) return;
      final wsId = workspaceId?.isNotEmpty == true ? workspaceId! : null;
      if (wsId == null || wsId.isEmpty) return;

      void doNavigate() {
        if (!mounted) return;
        if (_authCubit.state is! AuthAuthenticated) return;
        final router = _appRouter.router;
        final path = '/workspaces/$wsId/channels/$channelId/huddle';
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_authCubit.state is! AuthAuthenticated) return;
          router.push(path, extra: channelName);
        });
      }

      // Đã authenticated → navigate ngay (sau frame)
      if (_authCubit.state is AuthAuthenticated) {
        doNavigate();
        return;
      }
      // App vừa mở từ background/terminated: chờ auth xong (tối đa 5s)
      StreamSubscription<AuthState>? sub;
      sub = _authCubit.stream.listen((state) {
        sub?.cancel();
        if (!mounted) return;
        if (state is AuthAuthenticated) doNavigate();
      });
      Future.delayed(const Duration(seconds: 5), () {
        sub?.cancel();
      });
    });
  }

  /// Điều hướng tới channel từ FCM: build stack workspace → channel để Back có route để pop.
  void _navigateToChannelWithStack(
    GoRouter router,
    String workspaceId,
    String channelId,
    String channelName,
    String? messageId,
  ) {
    router.go('/workspaces/$workspaceId');
    final path = messageId != null && messageId.isNotEmpty
        ? '/workspaces/$workspaceId/channels/$channelId?messageId=$messageId'
        : '/workspaces/$workspaceId/channels/$channelId';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      router.push(path, extra: channelName);
    });
  }

  void _flushPendingNotification() {
    final pending = FcmService.takePendingNotificationData();
    if (pending != null && pending.isNotEmpty) {
      // Trì hoãn để auth redirect xong rồi mới điều hướng
      Future.delayed(const Duration(milliseconds: 800), () {
        if (!mounted) return;
        if (_authCubit.state is! AuthAuthenticated) return;
        _onNotificationTap(pending);
      });
    }
  }

  void _onNotificationTap(Map<String, String> data) {
    final type = data['type'];
    final workspaceId = data['workspaceId'];
    final channelId = data['channelId'];
    final messageId = data['messageId'];
    final channelName = data['channelName'] ?? 'Channel';
    final router = _appRouter.router;

    if (type == 'channel_message' &&
        workspaceId != null &&
        workspaceId.isNotEmpty &&
        channelId != null &&
        channelId.isNotEmpty) {
      _navigateToChannelWithStack(router, workspaceId, channelId, channelName, messageId);
      return;
    }
    if (type == 'dm_message') {
      router.go('/notifications');
      return;
    }
    if (type == 'channel_added' && workspaceId != null && channelId != null) {
      _navigateToChannelWithStack(router, workspaceId, channelId, channelName, null);
      return;
    }
    router.go('/notifications');
  }

  @override
  void dispose() {
    _notificationTapSubscription?.cancel();
    _authCubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _authCubit,
      child: ListenableBuilder(
        listenable: appSettingsNotifier,
        builder: (context, _) {
          final themeMode = appSettingsNotifier.themeMode;
          final fontScale = appSettingsNotifier.fontScale;
          return MaterialApp.router(
            title: 'HanCity Work',
            theme: appTheme,
            darkTheme: appThemeDark,
            themeMode: themeMode,
            debugShowCheckedModeBanner: false,
            routerConfig: _appRouter.router,
            builder: (context, child) {
              return GestureDetector(
                onTap: () {
                  FocusScopeNode currentFocus = FocusScope.of(context);
                  if (!currentFocus.hasPrimaryFocus && currentFocus.focusedChild != null) {
                    FocusManager.instance.primaryFocus?.unfocus();
                  }
                },
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(fontScale),
                  ),
                  child: child!,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
