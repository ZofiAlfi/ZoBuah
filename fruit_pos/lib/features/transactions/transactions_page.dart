import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../database/app_database.dart';
import '../../models/sale.dart';
import '../../shared/widgets/common_widgets.dart';

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key});

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  bool _loading = true;
  List<Sale> _sales = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = AppDatabase.instance;
    _sales = await db.sales.getSales(limit: 200);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat Transaksi')),
      body: _loading
          ? const LoadingView()
          : _sales.isEmpty
              ? const EmptyView(message: 'Belum ada transaksi')
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _sales.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) => _SaleTile(
                      sale: _sales[i],
                      onTap: () => _showDetail(_sales[i]),
                    ),
                  ),
                ),
    );
  }

  void _showDetail(Sale sale) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        builder: (_, controller) => _SaleDetail(sale: sale, scroll: controller),
      ),
    );
  }
}

class _SaleTile extends StatelessWidget {
  final Sale sale;
  final VoidCallback onTap;
  const _SaleTile({required this.sale, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        title: Text(sale.transactionNumber,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          '${sale.employeeName ?? '-'}\n${Formatters.dateTime(DateTime.tryParse(sale.createdAt ?? ''))} · ${sale.items.length} item',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(Formatters.currency(sale.totalAmount),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: AppColors.primary)),
            const SizedBox(height: 2),
            StatusBadge(status: sale.status),
          ],
        ),
      ),
    );
  }
}

class _SaleDetail extends StatelessWidget {
  final Sale sale;
  final ScrollController scroll;
  const _SaleDetail({required this.sale, required this.scroll});

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            color: const Color(0xFFE0E0E0),
          ),
        ),
        const SizedBox(height: 16),
        Text(sale.transactionNumber,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(
          Formatters.dateTime(DateTime.tryParse(sale.createdAt ?? '')),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        for (final item in sale.items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${item.productName} (${item.quantity} ${item.unit} x ${Formatters.currency(item.unitPrice)})',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                Text(Formatters.currency(item.subtotal),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        const Divider(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Subtotal',
                style: TextStyle(color: AppColors.textSecondary)),
            Text(Formatters.currency(
                sale.totalAmount + sale.discount)),
          ],
        ),
        if (sale.discount > 0)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Diskon',
                  style: TextStyle(color: AppColors.textSecondary)),
              Text('-${Formatters.currency(sale.discount)}'),
            ],
          ),
        const Divider(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('TOTAL',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Text(Formatters.currency(sale.totalAmount),
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: AppColors.primary)),
          ],
        ),
        const SizedBox(height: 12),
        if (sale.payment != null) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Metode: ${sale.payment!.method}',
                  style: const TextStyle(color: AppColors.textSecondary)),
              if (sale.payment!.changeAmount != null)
                Text(
                  'Kembalian: ${Formatters.currency(sale.payment!.changeAmount!)}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
            ],
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}