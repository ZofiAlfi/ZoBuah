import '../core/constants.dart';

class Product {
  final String id;
  final String name;
  final String? categoryId;
  final String? categoryName;
  final String unit;
  final double modalPrice;
  final double sellingPrice;
  final double stock;
  final double minStock;
  final bool isActive;
  final String? description;
  final String? photoUrl;

  Product({
    required this.id,
    required this.name,
    this.categoryId,
    this.categoryName,
    required this.unit,
    required this.modalPrice,
    required this.sellingPrice,
    required this.stock,
    required this.minStock,
    required this.isActive,
    this.description,
    this.photoUrl,
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    categoryId: json['category_id']?.toString(),
    categoryName: json['category_name']?.toString(),
    unit: json['unit']?.toString() ?? 'kg',
    modalPrice: (json['modal_price'] ?? 0).toDouble(),
    sellingPrice: (json['selling_price'] ?? 0).toDouble(),
    stock: (json['stock'] ?? 0).toDouble(),
    minStock: (json['min_stock'] ?? 0).toDouble(),
    isActive: json['is_active'] ?? true,
    description: json['description']?.toString(),
    photoUrl: json['photo_url']?.toString(),
  );

  bool get isLowStock => stock <= minStock && isActive;

  /// Konversi ke URL absolut. Backend bisa mengirim path relatif
  /// (`/uploads/...`, mode local) atau URL absolut (Backblaze B2 / S3).
  String get photoAbsoluteUrl {
    final u = photoUrl ?? '';
    if (u.isEmpty) return '';
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    return '${AppConstants.baseUrl}$u';
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'category_id': categoryId,
    'category_name': categoryName,
    'unit': unit,
    'modal_price': modalPrice,
    'selling_price': sellingPrice,
    'stock': stock,
    'min_stock': minStock,
    'is_active': isActive ? 1 : 0,
    'description': description,
    'photo_url': photoUrl,
  };
}
