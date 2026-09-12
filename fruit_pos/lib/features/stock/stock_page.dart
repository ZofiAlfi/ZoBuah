import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_service.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/product.dart';
import '../../models/stock_movement.dart';
import '../../shared/widgets/common_widgets.dart';

class StockPage extends StatefulWidget {
  const StockPage({super.key});

  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  bool _loading = true;
  String? _error;
  List<Product> _products = [];
  String _search = '';
  String _view = 'stock'; // 'stock' | 'movements'

  @override
  void initState() {
    super.initState();
    _loadStock();
  }

  Future<void> _loadStock() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<ApiService>();
      _products = await api.fetchStock(_search);
    } catch (e) {
      setState(() => _error = 'Gagal memuat stok: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMovements() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<ApiService>();
      // This fetches all products for stock overview; movements are loaded separately
      _products = await api.fetchStock('');
    } catch (e) {
      setState(() => _error = 'Gagal memuat data: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Manajemen Stok'),
          bottom: TabBar(
            onTap: (i) {
              setState(() => _view = i == 0 ? 'stock' : 'movements');
              if (i == 0) _loadStock();
            },
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            tabs: const [
              Tab(text: 'Stok Produk'),
              Tab(text: 'Riwayat Pergerakan'),
            ],
          ),
        ),
        body: _loading
            ? const LoadingView()
            : _error != null
                ? ErrorView(message: _error!, onRetry: _view == 'stock' ? _loadStock : _loadMovements)
                : _view == 'stock'
                    ? _buildStockList()
                    : const StockMovementsView(),
        floatingActionButton: _view == 'stock'
            ? FloatingActionButton.extended(
                onPressed: () => _showStockInDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Stok Masuk'),
              )
            : null,
      ),
    );
  }

  Widget _buildStockList() {
    final filtered = _search.isEmpty
        ? _products
        : _products
            .where((p) => p.name.toLowerCase().contains(_search.toLowerCase()))
            .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            onChanged: (v) {
              _search = v;
              setState(() {});
            },
            decoration: const InputDecoration(
              hintText: 'Cari produk...',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const EmptyView(message: 'Tidak ada data stok')
              : RefreshIndicator(
                  onRefresh: _loadStock,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) => _StockTile(
                      product: filtered[i],
                      onAdjust: () => _showAdjustmentDialog(filtered[i]),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  void _showStockInDialog() {
    Product? selectedProduct;
    final qtyCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Stok Masuk',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              DropdownButtonFormField<Product>(
                decoration: const InputDecoration(labelText: 'Produk'),
                items: _products
                    .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
                    .toList(),
                onChanged: (v) => setSheetState(() => selectedProduct = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Jumlah',
                  hintText: 'Contoh: 50',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Catatan (opsional)',
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  if (selectedProduct == null) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Pilih produk terlebih dahulu')),
                    );
                    return;
                  }
                  final qty = double.tryParse(qtyCtrl.text) ?? 0;
                  if (qty <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Jumlah harus lebih dari 0')),
                    );
                    return;
                  }
                  Navigator.pop(ctx);
                  await _doStockIn(
                      selectedProduct!.id, qty, notesCtrl.text);
                },
                child: const Text('Simpan Stok Masuk'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _doStockIn(
      String productId, double quantity, String notes) async {
    try {
      final api = context.read<ApiService>();
      await api.stockIn({
        'product_id': productId,
        'quantity': quantity,
        'notes': notes.isNotEmpty ? notes : 'Stok masuk',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stok masuk berhasil')),
        );
        _loadStock();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: $e')),
        );
      }
    }
  }

  void _showAdjustmentDialog(Product product) {
    final qtyCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String adjustType = 'add'; // 'add' | 'subtract'

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Penyesuaian Stok: ${product.name}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                  'Stok saat ini: ${Formatters.quantity(product.stock)} ${product.unit}',
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'add', label: Text('Tambah')),
                  ButtonSegment(value: 'subtract', label: Text('Kurang')),
                ],
                selected: {adjustType},
                onSelectionChanged: (s) =>
                    setSheetState(() => adjustType = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Jumlah',
                  hintText: 'Contoh: 5',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Alasan penyesuaian',
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  final qty = double.tryParse(qtyCtrl.text) ?? 0;
                  if (qty <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Jumlah harus lebih dari 0')),
                    );
                    return;
                  }
                  if (notesCtrl.text.trim().isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Alasan wajib diisi')),
                    );
                    return;
                  }
                  Navigator.pop(ctx);
                  final adjustment = adjustType == 'add' ? qty : -qty;
                  await _doAdjustment(product.id, adjustment, notesCtrl.text);
                },
                child: const Text('Simpan Penyesuaian'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _doAdjustment(
      String productId, double quantity, String notes) async {
    try {
      final api = context.read<ApiService>();
      await api.stockAdjustment({
        'product_id': productId,
        'quantity': quantity,
        'notes': notes,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Penyesuaian stok berhasil')),
        );
        _loadStock();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: $e')),
        );
      }
    }
  }
}

class _StockTile extends StatelessWidget {
  final Product product;
  final VoidCallback onAdjust;
  const _StockTile({required this.product, required this.onAdjust});

  @override
  Widget build(BuildContext context) {
    final isLow = product.isLowStock;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(product.name,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Flexible(
                  child: Text(
                    'Stok: ${Formatters.quantity(product.stock)} ${product.unit}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isLow ? AppColors.danger : AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    'Min: ${Formatters.quantity(product.minStock)} ${product.unit}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLow)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: StatusBadge(status: 'Stok Menipis'),
              ),
            IconButton(
              icon: const Icon(Icons.tune, size: 20),
              tooltip: 'Penyesuaian',
              onPressed: onAdjust,
            ),
          ],
        ),
      ),
    );
  }
}

class StockMovementsView extends StatefulWidget {
  const StockMovementsView({super.key});

  @override
  State<StockMovementsView> createState() => _StockMovementsViewState();
}

class _StockMovementsViewState extends State<StockMovementsView> {
  bool _loading = true;
  List<StockMovement> _movements = [];
  String? _error;
  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';
  String _type = '';

  static const List<({String value, String label})> _typeFilters = [
    (value: '', label: 'Semua'),
    (value: 'STOCK_IN', label: 'Stok Masuk'),
    (value: 'SALE', label: 'Terjual'),
    (value: 'DAMAGE', label: 'Rusak'),
    (value: 'ADJUSTMENT', label: 'Penyesuaian'),
    (value: 'RETURN', label: 'Retur'),
  ];

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

  List<StockMovement> get _filtered {
    final q = _search.trim().toLowerCase();
    return _movements.where((m) {
      if (_type.isNotEmpty && m.movementType != _type) return false;
      if (q.isEmpty) return true;
      final hay = [
        m.productName ?? '',
        m.productId,
        m.movementType,
        m.notes ?? '',
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<ApiService>();
      _movements = await api.fetchStockMovements();
    } catch (e) {
      setState(() => _error = 'Gagal memuat riwayat: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);

    final list = _filtered;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _search = v),
            decoration: const InputDecoration(
              hintText: 'Cari produk, jenis, catatan...',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (final f in _typeFilters)
                  _FilterChip(
                    label: f.label,
                    selected: _type == f.value,
                    onTap: () => setState(() => _type = f.value),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? EmptyView(
                  message: _movements.isEmpty
                      ? 'Belum ada pergerakan stok'
                      : 'Tidak ada yang cocok',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) =>
                        _MovementTile(movement: list[i]),
                  ),
                ),
        ),
      ],
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

class _MovementTile extends StatelessWidget {
  final StockMovement movement;
  const _MovementTile({required this.movement});

  IconData _iconForType(String type) {
    switch (type) {
      case 'STOCK_IN':
        return Icons.add_circle;
      case 'SALE':
        return Icons.shopping_cart;
      case 'DAMAGE':
        return Icons.warning;
      case 'ADJUSTMENT':
        return Icons.tune;
      case 'RETURN':
        return Icons.undo;
      default:
        return Icons.swap_horiz;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'STOCK_IN':
        return AppColors.success;
      case 'SALE':
        return AppColors.info;
      case 'DAMAGE':
        return AppColors.danger;
      case 'ADJUSTMENT':
        return AppColors.warning;
      case 'RETURN':
        return AppColors.primary;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorForType(movement.movementType);
    final isNegative = movement.movementType == 'SALE' ||
        movement.movementType == 'DAMAGE';

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(_iconForType(movement.movementType), color: color),
        title: Text(
          movement.productName ?? movement.productId,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${movement.movementType} - ${movement.notes ?? "-"}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${isNegative ? "-" : "+"}${Formatters.quantity(movement.quantity)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isNegative ? AppColors.danger : AppColors.success,
              ),
            ),
            Text(
              'Sisa: ${Formatters.quantity(movement.stockAfter)}',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
