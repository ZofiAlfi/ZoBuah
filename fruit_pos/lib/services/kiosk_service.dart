import 'package:flutter/services.dart';

class KioskService {
  static const MethodChannel _channel = MethodChannel('com.fruitpos/locktask');

  /// Karyawan: full-screen immersive + lock task bila diizinkan.
  static Future<void> enterKiosk() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (_) {}
    try {
      await _channel
          .invokeMethod('startLockTask')
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // Lock task tidak tersedia (bukan device owner) — abaikan, immersive tetap aktif.
    }
  }

  /// BOS / normal: kembali ke tampilan sistem standar.
  /// Selalu mengembalikan UI sistem agar layar tidak "nyangkut" di mode kiosk.
  static Future<void> leaveKiosk() async {
    try {
      await _channel
          .invokeMethod('stopLockTask')
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // ignore — tetap lanjut memulihkan UI sistem
    }
    try {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    } catch (_) {}
  }

  /// Sembunyikan kembali bar sistem ketika ter-swipe (immersive sticky sudah menangani).
  static Future<void> rehideSystemUI() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }
}
