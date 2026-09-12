import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/auth_state.dart';
import '../../core/theme.dart';
import '../../services/kiosk_service.dart';
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

class _CashierHomeState extends State<CashierHome> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyKiosk());
  }

  void _applyKiosk() {
    debugPrint(
      '[CashierHome] _applyKiosk user=${context.read<AuthState>().user?.username} '
      'isKaryawan=${context.read<AuthState>().user?.isKaryawan}',
    );
    if (context.read<AuthState>().user?.isKaryawan == true) {
      KioskService.enterKiosk();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint(
      '[CashierHome] lifecycle=$state '
      'karyawan=${context.read<AuthState>().user?.isKaryawan}',
    );
    if (state == AppLifecycleState.resumed) {
      if (context.read<AuthState>().user?.isKaryawan == true) {
        KioskService.enterKiosk();
      }
    }
  }

  Future<void> _exitToLogin() async {
    await KioskService.leaveKiosk();
    if (mounted) await context.read<AuthState>().logout();
  }

  Future<void> _requestExit() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Keluar aplikasi?'),
            content: const Text('Kamu akan keluar dari aplikasi kasir.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Keluar'),
              ),
            ],
          ),
    );
    if (shouldExit == true &&
        mounted &&
        context.read<AuthState>().user?.isKaryawan == true) {
      await _exitToLogin();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _requestExit();
      },
      child: Scaffold(
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
                            builder: (_) => const SettingsPage(isHome: true),
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
