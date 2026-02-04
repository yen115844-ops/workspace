import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_cubit.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/channel/presentation/channel_list_screen.dart';
import '../../features/channel/presentation/channel_members_screen.dart';
import '../../features/huddle/presentation/huddle_screen.dart';
import '../../features/message/presentation/channel_media_screen.dart';
import '../../features/message/presentation/group_chat_screen.dart';
import '../../features/profile/presentation/change_password_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/search/presentation/search_screen.dart';
import '../../features/settings/presentation/appearance_settings_screen.dart';
import '../../features/settings/presentation/notification_settings_screen.dart';
import '../../features/task/presentation/task_board_screen.dart';
import '../models/models.dart';
import '../../features/task/presentation/task_detail_screen.dart';
import '../../features/workspace/presentation/workspace_list_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/notifications/presentation/accept_invite_screen.dart';
import '../../features/workspace/presentation/workspace_members_screen.dart';
import '../presentation/splash_screen.dart';

/// App Router configuration with proper auth flow
class AppRouter {
  final AuthCubit authCubit;
  late final GoRouter router;

  AppRouter(this.authCubit) {
    router = GoRouter(
      initialLocation: '/',
      refreshListenable: _AuthRefreshListenable(authCubit),
      redirect: _redirect,
      routes: _routes,
    );
  }

  /// Redirect logic based on auth state
  String? _redirect(BuildContext context, GoRouterState state) {
    final authState = authCubit.state;
    final currentPath = state.matchedLocation;

    // Still loading - stay on splash
    if (authState is AuthInitial || authState is AuthLoading) {
      if (currentPath != '/') return '/';
      return null;
    }

    final isAuthenticated = authState is AuthAuthenticated;
    final isAuthRoute = currentPath == '/login' || 
                        currentPath == '/register' || 
                        currentPath == '/forgot-password';
    final isSplash = currentPath == '/';

    // Not authenticated - go to login (unless already on auth route)
    if (!isAuthenticated) {
      if (isAuthRoute) return null;
      return '/login';
    }

    // Authenticated - redirect away from auth routes and splash
    if (isAuthenticated && (isAuthRoute || isSplash)) {
      return '/workspaces';
    }

    return null;
  }

  /// All app routes
  List<RouteBase> get _routes => [
        // Splash - initial route for auth check
        GoRoute(
          path: '/',
          builder: (context, state) => const SplashScreen(),
        ),

        // Auth routes
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/register',
          builder: (context, state) => const RegisterScreen(),
        ),
        GoRoute(
          path: '/forgot-password',
          builder: (context, state) => const ForgotPasswordScreen(),
        ),

        // Main app routes (require auth)
        GoRoute(
          path: '/workspaces',
          builder: (context, state) => const WorkspaceListScreen(),
        ),
        GoRoute(
          path: '/workspaces/:workspaceId',
          builder: (context, state) {
            final id = state.pathParameters['workspaceId']!;
            return ChannelListScreen(workspaceId: id);
          },
        ),
        GoRoute(
          path: '/workspaces/:workspaceId/channels/:channelId',
          builder: (context, state) {
            final workspaceId = state.pathParameters['workspaceId']!;
            final channelId = state.pathParameters['channelId']!;
            final channelName = (state.extra is String ? state.extra as String : null) ?? 'Channel';
            final initialMessageId = state.uri.queryParameters['messageId'];
            // Key theo channelId để khi chuyển channel trong chat, Flutter tạo State mới
            // (dispose cũ → leaveChannel, initState mới → joinChannel + _load), tránh reuse state sai.
            return GroupChatScreen(
              key: ValueKey('group_chat_$channelId'),
              channelId: channelId,
              channelName: channelName,
              workspaceId: workspaceId,
              initialMessageId: initialMessageId,
            );
          },
        ),
        GoRoute(
          path: '/workspaces/:workspaceId/channels/:channelId/members',
          builder: (context, state) {
            final workspaceId = state.pathParameters['workspaceId']!;
            final channelId = state.pathParameters['channelId']!;
            final channelName = state.extra as String? ?? 'Channel';
            return ChannelMembersScreen(
              channelId: channelId,
              channelName: channelName,
              workspaceId: workspaceId,
            );
          },
        ),
        GoRoute(
          path: '/workspaces/:workspaceId/channels/:channelId/huddle',
          builder: (context, state) {
            final workspaceId = state.pathParameters['workspaceId']!;
            final channelId = state.pathParameters['channelId']!;
            final channelName = state.extra as String? ?? 'Channel';
            return HuddleScreen(
              channelId: channelId,
              channelName: channelName,
              workspaceId: workspaceId,
            );
          },
        ),
        GoRoute(
          path: '/workspaces/:workspaceId/channels/:channelId/media',
          builder: (context, state) {
            final workspaceId = state.pathParameters['workspaceId']!;
            final channelId = state.pathParameters['channelId']!;
            final channelName = state.extra as String? ?? 'Channel';
            return ChannelMediaScreen(
              channelId: channelId,
              channelName: channelName,
              workspaceId: workspaceId,
            );
          },
        ),
        GoRoute(
          path: '/workspaces/:workspaceId/tasks',
          builder: (context, state) {
            final workspaceId = state.pathParameters['workspaceId']!;
            return TaskBoardScreen(workspaceId: workspaceId);
          },
        ),
        GoRoute(
          path: '/workspaces/:workspaceId/tasks/:taskId',
          builder: (context, state) {
            final workspaceId = state.pathParameters['workspaceId']!;
            final taskId = state.pathParameters['taskId']!;
            final task = state.extra is TaskModel ? state.extra as TaskModel : null;
            return TaskDetailScreen(
              workspaceId: workspaceId,
              taskId: taskId,
              task: task,
            );
          },
        ),
        GoRoute(
          path: '/workspaces/:workspaceId/members',
          builder: (context, state) {
            final workspaceId = state.pathParameters['workspaceId']!;
            final workspaceName = state.extra as String? ?? 'Workspace';
            return WorkspaceMembersScreen(workspaceId: workspaceId, workspaceName: workspaceName);
          },
        ),

        // Profile & Settings routes
        GoRoute(
          path: '/notifications',
          builder: (context, state) => const NotificationsScreen(),
        ),
        GoRoute(
          path: '/invites/:token',
          builder: (context, state) {
            final token = state.pathParameters['token']!;
            return AcceptInviteScreen(token: token);
          },
        ),
        GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfileScreen(),
        ),
        GoRoute(
          path: '/profile/change-password',
          builder: (context, state) => const ChangePasswordScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const ProfileScreen(),
        ),
        GoRoute(
          path: '/settings/notifications',
          builder: (context, state) => const NotificationSettingsScreen(),
        ),
        GoRoute(
          path: '/settings/appearance',
          builder: (context, state) => const AppearanceSettingsScreen(),
        ),
        
        // Search
        GoRoute(
          path: '/search',
          builder: (context, state) {
            final workspaceId = state.uri.queryParameters['workspaceId'];
            return SearchScreen(workspaceId: workspaceId);
          },
        ),
      ];
}

/// Listenable that notifies router when auth state changes
class _AuthRefreshListenable extends ChangeNotifier {
  _AuthRefreshListenable(AuthCubit cubit) {
    cubit.stream.listen((_) => notifyListeners());
  }
}
