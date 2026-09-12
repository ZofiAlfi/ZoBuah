import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/api_service.dart';
import '../../auth/auth_state.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../database/app_database.dart';
import '../../models/product.dart';
import '../../shared/widgets/common_widgets.dart';
import '../../sync/connectivity_service.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _loading = true;
  bool _isOffline = false;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = context.read<AuthState>();
    final api = context.read<ApiService>();
    final db = AppDatabase.instance;
    final connectivity = context.read<ConnectivityService>();

    _isOffline = !connectivity.isOnline.value;

    try {
      if (auth.user?.isBos == true && !_isOffline) {
        _data = await api.fetchDashboard();
      } else {
        await _loadProductsFromLocal(db);
      }
    } catch (e) {
      await _loadProductsFromLocal(db);
      _isOffline = true;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadProductsFromLocal(AppDatabase db) async {
    await db.products.getAllProducts();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);

    final auth = context.watch<AuthState>();
    final isBos = auth.user?.isBos ?? false;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _OfflineBanner(isOffline: _isOffline),
            const SizedBox(height: 12),
            if (isBos)
              _buildBosDashboard()
            else
              _buildKaryawanDashboard(),
          ],
        ),
      ),
    );
  }

  Widget _buildKaryawanDashboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Halo, ${context.read<AuthState>().user?.fullName ?? 'Karyawan'}!',
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        const Text('Pilih menu di bawah untuk mulai bekerja.',
            style: TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 20),
        _MenuCard(
          icon: Icons.point_of_sale,
          label: 'Mulai Penjualan',
          subtitle: 'Buka kasir & buat transaksi',
          color: AppColors.primary,
          onTap: () => Navigator.pushNamed(context, '/sales'),
        ),
        const SizedBox(height: 12),
        _MenuCard(
          icon: Icons.error_outline,
          label: 'Laporkan Produk Rusak',
          subtitle: 'Laporkan buah busuk / susut',
          color: AppColors.danger,
          onTap: () => Navigator.pushNamed(context, '/damage/new'),
        ),
        const SizedBox(height: 12),
        _MenuCard(
          icon: Icons.history,
          label: 'Riwayat Transaksi',
          subtitle: 'Lihat transaksi yang pernah dibuat',
          color: AppColors.info,
          onTap: () => Navigator.pushNamed(context, '/transactions'),
        ),
        const SizedBox(height: 12),
        _MenuCard(
          icon: Icons.report_problem,
          label: 'Laporan Rusak Saya',
          subtitle: 'Status laporan kerusakan',
          color: AppColors.warning,
          onTap: () => Navigator.pushNamed(context, '/damage/list'),
        ),
      ],
    );
  }

  Widget _buildBosDashboard() {
    final d = _data;
    if (d == null) return const ErrorView(message: 'Data dashboard tidak tersedia');

    final lowStock = (d['low_stock_products'] as List? ?? [])
        .map((e) => Product.fromJson(e as Map<String, dynamic>))
        .toList();
    final ownerName =
        context.read<AuthState>().user?.fullName ?? 'Pemilik Toko';
    final today = DateTime.now();
    String tgl;
    try {
      tgl = DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(today);
    } catch (_) {
      final b = <String>[
        'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu',
      ];
      final m = <String>[
        'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
        'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
      ];
      tgl = '${b[today.weekday - 1]}, ${today.day} ${m[today.month - 1]} ${today.year}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeroHeader(
          greeting: 'Selamat datang kembali,',
          name: ownerName,
          date: tgl,
          pendingCount: d['pending_damage_count'] ?? 0,
          onPendingTap: () => Navigator.pushNamed(context, '/damage/list'),
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.45,
          children: [
            _StatCardModern(
              icon: Icons.payments_outlined,
              label: 'Omzet Hari Ini',
              value: Formatters.currency(d['revenue_today'] ?? 0),
              color: AppColors.primary,
              onTap: () => Navigator.pushNamed(context, '/transactions'),
            ),
            _StatCardModern(
              icon: Icons.receipt_long_outlined,
              label: 'Transaksi',
              value: '${d['sales_count_today'] ?? 0}',
              color: AppColors.accent,
              onTap: () => Navigator.pushNamed(context, '/transactions'),
            ),
            _StatCardModern(
              icon: Icons.shopping_basket_outlined,
              label: 'Produk Terjual',
              value: Formatters.quantity(d['items_sold_today'] ?? 0),
              color: AppColors.info,
            ),
            _StatCardModern(
              icon: Icons.trending_up,
              label: 'Laba Kotor',
              value: Formatters.currency(d['profit_today'] ?? 0),
              color: AppColors.success,
              onTap: () => Navigator.pushNamed(context, '/reports'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _PendingDamageCard(
          count: d['pending_damage_count'] ?? 0,
          lossValue: Formatters.currency(d['pending_damage_loss_value'] ?? 0),
          onTap: () => Navigator.pushNamed(context, '/damage/list'),
        ),
        const SizedBox(height: 24),
        const _SectionTitle(icon: Icons.inventory_2_outlined, title: 'Stok Menipis'),
        const SizedBox(height: 4),
        if (lowStock.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Semua stok aman.',
                style: TextStyle(color: AppColors.textSecondary)),
          )
        else
          ...lowStock.map((p) => _LowStockCard(product: p)),
        const SizedBox(height: 20),
        const _SectionTitle(
            icon: Icons.emoji_events_outlined, title: 'Produk Terlaris'),
        const SizedBox(height: 4),
        _TopProductsModern(
            list: (d['top_products'] as List? ?? []).cast<Map<String, dynamic>>()),
      ],
    );
  }
}

class _HeroHeader extends StatelessWidget {
  final String greeting;
  final String name;
  final String date;
  final int pendingCount;
  final VoidCallback onPendingTap;
  const _HeroHeader({
    required this.greeting,
    required this.name,
    required this.date,
    required this.pendingCount,
    required this.onPendingTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storefront, color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              Text(
                'Pusat Kendali Toko',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.85), fontSize: 13),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onPendingTap,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.report_problem,
                          size: 16, color: Colors.white),
                      const SizedBox(width: 5),
                      Text(
                        '$pendingCount menunggu',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(greeting,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.8), fontSize: 13)),
          const SizedBox(height: 2),
          Text(name,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Row(
            children: [
              const Icon(Icons.calendar_today, size: 13, color: Colors.white70),
              const SizedBox(width: 6),
              Text(date,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.85), fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCardModern extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  const _StatCardModern({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right,
                      size: 16, color: AppColors.textSecondary),
                ],
              ),
              const SizedBox(height: 10),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  )),
              Text(label,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingDamageCard extends StatelessWidget {
  final int count;
  final String lossValue;
  final VoidCallback onTap;
  const _PendingDamageCard({
    required this.count,
    required this.lossValue,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child:
                    const Icon(Icons.warning_amber, color: AppColors.warning),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      count > 0
                          ? '$count laporan menunggu persetujuan'
                          : 'Tidak ada laporan menunggu',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Perkiraan kerugian: $lossValue',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary)),
      ],
    );
  }
}

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _MenuCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _LowStockCard extends StatelessWidget {
  final Product product;
  const _LowStockCard({required this.product});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.warning.withOpacity(0.15),
          child: const Icon(Icons.warning_amber,
              color: AppColors.warning, size: 20),
        ),
        title: Text(product.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
            'Tersisa ${Formatters.quantity(product.stock)} ${product.unit} · Batas min ${Formatters.quantity(product.minStock)} ${product.unit}'),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        onTap: () => Navigator.pushNamed(context, '/stock'),
      ),
    );
  }
}

class _TopProductsModern extends StatelessWidget {
  final List<Map<String, dynamic>> list;
  const _TopProductsModern({required this.list});

  @override
  Widget build(BuildContext context) {
    if (list.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Belum ada penjualan hari ini.',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            for (var i = 0; i < list.length; i++)
              ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: i < 3
                      ? AppColors.primary.withOpacity(0.12)
                      : AppColors.textSecondary.withOpacity(0.12),
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: i < 3
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
                title: Text(list[i]['name']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                    'Terjual ${Formatters.quantity(list[i]['total_qty'] ?? 0)}'),
                trailing: list[i].containsKey('total_revenue')
                    ? Text(
                        Formatters.currency(list[i]['total_revenue'] ?? 0),
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.success),
                      )
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  final bool isOffline;
  const _OfflineBanner({required this.isOffline});

  @override
  Widget build(BuildContext context) {
    if (!isOffline) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        children: [
          Icon(Icons.cloud_off, color: AppColors.warning),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Mode offline. Data akan disimpan di perangkat dan disinkronkan saat koneksi kembali.',
              style: TextStyle(fontSize: 12, color: AppColors.warning),
            ),
          ),
        ],
      ),
    );
  }
}