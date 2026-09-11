import 'package:flutter/material.dart';
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

    return RefreshIndicator(
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Ringkasan Toko',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.4,
          children: [
            _StatCard(
              icon: Icons.payments,
              label: 'Omzet Hari Ini',
              value: Formatters.currency(d['revenue_today'] ?? 0),
              color: AppColors.primary,
              onTap: () => Navigator.pushNamed(context, '/transactions'),
            ),
            _StatCard(
              icon: Icons.receipt_long,
              label: 'Transaksi Hari Ini',
              value: '${d['sales_count_today'] ?? 0}',
              color: AppColors.info,
              onTap: () => Navigator.pushNamed(context, '/transactions'),
            ),
            _StatCard(
              icon: Icons.shopping_basket,
              label: 'Produk Terjual',
              value: Formatters.quantity(d['items_sold_today'] ?? 0),
              color: AppColors.accent,
            ),
            _StatCard(
              icon: Icons.trending_up,
              label: 'Laba Kotor',
              value: Formatters.currency(d['profit_today'] ?? 0),
              color: AppColors.success,
              onTap: () => Navigator.pushNamed(context, '/reports'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _StatCardWide(
                icon: Icons.report_problem,
                label: 'Menunggu Approval Rusak',
                value: '${d['pending_damage_count'] ?? 0}',
                subValue:
                    'Nilai kerugian: ${Formatters.currency(d['pending_damage_loss_value'] ?? 0)}',
                color: AppColors.warning,
                onTap: () => Navigator.pushNamed(context, '/damage/list'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text('Produk Stok Menipis',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        if (lowStock.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Semua stok aman.',
                style: TextStyle(color: AppColors.textSecondary)),
          )
        else
          ...lowStock.map((p) => _LowStockTile(product: p)),
        const SizedBox(height: 24),
        const Text('Produk Terlaris',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        _TopProducts(list: (d['top_products'] as List? ?? []).cast<Map<String, dynamic>>()),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  const _StatCard({
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
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 28),
              Text(value,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: color,
                    overflow: TextOverflow.ellipsis,
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

class _StatCardWide extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String subValue;
  final Color color;
  final VoidCallback? onTap;

  const _StatCardWide({
    required this.icon,
    required this.label,
    required this.value,
    required this.subValue,
    required this.color,
    this.onTap,
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
              Icon(icon, color: color, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value,
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: color)),
                    Text(label,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textPrimary)),
                    if (subValue.isNotEmpty)
                      Text(subValue,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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

class _LowStockTile extends StatelessWidget {
  final Product product;
  const _LowStockTile({required this.product});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.warning_amber, color: AppColors.warning),
        title: Text(product.name),
        subtitle: Text(
            'Sisa ${Formatters.quantity(product.stock)} ${product.unit} (min ${Formatters.quantity(product.minStock)} ${product.unit})'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.pushNamed(context, '/stock'),
      ),
    );
  }
}

class _TopProducts extends StatelessWidget {
  final List<Map<String, dynamic>> list;
  const _TopProducts({required this.list});

  @override
  Widget build(BuildContext context) {
    if (list.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Belum ada penjualan hari ini.',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < list.length; i++)
          ListTile(
            dense: true,
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withOpacity(0.1),
              child: Text('${i + 1}',
                  style: const TextStyle(color: AppColors.primary)),
            ),
            title: Text(list[i]['name']?.toString() ?? ''),
            subtitle: Text('Terjual ${list[i]['total_qty']}'),
          ),
      ],
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