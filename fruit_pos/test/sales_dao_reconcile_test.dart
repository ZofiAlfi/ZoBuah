import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../lib/database/app_database.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // File DB singleton menetap di disk antar run; hapus dulu supaya id test
    // tidak bentrok dengan sisa run sebelumnya.
    await AppDatabase.instance.close();
    await deleteDatabase('fruit_pos.db');
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  test('reconcileWithServer menghapus SYNCED yang tidak diakui server', () async {
    final db = AppDatabase.instance;
    final database = await db.database;

    await database.insert('sales', {
      'id': 'orphan-1',
      'transaction_number': 'TRX-ORPHAN-1',
      'total_amount': 10000,
      'total_modal': 6000,
      'total_profit': 4000,
      'status': 'COMPLETED',
      'sync_status': 'SYNCED',
    });
    await database.insert('sale_items', {
      'sale_id': 'orphan-1',
      'product_id': 'p-1',
      'product_name': 'Apel',
      'unit': 'kg',
      'unit_price': 10000,
      'modal_price': 6000,
      'quantity': 1,
      'subtotal': 10000,
    });
    await database.insert('payments', {
      'sale_id': 'orphan-1',
      'method': 'CASH',
      'amount': 10000,
    });
    await database.insert('sales', {
      'id': 'keep-1',
      'transaction_number': 'TRX-KEEP-1',
      'status': 'COMPLETED',
      'sync_status': 'SYNCED',
    });
    await database.insert('sales', {
      'id': 'pending-1',
      'transaction_number': 'TRX-PENDING-1',
      'status': 'COMPLETED',
      'sync_status': 'PENDING',
    });

    final removed = await db.sales.reconcileWithServer({'keep-1'});

    expect(removed, 1);
    expect(
      await database.query('sales', where: 'id = ?', whereArgs: ['orphan-1']),
      isEmpty,
      reason: 'sales SYNCED yang tidak ada di server harus dihapus',
    );
    expect(
      await database.query('sale_items', where: 'sale_id = ?', whereArgs: ['orphan-1']),
      isEmpty,
      reason: 'sale_items milik sales yang dihapus harus ikut bersih',
    );
    expect(
      await database.query('payments', where: 'sale_id = ?', whereArgs: ['orphan-1']),
      isEmpty,
      reason: 'payments milik sales yang dihapus harus ikut bersih',
    );
    expect(
      await database.query('sales', where: 'id = ?', whereArgs: ['keep-1']),
      isNotEmpty,
      reason: 'sales SYNCED yang masih diakui server tidak boleh hilang',
    );
    expect(
      await database.query('sales', where: 'id = ?', whereArgs: ['pending-1']),
      isNotEmpty,
      reason: 'sales offline PENDING tidak boleh dihapus rekonsiliasi',
    );
  });
}