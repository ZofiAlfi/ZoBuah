import 'package:flutter/foundation.dart';

import '../models/user.dart';
import 'auth_repository.dart';

enum AuthStatus { unknown, unauthenticated, authenticated }

class AuthState extends ChangeNotifier {
  final AuthRepository repository;

  AuthState({required this.repository});

  AuthStatus _status = AuthStatus.unknown;
  User? _user;

  AuthStatus get status => _status;
  User? get user => _user;

  Future<void> initialize() async {
    try {
      _user = await repository.loadSession();
      _status = _user != null ? AuthStatus.authenticated : AuthStatus.unauthenticated;
    } catch (e) {
      _status = AuthStatus.unauthenticated;
      _user = null;
      debugPrint('Auth init error: $e');
    }
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