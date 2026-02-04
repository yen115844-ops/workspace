import 'dart:async';

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/services/fcm_service.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../core/models/models.dart';
import '../data/auth_repository.dart';

// States
abstract class AuthState extends Equatable {
  const AuthState();
  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class AuthAuthenticated extends AuthState {
  final UserModel user;
  const AuthAuthenticated(this.user);
  @override
  List<Object?> get props => [user];
}

class AuthUnauthenticated extends AuthState {}

class AuthError extends AuthState {
  final String message;
  const AuthError(this.message);
  @override
  List<Object?> get props => [message];
}

/// Helper to extract error message from various exception types
String _extractErrorMessage(Object error) {
  if (error is DioException) {
    // Check if error was converted to ApiException
    if (error.error is ApiException) {
      return (error.error as ApiException).message;
    }
    // Fallback to manual extraction
    return ApiException.fromDioException(error).message;
  }
  
  if (error is ApiException) {
    return error.message;
  }
  
  // Generic error handling
  final message = error.toString();
  if (message.startsWith('Exception: ')) {
    return message.replaceFirst('Exception: ', '');
  }
  return message;
}

// Cubit
class AuthCubit extends Cubit<AuthState> {
  AuthCubit(this._repo) : super(AuthInitial()) {
    _listenToAuthEvents();
    checkAuth();
  }

  final AuthRepository _repo;
  StreamSubscription<AuthEvent>? _authEventSubscription;

  /// Listen to auth events from API client (e.g., force logout on token expiry)
  void _listenToAuthEvents() {
    _authEventSubscription = authEventController.stream.listen((event) {
      if (event == AuthEvent.forceLogout || event == AuthEvent.tokenExpired) {
        log.auth('Force logout due to token expiry');
        emit(AuthUnauthenticated());
      }
    });
  }

  @override
  Future<void> close() {
    _authEventSubscription?.cancel();
    return super.close();
  }

  Future<void> checkAuth() async {
    emit(AuthLoading());
    log.auth('checkAuth');
    final ok = await _repo.isLoggedIn();
    if (!ok) {
      log.auth('not logged in');
      ApiClient.currentUserId = null;
      emit(AuthUnauthenticated());
      return;
    }
    try {
      final me = await _repo.me();
      if (me != null) {
        final user = UserModel.fromJson(me);
        ApiClient.currentUserId = user.id;
        log.auth('restored', user.email);
        emit(AuthAuthenticated(user));
        FcmService().registerTokenIfLoggedIn();
      } else {
        ApiClient.currentUserId = null;
        emit(AuthUnauthenticated());
      }
    } catch (e, st) {
      log.auth('checkAuth error', e);
      log.e('checkAuth', e, st);
      ApiClient.currentUserId = null;
      emit(AuthUnauthenticated());
    }
  }

  /// Refresh current user data without triggering redirect to splash.
  /// Use when updating profile (name, avatar) - keeps user on current screen.
  Future<void> refreshUser() async {
    final current = state;
    if (current is! AuthAuthenticated) return;
    try {
      final me = await _repo.me();
      if (me != null) {
        final user = UserModel.fromJson(me);
        ApiClient.currentUserId = user.id;
        emit(AuthAuthenticated(user));
      }
    } catch (e, st) {
      log.auth('refreshUser error', e);
      log.e('refreshUser', e, st);
    }
  }

  Future<void> login(String email, String password) async {
    emit(AuthLoading());
    log.auth('login', email);
    try {
      final result = await _repo.login(email, password);
      if (result.user != null) {
        log.auth('login success', result.user!.email);
        emit(AuthAuthenticated(result.user!));
        FcmService().registerTokenIfLoggedIn();
      } else {
        emit(const AuthError('Có lỗi xảy ra, vui lòng thử lại'));
      }
    } catch (e, st) {
      log.auth('login error', e);
      log.e('login', e, st);
      final errorMessage = _extractErrorMessage(e);
      emit(AuthError(errorMessage));
    }
  }

  Future<void> register(String email, String password, String name) async {
    emit(AuthLoading());
    log.auth('register', email);
    try {
      final result = await _repo.register(email, password, name);
      if (result.user != null) {
        log.auth('register success', result.user!.email);
        emit(AuthAuthenticated(result.user!));
        FcmService().registerTokenIfLoggedIn();
      } else {
        emit(const AuthError('Có lỗi xảy ra, vui lòng thử lại'));
      }
    } catch (e, st) {
      log.auth('register error', e);
      log.e('register', e, st);
      final errorMessage = _extractErrorMessage(e);
      emit(AuthError(errorMessage));
    }
  }

  Future<void> logout() async {
    log.auth('logout');
    FcmService().removeToken();
    await _repo.logout();
    ApiClient.currentUserId = null;
    emit(AuthUnauthenticated());
  }
}
