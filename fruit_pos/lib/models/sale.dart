class SaleItem {
  final String? id;
  final String productId;
  final String productName;
  final String unit;
  final double unitPrice;
  final double modalPrice;
  double quantity;
  double subtotal;

  SaleItem({
    this.id,
    required this.productId,
    required this.productName,
    required this.unit,
    required this.unitPrice,
    required this.modalPrice,
    required this.quantity,
    required this.subtotal,
  });

  factory SaleItem.fromJson(Map<String, dynamic> json) => SaleItem(
        id: json['id']?.toString(),
        productId: json['product_id']?.toString() ?? '',
        productName: json['product_name']?.toString() ?? '',
        unit: json['unit']?.toString() ?? 'kg',
        unitPrice: (json['unit_price'] ?? 0).toDouble(),
        modalPrice: (json['modal_price'] ?? 0).toDouble(),
        quantity: (json['quantity'] ?? 0).toDouble(),
        subtotal: (json['subtotal'] ?? 0).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'product_name': productName,
        'unit': unit,
        'unit_price': unitPrice,
        'modal_price': modalPrice,
        'quantity': quantity,
        'subtotal': subtotal,
      };
}

class Payment {
  final String method;
  final double amount;
  final double? cashReceived;
  final double? changeAmount;
  final String? reference;
  final String? photo;
  final String? photoUrl;

  Payment({
    required this.method,
    required this.amount,
    this.cashReceived,
    this.changeAmount,
    this.reference,
    this.photo,
    this.photoUrl,
  });

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
        method: json['method']?.toString() ?? 'CASH',
        amount: (json['amount'] ?? 0).toDouble(),
        cashReceived: json['cash_received']?.toDouble(),
        changeAmount: json['change_amount']?.toDouble(),
        reference: json['reference']?.toString(),
        photo: json['photo']?.toString(),
        photoUrl: json['file_url']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'method': method,
        'amount': amount,
        'cash_received': cashReceived,
        'change_amount': changeAmount,
        'reference': reference,
        'photo': photo,
      };
}

class Sale {
  final String? id;
  final String transactionNumber;
  final String employeeId;
  final String? employeeName;
  final double totalAmount;
  final double totalModal;
  final double totalProfit;
  final double discount;
  final String status;
  final String? createdAt;
  final List<SaleItem> items;
  final Payment? payment;

  Sale({
    this.id,
    required this.transactionNumber,
    required this.employeeId,
    this.employeeName,
    required this.totalAmount,
    required this.totalModal,
    required this.totalProfit,
    this.discount = 0,
    this.status = 'COMPLETED',
    this.createdAt,
    this.items = const [],
    this.payment,
  });

  factory Sale.fromJson(Map<String, dynamic> json) => Sale(
        id: json['id']?.toString(),
        transactionNumber: json['transaction_number']?.toString() ?? '',
        employeeId: json['employee_id']?.toString() ?? '',
        employeeName: json['employee_name']?.toString(),
        totalAmount: (json['total_amount'] ?? 0).toDouble(),
        totalModal: (json['total_modal'] ?? 0).toDouble(),
        totalProfit: (json['total_profit'] ?? 0).toDouble(),
        discount: (json['discount'] ?? 0).toDouble(),
        status: json['status']?.toString() ?? 'COMPLETED',
        createdAt: json['created_at']?.toString(),
        items: (json['items'] as List? ?? [])
            .map((e) => SaleItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        payment: json['payment'] == null
            ? null
            : Payment.fromJson(json['payment'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toSyncJson() => {
        'id': id,
        'transaction_number': transactionNumber,
        'employee_id': employeeId,
        'total_amount': totalAmount,
        'total_modal': totalModal,
        'total_profit': totalProfit,
        'discount': discount,
        'status': status,
        'created_at': createdAt,
        'items': items.map((e) => e.toJson()).toList(),
        'payment': payment?.toJson(),
      };
}