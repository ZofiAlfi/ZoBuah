import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/api_service.dart';
import '../core/constants.dart';
import '../models/user.dart';

class AuthRepository {
  final ApiClient apiClient;
  final ApiService apiService;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  AuthRepository({required this.apiClient, required this.apiService});

  // Workaround: obtain prefs lazily
  Future<SharedPreferences> get _prefsAsync => SharedPreferences.getInstance();

  Future<User?> login(String username, String password) async {
    final result = await apiService.login(username, password);
    await _saveSession(result.accessToken, result.refreshToken, result.user);
    return result.user;
  }

  Future<void> _saveSession(String access, String refresh, User user) async {
    await _secureStorage.write(key: 'access_token', value: access);
    await _secureStorage.write(key: 'refresh_token', value: refresh);
    final prefs = await _prefsAsync;
    await prefs.setString(AppConstants.prefUserId, user.id);
    await prefs.setString(AppConstants.prefRole, user.role);
    await prefs.setString(AppConstants.prefFullName, user.fullName);
    await prefs.setString(AppConstants.prefUsername, user.username);
  }

  Future<User?> loadSession() async {
    final access = await _secureStorage.read(key: 'access_token');
    if (access == null) return null;
    final prefs = await _prefsAsync;
    final id = prefs.getString(AppConstants.prefUserId);
    final role = prefs.getString(AppConstants.prefRole);
    final name = prefs.getString(AppConstants.prefFullName);
    final username = prefs.getString(AppConstants.prefUsername);
    if (id == null || role == null) return null;
    apiClient.setTokens(
      access: access,
      refresh: await _secureStorage.read(key: 'refresh_token'),
    );
    return User(id: id, username: username ?? '', fullName: name ?? '', role: role);
  }

  Future<void> logout() async {
    // cleanup lokal tidak boleh.memblokir UI selamanya.
    try {
      await _secureStorage.deleteAll().timeout(const Duration(seconds: 5));
    } catch (_) {
      // keystore bermasalah — lanjutkan, sesi akan tetap terhapus via prefs.
      try {
        await _secureStorage.deleteAll();
      } catch (_) {}
    }
    try {
      final prefs = await _prefsAsync;
      await prefs.clear();
    } catch (_) {}
    try {
      apiClient.setTokens(access: null, refresh: null);
    } catch (_) {}
  }
}