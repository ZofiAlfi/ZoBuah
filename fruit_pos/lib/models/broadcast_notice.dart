/// Pengumuman dari owner SaaS yang tiba lewat sync pull.
///
/// Backend mengirim paling banyak satu pengumuman per level lewat
/// `app_settings`, jadi kunci map-nya adalah level itu sendiri
/// ('info', 'warning', 'maintenance').
class BroadcastNotice {
  final String level;
  final String id;
  final String title;
  final String body;
  final DateTime? startsAt;
  final DateTime? expiresAt;

  const BroadcastNotice({
    required this.level,
    required this.id,
    required this.title,
    required this.body,
    this.startsAt,
    this.expiresAt,
  });

  factory BroadcastNotice.fromJson(String level, Map<String, dynamic> json) {
    return BroadcastNotice(
      level: level,
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      startsAt: _parseDate(json['starts_at']),
      expiresAt: _parseDate(json['expires_at']),
    );
  }

  factory BroadcastNotice.fromMap(String level, Map<String, dynamic> map) {
    return BroadcastNotice(
      level: level,
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      body: map['body'] as String? ?? '',
      startsAt: _parseDate(map['starts_at']),
      expiresAt: _parseDate(map['expires_at']),
    );
  }

  /// Tanggal dari server selalu dikirim sebagai waktu UTC dengan suffix Z,
  /// misalnya "2026-09-28T02:53:40.738865Z".
  ///
  /// `DateTime.tryParse` memperlakukan string tanpa offset sebagai waktu
  /// lokal, lalu `toLocal()` tidak mengubah apa pun karena sudah lokal. Hasilnya
  /// jam pengumuman bergeser sebesar selisih zona waktu: pengumuman yang
  /// seharusnya kedaluwarsa besok pagi hilang 7 jam lebih awal.
  ///
  /// Cabang tanpa offset di bawah bukan lagi jalur yang diharapkan, tapi tetap
  /// dipertahankan untuk server lama yang belum memakai kontrak baru. Melewati
  /// pengumuman karena format berubah lebih buruk daripada satu jam selisih,
  /// jadi parsing dibuat toleran terhadap kedua bentuk.
  static DateTime? _parseDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    var text = raw.trim();
    final hasOffset =
        text.endsWith('Z') || text.endsWith('z') || _offsetPattern.hasMatch(text);
    if (!hasOffset) text = '${text}Z';
    return DateTime.tryParse(text)?.toLocal();
  }

  static final RegExp _offsetPattern = RegExp(r'[+-]\d{2}:?\d{2}$');

  /// Urutan tampil: yang paling mendesak didahulukan.
  bool get isUrgent => level == 'warning' || level == 'maintenance';

  /// Bentuk yang disimpan di perangkat.
  ///
  /// Wajib ditulis sebagai UTC dengan suffix Z. Nilai `startsAt`/`expiresAt`
  /// sudah berupa waktu lokal, dan `toIso8601String()` untuk waktu lokal tidak
  /// memuat suffix Z. Kalau string tanpa offset itu nanti dibaca kembali sebagai
  /// UTC, jamnya bergeser satu kali lagi setiap kali app start, dan setiap
  /// start berikutnya menggesernya satu zona waktu lagi.
  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'body': body,
        'starts_at': startsAt?.toUtc().toIso8601String(),
        'expires_at': expiresAt?.toUtc().toIso8601String(),
      };
}
