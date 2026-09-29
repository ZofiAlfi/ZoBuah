import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/api_service.dart';
import '../../auth/auth_state.dart';
import '../../core/formatters.dart';
import '../../models/broadcast_notice.dart';
import '../../services/notification_service.dart';
import '../../sync/sync_manager.dart';
import '../cashier/cashier_home.dart';
import '../settings/settings_page.dart';
import '../stock/stock_page.dart';
import '../transactions/transactions_page.dart';
import 'dashboard_page.dart';
import 'owner_notice_banner.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _seenKey = 'bos_seen_damage_ids';
  int _index = 0;
  late final SyncManager _sync;
  Set<String> _dismissedNotices = <String>{};

  @override
  void initState() {
    super.initState();
    _sync = context.read<SyncManager>();
    _sync.addListener(_onSyncChanged);
    _loadDismissedNotices();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onSyncChanged());
  }

  Future<void> _loadDismissedNotices() async {
    final ids = await OwnerNoticeBanner.dismissedIds();
    if (!mounted) return;
    setState(() => _dismissedNotices = ids);
  }

  /// Menutup pengumuman atas harus membuat pengumuman di bawahnya langsung
  /// tampil, jadi daftar yang ditutup hidup di sini, bukan di dalam banner.
  void _dismissNotice(String id) {
    setState(() => _dismissedNotices = {..._dismissedNotices, id});
    OwnerNoticeBanner.markDismissed(id);
  }

  @override
  void dispose() {
    _sync.removeListener(_onSyncChanged);
    super.dispose();
  }

  Future<void> _onSyncChanged() async {
    if (!mounted) return;
    try {
      final reports = await context
          .read<ApiService>()
          .fetchDamageReports(status: 'PENDING');
      final ids = {for (final r in reports) r.id}.whereType<String>().toSet();
      final prefs = await SharedPreferences.getInstance();
      final seen = (prefs.getStringList(_seenKey) ?? const []).toSet();
      final newIds = ids.difference(seen);
      final isInitial = seen.isEmpty;
      if (!isInitial && newIds.isNotEmpty) {
        final fresh = reports
            .where((r) => newIds.contains(r.id))
            .toList();
        final title = fresh.length == 1
            ? 'Laporan produk rusak baru'
            : '${fresh.length} laporan produk rusak baru';
        final first = fresh.first;
        final body = fresh.length == 1
            ? '${first.productName ?? 'Produk'} (${Formatters.quantity(first.quantity)} ${first.unit}) oleh ${first.employeeName ?? '-'}'
            : '${first.productName ?? 'Produk'} dkk. menunggu persetujuan';
        await NotificationService.instance.showDamagePending(title, body);
      }
      await prefs.setStringList(_seenKey, seen.union(ids).toList());
    } catch (_) {
      // Abaikan (offline/token, akan dicoba lagi di sinkron berikutnya).
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final user = auth.user;

    // Pengumuman owner berlaku untuk semua peran, jadi banner dipasang di luar
    // percabangan BOS/Karyawan. Yang sudah ditutup difilter di sini supaya
    // menutup pengumuman atas langsung memunculkan pengumuman berikutnya.
    // ValueListenableBuilder dipakai, bukan _sync.notices.value, karena
    // ValueNotifier tidak membangun ulang HomeShell saat nilainya berubah.
    final noticeBanner = ValueListenableBuilder<List<BroadcastNotice>>(
      valueListenable: _sync.notices,
      builder: (context, notices, _) {
        final visible = notices
            .where((n) => !_dismissedNotices.contains(n.id))
            .toList();
        if (visible.isEmpty) return const SizedBox.shrink();
        final notice = visible.first;
        return OwnerNoticeBanner(
          key: ValueKey(notice.id),
          notice: notice,
          onDismiss: () => _dismissNotice(notice.id),
        );
      },
    );

    // Karyawan: satu halaman kasir lengkap (kiosk). CashierHome sudah
    // menjadi Scaffold-nya sendiri, jadi di sini tidak perlu Scaffold kedua.
    if (user != null && !user.isBos) {
      return Column(
        children: [
          noticeBanner,
          const Expanded(child: CashierHome()),
        ],
      );
    }

    final pages = <Widget>[
      const DashboardPage(),
      const StockPage(),
      const TransactionsPage(),
      const SettingsPage(isHome: true),
    ];

    return Scaffold(
      body: Column(
        children: [
          noticeBanner,
          Expanded(child: IndexedStack(index: _index, children: pages)),
        ],
      ),
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