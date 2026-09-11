import 'package:flutter/services.dart';

class KioskService {
  static const MethodChannel _channel = MethodChannel('com.fruitpos/locktask');

  /// Karyawan: full-screen immersive + lock task bila diizinkan.
  static Future<void> enterKiosk() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    try {
      await _channel.invokeMethod('startLockTask');
    } catch (_) {
      // Lock task tidak tersedia (bukan device owner) — abaikan, immersive tetap aktif.
    }
  }

  /// BOS / normal: kembali ke tampilan sistem standar.
  static Future<void> leaveKiosk() async {
    try {
      await _channel.invokeMethod('stopLockTask');
    } catch (_) {
      // ignore
    }
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
  }

  /// Sembunyikan kembali bar sistem ketika ter-swipe (immersive sticky sudah menangani).
  static Future<void> rehideSystemUI() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }
}
