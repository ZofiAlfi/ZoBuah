class StockMovement {
  final String id;
  final String productId;
  final String? productName;
  final String movementType;
  final double quantity;
  final double stockBefore;
  final double stockAfter;
  final String? referenceId;
  final String? referenceType;
  final String? notes;
  final String userId;
  final String? createdAt;

  StockMovement({
    required this.id,
    required this.productId,
    this.productName,
    required this.movementType,
    required this.quantity,
    required this.stockBefore,
    required this.stockAfter,
    this.referenceId,
    this.referenceType,
    this.notes,
    required this.userId,
    this.createdAt,
  });

  factory StockMovement.fromJson(Map<String, dynamic> json) => StockMovement(
        id: json['id']?.toString() ?? '',
        productId: json['product_id']?.toString() ?? '',
        productName: json['product_name']?.toString(),
        movementType: json['movement_type']?.toString() ?? '',
        quantity: (json['quantity'] ?? 0).toDouble(),
        stockBefore: (json['stock_before'] ?? 0).toDouble(),
        stockAfter: (json['stock_after'] ?? 0).toDouble(),
        referenceId: json['reference_id']?.toString(),
        referenceType: json['reference_type']?.toString(),
        notes: json['notes']?.toString(),
        userId: json['user_id']?.toString() ?? '',
        createdAt: json['created_at']?.toString(),
      );
}