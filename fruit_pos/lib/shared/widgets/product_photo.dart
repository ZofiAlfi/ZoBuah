import 'package:flutter/material.dart';

import '../../core/product_art.dart';
import '../../core/theme.dart';
import '../../models/product.dart';

/// Foto produk: menampilkan foto dari server bila ada,
/// dengan fallback ilustrasi emoji + warna bila belum ada foto.
class ProductPhoto extends StatelessWidget {
  final Product product;
  final double size;
  final EdgeInsets margin;

  const ProductPhoto({
    super.key,
    required this.product,
    this.size = 56,
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
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
        style: TextStyle(fontSize: size * 0.55),
      ),
    );

    if (product.photoUrl == null || product.photoUrl!.isEmpty) {
      return fallback;
    }

    return Container(
      width: size,
      height: size,
      margin: margin,
      child: ClipOval(
        child: Image.network(
          product.photoAbsoluteUrl,
          fit: BoxFit.cover,
          width: size,
          height: size,
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return fallback;
          },
          errorBuilder: (context, error, stack) => fallback,
        ),
      ),
    );
  }
}
