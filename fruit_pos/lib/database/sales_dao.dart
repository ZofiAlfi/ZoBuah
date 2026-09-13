import 'package:sqflite/sqflite.dart';

import '../models/sale.dart';
import 'app_database.dart';

class SalesDao {
  final AppDatabase db;
  SalesDao(this.db);

  Future<Database> get _db => db.database;

  Future<void> insertSale(Sale sale) async {
    final database = await _db;
    await database.insert('sales', {
      'id': sale.id,
      'transaction_number': sale.transactionNumber,
      'employee_id': sale.employeeId,
      'employee_name': sale.employeeName,
      'total_amount': sale.totalAmount,
      'total_modal': sale.totalModal,
      'total_profit': sale.totalProfit,
      'discount': sale.discount,
      'status': sale.status,
      'created_at': sale.createdAt,
      'sync_status': 'PENDING',
    });

    for (final item in sale.items) {
      await database.insert('sale_items', {
        'sale_id': sale.id,
        'product_id': item.productId,
        'product_name': item.productName,
        'unit': item.unit,
        'unit_price': item.unitPrice,
        'modal_price': item.modalPrice,
        'quantity': item.quantity,
        'subtotal': item.subtotal,
      });
    }

    if (sale.payment != null) {
      await database.insert('payments', {
        'sale_id': sale.id,
        'method': sale.payment!.method,
        'amount': sale.payment!.amount,
        'cash_received': sale.payment!.cashReceived,
        'change_amount': sale.payment!.changeAmount,
        'reference': sale.payment!.reference,
        'photo': sale.payment!.photo ?? sale.payment!.photoUrl,
      });
    }
  }

  Future<void> markSynced(String saleId) async {
    final database = await _db;
    await database.update('sales', {'sync_status': 'SYNCED'},
        where: 'id = ?', whereArgs: [saleId]);
  }

  Future<List<Map<String, dynamic>>> getPendingSales() async {
    final database = await _db;
    return database.query('sales', where: "sync_status != 'SYNCED'");
  }

  Future<List<Sale>> getSales({int limit = 50}) async {
    final database = await _db;
    final rows = await database.query('sales', orderBy: 'created_at DESC', limit: limit);
    final result = <Sale>[];
    for (final row in rows) {
      final items = await database
          .query('sale_items', where: 'sale_id = ?', whereArgs: [row['id']]);
      final payment = await database
          .query('payments', where: 'sale_id = ?', whereArgs: [row['id']]);
      result.add(_saleFromRow(row, items, payment));
    }
    return result;
  }

  Future<void> upsertFromServer(List<Sale> sales) async {
    final database = await _db;
    for (final sale in sales) {
      if (sale.id == null) continue;
      final existing = await database.query('sales',
          where: 'id = ?', whereArgs: [sale.id]);
      if (existing.isEmpty) {
        // Don't overwrite local pending sales; only insert server sales not present locally
        await database.insert('sales', {
          'id': sale.id,
          'transaction_number': sale.transactionNumber,
          'employee_id': sale.employeeId,
          'employee_name': sale.employeeName,
          'total_amount': sale.totalAmount,
          'total_modal': sale.totalModal,
          'total_profit': sale.totalProfit,
          'discount': sale.discount,
          'status': sale.status,
          'created_at': sale.createdAt,
          'sync_status': 'SYNCED',
        }, conflictAlgorithm: ConflictAlgorithm.ignore);

        for (final item in sale.items) {
          await database.insert('sale_items', {
            'sale_id': sale.id,
            'product_id': item.productId,
            'product_name': item.productName,
            'unit': item.unit,
            'unit_price': item.unitPrice,
            'modal_price': item.modalPrice,
            'quantity': item.quantity,
            'subtotal': item.subtotal,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }

        if (sale.payment != null) {
          await database.insert('payments', {
            'sale_id': sale.id,
            'method': sale.payment!.method,
            'amount': sale.payment!.amount,
            'cash_received': sale.payment!.cashReceived,
            'change_amount': sale.payment!.changeAmount,
            'reference': sale.payment!.reference,
            'photo': sale.payment!.photo ?? sale.payment!.photoUrl,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
    }
  }

  Sale _saleFromRow(Map<String, dynamic> row, List<Map<String, dynamic>> items,
      List<Map<String, dynamic>> payments) {
    return Sale(
      id: row['id'],
      transactionNumber: row['transaction_number'],
      employeeId: row['employee_id'],
      employeeName: row['employee_name'],
      totalAmount: (row['total_amount'] as num).toDouble(),
      totalModal: (row['total_modal'] as num).toDouble(),
      totalProfit: (row['total_profit'] as num).toDouble(),
      discount: (row['discount'] as num).toDouble(),
      status: row['status'],
      createdAt: row['created_at'],
      items: items
          .map((i) => SaleItem(
                productId: i['product_id'],
                productName: i['product_name'],
                unit: i['unit'],
                unitPrice: (i['unit_price'] as num).toDouble(),
                modalPrice: (i['modal_price'] as num).toDouble(),
                quantity: (i['quantity'] as num).toDouble(),
                subtotal: (i['subtotal'] as num).toDouble(),
              ))
          .toList(),
      payment: payments.isEmpty
          ? null
          : Payment(
              method: payments.first['method'],
              amount: (payments.first['amount'] as num).toDouble(),
              cashReceived: payments.first['cash_received']?.toDouble(),
              changeAmount: payments.first['change_amount']?.toDouble(),
              reference: payments.first['reference'],
              photo: payments.first['photo']?.toString(),
            ),
    );
  }
}