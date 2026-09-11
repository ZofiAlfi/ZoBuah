class SyncEntry {
  final int? id;
  final String entityType;
  final String entityId;
  final String data;
  final String status;
  final String createdAt;
  final int retryCount;

  SyncEntry({
    this.id,
    required this.entityType,
    required this.entityId,
    required this.data,
    this.status = 'PENDING',
    required this.createdAt,
    this.retryCount = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'entity_type': entityType,
        'entity_id': entityId,
        'data': data,
        'status': status,
        'created_at': createdAt,
        'retry_count': retryCount,
      };

  factory SyncEntry.fromMap(Map<String, dynamic> map) => SyncEntry(
        id: map['id'],
        entityType: map['entity_type'] as String,
        entityId: map['entity_id'] as String,
        data: map['data'] as String,
        status: map['status'] as String,
        createdAt: map['created_at'] as String,
        retryCount: map['retry_count'] as int? ?? 0,
      );
}