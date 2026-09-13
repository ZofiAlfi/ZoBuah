import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';

/// Menampilkan foto bukti pembayaran.
/// `image` bisa berisi base64 (offsetline) atau URL/path server
/// (mis. `/uploads/payment/<sale-id>_0.jpg`).
class PaymentProof extends StatelessWidget {
  final String? image;
  final double size;
  final bool circle;

  const PaymentProof({
    super.key,
    this.image,
    this.size = 64,
    this.circle = false,
  });

  @override
  Widget build(BuildContext context) {
    final placeholder = _placeholder();
    if (image == null || image!.isEmpty) return placeholder;

    if (_isUrl(image!)) {
      Widget network = Image.network(
        _absolute(image!),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      );
      return _wrap(network);
    }

    Uint8List? bytes;
    try {
      String b64 = image!;
      if (b64.startsWith('data:image')) {
        b64 = b64.split(',').last;
      }
      bytes = base64Decode(b64);
    } catch (_) {}

    if (bytes == null || bytes.isEmpty) return placeholder;
    return _wrap(Image.memory(
      bytes,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => placeholder,
    ));
  }

  Widget _wrap(Widget child) {
    final rounded = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: child,
    );
    return Container(
      decoration: BoxDecoration(
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        border: Border.all(color: const Color(0xFFCFD8DC)),
      ),
      child: circle ? ClipOval(child: child) : rounded,
    );
  }

  Widget _placeholder() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        color: const Color(0xFFE0E0E0),
        borderRadius: circle ? null : BorderRadius.circular(8),
      ),
      child: Icon(Icons.receipt_long, color: AppColors.textSecondary),
    );
  }

  bool _isUrl(String s) =>
      s.startsWith('http://') || s.startsWith('https://') || s.startsWith('/');

  String _absolute(String s) =>
      s.startsWith('/') ? '${AppConstants.baseUrl}$s' : s;
}