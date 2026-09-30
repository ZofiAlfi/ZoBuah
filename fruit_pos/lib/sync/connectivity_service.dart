import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../core/constants.dart';

class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  Future<void> initialize() async {
    final results = await _connectivity.checkConnectivity();
    isOnline.value = _anyOnline(results);
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      final online = _anyOnline(results);
      if (online != isOnline.value) {
        isOnline.value = online;
        debugPrint('Koneksi internet: $online');
      }
    });
  }

  bool _anyOnline(List<ConnectivityResult> results) {
    // `adb reverse` membuat localhost di HP meneruskan ke PC tanpa perlu
    // koneksi internet apa pun. Kalau API-nya loopback, status konektivitas
    // tidak relevan: mencoba request lebih baik daripada menandai offline
    // lalu menampilkan dashboard kosong.
    if (AppConstants.isLoopbackApi) return true;
    return results.any((r) =>
        r == ConnectivityResult.mobile || r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet);
  }

  void dispose() {
    _subscription?.cancel();
    isOnline.dispose();
  }
}