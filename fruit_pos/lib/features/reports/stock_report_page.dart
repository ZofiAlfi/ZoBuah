import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_service.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../shared/widgets/common_widgets.dart';

class StockReportPage extends StatefulWidget {
  const StockReportPage({super.key});

  @override
  State<StockReportPage> createState() => _StockReportPageState();
}

class _StockReportPageState extends State<StockReportPage> {
  bool _loading = true;
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
    try {
      final api = context.read<ApiService>();
      _data = await api.fetchStockReport();
    } catch (e) {
      setState(() => _error = 'Gagal memuat laporan stok: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Laporan Stok')),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _buildContent(),
                ),
    );
  }

  Widget _buildContent() {
    final products = (_data?['products'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final totals = (_data?['totals'] as Map<String, dynamic>?) ?? {};
    final lowStock = (_data?['low_stock'] as List? ?? [])
        .cast<Map<String, dynamic>>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Ringkasan Pergerakan Stok',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary)),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _SummaryRow(
                  label: 'Total Stok Masuk',
                  value:
                      '${Formatters.quantity(totals['stock_in'] ?? 0)} unit',
                  color: AppColors.success,
                  icon: Icons.add_circle,
                ),
                const Divider(),
                _SummaryRow(
                  label: 'Total Terjual',
                  value:
                      '${Formatters.quantity(totals['sale_out'] ?? 0)} unit',
                  color: AppColors.info,
                  icon: Icons.shopping_cart,
                ),
                const Divider(),
                _SummaryRow(
                  label: 'Total Rusak',
                  value:
                      '${Formatters.quantity(totals['damage'] ?? 0)} unit',
                  color: AppColors.danger,
                  icon: Icons.warning,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text('Detail per Produk',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        if (products.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Belum ada data pergerakan stok',
                style: TextStyle(color: AppColors.textSecondary)),
          )
        else
          ...products.map(
            (p) => Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p['product_name'] ?? '?',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _MiniStat('Masuk', p['stock_in'] ?? 0, AppColors.success),
                        _MiniStat('Terjual', p['sale_out'] ?? 0, AppColors.info),
                        _MiniStat('Rusak', p['damage_out'] ?? 0, AppColors.danger),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Stok saat ini:',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.textSecondary)),
                        Text(
                          '${Formatters.quantity(p['current_stock'] ?? 0)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: AppColors.primary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (lowStock.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text('Stok Menipis',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.danger)),
          const SizedBox(height: 8),
          ...lowStock.map(
            (p) => ListTile(
              dense: true,
              leading: const Icon(Icons.warning_amber,
                  color: AppColors.warning),
              title: Text(p['name']?.toString() ?? '?'),
              subtitle: Text(
                  'Sisa ${Formatters.quantity(p['stock'] ?? 0)} ${p['unit'] ?? ''}'),
            ),
          ),
        ],
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _SummaryRow({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 14)),
        ),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.bold, color: color, fontSize: 14)),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final dynamic value;
  final Color color;
  const _MiniStat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            Formatters.quantity(value ?? 0),
            style: TextStyle(
                fontWeight: FontWeight.bold, color: color, fontSize: 14),
          ),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
