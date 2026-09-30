import 'package:flutter/foundation.dart';

import '../models/user.dart';
import 'auth_repository.dart';

enum AuthStatus { unknown, unauthenticated, authenticated }

class AuthState extends ChangeNotifier {
  final AuthRepository repository;

  AuthState({required this.repository}) {
    repository.apiClient.onSessionExpired = _handleSessionExpired;
  }

  AuthStatus _status = AuthStatus.unknown;
  User? _user;

  AuthStatus get status => _status;
  User? get user => _user;

  Future<void> initialize() async {
    try {
      _user = await repository.loadSession();
      if (_user == null) {
        _status = AuthStatus.unauthenticated;
        notifyListeners();
        return;
      }
      // Token yang tersimpan bisa saja sudah mati (app lama tidak dibuka,
      // atau backend sempat diganti). Tanpa verifikasi di sini, user terjebak
      // di dashboard yang menampilkan "Data tidak tersedia" padahal
      // masalahnya sesi. Refresh yang ditolak berarti wajib login ulang;
      // device offline tetap dibiarkan masuk dan pakai cache lokal.
      final verdict = await repository.refreshSession();
      if (verdict == false) {
        debugPrint('Sesi tidak valid, memaksa login ulang');
        await repository.clearTokens();
        _user = null;
        _status = AuthStatus.unauthenticated;
      } else {
        _status = AuthStatus.authenticated;
      }
    } catch (e) {
      _status = AuthStatus.unauthenticated;
      _user = null;
      debugPrint('Auth init error: $e');
    }
    notifyListeners();
  }

  /// Dipanggil ApiClient saat refresh token juga ditolak server. Sesi sudah
  /// tidak bisa dipulihkan, jadi langsung arahkan user ke halaman login.
  void _handleSessionExpired() {
    if (_status != AuthStatus.authenticated) return;
    debugPrint('Sesi kedaluwarsa saat dipakai, memaksa login ulang');
    _status = AuthStatus.unauthenticated;
    _user = null;
    repository.clearTokens();
    notifyListeners();
  }

  Future<bool> login(String username, String password) async {
    try {
      _user = await repository.login(username, password);
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> logout() async {
    await repository.logout();
    _user = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }
}