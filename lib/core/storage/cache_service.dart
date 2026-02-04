import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_logger.dart';

/// Simple cache service using SharedPreferences for offline support
class CacheService {
  static const String _cachePrefix = 'cache_';
  static const String _cacheExpiry = 'expiry_';
  
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static SharedPreferences get _p {
    if (_prefs == null) {
      throw StateError('CacheService not initialized. Call init() first.');
    }
    return _prefs!;
  }

  /// Cache data with optional expiration
  static Future<void> set(String key, dynamic data, {Duration? expiry}) async {
    try {
      final jsonStr = jsonEncode(data);
      await _p.setString('$_cachePrefix$key', jsonStr);
      
      if (expiry != null) {
        final expiryTime = DateTime.now().add(expiry).millisecondsSinceEpoch;
        await _p.setInt('$_cacheExpiry$key', expiryTime);
      }
      
      log.d('[Cache] Set: $key');
    } catch (e) {
      log.e('[Cache] Error setting: $key', e);
    }
  }

  /// Get cached data
  static T? get<T>(String key) {
    try {
      // Check expiry
      final expiryTime = _p.getInt('$_cacheExpiry$key');
      if (expiryTime != null && DateTime.now().millisecondsSinceEpoch > expiryTime) {
        // Expired, remove cache
        remove(key);
        return null;
      }
      
      final jsonStr = _p.getString('$_cachePrefix$key');
      if (jsonStr == null) return null;
      
      final data = jsonDecode(jsonStr);
      log.d('[Cache] Get: $key');
      return data as T?;
    } catch (e) {
      log.e('[Cache] Error getting: $key', e);
      return null;
    }
  }

  /// Check if cache exists and not expired
  static bool has(String key) {
    final expiryTime = _p.getInt('$_cacheExpiry$key');
    if (expiryTime != null && DateTime.now().millisecondsSinceEpoch > expiryTime) {
      return false;
    }
    return _p.containsKey('$_cachePrefix$key');
  }

  /// Remove cached data
  static Future<void> remove(String key) async {
    await _p.remove('$_cachePrefix$key');
    await _p.remove('$_cacheExpiry$key');
    log.d('[Cache] Removed: $key');
  }

  /// Clear all cache
  static Future<void> clearAll() async {
    final keys = _p.getKeys().where((k) => k.startsWith(_cachePrefix) || k.startsWith(_cacheExpiry));
    for (final key in keys) {
      await _p.remove(key);
    }
    log.d('[Cache] Cleared all');
  }

  /// Clear expired cache
  static Future<void> clearExpired() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final expiryKeys = _p.getKeys().where((k) => k.startsWith(_cacheExpiry)).toList();
    
    for (final expiryKey in expiryKeys) {
      final expiryTime = _p.getInt(expiryKey);
      if (expiryTime != null && now > expiryTime) {
        final dataKey = expiryKey.replaceFirst(_cacheExpiry, _cachePrefix);
        await _p.remove(dataKey);
        await _p.remove(expiryKey);
      }
    }
    log.d('[Cache] Cleared expired');
  }

  // Convenience methods for common data types

  /// Cache workspaces list
  static Future<void> cacheWorkspaces(List<Map<String, dynamic>> workspaces) async {
    await set('workspaces', workspaces, expiry: const Duration(hours: 1));
  }

  static List<Map<String, dynamic>>? getCachedWorkspaces() {
    final data = get<List<dynamic>>('workspaces');
    return data?.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Cache channels for a workspace
  static Future<void> cacheChannels(String workspaceId, List<Map<String, dynamic>> channels) async {
    await set('channels_$workspaceId', channels, expiry: const Duration(hours: 1));
  }

  static List<Map<String, dynamic>>? getCachedChannels(String workspaceId) {
    final data = get<List<dynamic>>('channels_$workspaceId');
    return data?.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Cache messages for a channel
  static Future<void> cacheMessages(String channelId, List<Map<String, dynamic>> messages) async {
    await set('messages_$channelId', messages, expiry: const Duration(minutes: 30));
  }

  static List<Map<String, dynamic>>? getCachedMessages(String channelId) {
    final data = get<List<dynamic>>('messages_$channelId');
    return data?.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Cache tasks for a workspace
  static Future<void> cacheTasks(String workspaceId, List<Map<String, dynamic>> tasks) async {
    await set('tasks_$workspaceId', tasks, expiry: const Duration(hours: 1));
  }

  static List<Map<String, dynamic>>? getCachedTasks(String workspaceId) {
    final data = get<List<dynamic>>('tasks_$workspaceId');
    return data?.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Cache user profile
  static Future<void> cacheUserProfile(Map<String, dynamic> user) async {
    await set('user_profile', user, expiry: const Duration(days: 1));
  }

  static Map<String, dynamic>? getCachedUserProfile() {
    final data = get<Map<String, dynamic>>('user_profile');
    return data;
  }
}
