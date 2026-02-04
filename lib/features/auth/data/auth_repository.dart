import '../../../core/models/models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/auth_storage.dart';

class AuthRepository {
  final ApiClient _api = ApiClient();
  final AuthStorage _storage = AuthStorage();

  Future<AuthResult> login(String email, String password) async {
    final res = await _api.post<Map<String, dynamic>>(
        '/auth/login', data: {'email': email, 'password': password});
    final result = _parseAuthResult(res.data);
    await _storage.saveTokens(
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      userId: result.user?.id,
    );
    ApiClient.currentUserId = result.user?.id;
    return result;
  }

  Future<AuthResult> register(String email, String password, String name) async {
    final res = await _api.post<Map<String, dynamic>>('/auth/register',
        data: {'email': email, 'password': password, 'name': name});
    final result = _parseAuthResult(res.data);
    await _storage.saveTokens(
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      userId: result.user?.id,
    );
    ApiClient.currentUserId = result.user?.id;
    return result;
  }

  Future<void> forgotPassword(String email) async {
    await _api.post('/auth/forgot-password', data: {'email': email});
  }

  Future<void> resetPassword(String token, String newPassword) async {
    await _api.post('/auth/reset-password', data: {
      'token': token,
      'password': newPassword,
    });
  }

  AuthResult _parseAuthResult(Map<String, dynamic>? data) {
    if (data == null) throw Exception('Invalid response');
    final payload = data['data'] as Map<String, dynamic>? ?? data;
    final accessToken = payload['access_token'] as String?;
    final refreshToken = payload['refresh_token'] as String?;
    final user = payload['user'] as Map<String, dynamic>?;
    if (accessToken == null || accessToken.isEmpty) {
      throw Exception('No access token');
    }
    return AuthResult(
      accessToken: accessToken,
      refreshToken: refreshToken ?? '',
      user: user != null ? UserModel.fromJson(user) : null,
    );
  }

  Future<Map<String, dynamic>?> me() async {
    final res = await _api.get<Map<String, dynamic>>('/auth/me');
    final data = res.data;
    if (data != null && data['data'] != null) {
      return data['data'] as Map<String, dynamic>;
    }
    return data;
  }

  Future<void> logout() async {
    try {
      final refresh = await _storage.getRefreshToken();
      if (refresh != null) {
        await _api.post('/auth/logout', data: {'refreshToken': refresh});
      }
    } catch (_) {}
    await _storage.clear();
  }

  Future<bool> isLoggedIn() async {
    final token = await _storage.getAccessToken();
    return token != null && token.isNotEmpty;
  }
}

class AuthResult {
  final String accessToken;
  final String refreshToken;
  final UserModel? user;

  AuthResult(
      {required this.accessToken, required this.refreshToken, this.user});
}
