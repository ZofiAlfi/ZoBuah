import 'dart:convert';

class AppConstants {
  static const String appName = 'Laporan Buah';
  static const String appVersion = '1.0.0';
  static const String appCredit = 'Made with love by Herry';

  /// Base URL API. Di-set saat build lewat:
  ///   flutter build apk --dart-define=API_BASE_URL=https://nama-app.onrender.com
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );
  static const String apiV1 = '$baseUrl/api/v1';

  /// True kalau API-nya Accessible tanpa internet, yaitu lewat `adb reverse`
  /// (localhost) atau emulator loopback. Pada mode ini device bisa saja
  /// tidak punya Wi-Fi/mibil/data sama sekali, jadi status konektivitas
  /// tidak boleh dipakai untuk decide "offline".
  static bool get isLoopbackApi {
    final host = Uri.tryParse(baseUrl)?.host ?? '';
    return host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '10.0.2.2' ||
        host == '0.0.0.0';
  }

  static const String dbName = 'fruit_pos.db';
  static const int dbVersion = 1;

  static const String prefAuthToken = 'auth_token';
  static const String prefRefreshToken = 'refresh_token';
  static const String prefUserId = 'user_id';
  static const String prefRole = 'user_role';
  static const String prefFullName = 'user_full_name';
  static const String prefUsername = 'user_username';
  static const String prefDeviceId = 'device_id';
  static const String prefLastSync = 'last_sync_at';
  static const String prefNotices = 'owner_notices';

  static const List<String> units = [
    'kg', 'gram', 'buah', 'sisir', 'ikat', 'dus', 'paket', 'liter', 'loyang',
    'cup', 'pcs', 'sak',
  ];

  static const List<String> damageReasons = [
    'BUSUK',
    'RUSAK_FISIK',
    'JATUH',
    'KADALUARSA',
    'SUSUT',
    'LAINNYA',
  ];

  static String encodeBase64(String s) => base64Encode(utf8.encode(s));
}