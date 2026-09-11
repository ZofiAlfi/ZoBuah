import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../auth/auth_state.dart';
import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../database/app_database.dart';
import '../../models/damage_report.dart';
import '../../models/product.dart';
import '../../shared/widgets/common_widgets.dart';
import '../../sync/sync_manager.dart';
import '../../api/api_service.dart';

class NewDamageReportPage extends StatefulWidget {
  const NewDamageReportPage({super.key});

  @override
  State<NewDamageReportPage> createState() => _NewDamageReportPageState();
}

class _NewDamageReportPageState extends State<NewDamageReportPage> {
  final _formKey = GlobalKey<FormState>();
  List<Product> _products = [];
  String? _productId;
  final _quantityCtrl = TextEditingController();
  String _unit = 'kg';
  String _baseUnit = 'kg';
  String _reason = 'LAINNYA';
  final _descCtrl = TextEditingController();
  final List<String> _photosBase64 = [];
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _quantityCtrl.addListener(_onQtyChanged);
    _loadProducts();
  }

  void _onQtyChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadProducts() async {
    final db = AppDatabase.instance;
    _products = await db.products.getAllProducts(activeOnly: true);
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _quantityCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 70,
    );
    if (file != null) {
      final bytes = await file.readAsBytes();
      setState(() {
        _photosBase64.add(base64Encode(bytes));
      });
    }
  }

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1200,
      imageQuality: 70,
    );
    if (file != null) {
      final bytes = await file.readAsBytes();
      setState(() {
        _photosBase64.add(base64Encode(bytes));
      });
    }
  }

  Future<void> _submit() async {
    if (_productId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih produk terlebih dahulu')),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    final auth = context.read<AuthState>();
    final db = AppDatabase.instance;
    final syncManager = context.read<SyncManager>();
    final api = context.read<ApiService>();

    final reportId = const Uuid().v4();
    final now = DateTime.now().toIso8601String();

    final report = DamageReport(
      id: reportId,
      productId: _productId!,
      productName: _products.firstWhere((p) => p.id == _productId).name,
      quantity: double.tryParse(_quantityCtrl.text.replaceAll(',', '.')) ?? 0,
      unit: _unit,
      reason: _reason,
      description: _descCtrl.text.trim(),
      status: 'PENDING',
      employeeId: auth.user?.id ?? '',
      employeeName: auth.user?.fullName,
      createdAt: now,
      photos: _photosBase64,
    );

    try {
      // Coba kirim langsung
      final res = await api.createDamageReport(report.toSyncJson());
      final serverReport = DamageReport.fromJson(res);
      await db.damage.insertDamageReport(serverReport);
      await db.damage.markSynced(reportId);
      if (mounted) _showSuccess('Laporan produk rusak terkirim.');
    } catch (e) {
      // Simpan lokal + queue
      await db.damage.insertDamageReport(report);
      await syncManager.enqueueDamage(reportId, report.toSyncJson());
      if (mounted) {
        _showSuccess(
            'Laporan disimpan (offline). Akan dikirim saat tersambung kembali.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSuccess(String msg) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: AppColors.success, size: 48),
        title: const Text('Berhasil'),
        content: Text(msg, textAlign: TextAlign.center),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.popUntil(ctx, (route) => route.isFirst),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Laporkan Produk Rusak')),
      body: _loading
          ? const LoadingView()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      value: _productId,
                      decoration: const InputDecoration(
                          labelText: 'Produk', prefixIcon: Icon(Icons.apple)),
                      items: _products
                          .map((p) => DropdownMenuItem(
                              value: p.id, child: Text(p.name)))
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          _productId = v;
                          final p = _products.cast<Product?>().firstWhere(
                              (e) => e?.id == v,
                              orElse: () => null);
                          if (p != null) {
                            _unit = p.unit;
                            _baseUnit = p.unit;
                          }
                        });
                      },
                      validator: (v) => v == null ? 'Pilih produk' : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _unit,
                      decoration: const InputDecoration(
                          labelText: 'Satuan', prefixIcon: Icon(Icons.scale)),
                      items: AppConstants.units
                          .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                          .toList(),
                      onChanged: (v) => setState(() => _unit = v ?? 'kg'),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _quantityCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Jumlah Rusak',
                        suffixText: _unit,
                        helperText: _unitNote(),
                      ),
                      validator: (v) {
                        final q = double.tryParse((v ?? '').replaceAll(',', '.'));
                        if (q == null || q <= 0) return 'Jumlah tidak valid';
                        return null;
                      },
                    ),
                    if (_productId != null &&
                        _unit.trim().toLowerCase() !=
                            _baseUnit.trim().toLowerCase())
                      _buildUnitWarning()!,
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _reason,
                      decoration: const InputDecoration(
                          labelText: 'Alasan Kerusakan',
                          prefixIcon: Icon(Icons.error_outline)),
                      items: AppConstants.damageReasons
                          .map((r) => DropdownMenuItem(value: r, child: Text(_reasonLabel(r))))
                          .toList(),
                      onChanged: (v) => setState(() => _reason = v ?? 'LAINNYA'),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                          labelText: 'Keterangan (opsional)'),
                    ),
                    const SizedBox(height: 16),
                    Text('Foto Bukti', style: _labelStyle()),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _takePhoto,
                            icon: const Icon(Icons.photo_camera),
                            label: const Text('Ambil Foto'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickPhoto,
                            icon: const Icon(Icons.photo_library),
                            label: const Text('Dari Galeri'),
                          ),
                        ),
                      ],
                    ),
                    if (_photosBase64.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 90,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _photosBase64.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (ctx, i) => Stack(
                            children: [
                              _PhotoThumb(base64: _photosBase64[i]),
                              Positioned(
                                top: 0,
                                right: 0,
                                child: GestureDetector(
                                  onTap: () => setState(
                                      () => _photosBase64.removeAt(i)),
                                  child: const CircleAvatar(
                                    radius: 12,
                                    backgroundColor: AppColors.danger,
                                    child: Icon(Icons.close,
                                        size: 14, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      child: Text(_submitting
                          ? 'MENGIRIM...'
                          : 'KIRIM LAPORAN'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Laporan akan berstatus PENDING dan menunggu persetujuan Bos.',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  TextStyle _labelStyle() => const TextStyle(
      fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary);

  double? _convert(double q) {
    final f = _unit.trim().toLowerCase();
    final t = _baseUnit.trim().toLowerCase();
    if (f == t) return q;
    const mass = {'kg': 1000.0, 'gram': 1.0};
    if (mass.containsKey(f) && mass.containsKey(t)) {
      return q * mass[f]! / mass[t]!;
    }
    const count = {'buah', 'pcs'};
    if (count.contains(f) && count.contains(t)) return q;
    return null;
  }

  String? _unitNote() {
    final q = double.tryParse(_quantityCtrl.text.replaceAll(',', '.'));
    if (q == null || q <= 0) return 'Satuan stok: $_baseUnit';
    final conv = _convert(q);
    if (conv == null) {
      return 'Satuan "$_unit" tidak bisa dikonversi ke $_baseUnit';
    }
    if (_unit.trim().toLowerCase() == _baseUnit.trim().toLowerCase()) {
      return 'Satuan stok: $_baseUnit';
    }
    return 'Setara dengan ${Formatters.quantity(conv)} $_baseUnit (dikonversi otomatis)';
  }

  Widget? _buildUnitWarning() {
    final conv = _convert(
        double.tryParse(_quantityCtrl.text.replaceAll(',', '.')) ?? 0);
    final ok = conv != null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: (ok ? AppColors.info : AppColors.danger).withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              ok ? Icons.info_outline : Icons.warning_amber_rounded,
              size: 18,
              color: ok ? AppColors.primary : AppColors.danger,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                ok
                    ? 'Jumlah akan otomatis dikonversi ke satuan stok ($_baseUnit) saat disetujui.'
                    : 'Pilih satuan yang bisa dikonversi (kg/gram/buah/pcs) atau ubah satuan stok produk.',
                style: TextStyle(
                  fontSize: 12,
                  color: ok ? AppColors.textPrimary : AppColors.danger,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _reasonLabel(String r) {
    switch (r) {
      case 'BUSUK':
        return 'Busuk';
      case 'RUSAK_FISIK':
        return 'Rusak fisik';
      case 'JATUH':
        return 'Jatuh';
      case 'KADALUARSA':
        return 'Kadaluarsa / tidak layak jual';
      case 'SUSUT':
        return 'Susut';
      default:
        return 'Lainnya';
    }
  }
}

class _PhotoThumb extends StatelessWidget {
  final String base64;
  const _PhotoThumb({required this.base64});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.memory(
        base64Decode(base64),
        width: 90,
        height: 90,
        fit: BoxFit.cover,
      ),
    );
  }
}
