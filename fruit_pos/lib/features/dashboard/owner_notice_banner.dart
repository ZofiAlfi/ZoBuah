import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../../models/broadcast_notice.dart';

/// Banner pengumuman owner di atas halaman POS.
///
  /// Banner ini tidak menyimpan daftar mana yang sudah ditutup. Penutupan dikembalikan
/// lewat [onDismiss] supaya pemilik widget bisa memilih pengumuman berikutnya:
/// kalau penyimpanannya sendiri, menutup pengumuman atas hanya akan membuat
/// banner hilang dan pengumuman di bawahnya tidak pernah muncul.
class OwnerNoticeBanner extends StatelessWidget {
  final BroadcastNotice notice;
  final VoidCallback onDismiss;

  const OwnerNoticeBanner({
    super.key,
    required this.notice,
    required this.onDismiss,
  });

  static const dismissedKey = 'owner_notice_dismissed_ids';

  /// Daftar id yang sudah ditutup, untuk dipakai kembali setelah app start.
  static Future<Set<String>> dismissedIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(dismissedKey) ?? const []).toSet();
  }

  /// Tandai satu pengumuman sudah ditutup. Penutupan disimpan per id, jadi
  /// pengumuman baru tetap muncul walaupun pengumuman lama sudah ditutup.
  static Future<void> markDismissed(String id) async {
    if (id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final dismissed = (prefs.getStringList(dismissedKey) ?? const []).toSet()..add(id);
    await prefs.setStringList(dismissedKey, dismissed.toList());
  }

  ({Color bg, Color fg, IconData icon, String label}) _styleFor(String level) {
    switch (level) {
      case 'maintenance':
        return (
          bg: AppColors.warning,
          fg: Colors.white,
          icon: Icons.build_circle_outlined,
          label: 'Pemeliharaan',
        );
      case 'warning':
        return (
          bg: AppColors.danger,
          fg: Colors.white,
          icon: Icons.warning_amber_rounded,
          label: 'Penting',
        );
      default:
        return (
          bg: AppColors.info,
          fg: Colors.white,
          icon: Icons.campaign_outlined,
          label: 'Info',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(notice.level);

    return Material(
      color: style.bg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(style.icon, color: style.fg, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          style.label.toUpperCase(),
                          style: TextStyle(
                            color: style.fg.withValues(alpha: 0.85),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                      Text(
                        notice.title,
                        style: TextStyle(
                          color: style.fg,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (notice.body.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          notice.body,
                        style: TextStyle(
                          color: style.fg.withValues(alpha: 0.95),
                          fontSize: 13.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
                IconButton(
                  tooltip: 'Tutup pengumuman',
                  onPressed: onDismiss,
                  icon: Icon(Icons.close, color: style.fg),
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
