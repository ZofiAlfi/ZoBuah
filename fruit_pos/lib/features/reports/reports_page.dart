import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_service.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/product.dart';
import '../../shared/widgets/common_widgets.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _daily;

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
    try {
      final api = context.read<ApiService>();
      final results = await Future.wait([
        api.fetchDashboard(),
      ]);
      _daily = results[0];
    } catch (e) {
      setState(() => _error = 'Gagal memuat laporan: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Laporan & Analisis')),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _ReportSection(
                        title: 'Hari Ini',
                        rows: [
                          _RowData('Omzet', Formatters.currency(_daily?['revenue_today'] ?? 0)),
                          _RowData('Laba Kotor', Formatters.currency(_daily?['profit_today'] ?? 0)),
                          _RowData('Jumlah Transaksi', '${_daily?['sales_count_today'] ?? 0}'),
                          _RowData('Produk Terjual', Formatters.quantity(_daily?['items_sold_today'] ?? 0)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text('Produk Stok Menipis',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 8),
                      ..._lowStockTiles(),
                      const SizedBox(height: 24),
                      const Text('Menu Laporan',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 8),
                      for (final item in _menuItems())
                        Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: Icon(item.icon, color: AppColors.primary),
                            title: Text(item.title),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _openMenu(item.destination),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  List<Widget> _lowStockTiles() {
    final list = (_daily?['low_stock_products'] as List? ?? [])
        .map((e) => Product.fromJson(e as Map<String, dynamic>))
        .toList();
    if (list.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.all(12),
          child: Text('Semua stok aman.',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      ];
    }
    return list
        .map((p) => ListTile(
              dense: true,
              leading: const Icon(Icons.warning_amber, color: AppColors.warning),
              title: Text(p.name),
              subtitle: Text(
                  'Sisa ${Formatters.quantity(p.stock)} ${p.unit}'),
            ))
        .toList();
  }

  List<_MenuInfo> _menuItems() => [
        const _MenuInfo('Penjualan', Icons.receipt_long, '/reports/sales'),
        const _MenuInfo('Stok', Icons.inventory_2, '/reports/stock'),
        const _MenuInfo('Produk Rusak', Icons.report_problem, '/damage/list'),
        const _MenuInfo('Laba & Estimasi', Icons.trending_up, '/reports/profit'),
        const _MenuInfo('Audit Log', Icons.history_edu, '/audit'),
        const _MenuInfo('Kelola Karyawan', Icons.group, '/employees'),
      ];

  void _openMenu(String route) {
    Navigator.pushNamed(context, route);
  }
}

class _ReportSection extends StatelessWidget {
  final String title;
  final List<_RowData> rows;
  const _ReportSection({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(row.label,
                        style: const TextStyle(color: AppColors.textSecondary)),
                    Text(row.value,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RowData {
  final String label;
  final String value;
  const _RowData(this.label, this.value);
}

class _MenuInfo {
  final String title;
  final IconData icon;
  final String destination;
  const _MenuInfo(this.title, this.icon, this.destination);
}