import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../api/api_service.dart';
import '../../auth/auth_state.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../database/app_database.dart';
import '../../models/sale.dart';
import '../../shared/widgets/common_widgets.dart';
import '../../sync/sync_manager.dart';

class PaymentPage extends StatefulWidget {
  final List<SaleItem> items;
  const PaymentPage({super.key, required this.items});

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  String _method = 'CASH';
  TextEditingController _cashCtrl = TextEditingController();
  TextEditingController _discountCtrl = TextEditingController();
  bool _processing = false;

  double get _subtotal =>
      widget.items.fold(0, (sum, item) => sum + item.subtotal);

  double get _discount =>
      double.tryParse(_discountCtrl.text.replaceAll(',', '.')) ?? 0;

  double get _total {
    final t = _subtotal - _discount;
    return t < 0 ? 0 : t;
  }

  double get _change {
    final cash = double.tryParse(_cashCtrl.text.replaceAll(',', '.')) ?? 0;
    return cash - _total;
  }

  @override
  void dispose() {
    _cashCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  Future<void> _processPayment() async {
    if (_method == 'CASH') {
      final cash = double.tryParse(_cashCtrl.text.replaceAll(',', '.')) ?? 0;
      if (cash < _total) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Uang diterima kurang dari total')),
        );
        return;
      }
    }

    setState(() => _processing = true);
    final auth = context.read<AuthState>();
    final api = context.read<ApiService>();
    final db = AppDatabase.instance;
    final syncManager = context.read<SyncManager>();

    final now = DateTime.now();
    final saleId = const Uuid().v4();
    final transactionNumber = 'TRX-${now.year}${_two(now.month)}${_two(now.day)}-${saleId.substring(0, 3).toUpperCase()}';

    final totalModal =
        widget.items.fold(0.0, (sum, item) => sum + item.modalPrice * item.quantity);

    final sale = Sale(
      id: saleId,
      transactionNumber: transactionNumber,
      employeeId: auth.user?.id ?? '',
      employeeName: auth.user?.fullName,
      totalAmount: _total,
      totalModal: totalModal,
      totalProfit: _total - totalModal,
      discount: _discount,
      status: 'COMPLETED',
      createdAt: now.toIso8601String(),
      items: widget.items,
      payment: Payment(
        method: _method,
        amount: _total,
        cashReceived: _method == 'CASH'
            ? double.tryParse(_cashCtrl.text.replaceAll(',', '.'))
            : null,
        changeAmount: _method == 'CASH' && _change >= 0 ? _change : null,
      ),
    );

    try {
      // Coba langsung ke server
      final res = await api.createSale(sale.toSyncJson());
      final serverSale = Sale.fromJson(res);
      await db.sales.insertSale(serverSale);
      await db.sales.markSynced(saleId);
      await _updateLocalStock();
      if (mounted) _showSuccess(serverSale);
    } catch (e) {
      // Simpan ke lokal, masuk queue sinkronisasi
      await db.sales.insertSale(sale);
      await _applyLocalStockSubtraction();
      await syncManager.enqueueSale(saleId, sale.toSyncJson());
      if (mounted) _showSuccessOffline(sale);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  String _toInput(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString().replaceAll('.', ',');
  }

  Future<void> _updateLocalStock() async {
    final db = AppDatabase.instance;
    for (final item in widget.items) {
      final product = await db.products.getProductById(item.productId);
      if (product != null) {
        await db.products.updateStock(
            item.productId, product.stock - item.quantity);
      }
    }
  }

  Future<void> _applyLocalStockSubtraction() async {
    final db = AppDatabase.instance;
    for (final item in widget.items) {
      final product = await db.products.getProductById(item.productId);
      if (product != null) {
        await db.products.updateStock(
            item.productId, product.stock - item.quantity);
      }
    }
  }

  void _showSuccess(Sale sale) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => _SuccessPage(
          sale: sale,
          isOffline: false,
          header: 'Transaksi Berhasil',
        ),
      ),
    );
  }

  void _showSuccessOffline(Sale sale) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => _SuccessPage(
          sale: sale,
          isOffline: true,
          header: 'Transaksi Tersimpan (Offline)',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pembayaran')),
      body: _processing
          ? const LoadingView(message: 'Memproses transaksi...')
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Item',
                      style: _sectionTitle()),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          for (final item in widget.items)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${item.productName}\n${Formatters.quantity(item.quantity)} ${item.unit} x ${Formatters.currency(item.unitPrice)}',
                                      style: const TextStyle(
                                          fontSize: 12, color: AppColors.textSecondary),
                                    ),
                                  ),
                                  Text(Formatters.currency(item.subtotal),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          const Divider(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Subtotal',
                                  style: TextStyle(color: AppColors.textSecondary)),
                              Text(Formatters.currency(_subtotal)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Diskon', style: _sectionTitle()),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _discountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Diskon (opsional)', prefixText: 'Rp '),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  Text('Metode Pembayaran', style: _sectionTitle()),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final m in ['CASH', 'TRANSFER', 'QRIS'])
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: _MethodChip(
                              method: m,
                              selected: _method == m,
                              onTap: () => setState(() => _method = m),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (_method == 'CASH') ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _cashCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Uang Diterima', prefixText: 'Rp '),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _QuickCash(
                          label: 'Uang Pas',
                          onTap: () => setState(
                              () => _cashCtrl.text = _toInput(_total)),
                        ),
                        for (final a in [50000.0, 100000.0, 200000.0])
                          _QuickCash(
                            label: Formatters.quantity(a),
                            onTap: () =>
                                setState(() => _cashCtrl.text = _toInput(a)),
                          ),
                      ],
                    ),
                    if (_cashCtrl.text.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 16),
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _change < 0
                              ? AppColors.danger.withValues(alpha: 0.08)
                              : AppColors.success.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _change < 0
                                ? AppColors.danger
                                : AppColors.success,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              _change < 0 ? 'UANG KURANG' : 'KEMBALIAN',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              Formatters.currency(_change < 0 ? _change.abs() : _change),
                              style: TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.bold,
                                color: _change < 0
                                    ? AppColors.danger
                                    : AppColors.success,
                              ),
                            ),
                            if (_change > 0)
                              Text('Dibayar ${Formatters.currency(double.parse(_cashCtrl.text.replaceAll(',', '.')))}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                  ],
                  const SizedBox(height: 24),
                  Card(
                    color: AppColors.primary,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Subtotal',
                                  style: TextStyle(color: Colors.white70)),
                              Text(Formatters.currency(_subtotal),
                                  style:
                                      const TextStyle(color: Colors.white70)),
                            ],
                          ),
                          if (_discount > 0)
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Diskon',
                                    style: TextStyle(color: Colors.white70)),
                                Text('− ${Formatters.currency(_discount)}',
                                    style: const TextStyle(
                                        color: Colors.white70)),
                              ],
                            ),
                          const Divider(color: Colors.white24, height: 20),
                          const Text('TOTAL BAYAR',
                              style:
                                  TextStyle(color: Colors.white70, fontSize: 13)),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(Formatters.currency(_total),
                                style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _processing ? null : _processPayment,
                    child: Text('KONFIRMASI PEMBAYARAN ${_method}'),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }

  TextStyle _sectionTitle() => const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
      );
}

class _MethodChip extends StatelessWidget {
  final String method;
  final bool selected;
  final VoidCallback onTap;

  const _MethodChip({
    required this.method,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = selected
        ? AppColors.primary
        : AppColors.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLight.withOpacity(0.15) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? AppColors.primary : const Color(0xFFCFD8DC)),
        ),
        child: Center(
          child: Text(method,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 12, color: colors)),
        ),
      ),
    );
  }
}

class _QuickCash extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickCash({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primaryLight.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
        ),
        child: Text('Rp $label',
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: AppColors.primary)),
      ),
    );
  }
}

class _SuccessPage extends StatelessWidget {
  final Sale sale;
  final bool isOffline;
  final String header;
  const _SuccessPage({
    required this.sale,
    required this.isOffline,
    required this.header,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryDark,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isOffline ? Icons.cloud_off : Icons.check_circle,
                  color: Colors.white,
                  size: 80,
                ),
                const SizedBox(height: 16),
                Text(header,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  'No. ${sale.transactionNumber}',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      const Text('Total Pembayaran',
                          style: TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      Text(Formatters.currency(sale.totalAmount),
                          style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary)),
                      if (sale.payment != null &&
                          sale.payment!.changeAmount != null) ...[
                        const SizedBox(height: 8),
                        Text('Kembalian ${Formatters.currency(sale.payment!.changeAmount!)}',
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.success)),
                      ],
                      if (isOffline) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Transaksi disimpan di perangkat dan akan dikirim otomatis saat koneksi kembali.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary),
                  onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
                  child: const Text('SELESAI'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}