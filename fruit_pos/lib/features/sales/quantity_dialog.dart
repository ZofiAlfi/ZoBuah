import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/product.dart';

class QuantityDialog extends StatefulWidget {
  final Product product;

  const QuantityDialog({super.key, required this.product});

  /// Unit yang bisa pakai angka pecahan (timbang/volume).
  static const Set<String> decimalUnits = {
    'kg',
    'gram',
    'liter',
    'loyang',
    'cup',
  };

  static bool allowsDecimal(String unit) => decimalUnits.contains(unit);

  static Future<double?> show(BuildContext context, Product product) async {
    return showDialog<double>(
      context: context,
      builder: (_) => QuantityDialog(product: product),
    );
  }

  @override
  State<QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<QuantityDialog> {
  late final bool _decimal = QuantityDialog.allowsDecimal(widget.product.unit);
  late final double _max = widget.product.stock;
  late final TextEditingController _ctrl;
  double _qty = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _formatQty(_qty));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _formatQty(double v) {
    if (!_decimal) return v.round().toString();
    if (v == v.roundToDouble()) return v.round().toString();
    return v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(
      RegExp(r'\.$'),
      '',
    );
  }

  double _round2(double v) => (v * 100).roundToDouble() / 100;

  void _setQty(double v) {
    setState(() {
      _qty = _round2(v);
      _error = null;
    });
    _ctrl.text = _formatQty(_qty);
  }

  void _step(double delta) {
    final step = _decimal ? 0.1 : 1.0;
    var v = _qty + delta * step;
    if (v < 0) v = 0;
    _setQty(v);
  }

  void _submit() {
    final raw = double.tryParse(_ctrl.text.replaceAll(',', '.'));
    if (raw == null || !raw.isFinite || raw <= 0) {
      setState(() => _error = 'Isi jumlah yang valid');
      return;
    }
    var v = _round2(raw);
    if (!_decimal) v = v.floorToDouble();
    if (_max > 0 && v > _max) {
      v = _max;
      _setQty(v);
      setState(() => _error = 'Maksimal ${_formatQty(_max)} ${widget.product.unit}');
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final subtotal = _round2(_qty * product.sellingPrice);

    return AlertDialog(
      key: const Key('qty_dialog'),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      title: Text(
        product.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${Formatters.currency(product.sellingPrice)} / ${product.unit}  '
            '•  Stok ${Formatters.quantity(product.stock)} ${product.unit}',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filled(
                key: const Key('qty_minus'),
                onPressed: () => _step(-1),
                icon: const Icon(Icons.remove),
                visualDensity: VisualDensity.compact,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: 110,
                  child: TextField(
                    key: const Key('qty_field'),
                    controller: _ctrl,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: _decimal,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[\d.,]'),
                      ),
                      LengthLimitingTextInputFormatter(8),
                    ],
                    decoration: InputDecoration(
                      isDense: true,
                      errorText: _error,
                      hintText: 'Jumlah',
                    ),
                    onChanged: (v) {
                      final parsed = double.tryParse(
                        v.replaceAll(',', '.'),
                      );
                      if (parsed != null && parsed > 0) {
                        setState(() {
                          _qty = _round2(parsed);
                          _error = null;
                        });
                      }
                    },
                  ),
                ),
              ),
              IconButton.filled(
                key: const Key('qty_plus'),
                onPressed: () => _step(1),
                icon: const Icon(Icons.add),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          if (_decimal) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [0.25, 0.5, 0.75, 1.0].map((v) {
                return ChoiceChip(
                  label: Text(_formatQty(v)),
                  selected: (_qty - v).abs() < 0.001,
                  onSelected: (_) => _setQty(v),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Total',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Text(
                Formatters.currency(subtotal),
                key: const Key('qty_subtotal'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          key: const Key('qty_add'),
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text('Tambah'),
        ),
      ],
    );
  }
}