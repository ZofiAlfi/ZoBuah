import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../database/app_database.dart';
import '../../services/notification_service.dart';
import '../../sync/sync_manager.dart';
import '../sales/sales_page.dart';
import '../settings/settings_page.dart';
import '../transactions/transactions_page.dart';
import '../damage/new_damage_report_page.dart';

/// Halaman tunggal untuk karyawan: POS kasir lengkap + akses cepat fitur lain.
class CashierHome extends StatefulWidget {
  const CashierHome({super.key});

  @override
  State<CashierHome> createState() => _CashierHomeState();
}

class _CashierHomeState extends State<CashierHome> {
  static const _statusKey = 'karyawan_damage_status';
  late final SyncManager _sync;

  @override
  void initState() {
    super.initState();
    _sync = context.read<SyncManager>();
    _sync.addListener(_onSyncChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onSyncChanged());
  }

  @override
  void dispose() {
    _sync.removeListener(_onSyncChanged);
    super.dispose();
  }

  Future<void> _onSyncChanged() async {
    if (!mounted) return;
    try {
      final reports = await AppDatabase.instance.damage
          .getDamageReports();
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_statusKey);
      final known = <String, String>{
        if (stored != null && stored.isNotEmpty)
          for (final entry in stored.split(','))
            if (entry.contains('='))
              entry.split('=').first: entry.split('=').last,
      };
      final isInitial = known.isEmpty;
      for (final r in reports) {
        final id = r.id;
        if (id == null) continue;
        final prev = known[id];
        if (!isInitial &&
            prev != r.status &&
            (r.isApproved || r.isRejected)) {
          final label = r.isApproved ? 'disetujui' : 'ditolak';
          await NotificationService.instance.showDamageStatus(
            'Laporan produk rusak $label',
            '${Formatters.quantity(r.quantity)} ${r.unit} ${r.productName ?? 'Produk'}',
          );
        }
        known[id] = r.status;
      }
      final entries = known.entries
          .where((e) => e.key.isNotEmpty && e.value.isNotEmpty)
          .map((e) => '${e.key}=${e.value}')
          .toList();
      await prefs.setString(_statusKey, entries.join(','));
    } catch (_) {
      // Abaikan, akan dicoba lagi di sinkron berikutnya.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AppLogo(),
              SizedBox(width: 8),
              Text('Laporan Buah - Kasir'),
            ],
          ),
          leading: const SizedBox.shrink(),
          actions: [
            IconButton(
              icon: const Icon(Icons.sync),
              onPressed: () {
                context.read<SyncManager>().syncNow(forcePull: true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sinkronisasi dijalankan...')),
                );
              },
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _ShortcutChip(
                    icon: Icons.receipt_long,
                    label: 'Riwayat Transaksi',
                    color: AppColors.info,
                    onTap:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const TransactionsPage(),
                          ),
                        ),
                  ),
                  _ShortcutChip(
                    icon: Icons.error_outline,
                    label: 'Lapor Rusak',
                    color: AppColors.danger,
                    onTap:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const NewDamageReportPage(),
                          ),
                        ),
                  ),
                  _ShortcutChip(
                    icon: Icons.menu,
                    label: 'Menu',
                    color: AppColors.textSecondary,
                    onTap:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SettingsPage(),
                          ),
                        ),
                  ),
                ],
              ),
            ),
            const Divider(height: 12),
            const Expanded(child: SalesPage(embedded: true)),
          ],
        ),
    );
  }
}

class _AppLogo extends StatelessWidget {
  const _AppLogo();

  @override
  Widget build(BuildContext context) {
    return Image.asset('assets/logo.png', width: 24, height: 24);
  }
}

class _ShortcutChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ShortcutChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      backgroundColor: Colors.white,
      onPressed: onTap,
    );
  }
}
