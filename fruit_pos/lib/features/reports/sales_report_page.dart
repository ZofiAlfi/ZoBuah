import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_service.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../shared/widgets/common_widgets.dart';

class SalesReportPage extends StatefulWidget {
  const SalesReportPage({super.key});

  @override
  State<SalesReportPage> createState() => _SalesReportPageState();
}

class _SalesReportPageState extends State<SalesReportPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _dailyData;
  Map<String, dynamic>? _weeklyData;
  Map<String, dynamic>? _monthlyData;
  List<Map<String, dynamic>> _topProducts = [];
  List<Map<String, dynamic>> _byEmployee = [];

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
      final results = await Future.wait<Object?>([
        api.fetchReport('daily'),
        api.fetchReport('weekly'),
        api.fetchReport('monthly'),
        api.fetchTopProducts(limit: 10),
        api.fetchSalesByEmployee(),
      ]);
      _dailyData = results[0] as Map<String, dynamic>?;
      _weeklyData = results[1] as Map<String, dynamic>?;
      _monthlyData = results[2] as Map<String, dynamic>?;
      _topProducts = (results[3] as List).cast<Map<String, dynamic>>();
      _byEmployee = (results[4] as List).cast<Map<String, dynamic>>();
    } catch (e) {
      setState(() => _error = 'Gagal memuat laporan penjualan: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Laporan Penjualan')),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _SummarySection(
                        title: 'Hari Ini',
                        data: _dailyData,
                      ),
                      const SizedBox(height: 12),
                      _SummarySection(
                        title: 'Minggu Ini',
                        data: _weeklyData,
                      ),
                      const SizedBox(height: 12),
                      _SummarySection(
                        title: 'Bulan Ini',
                        data: _monthlyData,
                      ),
                      const SizedBox(height: 24),
                      const Text('Produk Terlaris',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 8),
                      if (_topProducts.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('Belum ada data',
                              style: TextStyle(color: AppColors.textSecondary)),
                        )
                      else
                        ..._topProducts.asMap().entries.map(
                              (e) => ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  backgroundColor:
                                      AppColors.primary.withOpacity(0.1),
                                  child: Text('${e.key + 1}',
                                      style: const TextStyle(
                                          color: AppColors.primary)),
                                ),
                                title: Text(e.value['product_name'] ?? ''),
                                subtitle: Text(
                                    'Terjual ${Formatters.quantity(e.value['total_qty'] ?? 0)}'),
                                trailing: Text(
                                  Formatters.currency(
                                      e.value['total_revenue'] ?? 0),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                      const SizedBox(height: 24),
                      const Text('Penjualan per Karyawan',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 8),
                      if (_byEmployee.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('Belum ada data',
                              style: TextStyle(color: AppColors.textSecondary)),
                        )
                      else
                        ..._byEmployee.map(
                          (e) => Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    AppColors.info.withOpacity(0.1),
                                child: const Icon(Icons.person,
                                    color: AppColors.info, size: 20),
                              ),
                              title: Text(e['employee_name'] ?? ''),
                              subtitle: Text(
                                  '${e['total_sales'] ?? 0} transaksi'),
                              trailing: Text(
                                Formatters.currency(e['total_amount'] ?? 0),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

class _SummarySection extends StatelessWidget {
  final String title;
  final Map<String, dynamic>? data;
  const _SummarySection({required this.title, this.data});

  @override
  Widget build(BuildContext context) {
    if (data == null) {
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
              const SizedBox(height: 8),
              const Text('Data tidak tersedia',
                  style: TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
    }

    final rows = [
      _RowData('Total Penjualan',
          '${data!['total_sales'] ?? data!['sales_count'] ?? 0}'),
      _RowData('Total Omzet',
          Formatters.currency(data!['total_amount'] ?? 0)),
      _RowData('Laba Kotor',
          Formatters.currency(data!['total_profit'] ?? 0)),
    ];

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
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(row.label,
                        style:
                            const TextStyle(color: AppColors.textSecondary)),
                    Text(row.value,
                        style:
                            const TextStyle(fontWeight: FontWeight.w600)),
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
