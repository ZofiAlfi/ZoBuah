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
        continue;
      }

      // Baris sudah ada. Dua-duanya harus ditulis ulang dari server.
      //
      // Versi sebelumnya hanya menulis kolom `status` dan langsung `continue`
      // kalau status-nya sama. Akibatnya koreksi nominal dari Owner Console
      // tidak pernah sampai ke perangkat: owner mengubah 0,8 kg jadi 0,7 kg,
      // server menulis ulang total_amount dan sale_items-nya, tapi perangkat
      // tetap menampilkan angka lama selamanya. sale_items juga di-insert
      // dengan ConflictAlgorithm.ignore, jadi baris lamanya tidak pernah
      // tergantikan.
      //
      // Yang tetap tidak boleh ditimpa: penjualan lokal yang masih PENDING,
      // karena isinya belum pernah sampai ke server dan akan hilang permanen.
      if (existing.first['sync_status'] == 'PENDING') continue;

      final row = existing.first;
      // `created_at` ikut dibandingkan supaya koreksi jam di server ikut
      // diterima. Transaksi yang dibuat saat offline pernah terkirim dengan jam
      // LOKAL perangkat, lalu dilabeli `Z` oleh server, sehingga tampil meleset
      // 7 jam di Owner Console. Saat server mengirim waktu yang benar, baris
      // lokal harus ditulis ulang juga -- kalau tidak, transact ini selamanya
      // menampilkan tanggal yang salah di perangkat.
      //
      // Bandingkan sebagai string: kedua sisi memakai format ISO yang sama
      // (6 digit pecahan + suffix Z), jadi ini tidak memicu penulisan ulang
      // berulang pada tiap pull.
      final waktuBerbeda = row['created_at'] != sale.createdAt;
      final nominalBerbeda =
          _numTidek(row['total_amount']) != _numTidek(sale.totalAmount) ||
              _numTidek(row['total_modal']) != _numTidek(sale.totalModal) ||
              _numTidek(row['total_profit']) != _numTidek(sale.totalProfit) ||
              _numTidek(row['discount']) != _numTidek(sale.discount) ||
              row['status'] != sale.status ||
              row['transaction_number'] != sale.transactionNumber ||
              row['employee_name'] != sale.employeeName;
      if (!nominalBerbeda && !waktuBerbeda) continue;

      await database.update(
        'sales',
        {
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
        },
        where: 'id = ?',
        whereArgs: [sale.id],
      );

      // Baris detail tidak punya primary key dari server, jadi isinya tidak
      // bisa dicocokkan satu per satu. Ganti total: hapus lama, tulis ulang.
      // Kalau tidak, item yang dikoreksi owner dan item yang dihapus owner
      // sama-sama tetap muncul di perangkat.
      await database.delete('sale_items',
          where: 'sale_id = ?', whereArgs: [sale.id]);
      await database.delete('payments',
          where: 'sale_id = ?', whereArgs: [sale.id]);
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
  }

  /// Bandingkan angka dengan toleransi pembulatan, karena SQLite menyimpan
  /// REAL dan 12600.0 bisa tersimpan sebagai 12600.0000001.
  static double _numTidek(Object? v) {
    if (v == null) return -1;
    if (v is num) return double.parse(v.toStringAsFixed(2));
    return double.tryParse(v.toString()) ?? -1;
  }

  /// Rekonsiliasi riwayat transaksi lokal terhadap daftar id yang diakui
  /// server untuk akun yang sedang login.
  ///
  /// Dipanggil hanya setelah FULL pull (tanpa last_sync) yang TAHU bahwa
  /// payload sales lengkap (server mengirim `sales_complete`). Menghapus
  /// penjualan lokal yang sudah SYNCED tetapi tidak ada lagi di daftar server
  /// -- mis. data UAT diganti total, atau perangkat dipakai berganti akun
  /// karyawan -- sehingga riwayat transaksi di HP tidak menyimpan data toko/
  /// akun lain selamanya. Penjualan yang masih PENDING (offline, belum
  /// terkirim ke server) tidak pernah dihapus.
  ///
  /// Mengembalikan jumlah baris sales yang dihapus.
  Future<int> reconcileWithServer(Set<String> serverSaleIds) async {
    final database = await _db;
    final rows = await database.query(
      'sales',
      columns: ['id'],
      where: 'sync_status = ?',
      whereArgs: ['SYNCED'],
    );
    final orphanIds = rows
        .map((r) => r['id'] as String?)
        .whereType<String>()
        .where((id) => !serverSaleIds.contains(id))
        .toList();
    if (orphanIds.isEmpty) return 0;

    final batch = database.batch();
    for (final id in orphanIds) {
      batch.delete('sale_items', where: 'sale_id = ?', whereArgs: [id]);
      batch.delete('payments', where: 'sale_id = ?', whereArgs: [id]);
      batch.delete('sales', where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
    return orphanIds.length;
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