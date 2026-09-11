class DamageReport {
  final String? id;
  final String productId;
  final String? productName;
  final double quantity;
  final String unit;
  final String reason;
  final String? description;
  final String status;
  final String employeeId;
  final String? employeeName;
  final String? approvedBy;
  final String? approvedAt;
  final String? rejectedBy;
  final String? rejectedAt;
  final String? rejectionReason;
  final String? createdAt;
  final List<String> photos;

  DamageReport({
    this.id,
    required this.productId,
    this.productName,
    required this.quantity,
    required this.unit,
    required this.reason,
    this.description,
    this.status = 'PENDING',
    required this.employeeId,
    this.employeeName,
    this.approvedBy,
    this.approvedAt,
    this.rejectedBy,
    this.rejectedAt,
    this.rejectionReason,
    this.createdAt,
    this.photos = const [],
  });

  bool get isPending => status == 'PENDING';
  bool get isApproved => status == 'APPROVED';
  bool get isRejected => status == 'REJECTED';

  factory DamageReport.fromJson(Map<String, dynamic> json) => DamageReport(
        id: json['id']?.toString(),
        productId: json['product_id']?.toString() ?? '',
        productName: json['product_name']?.toString(),
        quantity: (json['quantity'] ?? 0).toDouble(),
        unit: json['unit']?.toString() ?? 'kg',
        reason: json['reason']?.toString() ?? 'LAINNYA',
        description: json['description']?.toString(),
        status: json['status']?.toString() ?? 'PENDING',
        employeeId: json['employee_id']?.toString() ?? '',
        employeeName: json['employee_name']?.toString(),
        approvedBy: json['approved_by']?.toString(),
        approvedAt: json['approved_at']?.toString(),
        rejectedBy: json['rejected_by']?.toString(),
        rejectedAt: json['rejected_at']?.toString(),
        rejectionReason: json['rejection_reason']?.toString(),
        createdAt: json['created_at']?.toString(),
        photos: (json['photos'] as List? ?? [])
            .map((e) =>
                e is Map
                    ? (e['file_url']?.toString() ?? e['file_path']?.toString() ?? '')
                    : e.toString())
            .where((s) => s.isNotEmpty)
            .toList(),
      );

  Map<String, dynamic> toSyncJson() => {
        'id': id,
        'product_id': productId,
        'quantity': quantity,
        'unit': unit,
        'reason': reason,
        'description': description,
        'status': status,
        'employee_id': employeeId,
        'created_at': createdAt,
        'photos': photos,
      };
}