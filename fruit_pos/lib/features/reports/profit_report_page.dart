import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_service.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../shared/widgets/common_widgets.dart';

class ProfitReportPage extends StatefulWidget {
  const ProfitReportPage({super.key});

  @override
  State<ProfitReportPage> createState() => _ProfitReportPageState();
}

class _ProfitReportPageState extends State<ProfitReportPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _profitData;
  Map<String, dynamic>? _damageData;

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
        api.fetchProfitReport(),
        api.fetchDamageReportSummary(),
      ]);
      _profitData = results[0];
      _damageData = results[1];
    } catch (e) {
      setState(() => _error = 'Gagal memuat laporan laba: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Laba & Estimasi')),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text('Laba Kotor',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 12),
                      _ProfitCard(data: _profitData),
                      const SizedBox(height: 24),
                      const Text('Kerugian Akibat Produk Rusak',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 12),
                      _DamageSummaryCard(data: _damageData),
                    ],
                  ),
                ),
    );
  }
}

class _ProfitCard extends StatelessWidget {
  final Map<String, dynamic>? data;
  const _ProfitCard({this.data});

  @override
  Widget build(BuildContext context) {
    if (data == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Data tidak tersedia',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }

    final totalRevenue = data!['total_revenue'] ?? 0;
    final totalModal = data!['total_modal'] ?? 0;
    final grossProfit = data!['total_profit_gross'] ?? 0;
    final damageLoss = data!['damage_loss'] ?? 0;
    final netProfit = data!['net_profit'] ?? 0;
    final salesCount = data!['sales_count'] ?? 0;
    final margin = data!['gross_margin_percent'] ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('Total Pendapatan', Formatters.currency(totalRevenue)),
            _row('Total Modal', Formatters.currency(totalModal)),
            const Divider(),
            _row('Laba Kotor', Formatters.currency(grossProfit),
                bold: true, color: AppColors.success),
            _row('Kerugian Waste', Formatters.currency(damageLoss),
                bold: true, color: AppColors.danger),
            const Divider(),
            _row('Laba Bersih', Formatters.currency(netProfit),
                bold: true,
                color:
                    netProfit >= 0 ? AppColors.success : AppColors.danger),
            const SizedBox(height: 4),
            _row('Jumlah Transaksi', '$salesCount'),
            _row('Margin Kotor', '${Formatters.decimal(margin)}%'),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value,
      {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: bold ? FontWeight.w600 : FontWeight.normal)),
          Text(value,
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                color: color,
                fontSize: bold ? 15 : 14,
              )),
        ],
      ),
    );
  }
}

class _DamageSummaryCard extends StatelessWidget {
  final Map<String, dynamic>? data;
  const _DamageSummaryCard({this.data});

  @override
  Widget build(BuildContext context) {
    if (data == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Data tidak tersedia',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }

    final totalReports = data!['total_reports'] ?? 0;
    final statusCounts = (data!['status_counts'] as Map<String, dynamic>?) ?? {};
    final totalQty = data!['total_approved_quantity'] ?? 0;
    final totalLoss = data!['total_loss_value'] ?? 0;
    final perProduct = (data!['per_product'] as Map<String, dynamic>?) ?? {};

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('Total Laporan', '$totalReports'),
            _row('Pending', '${statusCounts['PENDING'] ?? 0}',
                color: AppColors.warning),
            _row('Disetujui', '${statusCounts['APPROVED'] ?? 0}',
                color: AppColors.success),
            _row('Ditolak', '${statusCounts['REJECTED'] ?? 0}',
                color: AppColors.danger),
            const Divider(),
            _row('Total Kuantitas Rusak',
                '${Formatters.quantity(totalQty)} unit',
                bold: true),
            _row('Total Nilai Kerugian', Formatters.currency(totalLoss),
                bold: true, color: AppColors.danger),
            if (perProduct.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Detail per Produk:',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              ...perProduct.entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(e.key,
                          style: const TextStyle(fontSize: 13)),
                      Text(
                        '${Formatters.quantity((e.value as Map)['quantity'] ?? 0)} - ${Formatters.currency((e.value as Map)['loss_value'] ?? 0)}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.danger),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value,
      {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.w600 : FontWeight.normal)),
          Text(value,
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                color: color,
                fontSize: 13,
              )),
        ],
      ),
    );
  }
}
