import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

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
    return results.any((r) =>
        r == ConnectivityResult.mobile || r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet);
  }

  void dispose() {
    _subscription?.cancel();
    isOnline.dispose();
  }
}