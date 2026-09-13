import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Menampilkan notifikasi lokal untuk laporan kerusakan produk.
///
/// Dipakai saat sinkron (app terbuka/foreground): BOS dapat notifikasi laporan
/// rusak baru, karyawan dapat notifikasi saat laporannya disetujui/ditolak.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Dipanggil saat notifikasi kerusakan ditekan, untuk membuka daftar laporan.
  VoidCallback? onOpenDamage;

  Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
    );
    final ok = await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onTap,
    );
    _ready = ok ?? false;

    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.requestNotificationsPermission();
    }
  }

  void _onTap(NotificationResponse response) {
    if (response.payload == 'open_damage_list') {
      onOpenDamage?.call();
    }
  }

  Future<void> _show(int id, String title, String body) async {
    if (!_ready) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'damage_channel',
        'Kerusakan Produk',
        channelDescription: 'Notifikasi laporan kerusakan produk',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _plugin.show(
      id,
      title,
      body,
      details,
      payload: 'open_damage_list',
    );
  }

  Future<void> showDamagePending(String title, String body) {
    return _show(1001, title, body);
  }

  Future<void> showDamageStatus(String title, String body) {
    return _show(1002, title, body);
  }
}