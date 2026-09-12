import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../database/app_database.dart';
import '../../models/category.dart';
import '../../models/product.dart';
import '../../shared/widgets/common_widgets.dart';
import 'product_form_page.dart';

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  bool _loading = true;
  String? _error;
  List<Product> _products = [];
  String _search = '';
  List<Category> _categories = [];
  String _category = '';

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
      await _reloadData();
    } catch (e) {
      setState(() => _error = 'Gagal memuat produk: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reloadData() async {
    final db = AppDatabase.instance;
    _products = await db.products.getAllProducts(search: _search);
    _categories = await db.products.getAllCategories();
  }

  List<Product> get _filtered => _products
      .where((p) => _category.isEmpty || p.categoryName == _category)
      .toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kelola Produk')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const ProductFormPage()),
          );
          if (created == true) _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('Tambah Produk'),
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: TextField(
                          onChanged: (v) {
                            _search = v;
                            _reloadData().then((_) {
                              if (mounted) setState(() {});
                            });
                          },
                          decoration: const InputDecoration(
                            hintText: 'Cari produk...',
                            prefixIcon: Icon(Icons.search),
                          ),
                        ),
),
                        if (_categories.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 0, 0),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _FilterChip(
                                    label: 'Semua',
                                    selected: _category.isEmpty,
                                    onTap: () =>
                                        setState(() => _category = ''),
                                  ),
                                  for (final c in _categories)
                                    _FilterChip(
                                      label: c.name,
                                      selected: _category == c.name,
                                      onTap: () => setState(
                                          () => _category = c.name),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        Expanded(
                          child: _filtered.isEmpty
                              ? const EmptyView(message: 'Belum ada produk')
                              : ListView.separated(
                                  padding: const EdgeInsets.all(16),
                                  itemCount: _filtered.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 8),
                                  itemBuilder: (ctx, i) => _ProductTile(
                                    product: _filtered[i],
                                    onTap: () async {
                                      final created =
                                          await Navigator.push<bool>(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) => ProductFormPage(
                                                product: _filtered[i])),
                                      );
                                      if (created == true) _load();
                                    },
                                  ),
                                ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) => onTap(),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  const _ProductTile({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(product.name,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (product.categoryName != null)
              Text(product.categoryName!,
                  style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Row(
              children: [
                Flexible(
                  child: Text('Jual ${Formatters.currency(product.sellingPrice)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.primary)),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                      'Stok ${Formatters.quantity(product.stock)} ${product.unit}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          color: product.isLowStock
                              ? AppColors.danger
                              : AppColors.textSecondary)),
                ),
              ],
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!product.isActive) const StatusBadge(status: 'Nonaktif'),
            if (product.isLowStock) const StatusBadge(status: 'Stok Menipis'),
          ],
        ),
      ),
    );
  }
}