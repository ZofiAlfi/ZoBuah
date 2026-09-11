import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../database/app_database.dart';
import '../../models/product.dart';
import '../../models/sale.dart';
import '../../shared/widgets/common_widgets.dart';
import '../../shared/widgets/product_photo.dart';
import 'payment_page.dart';
import 'quantity_dialog.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({super.key, this.productsLoader, this.embedded = false});

  final Future<List<Product>> Function(String search)? productsLoader;

  /// true = ditanam langsung di halaman cashier (tanpa Scaffold/AppBar sendiri).
  final bool embedded;

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  bool _loading = true;
  List<Product> _products = [];
  final List<SaleItem> _cart = [];
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final loader = widget.productsLoader;
    if (loader != null) {
      _products = await loader(_search);
    } else {
      final db = AppDatabase.instance;
      _products = await db.products.getAllProducts(
        search: _search,
        activeOnly: true,
      );
    }
    if (mounted) setState(() => _loading = false);
  }

  double get _total => _cart.fold(0, (sum, item) => sum + item.subtotal);

  Future<void> _pickQuantity(Product product) async {
    final qty = await QuantityDialog.show(context, product);
    if (qty != null && mounted) _addToCart(product, qty);
  }

  void _addToCart(Product product, [double qty = 1]) {
    final stock = product.stock;
    var addQty = qty > 0 ? qty : 1.0;
    if (stock > 0 && addQty > stock) addQty = stock;
    final existing = _cart.where((e) => e.productId == product.id).firstOrNull;
    if (existing != null) {
      setState(() {
        var newQty = _round2(existing.quantity + addQty);
        if (stock > 0 && newQty > stock) newQty = stock;
        existing.quantity = newQty;
        existing.subtotal = _round2(existing.unitPrice * newQty);
      });
    } else {
      setState(() {
        _cart.add(
          SaleItem(
            productId: product.id,
            productName: product.name,
            unit: product.unit,
            unitPrice: product.sellingPrice,
            modalPrice: product.modalPrice,
            quantity: addQty,
            subtotal: _round2(product.sellingPrice * addQty),
          ),
        );
      });
    }
  }

  double _round2(double v) => (v * 100).roundToDouble() / 100;

  @override
  Widget build(BuildContext context) {
    final body =
        _loading
            ? const LoadingView()
            : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) {
                      _search = v;
                      _load();
                    },
                    decoration: const InputDecoration(
                      hintText: 'Cari produk / scan barcode...',
                      prefixIcon: Icon(Icons.search),
                      suffixIcon: Icon(Icons.qr_code_scanner),
                    ),
                  ),
                ),
                Expanded(
                  flex: 5,
                  child:
                      _products.isEmpty
                          ? const EmptyView(message: 'Produk tidak ditemukan')
                          : GridView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  childAspectRatio: 0.75,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                ),
                            itemCount: _products.length,
                            itemBuilder:
                                (ctx, i) => _ProductButton(
                                  key: ValueKey('prod_${_products[i].id}'),
                                  product: _products[i],
                                  onTap: () => _pickQuantity(_products[i]),
                                ),
                          ),
                ),
                if (_cart.isNotEmpty)
                  _CartSummary(
                    items: _cart,
                    total: _total,
                    onCheckout: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PaymentPage(items: _cart),
                        ),
                      );
                      if (mounted) {
                        setState(() => _cart.clear());
                        _load();
                      }
                    },
                    onClear: () => setState(() => _cart.clear()),
                  ),
              ],
            );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('Kasir Penjualan')),
      body: body,
    );
  }
}

class _ProductButton extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  const _ProductButton({super.key, required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Center(child: ProductPhoto(product: product))),
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  Formatters.currency(product.sellingPrice),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Stok ${Formatters.quantity(product.stock)} ${product.unit}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CartSummary extends StatelessWidget {
  final List<SaleItem> items;
  final double total;
  final VoidCallback onCheckout;
  final VoidCallback onClear;

  const _CartSummary({
    required this.items,
    required this.total,
    required this.onCheckout,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final itemCount = items.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Belanja',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$itemCount item',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: onClear,
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.delete_sweep,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
                tooltip: 'Kosongkan keranjang',
              ),
            ],
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 132),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final it = items[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          it.productName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.textSecondary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${Formatters.quantity(it.quantity)} ${it.unit}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Text(
                        Formatters.currency(it.subtotal),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const Divider(height: 16),
          Row(
            children: [
              const Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Total Harga',
                    maxLines: 1,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const Spacer(),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    Formatters.currency(total),
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            key: const Key('checkout'),
            onPressed: onCheckout,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Checkout'),
          ),
        ],
      ),
    );
  }
}
