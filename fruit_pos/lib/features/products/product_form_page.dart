import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../api/api_service.dart';
import '../../api/api_exception.dart';
import '../../core/constants.dart';
import '../../core/product_art.dart';
import '../../core/theme.dart';
import '../../database/app_database.dart';
import '../../models/category.dart';
import '../../models/product.dart';
import '../../shared/widgets/common_widgets.dart';
import '../../shared/widgets/product_photo.dart';

class ProductFormPage extends StatefulWidget {
  final Product? product;
  const ProductFormPage({super.key, this.product});

  @override
  State<ProductFormPage> createState() => _ProductFormPageState();
}

class _ProductFormPageState extends State<ProductFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _modalCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  final _minStockCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  Uint8List? _newPhotoBytes;
  String _newPhotoName = 'photo.jpg';
  String? _photoUrl;

  String _unit = 'kg';
  String? _categoryId;
  bool _isActive = true;
  bool _loading = false;
  List<Category> _categories = [];
  bool _addingCategory = false;
  final _newCatCtrl = TextEditingController();

  bool get _isEdit => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    if (p != null) {
      _nameCtrl.text = p.name;
      _modalCtrl.text = p.modalPrice == 0 ? '' : p.modalPrice.toString();
      _priceCtrl.text = p.sellingPrice == 0 ? '' : p.sellingPrice.toString();
      _stockCtrl.text = p.stock == 0 ? '' : p.stock.toString();
      _minStockCtrl.text = p.minStock == 0 ? '' : p.minStock.toString();
      _descCtrl.text = p.description ?? '';
      _unit = p.unit;
      _categoryId = p.categoryId;
      _isActive = p.isActive;
      _photoUrl = p.photoUrl;
    }
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final api = context.read<ApiService>();
      _categories = await api.fetchCategories();
    } catch (e) {
      try {
        final db = AppDatabase.instance;
        _categories = await db.products.getAllCategories();
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _modalCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _minStockCtrl.dispose();
    _descCtrl.dispose();
    _newCatCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 82,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (mounted) {
        setState(() {
          _newPhotoBytes = bytes;
          _newPhotoName = picked.name;
        });
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal membaca foto dari galeri')),
        );
    }
  }

  Future<void> _removePhoto() async {
    if (widget.product == null || _photoUrl == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Hapus Foto?'),
            content: const Text('Foto produk akan dihapus dari server.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Hapus'),
              ),
            ],
          ),
    );
    if (confirm != true) return;
    setState(() => _loading = true);
    try {
      final api = context.read<ApiService>();
      await api.deleteProductPhoto(widget.product!.id);
      if (mounted) setState(() => _photoUrl = null);
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Gagal menghapus foto')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _photoPreview(Product product, double size) {
    if (_newPhotoBytes != null) {
      return ClipOval(
        child: Image.memory(
          _newPhotoBytes!,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }
    if (_photoUrl != null && _photoUrl!.isNotEmpty) {
      return ProductPhoto(product: product, size: size);
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: ProductArt.background(product.name),
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.primaryLight.withOpacity(0.4)),
      ),
      alignment: Alignment.center,
      child: Text(
        ProductArt.emoji(product.name),
        style: TextStyle(fontSize: size * 0.45),
      ),
    );
  }

  Product _withPhoto() {
    final p = widget.product!;
    return Product(
      id: p.id,
      name: p.name,
      categoryId: p.categoryId,
      categoryName: p.categoryName,
      unit: p.unit,
      modalPrice: p.modalPrice,
      sellingPrice: p.sellingPrice,
      stock: p.stock,
      minStock: p.minStock,
      isActive: p.isActive,
      description: p.description,
      photoUrl: _photoUrl,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final body = {
      'name': _nameCtrl.text.trim(),
      'category_id': _categoryId,
      'unit': _unit,
      'modal_price': double.tryParse(_modalCtrl.text.replaceAll(',', '.')) ?? 0,
      'selling_price':
          double.tryParse(_priceCtrl.text.replaceAll(',', '.')) ?? 0,
      'min_stock':
          double.tryParse(_minStockCtrl.text.replaceAll(',', '.')) ?? 0,
      'is_active': _isActive,
      'description': _descCtrl.text.trim(),
    };

    try {
      final api = context.read<ApiService>();
      String productId;
      if (_isEdit) {
        await api.updateProduct(widget.product!.id, body);
        productId = widget.product!.id;
      } else {
        body['stock'] =
            double.tryParse(_stockCtrl.text.replaceAll(',', '.')) ?? 0;
        final created = await api.createProduct(body);
        productId = created['id']?.toString() ?? '';
      }

      if (_newPhotoBytes != null && productId.isNotEmpty) {
        await api.uploadProductPhoto(productId, _newPhotoBytes!, _newPhotoName);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEdit ? 'Produk diperbarui' : 'Produk dibuat'),
          ),
        );
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _loading = false);
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal menyimpan: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit Produk' : 'Tambah Produk')),
      body:
          _loading
              ? const LoadingView(message: 'Menyimpan...')
              : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nama Produk',
                          prefixIcon: Icon(Icons.apple),
                        ),
                        validator:
                            (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? 'Nama wajib diisi'
                                    : null,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _isEdit
                              ? _photoPreview(_withPhoto(), 72)
                              : _photoPreview(
                                Product(
                                  id: '',
                                  name:
                                      _nameCtrl.text.trim().isEmpty
                                          ? '?'
                                          : _nameCtrl.text.trim(),
                                  unit: _unit,
                                  modalPrice: 0,
                                  sellingPrice: 0,
                                  stock: 0,
                                  minStock: 0,
                                  isActive: true,
                                ),
                                72,
                              ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _loading ? null : _pickPhoto,
                                  icon: const Icon(
                                    Icons.photo_camera,
                                    size: 18,
                                  ),
                                  label: Text(
                                    _newPhotoBytes != null
                                        ? 'Ganti Foto'
                                        : 'Pilih Foto Produk',
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.primary,
                                    side: const BorderSide(
                                      color: AppColors.primary,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
if (_isEdit && _photoUrl != null) ...[
                                  const SizedBox(height: 6),
                                  TextButton.icon(
                                    onPressed:
                                        _loading ? null : _removePhoto,
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                    ),
                                    label: const Text('Hapus Foto'),
                                    style: TextButton.styleFrom(
                                      foregroundColor:
                                          AppColors.textSecondary,
                                      padding: EdgeInsets.zero,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _categories.any(
                                      (c) => c.id == _categoryId)
                                  ? _categoryId
                                  : null,
                              decoration: const InputDecoration(
                                labelText: 'Kategori',
                                prefixIcon: Icon(Icons.category),
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('-'),
                                ),
                                ..._categories.map(
                                  (c) => DropdownMenuItem(
                                    value: c.id,
                                    child: Text(c.name),
                                  ),
                                ),
                              ],
                              onChanged: (v) => setState(() => _categoryId = v),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed:
                                _addingCategory
                                    ? null
                                    : () => _showAddCategoryDialog(),
                            icon: const Icon(
                              Icons.add_circle,
                              color: AppColors.primary,
                            ),
                            tooltip: 'Tambah kategori baru',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _unit,
                        decoration: const InputDecoration(
                          labelText: 'Satuan',
                          prefixIcon: Icon(Icons.scale),
                        ),
                        items:
                            AppConstants.units
                                .map(
                                  (u) => DropdownMenuItem(
                                    value: u,
                                    child: Text(u),
                                  ),
                                )
                                .toList(),
                        onChanged: (v) => setState(() => _unit = v ?? 'kg'),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _modalCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Harga Modal',
                                prefixText: 'Rp ',
                              ),
                              validator:
                                  (v) =>
                                      (v == null || v.isEmpty)
                                          ? 'Wajib diisi'
                                          : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _priceCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Harga Jual',
                                prefixText: 'Rp ',
                              ),
                              validator:
                                  (v) =>
                                      (v == null || v.isEmpty)
                                          ? 'Wajib diisi'
                                          : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _stockCtrl,
                              readOnly: _isEdit,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: 'Stok Awal',
                                prefixIcon: const Icon(Icons.inventory),
                                helperText:
                                    _isEdit
                                        ? 'Gunakan stok in / adjustment'
                                        : null,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _minStockCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Batas Min Stok',
                                prefixIcon: Icon(Icons.warning_amber),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _descCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Keterangan (opsional)',
                        ),
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: const Text('Produk aktif'),
                        subtitle: const Text(
                          'Produk nonaktif tidak dapat dijual',
                        ),
                        value: _isActive,
                        activeColor: AppColors.primary,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) => setState(() => _isActive = v),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: _loading ? null : _save,
            child: Text(_isEdit ? 'SIMPAN PERUBAHAN' : 'SIMPAN PRODUK'),
          ),
        ),
      ),
    );
  }

  Future<void> _showAddCategoryDialog() async {
    final result = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Tambah Kategori'),
            content: TextField(
              controller: _newCatCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nama kategori',
                hintText: 'misal: Apel, Jeruk...',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, _newCatCtrl.text.trim()),
                child: const Text('Simpan'),
              ),
            ],
          ),
    );
    if (result != null && result.isNotEmpty) {
      setState(() => _addingCategory = true);
      try {
        final api = context.read<ApiService>();
        final res = await api.createCategory({'name': result});
        _categories.add(Category.fromJson(res));
        _categoryId = res['id']?.toString();
        _newCatCtrl.clear();
        if (mounted) setState(() {});
      } on ApiException catch (e) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.message)));
      } finally {
        if (mounted) setState(() => _addingCategory = false);
      }
    }
  }
}
