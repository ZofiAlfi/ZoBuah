import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/damage_report.dart';
import 'app_database.dart';

class DamageDao {
  final AppDatabase db;
  DamageDao(this.db);

  Future<Database> get _db => db.database;

  Future<void> insertDamageReport(DamageReport report) async {
    final database = await _db;
    await database.insert('damage_reports', {
      'id': report.id,
      'product_id': report.productId,
      'product_name': report.productName,
      'quantity': report.quantity,
      'unit': report.unit,
      'reason': report.reason,
      'description': report.description,
      'status': report.status,
      'employee_id': report.employeeId,
      'employee_name': report.employeeName,
      'created_at': report.createdAt,
      'photos': jsonEncode(report.photos),
      'approved_by': report.approvedBy,
      'approved_at': report.approvedAt,
      'rejected_by': report.rejectedBy,
      'rejected_at': report.rejectedAt,
      'rejection_reason': report.rejectionReason,
      'sync_status': 'PENDING',
    });
  }

  Future<void> upsertAll(List<DamageReport> reports) async {
    final database = await _db;
    final batch = database.batch();
    for (final r in reports) {
      batch.insert('damage_reports', {
        'id': r.id,
        'product_id': r.productId,
        'product_name': r.productName,
        'quantity': r.quantity,
        'unit': r.unit,
        'reason': r.reason,
        'description': r.description,
        'status': r.status,
        'employee_id': r.employeeId,
        'employee_name': r.employeeName,
        'created_at': r.createdAt,
        'photos': jsonEncode(r.photos),
        'approved_by': r.approvedBy,
        'approved_at': r.approvedAt,
        'rejected_by': r.rejectedBy,
        'rejected_at': r.rejectedAt,
        'rejection_reason': r.rejectionReason,
        'sync_status': 'SYNCED',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> updateFromServer(DamageReport report) async {
    final database = await _db;
    await database.update('damage_reports', {
      'status': report.status,
      'approved_by': report.approvedBy,
      'approved_at': report.approvedAt,
      'rejected_by': report.rejectedBy,
      'rejected_at': report.rejectedAt,
      'rejection_reason': report.rejectionReason,
      'sync_status': 'SYNCED',
    }, where: 'id = ?', whereArgs: [report.id]);
  }

  Future<List<DamageReport>> getDamageReports({String? status, String? search}) async {
    final database = await _db;
    String where = '';
    List args = [];
    if (status != null && status.isNotEmpty) {
      where = 'status = ?';
      args = [status];
    }
    if (search != null && search.isNotEmpty) {
      where = where.isEmpty ? 'product_name LIKE ?' : '$where AND product_name LIKE ?';
      args.add('%$search%');
    }
    final rows = await database.query('damage_reports',
        where: where.isEmpty ? null : where,
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'created_at DESC');
    return rows.map(_fromRow).toList();
  }

  DamageReport _fromRow(Map<String, dynamic> row) {
    List<String> photos = [];
    try {
      final p = jsonDecode(row['photos'] as String? ?? '[]');
      photos = (p as List).map((e) => e.toString()).toList();
    } catch (_) {}
    return DamageReport(
      id: row['id'],
      productId: row['product_id'],
      productName: row['product_name'],
      quantity: (row['quantity'] as num).toDouble(),
      unit: row['unit'],
      reason: row['reason'],
      description: row['description'],
      status: row['status'],
      employeeId: row['employee_id'],
      employeeName: row['employee_name'],
      createdAt: row['created_at'],
      photos: photos,
      approvedBy: row['approved_by'],
      approvedAt: row['approved_at'],
      rejectedBy: row['rejected_by'],
      rejectedAt: row['rejected_at'],
      rejectionReason: row['rejection_reason'],
    );
  }

  Future<void> markSynced(String reportId) async {
    final database = await _db;
    await database.update('damage_reports', {'sync_status': 'SYNCED'},
        where: 'id = ?', whereArgs: [reportId]);
  }
}