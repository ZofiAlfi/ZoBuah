import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/auth_state.dart';
import '../../sync/sync_manager.dart';
import '../cashier/cashier_home.dart';
import '../settings/settings_page.dart';
import '../stock/stock_page.dart';
import '../transactions/transactions_page.dart';
import 'dashboard_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final user = auth.user;

    // Karyawan: satu halaman kasir lengkap (kiosk).
    if (user != null && !user.isBos) return const CashierHome();

    final pages = <Widget>[
      const DashboardPage(),
      const StockPage(),
      const TransactionsPage(),
      const SettingsPage(isHome: true),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/logo.png', width: 24, height: 24),
            const SizedBox(width: 8),
            const Text('Laporan Buah - Pemilik'),
          ],
        ),
        leading: null,
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
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Stok',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Transaksi',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Menu',
          ),
        ],
      ),
    );
  }
}